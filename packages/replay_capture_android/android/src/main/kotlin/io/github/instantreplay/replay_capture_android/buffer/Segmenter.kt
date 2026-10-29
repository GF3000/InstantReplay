package io.github.instantreplay.replay_capture_android.buffer

import io.github.instantreplay.replay_capture_android.mp4.Fmp4
import io.github.instantreplay.replay_capture_android.mp4.Sample

/**
 * Groups encoded frames into one fMP4 fragment per GOP (each fragment starts on a keyframe)
 * and appends them to the [RingBuffer]. Called on the encoder output thread.
 */
internal class Segmenter(private val ring: RingBuffer, private val frameIntervalUs: Long) {

    private class Pending(val ptsUs: Long, val isSync: Boolean, val data: ByteArray)

    private val pending = ArrayList<Pending>()
    private var epochStartUs = -1L
    private var sequence = 0

    @Volatile var frames = 0L
        private set
    /** Frame intervals longer than 1.5× nominal: frames the camera or encoder dropped. */
    @Volatile var gaps = 0L
        private set
    @Volatile var droppedBeforeKeyframe = 0L
        private set

    fun onFrame(ptsUs: Long, isKeyframe: Boolean, avcc: ByteArray) {
        if (ring.track == null) return
        if (epochStartUs < 0) {
            if (!isKeyframe) {
                droppedBeforeKeyframe++
                return
            }
            epochStartUs = ptsUs
        }
        pending.lastOrNull()?.let { prev ->
            if (ptsUs - prev.ptsUs > frameIntervalUs * 3 / 2) gaps++
            if (ptsUs <= prev.ptsUs) return // non-monotonic PTS; drop
        }
        if (isKeyframe && pending.isNotEmpty()) flush(endUs = ptsUs)
        pending += Pending(ptsUs, isKeyframe, avcc)
        frames++
        ring.noteFrame(ptsUs)
    }

    private fun flush(endUs: Long) {
        val samples = pending.mapIndexed { i, s ->
            val nextUs = if (i + 1 < pending.size) pending[i + 1].ptsUs else endUs
            val duration = (ticks(nextUs) - ticks(s.ptsUs)).coerceAtLeast(1)
            Sample(s.data, duration.toInt(), s.isSync)
        }
        val startUs = pending.first().ptsUs
        val baseTicks = ticks(startUs)
        sequence++
        ring.append(
            sequence = sequence,
            startUs = startUs,
            endUs = endUs,
            baseTicks = baseTicks,
            durationTicks = ticks(endUs) - baseTicks,
            data = Fmp4.fragment(sequence, baseTicks, samples),
        )
        pending.clear()
    }

    // Decode times are relative to the start of this encoder session (epoch).
    private fun ticks(us: Long) = Fmp4.usToTicks(us - epochStartUs)
}
