package io.github.instantreplay.replay_capture_android.mp4

import java.io.ByteArrayOutputStream
import java.io.DataOutputStream

/** H.264 track parameters needed to write an fMP4 init segment. */
data class TrackInfo(
    val width: Int,
    val height: Int,
    val sps: ByteArray,
    val pps: ByteArray,
    /** Clockwise display rotation written to the track matrix: 0 or 180 (landscape only). */
    val rotationDeg: Int = 0,
)

/** One encoded access unit in AVCC (length-prefixed) form. */
class Sample(val data: ByteArray, val durationTicks: Int, val isSync: Boolean)

/**
 * Minimal fragmented-MP4 writer for a single H.264 video track (no audio, no B-frames).
 *
 * Ring-buffer fragments are written once with [fragment]. A clip is built as
 * `init(duration) + sidx + fragments`, where each fragment is patched in place with
 * [patchFragment] so sequence numbers and decode times start at the clip origin.
 */
object Fmp4 {
    const val TIMESCALE = 90_000
    private const val TRACK_ID = 1

    // Byte offsets inside a fragment produced by [fragment]; see the layout in that function.
    internal const val MFHD_SEQUENCE_OFFSET = 20
    internal const val TFDT_DECODE_TIME_OFFSET = 60

    private const val SAMPLE_FLAGS_SYNC = 0x02000000
    private const val SAMPLE_FLAGS_NON_SYNC = 0x01010000

    private val UNITY_MATRIX = intArrayOf(0x00010000, 0, 0, 0, 0x00010000, 0, 0, 0, 0x40000000)

    fun usToTicks(us: Long): Long = us * TIMESCALE / 1_000_000

    /** ftyp + moov. [durationTicks] is 0 for an open-ended stream. */
    fun init(track: TrackInfo, durationTicks: Long = 0): ByteArray = BoxWriter().apply {
        box("ftyp") {
            fourcc("isom"); u32(0x200)
            fourcc("isom"); fourcc("iso6"); fourcc("avc1"); fourcc("mp41")
        }
        box("moov") {
            fullBox("mvhd", 0, 0) {
                u32(0); u32(0); u32(TIMESCALE); u32(durationTicks.toInt())
                u32(0x00010000); u16(0x0100); u16(0); u32(0); u32(0)
                UNITY_MATRIX.forEach { u32(it) }
                repeat(6) { u32(0) }
                u32(TRACK_ID + 1)
            }
            box("trak") {
                fullBox("tkhd", 0, 0x000003) {
                    u32(0); u32(0); u32(TRACK_ID); u32(0); u32(durationTicks.toInt())
                    u32(0); u32(0); u16(0); u16(0); u16(0); u16(0)
                    trackMatrix(track).forEach { u32(it) }
                    u32(track.width shl 16); u32(track.height shl 16)
                }
                box("mdia") {
                    fullBox("mdhd", 0, 0) {
                        u32(0); u32(0); u32(TIMESCALE); u32(durationTicks.toInt())
                        u16(0x55C4); u16(0) // language "und"
                    }
                    fullBox("hdlr", 0, 0) {
                        u32(0); fourcc("vide"); u32(0); u32(0); u32(0)
                        bytes("VideoHandler".toByteArray(Charsets.US_ASCII)); u8(0)
                    }
                    box("minf") {
                        fullBox("vmhd", 0, 1) { u16(0); u16(0); u16(0); u16(0) }
                        box("dinf") {
                            fullBox("dref", 0, 0) { u32(1); fullBox("url ", 0, 1) {} }
                        }
                        box("stbl") {
                            fullBox("stsd", 0, 0) { u32(1); avc1(track) }
                            fullBox("stts", 0, 0) { u32(0) }
                            fullBox("stsc", 0, 0) { u32(0) }
                            fullBox("stsz", 0, 0) { u32(0); u32(0) }
                            fullBox("stco", 0, 0) { u32(0) }
                        }
                    }
                }
            }
            box("mvex") {
                if (durationTicks > 0) fullBox("mehd", 0, 0) { u32(durationTicks.toInt()) }
                fullBox("trex", 0, 0) { u32(TRACK_ID); u32(1); u32(0); u32(0); u32(0) }
            }
        }
    }.toByteArray()

    /** ISO/IEC 14496-12 display matrix (16.16 fixed point, w in 2.30). */
    internal fun trackMatrix(track: TrackInfo): IntArray = when (track.rotationDeg) {
        0 -> UNITY_MATRIX
        180 -> intArrayOf(-0x10000, 0, 0, 0, -0x10000, 0, track.width shl 16, track.height shl 16, 0x40000000)
        else -> error("Unsupported track rotation ${track.rotationDeg}")
    }

