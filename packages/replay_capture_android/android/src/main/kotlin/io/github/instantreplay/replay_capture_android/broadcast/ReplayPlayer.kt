package io.github.instantreplay.replay_capture_android.broadcast

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.util.Log
import android.view.Surface
import java.io.File

/**
 * Decodes one clip into [output] for a replay on air (SPEC §12.6). Each decoded frame is rendered
 * when the [MediaClock] reaches its timestamp, so the speed can change at any moment. Runs on its
 * own thread; [stop] blocks until the decoder is released (the surface can then take another one).
 *
 * The track's rotation is passed to the decoder, which applies it through the output surface's
 * transform, so clips recorded on the direct (sensor-oriented) path come out upright.
 */
internal class ReplayPlayer(
    val clipId: String,
    private val file: File,
    speed: Float,
    private val output: Surface,
    /** First frame rendered; the clip's duration in ms. */
    private val onStarted: (durationMs: Long) -> Unit,
    /** The decoder is done: end of the clip (null), or a failure. Not called after [stop]. */
    private val onEnded: (error: String?) -> Unit,
) {
    val clock = MediaClock(MediaClock.snap(speed))

    @Volatile var durationMs = 0L
        private set

    @Volatile var positionMs = 0L
        private set

    @Volatile private var running = true
    private val thread = Thread(::run, "ir-replay").apply { start() }

    fun setSpeed(speed: Float) = clock.setSpeed(MediaClock.snap(speed), System.nanoTime())

    /** Stops decoding and releases the decoder; no [onEnded] callback. Any thread but its own. */
    fun stop() {
        running = false
        thread.join(2000)
    }

    private fun run() {
        var extractor: MediaExtractor? = null
        var codec: MediaCodec? = null
        var error: String? = null
        try {
            val ex = MediaExtractor().also { extractor = it }
            ex.setDataSource(file.absolutePath)
            val track = (0 until ex.trackCount).first {
                ex.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("video/") == true
            }
            ex.selectTrack(track)
            val format = ex.getTrackFormat(track)
            if (format.containsKey(MediaFormat.KEY_DURATION)) durationMs = format.getLong(MediaFormat.KEY_DURATION) / 1000
            val decoder = MediaCodec.createDecoderByType(format.getString(MediaFormat.KEY_MIME)!!).also { codec = it }
            decoder.configure(format, output, null, 0)
            decoder.start()
            decode(ex, decoder)
        } catch (e: Exception) {
            Log.w(TAG, "Replay failed", e)
            error = e.message ?: e.toString()
        } finally {
            try {
                codec?.stop()
            } catch (_: Exception) {
            }
            codec?.release()
            extractor?.release()
        }
        if (running) onEnded(error)
    }

    private fun decode(ex: MediaExtractor, decoder: MediaCodec) {
        val info = MediaCodec.BufferInfo()
        var inputDone = false
        var firstPtsUs = -1L
        while (running) {
            if (!inputDone) {
                val inIndex = decoder.dequeueInputBuffer(TIMEOUT_US)
                if (inIndex >= 0) {
                    val size = ex.readSampleData(decoder.getInputBuffer(inIndex)!!, 0)
                    if (size < 0) {
                        decoder.queueInputBuffer(inIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                        inputDone = true
                    } else {
                        decoder.queueInputBuffer(inIndex, 0, size, ex.sampleTime, 0)
                        ex.advance()
                    }
                }
            }
            val outIndex = decoder.dequeueOutputBuffer(info, TIMEOUT_US)
            if (outIndex < 0) continue
            if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                decoder.releaseOutputBuffer(outIndex, false)
                return
            }
            if (firstPtsUs < 0) {
                firstPtsUs = info.presentationTimeUs
                clock.start(System.nanoTime())
            }
            val dueUs = info.presentationTimeUs - firstPtsUs
            // Hold the frame until media time reaches it; short sleeps keep speed changes prompt.
            while (running && clock.positionUs(System.nanoTime()) < dueUs) Thread.sleep(WAIT_MS)
            if (!running) {
                decoder.releaseOutputBuffer(outIndex, false)
                return
            }
            decoder.releaseOutputBuffer(outIndex, true)
            positionMs = dueUs / 1000
            if (dueUs == 0L) onStarted(durationMs)
        }
    }

    private companion object {
        const val TAG = "ReplayPlayer"
        const val TIMEOUT_US = 10_000L
        const val WAIT_MS = 4L
    }
}
