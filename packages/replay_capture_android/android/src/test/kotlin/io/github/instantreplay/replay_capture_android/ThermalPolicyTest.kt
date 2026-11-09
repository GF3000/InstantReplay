package io.github.instantreplay.replay_capture_android

import android.os.PowerManager
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class ThermalPolicyTest {

    @Test
    fun mapsStatusToStagedActions() {
        assertEquals(ThermalAction.NONE, ThermalPolicy.actionFor(PowerManager.THERMAL_STATUS_LIGHT))
        assertEquals(ThermalAction.PREVIEW_OFF, ThermalPolicy.actionFor(PowerManager.THERMAL_STATUS_MODERATE))
        assertEquals(ThermalAction.REDUCE_FPS, ThermalPolicy.actionFor(PowerManager.THERMAL_STATUS_SEVERE))
        assertEquals(ThermalAction.REDUCE_RESOLUTION, ThermalPolicy.actionFor(PowerManager.THERMAL_STATUS_CRITICAL))
        assertEquals(ThermalAction.STOP_LIVE, ThermalPolicy.actionFor(PowerManager.THERMAL_STATUS_EMERGENCY))
        assertEquals(ThermalAction.STOP_LIVE, ThermalPolicy.actionFor(PowerManager.THERMAL_STATUS_SHUTDOWN))
    }

    @Test
    fun onlyEscalatesWithinASession() {
        val policy = ThermalPolicy()
        assertNull(policy.onStatus(PowerManager.THERMAL_STATUS_NONE))
        assertEquals(ThermalAction.REDUCE_FPS, policy.onStatus(PowerManager.THERMAL_STATUS_SEVERE))
        // Cooling down does not undo, and the same level is not re-applied.
        assertNull(policy.onStatus(PowerManager.THERMAL_STATUS_MODERATE))
        assertNull(policy.onStatus(PowerManager.THERMAL_STATUS_SEVERE))
        assertEquals(ThermalAction.STOP_LIVE, policy.onStatus(PowerManager.THERMAL_STATUS_EMERGENCY))
    }

    @Test
    fun broadcastModeNeverTouchesTheProgram() {
        // No fps or resolution change (a capture restart would cut the stream): only the
        // preview and the viewers' live view give way.
        val broadcast = { status: Int -> ThermalPolicy.actionFor(status, broadcast = true) }
        assertEquals(ThermalAction.NONE, broadcast(PowerManager.THERMAL_STATUS_LIGHT))
        assertEquals(ThermalAction.PREVIEW_OFF, broadcast(PowerManager.THERMAL_STATUS_MODERATE))
        assertEquals(ThermalAction.REDUCE_LIVE_BITRATE, broadcast(PowerManager.THERMAL_STATUS_SEVERE))
        assertEquals(ThermalAction.STOP_LIVE, broadcast(PowerManager.THERMAL_STATUS_CRITICAL))
        assertEquals(ThermalAction.STOP_LIVE, broadcast(PowerManager.THERMAL_STATUS_SHUTDOWN))

        val policy = ThermalPolicy().apply { reset(broadcast = true) }
        assertEquals(ThermalAction.REDUCE_LIVE_BITRATE, policy.onStatus(PowerManager.THERMAL_STATUS_SEVERE))
        policy.reset()
        assertEquals(ThermalAction.REDUCE_FPS, policy.onStatus(PowerManager.THERMAL_STATUS_SEVERE), "reset() is replay mode")
    }

    @Test
    fun resetStartsOver() {
        val policy = ThermalPolicy()
        policy.onStatus(PowerManager.THERMAL_STATUS_CRITICAL)
        policy.reset()
        assertEquals(ThermalAction.PREVIEW_OFF, policy.onStatus(PowerManager.THERMAL_STATUS_MODERATE))
    }
}
