package io.github.instantreplay.replay_capture_android.broadcast

import android.media.MediaCodec
import android.media.MediaCodecInfo.CodecCapabilities
import android.media.MediaCodecInfo.CodecProfileLevel
import android.media.MediaCodecInfo.EncoderCapabilities
import android.media.MediaFormat
import android.os.Bundle
import android.os.Handler
import android.os.HandlerThread
import android.os.Process
import android.view.Surface
import java.nio.ByteBuffer

/**
 * H.264 encoder for the broadcast program (camera + scoreboard), fed by the GL thread through
 * [inputSurface] (SPEC §12.1). Unlike the HQ encoder it targets a network: CBR when supported,
 * GOP 2 s, and a bitrate that changes at runtime for adaptive streaming.
 *
 * Output (Annex-B, as MediaCodec produces it) arrives on its own thread `ir-program`; [onFrame]
 * must consume the buffer before returning.
 */
internal class ProgramEncoder(
    width: Int,
    height: Int,
    fps: Int,
    bitrateBps: Int,
    private val onFormat: (sps: ByteBuffer, pps: ByteBuffer) -> Unit,
    private val onFrame: (buffer: ByteBuffer, info: MediaCodec.BufferInfo) -> Unit,
    private val onError: (String) -> Unit,
) {
    private val thread = HandlerThread("ir-program", Process.THREAD_PRIORITY_URGENT_DISPLAY).apply { start() }
    private val codec: MediaCodec = MediaCodec.createEncoderByType(MIME)
    val inputSurface: Surface
    var usesHighProfile = false
        private set

    /** Encoded frames so far (for the program fps). */
    @Volatile var frames = 0L
        private set

    private val callback = object : MediaCodec.Callback() {
        override fun onInputBufferAvailable(codec: MediaCodec, index: Int) = Unit

        override fun onOutputBufferAvailable(codec: MediaCodec, index: Int, info: MediaCodec.BufferInfo) {
            try {
                val isConfig = info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0
                if (!isConfig && info.size > 0) {
                    val buffer = codec.getOutputBuffer(index)!!
                    buffer.position(info.offset)
                    buffer.limit(info.offset + info.size)
                    frames++
                    onFrame(buffer.slice(), info.apply { set(0, size, presentationTimeUs, flags) })
                }
                codec.releaseOutputBuffer(index, false)
            } catch (e: IllegalStateException) {
                // Codec stopped while a buffer was in flight.
            }
        }

        override fun onOutputFormatChanged(codec: MediaCodec, format: MediaFormat) {
            val sps = format.getByteBuffer("csd-0") ?: return
            val pps = format.getByteBuffer("csd-1") ?: return
            onFormat(sps, pps)
        }

        override fun onError(codec: MediaCodec, e: MediaCodec.CodecException) {
            onError("Program encoder error: ${e.diagnosticInfo}")
        }
    }

    init {
        val handler = Handler(thread.looper)
        val base = MediaFormat.createVideoFormat(MIME, width, height).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT, CodecCapabilities.COLOR_FormatSurface)
            setInteger(MediaFormat.KEY_BIT_RATE, bitrateBps)
            setInteger(MediaFormat.KEY_FRAME_RATE, fps)
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 2)
            setInteger(MediaFormat.KEY_MAX_B_FRAMES, 0)
            setInteger(MediaFormat.KEY_PRIORITY, 0) // realtime
        }
        val caps = codec.codecInfo.getCapabilitiesForType(MIME)
        // A network stream wants a steady rate; VBR is the fallback so the encoder accepts the format.
        val mode = listOf(EncoderCapabilities.BITRATE_MODE_CBR, EncoderCapabilities.BITRATE_MODE_VBR)
            .firstOrNull { caps.encoderCapabilities?.isBitrateModeSupported(it) == true }
        mode?.let { base.setInteger(MediaFormat.KEY_BITRATE_MODE, it) }

        val format = MediaFormat(base)
        val high = caps.profileLevels.filter { it.profile == CodecProfileLevel.AVCProfileHigh }.maxByOrNull { it.level }
        if (high != null) {
            format.setInteger(MediaFormat.KEY_PROFILE, CodecProfileLevel.AVCProfileHigh)
            format.setInteger(MediaFormat.KEY_LEVEL, high.level)
        }
        codec.setCallback(callback, handler)
        usesHighProfile = try {
            codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            high != null
        } catch (e: Exception) {
            // Some encoders reject explicit profile/level; fall back to their defaults.
            codec.reset()
            codec.setCallback(callback, handler)
            codec.configure(base, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            false
        }
        inputSurface = codec.createInputSurface()
        codec.start()
    }

    /** Adaptive bitrate: takes effect within a few frames, no restart. */
    fun setBitrate(bps: Int) = setParameter(MediaCodec.PARAMETER_KEY_VIDEO_BITRATE, bps)

    /** Next frame becomes an IDR, e.g. right after an RTMP reconnection. */
    fun requestKeyframe() = setParameter(MediaCodec.PARAMETER_KEY_REQUEST_SYNC_FRAME, 0)

    private fun setParameter(key: String, value: Int) {
        try {
            codec.setParameters(Bundle().apply { putInt(key, value) })
        } catch (_: IllegalStateException) {
            // Released meanwhile.
        }
    }

    /** Call after the GL thread stopped drawing into [inputSurface]. */
    fun release() {
        try {
            codec.stop()
        } catch (_: IllegalStateException) {
        }
        codec.release()
        inputSurface.release()
        thread.quitSafely()
    }

    private companion object {
        const val MIME = MediaFormat.MIMETYPE_VIDEO_AVC
    }
}