    private fun BoxWriter.avc1(track: TrackInfo) = box("avc1") {
        zeros(6); u16(1)                    // reserved, data_reference_index
        u16(0); u16(0); zeros(12)           // pre_defined, reserved, pre_defined
        u16(track.width); u16(track.height)
        u32(0x00480000); u32(0x00480000)    // 72 dpi
        u32(0); u16(1); zeros(32)           // reserved, frame_count, compressorname
        u16(0x0018); u16(0xFFFF)            // depth, pre_defined
        box("avcC") {
            val sps = track.sps
            u8(1); u8(sps[1].toInt()); u8(sps[2].toInt()); u8(sps[3].toInt())
            u8(0xFF)                        // 4-byte NAL lengths
            u8(0xE1); u16(sps.size); bytes(sps)
            u8(1); u16(track.pps.size); bytes(track.pps)
            val profile = sps[1].toInt() and 0xFF
            if (profile == 100 || profile == 110 || profile == 122 || profile == 144) {
                // Hardware encoders emit 4:2:0 8-bit.
                u8(0xFD); u8(0xF8); u8(0xF8); u8(0)
            }
        }
    }

    /**
     * moof + mdat. Layout (offsets used by [patchFragment]):
     * moof(8) mfhd(8+4, seq@20) traf(8) tfhd(16) tfdt v1(8+4, time@60) trun mdat.
     */
    fun fragment(sequence: Int, baseDecodeTicks: Long, samples: List<Sample>): ByteArray {
        fun moof(dataOffset: Int) = BoxWriter().apply {
            box("moof") {
                fullBox("mfhd", 0, 0) { u32(sequence) }
                box("traf") {
                    fullBox("tfhd", 0, 0x020000) { u32(TRACK_ID) } // default-base-is-moof
                    fullBox("tfdt", 1, 0) { u64(baseDecodeTicks) }
                    fullBox("trun", 0, 0x000701) { // data-offset, duration, size, flags
                        u32(samples.size); u32(dataOffset)
                        for (s in samples) {
                            u32(s.durationTicks); u32(s.data.size)
                            u32(if (s.isSync) SAMPLE_FLAGS_SYNC else SAMPLE_FLAGS_NON_SYNC)
                        }
                    }
                }
            }
        }.toByteArray()

        val moofSize = moof(0).size
        val mdatSize = 8 + samples.sumOf { it.data.size }
        return BoxWriter().apply {
            bytes(moof(moofSize + 8))
            u32(mdatSize); fourcc("mdat")
            samples.forEach { bytes(it.data) }
        }.toByteArray()
    }

    /** Segment index so players can seek without scanning: one reference per fragment. */
    fun sidx(fragments: List<Pair<Int, Long>>): ByteArray = BoxWriter().apply {
        fullBox("sidx", 0, 0) {
            u32(TRACK_ID); u32(TIMESCALE); u32(0); u32(0)
            u16(0); u16(fragments.size)
            for ((size, durationTicks) in fragments) {
                u32(size and 0x7FFFFFFF); u32(durationTicks.toInt()); u32(0x90000000.toInt())
            }
        }
    }.toByteArray()

    fun patchFragment(fragment: ByteArray, sequence: Int, baseDecodeTicks: Long) {
        writeU32(fragment, MFHD_SEQUENCE_OFFSET, sequence)
        writeU32(fragment, TFDT_DECODE_TIME_OFFSET, (baseDecodeTicks ushr 32).toInt())
        writeU32(fragment, TFDT_DECODE_TIME_OFFSET + 4, baseDecodeTicks.toInt())
    }

    private fun writeU32(b: ByteArray, at: Int, v: Int) {
        b[at] = (v ushr 24).toByte(); b[at + 1] = (v ushr 16).toByte()
        b[at + 2] = (v ushr 8).toByte(); b[at + 3] = v.toByte()
    }
}

internal class BoxWriter {
    private val buffer = ByteArrayOutputStream()
    private val out = DataOutputStream(buffer)

    val size: Int get() = buffer.size()

    fun u8(v: Int) = out.writeByte(v)
    fun u16(v: Int) = out.writeShort(v)
    fun u32(v: Int) = out.writeInt(v)
    fun u64(v: Long) = out.writeLong(v)
    fun bytes(b: ByteArray) = out.write(b)
    fun zeros(n: Int) = repeat(n) { out.writeByte(0) }
    fun fourcc(s: String) = out.write(s.toByteArray(Charsets.US_ASCII))

    fun box(type: String, body: BoxWriter.() -> Unit) {
        val inner = BoxWriter().apply(body).toByteArray()
        u32(8 + inner.size); fourcc(type); bytes(inner)
    }

    fun fullBox(type: String, version: Int, flags: Int, body: BoxWriter.() -> Unit) =
        box(type) { u32((version shl 24) or flags); body() }

    fun toByteArray(): ByteArray = buffer.toByteArray()
}
