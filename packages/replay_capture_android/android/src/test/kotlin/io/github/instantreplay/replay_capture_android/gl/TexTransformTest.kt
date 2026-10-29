package io.github.instantreplay.replay_capture_android.gl

import kotlin.test.Test
import kotlin.test.assertEquals

class TexTransformTest {

    /** The usual SurfaceTexture matrix with no rotation: flip vertically. */
    private val flipY = floatArrayOf(
        1f, 0f, 0f, 0f,
        0f, -1f, 0f, 0f,
        0f, 0f, 1f, 0f,
        0f, 1f, 0f, 1f,
    )

    private fun apply(m: FloatArray, x: Float, y: Float) =
        (m[0] * x + m[4] * y + m[12]) to (m[1] * x + m[5] * y + m[13])

    private fun assertMaps(m: FloatArray, x: Float, y: Float, s: Float, t: Float) {
        val (a, b) = apply(m, x, y)
        assertEquals(s, a, 1e-5f, "s for ($x,$y)")
        assertEquals(t, b, 1e-5f, "t for ($x,$y)")
    }

    @Test
    fun plainMatrixIsUnchanged() {
        val out = FloatArray(16)
        TexTransform.normalize(flipY, 0, out)
        assertMaps(out, 0f, 0f, 0f, 1f)
        assertMaps(out, 1f, 1f, 1f, 0f)
    }

    @Test
    fun cameraRotationIsRemoved() {
        // What Camera2 adds for a 90° sensor: the plain flip composed with a 90° turn.
        for (k in 1..3) {
            val rotated = TexTransform.multiply(flipY, TexTransform.rotation(k * 90))
            val out = FloatArray(16)
            TexTransform.normalize(rotated, 0, out)
            assertMaps(out, 0f, 0f, 0f, 1f)
            assertMaps(out, 1f, 0f, 1f, 1f)
            assertMaps(out, 0f, 1f, 0f, 0f)
        }
    }

    @Test
    fun extraRotationOf180TurnsTheFrame() {
        val out = FloatArray(16)
        TexTransform.normalize(flipY, 180, out)
        assertMaps(out, 0f, 0f, 1f, 0f)
        assertMaps(out, 1f, 1f, 0f, 1f)
    }

    @Test
    fun uprightRotationForLandscapeLeft() {
        // Back cameras are usually mounted at 90°: raw frames are already upright in landscapeLeft.
        assertEquals(0, TexTransform.uprightRotation(sensorOrientation = 90, displayDeg = 90))
        assertEquals(180, TexTransform.uprightRotation(sensorOrientation = 270, displayDeg = 90))
    }
}
