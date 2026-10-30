package io.github.instantreplay.replay_capture_android.buffer

import io.github.instantreplay.replay_capture_android.mp4.TrackInfo
import java.io.File

/**
 * Rolling window of 1 s fMP4 fragments stored as files. Written by the encoder thread,
 * read by the clip assembler.
 *
 * Every encoder session is an *epoch* (SPEC §3.1): it has its own init segment ([track]) and its
 * decode times restart, so fragments of different epochs must never end up in the same clip.
 * Older epochs stay in the window until evicted, so a clip already waiting for its post-roll
 * can still be cut from them.
 */
internal class RingBuffer(private val dir: File, private val windowUs: Long) {

    data class Fragment(
        val epoch: Int,
        val sequence: Int,
        val startUs: Long,
        val endUs: Long,
        val baseTicks: Long,
        val durationTicks: Long,
        val file: File,
        val bytes: Long,
    )

    /** The newest encoded frame of [epoch]; [ptsUs] is -1 before the first frame. */
    data class Cursor(val epoch: Int, val ptsUs: Long)

    private val lock = Object()
    private val fragments = ArrayDeque<Fragment>()
    private val tracks = HashMap<Int, TrackInfo>()
    private var totalBytes = 0L
    private var totalUs = 0L

    /** Current encoder session. Incremented by [newEpoch] and [reset]. */
    @Volatile var epoch = 0
        private set

    /**
     * Called with every fragment once it is in the window, on the writer's thread and outside the
     * lock. Used by the session recorder, which archives what the window would otherwise evict.
     */
    @Volatile var fragmentListener: ((Fragment, ByteArray) -> Unit)? = null

    @Volatile private var currentTrack: TrackInfo? = null

    /** Codec configuration of the current epoch; null until the encoder reports its format. */
    var track: TrackInfo?
        get() = currentTrack
        set(value) {
            synchronized(lock) {
                currentTrack = value
                if (value == null) tracks.remove(epoch) else tracks[epoch] = value
            }
        }

    /** PTS of the newest encoded frame of the current epoch, including frames not yet in a closed fragment. */
    @Volatile var latestPtsUs: Long = -1
        private set

    init {
        reset()
    }

    /** Drops every fragment and starts a new epoch. */
    fun reset() = synchronized(lock) {
        fragments.clear()
        tracks.clear()
        totalBytes = 0
        totalUs = 0
        dir.deleteRecursively()
        dir.mkdirs()
        newEpoch()
    }

    /**
     * Starts a new encoder session (profile change, encoder restart). Fragments of older epochs are
     * kept until the window evicts them; clips waiting on an older epoch stop waiting.
     */
    fun newEpoch(): Int = synchronized(lock) {
        epoch++
        currentTrack = null
        latestPtsUs = -1
        lock.notifyAll()
        epoch
    }

    fun cursor(): Cursor = synchronized(lock) { Cursor(epoch, latestPtsUs) }

    fun trackFor(epoch: Int): TrackInfo? = synchronized(lock) { tracks[epoch] }

    fun noteFrame(ptsUs: Long, epoch: Int = this.epoch) {
        if (epoch == this.epoch) latestPtsUs = ptsUs
    }

    /** Ignored when [epoch] is no longer current (a late write from a stopped encoder). */
    fun append(
        sequence: Int,
        startUs: Long,
        endUs: Long,
        baseTicks: Long,
        durationTicks: Long,
        data: ByteArray,
        epoch: Int = this.epoch,
    ) {
        if (epoch != this.epoch) return
        val file = File(dir, "e%04d_frag_%08d.m4s".format(epoch, sequence))
        file.writeBytes(data)
        val fragment = Fragment(epoch, sequence, startUs, endUs, baseTicks, durationTicks, file, data.size.toLong())
        synchronized(lock) {
            if (epoch != this.epoch) {
                file.delete()
                return
            }
            fragments.addLast(fragment)
            totalBytes += data.size
            totalUs += endUs - startUs
            // Fragments are contiguous within an epoch, so the summed duration is the window span.
            while (fragments.size > 1 && totalUs > windowUs) {
                val old = fragments.removeFirst()
                totalBytes -= old.bytes
                totalUs -= old.endUs - old.startUs
                old.file.delete()
            }
            tracks.keys.retainAll { e -> e == this.epoch || fragments.any { it.epoch == e } }
            lock.notifyAll()
        }
        fragmentListener?.invoke(fragment, data)
    }

    /**
     * Blocks until a closed fragment of [epoch] ends at or after [us], or [epoch] is superseded
     * (no more fragments will come for it). Returns false on timeout.
     */
    fun awaitEnd(epoch: Int, us: Long, timeoutMs: Long): Boolean = synchronized(lock) {
        val deadline = System.nanoTime() + timeoutMs * 1_000_000
        while (epoch == this.epoch && lastEndUs(epoch) < us) {
            val leftMs = (deadline - System.nanoTime()) / 1_000_000
            if (leftMs <= 0) return false
            lock.wait(leftMs)
        }
        true
    }

    /** Fragments of [epoch] overlapping [fromUs, toUs). */
    fun select(epoch: Int, fromUs: Long, toUs: Long): List<Fragment> = synchronized(lock) {
        fragments.filter { it.epoch == epoch && it.endUs > fromUs && it.startUs < toUs }
    }

    fun stats(): Map<String, Any> = synchronized(lock) {
        mapOf(
            "fragments" to fragments.size,
            "bufferMs" to totalUs / 1000,
            "bufferBytes" to totalBytes,
        )
    }

    private fun lastEndUs(epoch: Int): Long =
        fragments.lastOrNull { it.epoch == epoch }?.endUs ?: Long.MIN_VALUE
}
