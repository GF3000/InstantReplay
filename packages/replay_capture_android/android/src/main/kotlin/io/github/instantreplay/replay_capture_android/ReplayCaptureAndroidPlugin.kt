package io.github.instantreplay.replay_capture_android

import android.Manifest
import android.app.Activity
import android.app.Application
import android.content.Context
import android.content.pm.PackageManager
import android.os.Bundle
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.StatFs
import android.view.WindowManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.PluginRegistry
import io.flutter.view.TextureRegistry
import io.github.instantreplay.replay_capture_android.broadcast.Broadcaster
import io.github.instantreplay.replay_capture_android.broadcast.ScoreboardState
import io.github.instantreplay.replay_capture_android.buffer.RingBuffer
import io.github.instantreplay.replay_capture_android.broadcast.ReplayPlayer
import io.github.instantreplay.replay_capture_android.outbox.Outbox
import io.github.instantreplay.replay_capture_android.recording.MediaStorePartStore
import io.github.instantreplay.replay_capture_android.recording.SessionRecorder
import java.io.File

class ReplayCaptureAndroidPlugin :
    FlutterPlugin,
    ActivityAware,
    PluginRegistry.RequestPermissionsResultListener,
    CaptureHostApi {

    private lateinit var context: Context
    private lateinit var textures: TextureRegistry
    private lateinit var messenger: BinaryMessenger
    private lateinit var events: CaptureEventsApi
    private lateinit var outbox: Outbox
    private lateinit var recorder: SessionRecorder
    private val mainHandler = Handler(Looper.getMainLooper())

    private var activityBinding: ActivityPluginBinding? = null
    private val activity: Activity? get() = activityBinding?.activity
    private var pendingPermission: ((Result<Boolean>) -> Unit)? = null
    private var pendingMicPermission: ((Result<Boolean>) -> Unit)? = null

    private var engine: CaptureEngine? = null

    /** Present while capture runs in broadcast mode (SPEC §12). */
    private var broadcaster: Broadcaster? = null
    private var serviceMicrophone = false

    /** Latest engine stats, for the broadcast field log (written off the main thread). */
    @Volatile private var lastEngineStats: Map<String, Any?> = emptyMap()
    private var live: LiveStreamer? = null
    private var preview: TextureRegistry.SurfaceProducer? = null
    private var previewEnabled = true

    /**
     * With the screen off or the app in the background Flutter stops consuming preview frames, and
     * drawing into them stalls the GL pipeline until the HQ recording drops frames. Measured on the
     * reference phone: ~5 lost frames per second after screen-off. So the preview is detached then.
     */
    private var appVisible = true
    private var liveAttached = false
    private val showPreview get() = previewEnabled && appVisible

    private val lifecycle = object : Application.ActivityLifecycleCallbacks {
        override fun onActivityStarted(a: Activity) = onVisibility(a, true)
        override fun onActivityStopped(a: Activity) = onVisibility(a, false)
        override fun onActivityCreated(a: Activity, state: Bundle?) = Unit
        override fun onActivityResumed(a: Activity) = Unit
        override fun onActivityPaused(a: Activity) = Unit
        override fun onActivitySaveInstanceState(a: Activity, state: Bundle) = Unit
        override fun onActivityDestroyed(a: Activity) = Unit
    }

    private fun onVisibility(a: Activity, visible: Boolean) {
        if (a !== activity || appVisible == visible) return
        appVisible = visible
        applyPreview()
    }
    private var ring: RingBuffer? = null
    private var ringWindowSeconds = 0
    private val thermalPolicy = ThermalPolicy()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        textures = binding.textureRegistry
        messenger = binding.binaryMessenger
        events = CaptureEventsApi(messenger)
        val outboxDir = File(context.getExternalFilesDir(null) ?: context.filesDir, "outbox")
        outbox = Outbox(outboxDir) { clip -> mainHandler.post { events.onClipChanged(clip) {} } }
        recorder = SessionRecorder(
            store = MediaStorePartStore(context.contentResolver),
            stateDir = File(context.filesDir, "recording"),
            freeBytes = ::sharedFreeBytes,
            onStatus = { status -> mainHandler.post { events.onRecording(status) {} } },
            onSaved = { saved -> mainHandler.post { events.onRecordingSaved(saved) {} } },
        )
        CaptureHostApi.setUp(messenger, this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        stopCapture()
        CaptureHostApi.setUp(messenger, null)
        outbox.release()
        recorder.release()
    }

    // region CaptureHostApi

    override fun requestPermission(callback: (Result<Boolean>) -> Unit) {
        if (hasCameraPermission()) return callback(Result.success(true))
        val host = activity
            ?: return callback(Result.failure(FlutterError("no_activity", "Plugin is not attached to an activity")))
        pendingPermission = callback
        host.requestPermissions(arrayOf(Manifest.permission.CAMERA), PERMISSION_REQUEST)
    }

    override fun requestMicPermission(callback: (Result<Boolean>) -> Unit) {
        if (hasMicPermission()) return callback(Result.success(true))
        val host = activity
            ?: return callback(Result.failure(FlutterError("no_activity", "Plugin is not attached to an activity")))
        pendingMicPermission = callback
        host.requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), MIC_PERMISSION_REQUEST)
    }

    override fun supportedProfiles(): List<CaptureProfile> = Profiles.supported(context)

    override fun start(request: StartRequest): StartResult {
        if (engine != null) throw FlutterError("busy", "Capture already running")
        if (!hasCameraPermission()) throw FlutterError("permission", "Camera permission not granted")
        val profile = supportedProfiles().firstOrNull { it.id == request.profileId }
            ?: throw FlutterError("profile", "Profile ${request.profileId} is not supported on this device")

        val config = CaptureConfig(
            width = profile.width.toInt(),
            height = profile.height.toInt(),
            fps = profile.fps.toInt(),
            bitrate = profile.bitrate.toInt(),
            windowSeconds = request.windowSeconds.toInt(),
            broadcast = request.broadcast == true,
        )
        val ring = ringFor(config.windowSeconds)
        val producer = textures.createSurfaceProducer().apply { setSize(PREVIEW_WIDTH, PREVIEW_HEIGHT) }
        val capture = CaptureEngine(context, config, ring, ::emit)
        var streamer: LiveStreamer? = null

        try {
            capture.start()
            if (showPreview) capture.setPreviewSurface(producer.surface, PREVIEW_WIDTH, PREVIEW_HEIGHT)
            streamer = LiveStreamer(context, ::emit)
        } catch (e: Exception) {
            capture.release()
            streamer?.release()
            producer.release()
            throw FlutterError("start_failed", e.message)
        }
        producer.setCallback(object : TextureRegistry.SurfaceProducer.Callback {
            override fun onSurfaceAvailable() {
                if (showPreview) engine?.setPreviewSurface(producer.surface, PREVIEW_WIDTH, PREVIEW_HEIGHT)
            }

            override fun onSurfaceCleanup() {
                engine?.setPreviewSurface(null, 0, 0)
            }
        })

        engine = capture
        live = streamer
        preview = producer
        if (config.broadcast) {
            broadcaster = Broadcaster(
                config = config,
                logDir = context.getExternalFilesDir(null),
                boottimeTimestamps = capture.boottimeTimestamps,
                attachProgram = capture::setProgramSurface,
                deviceStats = { lastEngineStats },
                onStatus = { status -> mainHandler.post { onBroadcastStatus(status) } },
            )
        }
        outbox.attach(ring)
        recorder.attach(ring, config.bitrate)
        CaptureService.start(context)
        serviceMicrophone = false
        activity?.window?.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        // The engine only reports changes; a phone that is already hot must degrade from the start.
        thermalPolicy.reset(broadcast = config.broadcast)
        applyThermal(context.getSystemService(PowerManager::class.java).currentThermalStatus)

        return StartResult(
            textureId = producer.id(),
            encoder = capture.encoderName,
            highProfile = capture.highProfile,
            sensorOrientation = capture.sensorOrientation.toLong(),
            maxZoom = capture.maxZoom.toDouble(),
        )
    }

    override fun stop() = stopCapture()

    override fun setPreviewEnabled(enabled: Boolean) {
        previewEnabled = enabled
        applyPreview()
    }

    private fun applyPreview() {
        val producer = preview ?: return
        engine?.setPreviewSurface(if (showPreview) producer.surface else null, PREVIEW_WIDTH, PREVIEW_HEIGHT)
    }

    override fun saveClip(request: SaveRequest, callback: (Result<ClipInfo>) -> Unit) {
        outbox.save(request) { result -> mainHandler.post { callback(result) } }
    }

    override fun listClips(): List<ClipInfo> = outbox.list()

    override fun getClip(id: String): ClipInfo? = outbox.get(id)

    override fun ackClip(id: String, sha256: String): Boolean = outbox.ack(id, sha256)

    override fun setClipReserve(size: Long) = outbox.setReserveSize(size.toInt())

    override fun liveOffer(viewerId: String, codec: String, callback: (Result<String>) -> Unit) {
        val streamer = live ?: return callback(Result.failure(FlutterError("not_running", "Capture is not running")))
        updateLiveOutput(attach = true)
        streamer.createOffer(viewerId, codec) { r ->
            mainHandler.post { callback(r.recoverCatching { throw FlutterError("offer_failed", it.message) }) }
        }
    }

    override fun liveAnswer(viewerId: String, sdp: String, callback: (Result<Unit>) -> Unit) {
        val streamer = live ?: return callback(Result.failure(FlutterError("not_running", "Capture is not running")))
        streamer.setAnswer(viewerId, sdp) { r ->
            mainHandler.post { callback(r.recoverCatching { throw FlutterError("answer_failed", it.message) }) }
        }
    }

    override fun liveAddIceCandidate(viewerId: String, candidate: String, sdpMid: String?, sdpMLineIndex: Long?) {
        live?.addIceCandidate(viewerId, candidate, sdpMid, sdpMLineIndex?.toInt())
    }

    override fun liveClose(viewerId: String) {
        live?.close(viewerId)
        updateLiveOutput(attach = false)
    }

    /** The live surface is only fed while someone watches: the copy costs GPU time the HQ path needs. */
    private fun updateLiveOutput(attach: Boolean) {
        val streamer = live ?: return
        val want = attach || streamer.viewerCount > 0
        if (want == liveAttached) return
        liveAttached = want
        engine?.setLiveSurface(if (want) streamer.surface else null, LiveStreamer.WIDTH, LiveStreamer.HEIGHT)
    }

    override fun liveStats(callback: (Result<List<LiveViewerStats>>) -> Unit) {
        val streamer = live ?: return callback(Result.success(emptyList()))
        streamer.stats { stats -> mainHandler.post { callback(Result.success(stats.map(::toLiveStats))) } }
    }

    override fun recordingStatus(): RecordingStatus = recorder.currentStatus()

    override fun recordStart(includeSeconds: Long, callback: (Result<RecordingStatus>) -> Unit) {
        recorder.start(includeSeconds) { r -> mainHandler.post { callback(r) } }
    }

    override fun recordPause(callback: (Result<RecordingStatus>) -> Unit) {
        recorder.pause { r -> mainHandler.post { callback(r) } }
    }

    override fun recordStop(callback: (Result<RecordingSaved?>) -> Unit) {
        recorder.stop { r -> mainHandler.post { callback(r) } }
    }

    override fun recoverRecordings(callback: (Result<List<RecordingSaved>>) -> Unit) {
        recorder.recover { r -> mainHandler.post { callback(r) } }
    }

    override fun setZoom(ratio: Double) {
        engine?.setZoom(ratio.toFloat())
    }

    override fun setOverlay(overlay: OverlayState) {
        engine?.setOverlay(
            ScoreboardState(
                visible = overlay.visible,
                homeName = overlay.homeName,
                awayName = overlay.awayName,
                homeScore = overlay.homeScore.toInt(),
                awayScore = overlay.awayScore.toInt(),
                homeColor = overlay.homeColor.toInt(),
                awayColor = overlay.awayColor.toInt(),
                periodLabel = overlay.periodLabel,
                clockMs = overlay.clockMs,
                clockRunning = overlay.clockRunning,
                countDown = overlay.countDown,
                scalePercent = overlay.scalePercent.toInt(),
            ),
        )
    }

    override fun broadcastStart(config: BroadcastConfig, callback: (Result<BroadcastStatus>) -> Unit) {
        val b = broadcaster ?: return callback(
            Result.failure(FlutterError("not_broadcast_mode", "Capture is not running in broadcast mode")),
        )
        // No microphone permission is not an error: the stream carries silence and says audio=false.
        val useMic = config.audio && hasMicPermission()
        val kbps = config.targetKbps.toInt().coerceIn(MIN_BROADCAST_KBPS, MAX_BROADCAST_KBPS)
        b.start(config.url, kbps, useMic) { r ->
            mainHandler.post {
                callback(r.recoverCatching { throw FlutterError("broadcast_failed", it.message) })
            }
        }
    }

    override fun broadcastStop(callback: (Result<Unit>) -> Unit) {
        val b = broadcaster ?: return callback(Result.success(Unit))
        engine?.stopReplay() // nothing goes on air without a stream
        b.stop { mainHandler.post { callback(Result.success(Unit)) } }
    }

    override fun broadcastStatus(): BroadcastStatus = broadcaster?.status() ?: IDLE_BROADCAST

    // Replays on air (SPEC §12.6).

    override fun replayStart(
        clipId: String,
        speed: Double,
        label: String,
        scoreboard: Boolean,
        callback: (Result<ReplayStatus>) -> Unit,
    ) {
        val e = engine
        val b = broadcaster
        if (e == null || b == null || !b.isActive) {
            return callback(Result.failure(FlutterError("not_live", "No broadcast is active")))
        }
        // Pinned: neither the reserve nor the TTL deletes it while it is on air.
        val clip = outbox.pin(clipId)
        val path = clip?.path
        if (clip == null || path == null) {
            if (clip != null) outbox.unpin(clipId)
            return callback(Result.failure(FlutterError("replay_unavailable", "Clip $clipId is not on the Camera")))
        }
        var answered = false
        e.startReplay(
            clipId = clipId,
            file = File(path),
            speed = speed.toFloat(),
            badge = label,
            showScoreboard = scoreboard,
            onStarted = { player ->
                mainHandler.post {
                    val status = replayStatus(player)
                    if (!answered) {
                        answered = true
                        callback(Result.success(status))
                    }
                    events.onReplay(status) {}
                }
            },
            onEnded = { id, error ->
                outbox.unpin(id)
                mainHandler.post {
                    if (!answered) {
                        answered = true
                        callback(Result.failure(FlutterError("replay_failed", error ?: "Replay ended before its first frame")))
                    }
                    events.onReplayEnded(id, error) {}
                }
            },
        )
    }

    override fun replaySpeed(speed: Double) {
        val e = engine ?: return
        e.setReplaySpeed(speed.toFloat())
        e.currentReplay()?.let { events.onReplay(replayStatus(it)) {} }
    }

    override fun replayStop(callback: (Result<Unit>) -> Unit) {
        engine?.stopReplay()
        callback(Result.success(Unit))
    }

    private fun replayStatus(p: ReplayPlayer) = ReplayStatus(
        clipId = p.clipId,
        speed = p.clock.speed().toDouble(),
        positionMs = p.positionMs,
        durationMs = p.durationMs,
    )

    /** Main thread: forwards a broadcast state change and keeps the service type in step. */
    private fun onBroadcastStatus(status: BroadcastStatus) {
        // Null once capture stopped: the service is gone then, only the final state is forwarded.
        val b = broadcaster
        val microphone = b != null && b.isActive && status.audio
        if (b != null && microphone != serviceMicrophone) {
            serviceMicrophone = microphone
            CaptureService.start(context, microphone)
        }
        events.onBroadcast(status) {}
    }

    /** Free space on shared storage, where Movies/InstantReplay lives. */
    @Suppress("DEPRECATION")
    private fun sharedFreeBytes(): Long = StatFs(Environment.getExternalStorageDirectory().path).availableBytes

    // endregion

    /**
     * One ring per window size, kept across starts so a clip still waiting for its post-roll keeps
     * its fragments; each start is a new epoch instead.
     */
    private fun ringFor(windowSeconds: Int): RingBuffer {
        val existing = ring
        if (existing != null && ringWindowSeconds == windowSeconds) {
            existing.newEpoch()
            return existing
        }
        return RingBuffer(File(context.cacheDir, "ring"), windowSeconds * 1_000_000L).also {
            ring = it
            ringWindowSeconds = windowSeconds
        }
    }

    private fun stopCapture() {
        // Ends the epoch so saves waiting for a post-roll that will never come stop waiting now.
        ring?.newEpoch()
        // The broadcast first: it detaches the program surface while the engine still runs.
        broadcaster?.release()
        broadcaster = null
        serviceMicrophone = false
        // Engine first: it stops drawing into the live surface before the streamer is released.
        engine?.release()
        engine = null
        live?.release()
        live = null
        liveAttached = false
        preview?.release()
        preview = null
        outbox.attach(null)
        // Closes the open part; a recording continues in a new part when capture starts again.
        recorder.detach()
        CaptureService.stop(context)
        activity?.window?.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    /** Engine events arrive as maps from background threads; forward them typed on the main thread. */
    private fun emit(event: Map<String, Any?>) {
        if (event["type"] == "stats") {
            // Headroom is sampled every other interval; keep the last known value for the log.
            val headroom = event["thermalHeadroom"] ?: lastEngineStats["thermalHeadroom"]
            lastEngineStats = event + ("thermalHeadroom" to headroom)
        }
        mainHandler.post {
            when (event["type"]) {
                "stats" -> events.onStats(toStats(event)) {}
                "thermal" -> applyThermal(event["status"] as Int)
                "camera" -> events.onCameraState(event["state"] as String) {}
                "error" -> events.onError(event["message"] as String) {}
                "live" -> events.onLiveState(event["viewer"] as String, event["state"] as String) {}
                "live_ice" -> events.onLiveIceCandidate(
                    event["viewer"] as String,
                    event["candidate"] as String,
                    event["sdpMid"] as String?,
                    (event["sdpMLineIndex"] as Int?)?.toLong(),
                ) {}
            }
        }
    }

    /**
     * Applies in-process effects up to the escalated action (SPEC §3.6). Lowering fps or resolution
     * needs a capture restart with another profile, which the Dart side does on the event.
     */
    private fun applyThermal(status: Int) {
        val action = thermalPolicy.onStatus(status) ?: return
        if (action.ordinal >= ThermalAction.PREVIEW_OFF.ordinal) setPreviewEnabled(false)
        if (action.ordinal >= ThermalAction.REDUCE_LIVE_BITRATE.ordinal) live?.setMaxBitrate(THERMAL_LIVE_BITRATE)
        if (action == ThermalAction.STOP_LIVE) {
            live?.closeAll()
            updateLiveOutput(attach = false)
        }
        events.onThermal(ThermalEvent(status = status.toLong(), action = action)) {}
    }

    private fun toStats(e: Map<String, Any?>): CaptureStats {
        val (clips, bytes) = outbox.stats()
        fun long(key: String) = (e[key] as Number?)?.toLong() ?: 0L
        return CaptureStats(
            encodedFrames = long("encodedFrames"),
            fps = (e["fps"] as Number?)?.toDouble() ?: 0.0,
            gaps = long("gaps"),
            cameraGaps = long("cameraGaps"),
            glGaps = long("glGaps"),
            bufferMs = long("bufferMs"),
            bufferBytes = long("bufferBytes"),
            outboxClips = clips,
            outboxBytes = bytes,
            thermalStatus = long("thermalStatus"),
            thermalHeadroom = (e["thermalHeadroom"] as Number?)?.toDouble(),
            batteryTempC = (e["batteryTempC"] as Number?)?.toDouble(),
            batteryPercent = (e["batteryPercent"] as Number?)?.toLong(),
            plugged = e["plugged"] == true,
            recording = recorder.currentStatus(),
            broadcast = broadcaster?.status(),
            replay = engine?.currentReplay()?.let(::replayStatus),
        )
    }

    private fun toLiveStats(m: Map<String, Any?>) = LiveViewerStats(
        viewerId = m["viewer"] as String,
        codec = m["codec"] as String?,
        encoderImplementation = m["encoderImplementation"] as String?,
        framesPerSecond = (m["framesPerSecond"] as String?)?.toDoubleOrNull(),
        frameWidth = (m["frameWidth"] as String?)?.toDoubleOrNull()?.toLong(),
        frameHeight = (m["frameHeight"] as String?)?.toDoubleOrNull()?.toLong(),
        qualityLimitationReason = m["qualityLimitationReason"] as String?,
    )

    // region Permissions / ActivityAware

    private fun hasCameraPermission() =
        context.checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED

    private fun hasMicPermission() =
        context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray): Boolean {
        val granted = Result.success(grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED)
        when (requestCode) {
            PERMISSION_REQUEST -> {
                pendingPermission?.invoke(granted)
                pendingPermission = null
            }
            MIC_PERMISSION_REQUEST -> {
                pendingMicPermission?.invoke(granted)
                pendingMicPermission = null
            }
            else -> return false
        }
        return true
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addRequestPermissionsResultListener(this)
        binding.activity.application.registerActivityLifecycleCallbacks(lifecycle)
    }

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)

    override fun onDetachedFromActivity() {
        activityBinding?.let {
            it.removeRequestPermissionsResultListener(this)
            it.activity.application.unregisterActivityLifecycleCallbacks(lifecycle)
        }
        activityBinding = null
    }

    // endregion

    private companion object {
        const val PERMISSION_REQUEST = 4207
        const val MIC_PERMISSION_REQUEST = 4208
        const val PREVIEW_WIDTH = 1280
        const val PREVIEW_HEIGHT = 720
        const val THERMAL_LIVE_BITRATE = 1_500_000
        const val MIN_BROADCAST_KBPS = 2500
        const val MAX_BROADCAST_KBPS = 6000
        val IDLE_BROADCAST = BroadcastStatus(
            state = BroadcastState.IDLE,
            targetKbps = 0,
            droppedFrames = 0,
            audio = false,
        )
    }
}
