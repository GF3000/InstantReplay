package io.github.instantreplay.replay_capture_android.buffer

import io.github.instantreplay.replay_capture_android.mp4.Fmp4
import io.github.instantreplay.replay_capture_android.mp4.Sample
import io.github.instantreplay.replay_capture_android.mp4.TrackInfo
import java.io.File
import java.nio.ByteBuffer
import java.nio.file.Files
import kotlin.concurrent.thread
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Buffer epochs (SPEC §3.1): a clip never mixes encoder sessions. */
class EpochTest {

    private val root: File = Files.createTempDirectory("ring").toFile()
    private val ring = RingBuffer(File(root, "ring"), windowUs = 80_000_000)

    private fun track(width: Int) = TrackInfo(
        width = width,
        height = 1080,
        sps = byteArrayOf(0x67, 100, 0, 40, 0x11, 0x22),
        pps = byteArrayOf(0x68, 0x33, 0x44),
    )

    @AfterTest
    fun tearDown() {
        root.deleteRecursively()
    }

    /** Appends 1 s fragments covering [fromS, toS) seconds in the current epoch (timestamps restart per epoch). */
    private fun fill(ring: RingBuffer, fromS: Int, toS: Int, epoch: Int = ring.epoch) {
        for (s in fromS until toS) {
            val startUs = s * 1_000_000L
            val endUs = startUs + 1_000_000L
            val base = Fmp4.usToTicks(startUs)
            val ticks = Fmp4.usToTicks(endUs) - base
            ring.append(
                sequence = s + 1,
                startUs = startUs,
                endUs = endUs,
                baseTicks = base,
                durationTicks = ticks,
                data = Fmp4.fragment(s + 1, base, listOf(Sample(ByteArray(16) { s.toByte() }, ticks.toInt(), true))),
                epoch = epoch,
            )
            ring.noteFrame(endUs - 33_333, epoch)
        }
    }

    private fun startEpoch(width: Int): Int {
        val epoch = ring.newEpoch()
        ring.track = track(width)
        return epoch
    }

    private fun widthOf(clip: File): Int {
        // avc1 stores width/height as u16 right after the sample entry header and 16 bytes of zeros.
        val bytes = clip.readBytes()
        val text = String(bytes, Charsets.ISO_8859_1)
        val at = text.indexOf("avc1", text.indexOf("stsd")) // ftyp may list "avc1" as a brand
        return ByteBuffer.wrap(bytes, at + 4 + 24, 2).short.toInt() and 0xffff
    }

    @Test
    fun resetAndNewEpochIncrement() {
        val first = ring.epoch
        assertEquals(first + 1, ring.newEpoch())
        ring.reset()
        assertEquals(first + 2, ring.epoch)
        assertEquals(-1, ring.cursor().ptsUs)
        assertNull(ring.track)
    }

    @Test
    fun fragmentsCarryTheirEpoch() {
        val e1 = startEpoch(1280)
        fill(ring, 0, 3)
        val e2 = startEpoch(1920)
        fill(ring, 0, 2)

        assertEquals(listOf(e1, e1, e1), ring.select(e1, 0, Long.MAX_VALUE).map { it.epoch })
        assertEquals(listOf(e2, e2), ring.select(e2, 0, Long.MAX_VALUE).map { it.epoch })
        // Same timestamps, different epochs: no file name collision.
        assertTrue(ring.select(e1, 0, 1).single().file.exists())
        assertTrue(ring.select(e2, 0, 1).single().file.exists())
        assertEquals(1280, ring.trackFor(e1)?.width)
        assertEquals(1920, ring.trackFor(e2)?.width)
    }

    @Test
    fun clipIsTruncatedToNewestEpoch() {
        startEpoch(1280)
        fill(ring, 0, 30)
        startEpoch(1920)
        fill(ring, 0, 4) // timestamps restart at 0

        val target = File(root, "clip.mp4")
        val a = ClipAssembler(ring).mark(preSeconds = 20.0, postSeconds = 0.0).assemble(target)

        assertEquals(4, a.fragments)
        assertEquals(4000, a.durationMs)
        assertEquals(1920, widthOf(target))
        assertTrue(target.exists())
        assertTrue(!File(target.path + ".part").exists())
    }

    @Test
    fun pendingClipStopsWaitingWhenEpochEnds() {
        startEpoch(1280)
        fill(ring, 0, 10)
        val job = ClipAssembler(ring, graceMs = 10_000).mark(preSeconds = 3.0, postSeconds = 30.0)

        thread {
            Thread.sleep(200)
            startEpoch(1920)
            fill(ring, 0, 40) // would satisfy the post-roll if epochs were mixed
        }
        val started = System.nanoTime()
        val target = File(root, "clip.mp4")
        val a = job.assemble(target)

        assertTrue((System.nanoTime() - started) / 1_000_000 < 5_000, "should not wait for the timeout")
        // Window [~6.97 s, 10 s) of the old epoch only.
        assertEquals(4, a.fragments)
        assertEquals(1280, widthOf(target))
    }

    @Test
    fun staleEpochWritesAreIgnored() {
        val e1 = startEpoch(1280)
        fill(ring, 0, 2)
        val e2 = startEpoch(1920)
        fill(ring, 2, 4, epoch = e1) // late output of the stopped encoder
        ring.noteFrame(99_000_000, e1)

        assertEquals(2, ring.select(e1, 0, Long.MAX_VALUE).size)
        assertEquals(0, ring.select(e2, 0, Long.MAX_VALUE).size)
        assertEquals(RingBuffer.Cursor(e2, -1), ring.cursor())
    }

    @Test
    fun windowEvictsOldEpochsAndTheirTracks() {
        val small = RingBuffer(File(root, "small"), windowUs = 5_000_000)
        val e1 = small.newEpoch().also { small.track = track(1280) }
        fill(small, 0, 4)
        val e2 = small.newEpoch().also { small.track = track(1920) }
        fill(small, 0, 3)
        assertEquals(listOf(e1, e1, e2, e2, e2), small.select(e1, 0, Long.MAX_VALUE).map { it.epoch } +
            small.select(e2, 0, Long.MAX_VALUE).map { it.epoch })
        assertEquals(5000L, small.stats()["bufferMs"])

        fill(small, 3, 5)
        assertEquals(0, small.select(e1, 0, Long.MAX_VALUE).size)
        assertNull(small.trackFor(e1))
        assertEquals(1920, small.trackFor(e2)?.width)
    }

    @Test
    fun segmenterRestartsSequencePerEpoch() {
        val e1 = startEpoch(1280)
        val segmenter = Segmenter(ring, frameIntervalUs = 500_000)
        val frame = byteArrayOf(0, 0, 0, 1, 0x65)
        // Keyframe every second, timestamps on an arbitrary clock.
        for (i in 0..4) segmenter.onFrame(50_000_000L + i * 500_000, isKeyframe = i % 2 == 0, avcc = frame)
        assertEquals(listOf(1, 2), ring.select(e1, 0, Long.MAX_VALUE).map { it.sequence })

        val e2 = startEpoch(1920)
        for (i in 0..4) segmenter.onFrame(1_000L + i * 500_000, isKeyframe = i % 2 == 0, avcc = frame)
        val fragments = ring.select(e2, 0, Long.MAX_VALUE)
        assertEquals(listOf(1, 2), fragments.map { it.sequence })
        assertEquals(0L, fragments.first().baseTicks) // decode time restarts with the epoch
        assertEquals(e2, ring.cursor().epoch)
        assertEquals(1_000L + 4 * 500_000, ring.cursor().ptsUs)
    }
}
