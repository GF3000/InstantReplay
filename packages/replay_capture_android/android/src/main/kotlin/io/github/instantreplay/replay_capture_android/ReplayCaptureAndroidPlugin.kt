package io.github.instantreplay.replay_capture_android

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import android.view.WindowManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.PluginRegistry
import io.flutter.view.TextureRegistry
import io.github.instantreplay.replay_capture_android.buffer.RingBuffer
import io.github.instantreplay.replay_capture_android.outbox.Outbox
import java.io.File

class ReplayCaptureAndroidPlugin :
    FlutterPlugin,
    ActivityAware,
    PluginRegistry.RequestPermissionsResultListener,
    CaptureHostApi {

    private lateinit var context: Context
    private lateinit var textures: TextureRegistry
    private lateinit var messenger: BinaryMessenger
    private lateinit var events: CaptureEventsApi
    private lateinit var outbox: Outbox
    private val mainHandler = Handler(Looper.getMainLooper())

    private var activityBinding: ActivityPluginBinding? = null
    private val activity: Activity? get() = activityBinding?.activity
    private var pendingPermission: ((Result<Boolean>) -> Unit)? = null

    private var engine: CaptureEngine? = null
    private var live: LiveStreamer? = null
    private var preview: TextureRegistry.SurfaceProducer? = null
    private var previewEnabled = true

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        textures = binding.textureRegistry
        messenger = binding.binaryMessenger
        events = CaptureEventsApi(messenger)
        val outboxDir = File(context.getExternalFilesDir(null) ?: context.filesDir, "outbox")
        outbox = Outbox(outboxDir) { clip -> mainHandler.post { events.onClipChanged(clip) {} } }
        CaptureHostApi.setUp(messenger, this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        stopCapture()
        CaptureHostApi.setUp(messenger, null)
        outbox.release()
    }

    // region CaptureHostApi

    override fun requestPermission(callback: (Result<Boolean>) -> Unit) {
        if (hasCameraPermission()) return callback(Result.success(true))
        val host = activity
            ?: return callback(Result.failure(FlutterError("no_activity", "Plugin is not attached to an activity")))
        pendingPermission = callback
        host.requestPermissions(arrayOf(Manifest.permission.CAMERA), PERMISSION_REQUEST)
    }

    override fun supportedProfiles(): List<CaptureProfile> = Profiles.supported(context)

    override fun start(request: StartRequest): StartResult {
        if (engine != null) throw FlutterError("busy", "Capture already running")
        if (!hasCameraPermission()) throw FlutterError("permission", "Camera permission not granted")
        val profile = supportedProfiles().firstOrNull { it.id == request.profileId }
            ?: throw FlutterError("profile", "Profile ${request.profileId} is not supported on this device")

        val config = CaptureConfig(
            width = profile.width.toInt(),
            height = profile.height.toInt(),
            fps = profile.fps.toInt(),
            bitrate = profile.bitrate.toInt(),
            windowSeconds = request.windowSeconds.toInt(),
        )
        val ring = RingBuffer(File(context.cacheDir, "ring"), config.windowSeconds * 1_000_000L)
        val producer = textures.createSurfaceProducer().apply { setSize(PREVIEW_WIDTH, PREVIEW_HEIGHT) }
        val capture = CaptureEngine(context, config, ring, ::emit)
        var streamer: LiveStreamer? = null

        try {
            capture.start()
            if (previewEnabled) capture.setPreviewSurface(producer.surface, PREVIEW_WIDTH, PREVIEW_HEIGHT)
            streamer = LiveStreamer(context, ::emit)
            capture.setLiveSurface(streamer.surface, LiveStreamer.WIDTH, LiveStreamer.HEIGHT)
        } catch (e: Exception) {
            capture.release()
            streamer?.release()
            producer.release()
            throw FlutterError("start_failed", e.message)
        }
        producer.setCallback(object : TextureRegistry.SurfaceProducer.Callback {
            override fun onSurfaceAvailable() {
                if (previewEnabled) engine?.setPreviewSurface(producer.surface, PREVIEW_WIDTH, PREVIEW_HEIGHT)
            }

            override fun onSurfaceCleanup() {
                engine?.setPreviewSurface(null, 0, 0)
            }
        })

        engine = capture
        live = streamer
        preview = producer
        outbox.attach(ring)
        CaptureService.start(context)
        activity?.window?.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        return StartResult(
            textureId = producer.id(),
            encoder = capture.encoderName,
            highProfile = capture.highProfile,
            sensorOrientation = capture.sensorOrientation.toLong(),
        )
    }

    override fun stop() = stopCapture()

    override fun setPreviewEnabled(enabled: Boolean) {
        previewEnabled = enabled
        val producer = preview ?: return
        engine?.setPreviewSurface(if (enabled) producer.surface else null, PREVIEW_WIDTH, PREVIEW_HEIGHT)
    }

    override fun saveClip(request: SaveRequest, callback: (Result<ClipInfo>) -> Unit) {
        outbox.save(request) { result -> mainHandler.post { callback(result) } }
    }

    override fun listClips(): List<ClipInfo> = outbox.list()

    override fun getClip(id: String): ClipInfo? = outbox.get(id)

    override fun ackClip(id: String, sha256: String): Boolean = outbox.ack(id, sha256)

    override fun liveOffer(viewerId: String, codec: String, callback: (Result<String>) -> Unit) {
        val streamer = live ?: return callback(Result.failure(FlutterError("not_running", "Capture is not running")))
        streamer.createOffer(viewerId, codec) { r ->
            mainHandler.post { callback(r.recoverCatching { throw FlutterError("offer_failed", it.message) }) }
        }
    }

    override fun liveAnswer(viewerId: String, sdp: String, callback: (Result<Unit>) -> Unit) {
        val streamer = live ?: return callback(Result.failure(FlutterError("not_running", "Capture is not running")))
        streamer.setAnswer(viewerId, sdp) { r ->
            mainHandler.post { callback(r.recoverCatching { throw FlutterError("answer_failed", it.message) }) }
        }
    }

    override fun liveClose(viewerId: String) {
        live?.close(viewerId)
    }

    override fun liveStats(callback: (Result<List<LiveViewerStats>>) -> Unit) {
        val streamer = live ?: return callback(Result.success(emptyList()))
        streamer.stats { stats -> mainHandler.post { callback(Result.success(stats.map(::toLiveStats))) } }
    }

    // endregion

    private fun stopCapture() {
        // Engine first: it stops drawing into the live surface before the streamer is released.
        engine?.release()
        engine = null
        live?.release()
        live = null
        preview?.release()
        preview = null
        outbox.attach(null)
        CaptureService.stop(context)
        activity?.window?.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    /** Engine events arrive as maps from background threads; forward them typed on the main thread. */
    private fun emit(event: Map<String, Any?>) {
        mainHandler.post {
            when (event["type"]) {
                "stats" -> events.onStats(toStats(event)) {}
                "thermal" -> events.onThermal(
                    ThermalEvent(status = (event["status"] as Int).toLong(), action = ThermalAction.NONE),
                ) {}
                "camera" -> events.onCameraState(event["state"] as String) {}
                "error" -> events.onError(event["message"] as String) {}
            }
        }
    }

    private fun toStats(e: Map<String, Any?>): CaptureStats {
        val (clips, bytes) = outbox.stats()
        fun long(key: String) = (e[key] as Number?)?.toLong() ?: 0L
        return CaptureStats(
            encodedFrames = long("encodedFrames"),
            fps = (e["fps"] as Number?)?.toDouble() ?: 0.0,
            gaps = long("gaps"),
            cameraGaps = long("cameraGaps"),
            glGaps = long("glGaps"),
            bufferMs = long("bufferMs"),
            bufferBytes = long("bufferBytes"),
            outboxClips = clips,
            outboxBytes = bytes,
            thermalStatus = long("thermalStatus"),
            thermalHeadroom = (e["thermalHeadroom"] as Number?)?.toDouble(),
            batteryTempC = (e["batteryTempC"] as Number?)?.toDouble(),
            batteryPercent = (e["batteryPercent"] as Number?)?.toLong(),
            plugged = e["plugged"] == true,
        )
    }

    private fun toLiveStats(m: Map<String, Any?>) = LiveViewerStats(
        viewerId = m["viewer"] as String,
        codec = m["codec"] as String?,
        encoderImplementation = m["encoderImplementation"] as String?,
        framesPerSecond = (m["framesPerSecond"] as String?)?.toDoubleOrNull(),
        frameWidth = (m["frameWidth"] as String?)?.toDoubleOrNull()?.toLong(),
        frameHeight = (m["frameHeight"] as String?)?.toDoubleOrNull()?.toLong(),
        qualityLimitationReason = m["qualityLimitationReason"] as String?,
    )

    // region Permissions / ActivityAware

    private fun hasCameraPermission() =
        context.checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray): Boolean {
        if (requestCode != PERMISSION_REQUEST) return false
        pendingPermission?.invoke(Result.success(grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED))
        pendingPermission = null
        return true
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)

    override fun onDetachedFromActivity() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
    }

    // endregion

    private companion object {
        const val PERMISSION_REQUEST = 4207
        const val PREVIEW_WIDTH = 1280
        const val PREVIEW_HEIGHT = 720
    }
}
