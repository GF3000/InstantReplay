package io.github.instantreplay.replay_capture_android.recording

import io.github.instantreplay.replay_capture_android.FlutterError
import io.github.instantreplay.replay_capture_android.RecordingEnd
import io.github.instantreplay.replay_capture_android.RecordingSaved
import io.github.instantreplay.replay_capture_android.RecordingState
import io.github.instantreplay.replay_capture_android.RecordingStatus
import io.github.instantreplay.replay_capture_android.buffer.RingBuffer
import io.github.instantreplay.replay_capture_android.mp4.Fmp4
import io.github.instantreplay.replay_capture_android.mp4.TrackInfo
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * Full-session recording (SPEC D8, §3.8): archives the ring-buffer fragments into gallery videos
 * as they are produced, so the window can still evict them. Nothing is concatenated at the end;
 * each part is written in place:
 *
 * `init(duration) | sidx + free (reserved, fixed size) | moof mdat | moof mdat | …`
 *
 * The init is written with a placeholder duration and the index region as one `free` box; on
 * finish both are rewritten in place (same sizes), so a 90-minute game never needs twice its size.
 * Every fragment is patched with the part's own running sequence and decode time, so the video is
 * continuous across pauses. A part ends when the encoder epoch changes (profile or thermal
 * restart), when capture stops, or after [maxFragmentsPerPart] fragments.
 *
 * Pause and resume cut per fragment: a pause still writes the fragment in progress; a resume
 * without [includeSeconds][start] starts at the next keyframe, one with it first writes that much
 * of the ring (never a fragment twice).
 *
 * Threading: every state change runs on one single-thread executor; host calls post to it and
 * complete their callback from it. [status] is a volatile snapshot for the stats path. The ring
 * listener only posts, so a slow disk never blocks the encoder. An IO error ends the recording
 * (finalizing what was written) and never reaches capture.
 *
 * Crash safety: each open part has a [PartJournal] in [stateDir]; [recover] finalizes leftovers.
 */
