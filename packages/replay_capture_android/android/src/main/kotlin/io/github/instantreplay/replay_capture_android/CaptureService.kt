package io.github.instantreplay.replay_capture_android

import android.content.Context

/**
 * Keeps capture alive with the screen off or the app in the background (SPEC §3.5).
 * Placeholder: M2.4 turns this into a foreground service of type `camera`.
 */
internal object CaptureService {
    fun start(context: Context) = Unit

    fun stop(context: Context) = Unit
}
