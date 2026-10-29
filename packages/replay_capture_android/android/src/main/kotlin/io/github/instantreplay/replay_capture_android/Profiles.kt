package io.github.instantreplay.replay_capture_android

import android.content.Context
import android.graphics.SurfaceTexture
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager

/** Capture profiles the back camera supports in a regular session (SPEC D12). */
internal object Profiles {
    private val candidates = listOf(
        CaptureProfile(id = "1080p60", width = 1920L, height = 1080L, fps = 60L, bitrate = 20_000_000L),
        CaptureProfile(id = "1080p30", width = 1920L, height = 1080L, fps = 30L, bitrate = 12_000_000L),
        CaptureProfile(id = "720p30", width = 1280L, height = 720L, fps = 30L, bitrate = 5_000_000L),
    )

    /** Best first. Excludes profiles that only exist in constrained high-speed sessions. */
    fun supported(context: Context): List<CaptureProfile> {
        val manager = context.getSystemService(CameraManager::class.java)
        val id = manager.cameraIdList.firstOrNull {
            manager.getCameraCharacteristics(it).get(CameraCharacteristics.LENS_FACING) ==
                CameraCharacteristics.LENS_FACING_BACK
        } ?: return emptyList()
        val chars = manager.getCameraCharacteristics(id)
        val sizes = chars.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
            ?.getOutputSizes(SurfaceTexture::class.java).orEmpty()
        val fpsRanges = chars.get(CameraCharacteristics.CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES).orEmpty()
        return candidates.filter { p ->
            sizes.any { it.width == p.width.toInt() && it.height == p.height.toInt() } &&
                fpsRanges.any { it.upper == p.fps.toInt() }
        }
    }
}
