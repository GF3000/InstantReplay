package io.github.instantreplay.replay_capture_android.buffer

import io.github.instantreplay.replay_capture_android.mp4.TrackInfo
import java.io.File

/**
 * Rolling window of 1 s fMP4 fragments stored as files. Written by the encoder thread,
 * read by the clip assembler.
 */
internal class RingBuffer(private val dir: File, private val windowUs: Long) {

    data class Fragment(
        val sequence: Int,
        val startUs: Long,
        val endUs: Long,
        val baseTicks: Long,
        val durationTicks: Long,
        val file: File,
        val bytes: Long,
    )

    private val lock = Object()
    private val fragments = ArrayDeque<Fragment>()
    private var totalBytes = 0L

    @Volatile var track: TrackInfo? = null

    /** PTS of the newest encoded frame, including frames not yet in a closed fragment. */
    @Volatile var latestPtsUs: Long = -1
        private set

    init {
        reset()
    }

    fun reset() = synchronized(lock) {
        fragments.clear()
        totalBytes = 0
        latestPtsUs = -1
        track = null
        dir.deleteRecursively()
        dir.mkdirs()
    }

    fun noteFrame(ptsUs: Long) {
        latestPtsUs = ptsUs
    }

    fun append(sequence: Int, startUs: Long, endUs: Long, baseTicks: Long, durationTicks: Long, data: ByteArray) {
        val file = File(dir, "frag_%08d.m4s".format(sequence))
        file.writeBytes(data)
        synchronized(lock) {
            fragments.addLast(Fragment(sequence, startUs, endUs, baseTicks, durationTicks, file, data.size.toLong()))
            totalBytes += data.size
            while (fragments.size > 1 && endUs - fragments.first().startUs > windowUs) {
                val old = fragments.removeFirst()
                totalBytes -= old.bytes
                old.file.delete()
            }
            lock.notifyAll()
        }
    }

    /** Blocks until a closed fragment ends at or after [us]. */
    fun awaitEnd(us: Long, timeoutMs: Long): Boolean = synchronized(lock) {
        val deadline = System.currentTimeMillis() + timeoutMs
        while ((fragments.lastOrNull()?.endUs ?: Long.MIN_VALUE) < us) {
            val left = deadline - System.currentTimeMillis()
            if (left <= 0) return false
            lock.wait(left)
        }
        true
    }

    /** Fragments overlapping [fromUs, toUs). */
    fun select(fromUs: Long, toUs: Long): List<Fragment> = synchronized(lock) {
        fragments.filter { it.endUs > fromUs && it.startUs < toUs }
    }

    fun stats(): Map<String, Any> = synchronized(lock) {
        val first = fragments.firstOrNull()
        val last = fragments.lastOrNull()
        mapOf(
            "fragments" to fragments.size,
            "bufferMs" to if (first != null && last != null) (last.endUs - first.startUs) / 1000 else 0L,
            "bufferBytes" to totalBytes,
        )
    }
}
