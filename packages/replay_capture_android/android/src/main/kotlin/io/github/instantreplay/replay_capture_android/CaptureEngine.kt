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
import android.opengl.GLES20
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
import io.github.instantreplay.replay_capture_android.gl.FrameHandoff
import io.github.instantreplay.replay_capture_android.gl.TexTransform
import io.github.instantreplay.replay_capture_android.gl.TextureRenderer
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
 * Threads: `ir-gl` (capture EGL context, SurfaceTexture, HQ encoder input), `ir-gl-out` (shared
 * EGL context drawing preview and live view from a [FrameHandoff] copy, so their slow swaps never
 * delay the HQ path), `ir-camera` (Camera2 callbacks), `ir-encoder` (encoder output, segmenting,
 * ring writes), `ir-stats`.
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
    private val outThread = HandlerThread("ir-gl-out").apply { start() }
    private val outHandler = Handler(outThread.looper)
    private val cameraThread = HandlerThread("ir-camera").apply { start() }
    private val cameraHandler = Handler(cameraThread.looper)
    private val encoderThread = HandlerThread("ir-encoder").apply { start() }
    private val encoderHandler = Handler(encoderThread.looper)
    // Stats involve binder calls (battery, thermal headroom); keep them off the GL thread.
    private val statsThread = HandlerThread("ir-stats").apply { start() }
    private val statsHandler = Handler(statsThread.looper)

    // GL-thread state.
    private var egl: EglCore? = null
    private var renderer: TextureRenderer? = null
    private var cameraTexture = 0
    private var surfaceTexture: SurfaceTexture? = null
    private var cameraSurface: Surface? = null
    private var encoderEglSurface: EGLSurface? = null
    private val texMatrix = FloatArray(16)
    private var uprightRotation = 0
    @Volatile private var renderedFrames = 0L

    // Used by both GL threads; created and released on the GL thread.
    @Volatile private var handoff: FrameHandoff? = null

    // Output-thread state.
    private var outEgl: EglCore? = null
    private var outIdle: EGLSurface? = null
    private var outRenderer: TextureRenderer? = null
    private var preview: Output? = null
    private var live: Output? = null
    @Volatile private var hasOutputs = false

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
        val captureEgl = onGl {
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
            renderer = TextureRenderer(external = true)
            cameraTexture = TextureRenderer.createExternalTexture()
            val outWidth = minOf(config.width, OUT_MAX_WIDTH)
            handoff = FrameHandoff(outWidth, outWidth * config.height / config.width, useFences = core.glVersion >= 3)
            val st = SurfaceTexture(cameraTexture).apply {
                setDefaultBufferSize(config.width, config.height)
                setOnFrameAvailableListener({ drawFrame() }, glHandler)
            }
            surfaceTexture = st
            cameraSurface = Surface(st)
            core
        }
        onOut {
            val core = EglCore(shared = captureEgl)
            outEgl = core
            val idle = core.createPbufferSurface(1, 1)
            outIdle = idle
            core.makeCurrent(idle)
            outRenderer = TextureRenderer(external = false)
        }
        powerManager.addThermalStatusListener(Executor { statsHandler.post(it) }, thermalListener)
        thermalStatus = powerManager.currentThermalStatus
        openCamera(cameraId, fpsRange)
        statsHandler.postDelayed(::emitStats, STATS_INTERVAL_MS)
    }

    /** Replaces the preview target; pass null to stop drawing it. Blocks until applied. */
    fun setPreviewSurface(surface: Surface?, width: Int, height: Int) = onOut {
        preview = replaceOutput(preview, surface, width, height)
        hasOutputs = preview != null || live != null
    }

    /** Replaces the live-view (WebRTC) target; pass null to stop drawing it. Blocks until applied. */
    fun setLiveSurface(surface: Surface?, width: Int, height: Int) = onOut {
        live = replaceOutput(live, surface, width, height)
        hasOutputs = preview != null || live != null
    }

    // Output thread.
    private fun replaceOutput(current: Output?, surface: Surface?, width: Int, height: Int): Output? {
        val core = outEgl ?: return null
        current?.let {
            outIdle?.let(core::makeCurrent)
            core.releaseSurface(it.surface)
        }
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
        // The output context goes first: it uses the capture context's display, which the capture
        // context terminates. Frames handed off meanwhile find outEgl null and are ignored.
        onOut {
            hasOutputs = false
            outHandler.removeCallbacksAndMessages(null)
            val core = outEgl
            val idle = outIdle
            if (core != null && idle != null) {
                core.makeCurrent(idle)
                outRenderer?.release()
                listOfNotNull(preview, live).forEach { core.releaseSurface(it.surface) }
                core.release()
                core.releaseSurface(idle)
            }
            outEgl = null
            preview = null
            live = null
        }
        outThread.quitSafely()
        outThread.join()
        onGl {
            glHandler.removeCallbacksAndMessages(null)
            val core = egl
            if (core != null) {
                encoderEglSurface?.let(core::makeCurrent)
                handoff?.release()
                renderer?.release()
                GLES20.glDeleteTextures(1, intArrayOf(cameraTexture), 0)
                encoderEglSurface?.let { core.releaseSurface(it) }
                core.release()
            }
            handoff = null
            surfaceTexture?.release()
            cameraSurface?.release()
            egl = null
        }
        encoder?.release()
        glThread.quitSafely()
        glThread.join()
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
        uprightRotation = TexTransform.uprightRotation(sensorOrientation, CAMERA_UI_ROTATION_DEG)

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
    @Volatile private var secondaryFrames = 0L
    @Volatile private var maxSecondaryMs = 0.0

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
        val frames = handoff ?: return
        val started = System.nanoTime()

        core.makeCurrent(encSurface)
        st.updateTexImage()
        st.getTransformMatrix(texMatrix)
        TexTransform.normalize(texMatrix, uprightRotation, texMatrix)
        val ts = st.timestamp
        if (lastGlNs != 0L && ts - lastGlNs > frameIntervalNs * 3 / 2) glGaps++
        lastGlNs = ts
        gl.draw(cameraTexture, config.width, config.height, texMatrix)
        core.setPresentationTime(encSurface, ts)
        core.swapBuffers(encSurface)
        renderedFrames++

        // Preview and live view at most 30 fps. Only a cheap copy happens here; the output thread
        // draws and swaps them, so a slow consumer can never delay the next HQ frame.
        if (hasOutputs && (config.fps <= 30 || renderedFrames % 2 == 0L)) {
            val wake = frames.publish { gl.draw(cameraTexture, frames.width, frames.height, texMatrix) }
            if (wake) outHandler.post(::drawOutputs)
        }

        val drawMs = (System.nanoTime() - started) / 1e6
        if (drawMs > frameIntervalNs / 1e6) slowDraws++
        if (drawMs > maxDrawMs) maxDrawMs = drawMs
    }

    // Output thread: draws the latest handed-off frame; older ones were dropped by publish().
    private fun drawOutputs() {
        val core = outEgl ?: return
        val idle = outIdle ?: return
        val gl = outRenderer ?: return
        val frames = handoff ?: return
        val started = System.nanoTime()
        val outputs = listOfNotNull(preview, live)
        core.makeCurrent(outputs.firstOrNull()?.surface ?: idle)
        frames.consume { texture ->
            for (output in outputs) {
                core.makeCurrent(output.surface)
                gl.draw(texture, output.width, output.height)
                core.swapBuffers(output.surface)
            }
            secondaryFrames++
        }
        val ms = (System.nanoTime() - started) / 1e6
        if (ms > maxSecondaryMs) maxSecondaryMs = ms
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
                "secondaryFrames" to secondaryFrames,
                "secondaryDropped" to (handoff?.dropped ?: 0L),
                "maxSecondaryMs" to maxSecondaryMs,
                "thermalStatus" to thermalStatus,
                "thermalHeadroom" to headroom,
            ) + ring.stats() + batteryStats(),
        )
        lastStatsFrames = frames
        maxDrawMs = 0.0 // per stats interval
        maxSecondaryMs = 0.0
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

    private fun <T> onGl(block: () -> T): T = runOn(glHandler, block)

    private fun <T> onOut(block: () -> T): T = runOn(outHandler, block)

    private fun <T> runOn(handler: Handler, block: () -> T): T {
        val task = FutureTask(block)
        handler.post(task)
        return try {
            task.get()
        } catch (e: ExecutionException) {
            throw e.cause ?: e
        }
    }

    private companion object {
        const val STATS_INTERVAL_MS = 1000L
        // Preview and live view are at most 720p; the handoff copy needs no more.
        const val OUT_MAX_WIDTH = 1280
        // The Camera role UI is locked to landscapeLeft (Surface.ROTATION_90).
        const val CAMERA_UI_ROTATION_DEG = 90
    }
}
