package io.github.instantreplay.replay_capture_android.gl

import android.content.res.AssetManager
import android.graphics.Typeface
import android.util.Log

/**
 * The IBM Plex faces the plate style draws with, bundled in this plugin's assets (OFL, see
 * `assets/replay_capture_android/fonts/OFL.txt`); no network. Falls back to the default bold face
 * when an asset can't be read.
 */
internal class OverlayFonts(assets: AssetManager?) {
    /** IBM Plex Sans Condensed SemiBold: team names, period. */
    val condensed: Typeface = load(assets, "IBMPlexSansCondensed-SemiBold.ttf")

    /** IBM Plex Mono Bold: scores, clock, the replay badge. */
    val mono: Typeface = load(assets, "IBMPlexMono-Bold.ttf")

    private fun load(assets: AssetManager?, file: String): Typeface {
        if (assets == null) return Typeface.DEFAULT_BOLD
        return try {
            Typeface.createFromAsset(assets, "$DIR/$file")
        } catch (e: RuntimeException) {
            Log.w(TAG, "font $file not loaded, using the default bold face", e)
            Typeface.DEFAULT_BOLD
        }
    }

    private companion object {
        const val DIR = "replay_capture_android/fonts"
        const val TAG = "OverlayFonts"
    }
}
