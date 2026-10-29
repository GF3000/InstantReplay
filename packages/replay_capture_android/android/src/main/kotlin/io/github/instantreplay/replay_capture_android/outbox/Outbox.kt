package io.github.instantreplay.replay_capture_android.outbox

import io.github.instantreplay.replay_capture_android.ClipInfo
import io.github.instantreplay.replay_capture_android.ClipState
import io.github.instantreplay.replay_capture_android.FlutterError
import io.github.instantreplay.replay_capture_android.SaveRequest
import io.github.instantreplay.replay_capture_android.buffer.ClipAssembler
import io.github.instantreplay.replay_capture_android.buffer.ClipJob
import io.github.instantreplay.replay_capture_android.buffer.ClipSource
import io.github.instantreplay.replay_capture_android.buffer.RingBuffer
import java.io.File
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.ThreadFactory
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

/**
 * Clips waiting for a Viewer to download and acknowledge them (SPEC §3.4):
 * `recording → ready → acked (file deleted)`, or `ready → expired` after [ttlMs] or when ready clips
 * exceed [capBytes] (oldest first).
 *
 * Outlives capture start/stop: [attach] connects it to the current ring buffer. Clip files are
 * `<id>.mp4` in [dir]; the index ([OutboxIndex]) is rewritten on every change so ready clips survive
 * app restarts.
 *
 * Threading: every save waits for its post-roll and assembles on its own worker thread, so
 * overlapping saves run in parallel (assembly only reads the ring). State is guarded by one lock;
 * file deletion and index writes happen under it, [onChange] and callbacks are called outside it.
 */
