package io.github.instantreplay.replay_capture_android.broadcast

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class StreamClockTest {

    @Test
    fun startsAtTheFirstVideoKeyframe() {
        val clock = StreamClock()
        assertNull(clock.audio(5_000_000), "audio before the stream starts is dropped")
        assertNull(clock.video(5_000_000, keyframe = false), "waits for a keyframe")
        assertFalse(clock.started)
        assertEquals(0L, clock.video(5_033_333, keyframe = true))
        assertTrue(clock.started)
        assertEquals(33_334L, clock.video(5_066_667, keyframe = false))
        // Audio shares the base: same monotonic clock.
        assertEquals(10_000L, clock.audio(5_043_333))
    }

    @Test
    fun dropsWhatWouldGoBackwards() {
        val clock = StreamClock()
        clock.video(1_000_000, keyframe = true)
        assertNull(clock.audio(999_000), "captured before the stream start")
        assertEquals(20_000L, clock.audio(1_020_000))
        assertNull(clock.audio(1_020_000), "not increasing")
        assertNull(clock.audio(1_010_000))
        assertEquals(33_000L, clock.video(1_033_000, keyframe = false))
        assertNull(clock.video(1_033_000, keyframe = false))
    }

    @Test
    fun resetStartsANewTimelineAtTheNextKeyframe() {
        val clock = StreamClock()
        clock.video(1_000_000, keyframe = true)
        clock.video(9_000_000, keyframe = false)
        clock.reset()
        assertNull(clock.video(10_000_000, keyframe = false))
        assertNull(clock.audio(10_010_000))
        assertEquals(0L, clock.video(10_033_000, keyframe = true))
        assertEquals(1_000L, clock.audio(10_034_000))
    }
}

class AudioClockTest {
    private val chunk = 1024
    private val chunkUs = 1024 * 1_000_000L / 48_000 // 21_333 µs

    @Test
    fun firstChunkIsStampedAtCaptureTime() {
        val clock = AudioClock(48_000)
        // Read finished at 1 s: the chunk started one chunk duration earlier.
        assertEquals(1_000_000L - chunkUs, clock.next(1_000_000_000L, chunk))
    }

    @Test
    fun followingChunksAreEvenlySpacedDespiteJitter() {
        val clock = AudioClock(48_000)
        val first = clock.next(1_000_000_000L, chunk)
        // Reads complete a few ms late or early; timestamps still advance by exactly one chunk.
        val second = clock.next(1_000_000_000L + chunkUs * 1000 + 5_000_000, chunk)
        val third = clock.next(1_000_000_000L + 2 * chunkUs * 1000 - 3_000_000, chunk)
        assertEquals(first + 1024 * 1_000_000L / 48_000, second)
        assertEquals(first + 2048 * 1_000_000L / 48_000, third)
    }

    @Test
    fun reanchorsAfterAStall() {
        val clock = AudioClock(48_000)
        clock.next(1_000_000_000L, chunk)
        // Half a second lost: far beyond the drift tolerance, so it follows the read time again.
        val readEndNs = 1_000_000_000L + chunkUs * 1000 + 500_000_000
        assertEquals(readEndNs / 1000 - chunkUs, clock.next(readEndNs, chunk))
    }
}
