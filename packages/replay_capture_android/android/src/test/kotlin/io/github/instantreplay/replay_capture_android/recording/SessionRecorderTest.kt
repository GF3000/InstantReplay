package io.github.instantreplay.replay_capture_android.recording

import io.github.instantreplay.replay_capture_android.FlutterError
import io.github.instantreplay.replay_capture_android.RecordingEnd
import io.github.instantreplay.replay_capture_android.RecordingSaved
import io.github.instantreplay.replay_capture_android.RecordingState
import io.github.instantreplay.replay_capture_android.RecordingStatus
import io.github.instantreplay.replay_capture_android.buffer.RingBuffer
import io.github.instantreplay.replay_capture_android.mp4.Fmp4
import io.github.instantreplay.replay_capture_android.mp4.Sample
import io.github.instantreplay.replay_capture_android.mp4.TrackInfo
import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.file.Files
import java.util.Collections
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Full-session recording (SPEC §3.8) against a real ring buffer and plain files. */
class SessionRecorderTest {

    private val root: File = Files.createTempDirectory("recorder").toFile()
    private val gallery = File(root, "gallery")
    private val stateDir = File(root, "state")
    private val ring = RingBuffer(File(root, "ring"), windowUs = 60_000_000)
    @Volatile private var free = 10L shl 30
    private val statuses: MutableList<RecordingStatus> = Collections.synchronizedList(mutableListOf())
    private val saved: MutableList<RecordingSaved> = Collections.synchronizedList(mutableListOf())
    private val recorders = mutableListOf<SessionRecorder>()

    /** Parts are `<name>.pending` until published, then `<name>`. */
    private class FilePartStore(private val dir: File) : PartStore {
        override fun create(displayName: String): PartSink {
            dir.mkdirs()
            return open(File(dir, "$displayName.pending").also { it.createNewFile() }.path, displayName)!!
        }

        override fun open(id: String, displayName: String): PartSink? {
            val file = File(id)
            if (!file.isFile) return null
            return object : ChannelPartSink(RandomAccessFile(file, "rw").channel) {
                override val name = displayName
                override val id = id

                override fun publish() {
                    close()
                    check(file.renameTo(File(dir, displayName)))
                }

                override fun discard() {
                    close()
                    file.delete()
                }
            }
        }
    }

    private fun recorder(maxFragments: Int = SessionRecorder.MAX_FRAGMENTS_PER_PART) = SessionRecorder(
        store = FilePartStore(gallery),
        stateDir = stateDir,
        freeBytes = { free },
        clock = { 1_793_000_000_000L },
        maxFragmentsPerPart = maxFragments,
        onStatus = { statuses += it },
        onSaved = { saved += it },
    ).also {
        recorders += it
        it.attach(ring, 8_000_000)
    }

    @AfterTest
    fun tearDown() {
        recorders.forEach { it.release() }
        root.deleteRecursively()
    }

    private fun <T> await(call: ((Result<T>) -> Unit) -> Unit): T {
        val done = CountDownLatch(1)
        var result: Result<T>? = null
        call {
            result = it
            done.countDown()
        }
        assertTrue(done.await(10, TimeUnit.SECONDS), "call did not complete")
        return result!!.getOrThrow()
    }

    private fun startEpoch(width: Int = 1920): Int {
        val epoch = ring.newEpoch()
        ring.track = TrackInfo(width, 1080, byteArrayOf(0x67, 100, 0, 40, 0x11), byteArrayOf(0x68, 0x33))
        return epoch
    }

    /** Closes the 1 s fragment [s, s+1) of the current epoch; the encoder is then at [s+1, s+1.5]. */
    private fun fragment(s: Int, size: Int = 32) {
        val startUs = s * 1_000_000L
        val endUs = startUs + 1_000_000L
        val base = Fmp4.usToTicks(startUs)
        val ticks = Fmp4.usToTicks(endUs) - base
        ring.noteFrame(endUs)
        ring.append(s + 1, startUs, endUs, base, ticks, Fmp4.fragment(s + 1, base, listOf(Sample(ByteArray(size) { s.toByte() }, ticks.toInt(), true))))
        ring.noteFrame(endUs + 500_000)
    }

