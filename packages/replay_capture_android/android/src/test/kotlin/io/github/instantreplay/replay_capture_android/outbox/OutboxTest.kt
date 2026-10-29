package io.github.instantreplay.replay_capture_android.outbox

import io.github.instantreplay.replay_capture_android.ClipInfo
import io.github.instantreplay.replay_capture_android.ClipState
import io.github.instantreplay.replay_capture_android.FlutterError
import io.github.instantreplay.replay_capture_android.SaveRequest
import io.github.instantreplay.replay_capture_android.buffer.Assembly
import io.github.instantreplay.replay_capture_android.buffer.ClipJob
import io.github.instantreplay.replay_capture_android.buffer.ClipSource
import java.io.File
import java.nio.file.Files
import java.security.MessageDigest
import java.util.Collections
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

class OutboxTest {

    private val dir: File = Files.createTempDirectory("outbox").toFile()
    private val events: MutableList<ClipInfo> = Collections.synchronizedList(mutableListOf())
    @Volatile private var now = 1_000_000L
    private val outboxes = mutableListOf<Outbox>()

    /** Writes [size] bytes per clip; jobs optionally block on [gate]. */
    private class FakeSource(var size: Int = 100) : ClipSource {
        val marks = AtomicInteger()
        @Volatile var gate: CountDownLatch? = null
        @Volatile var onAssemble: () -> Unit = {}
        @Volatile var fail = false

        override fun mark(preSeconds: Double, postSeconds: Double): ClipJob {
            val n = marks.incrementAndGet()
            val gate = gate
            return ClipJob { target ->
                onAssemble()
                gate?.let { check(it.await(5, TimeUnit.SECONDS)) { "gate timed out" } }
                check(!fail) { "assembly failed" }
                target.writeBytes(ByteArray(size) { (it + n).toByte() })
                Assembly(bytes = target.length(), durationMs = 1000, fragments = 1, assemblyMs = 1, extraPreRollMs = 0)
            }
        }
    }

    @AfterTest
    fun tearDown() {
        outboxes.forEach { it.release() }
        dir.deleteRecursively()
    }

    private fun outbox(ttlMs: Long = 2 * 60 * 60 * 1000L, capBytes: Long = 1L shl 30) =
        Outbox(dir, clock = { now }, ttlMs = ttlMs, capBytes = capBytes, expiryPeriodMs = 0) { events += it }
            .also { outboxes += it }

    private fun request(id: String) = SaveRequest(requestId = id, preSeconds = 10.0, postSeconds = 2.0)

    private fun saveAsync(outbox: Outbox, requestId: String): () -> Result<ClipInfo> {
        val done = CountDownLatch(1)
        var result: Result<ClipInfo>? = null
        outbox.save(request(requestId)) {
            result = it
            done.countDown()
        }
        return {
            assertTrue(done.await(5, TimeUnit.SECONDS), "save did not complete")
            result!!
        }
    }

    private fun save(outbox: Outbox, requestId: String): ClipInfo = saveAsync(outbox, requestId)().getOrThrow()

    private fun sha256(file: File) =
        MessageDigest.getInstance("SHA-256").digest(file.readBytes()).joinToString("") { "%02x".format(it) }

    @Test
    fun lifecycleRecordingReadyAcked() {
        val outbox = outbox().apply { attachSource(FakeSource()) }
        val clip = save(outbox, "r1")

        assertEquals(ClipState.READY, clip.state)
        val file = File(dir, "${clip.id}.mp4")
        assertEquals(file.absolutePath, clip.path)
        assertEquals(100L, clip.bytes)
        assertEquals(sha256(file), clip.sha256)
        assertEquals(now, clip.createdAtMs)
        assertEquals(1L to 100L, outbox.stats())

        assertTrue(outbox.ack(clip.id, clip.sha256!!.uppercase()))
        assertFalse(file.exists())
        assertEquals(emptyList(), outbox.list())
        assertEquals(0L to 0L, outbox.stats())
        assertEquals(listOf(ClipState.RECORDING, ClipState.READY, ClipState.ACKED), events.map { it.state })
        assertTrue(events.all { it.id == clip.id })
        assertFalse(outbox.ack(clip.id, clip.sha256!!), "second ack")
    }

