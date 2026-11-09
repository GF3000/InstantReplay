package io.github.instantreplay.replay_capture_android

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log

/**
 * Keeps capture alive with the screen off or the app in the background (SPEC §3.5).
 *
 * A foreground service of type `camera` with an ongoing, low-priority notification. It owns no
 * capture state: the plugin runs the pipeline in the same process, and this service only tells
 * Android that the process is doing user-visible camera work so it is neither frozen nor killed
 * and keeps camera access while the activity is in the background.
 */
internal class CaptureService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        // Promote as early as possible: a stop() that races the start must find us already in the foreground.
        promote()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        microphone = intent?.getBooleanExtra(EXTRA_MICROPHONE, false) ?: false
        promote()
        // Without the engine (process restart) there is nothing to keep alive.
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }

    /** A broadcast with audio runs: Android 14+ cuts the mic in the background without this type. */
    private var microphone = false

    private fun promote() {
        try {
            if (microphone) {
                try {
                    startForeground(
                        NOTIFICATION_ID,
                        buildNotification(),
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA or ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE,
                    )
                    return
                } catch (e: Exception) {
                    // E.g. requested from the background: keep the camera guarantee at least.
                    Log.w(TAG, "Could not add the microphone type", e)
                }
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(NOTIFICATION_ID, buildNotification(), ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA)
            } else {
                startForeground(NOTIFICATION_ID, buildNotification())
            }
        } catch (e: Exception) {
            // Missing camera permission or a background start on Android 12+: capture keeps running
            // while the app is visible, it just loses the background guarantee.
            Log.w(TAG, "Could not enter the foreground", e)
            stopSelf()
        }
    }

    private fun buildNotification(): Notification {
        val manager = getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(CHANNEL_ID) == null) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    getString(R.string.replay_capture_notification_channel),
                    NotificationManager.IMPORTANCE_LOW,
                ).apply {
                    setShowBadge(false)
                    enableVibration(false)
                    setSound(null, null)
                },
            )
        }

        val builder = Notification.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.replay_capture_ic_recording)
            .setContentTitle(getString(R.string.replay_capture_notification_title))
            .setContentText(getString(R.string.replay_capture_notification_text))
            .setCategory(Notification.CATEGORY_SERVICE)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(true)
            .setUsesChronometer(true)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
        }
        packageManager.getLaunchIntentForPackage(packageName)?.let { launch ->
            // Bring the existing task to the front instead of starting a new activity.
            launch.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED
            builder.setContentIntent(
                PendingIntent.getActivity(
                    this,
                    0,
                    launch,
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
                ),
            )
        }
        return builder.build()
    }

    companion object {
        private const val TAG = "CaptureService"
        private const val CHANNEL_ID = "replay_capture_recording"
        private const val NOTIFICATION_ID = 0x1257

        private const val EXTRA_MICROPHONE = "microphone"

        /**
         * Called by the plugin once the pipeline is running (the app is in the foreground then),
         * and again with [microphone] when a broadcast with audio starts or stops, to change the
         * service type (`camera` or `camera|microphone`).
         */
        fun start(context: Context, microphone: Boolean = false) {
            try {
                context.startForegroundService(
                    Intent(context, CaptureService::class.java).putExtra(EXTRA_MICROPHONE, microphone),
                )
            } catch (e: Exception) {
                // ForegroundServiceStartNotAllowedException (Android 12+) if somehow started from the background.
                Log.w(TAG, "Could not start the capture service", e)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, CaptureService::class.java))
        }
    }
}
