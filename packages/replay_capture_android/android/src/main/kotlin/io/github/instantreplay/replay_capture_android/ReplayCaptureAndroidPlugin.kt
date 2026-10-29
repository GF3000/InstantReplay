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
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry
import io.flutter.view.TextureRegistry
import io.github.instantreplay.replay_capture_android.buffer.ClipAssembler
import io.github.instantreplay.replay_capture_android.buffer.RingBuffer
import java.io.File
import java.util.concurrent.Executors

class ReplayCaptureAndroidPlugin :
    FlutterPlugin,
    MethodCallHandler,
    ActivityAware,
    EventChannel.StreamHandler,
    PluginRegistry.RequestPermissionsResultListener {

    private lateinit var context: Context
    private lateinit var textures: TextureRegistry
    private lateinit var methods: MethodChannel
    private lateinit var events: EventChannel
    private val mainHandler = Handler(Looper.getMainLooper())
    private val io = Executors.newSingleThreadExecutor()

    private var activityBinding: ActivityPluginBinding? = null
    private val activity: Activity? get() = activityBinding?.activity
    private var eventSink: EventChannel.EventSink? = null
    private var pendingPermission: Result? = null

    private var engine: CaptureEngine? = null
    private var live: LiveStreamer? = null
    private var assembler: ClipAssembler? = null
    private var preview: TextureRegistry.SurfaceProducer? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        textures = binding.textureRegistry
        methods = MethodChannel(binding.binaryMessenger, "instant_replay/capture").also { it.setMethodCallHandler(this) }
        events = EventChannel(binding.binaryMessenger, "instant_replay/capture/events").also { it.setStreamHandler(this) }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        stopCapture()
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
        io.shutdown()
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "requestPermission" -> requestPermission(result)
            "start" -> start(call, result)
            "stop" -> {
                stopCapture()
                result.success(null)
            }
            "saveClip" -> saveClip(call, result)
            "liveOffer" -> liveOffer(call, result)
            "liveAnswer" -> liveAnswer(call, result)
            "liveClose" -> {
                live?.close(call.argument<String>("viewerId")!!)
                result.success(null)
            }
            "liveStats" -> {
                val streamer = live ?: return result.success(emptyList<Any>())
                streamer.stats { stats -> mainHandler.post { result.success(stats) } }
            }
            else -> result.notImplemented()
        }
    }

    private fun start(call: MethodCall, result: Result) {
        if (engine != null) return result.error("busy", "Capture already running", null)
        if (!hasCameraPermission()) return result.error("permission", "Camera permission not granted", null)

        val config = CaptureConfig(
            width = call.argument<Int>("width")!!,
            height = call.argument<Int>("height")!!,
            fps = call.argument<Int>("fps")!!,
            bitrate = call.argument<Int>("bitrate")!!,
            windowSeconds = call.argument<Int>("windowSeconds")!!,
        )
        val clipsDir = context.getExternalFilesDir("clips") ?: File(context.filesDir, "clips")
        val ring = RingBuffer(File(context.cacheDir, "ring"), config.windowSeconds * 1_000_000L)
        val producer = textures.createSurfaceProducer().apply { setSize(PREVIEW_WIDTH, PREVIEW_HEIGHT) }
        val capture = CaptureEngine(context, config, ring, ::emit)
        var streamer: LiveStreamer? = null

        try {
            capture.start()
            capture.setPreviewSurface(producer.surface, PREVIEW_WIDTH, PREVIEW_HEIGHT)
            streamer = LiveStreamer(context, ::emit)
            capture.setLiveSurface(streamer.surface, LiveStreamer.WIDTH, LiveStreamer.HEIGHT)
        } catch (e: Exception) {
            capture.release()
            streamer?.release()
            producer.release()
            return result.error("start_failed", e.message, null)
        }
        producer.setCallback(object : TextureRegistry.SurfaceProducer.Callback {
            override fun onSurfaceAvailable() {
                engine?.setPreviewSurface(producer.surface, PREVIEW_WIDTH, PREVIEW_HEIGHT)
            }

            override fun onSurfaceCleanup() {
                engine?.setPreviewSurface(null, 0, 0)
            }
        })

        engine = capture
        live = streamer
        assembler = ClipAssembler(ring, clipsDir)
        preview = producer
        activity?.window?.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        result.success(
            mapOf(
                "textureId" to producer.id(),
                "clipsDir" to clipsDir.absolutePath,
                "encoder" to capture.encoderName,
                "highProfile" to capture.highProfile,
                "sensorOrientation" to capture.sensorOrientation,
            ),
        )
    }

    private fun stopCapture() {
        // Engine first: it stops drawing into the live surface before the streamer is released.
        engine?.release()
        engine = null
        live?.release()
        live = null
        assembler = null
        preview?.release()
        preview = null
        activity?.window?.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    private fun saveClip(call: MethodCall, result: Result) {
        val clips = assembler ?: return result.error("not_running", "Capture is not running", null)
        val pre = call.argument<Double>("preSeconds")!!
        val post = call.argument<Double>("postSeconds")!!
        io.execute {
            try {
                val clip = clips.save(pre, post)
                mainHandler.post { result.success(clip) }
            } catch (e: Exception) {
                mainHandler.post { result.error("save_failed", e.message, null) }
            }
        }
    }

    private fun liveOffer(call: MethodCall, result: Result) {
        val streamer = live ?: return result.error("not_running", "Capture is not running", null)
        streamer.createOffer(call.argument<String>("viewerId")!!, call.argument<String>("codec") ?: "H264") { r ->
            mainHandler.post {
                r.fold({ result.success(it) }, { result.error("offer_failed", it.message, null) })
            }
        }
    }

    private fun liveAnswer(call: MethodCall, result: Result) {
        val streamer = live ?: return result.error("not_running", "Capture is not running", null)
        streamer.setAnswer(call.argument<String>("viewerId")!!, call.argument<String>("sdp")!!) { r ->
            mainHandler.post {
                r.fold({ result.success(null) }, { result.error("answer_failed", it.message, null) })
            }
        }
    }

    private fun emit(event: Map<String, Any?>) {
        mainHandler.post { eventSink?.success(event) }
    }

    // region Permissions

    private fun hasCameraPermission() =
        context.checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED

    private fun requestPermission(result: Result) {
        if (hasCameraPermission()) return result.success(true)
        val host = activity ?: return result.error("no_activity", "Plugin is not attached to an activity", null)
        pendingPermission = result
        host.requestPermissions(arrayOf(Manifest.permission.CAMERA), PERMISSION_REQUEST)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray): Boolean {
        if (requestCode != PERMISSION_REQUEST) return false
        pendingPermission?.success(grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED)
        pendingPermission = null
        return true
    }

    // endregion

    // region ActivityAware / StreamHandler

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

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
        eventSink = sink
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    // endregion

    private companion object {
        const val PERMISSION_REQUEST = 4207
        const val PREVIEW_WIDTH = 1280
        const val PREVIEW_HEIGHT = 720
    }
}
