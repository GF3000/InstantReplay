package io.github.instantreplay.instant_replay

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import java.io.File
import java.io.IOException
import java.nio.ByteBuffer
import java.util.concurrent.Executors

/**
 * Joins library clips (video only, no audio) into one MP4 by copying their samples back to back,
 * without re-encoding. The output takes the first clip's track format, so clips should share the
 * same codec and resolution (they do when recorded by the same Camera profile).
 */
object ClipConcat {
    const val CHANNEL = "instant_replay/export"
    const val TAG = "ClipConcat"

    val executor = Executors.newSingleThreadExecutor()

    fun concat(inputs: List<String>, output: String) {
        require(inputs.isNotEmpty()) { "No clips" }
        File(output).delete()
        val muxer = MediaMuxer(output, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        var track = -1
        var offsetUs = 0L
        var buffer = ByteBuffer.allocate(4 * 1024 * 1024)
        val info = MediaCodec.BufferInfo()
        try {
            for (path in inputs) {
                val extractor = MediaExtractor()
                try {
                    extractor.setDataSource(path)
                    val index = (0 until extractor.trackCount).firstOrNull {
                        extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("video/") == true
                    } ?: continue
                    val format = extractor.getTrackFormat(index)
                    extractor.selectTrack(index)
                    if (track < 0) {
                        if (format.containsKey(MediaFormat.KEY_ROTATION)) {
                            muxer.setOrientationHint(format.getInteger(MediaFormat.KEY_ROTATION))
                        }
                        track = muxer.addTrack(format)
                        muxer.start()
                    }
                    if (format.containsKey(MediaFormat.KEY_MAX_INPUT_SIZE)) {
                        val max = format.getInteger(MediaFormat.KEY_MAX_INPUT_SIZE)
                        if (max > buffer.capacity()) buffer = ByteBuffer.allocate(max)
                    }
                    val frameUs = if (format.containsKey(MediaFormat.KEY_FRAME_RATE)) {
                        1_000_000L / maxOf(1, format.getInteger(MediaFormat.KEY_FRAME_RATE))
                    } else 33_333L
                    var firstUs = -1L
                    var lastUs = offsetUs
                    while (true) {
                        buffer.clear()
                        val size = extractor.readSampleData(buffer, 0)
                        if (size < 0) break
                        val t = extractor.sampleTime
                        if (firstUs < 0) firstUs = t
                        info.set(
                            0, size, offsetUs + (t - firstUs),
                            if (extractor.sampleFlags and MediaExtractor.SAMPLE_FLAG_SYNC != 0) MediaCodec.BUFFER_FLAG_KEY_FRAME else 0,
                        )
                        muxer.writeSampleData(track, buffer, info)
                        lastUs = maxOf(lastUs, info.presentationTimeUs)
                        extractor.advance()
                    }
                    if (firstUs >= 0) offsetUs = lastUs + frameUs
                } finally {
                    extractor.release()
                }
            }
            if (track < 0) throw IOException("No video in the selected clips")
            muxer.stop()
        } finally {
            muxer.release()
        }
    }
}
