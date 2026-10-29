package io.github.instantreplay.replay_capture_android.outbox

import io.github.instantreplay.replay_capture_android.ClipInfo
import io.github.instantreplay.replay_capture_android.ClipState
import java.io.File
import java.nio.file.Files
import java.nio.file.StandardCopyOption

/**
 * Persisted outbox index: UTF-8 text, a version header, then one tab-separated line per clip:
 *
 * `id  requestId  state  createdAtMs  bytes  durationMs  fragments  assemblyMs  extraPreRollMs  sha256`
 *
 * Empty field = null. `\`, tab, CR and LF inside fields are backslash-escaped. The clip path is not
 * stored; it is always `<dir>/<id>.mp4`. Written to a temp file and atomically renamed.
 * (Hand-written because `org.json` is a stub in JVM unit tests.)
 */
internal class OutboxIndex(private val file: File) {

    fun read(): List<ClipInfo> {
        if (!file.isFile) return emptyList()
        val lines = try {
            file.readLines(Charsets.UTF_8)
        } catch (_: Exception) {
            return emptyList()
        }
        if (lines.firstOrNull() != HEADER) return emptyList()
        return lines.drop(1).mapNotNull(::parse)
    }

    fun write(clips: Collection<ClipInfo>) {
        val text = buildString {
            append(HEADER).append('\n')
            for (clip in clips) append(format(clip)).append('\n')
        }
        val tmp = File(file.path + ".tmp")
        tmp.writeText(text, Charsets.UTF_8)
        Files.move(tmp.toPath(), file.toPath(), StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE)
    }

    private fun format(c: ClipInfo): String = listOf(
        c.id, c.requestId, c.state.name, c.createdAtMs.toString(),
        c.bytes?.toString(), c.durationMs?.toString(), c.fragments?.toString(),
        c.assemblyMs?.toString(), c.extraPreRollMs?.toString(), c.sha256,
    ).joinToString("\t") { escape(it ?: "") }

    private fun parse(line: String): ClipInfo? {
        if (line.isEmpty()) return null
        val f = line.split('\t').map(::unescape)
        if (f.size != FIELDS) return null
        fun long(i: Int) = f[i].takeIf { it.isNotEmpty() }?.toLongOrNull()
        return ClipInfo(
            id = f[0].takeIf { it.isNotEmpty() } ?: return null,
            requestId = f[1],
            state = ClipState.entries.firstOrNull { it.name == f[2] } ?: return null,
            createdAtMs = long(3) ?: return null,
            bytes = long(4),
            durationMs = long(5),
            fragments = long(6),
            assemblyMs = long(7),
            extraPreRollMs = long(8),
            sha256 = f[9].takeIf { it.isNotEmpty() },
        )
    }

    companion object {
        const val FILE_NAME = "index.tsv"
        private const val HEADER = "instantreplay-outbox\t1"
        private const val FIELDS = 10

        fun escape(s: String): String = buildString {
            for (ch in s) when (ch) {
                '\\' -> append("\\\\")
                '\t' -> append("\\t")
                '\n' -> append("\\n")
                '\r' -> append("\\r")
                else -> append(ch)
            }
        }

        fun unescape(s: String): String {
            if ('\\' !in s) return s
            return buildString {
                var i = 0
                while (i < s.length) {
                    val ch = s[i++]
                    if (ch != '\\' || i == s.length) {
                        append(ch)
                        continue
                    }
                    when (val next = s[i++]) {
                        't' -> append('\t')
                        'n' -> append('\n')
                        'r' -> append('\r')
                        else -> append(next)
                    }
                }
            }
        }
    }
}
