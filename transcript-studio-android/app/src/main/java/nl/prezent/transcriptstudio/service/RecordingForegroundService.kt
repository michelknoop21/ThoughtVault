package nl.prezent.transcriptstudio.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import nl.prezent.transcriptstudio.MainActivity
import nl.prezent.transcriptstudio.R

private const val TAG = "RecordingFgService"
private const val CHANNEL_ID = "recording_channel"
private const val NOTIFICATION_ID = 1001
private const val UPDATE_INTERVAL_MS = 1000L

/**
 * Foreground service that keeps the recording alive when the app is in the background.
 * Displays a persistent notification with a timer and stop action.
 *
 * Uses FOREGROUND_SERVICE_TYPE_MICROPHONE as required by API 34+.
 */
class RecordingForegroundService : Service() {

    companion object {
        const val ACTION_START = "nl.prezent.transcriptstudio.action.START_RECORDING"
        const val ACTION_STOP = "nl.prezent.transcriptstudio.action.STOP_RECORDING"

        fun startIntent(context: Context): Intent =
            Intent(context, RecordingForegroundService::class.java).apply {
                action = ACTION_START
            }

        fun stopIntent(context: Context): Intent =
            Intent(context, RecordingForegroundService::class.java).apply {
                action = ACTION_STOP
            }
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var startTimeMs = 0L

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                startTimeMs = System.currentTimeMillis()
                startForeground(
                    NOTIFICATION_ID,
                    buildNotification("00:00"),
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE,
                )
                startTimerUpdates()
                Log.d(TAG, "Foreground service started")
            }
            ACTION_STOP -> {
                stopSelf()
            }
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        super.onDestroy()
        scope.cancel()
        Log.d(TAG, "Foreground service destroyed")
    }

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            getString(R.string.notification_channel_recording),
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = getString(R.string.notification_channel_recording_desc)
            setShowBadge(false)
        }
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(channel)
    }

    private fun buildNotification(elapsed: String): Notification {
        val openIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val stopIntent = PendingIntent.getService(
            this,
            1,
            stopIntent(this),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(getString(R.string.notification_recording_title))
            .setContentText(getString(R.string.notification_recording_text, elapsed))
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setOngoing(true)
            .setContentIntent(openIntent)
            .addAction(
                android.R.drawable.ic_media_pause,
                getString(R.string.notification_action_stop),
                stopIntent,
            )
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()
    }

    private fun startTimerUpdates() {
        scope.launch {
            while (isActive) {
                delay(UPDATE_INTERVAL_MS)
                val elapsed = System.currentTimeMillis() - startTimeMs
                val formatted = formatElapsed(elapsed)
                val manager = getSystemService(NotificationManager::class.java)
                manager.notify(NOTIFICATION_ID, buildNotification(formatted))
            }
        }
    }

    private fun formatElapsed(ms: Long): String {
        val totalSeconds = ms / 1000
        val minutes = totalSeconds / 60
        val seconds = totalSeconds % 60
        return "%02d:%02d".format(minutes, seconds)
    }
}
