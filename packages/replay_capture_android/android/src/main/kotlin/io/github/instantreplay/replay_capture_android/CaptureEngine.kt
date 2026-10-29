package io.github.instantreplay.replay_capture_android

import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.SurfaceTexture
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CaptureFailure
import android.hardware.camera2.CaptureRequest
import android.hardware.camera2.CaptureResult
import android.hardware.camera2.TotalCaptureResult
import android.hardware.camera2.params.OutputConfiguration
import android.hardware.camera2.params.SessionConfiguration
import android.opengl.EGLSurface
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.PowerManager
import android.util.Range
import android.view.Surface
import io.github.instantreplay.replay_capture_android.buffer.RingBuffer
import io.github.instantreplay.replay_capture_android.buffer.Segmenter
import io.github.instantreplay.replay_capture_android.gl.EglCore
import io.github.instantreplay.replay_capture_android.gl.OesRenderer
import java.util.concurrent.ExecutionException
import java.util.concurrent.Executor
import java.util.concurrent.FutureTask

data class CaptureConfig(
    val width: Int,
    val height: Int,
    val fps: Int,
    val bitrate: Int,
    val windowSeconds: Int,
)

/**
 * Single owner of the camera. Frames land in one OES texture and are fanned out by GL to the
 * HQ encoder surface and the optional preview and live-view (WebRTC) surfaces.
 *
 * Threads: `ir-gl` (EGL, SurfaceTexture, stats), `ir-camera` (Camera2 callbacks),
 * `ir-encoder` (encoder output, segmenting, ring writes).
 */
