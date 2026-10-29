package io.github.instantreplay.replay_capture_android.mp4

import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer

/** H.264 Annex-B helpers. */
object Avc {
    private const val NAL_SPS = 7
    private const val NAL_PPS = 8
    private const val NAL_AUD = 9

    /** Splits an Annex-B buffer into NAL units without start codes. */
    fun splitNals(data: ByteArray): List<ByteArray> {
        val nals = ArrayList<ByteArray>()
        var i = 0
        var start = -1
        while (i + 2 < data.size) {
            if (data[i].toInt() == 0 && data[i + 1].toInt() == 0 && data[i + 2].toInt() == 1) {
                if (start >= 0) nals += data.copyOfRange(start, trimZeros(data, start, i))
                i += 3
                start = i
            } else {
                i++
            }
        }
        if (start >= 0 && start < data.size) nals += data.copyOfRange(start, data.size)
        else if (start < 0 && data.isNotEmpty()) nals += data // already a bare NAL
        return nals
    }

    // A 4-byte start code leaves one extra zero at the end of the previous NAL.
    private fun trimZeros(data: ByteArray, start: Int, end: Int): Int {
        var e = end
        while (e > start && data[e - 1].toInt() == 0) e--
        return e
    }

    /** Annex-B access unit → AVCC sample, dropping in-band SPS/PPS/AUD (they live in avcC). */
    fun toAvcc(buffer: ByteBuffer): ByteArray {
        val raw = ByteArray(buffer.remaining()).also { buffer.get(it) }
        val out = ByteArrayOutputStream(raw.size + 16)
        for (nal in splitNals(raw)) {
            if (nal.isEmpty()) continue
            val type = nal[0].toInt() and 0x1F
            if (type == NAL_SPS || type == NAL_PPS || type == NAL_AUD) continue
            out.write(nal.size ushr 24); out.write(nal.size ushr 16)
            out.write(nal.size ushr 8); out.write(nal.size)
            out.write(nal)
        }
        return out.toByteArray()
    }

    /** csd-0 / csd-1 from MediaFormat → first NAL without start code. */
    fun parameterSet(buffer: ByteBuffer): ByteArray {
        val raw = ByteArray(buffer.remaining()).also { buffer.duplicate().get(it) }
        return splitNals(raw).first()
    }
}