    @Test
    fun ackRejectsHashMismatchAndUnknownIds() {
        val outbox = outbox().apply { attachSource(FakeSource()) }
        val clip = save(outbox, "r1")

        assertFalse(outbox.ack(clip.id, "0".repeat(64)))
        assertFalse(outbox.ack("nope", clip.sha256!!))
        assertEquals(ClipState.READY, outbox.get(clip.id)?.state)
        assertTrue(File(clip.path!!).exists())
    }

    @Test
    fun ackRejectsRecordingClip() {
        val source = FakeSource().apply { gate = CountDownLatch(1) }
        val outbox = outbox().apply { attachSource(source) }
        val pending = saveAsync(outbox, "r1")
        val recording = outbox.list().single()
        assertEquals(ClipState.RECORDING, recording.state)
        assertFalse(outbox.ack(recording.id, ""))
        source.gate!!.countDown()
        assertEquals(ClipState.READY, pending().getOrThrow().state)
    }

    @Test
    fun saveWithoutCaptureFails() {
        val outbox = outbox()
        val error = saveAsync(outbox, "r1")().exceptionOrNull()
        assertEquals("not_running", (error as FlutterError).code)
        assertEquals(emptyList(), outbox.list())
    }

    @Test
    fun failedAssemblyRemovesClip() {
        val source = FakeSource().apply { fail = true }
        val outbox = outbox().apply { attachSource(source) }
        val error = saveAsync(outbox, "r1")().exceptionOrNull()
        assertEquals("save_failed", (error as FlutterError).code)
        assertEquals(emptyList(), outbox.list())
        assertEquals(listOf(OutboxIndex.FILE_NAME), dir.list()!!.toList())
    }

    @Test
    fun repeatedRequestIdNeverCutsTwice() {
        val source = FakeSource().apply { gate = CountDownLatch(1) }
        val outbox = outbox().apply { attachSource(source) }
        val first = saveAsync(outbox, "same")
        val second = saveAsync(outbox, "same")
        assertEquals(1, source.marks.get())
        assertEquals(1, outbox.list().size)

        source.gate!!.countDown()
        val a = first().getOrThrow()
        val b = second().getOrThrow()
        assertEquals(a, b)
        assertEquals(ClipState.READY, a.state)

        // Once ready, the same id answers immediately with the same clip.
        assertEquals(a, save(outbox, "same"))
        assertEquals(1, source.marks.get())
        assertEquals(1, events.count { it.state == ClipState.READY })
    }

    @Test
    fun overlappingSavesWaitInParallel() {
        val bothStarted = CountDownLatch(2)
        val source = FakeSource().apply {
            // Each job only finishes once the other one is also running: deadlocks if serialized.
            onAssemble = {
                bothStarted.countDown()
                check(bothStarted.await(5, TimeUnit.SECONDS)) { "saves were serialized" }
            }
        }
        val outbox = outbox().apply { attachSource(source) }
        val a = saveAsync(outbox, "a")
        val b = saveAsync(outbox, "b")
        val clipA = a().getOrThrow()
        val clipB = b().getOrThrow()
        assertTrue(clipA.id != clipB.id)
        assertEquals(2, outbox.list().count { it.state == ClipState.READY })
    }

    @Test
    fun readyClipsSurviveRestart() {
        val first = outbox().apply { attachSource(FakeSource()) }
        val a = save(first, "a\twith\ttabs\nand newline\\")
        now += 1000
        val b = save(first, "b")
        first.release()

        val second = outbox()
        assertEquals(listOf(a, b), second.list())
        assertEquals(2L to 200L, second.stats())
        assertEquals(b, second.get(b.id))
        assertTrue(second.ack(a.id, a.sha256!!))

        val third = outbox()
        assertEquals(listOf(b), third.list())
    }

    @Test
    fun indexRecordsRecordingClip() {
        val source = FakeSource().apply { gate = CountDownLatch(1) }
        val outbox = outbox().apply { attachSource(source) }
        val pending = saveAsync(outbox, "r1")
        val persisted = OutboxIndex(File(dir, OutboxIndex.FILE_NAME)).read()
        assertEquals(listOf(ClipState.RECORDING), persisted.map { it.state })
        source.gate!!.countDown()
        pending()
    }