internal class CaptureEngine(
    context: Context,
    private val config: CaptureConfig,
    private val ring: RingBuffer,
    private val emit: (Map<String, Any?>) -> Unit,
) {
    private val cameraManager = context.getSystemService(CameraManager::class.java)
    private val powerManager = context.getSystemService(PowerManager::class.java)
    private val batteryManager = context.getSystemService(BatteryManager::class.java)
    private val appContext = context.applicationContext

    private val glThread = HandlerThread("ir-gl").apply { start() }
    private val glHandler = Handler(glThread.looper)
    private val cameraThread = HandlerThread("ir-camera").apply { start() }
    private val cameraHandler = Handler(cameraThread.looper)
    private val encoderThread = HandlerThread("ir-encoder").apply { start() }
    private val encoderHandler = Handler(encoderThread.looper)
    // Stats involve binder calls (battery, thermal headroom); keep them off the GL thread.
    private val statsThread = HandlerThread("ir-stats").apply { start() }
    private val statsHandler = Handler(statsThread.looper)

    // GL-thread state.
    private var egl: EglCore? = null
    private var renderer: OesRenderer? = null
    private var surfaceTexture: SurfaceTexture? = null
    private var cameraSurface: Surface? = null
    private var encoderEglSurface: EGLSurface? = null
    private var preview: Output? = null
    private var live: Output? = null
    private val texMatrix = FloatArray(16)
    @Volatile private var renderedFrames = 0L
    private var lastDrawNs = 0L

    private var encoder: HqEncoder? = null
    private val segmenter = Segmenter(ring, 1_000_000L / config.fps)
    private var camera: CameraDevice? = null
    private var session: CameraCaptureSession? = null
    @Volatile private var thermalStatus = PowerManager.THERMAL_STATUS_NONE
    private var lastStatsFrames = 0L
    private var statsTicks = 0
    private var released = false

    var sensorOrientation = 0
        private set
    val encoderName: String get() = encoder?.codecName ?: ""
    val highProfile: Boolean get() = encoder?.usesHighProfile ?: false

    private val thermalListener = PowerManager.OnThermalStatusChangedListener { status ->
        thermalStatus = status
        emit(mapOf("type" to "thermal", "status" to status))
    }

    /** Sets up encoder and GL synchronously, then opens the camera asynchronously. */
    fun start() {
        val (cameraId, fpsRange) = selectCamera()
        onGl {
            val enc = HqEncoder(
                config, encoderHandler,
                onTrack = { ring.track = it },
                onFrame = segmenter::onFrame,
                onError = { emitError(it) },
            )
            encoder = enc
            val core = EglCore()
            egl = core
            val encSurface = core.createWindowSurface(enc.inputSurface)
            encoderEglSurface = encSurface
            core.makeCurrent(encSurface)
            val gl = OesRenderer()
            renderer = gl
            val st = SurfaceTexture(gl.textureId).apply {
                setDefaultBufferSize(config.width, config.height)
                setOnFrameAvailableListener({ drawFrame() }, glHandler)
            }
            surfaceTexture = st
            cameraSurface = Surface(st)
        }
        powerManager.addThermalStatusListener(Executor { statsHandler.post(it) }, thermalListener)
        thermalStatus = powerManager.currentThermalStatus
        openCamera(cameraId, fpsRange)
        statsHandler.postDelayed(::emitStats, STATS_INTERVAL_MS)
    }

    /** Replaces the preview target; pass null to stop drawing it. Blocks until applied. */
    fun setPreviewSurface(surface: Surface?, width: Int, height: Int) = onGl {
        preview = replaceOutput(preview, surface, width, height)
    }

    /** Replaces the live-view (WebRTC) target; pass null to stop drawing it. Blocks until applied. */
    fun setLiveSurface(surface: Surface?, width: Int, height: Int) = onGl {
        live = replaceOutput(live, surface, width, height)
    }

    private fun replaceOutput(current: Output?, surface: Surface?, width: Int, height: Int): Output? {
        val core = egl ?: return null
        current?.let { core.releaseSurface(it.surface) }
        return surface?.let {
            val egl = core.createWindowSurface(it)
            core.setSwapInterval(egl, 0)
            Output(egl, width, height)
        }
    }

    fun release() {
        if (released) return
        released = true
        powerManager.removeThermalStatusListener(thermalListener)
        statsHandler.removeCallbacksAndMessages(null)
        statsThread.quitSafely()
        session?.close()
        camera?.close()
        onGl {
            glHandler.removeCallbacksAndMessages(null)
            val core = egl
            if (core != null) {
                preview?.let { core.releaseSurface(it.surface) }
                live?.let { core.releaseSurface(it.surface) }
                encoderEglSurface?.let { core.releaseSurface(it) }
                renderer?.release()
                core.release()
            }
            surfaceTexture?.release()
            cameraSurface?.release()
            egl = null
        }
        encoder?.release()
        glThread.quitSafely()
        cameraThread.quitSafely()
        encoderThread.quitSafely()
    }

    private fun selectCamera(): Pair<String, Range<Int>> {
        val id = cameraManager.cameraIdList.firstOrNull {
            cameraManager.getCameraCharacteristics(it).get(CameraCharacteristics.LENS_FACING) ==
                CameraCharacteristics.LENS_FACING_BACK
        } ?: error("No back camera")
        val chars = cameraManager.getCameraCharacteristics(id)
        sensorOrientation = chars.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 0

        val sizes = chars.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)!!
            .getOutputSizes(SurfaceTexture::class.java)
        require(sizes.any { it.width == config.width && it.height == config.height }) {
            "Camera does not support ${config.width}x${config.height}"
        }
        val range = chars.get(CameraCharacteristics.CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES)!!
            .filter { it.upper == config.fps }
            .maxByOrNull { it.lower }
            ?: error("Camera does not support ${config.fps} fps")
        return id to range
    }

    @SuppressLint("MissingPermission") // Checked by the plugin before start().
    private fun openCamera(id: String, fpsRange: Range<Int>) {
        cameraManager.openCamera(id, object : CameraDevice.StateCallback() {
            override fun onOpened(device: CameraDevice) {
                if (released) return device.close()
                camera = device
                createSession(device, fpsRange)
            }

            override fun onDisconnected(device: CameraDevice) {
                device.close()
                emitError("Camera disconnected")
            }

            override fun onError(device: CameraDevice, error: Int) {
                device.close()
                emitError("Camera error $error")
            }
        }, cameraHandler)
    }

    private fun createSession(device: CameraDevice, fpsRange: Range<Int>) {
        val target = cameraSurface ?: return
        val callback = object : CameraCaptureSession.StateCallback() {
            override fun onConfigured(s: CameraCaptureSession) {
                if (released) return s.close()
                session = s
                val request = device.createCaptureRequest(CameraDevice.TEMPLATE_RECORD).apply {
                    addTarget(target)
                    set(CaptureRequest.CONTROL_AE_TARGET_FPS_RANGE, fpsRange)
                    set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_VIDEO)
                }.build()
                s.setRepeatingRequest(request, captureCounter, cameraHandler)
                emit(mapOf("type" to "camera", "state" to "streaming", "fpsRange" to fpsRange.toString()))
            }

            override fun onConfigureFailed(s: CameraCaptureSession) = emitError("Camera session configuration failed")
        }
        device.createCaptureSession(
            SessionConfiguration(
                SessionConfiguration.SESSION_REGULAR,
                listOf(OutputConfiguration(target)),
                Executor { cameraHandler.post(it) },
                callback,
            ),
        )
    }

    // Gap diagnostics: a gap is an interval > 1.5× nominal at that stage. Comparing camera gaps
    // (sensor timestamps) with GL gaps (SurfaceTexture timestamps) tells whether frames are lost
    // in the camera or coalesced because the GL thread was too slow to consume them.
    private val frameIntervalNs = 1_000_000_000L / config.fps
    @Volatile private var cameraFrames = 0L
    @Volatile private var cameraGaps = 0L
    @Volatile private var captureFailures = 0L
    private var lastSensorNs = 0L
    @Volatile private var glGaps = 0L
    private var lastGlNs = 0L
    @Volatile private var slowDraws = 0L
    @Volatile private var maxDrawMs = 0.0
    @Volatile private var skippedSecondary = 0L

    private val captureCounter = object : CameraCaptureSession.CaptureCallback() {
        override fun onCaptureCompleted(s: CameraCaptureSession, request: CaptureRequest, result: TotalCaptureResult) {
            val ts = result.get(CaptureResult.SENSOR_TIMESTAMP) ?: return
            if (lastSensorNs != 0L && ts - lastSensorNs > frameIntervalNs * 3 / 2) cameraGaps++
            lastSensorNs = ts
            cameraFrames++
        }

        override fun onCaptureFailed(s: CameraCaptureSession, request: CaptureRequest, failure: CaptureFailure) {
            captureFailures++
        }
    }

    private fun drawFrame() {
        val core = egl ?: return
        val st = surfaceTexture ?: return
        val gl = renderer ?: return
        val encSurface = encoderEglSurface ?: return
        val started = System.nanoTime()

        core.makeCurrent(encSurface)
        st.updateTexImage()
        st.getTransformMatrix(texMatrix)
        val ts = st.timestamp
        if (lastGlNs != 0L && ts - lastGlNs > frameIntervalNs * 3 / 2) glGaps++
        lastGlNs = ts
        gl.draw(texMatrix, config.width, config.height)
        core.setPresentationTime(encSurface, ts)
        core.swapBuffers(encSurface)
        renderedFrames++

        // Preview and live view at most 30 fps. The HQ encoder must get every frame, so if the
        // previous frame ran long, skip the secondary outputs once to catch up.
        val behind = lastDrawNs > frameIntervalNs * 6 / 10
        if (behind) skippedSecondary++
        if (!behind && (config.fps <= 30 || renderedFrames % 2 == 0L)) {
            for (output in listOfNotNull(preview, live)) {
                core.makeCurrent(output.surface)
                gl.draw(texMatrix, output.width, output.height)
                core.swapBuffers(output.surface)
            }
        }

        lastDrawNs = System.nanoTime() - started
        val drawMs = lastDrawNs / 1e6
        if (drawMs > frameIntervalNs / 1e6) slowDraws++
        if (drawMs > maxDrawMs) maxDrawMs = drawMs
    }

    private class Output(val surface: EGLSurface, val width: Int, val height: Int)

    private fun emitStats() {
        val frames = segmenter.frames
        val headroom = if (Build.VERSION.SDK_INT >= 30 && statsTicks++ % 2 == 0) {
            powerManager.getThermalHeadroom(10).takeUnless { it.isNaN() }?.toDouble()
        } else {
            null
        }
        emit(
            mapOf(
                "type" to "stats",
                "renderedFrames" to renderedFrames,
                "encodedFrames" to frames,
                "fps" to (frames - lastStatsFrames) * 1000.0 / STATS_INTERVAL_MS,
                "gaps" to segmenter.gaps,
                "droppedBeforeKeyframe" to segmenter.droppedBeforeKeyframe,
                "cameraFrames" to cameraFrames,
                "cameraGaps" to cameraGaps,
                "captureFailures" to captureFailures,
                "glGaps" to glGaps,
                "slowDraws" to slowDraws,
                "maxDrawMs" to maxDrawMs,
                "skippedSecondary" to skippedSecondary,
                "thermalStatus" to thermalStatus,
                "thermalHeadroom" to headroom,
            ) + ring.stats() + batteryStats(),
        )
        lastStatsFrames = frames
        maxDrawMs = 0.0 // per stats interval
        statsHandler.postDelayed(::emitStats, STATS_INTERVAL_MS)
    }

    // Charging heats the phone too; logged so soak tests can separate it from encoder heat.
    private fun batteryStats(): Map<String, Any?> {
        val battery = appContext.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
            ?: return emptyMap()
        val level = battery.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
        val scale = battery.getIntExtra(BatteryManager.EXTRA_SCALE, 100)
        return mapOf(
            "batteryTempC" to battery.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, 0) / 10.0,
            "batteryPercent" to if (level >= 0) level * 100 / scale else null,
            "plugged" to (battery.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) != 0),
            // Sign convention varies by vendor: usually positive while charging.
            "batteryCurrentMa" to batteryManager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CURRENT_NOW) / 1000,
        )
    }

    private fun emitError(message: String) = emit(mapOf("type" to "error", "message" to message))

    private fun <T> onGl(block: () -> T): T {
        val task = FutureTask(block)
        glHandler.post(task)
        return try {
            task.get()
        } catch (e: ExecutionException) {
            throw e.cause ?: e
        }
    }

    private companion object {
        const val STATS_INTERVAL_MS = 1000L
    }
}
