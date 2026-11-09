package io.github.instantreplay.replay_capture_android

import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * Camera zoom (SPEC §3.1): a sensor-level zoom, so the clips, the recording and the broadcast all
 * get it. Changes glide over a few frames instead of jumping, because it can change on air.
 */
internal object Zoom {
    /** Fraction of the remaining distance covered per step (one step per frame at ~30 fps). */
    private const val EASE = 0.25f

    /** Closer than this to the target, the ramp snaps to it and stops. */
    private const val SNAP = 0.01f

    /** Next zoom on the way from [current] to [target]; equals [target] when close enough. */
    fun step(current: Float, target: Float): Float {
        val next = current + (target - current) * EASE
        return if (abs(target - next) < SNAP) target else next
    }

    /**
     * Crop region `[left, top, right, bottom]` for [ratio], centred in the sensor's active array:
     * the pre-Android 11 way (`SCALER_CROP_REGION`), when `CONTROL_ZOOM_RATIO` does not exist.
     */
    fun cropRegion(left: Int, top: Int, width: Int, height: Int, ratio: Float): IntArray {
        val r = ratio.coerceAtLeast(1f)
        val w = (width / r).roundToInt()
        val h = (height / r).roundToInt()
        val l = left + (width - w) / 2
        val t = top + (height - h) / 2
        return intArrayOf(l, t, l + w, t + h)
    }
}
