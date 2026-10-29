package io.github.instantreplay.replay_capture_android.outbox

import io.github.instantreplay.replay_capture_android.ClipInfo
import io.github.instantreplay.replay_capture_android.ClipState
import io.github.instantreplay.replay_capture_android.FlutterError
import io.github.instantreplay.replay_capture_android.SaveRequest
import io.github.instantreplay.replay_capture_android.buffer.ClipAssembler
import io.github.instantreplay.replay_capture_android.buffer.RingBuffer
import java.io.File
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.Executors

/**
 * Clips waiting for a Viewer to download and acknowledge them (SPEC §3.4).
 * Outlives capture start/stop: [attach] connects it to the current ring buffer.
 *
 * Minimal version: in memory only. M2.5 adds persistence, TTL and the size cap.
 */
internal class Outbox(private val dir: File, private val onChange: (ClipInfo) -> Unit) {
    private val clips = LinkedHashMap<String, ClipInfo>()
    private val io = Executors.newSingleThreadExecutor()
    @Volatile private var assembler: ClipAssembler? = null

    fun attach(ring: RingBuffer?) {
        assembler = ring?.let { ClipAssembler(it, dir) }
    }

    /** [callback] runs on a background thread. */
    fun save(request: SaveRequest, callback: (Result<ClipInfo>) -> Unit) {
        synchronized(clips) { clips.values.firstOrNull { it.requestId == request.requestId } }
            ?.takeIf { it.state == ClipState.READY }
            ?.let { return callback(Result.success(it)) }
        val clipAssembler = assembler
            ?: return callback(Result.failure(FlutterError("not_running", "Capture is not running")))

        val recording = ClipInfo(
            id = UUID.randomUUID().toString(),
            requestId = request.requestId,
            state = ClipState.RECORDING,
            createdAtMs = System.currentTimeMillis(),
        )
        put(recording)
        io.execute {
            try {
                val r = clipAssembler.save(request.preSeconds, request.postSeconds)
                val path = r["path"] as String
                val ready = recording.copy(
                    state = ClipState.READY,
                    path = path,
                    bytes = r["bytes"] as Long,
                    durationMs = r["durationMs"] as Long,
                    fragments = (r["fragments"] as Int).toLong(),
                    assemblyMs = r["assemblyMs"] as Long,
                    extraPreRollMs = r["extraPreRollMs"] as Long,
                    sha256 = sha256(File(path)),
                )
                put(ready)
                callback(Result.success(ready))
            } catch (e: Exception) {
                synchronized(clips) { clips.remove(recording.id) }
                callback(Result.failure(FlutterError("save_failed", e.message)))
            }
        }
    }

    fun list(): List<ClipInfo> = synchronized(clips) { clips.values.toList() }

    fun get(id: String): ClipInfo? = synchronized(clips) { clips[id] }

    fun ack(id: String, sha256: String): Boolean {
        val clip = get(id) ?: return false
        if (clip.state != ClipState.READY || !clip.sha256.equals(sha256, ignoreCase = true)) return false
        clip.path?.let { File(it).delete() }
        synchronized(clips) { clips.remove(id) }
        onChange(clip.copy(state = ClipState.ACKED))
        return true
    }

    /** Clip count and bytes on disk. */
    fun stats(): Pair<Long, Long> = synchronized(clips) {
        clips.size.toLong() to clips.values.sumOf { it.bytes ?: 0L }
    }

    fun release() {
        io.shutdownNow()
    }

    private fun put(clip: ClipInfo) {
        synchronized(clips) { clips[clip.id] = clip }
        onChange(clip)
    }

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
}
