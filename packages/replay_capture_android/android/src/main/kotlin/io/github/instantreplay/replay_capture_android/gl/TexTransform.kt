package io.github.instantreplay.replay_capture_android.gl

/**
 * Camera2 tags SurfaceTexture outputs with a rotation meant for a preview in the device's natural
 * (portrait) orientation. We draw into landscape 16:9 targets, so applying that matrix as-is turns
 * and stretches the image. This strips the rotation, keeping the sensor's own landscape frame,
 * then applies [extraRotationDeg] (multiple of 90, clockwise) to make it upright for the UI.
 *
 * Matrices are 4×4 column-major, as returned by SurfaceTexture.getTransformMatrix.
 */
internal object TexTransform {

    /** Rotation that makes the raw sensor frame upright on a display rotated by [displayDeg]. */
    fun uprightRotation(sensorOrientation: Int, displayDeg: Int): Int =
        ((sensorOrientation - displayDeg) % 360 + 360) % 360

    fun normalize(st: FloatArray, extraRotationDeg: Int, out: FloatArray) {
        // Find the output-space rotation that leaves st with the plain "flip vertically" form
        // (s grows with x, t shrinks with y), i.e. no rotation left.
        var base = st
        for (k in 0 until 4) {
            val candidate = multiply(st, rotation(k * 90))
            if (candidate[0] > 0.5f && candidate[5] < -0.5f) {
                base = candidate
                break
            }
        }
        multiply(base, rotation(extraRotationDeg)).copyInto(out)
    }

    /** Rotation by [deg] (clockwise, multiple of 90) about the texture centre (0.5, 0.5). */
    internal fun rotation(deg: Int): FloatArray {
        val (c, s) = when ((deg % 360 + 360) % 360) {
            0 -> 1f to 0f
            90 -> 0f to 1f
            180 -> -1f to 0f
            270 -> 0f to -1f
            else -> error("Rotation must be a multiple of 90: $deg")
        }
        // x' = c·(x-.5) + s·(y-.5) + .5 ; y' = -s·(x-.5) + c·(y-.5) + .5
        return floatArrayOf(
            c, -s, 0f, 0f,
            s, c, 0f, 0f,
            0f, 0f, 1f, 0f,
            0.5f - 0.5f * c - 0.5f * s, 0.5f + 0.5f * s - 0.5f * c, 0f, 1f,
        )
    }

    internal fun multiply(a: FloatArray, b: FloatArray): FloatArray {
        val r = FloatArray(16)
        for (col in 0 until 4) {
            for (row in 0 until 4) {
                var sum = 0f
                for (i in 0 until 4) sum += a[i * 4 + row] * b[col * 4 + i]
                r[col * 4 + row] = sum
            }
        }
        return r
    }
}
