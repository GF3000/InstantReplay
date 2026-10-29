package io.github.instantreplay.replay_capture_android.buffer

import android.os.SystemClock
import io.github.instantreplay.replay_capture_android.mp4.Fmp4
import java.io.BufferedOutputStream
import java.io.File
import java.io.FileOutputStream

/** Builds a self-contained, seekable fMP4 clip from ring-buffer fragments without re-encoding. */
internal class ClipAssembler(private val ring: RingBuffer, private val outDir: File) {

    /** Blocking: waits for the post-roll, then concatenates. Call off the main thread. */
    fun save(preSeconds: Double, postSeconds: Double): Map<String, Any> {
        val t0 = ring.latestPtsUs
        check(t0 >= 0) { "No frames encoded yet" }
        val fromUs = t0 - (preSeconds * 1_000_000).toLong()
        val toUs = t0 + (postSeconds * 1_000_000).toLong()

        // A fragment closes at the next keyframe, so allow one GOP on top of the post-roll.
        val waitMs = (postSeconds * 1000).toLong() + 3_000
        check(ring.awaitEnd(toUs, waitMs)) { "Timed out waiting for post-roll" }

        val started = SystemClock.elapsedRealtime()
        val fragments = ring.select(fromUs, toUs)
        check(fragments.isNotEmpty()) { "Buffer is empty" }
        val track = checkNotNull(ring.track)
        val durationTicks = fragments.sumOf { it.durationTicks }
        val originTicks = fragments.first().baseTicks

        outDir.mkdirs()
        val name = "clip_${System.currentTimeMillis()}.mp4"
        val tmp = File(outDir, "$name.part")
        BufferedOutputStream(FileOutputStream(tmp), 1 shl 20).use { out ->
            out.write(Fmp4.init(track, durationTicks))
            out.write(Fmp4.sidx(fragments.map { it.bytes.toInt() to it.durationTicks }))
            fragments.forEachIndexed { i, f ->
                val data = f.file.readBytes()
                Fmp4.patchFragment(data, i + 1, f.baseTicks - originTicks)
                out.write(data)
            }
        }
        val file = File(outDir, name)
        check(tmp.renameTo(file)) { "Could not finalize $name" }

        return mapOf(
            "path" to file.absolutePath,
            "name" to name,
            "bytes" to file.length(),
            "durationMs" to durationTicks * 1000 / Fmp4.TIMESCALE,
            "fragments" to fragments.size,
            "assemblyMs" to SystemClock.elapsedRealtime() - started,
            // How much earlier than requested the clip starts (keyframe alignment).
            "extraPreRollMs" to (fromUs - fragments.first().startUs).coerceAtLeast(0) / 1000,
        )
    }
}
