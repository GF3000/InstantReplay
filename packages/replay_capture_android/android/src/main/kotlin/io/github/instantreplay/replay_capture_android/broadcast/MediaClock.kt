package io.github.instantreplay.replay_capture_android.broadcast

/**
 * Media time of a replay (SPEC §12.6): advances [speed] × wall time, so a speed change takes effect
 * from that moment without a jump. Wall time is passed in (ns) to keep it testable. Thread-safe.
 */
internal class MediaClock(speed: Float) {
    private var speed = speed
    private var positionUs = 0L
    private var lastNs = -1L

    /** Starts (or restarts) counting from media time 0 at [nowNs]. */
    @Synchronized
    fun start(nowNs: Long) {
        positionUs = 0
        lastNs = nowNs
    }

    /** Media position at [nowNs]; 0 before [start]. */
    @Synchronized
    fun positionUs(nowNs: Long): Long {
        if (lastNs < 0) return 0
        positionUs += ((nowNs - lastNs) / 1000.0 * speed).toLong()
        lastNs = nowNs
        return positionUs
    }

    /** Changes the speed from [nowNs] on: media time so far is kept. */
    @Synchronized
    fun setSpeed(speed: Float, nowNs: Long) {
        positionUs(nowNs)
        this.speed = speed
    }

    @Synchronized
    fun speed(): Float = speed

    companion object {
        /** Speeds a replay can run at; anything else snaps to the nearest. */
        val SPEEDS = floatArrayOf(0.25f, 0.5f, 1f)

        fun snap(speed: Float): Float = SPEEDS.minBy { kotlin.math.abs(it - speed) }
    }
}
