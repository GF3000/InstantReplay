package io.github.instantreplay.replay_capture_android.broadcast

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class MicLevelTest {

    private fun pcm(vararg samples: Int): ByteArray {
        val out = ByteArray(samples.size * 2)
        samples.forEachIndexed { i, s ->
            out[2 * i] = (s and 0xFF).toByte()
            out[2 * i + 1] = (s shr 8 and 0xFF).toByte()
        }
        return out
    }

    @Test
    fun silenceIsTheFloor() {
        assertEquals(MicLevelMeter.FLOOR_DB, MicLevelMeter.peakDbfs(ByteArray(2048), 2048))
    }

    @Test
    fun fullScaleIsZeroAndHalfIsMinusSix() {
        assertEquals(0.0, MicLevelMeter.peakDbfs(pcm(0, -32768, 100), 6), 1e-9)
        assertEquals(-6.02, MicLevelMeter.peakDbfs(pcm(10, 16384, -200), 6), 0.01)
        // Negative peaks count like positive ones.
        assertEquals(-6.02, MicLevelMeter.peakDbfs(pcm(10, -16384, 200), 6), 0.01)
    }

    @Test
    fun onlyTheBytesReadCount() {
        val b = pcm(100, 32767)
        assertEquals(20 * kotlin.math.log10(100 / 32768.0), MicLevelMeter.peakDbfs(b, 2), 1e-9)
    }

    @Test
    fun attackIsInstantAndReleaseIsSixtyDbPerSecond() {
        val m = MicLevelMeter()
        assertNull(m.read(0))
        m.update(pcm(16384), 2, 0)
        assertEquals(-6.02, m.read(0)!!, 0.01)
        // 300 ms later with no chunk: 18 dB lower.
        assertEquals(-24.02, m.read(300_000_000)!!, 0.01)
        // A quiet chunk does not pull the level below the release curve.
        m.update(pcm(10), 2, 100_000_000)
        assertEquals(-12.02, m.read(100_000_000)!!, 0.01)
        // A louder one jumps up at once.
        m.update(pcm(32767), 2, 200_000_000)
        assertEquals(0.0, m.read(200_000_000)!!, 0.01)
        // Never below the floor.
        assertEquals(MicLevelMeter.FLOOR_DB, m.read(60_000_000_000)!!)
    }
}
