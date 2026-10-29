package io.github.instantreplay.replay_capture_android

import android.os.PowerManager

/**
 * Staged degradation on overheating (SPEC §3.6). Actions only escalate during a session, so the
 * pipeline doesn't oscillate as the phone cools and heats again; [reset] at each start.
 */
internal class ThermalPolicy {
    private var applied = ThermalAction.NONE

    /** The action to apply for [status], or null if nothing new needs to happen. */
    fun onStatus(status: Int): ThermalAction? {
        val wanted = actionFor(status)
        if (wanted.ordinal <= applied.ordinal) return null
        applied = wanted
        return wanted
    }

    fun reset() {
        applied = ThermalAction.NONE
    }

    companion object {
        fun actionFor(status: Int): ThermalAction = when {
            status >= PowerManager.THERMAL_STATUS_EMERGENCY -> ThermalAction.STOP_LIVE
            status >= PowerManager.THERMAL_STATUS_CRITICAL -> ThermalAction.REDUCE_RESOLUTION
            status >= PowerManager.THERMAL_STATUS_SEVERE -> ThermalAction.REDUCE_FPS
            status >= PowerManager.THERMAL_STATUS_MODERATE -> ThermalAction.PREVIEW_OFF
            else -> ThermalAction.NONE
        }
    }
}