    private fun fragments(from: Int, to: Int) = (from until to).forEach { fragment(it) }

    private companion object {
        val NAME = Regex("""InstantReplay_\d{4}-\d{2}-\d{2}_\d{2}-\d{2}\.mp4""")
    }

    // region MP4 parsing

    private class Box(val type: String, val at: Int, val size: Int)

    private fun boxes(b: ByteArray): List<Box> {
        val out = ArrayList<Box>()
        var at = 0
        while (at < b.size) {
            val size = u32(b, at)
            assertTrue(size >= 8 && at + size <= b.size, "bad box at $at")
            out += Box(String(b, at + 4, 4, Charsets.US_ASCII), at, size)
            at += size
        }
        return out
    }

    private fun u32(b: ByteArray, at: Int) = ByteBuffer.wrap(b, at, 4).int
    private fun u64(b: ByteArray, at: Int) = ByteBuffer.wrap(b, at, 8).long

    /** Payload byte of each fragment (its source second) and its patched (sequence, tfdt). */
    private fun moofs(b: ByteArray): List<Triple<Int, Int, Long>> = boxes(b).filter { it.type == "moof" }.map { m ->
        val mdat = m.at + m.size
        Triple(b[mdat + 8].toInt(), u32(b, m.at + Fmp4.MFHD_SEQUENCE_OFFSET), u64(b, m.at + Fmp4.TFDT_DECODE_TIME_OFFSET))
    }

    /** `mehd` fragment_duration. */
    private fun mehd(b: ByteArray): Int {
        val text = String(b, Charsets.ISO_8859_1)
        return u32(b, text.indexOf("mehd") + 8)
    }

    private fun published(): List<File> = gallery.listFiles().orEmpty().filter { !it.name.endsWith(".pending") }.sortedBy { it.name }

    // endregion

    @Test
    fun finalizedPartIsAValidSeekableFile() {
        startEpoch()
        val r = recorder()
        fragment(0)
        await { r.start(0, it) }
        fragments(1, 5) // 2, 3, 4
        val result = assertNotNull(await<RecordingSaved?> { r.stop(it) })

        val file = published().single()
        assertTrue(NAME.matches(file.name), file.name)
        val bytes = file.readBytes()
        val list = boxes(bytes)
        assertEquals(listOf("ftyp", "moov", "sidx", "free") + List(3) { listOf("moof", "mdat") }.flatten(), list.map { it.type })
        assertEquals(3 * 90_000, mehd(bytes))

        val sidx = list[2]
        val free = list[3]
        assertEquals(free.size, u32(bytes, sidx.at + 24)) // first_offset skips the free box
        assertEquals(list[4].at, sidx.at + sidx.size + u32(bytes, sidx.at + 24))
        assertEquals(3, ByteBuffer.wrap(bytes, sidx.at + 30, 2).short.toInt())
        assertEquals(list[4].size + list[5].size, u32(bytes, sidx.at + 32) and 0x7FFFFFFF)

        assertEquals(RecordingEnd.USER, result.reason)
        assertEquals(1, result.parts)
        assertEquals(3000, result.durationMs)
        assertEquals(bytes.size.toLong(), result.bytes)
        assertEquals(file.name, result.name)
        assertEquals(listOf(result), saved)
        assertEquals(RecordingState.IDLE, statuses.last().state)
        assertEquals(0, statuses.last().elapsedMs)
        assertTrue(stateDir.listFiles().orEmpty().isEmpty(), "journal cleaned up")
    }

    @Test
    fun startSkipsTheFragmentInProgress() {
        startEpoch()
        val r = recorder()
        fragment(0) // encoder now at 1.5 s, inside [1, 2)
        await { r.start(0, it) }
        fragments(1, 4)
        await { r.stop(it) }
        assertEquals(listOf(2, 3), moofs(published().single().readBytes()).map { it.first })
    }

