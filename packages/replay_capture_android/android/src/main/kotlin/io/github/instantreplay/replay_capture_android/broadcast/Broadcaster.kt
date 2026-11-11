package io.github.instantreplay.replay_capture_android.broadcast

import android.media.MediaCodec
import android.os.Handler
import android.os.HandlerThread
import android.os.SystemClock
import android.util.Log
import android.view.Surface
import com.pedro.common.ConnectChecker
import com.pedro.common.VideoCodec
import com.pedro.rtmp.rtmp.RtmpClient
import io.github.instantreplay.replay_capture_android.BroadcastState
import io.github.instantreplay.replay_capture_android.BroadcastStatus
import io.github.instantreplay.replay_capture_android.CaptureConfig
import java.io.File
import java.nio.ByteBuffer
import java.time.LocalDateTime
import java.time.OffsetDateTime
import java.util.concurrent.ExecutionException
import java.util.concurrent.FutureTask

/**
 * Streams the program (camera + scoreboard) and audio to an RTMP(S) server (SPEC §12.1).
 *
 * One broadcast at a time: [start] creates the program encoder (attached to the GL thread via
 * [attachProgram]), the audio encoder and a RootEncoder [RtmpClient]; [stop] releases them all.
 * A lost connection never stops the encoders: the client retries every 3 s until the user stops,
 * and each (re)connection starts a new RTMP timeline at 0 with a keyframe ([StreamClock]).
 *
 * State changes go through [onStatus] (any thread). All state transitions run on `ir-broadcast`;
 * encoder outputs are forwarded straight from their own threads.
 */
