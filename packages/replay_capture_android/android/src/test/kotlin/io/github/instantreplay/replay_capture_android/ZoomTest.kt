package io.github.instantreplay.replay_capture_android

import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class ZoomTest {
    @Test
    fun `a ramp glides towards the target and lands on it`() {
        var z = 1f
        val seen = mutableListOf<Float>()
        repeat(40) {
            z = Zoom.step(z, 2f)
            seen += z
        }
        assertTrue(seen.zipWithNext().all { (a, b) -> b >= a }, "never overshoots or goes back")
        assertTrue(seen[0] < 1.5f, "the first step is gentle")
        assertEquals(2f, seen.last())
        assertEquals(1f, Zoom.step(1.005f, 1f), "snaps when close")
    }

    @Test
    fun `the crop region is centred and shrinks with the ratio`() {
        assertContentEquals(intArrayOf(0, 0, 4000, 3000), Zoom.cropRegion(0, 0, 4000, 3000, 1f))
        assertContentEquals(intArrayOf(1000, 750, 3000, 2250), Zoom.cropRegion(0, 0, 4000, 3000, 2f))
        assertContentEquals(intArrayOf(8, 4, 4008, 3004), Zoom.cropRegion(8, 4, 4000, 3000, 0.5f), "never below 1x")
    }
}
