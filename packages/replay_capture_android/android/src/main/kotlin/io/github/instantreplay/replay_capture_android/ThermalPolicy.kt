package io.github.instantreplay.replay_capture_android

import android.os.PowerManager

/**
 * Staged degradation on overheating (SPEC §3.6). Actions only escalate during a session, so the
 * pipeline doesn't oscillate as the phone cools and heats again; [reset] at each start.
 *
 * In broadcast mode (SPEC §12.1) the program stream is never degraded: fps and resolution
 * changes need a capture restart, which would cut the broadcast, so only the local preview and
 * the viewers' live view give way.
 */
internal class ThermalPolicy {
    private var applied = ThermalAction.NONE
    private var broadcast = false

    /** The action to apply for [status], or null if nothing new needs to happen. */
    fun onStatus(status: Int): ThermalAction? {
        val wanted = actionFor(status, broadcast)
        if (wanted.ordinal <= applied.ordinal) return null
        applied = wanted
        return wanted
    }

    fun reset(broadcast: Boolean = false) {
        applied = ThermalAction.NONE
        this.broadcast = broadcast
    }

    companion object {
        fun actionFor(status: Int, broadcast: Boolean = false): ThermalAction = if (broadcast) {
            when {
                status >= PowerManager.THERMAL_STATUS_CRITICAL -> ThermalAction.STOP_LIVE
                status >= PowerManager.THERMAL_STATUS_SEVERE -> ThermalAction.REDUCE_LIVE_BITRATE
                status >= PowerManager.THERMAL_STATUS_MODERATE -> ThermalAction.PREVIEW_OFF
                else -> ThermalAction.NONE
            }
        } else {
            when {
                status >= PowerManager.THERMAL_STATUS_EMERGENCY -> ThermalAction.STOP_LIVE
                status >= PowerManager.THERMAL_STATUS_CRITICAL -> ThermalAction.REDUCE_RESOLUTION
                status >= PowerManager.THERMAL_STATUS_SEVERE -> ThermalAction.REDUCE_FPS
                status >= PowerManager.THERMAL_STATUS_MODERATE -> ThermalAction.PREVIEW_OFF
                else -> ThermalAction.NONE
            }
        }
    }
}