internal class Outbox(
    private val dir: File,
    private val clock: () -> Long = System::currentTimeMillis,
    private val ttlMs: Long = 2 * 60 * 60 * 1000L,
    private val capBytes: Long = 1L shl 30,
    /** Expiry timer period; <= 0 disables the timer (expiry then only runs after each save). */
    expiryPeriodMs: Long = 60_000,
    /** Last so `Outbox(dir) { clip -> ... }` keeps working. */
    private val onChange: (ClipInfo) -> Unit,
) {
    private val lock = Object()
    private val clips = LinkedHashMap<String, ClipInfo>()
    /** Callers waiting for a clip that is still recording, by clip id. */
    private val waiters = HashMap<String, MutableList<(Result<ClipInfo>) -> Unit>>()
    private val index = OutboxIndex(File(dir, OutboxIndex.FILE_NAME))
    private val workers = Executors.newCachedThreadPool(daemonThreads("ir-outbox-save"))
    private val timer: ScheduledExecutorService? =
        if (expiryPeriodMs > 0) Executors.newSingleThreadScheduledExecutor(daemonThreads("ir-outbox-expiry")) else null
    @Volatile private var source: ClipSource? = null

    init {
        dir.mkdirs()
        restore()
        timer?.scheduleWithFixedDelay(::expireSafely, 0, expiryPeriodMs, TimeUnit.MILLISECONDS)
    }

    fun attach(ring: RingBuffer?) = attachSource(ring?.let { ClipAssembler(it) })

    fun attachSource(source: ClipSource?) {
        this.source = source
    }

    /**
     * Cuts a clip `[now - pre, now + post]`. [callback] runs on a background thread once the clip is
     * ready (or immediately if [SaveRequest.requestId] is already ready). A repeated requestId never
     * cuts a second clip.
     */
    fun save(request: SaveRequest, callback: (Result<ClipInfo>) -> Unit) {
        var job: ClipJob? = null
        var recording: ClipInfo? = null
        val immediate: Result<ClipInfo>? = synchronized(lock) {
            val existing = clips.values.firstOrNull { it.requestId == request.requestId }
            when {
                existing?.state == ClipState.RECORDING -> {
                    waiters.getOrPut(existing.id) { mutableListOf() } += callback
                    return
                }
                existing != null -> Result.success(existing)
                else -> {
                    val clipSource = source
                        ?: return@synchronized Result.failure(FlutterError("not_running", "Capture is not running"))
                    job = try {
                        clipSource.mark(request.preSeconds, request.postSeconds)
                    } catch (e: Exception) {
                        return@synchronized Result.failure(FlutterError("save_failed", e.message))
                    }
                    val clip = ClipInfo(
                        id = UUID.randomUUID().toString(),
                        requestId = request.requestId,
                        state = ClipState.RECORDING,
                        createdAtMs = clock(),
                    )
                    clips[clip.id] = clip
                    waiters[clip.id] = mutableListOf(callback)
                    persist()
                    recording = clip
                    null
                }
            }
        }
        if (immediate != null) return callback(immediate)
        val clip = checkNotNull(recording)
        val clipJob = checkNotNull(job)
        onChange(clip)
        try {
            workers.execute { finish(clip, clipJob) }
        } catch (e: Exception) {
            finish(clip) { throw IllegalStateException("Outbox released", e) }
        }
    }

    fun list(): List<ClipInfo> = synchronized(lock) { clips.values.toList() }

    fun get(id: String): ClipInfo? = synchronized(lock) { clips[id] }

    /** Deletes a ready clip once the requester confirmed its checksum. */
    fun ack(id: String, sha256: String): Boolean {
        val acked = synchronized(lock) {
            val clip = clips[id] ?: return false
            if (clip.state != ClipState.READY || !clip.sha256.equals(sha256, ignoreCase = true)) return false
            clips.remove(id)
            clipFile(id).delete()
            persist()
            clip.copy(state = ClipState.ACKED)
        }
        onChange(acked)
        return true
    }

    /** Clip count and bytes on disk. */
    fun stats(): Pair<Long, Long> = synchronized(lock) {
        clips.size.toLong() to clips.values.sumOf { it.bytes ?: 0L }
    }

    /**
     * Expires ready clips older than [ttlMs], then the oldest ready clips while their total size
     * exceeds [capBytes]. Runs on the timer and after each save.
     */
    fun expire() {
        val expired = synchronized(lock) {
            val now = clock()
            val ready = clips.values.filter { it.state == ClipState.READY }.sortedBy { it.createdAtMs }
            val gone = ready.filter { now - it.createdAtMs > ttlMs }.toMutableList()
            var bytes = ready.sumOf { it.bytes ?: 0L } - gone.sumOf { it.bytes ?: 0L }
            for (clip in ready) {
                if (bytes <= capBytes) break
                if (clip in gone) continue
                gone += clip
                bytes -= clip.bytes ?: 0L
            }
            if (gone.isEmpty()) return
            for (clip in gone) {
                clips.remove(clip.id)
                clipFile(clip.id).delete()
            }
            persist()
            gone.map { it.copy(state = ClipState.EXPIRED) }
        }
        expired.forEach(onChange)
    }

    fun release() {
        timer?.shutdownNow()
        workers.shutdownNow()
    }

    private fun finish(recording: ClipInfo, job: ClipJob) {
        val file = clipFile(recording.id)
        val result = try {
            val a = job.assemble(file)
            Result.success(
                recording.copy(
                    state = ClipState.READY,
                    path = file.absolutePath,
                    bytes = a.bytes,
                    durationMs = a.durationMs,
                    fragments = a.fragments.toLong(),
                    assemblyMs = a.assemblyMs,
                    extraPreRollMs = a.extraPreRollMs,
                    sha256 = sha256(file),
                )
            )
        } catch (e: Exception) {
            Result.failure(FlutterError("save_failed", e.message ?: e.toString()))
        }

        val callbacks = synchronized(lock) {
            val ready = result.getOrNull()
            if (ready != null && clips.containsKey(recording.id)) {
                clips[recording.id] = ready
            } else {
                clips.remove(recording.id)
                file.delete()
            }
            persist()
            waiters.remove(recording.id).orEmpty()
        }
        result.getOrNull()?.let(onChange)
        // Before the callbacks, so callers already see the outbox within its cap.
        expireSafely()
        callbacks.forEach { it(result) }
    }

    private fun expireSafely() {
        try {
            expire()
        } catch (_: Exception) {
            // Keep the timer alive; the next run retries.
        }
    }

    /** Reloads the index: keeps ready clips whose file is intact, drops everything else. */
    private fun restore() {
        val restored = index.read().filter { clip ->
            val file = clipFile(clip.id)
            clip.state == ClipState.READY && file.isFile && file.length() == clip.bytes
        }
        synchronized(lock) {
            restored.forEach { clips[it.id] = it.copy(path = clipFile(it.id).absolutePath) }
            // Partial clips (recording at crash), orphans and stale temp files.
            val keep = clips.keys.map { "$it.mp4" }.toSet() + OutboxIndex.FILE_NAME
            dir.listFiles()?.filter { it.name !in keep }?.forEach { it.deleteRecursively() }
            persist()
        }
    }

    /** Call with [lock] held. */
    private fun persist() {
        try {
            index.write(clips.values)
        } catch (_: Exception) {
            // In-memory state stays authoritative; the next change rewrites the index.
        }
    }

    private fun clipFile(id: String) = File(dir, "$id.mp4")

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(1 shl 16)
            while (true) {
                val n = input.read(buffer)
                if (n < 0) break
                digest.update(buffer, 0, n)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    private companion object {
        fun daemonThreads(name: String): ThreadFactory {
            val count = AtomicInteger()
            return ThreadFactory { r -> Thread(r, "$name-${count.incrementAndGet()}").apply { isDaemon = true } }
        }
    }
}