    @Test
    fun timelineIsContinuousAcrossAPause() {
        startEpoch()
        val r = recorder()
        fragment(0)
        await { r.start(0, it) }
        fragments(1, 4) // writes 2, 3; encoder in [4, 5)
        assertEquals(RecordingState.PAUSED, await { r.pause(it) }.state)
        fragments(4, 8) // 4 was in progress: written; 5..7 dropped
        await { r.start(0, it) } // encoder in [8, 9): skipped
        fragments(8, 11)
        await { r.stop(it) }

        val moofs = moofs(published().single().readBytes())
        assertEquals(listOf(2, 3, 4, 9, 10), moofs.map { it.first })
        assertEquals(listOf(1, 2, 3, 4, 5), moofs.map { it.second })
        assertEquals((0L until 5L).map { it * 90_000 }, moofs.map { it.third })
    }

    @Test
    fun pauseKeepsTheFragmentInProgress() {
        startEpoch()
        val r = recorder()
        fragment(0)
        await { r.start(0, it) }
        fragments(1, 3) // 2
        await { r.pause(it) } // encoder in [3, 4)
        fragments(3, 6)
        r.sync()
        assertEquals(2000, assertNotNull(r.status()).elapsedMs)
        await { r.stop(it) }
        assertEquals(listOf(2, 3), moofs(published().single().readBytes()).map { it.first })
    }

    @Test
    fun includeSecondsBackfillsWithoutDuplicates() {
        startEpoch()
        val r = recorder()
        fragments(0, 10) // encoder in [10, 11)
        await { r.start(3, it) } // from 7.5 s: fragments 8, 9 and then the one in progress
        fragments(10, 12)
        await { r.pause(it) } // encoder in [12, 13)
        fragments(12, 16)
        await { r.start(5, it) } // encoder in [16, 17): backfill from 11.5 s, 12 already written
        fragments(16, 18)
        await { r.stop(it) }

        val moofs = moofs(published().single().readBytes())
        assertEquals(listOf(8, 9, 10, 11, 12, 13, 14, 15, 16, 17), moofs.map { it.first })
        assertEquals((1..10).toList(), moofs.map { it.second })
    }

    @Test
    fun epochChangeStartsANewPart() {
        startEpoch(1280)
        val r = recorder()
        fragment(0)
        await { r.start(0, it) }
        fragments(1, 4) // 2, 3
        startEpoch(1920) // profile change: timestamps restart
        fragments(0, 3)
        r.sync()
        assertEquals(2, assertNotNull(r.status()).parts)
        val result = assertNotNull(await<RecordingSaved?> { r.stop(it) })

        val files = published()
        val (first, second) = files.sortedBy { it.name.length }
        assertTrue(NAME.matches(first.name), first.name)
        assertEquals(first.name.removeSuffix(".mp4") + "_part2.mp4", second.name)
        assertEquals(listOf(2, 3), moofs(first.readBytes()).map { it.first })
        assertEquals(listOf(0L, 90_000L, 180_000L), moofs(second.readBytes()).map { it.third })
        assertEquals(2, result.parts)
        assertEquals(5000, result.durationMs)
        assertEquals(first.length() + second.length(), result.bytes)
        assertEquals(first.name, result.name)
    }

    @Test
    fun detachClosesThePartAndRecordingContinues() {
        startEpoch()
        val r = recorder()
        fragment(0)
        await { r.start(0, it) }
        fragments(1, 3)
        r.detach()
        r.sync()
        assertEquals(1, published().size)
        assertEquals(RecordingState.RECORDING, assertNotNull(r.status()).state)

        startEpoch()
        r.attach(ring, 8_000_000)
        fragments(0, 2)
        assertEquals(2, assertNotNull(await<RecordingSaved?> { r.stop(it) }).parts)
    }

