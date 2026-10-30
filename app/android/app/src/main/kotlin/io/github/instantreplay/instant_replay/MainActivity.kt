package io.github.instantreplay.instant_replay

import android.content.Context
import android.content.pm.PackageManager
import android.content.res.AssetManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val appContext = applicationContext
        val mainHandler = Handler(Looper.getMainLooper())
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WebBundle.CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "extract" -> WebBundle.executor.execute {
                    try {
                        val path = WebBundle.extract(appContext)
                        mainHandler.post { result.success(path) }
                    } catch (e: Exception) {
                        Log.e(WebBundle.TAG, "Web bundle extraction failed", e)
                        mainHandler.post { result.error("extract_failed", e.message, null) }
                    }
                }
                else -> result.notImplemented()
            }
        }
        // The native Viewer offers its QR scanner only on devices with a camera.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "instant_replay/device").setMethodCallHandler { call, result ->
            when (call.method) {
                "hasCamera" -> result.success(packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY))
                else -> result.notImplemented()
            }
        }
    }
}

/**
 * Copies the web Viewer bundle (APK `assets/web_viewer/`, added by tool/build_apk.*) to
 * `<filesDir>/web_viewer/` so the Camera's HTTP server can serve it from plain files (SPEC §6).
 *
 * The copy is redone only when the APK changed since the last one (PackageInfo.lastUpdateTime,
 * stored in a marker file next to the bundle).
 */
private object WebBundle {
    const val CHANNEL = "instant_replay/web_bundle"
    const val TAG = "WebBundle"
    private const val ASSET_ROOT = "web_viewer"
    private const val MARKER = "web_viewer.stamp"

    /** Single thread: concurrent calls are serialized instead of copying twice. */
    val executor = Executors.newSingleThreadExecutor()

    /** Returns the absolute bundle directory, or null when the APK has no bundle. */
    fun extract(context: Context): String? {
        val assets = context.assets
        if (!hasAsset(assets, "$ASSET_ROOT/index.html")) {
            Log.i(TAG, "No web bundle in this APK (built without tool/build_apk)")
            return null
        }
        val target = File(context.filesDir, ASSET_ROOT)
        val marker = File(context.filesDir, MARKER)
        val stamp = apkStamp(context)
        if (target.isDirectory && File(target, "index.html").isFile &&
            marker.isFile && marker.readText() == stamp
        ) {
            return target.absolutePath
        }

        // Copy into a temporary directory, then swap, so a crash never leaves a half bundle.
        val tmp = File(context.filesDir, "$ASSET_ROOT.tmp")
        tmp.deleteRecursively()
        copyAssetDir(assets, ASSET_ROOT, tmp)
        marker.delete()
        target.deleteRecursively()
        if (!tmp.renameTo(target)) throw IOException("Cannot rename $tmp to $target")
        marker.writeText(stamp)
        Log.i(TAG, "Extracted web bundle to $target")
        return target.absolutePath
    }

    private fun apkStamp(context: Context): String {
        val pm = context.packageManager
        val info = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            pm.getPackageInfo(context.packageName, android.content.pm.PackageManager.PackageInfoFlags.of(0))
        } else {
            @Suppress("DEPRECATION")
            pm.getPackageInfo(context.packageName, 0)
        }
        return "${info.lastUpdateTime}"
    }

    private fun hasAsset(assets: AssetManager, path: String): Boolean =
        try {
            assets.open(path).close()
            true
        } catch (_: IOException) {
            false
        }

    /** Recursively copies an asset directory. `list()` returns no children for a file. */
    private fun copyAssetDir(assets: AssetManager, assetPath: String, dest: File) {
        dest.mkdirs()
        for (name in assets.list(assetPath).orEmpty()) {
            val child = "$assetPath/$name"
            val children = assets.list(child)
            if (children != null && children.isNotEmpty()) {
                copyAssetDir(assets, child, File(dest, name))
            } else {
                assets.open(child).use { input ->
                    File(dest, name).outputStream().use { output -> input.copyTo(output) }
                }
            }
        }
    }
}