internal class SessionRecorder(
    private val store: PartStore,
    private val stateDir: File,
    /** Free bytes on the storage the parts are written to. */
    private val freeBytes: () -> Long,
    private val clock: () -> Long = System::currentTimeMillis,
    private val maxFragmentsPerPart: Int = MAX_FRAGMENTS_PER_PART,
    private val onStatus: (RecordingStatus) -> Unit,
    private val onSaved: (RecordingSaved) -> Unit,
) {
    /** `(epoch, µs)` position in the ring. */
    private data class Mark(val epoch: Int, val us: Long)

    /** Fragments starting in `[from, to]`; `to == null` is open-ended, later epochs are inside. */
    private data class Window(val from: Mark?, val to: Mark?) {
        fun contains(f: RingBuffer.Fragment): Boolean {
            val afterFrom = from == null || f.epoch > from.epoch || (f.epoch == from.epoch && f.startUs >= from.us)
            val beforeTo = to == null || (f.epoch == to.epoch && f.startUs <= to.us)
            return afterFrom && beforeTo
        }
    }

    private class Part(
        val number: Int,
        val epoch: Int,
        val track: TrackInfo,
        val sink: PartSink,
        val journal: PartJournal,
        val initSize: Int,
        val headerSize: Long,
    ) {
        val fragments = ArrayList<Pair<Int, Long>>()
        var sequence = 0
        var ticks = 0L
        /** File size: header + fragments. */
        var bytes = headerSize
    }

    private val executor: ExecutorService = Executors.newSingleThreadExecutor { r ->
        Thread(r, "ir-recorder").apply { isDaemon = true }
    }

    // Executor-confined state.
    private var ring: RingBuffer? = null
    private var bitrate = 0
    private var state = RecordingState.IDLE
    /** Accepting window while recording; null while paused or idle. */
    private var open: Window? = null
    /** The window closed by the last pause: its fragment in progress still has to be written. */
    private var closed: Window? = null
    /** End of the newest fragment written, so a fragment is never written twice. */
    private var lastWritten: Mark? = null
    private var part: Part? = null
    private var recordingStartMs = 0L
    private var recordingName: String? = null
    private var partsWritten = 0
    private var ticksBefore = 0L
    private var bytesBefore = 0L
    private var lowSpace = false

    @Volatile private var latest: RecordingStatus? = null
    @Volatile private var latestBitrate = 0

    /** Last known status; null until the recorder is first used in this process. */
    fun status(): RecordingStatus? = latest

    /** For the host call: the snapshot, with fresh free space when idle. */
    fun currentStatus(): RecordingStatus {
        val snapshot = latest
        if (snapshot != null && snapshot.state != RecordingState.IDLE) return snapshot
        val free = freeBytes()
        val remaining = remainingMs(free, 0, 0, latestBitrate)
        return RecordingStatus(
            state = RecordingState.IDLE,
            elapsedMs = 0,
            bytes = 0,
            parts = 0,
            freeBytes = free,
            remainingMs = remaining,
            lowSpace = remaining != null && remaining < LOW_SPACE_MS,
        )
    }

    /**
     * Connects to the ring of the capture that just started ([bitrate] in bit/s, the fallback rate
     * estimate). A different ring restarts epoch numbering, so a running recording then accepts
     * everything from it.
     */
    fun attach(ring: RingBuffer, bitrate: Int) {
        latestBitrate = bitrate
        post {
            if (ring !== this.ring) {
                this.ring?.fragmentListener = null
                this.ring = ring
                lastWritten = null
                closed = null
                if (state == RecordingState.RECORDING) open = Window(Mark(ring.epoch, -1), null)
            }
            this.bitrate = bitrate
        }
        // After the task above, so every fragment it posts sees the new ring.
        ring.fragmentListener = { f, data -> post { onFragment(ring, f, data) } }
    }

    /**
     * Capture stopped: closes the open part. The recording stays recording or paused, and the
     * next capture continues in a new part.
     */
    fun detach() = post { closePartSafely() }

    /** Starts a recording, or resumes a paused one. Fails with `no_space` or `not_running`. */
    fun start(includeSeconds: Long, callback: (Result<RecordingStatus>) -> Unit) = call(callback) {
        val ring = ring ?: throw FlutterError("not_running", "Capture is not running")
        when (state) {
            RecordingState.RECORDING -> return@call snapshot()
            RecordingState.IDLE -> {
                val free = freeBytes()
                if (free < MIN_FREE_TO_START) {
                    throw FlutterError("no_space", "Only ${free / (1 shl 20)} MB free; 1 GB needed to record")
                }
                resetCounters()
                recordingStartMs = clock()
            }
            RecordingState.PAUSED -> Unit
        }
        state = RecordingState.RECORDING
        val cursor = ring.cursor()
        var fromUs = cursor.ptsUs
        if (includeSeconds > 0 && cursor.ptsUs >= 0) {
            val sinceUs = cursor.ptsUs - includeSeconds * 1_000_000L
            val candidates = ring.select(cursor.epoch, sinceUs, Long.MAX_VALUE).filter { it.startUs >= sinceUs }
            for (f in candidates) {
                if (isWritten(f)) continue
                val data = try {
                    f.file.readBytes()
                } catch (_: Exception) {
                    continue // Evicted meanwhile.
                }
                write(f, data)
                if (state == RecordingState.IDLE) return@call snapshot() // Stopped by low space or an error.
            }
            candidates.lastOrNull()?.let { fromUs = it.endUs }
        }
        open = Window(Mark(cursor.epoch, fromUs), null)
        publishStatus()
    }

    /** Pauses at the end of the fragment in progress. No-op unless recording. */
    fun pause(callback: (Result<RecordingStatus>) -> Unit) = call(callback) {
        if (state != RecordingState.RECORDING) return@call snapshot()
        val cursor = ring?.cursor()
        closed = cursor?.let { open?.copy(to = Mark(it.epoch, it.ptsUs)) }
        open = null
        state = RecordingState.PAUSED
        publishStatus()
    }

    /** Finishes and publishes the recording; null if nothing was recording or nothing was written. */
    fun stop(callback: (Result<RecordingSaved?>) -> Unit) = call(callback) {
        if (state == RecordingState.IDLE) return@call null
        finish(RecordingEnd.USER, null).takeIf { it.parts > 0 }
    }

    /** Finalizes parts left open by a crash or kill: one result per recording. */
    fun recover(callback: (Result<List<RecordingSaved>>) -> Unit) = call(callback) {
        stateDir.mkdirs()
        val current = part?.journal?.key
        val saved = PartJournal.leftovers(stateDir).filter { it.key != current }.mapNotNull(::recoverPart)
        PartJournal.cleanOrphans(stateDir)
        saved
    }

    /** Waits for every task posted so far. For tests. */
    fun sync() {
        executor.submit {}.get(10, TimeUnit.SECONDS)
    }

    /**
     * Stops the executor after the pending tasks. A part still open is closed without finalizing
     * and recovered on the next run. Waits up to [awaitMs] for that.
     */
    fun release(awaitMs: Long = 0) {
        post {
            ring?.fragmentListener = null
            part?.let {
                runCatching { it.sink.close() }
                it.journal.close()
            }
            part = null
        }
        executor.shutdown()
        if (awaitMs > 0) executor.awaitTermination(awaitMs, TimeUnit.MILLISECONDS)
    }

    // region Executor side

    private fun onFragment(from: RingBuffer, f: RingBuffer.Fragment, data: ByteArray) {
        if (from !== ring || state == RecordingState.IDLE || isWritten(f)) return
        val accepted = when (state) {
            RecordingState.RECORDING -> open?.contains(f) == true || closed?.contains(f) == true
            else -> closed?.contains(f) == true
        }
        if (accepted) write(f, data)
    }

    private fun isWritten(f: RingBuffer.Fragment): Boolean {
        val last = lastWritten ?: return false
        return f.epoch < last.epoch || (f.epoch == last.epoch && f.startUs < last.us)
    }

    private fun write(f: RingBuffer.Fragment, data: ByteArray) {
        try {
            if (freeBytes() < MIN_FREE_TO_CONTINUE) {
                finish(RecordingEnd.LOW_SPACE, null)
                return
            }
            var current = part
            if (current != null && (current.epoch != f.epoch || current.fragments.size >= maxFragmentsPerPart)) {
                closePart()
                current = null
            }
            val newPart = current == null
            if (current == null) {
                val track = ring?.trackFor(f.epoch) ?: return // Codec config already evicted: nothing playable.
                current = openPart(f.epoch, track)
            }
            val copy = data.copyOf()
            current.sequence++
            Fmp4.patchFragment(copy, current.sequence, current.ticks)
            current.sink.append(copy)
            current.ticks += f.durationTicks
            current.bytes += copy.size
            current.fragments += copy.size to f.durationTicks
            current.journal.appendFragment(copy.size, f.durationTicks)
            lastWritten = Mark(f.epoch, f.endUs)

            val wasLow = lowSpace
            val status = snapshot()
            if (newPart || wasLow != status.lowSpace) onStatus(status)
        } catch (e: Exception) {
            finish(RecordingEnd.ERROR, e.message ?: e.toString())
        }
    }

    private fun openPart(epoch: Int, track: TrackInfo): Part {
        val number = partsWritten + 1
        val name = partName(number)
        val init = Fmp4.init(track, durationTicks = 1)
        val reserved = Fmp4.sidxSize(maxFragmentsPerPart) + MIN_FREE_BOX
        val sink = store.create(name)
        val journal = PartJournal.create(stateDir, "%d_%03d".format(Locale.ROOT, recordingStartMs, number))
        try {
            sink.append(init)
            sink.append(Fmp4.free(reserved))
            if (number == 1) recordingName = sink.name
            journal.writeState(
                PartState(
                    id = sink.id,
                    displayName = sink.name,
                    track = track,
                    headerSize = (init.size + reserved).toLong(),
                    recordingStartMs = recordingStartMs,
                    partNumber = number,
                    recordingName = recordingName ?: sink.name,
                    ticksBefore = ticksBefore,
                    bytesBefore = bytesBefore,
                )
            )
        } catch (e: Exception) {
            journal.delete()
            runCatching { sink.discard() }
            throw e
        }
        partsWritten = number
        return Part(number, epoch, track, sink, journal, init.size, (init.size + reserved).toLong()).also { part = it }
    }

    /** Finalizes and publishes the open part, adding it to the recording's totals. */
    private fun closePart() {
        val p = part ?: return
        part = null
        try {
            if (p.fragments.isEmpty()) {
                p.journal.delete()
                p.sink.discard()
                partsWritten--
                if (partsWritten == 0) recordingName = null
                return
            }
            finalizePart(p.sink, p.track, p.initSize, p.headerSize, p.fragments)
        } catch (e: Exception) {
            // The journal stays, so recover() can retry on the next run.
            runCatching { p.sink.close() }
            p.journal.close()
            throw e
        }
        p.journal.delete()
        ticksBefore += p.ticks
        bytesBefore += p.bytes
    }

    private fun closePartSafely() {
        try {
            closePart()
            if (state != RecordingState.IDLE) publishStatus()
        } catch (e: Exception) {
            finish(RecordingEnd.ERROR, e.message ?: e.toString())
        }
    }

    /**
     * Ends the recording: closes the open part if it can, reports it and goes idle. A part that
     * cannot be finalized keeps its journal, so [recover] retries it on the next run.
     */
    private fun finish(reason: RecordingEnd, message: String?): RecordingSaved {
        var error = message
        var why = reason
        try {
            closePart()
        } catch (e: Exception) {
            if (error == null) error = e.message ?: e.toString()
            why = RecordingEnd.ERROR
        }
        val saved = RecordingSaved(
            name = recordingName ?: partName(1),
            parts = partsWritten.toLong(),
            durationMs = ticksBefore * 1000 / Fmp4.TIMESCALE,
            bytes = bytesBefore,
            reason = why,
            message = error,
        )
        resetCounters()
        state = RecordingState.IDLE
        open = null
        closed = null
        if (reason != RecordingEnd.USER || saved.parts > 0) onSaved(saved)
        publishStatus()
        return saved
    }

    private fun recoverPart(journal: PartJournal): RecordingSaved? {
        val s = journal.readState() ?: return null.also { journal.delete() }
        val sink = store.open(s.id, s.displayName) ?: return null.also { journal.delete() }
        try {
            // Drop a fragment the crash cut short, and any index entry the file does not back.
            val fragments = journal.readFragments().toMutableList()
            val size = sink.size()
            while (fragments.isNotEmpty() && s.headerSize + fragments.sumOf { it.first.toLong() } > size) {
                fragments.removeAt(fragments.lastIndex)
            }
            if (fragments.isEmpty()) {
                sink.discard()
                journal.delete()
                if (s.partNumber == 1) return null
                return RecordingSaved(
                    name = s.recordingName,
                    parts = (s.partNumber - 1).toLong(),
                    durationMs = s.ticksBefore * 1000 / Fmp4.TIMESCALE,
                    bytes = s.bytesBefore,
                    reason = RecordingEnd.RECOVERED,
                )
            }
            val initSize = Fmp4.init(s.track, durationTicks = 1).size
            finalizePart(sink, s.track, initSize, s.headerSize, fragments)
            journal.delete()
            return RecordingSaved(
                name = s.recordingName,
                parts = s.partNumber.toLong(),
                durationMs = (s.ticksBefore + fragments.sumOf { it.second }) * 1000 / Fmp4.TIMESCALE,
                bytes = s.bytesBefore + s.headerSize + fragments.sumOf { it.first.toLong() },
                reason = RecordingEnd.RECOVERED,
            )
        } catch (_: Exception) {
            runCatching { sink.close() }
            journal.close()
            return null // Kept for the next attempt.
        }
    }

    /** Truncates to the written fragments, patches the duration and writes the index, then publishes. */
    private fun finalizePart(sink: PartSink, track: TrackInfo, initSize: Int, headerSize: Long, fragments: List<Pair<Int, Long>>) {
        val ticks = fragments.sumOf { it.second }
        sink.truncate(headerSize + fragments.sumOf { it.first.toLong() })
        val init = Fmp4.init(track, durationTicks = ticks.coerceAtLeast(1))
        check(init.size == initSize) { "Init size changed: $initSize -> ${init.size}" }
        sink.writeAt(0, init)
        val reserved = (headerSize - initSize).toInt()
        val sidxSize = Fmp4.sidxSize(fragments.size)
        val freeSize = reserved - sidxSize
        check(freeSize >= MIN_FREE_BOX) { "Index of ${fragments.size} fragments does not fit in $reserved bytes" }
        sink.writeAt(initSize.toLong(), Fmp4.sidx(fragments, firstOffset = freeSize.toLong()) + Fmp4.free(freeSize))
        sink.publish()
    }

    private fun resetCounters() {
        recordingName = null
        partsWritten = 0
        ticksBefore = 0
        bytesBefore = 0
        lastWritten = null
        lowSpace = false
    }

    /** Builds the status, refreshes the snapshot and the [lowSpace] flag. */
    private fun snapshot(): RecordingStatus {
        val p = part
        val ticks = ticksBefore + (p?.ticks ?: 0)
        val bytes = bytesBefore + (p?.bytes ?: 0)
        val free = freeBytes()
        val remaining = remainingMs(free, ticks, bytes, bitrate)
        lowSpace = state != RecordingState.IDLE && remaining != null && remaining < LOW_SPACE_MS
        return RecordingStatus(
            state = state,
            elapsedMs = ticks * 1000 / Fmp4.TIMESCALE,
            bytes = bytes,
            parts = partsWritten.toLong(),
            freeBytes = free,
            remainingMs = remaining,
            lowSpace = lowSpace,
        ).also { latest = it }
    }

    private fun publishStatus(): RecordingStatus = snapshot().also(onStatus)

    private fun partName(number: Int): String {
        val stamp = SimpleDateFormat("yyyy-MM-dd_HH-mm", Locale.ROOT).format(Date(recordingStartMs))
        return if (number == 1) "InstantReplay_$stamp.mp4" else "InstantReplay_${stamp}_part$number.mp4"
    }

    // endregion

    private fun post(task: () -> Unit) {
        try {
            executor.execute(task)
        } catch (_: Exception) {
            // Released.
        }
    }

    /** Runs [block] on the executor and completes [callback] from there. */
    private fun <T> call(callback: (Result<T>) -> Unit, block: () -> T) {
        try {
            executor.execute {
                val result = try {
                    Result.success(block())
                } catch (e: FlutterError) {
                    Result.failure(e)
                } catch (e: Exception) {
                    Result.failure(FlutterError("recording_failed", e.message ?: e.toString()))
                }
                callback(result)
            }
        } catch (e: Exception) {
            callback(Result.failure(FlutterError("recording_failed", "Recorder released")))
        }
    }

    internal companion object {
        /** 4 h at one fragment per second. */
        const val MAX_FRAGMENTS_PER_PART = 4 * 60 * 60
        const val MIN_FREE_TO_START = 1L shl 30
        const val MIN_FREE_TO_CONTINUE = 500L shl 20
        const val LOW_SPACE_MS = 10 * 60 * 1000L
        /** Smallest `free` box, so one always follows the index. */
        private const val MIN_FREE_BOX = 8

        /**
         * Time left before [MIN_FREE_TO_CONTINUE] at the measured rate (video bytes per video
         * second, after a few seconds), else at the encoder bitrate. Null when neither is known.
         */
        fun remainingMs(free: Long, ticks: Long, bytes: Long, bitrate: Int): Long? {
            val bytesPerSecond = when {
                ticks >= 5L * Fmp4.TIMESCALE && bytes > 0 -> bytes * Fmp4.TIMESCALE / ticks
                bitrate > 0 -> bitrate / 8L
                else -> return null
            }
            return (free - MIN_FREE_TO_CONTINUE).coerceAtLeast(0) * 1000 / bytesPerSecond.coerceAtLeast(1)
        }
    }
}
