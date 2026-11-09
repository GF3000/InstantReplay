package io.github.instantreplay.replay_capture_android.broadcast

import kotlin.test.Test
import kotlin.test.assertEquals

class MediaClockTest {
    private val ms = 1_000_000L

    @Test
    fun `media time follows wall time times the speed`() {
        val clock = MediaClock(1f)
        assertEquals(0, clock.positionUs(5 * ms), "not started")
        clock.start(10 * ms)
        assertEquals(500_000, clock.positionUs(510 * ms))
    }

    @Test
    fun `a speed change keeps the position and only changes the pace`() {
        val clock = MediaClock(1f)
        clock.start(0)
        clock.setSpeed(0.5f, 1000 * ms) // 1 s of media at 1x
        assertEquals(1_000_000, clock.positionUs(1000 * ms))
        assertEquals(1_500_000, clock.positionUs(2000 * ms)) // then 1 s wall = 0.5 s media
        clock.setSpeed(0.25f, 2000 * ms)
        assertEquals(1_750_000, clock.positionUs(3000 * ms))
        assertEquals(0.25f, clock.speed())
    }

    @Test
    fun `speeds snap to the offered ones`() {
        assertEquals(0.5f, MediaClock.snap(0.6f))
        assertEquals(1f, MediaClock.snap(5f))
        assertEquals(0.25f, MediaClock.snap(0f))
    }
}
