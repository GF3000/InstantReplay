package io.github.instantreplay.replay_capture_android.broadcast

import kotlin.math.abs
import kotlin.math.log10
import kotlin.math.max

/**
 * The microphone's level for the mic button's meter (SPEC §12.7), in dBFS (0 = full scale).
 *
 * VU-like ballistics on the peak of each PCM chunk: instant attack, and a linear release of
 * [releaseDbPerSecond] (60 dB/s ≈ 18 dB in 300 ms), so speech reads as steady bars instead of
 * flickering. [update] runs on the audio thread, [read] on any thread: the latest value is one
 * immutable snapshot behind a volatile reference.
 */
internal class MicLevelMeter(private val releaseDbPerSecond: Double = 60.0) {
    private class Snapshot(val db: Double, val atNs: Long)

    @Volatile private var last: Snapshot? = null

    /** One chunk of 16-bit little-endian PCM read at [nowNs]. */
    fun update(pcm: ByteArray, bytes: Int, nowNs: Long) {
        val chunk = peakDbfs(pcm, bytes)
        val prev = last
        val held = if (prev == null) FLOOR_DB else decay(prev.db, nowNs - prev.atNs, releaseDbPerSecond)
        last = Snapshot(max(chunk, held), nowNs)
    }

    /** The level at [nowNs] in dBFS ([FLOOR_DB]…0); null before the first chunk. */
    fun read(nowNs: Long): Double? {
        val s = last ?: return null
        return decay(s.db, nowNs - s.atNs, releaseDbPerSecond)
    }

    companion object {
        /** Silence; also the value of an all-zero chunk. */
        const val FLOOR_DB = -90.0

        /** Peak of 16-bit little-endian mono PCM in dBFS, at least [FLOOR_DB]. */
        fun peakDbfs(pcm: ByteArray, bytes: Int): Double {
            var peak = 0
            var i = 0
            val end = bytes - 1
            while (i < end) {
                val sample = (pcm[i].toInt() and 0xFF) or (pcm[i + 1].toInt() shl 8)
                val a = abs(sample.toShort().toInt())
                if (a > peak) peak = a
                i += 2
            }
            if (peak == 0) return FLOOR_DB
            return max(FLOOR_DB, 20 * log10(peak / 32768.0))
        }

        /** [db] after falling for [elapsedNs] at [dbPerSecond], never below [FLOOR_DB]. */
        fun decay(db: Double, elapsedNs: Long, dbPerSecond: Double): Double =
            max(FLOOR_DB, db - dbPerSecond * max(0L, elapsedNs) / 1e9)
    }
}
