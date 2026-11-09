package io.github.instantreplay.replay_capture_android.broadcast

import android.annotation.SuppressLint
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaRecorder
import android.os.Process
import android.util.Log
import java.nio.ByteBuffer

/**
 * Microphone → AAC-LC 48 kHz mono 128 kbps for the broadcast (SPEC §12.1).
 *
 * Without a microphone ([useMic] false, no permission, or AudioRecord refusing) it encodes
 * silence at real-time pace instead: YouTube expects an audio track and the stream must look the
 * same either way. [micActive] tells which one runs.
 *
 * One thread `ir-audio` reads PCM in AAC-frame-sized chunks (1024 samples), stamps them with
 * [AudioClock] on the same monotonic clock as the camera, and drains the encoder synchronously.
 * [onFrame] receives raw AAC frames and must consume the buffer before returning.
 */
internal class AudioEncoder(
    useMic: Boolean,
    /** The camera's timestamp clock (`System.nanoTime` or `elapsedRealtimeNanos`), for A/V sync. */
    private val nowNs: () -> Long,
    private val onFrame: (buffer: ByteBuffer, info: MediaCodec.BufferInfo) -> Unit,
    private val onError: (String) -> Unit,
) {
    private val record: AudioRecord? = if (useMic) openMic() else null
    val micActive: Boolean get() = record != null

    private val codec: MediaCodec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC).apply {
        val format = MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_AAC, SAMPLE_RATE, 1).apply {
            setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
            setInteger(MediaFormat.KEY_BIT_RATE, BITRATE)
            setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, CHUNK_BYTES * 2)
        }
        configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
    }

    @Volatile private var running = false
    private val thread = Thread(::loop, "ir-audio")

    fun start() {
        running = true
        codec.start()
        record?.startRecording()
        thread.start()
    }

    /** Stops the thread; the codec and AudioRecord are released by it on the way out. */
    fun release() {
        val started = running
        running = false
        if (started) thread.join(1000) else releaseResources()
    }

    @SuppressLint("MissingPermission") // The caller checked RECORD_AUDIO.
    private fun openMic(): AudioRecord? {
        val minBuffer = AudioRecord.getMinBufferSize(SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
        if (minBuffer <= 0) return null
        // CAMCORDER is tuned for video recording (the mic facing the scene); MIC as a fallback.
        for (source in intArrayOf(MediaRecorder.AudioSource.CAMCORDER, MediaRecorder.AudioSource.MIC)) {
            val record = try {
                AudioRecord(
                    source, SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT,
                    maxOf(minBuffer * 2, CHUNK_BYTES * 4),
                )
            } catch (e: Exception) {
                Log.w(TAG, "AudioRecord source $source failed", e)
                continue
            }
            if (record.state == AudioRecord.STATE_INITIALIZED) return record
            record.release()
        }
        return null
    }

    private fun loop() {
        Process.setThreadPriority(Process.THREAD_PRIORITY_URGENT_AUDIO)
        val pcm = ByteArray(CHUNK_BYTES) // zeros: silence unless the mic overwrites it
        val clock = AudioClock(SAMPLE_RATE)
        val info = MediaCodec.BufferInfo()
        val chunkNs = SAMPLES_PER_CHUNK * 1_000_000_000L / SAMPLE_RATE
        var nextSilenceNs = System.nanoTime() + chunkNs
        try {
            while (running) {
                val bytes = if (record != null) {
                    record.read(pcm, 0, CHUNK_BYTES).also { if (it < 0) throw IllegalStateException("AudioRecord.read $it") }
                } else {
                    // Real-time pace, so the silent track advances with the video.
                    val waitNs = nextSilenceNs - System.nanoTime()
                    if (waitNs > 0) Thread.sleep(waitNs / 1_000_000, (waitNs % 1_000_000).toInt())
                    nextSilenceNs += chunkNs
                    CHUNK_BYTES
                }
                if (bytes == 0) continue
                val ptsUs = clock.next(nowNs(), bytes / 2)
                val input = codec.dequeueInputBuffer(INPUT_TIMEOUT_US)
                if (input >= 0) {
                    codec.getInputBuffer(input)!!.apply { clear(); put(pcm, 0, bytes) }
                    codec.queueInputBuffer(input, 0, bytes, ptsUs, 0)
                } // else the encoder is behind: drop this chunk rather than stall the mic.
                drain(info)
            }
        } catch (e: InterruptedException) {
            // Stopping.
        } catch (e: Exception) {
            if (running) onError("Audio error: ${e.message}")
        } finally {
            releaseResources()
        }
    }

    private fun drain(info: MediaCodec.BufferInfo) {
        while (true) {
            val index = codec.dequeueOutputBuffer(info, 0)
            if (index < 0) return // try again later / format changed: nothing to send
            val isConfig = info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0
            if (!isConfig && info.size > 0) {
                val buffer = codec.getOutputBuffer(index)!!
                buffer.position(info.offset)
                buffer.limit(info.offset + info.size)
                info.set(0, info.size, info.presentationTimeUs, info.flags)
                onFrame(buffer.slice(), info)
            }
            codec.releaseOutputBuffer(index, false)
        }
    }

    private fun releaseResources() {
        try {
            record?.stop()
        } catch (_: IllegalStateException) {
        }
        record?.release()
        try {
            codec.stop()
        } catch (_: IllegalStateException) {
        }
        codec.release()
    }

    companion object {
        private const val TAG = "AudioEncoder"
        const val SAMPLE_RATE = 48_000
        const val BITRATE = 128_000
        private const val SAMPLES_PER_CHUNK = 1024 // one AAC-LC frame
        private const val CHUNK_BYTES = SAMPLES_PER_CHUNK * 2 // mono PCM16
        private const val INPUT_TIMEOUT_US = 10_000L
    }
}
