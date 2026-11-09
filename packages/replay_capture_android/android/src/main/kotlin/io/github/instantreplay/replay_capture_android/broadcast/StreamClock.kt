package io.github.instantreplay.replay_capture_android.broadcast

/**
 * Rebases video and audio timestamps to the start of the RTMP stream (SPEC §12.1).
 *
 * Both inputs are in µs on `CLOCK_MONOTONIC` (SurfaceTexture timestamps and `System.nanoTime`),
 * so one offset serves both tracks. The stream starts at the first video keyframe offered after
 * [reset]; earlier frames, and anything that would go backwards on its track, are dropped (null).
 * Reset on every (re)connection so each RTMP session starts at 0 with a keyframe.
 *
 * Thread-safe: video and audio arrive on their encoders' threads.
 */
internal class StreamClock {
    private var startUs = NONE
    private var lastVideoUs = NONE
    private var lastAudioUs = NONE

    @get:Synchronized val started: Boolean get() = startUs != NONE

    @Synchronized
    fun reset() {
        startUs = NONE
        lastVideoUs = NONE
        lastAudioUs = NONE
    }

    /** Rebased PTS for a video frame, or null to drop it. */
    @Synchronized
    fun video(ptsUs: Long, keyframe: Boolean): Long? {
        if (startUs == NONE) {
            if (!keyframe) return null
            startUs = ptsUs
        }
        val t = ptsUs - startUs
        if (t < 0 || t <= lastVideoUs) return null
        lastVideoUs = t
        return t
    }

    /** Rebased PTS for an audio frame, or null to drop it (stream not started, or out of order). */
    @Synchronized
    fun audio(ptsUs: Long): Long? {
        if (startUs == NONE) return null
        val t = ptsUs - startUs
        if (t < 0 || t <= lastAudioUs) return null
        lastAudioUs = t
        return t
    }

    private companion object {
        const val NONE = Long.MIN_VALUE
    }
}

/**
 * Timestamps for consecutive PCM chunks. Counted from samples so AAC frames are evenly spaced
 * (read-time jitter would otherwise show up as audio jitter), anchored to the monotonic time the
 * chunk was captured: read completion minus the chunk's own duration. Re-anchors when the count
 * drifts more than [maxDriftUs] from the read time, e.g. after a stall or dropped audio.
 */
internal class AudioClock(private val sampleRate: Int, private val maxDriftUs: Long = 40_000) {
    private var anchorUs = 0L
    private var samples = -1L

    /** PTS in µs of a chunk of [chunkSamples] samples whose read finished at [readEndNs]. */
    fun next(readEndNs: Long, chunkSamples: Int): Long {
        val measuredUs = readEndNs / 1000 - chunkSamples * 1_000_000L / sampleRate
        if (samples >= 0) {
            val expectedUs = anchorUs + samples * 1_000_000L / sampleRate
            if (kotlin.math.abs(expectedUs - measuredUs) <= maxDriftUs) {
                samples += chunkSamples
                return expectedUs
            }
        }
        anchorUs = measuredUs
        samples = chunkSamples.toLong()
        return measuredUs
    }
}
