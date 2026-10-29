package io.github.instantreplay.replay_capture_android.mp4

import java.nio.ByteBuffer
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals

class Fmp4Test {

    private fun u32(b: ByteArray, at: Int) = ByteBuffer.wrap(b, at, 4).int
    private fun u64(b: ByteArray, at: Int) = ByteBuffer.wrap(b, at, 8).long
    private fun type(b: ByteArray, at: Int) = String(b, at, 4, Charsets.US_ASCII)

    private val track = TrackInfo(
        width = 1920,
        height = 1080,
        sps = byteArrayOf(0x67, 100, 0, 40, 0x11, 0x22),
        pps = byteArrayOf(0x68, 0x33, 0x44),
    )

    @Test
    fun fragmentLayoutMatchesPatchOffsets() {
        val samples = listOf(
            Sample(ByteArray(10) { 1 }, 3000, isSync = true),
            Sample(ByteArray(7) { 2 }, 3000, isSync = false),
        )
        val frag = Fmp4.fragment(sequence = 42, baseDecodeTicks = 123_456_789_000L, samples = samples)

        assertEquals("moof", type(frag, 4))
        assertEquals("mfhd", type(frag, 12))
        assertEquals("traf", type(frag, 28))
        assertEquals("tfhd", type(frag, 36))
        assertEquals("tfdt", type(frag, 52))
        assertEquals(42, u32(frag, Fmp4.MFHD_SEQUENCE_OFFSET))
        assertEquals(123_456_789_000L, u64(frag, Fmp4.TFDT_DECODE_TIME_OFFSET))

        // trun data_offset points at the first sample byte inside mdat.
        val moofSize = u32(frag, 0)
        val trunAt = 48 + u32(frag, 48) // tfdt starts at 48
        assertEquals("trun", type(frag, trunAt + 4))
        val dataOffset = u32(frag, trunAt + 16)
        assertEquals(moofSize + 8, dataOffset)
        assertEquals("mdat", type(frag, moofSize + 4))
        assertEquals(1.toByte(), frag[dataOffset])
        assertEquals(frag.size, moofSize + u32(frag, moofSize))

        Fmp4.patchFragment(frag, sequence = 1, baseDecodeTicks = 90_000)
        assertEquals(1, u32(frag, Fmp4.MFHD_SEQUENCE_OFFSET))
        assertEquals(90_000L, u64(frag, Fmp4.TFDT_DECODE_TIME_OFFSET))
    }

    @Test
    fun initBoxSizesAreConsistent() {
        val init = Fmp4.init(track, durationTicks = 900_000)
        val ftypSize = u32(init, 0)
        assertEquals("ftyp", type(init, 4))
        assertEquals("moov", type(init, ftypSize + 4))
        assertEquals(init.size, ftypSize + u32(init, ftypSize))
    }

    @Test
    fun rotationIsWrittenToTheTrackMatrix() {
        assertContentEquals(intArrayOf(0x10000, 0, 0, 0, 0x10000, 0, 0, 0, 0x40000000), Fmp4.trackMatrix(track))
        val upsideDown = Fmp4.trackMatrix(track.copy(rotationDeg = 180))
        assertEquals(-0x10000, upsideDown[0])
        assertEquals(-0x10000, upsideDown[4])
        assertEquals(1920 shl 16, upsideDown[6])
        assertEquals(1080 shl 16, upsideDown[7])
    }

    @Test
    fun sidxHasOneReferencePerFragment() {
        val sidx = Fmp4.sidx(listOf(1000 to 90_000L, 2000 to 90_000L))
        assertEquals("sidx", type(sidx, 4))
        assertEquals(sidx.size, u32(sidx, 0))
        assertEquals(2, ByteBuffer.wrap(sidx, 30, 2).short.toInt())
    }

    @Test
    fun annexBToAvccStripsParameterSets() {
        val annexB = byteArrayOf(
            0, 0, 0, 1, 0x67, 1, 2,      // SPS (dropped)
            0, 0, 0, 1, 0x68, 3,         // PPS (dropped)
            0, 0, 1, 0x65, 9, 9, 9,      // IDR slice, 3-byte start code
        )
        val avcc = Avc.toAvcc(ByteBuffer.wrap(annexB))
        assertContentEquals(byteArrayOf(0, 0, 0, 4, 0x65, 9, 9, 9), avcc)
    }

    @Test
    fun parameterSetStripsStartCode() {
        val csd = ByteBuffer.wrap(byteArrayOf(0, 0, 0, 1, 0x67, 100, 0, 40))
        assertContentEquals(byteArrayOf(0x67, 100, 0, 40), Avc.parameterSet(csd))
    }
}
