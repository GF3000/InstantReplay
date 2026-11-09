package io.github.instantreplay.replay_capture_android.broadcast

/**
 * Adaptive video bitrate for the program stream (SPEC §12.1), ticked once per second.
 *
 * On congestion the target drops 15% (not below [floorKbps]); after [raiseAfterMs] without
 * congestion it rises 10% back towards [configuredKbps], then waits again. Dropping fast and
 * climbing slowly keeps the RTMP queue from filling up again right after it drained.
 */
internal class BitrateController(
    val configuredKbps: Int,
    private val floorKbps: Int = 1500,
    private val raiseAfterMs: Long = 10_000,
) {
    var targetKbps = configuredKbps
        private set
    private var calmSinceMs = -1L

    /** Returns the new target when it changed, else null. */
    fun onTick(nowMs: Long, congested: Boolean): Int? {
        if (calmSinceMs < 0) calmSinceMs = nowMs
        if (congested) {
            calmSinceMs = nowMs
            val lowered = maxOf(minOf(floorKbps, configuredKbps), targetKbps * 85 / 100)
            return change(lowered)
        }
        if (targetKbps >= configuredKbps || nowMs - calmSinceMs < raiseAfterMs) return null
        calmSinceMs = nowMs
        return change(minOf(configuredKbps, targetKbps * 110 / 100))
    }

    private fun change(kbps: Int): Int? {
        if (kbps == targetKbps) return null
        targetKbps = kbps
        return kbps
    }
}
