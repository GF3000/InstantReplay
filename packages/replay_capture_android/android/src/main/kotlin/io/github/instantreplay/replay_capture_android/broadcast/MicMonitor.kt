package io.github.instantreplay.replay_capture_android.broadcast

import android.media.AudioRecord
import android.os.Process
import android.util.Log

/**
 * The microphone measured before going live (SPEC §12.7): the same source as the stream, read
 * only for [MicLevelMeter], nothing encoded or sent. [open] returns null when the microphone is
 * refused. [release] stops it and frees the microphone for the stream.
 */
internal class MicMonitor private constructor(private val record: AudioRecord) {
    private val meter = MicLevelMeter()
    @Volatile private var running = true
    private val thread = Thread(::loop, "ir-mic-monitor")

    /** What the microphone hears now, in dBFS; null until the first chunk. Any thread. */
    val levelDbfs: Double? get() = meter.read(System.nanoTime())

    private fun loop() {
        Process.setThreadPriority(Process.THREAD_PRIORITY_AUDIO)
        val pcm = ByteArray(AudioEncoder.CHUNK_BYTES)
        try {
            record.startRecording()
            while (running) {
                val bytes = record.read(pcm, 0, pcm.size)
                if (bytes < 0) break
                if (bytes > 0) meter.update(pcm, bytes, System.nanoTime())
            }
        } catch (e: Exception) {
            Log.w(TAG, "Mic monitor stopped", e)
        } finally {
            try {
                record.stop()
            } catch (_: IllegalStateException) {
            }
            record.release()
        }
    }

    /** Stops reading and releases the microphone (waits up to 1 s for it). */
    fun release() {
        running = false
        thread.join(1000)
    }

    companion object {
        private const val TAG = "MicMonitor"

        /** Starts measuring; null when the microphone can't be opened. RECORD_AUDIO checked. */
        fun open(): MicMonitor? = AudioEncoder.openMic()?.let { MicMonitor(it).also { m -> m.thread.start() } }
    }
}
