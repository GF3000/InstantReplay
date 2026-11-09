package io.github.instantreplay.replay_capture_android.broadcast

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class BitrateControllerTest {

    @Test
    fun staysAtTargetWithoutCongestion() {
        val c = BitrateController(4500)
        for (t in 0L..60_000L step 1000) assertNull(c.onTick(t, congested = false))
        assertEquals(4500, c.targetKbps)
    }

    @Test
    fun dropsFifteenPercentPerCongestedTickDownToTheFloor() {
        val c = BitrateController(4500)
        assertEquals(3825, c.onTick(0, congested = true))
        assertEquals(3251, c.onTick(1000, congested = true))
        var t = 2000L
        while (c.onTick(t, congested = true) != null) t += 1000
        assertEquals(1500, c.targetKbps)
        assertNull(c.onTick(t + 1000, congested = true), "already at the floor")
    }

    @Test
    fun risesTenPercentAfterTenCalmSecondsBackToTheTarget() {
        val c = BitrateController(4500)
        c.onTick(0, congested = true) // 3825
        assertNull(c.onTick(5_000, congested = false))
        assertNull(c.onTick(9_000, congested = false))
        assertEquals(4207, c.onTick(10_000, congested = false))
        // Waits another 10 s before the next step.
        assertNull(c.onTick(15_000, congested = false))
        assertEquals(4500, c.onTick(20_000, congested = false), "capped at the configured target")
        assertNull(c.onTick(30_000, congested = false))
    }

    @Test
    fun congestionRestartsTheCalmPeriod() {
        val c = BitrateController(4500)
        c.onTick(0, congested = true)
        c.onTick(8_000, congested = true) // 3251, calm from 8 s
        assertNull(c.onTick(10_000, congested = false))
        assertEquals(3576, c.onTick(18_000, congested = false))
    }
}
