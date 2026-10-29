package io.github.instantreplay.replay_capture_android

import android.media.MediaCodec
import android.media.MediaCodecInfo.CodecCapabilities
import android.media.MediaCodecInfo.CodecProfileLevel
import android.media.MediaCodecInfo.EncoderCapabilities
import android.media.MediaFormat
import android.os.Handler
import android.view.Surface
import io.github.instantreplay.replay_capture_android.mp4.Avc
import io.github.instantreplay.replay_capture_android.mp4.TrackInfo

/** Hardware H.264 encoder fed through an input Surface; output is delivered on [handler]'s thread. */
internal class HqEncoder(
    private val config: CaptureConfig,
    handler: Handler,
    private val onTrack: (TrackInfo) -> Unit,
    private val onFrame: (ptsUs: Long, isKeyframe: Boolean, avcc: ByteArray) -> Unit,
    private val onError: (String) -> Unit,
) {
    private val codec: MediaCodec = MediaCodec.createEncoderByType(MIME)
    val inputSurface: Surface
    val codecName: String get() = codec.name
    var usesHighProfile = false
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
                    val isKey = info.flags and MediaCodec.BUFFER_FLAG_KEY_FRAME != 0
                    onFrame(info.presentationTimeUs, isKey, Avc.toAvcc(buffer))
                }
                codec.releaseOutputBuffer(index, false)
            } catch (e: IllegalStateException) {
                // Codec stopped while a buffer was in flight.
            }
        }

        override fun onOutputFormatChanged(codec: MediaCodec, format: MediaFormat) {
            onTrack(
                TrackInfo(
                    width = format.getInteger(MediaFormat.KEY_WIDTH),
                    height = format.getInteger(MediaFormat.KEY_HEIGHT),
                    sps = Avc.parameterSet(format.getByteBuffer("csd-0")!!),
                    pps = Avc.parameterSet(format.getByteBuffer("csd-1")!!),
                ),
            )
        }

        override fun onError(codec: MediaCodec, e: MediaCodec.CodecException) {
            onError("Encoder error: ${e.diagnosticInfo}")
        }
    }

    init {
        val format = baseFormat()
        val caps = codec.codecInfo.getCapabilitiesForType(MIME)
        val high = caps.profileLevels.filter { it.profile == CodecProfileLevel.AVCProfileHigh }.maxByOrNull { it.level }
        if (high != null) {
            format.setInteger(MediaFormat.KEY_PROFILE, CodecProfileLevel.AVCProfileHigh)
            format.setInteger(MediaFormat.KEY_LEVEL, high.level)
        }
        if (caps.encoderCapabilities.isBitrateModeSupported(EncoderCapabilities.BITRATE_MODE_VBR)) {
            format.setInteger(MediaFormat.KEY_BITRATE_MODE, EncoderCapabilities.BITRATE_MODE_VBR)
        }

        codec.setCallback(callback, handler)
        usesHighProfile = try {
            codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            high != null
        } catch (e: Exception) {
            // Some encoders reject explicit profile/level; fall back to their defaults.
            codec.reset()
            codec.setCallback(callback, handler)
            codec.configure(baseFormat(), null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            false
        }
        inputSurface = codec.createInputSurface()
        codec.start()
    }

    private fun baseFormat() = MediaFormat.createVideoFormat(MIME, config.width, config.height).apply {
        setInteger(MediaFormat.KEY_COLOR_FORMAT, CodecCapabilities.COLOR_FormatSurface)
        setInteger(MediaFormat.KEY_BIT_RATE, config.bitrate)
        setInteger(MediaFormat.KEY_FRAME_RATE, config.fps)
        setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
        setInteger(MediaFormat.KEY_MAX_B_FRAMES, 0)
        setInteger(MediaFormat.KEY_PRIORITY, 0) // realtime
    }

    fun release() {
        try {
            codec.stop()
        } catch (_: IllegalStateException) {
        }
        codec.release()
        inputSurface.release()
    }

    private companion object {
        const val MIME = MediaFormat.MIMETYPE_VIDEO_AVC
    }
}