    @Test
    fun restartDiscardsRecordingPartialAndOrphanFiles() {
        val ready = ClipInfo(
            id = "ready", requestId = "r1", state = ClipState.READY, createdAtMs = now,
            bytes = 3, durationMs = 1000, fragments = 1, assemblyMs = 1, extraPreRollMs = 0, sha256 = "ab",
        )
        val recording = ClipInfo(id = "rec", requestId = "r2", state = ClipState.RECORDING, createdAtMs = now)
        val truncated = ready.copy(id = "short", requestId = "r3", bytes = 10)
        File(dir, "ready.mp4").writeBytes(byteArrayOf(1, 2, 3))
        File(dir, "rec.mp4.part").writeBytes(byteArrayOf(1))
        File(dir, "short.mp4").writeBytes(byteArrayOf(1))
        File(dir, "orphan.mp4").writeBytes(byteArrayOf(1))
        File(dir, "${OutboxIndex.FILE_NAME}.tmp").writeText("junk")
        OutboxIndex(File(dir, OutboxIndex.FILE_NAME)).write(listOf(ready, recording, truncated))

        val outbox = outbox()
        assertEquals(listOf(ready.copy(path = File(dir, "ready.mp4").absolutePath)), outbox.list())
        assertEquals(setOf("ready.mp4", OutboxIndex.FILE_NAME), dir.list()!!.toSet())
        assertEquals(listOf("ready"), OutboxIndex(File(dir, OutboxIndex.FILE_NAME)).read().map { it.id })
    }

    @Test
    fun corruptIndexIsIgnored() {
        File(dir, OutboxIndex.FILE_NAME).writeText("{not an index}")
        File(dir, "x.mp4").writeBytes(byteArrayOf(1))
        val outbox = outbox()
        assertEquals(emptyList(), outbox.list())
        assertEquals(listOf(OutboxIndex.FILE_NAME), dir.list()!!.toList())
    }

    @Test
    fun expiresAfterTtl() {
        val outbox = outbox(ttlMs = 60_000).apply { attachSource(FakeSource()) }
        val old = save(outbox, "old")
        now += 30_000
        val young = save(outbox, "young")
        now += 30_001

        outbox.expire()
        assertEquals(listOf(young), outbox.list())
        assertFalse(File(old.path!!).exists())
        assertEquals(listOf(old.copy(state = ClipState.EXPIRED)), events.filter { it.state == ClipState.EXPIRED })

        // Survives a restart as expired.
        assertEquals(listOf(young), outbox().list())
    }

    @Test
    fun capExpiresOldestReadyFirst() {
        val outbox = outbox(capBytes = 250).apply { attachSource(FakeSource(size = 100)) }
        val a = save(outbox, "a")
        now += 1
        val b = save(outbox, "b")
        now += 1
        val c = save(outbox, "c")
        outbox.expire() // also runs after each save; repeat to avoid racing the worker thread

        assertEquals(listOf(b, c), outbox.list())
        assertEquals(2L to 200L, outbox.stats())
        assertFalse(File(a.path!!).exists())
        val expired = events.filter { it.state == ClipState.EXPIRED }
        assertEquals(listOf(a.id), expired.map { it.id })
    }

    @Test
    fun expiryLeavesRecordingClipsAlone() {
        val source = FakeSource().apply { gate = CountDownLatch(1) }
        val outbox = outbox(ttlMs = 10).apply { attachSource(source) }
        val pending = saveAsync(outbox, "r1")
        now += 1_000
        outbox.expire()
        assertEquals(ClipState.RECORDING, outbox.list().single().state)
        source.gate!!.countDown()
        assertNotNull(pending().getOrNull())
    }

    @Test
    fun indexEscapingRoundTrips() {
        val s = "a\\b\tc\nd\re\\t"
        assertEquals(s, OutboxIndex.unescape(OutboxIndex.escape(s)))
        assertFalse('\t' in OutboxIndex.escape(s))
        assertFalse('\n' in OutboxIndex.escape(s))
    }
}