internal class Broadcaster(
    private val config: CaptureConfig,
    private val logDir: File?,
    /** True when camera timestamps are CLOCK_BOOTTIME (`SENSOR_INFO_TIMESTAMP_SOURCE_REALTIME`). */
    private val boottimeTimestamps: Boolean,
    private val attachProgram: (Surface?) -> Unit,
    /** Latest engine stats (thermal, battery, camera fps) for the field log. */
    private val deviceStats: () -> Map<String, Any?>,
    private val onStatus: (BroadcastStatus) -> Unit,
) {
    private val thread = HandlerThread("ir-broadcast").apply { start() }
    private val handler = Handler(thread.looper)

    private class Session(
        val id: Int,
        val rtmp: RtmpClient,
        val program: ProgramEncoder,
        val audio: AudioEncoder,
        val bitrate: BitrateController,
        val log: FieldLog?,
    )

    // Broadcast-thread state.
    @Volatile private var session: Session? = null
    private var sessionIds = 0
    private var ticks = 0L
    private var lastProgramFrames = 0L

    // Read by encoder threads and status().
    private val clock = StreamClock()
    @Volatile private var connected = false
    @Volatile private var current: Session? = null
    @Volatile private var state = BroadcastState.IDLE
    @Volatile private var message: String? = null
    @Volatile private var targetKbps = 0
    @Volatile private var measuredBps: Long? = null
    @Volatile private var liveSinceMs = -1L
    @Volatile private var programFps: Double? = null
    @Volatile private var droppedFrames = 0L
    @Volatile private var audioActive = false
    /** The current session's mic is open, so it can be unmuted live. */
    @Volatile private var micOpen = false

    /**
     * Mutes or unmutes the microphone on air at once; false when there is no open mic to unmute
     * (no permission, or the stream is off). Any thread.
     */
    fun setMuted(muted: Boolean): Boolean {
        val audio = session?.audio ?: return false
        if (!micOpen) return muted
        audio.muted = muted
        audioActive = !muted
        onStatus(status())
        return true
    }

    private val programFrameRate = minOf(config.fps, 30)

    /**
     * Starts streaming to [url] (replacing a running broadcast). [done] gets the status once
     * connecting has started, or the error if the encoders can't be created.
     */
    /**
     * [useMic]: open the microphone (permission granted); [muted]: start with it silenced. A mic
     * that is open can be muted and unmuted live with [setMuted].
     */
    fun start(url: String, targetKbps: Int, useMic: Boolean, muted: Boolean, done: (Result<BroadcastStatus>) -> Unit) {
        handler.post { done(runCatching { startNow(url, targetKbps, useMic, muted) }) }
    }

    /** Disconnects and releases the encoders, then calls [done]; no-op when idle. */
    fun stop(done: () -> Unit) {
        handler.post {
            stopNow()
            done()
        }
    }

    /** Stops any broadcast (blocking until released) and the thread. */
    fun release() {
        onThread(::stopNow)
        thread.quitSafely()
    }

    private fun startNow(url: String, targetKbps: Int, useMic: Boolean, muted: Boolean): BroadcastStatus {
        session?.let(::teardown)
        state = BroadcastState.IDLE
        val id = ++sessionIds
        this.targetKbps = targetKbps
        message = null
        measuredBps = null
        liveSinceMs = -1L
        programFps = null
        droppedFrames = 0L
        lastProgramFrames = 0L
        ticks = 0L

        val rtmp = RtmpClient(Checker(id))
        var program: ProgramEncoder? = null
        var audio: AudioEncoder? = null
        try {
            program = ProgramEncoder(
                config.width, config.height, programFrameRate, targetKbps * 1000,
                onFormat = { sps, pps -> rtmp.setVideoInfo(sps, pps, null) },
                onFrame = ::sendVideo,
                onError = { reportError(id, it) },
            )
            attachProgram(program.inputSurface)
            audio = AudioEncoder(
                useMic,
                nowNs = if (boottimeTimestamps) SystemClock::elapsedRealtimeNanos else System::nanoTime,
                onFrame = ::sendAudio,
                onError = { reportError(id, it) },
            ).also { it.muted = muted }
            rtmp.setVideoCodec(VideoCodec.H264)
            rtmp.setAudioInfo(AudioEncoder.SAMPLE_RATE, false)
            rtmp.setVideoResolution(config.width, config.height)
            rtmp.setFps(programFrameRate)
            rtmp.setReTries(RETRIES)
        } catch (e: Exception) {
            attachProgram(null)
            program?.release()
            audio?.release()
            throw e
        }
        val log = logDir?.let {
            try {
                FieldLog(FieldLog.fileFor(it, LocalDateTime.now()))
            } catch (e: Exception) {
                Log.w(TAG, "No field log", e)
                null
            }
        }
        val s = Session(id, rtmp, program, audio, BitrateController(targetKbps), log)
        session = s
        current = s
        micOpen = audio.micActive
        audioActive = audio.micActive && !muted
        clock.reset()
        connected = false
        audio.start()
        state = BroadcastState.CONNECTING
        rtmp.connect(url)
        handler.removeCallbacks(tick)
        handler.postDelayed(tick, TICK_MS)
        return status().also(onStatus)
    }

    private fun stopNow() {
        session?.let(::teardown)
        if (state != BroadcastState.IDLE) {
            state = BroadcastState.IDLE
            message = null
            onStatus(status())
        }
    }

    fun status() = BroadcastStatus(
        state = state,
        targetKbps = targetKbps.toLong(),
        bitrateKbps = measuredBps?.takeIf { state == BroadcastState.LIVE }?.let { it / 1000 },
        uptimeMs = liveSinceMs.takeIf { it >= 0 }?.let { SystemClock.elapsedRealtime() - it },
        fps = programFps,
        droppedFrames = droppedFrames,
        audio = audioActive,
        message = message,
    )

    val isActive: Boolean get() = state != BroadcastState.IDLE && state != BroadcastState.FAILED

    // Broadcast thread.
    private fun teardown(s: Session) {
        handler.removeCallbacks(tick)
        connected = false
        current = null
        session = null
        // Detach before releasing, so GL never draws into a released surface.
        attachProgram(null)
        s.program.release()
        s.audio.release()
        try {
            s.rtmp.disconnect()
        } catch (e: Exception) {
            Log.w(TAG, "RTMP disconnect", e)
        }
        measuredBps = null
        programFps = null
    }

    // ir-program thread.
    private val videoInfo = MediaCodec.BufferInfo()

    private fun sendVideo(buffer: ByteBuffer, info: MediaCodec.BufferInfo) {
        val s = current ?: return
        if (!connected) return
        val key = info.flags and MediaCodec.BUFFER_FLAG_KEY_FRAME != 0
        val pts = clock.video(info.presentationTimeUs, key) ?: return
        videoInfo.set(0, info.size, pts, info.flags)
        s.rtmp.sendVideo(buffer, videoInfo)
    }

    // ir-audio thread.
    private val audioInfo = MediaCodec.BufferInfo()

    private fun sendAudio(buffer: ByteBuffer, info: MediaCodec.BufferInfo) {
        val s = current ?: return
        if (!connected) return
        val pts = clock.audio(info.presentationTimeUs) ?: return
        audioInfo.set(0, info.size, pts, info.flags)
        s.rtmp.sendAudio(buffer, audioInfo)
    }

    private val tick = object : Runnable {
        override fun run() {
            val s = session ?: return
            ticks++
            val frames = s.program.frames
            programFps = (frames - lastProgramFrames) * 1000.0 / TICK_MS
            lastProgramFrames = frames
            droppedFrames = s.rtmp.droppedVideoFrames
            if (state == BroadcastState.LIVE) {
                val congested = try {
                    s.rtmp.hasCongestion(CONGESTION_PERCENT)
                } catch (e: IllegalArgumentException) {
                    false
                }
                s.bitrate.onTick(SystemClock.elapsedRealtime(), congested)?.let { kbps ->
                    targetKbps = kbps
                    s.program.setBitrate(kbps * 1000)
                }
            }
            if (ticks % LOG_EVERY_TICKS == 0L) writeLog(s)
            handler.postDelayed(this, TICK_MS)
        }
    }

    private fun writeLog(s: Session) {
        val log = s.log ?: return
        val d = deviceStats()
        try {
            log.append(
                FieldSample(
                    time = OffsetDateTime.now(),
                    thermalStatus = (d["thermalStatus"] as Number?)?.toInt(),
                    thermalHeadroom = (d["thermalHeadroom"] as Number?)?.toDouble(),
                    batteryTempC = (d["batteryTempC"] as Number?)?.toDouble(),
                    batteryPercent = (d["batteryPercent"] as Number?)?.toInt(),
                    plugged = d["plugged"] as Boolean?,
                    cameraFps = (d["fps"] as Number?)?.toDouble(),
                    programFps = programFps,
                    targetKbps = targetKbps,
                    measuredKbps = measuredBps?.let { it / 1000 },
                    droppedFrames = droppedFrames,
                    rtmpState = state.name.lowercase(),
                    replay = d["replayActive"] == true,
                ),
            )
        } catch (e: Exception) {
            Log.w(TAG, "Field log write failed", e)
        }
    }

    private fun reportError(id: Int, error: String) = handler.post {
        val s = session ?: return@post
        if (s.id != id) return@post
        Log.e(TAG, error)
        teardown(s)
        state = BroadcastState.FAILED
        message = error
        onStatus(status())
    }

    /** RootEncoder callbacks arrive on its own threads; handled on ours, ignored for old sessions. */
    private inner class Checker(private val id: Int) : ConnectChecker {
        private fun on(block: (Session) -> Unit) {
            handler.post {
                val s = session ?: return@post
                if (s.id == id) block(s)
            }
        }

        override fun onConnectionStarted(url: String) = Unit

        override fun onConnectionSuccess() = on { s ->
            // A new RTMP session: new timeline from the next keyframe, requested right away.
            clock.reset()
            connected = true
            s.program.requestKeyframe()
            if (liveSinceMs < 0) liveSinceMs = SystemClock.elapsedRealtime()
            state = BroadcastState.LIVE
            message = null
            onStatus(status())
        }

        override fun onConnectionFailed(reason: String) = on { s ->
            connected = false
            if (s.rtmp.shouldRetry(reason)) {
                state = BroadcastState.RECONNECTING
                message = reason
                s.rtmp.reConnect(RETRY_DELAY_MS)
            } else {
                teardown(s)
                state = BroadcastState.FAILED
                message = reason
            }
            onStatus(status())
        }

        override fun onDisconnect() = Unit // after our own disconnect(), or inside a retry

        override fun onAuthError() = on { s ->
            teardown(s)
            state = BroadcastState.FAILED
            message = "Authentication failed"
            onStatus(status())
        }

        override fun onAuthSuccess() = Unit

        override fun onNewBitrate(bitrate: Long) {
            measuredBps = bitrate
        }
    }

    private fun <T> onThread(block: () -> T): T {
        if (Thread.currentThread() === thread) return block()
        val task = FutureTask(block)
        handler.post(task)
        return try {
            task.get()
        } catch (e: ExecutionException) {
            throw e.cause ?: e
        }
    }

    private companion object {
        const val TAG = "Broadcaster"
        const val TICK_MS = 1000L
        const val LOG_EVERY_TICKS = 5L
        const val RETRY_DELAY_MS = 3000L
        // "Forever" for a match: one try every 3 s for years.
        const val RETRIES = Int.MAX_VALUE / 2
        // RootEncoder's default: the send queue is more than 20% full.
        const val CONGESTION_PERCENT = 20f
    }
}