    @Test
    fun rollsOverAtMaxFragments() {
        startEpoch()
        val r = recorder(maxFragments = 3)
        fragment(0)
        await { r.start(0, it) }
        fragments(1, 9) // 2..8: 7 fragments
        val result = assertNotNull(await<RecordingSaved?> { r.stop(it) })

        assertEquals(3, result.parts)
        val files = published().sortedWith(compareBy({ it.name.length }, { it.name }))
        assertEquals(listOf(listOf(2, 3, 4), listOf(5, 6, 7), listOf(8)), files.map { f -> moofs(f.readBytes()).map { it.first } })
        // Every part has its own timeline and a full index that still fits in the reserved region.
        for (f in files) {
            val bytes = f.readBytes()
            assertEquals(0L, moofs(bytes).first().third)
            assertEquals(listOf("ftyp", "moov", "sidx", "free"), boxes(bytes).take(4).map { it.type })
        }
    }

    @Test
    fun startFailsWithoutSpace() {
        startEpoch()
        val r = recorder()
        free = 900L shl 20
        val e = assertFailsWith<FlutterError> { await { r.start(0, it) } }
        assertEquals("no_space", e.code)
    }

    @Test
    fun lowSpaceStopsCleanly() {
        startEpoch()
        val r = recorder()
        fragment(0)
        free = 2L shl 30
        await { r.start(0, it) }
        fragments(1, 3)
        free = (500L shl 20) + 1_000_000 // under 10 min at 1 MB/s
        fragment(3)
        r.sync()
        assertTrue(assertNotNull(r.status()).lowSpace)
        assertTrue(statuses.last().lowSpace, "lowSpace flip emitted")
        free = 400L shl 20
        fragments(4, 6)
        r.sync()

        val end = saved.single()
        assertEquals(RecordingEnd.LOW_SPACE, end.reason)
        assertEquals(2000, end.durationMs)
        assertEquals(RecordingState.IDLE, assertNotNull(r.status()).state)
        assertEquals(listOf(2, 3), moofs(published().single().readBytes()).map { it.first })
        assertNull(await { r.stop(it) })
    }

    @Test
    fun recoveryTruncatesAPartialFragment() {
        startEpoch()
        val crashed = recorder()
        fragment(0)
        await { crashed.start(0, it) }
        fragments(1, 5) // 2, 3, 4
        crashed.sync()
        crashed.release(awaitMs = 5_000)
        // Killed mid-write: half a fragment past the indexed ones, never published.
        val pending = gallery.listFiles()!!.single()
        assertTrue(pending.name.endsWith(".pending"))
        pending.appendBytes(ByteArray(50) { 7 })

        val r = recorder()
        val recovered = await { r.recover(it) }

        val result = recovered.single()
        assertEquals(RecordingEnd.RECOVERED, result.reason)
        assertEquals(3000, result.durationMs)
        val file = published().single()
        assertEquals(result.name, file.name)
        assertEquals(file.length(), result.bytes)
        val bytes = file.readBytes()
        assertEquals(listOf("ftyp", "moov", "sidx", "free") + List(3) { listOf("moof", "mdat") }.flatten(), boxes(bytes).map { it.type })
        assertEquals(3 * 90_000, mehd(bytes))
        assertTrue(stateDir.listFiles().orEmpty().isEmpty())
        assertTrue(await { r.recover(it) }.isEmpty())
    }

    @Test
    fun recoveryDropsAnEmptyPart() {
        startEpoch()
        val crashed = recorder()
        fragment(0)
        await { crashed.start(0, it) }
        fragments(1, 3) // 2
        crashed.sync()
        crashed.release(awaitMs = 5_000)
        // Simulate a crash right after creating the part: the journal has no fragments.
        stateDir.listFiles { f -> f.name.endsWith(".idx") }!!.forEach { it.delete() }

        val r = recorder()
        assertTrue(await { r.recover(it) }.isEmpty())
        assertTrue(gallery.listFiles().orEmpty().isEmpty())
        assertTrue(stateDir.listFiles().orEmpty().isEmpty())
        assertFalse(published().any())
    }
}
