package io.github.instantreplay.replay_capture_android.recording

import io.github.instantreplay.replay_capture_android.mp4.TrackInfo
import java.io.BufferedOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.EOFException
import java.io.File
import java.io.FileOutputStream
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.util.Base64
import java.util.Properties

/** Everything needed to finalize an open part after a crash, plus the totals of the parts before it. */
internal data class PartState(
    val id: String,
    val displayName: String,
    val track: TrackInfo,
    /** Init segment + reserved index region; fragments start here. */
    val headerSize: Long,
    val recordingStartMs: Long,
    val partNumber: Int,
    /** Name of the recording's first part, reported in [io.github.instantreplay.replay_capture_android.RecordingSaved]. */
    val recordingName: String,
    val ticksBefore: Long,
    val bytesBefore: Long,
)

/**
 * Crash journal of one open part, in the recorder's state directory:
 * `<key>.state` ([PartState] as a properties file, written once when the part opens) and
 * `<key>.idx`, an append-only list of `(u32 fragment size, u64 duration ticks)` records written after
 * each fragment write completes. A torn trailing record is ignored. Plain java.util formats because
 * `org.json` is a stub in JVM unit tests.
 */
internal class PartJournal private constructor(private val stateFile: File) {

    private val indexFile = File(stateFile.path.removeSuffix(STATE_SUFFIX) + INDEX_SUFFIX)
    private var index: DataOutputStream? = null

    fun writeState(state: PartState) {
        val p = Properties()
        p["id"] = state.id
        p["displayName"] = state.displayName
        p["width"] = state.track.width.toString()
        p["height"] = state.track.height.toString()
        p["rotationDeg"] = state.track.rotationDeg.toString()
        p["sps"] = Base64.getEncoder().encodeToString(state.track.sps)
        p["pps"] = Base64.getEncoder().encodeToString(state.track.pps)
        p["headerSize"] = state.headerSize.toString()
        p["recordingStartMs"] = state.recordingStartMs.toString()
        p["partNumber"] = state.partNumber.toString()
        p["recordingName"] = state.recordingName
        p["ticksBefore"] = state.ticksBefore.toString()
        p["bytesBefore"] = state.bytesBefore.toString()
        stateFile.parentFile?.mkdirs()
        val tmp = File(stateFile.path + ".tmp")
        tmp.outputStream().use { p.store(it, null) }
        Files.move(tmp.toPath(), stateFile.toPath(), StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE)
    }

    /** Null when the state file is missing or unreadable. */
    fun readState(): PartState? = try {
        val p = Properties()
        stateFile.inputStream().use { p.load(it) }
        fun s(key: String) = checkNotNull(p.getProperty(key)) { "missing $key" }
        PartState(
            id = s("id"),
            displayName = s("displayName"),
            track = TrackInfo(
                width = s("width").toInt(),
                height = s("height").toInt(),
                sps = Base64.getDecoder().decode(s("sps")),
                pps = Base64.getDecoder().decode(s("pps")),
                rotationDeg = s("rotationDeg").toInt(),
            ),
            headerSize = s("headerSize").toLong(),
            recordingStartMs = s("recordingStartMs").toLong(),
            partNumber = s("partNumber").toInt(),
            recordingName = s("recordingName"),
            ticksBefore = s("ticksBefore").toLong(),
            bytesBefore = s("bytesBefore").toLong(),
        )
    } catch (_: Exception) {
        null
    }

    fun appendFragment(size: Int, durationTicks: Long) {
        val out = index ?: DataOutputStream(BufferedOutputStream(FileOutputStream(indexFile, true), 64)).also { index = it }
        out.writeInt(size)
        out.writeLong(durationTicks)
        out.flush()
    }

    /** `(size, durationTicks)` per fragment, in write order. */
    fun readFragments(): List<Pair<Int, Long>> {
        if (!indexFile.isFile) return emptyList()
        val out = ArrayList<Pair<Int, Long>>()
        DataInputStream(indexFile.inputStream().buffered()).use { input ->
            try {
                while (true) {
                    val size = input.readInt()
                    val ticks = input.readLong()
                    out += size to ticks
                }
            } catch (_: EOFException) {
                // End of file, or a record torn by the crash.
            }
        }
        return out
    }

    fun close() {
        try {
            index?.close()
        } catch (_: Exception) {
        }
        index = null
    }

    /** Closes and removes both files: the part is finished or abandoned. */
    fun delete() {
        close()
        indexFile.delete()
        stateFile.delete()
    }

    companion object {
        private const val STATE_SUFFIX = ".state"
        private const val INDEX_SUFFIX = ".idx"

        fun create(dir: File, key: String) = PartJournal(File(dir, key + STATE_SUFFIX))

        /** Journals left behind in [dir], oldest key first. */
        fun leftovers(dir: File): List<PartJournal> =
            dir.listFiles { f -> f.name.endsWith(STATE_SUFFIX) }.orEmpty().sortedBy { it.name }.map(::PartJournal)

        /** Index files and temp files without a state file: nothing can be recovered from them. */
        fun cleanOrphans(dir: File) {
            val keys = dir.listFiles { f -> f.name.endsWith(STATE_SUFFIX) }.orEmpty().map { it.name.removeSuffix(STATE_SUFFIX) }.toSet()
            dir.listFiles().orEmpty()
                .filter { !it.name.endsWith(STATE_SUFFIX) && it.name.substringBefore('.') !in keys }
                .forEach { it.delete() }
        }
    }

    val key: String get() = stateFile.name.removeSuffix(STATE_SUFFIX)
}
