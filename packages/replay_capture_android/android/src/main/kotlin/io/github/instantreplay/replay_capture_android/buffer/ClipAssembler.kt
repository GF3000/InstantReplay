package io.github.instantreplay.replay_capture_android.buffer

import io.github.instantreplay.replay_capture_android.mp4.Fmp4
import java.io.BufferedOutputStream
import java.io.File
import java.io.FileOutputStream
import java.nio.file.Files
import java.nio.file.StandardCopyOption

/** Result of writing one clip file. */
internal data class Assembly(
    val bytes: Long,
    val durationMs: Long,
    val fragments: Int,
    val assemblyMs: Long,
    /** How much earlier than requested the clip starts (keyframe alignment). */
    val extraPreRollMs: Long,
)

/** A clip whose window is fixed; [assemble] blocks until it can be written to [target]. */
internal fun interface ClipJob {
    fun assemble(target: File): Assembly
}

/** Where the outbox gets clips from. [mark] fixes `t0 = now` and must not block. */
internal fun interface ClipSource {
    fun mark(preSeconds: Double, postSeconds: Double): ClipJob
}

/** Builds a self-contained, seekable fMP4 clip from ring-buffer fragments without re-encoding. */
internal class ClipAssembler(
    private val ring: RingBuffer,
    /** A fragment closes at the next keyframe, so allow some slack on top of the post-roll. */
    private val graceMs: Long = 3_000,
) : ClipSource {

    override fun mark(preSeconds: Double, postSeconds: Double): ClipJob {
        val t0 = ring.cursor()
        check(t0.ptsUs >= 0) { "No frames encoded yet" }
        val fromUs = t0.ptsUs - (preSeconds * 1_000_000).toLong()
        val toUs = t0.ptsUs + (postSeconds * 1_000_000).toLong()
        val waitMs = (postSeconds * 1000).toLong() + graceMs
        return ClipJob { target -> assemble(t0.epoch, fromUs, toUs, waitMs, target) }
    }

    /**
     * Blocking: waits for the post-roll, then concatenates. Only fragments of [epoch] are used,
     * so a window crossing an epoch boundary is truncated to it.
     */
    fun assemble(epoch: Int, fromUs: Long, toUs: Long, waitMs: Long, target: File): Assembly {
        check(ring.awaitEnd(epoch, toUs, waitMs)) { "Timed out waiting for post-roll" }

        val started = System.nanoTime()
        val fragments = ring.select(epoch, fromUs, toUs)
        check(fragments.isNotEmpty()) { "Buffer is empty" }
        val track = checkNotNull(ring.trackFor(epoch)) { "No codec configuration for epoch $epoch" }
        val durationTicks = fragments.sumOf { it.durationTicks }
        val originTicks = fragments.first().baseTicks

        target.parentFile?.mkdirs()
        val tmp = File(target.path + ".part")
        try {
            BufferedOutputStream(FileOutputStream(tmp), 1 shl 20).use { out ->
                out.write(Fmp4.init(track, durationTicks))
                out.write(Fmp4.sidx(fragments.map { it.bytes.toInt() to it.durationTicks }))
                fragments.forEachIndexed { i, f ->
                    val data = f.file.readBytes()
                    Fmp4.patchFragment(data, i + 1, f.baseTicks - originTicks)
                    out.write(data)
                }
            }
            Files.move(tmp.toPath(), target.toPath(), StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE)
        } catch (e: Exception) {
            tmp.delete()
            throw e
        }

        return Assembly(
            bytes = target.length(),
            durationMs = durationTicks * 1000 / Fmp4.TIMESCALE,
            fragments = fragments.size,
            assemblyMs = (System.nanoTime() - started) / 1_000_000,
            extraPreRollMs = (fromUs - fragments.first().startUs).coerceAtLeast(0) / 1000,
        )
    }
}
