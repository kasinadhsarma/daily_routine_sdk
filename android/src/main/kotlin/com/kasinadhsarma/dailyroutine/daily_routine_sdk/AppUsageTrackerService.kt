package com.kasinadhsarma.dailyroutine.daily_routine_sdk

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat

data class AppUsageEvent(
    val packageName: String,
    val appLabel: String,
    val startedAt: Long,
    val durationMs: Long,
)

/**
 * Foreground service that polls [UsageStatsManager] every few seconds for
 * the current foreground app and emits an [AppUsageEvent] via
 * [onSessionEnded] each time the foreground app changes.
 *
 * Same best-effort polling approach as [AppBlockerService] — this is not a
 * gapless log: it only sees switches that happen while this service (and
 * the hosting process) is alive.
 */
class AppUsageTrackerService : Service() {

    companion object {
        const val CHANNEL_ID = "app_usage_channel"
        const val NOTIFICATION_ID = 4243
        const val ACTION_START = "com.kasinadhsarma.dailyroutine.daily_routine_sdk.USAGE_START"
        const val ACTION_STOP = "com.kasinadhsarma.dailyroutine.daily_routine_sdk.USAGE_STOP"
        const val MIN_SESSION_MS = 2000L
        const val POLL_INTERVAL_MS = 3000L

        var onSessionEnded: ((AppUsageEvent) -> Unit)? = null
    }

    private val handler = Handler(Looper.getMainLooper())
    private val appLabelCache = mutableMapOf<String, String>()

    private var currentPackage: String? = null
    private var currentStartedAt: Long = 0L

    private val pollRunnable = object : Runnable {
        override fun run() {
            checkForegroundApp()
            handler.postDelayed(this, POLL_INTERVAL_MS)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                flushCurrentSession()
                stopSelf()
                return START_NOT_STICKY
            }
            else -> {
                startForeground(NOTIFICATION_ID, buildNotification())
                handler.removeCallbacks(pollRunnable)
                handler.post(pollRunnable)
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacks(pollRunnable)
        flushCurrentSession()
        super.onDestroy()
    }

    private fun checkForegroundApp() {
        val usm = getSystemService(Context.USAGE_STATS_SERVICE) as? UsageStatsManager ?: return
        val end = System.currentTimeMillis()
        val begin = end - 10_000
        val events = usm.queryEvents(begin, end)
        var lastForegroundPackage: String? = null
        val event = android.app.usage.UsageEvents.Event()
        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            if (event.eventType == android.app.usage.UsageEvents.Event.MOVE_TO_FOREGROUND) {
                lastForegroundPackage = event.packageName
            }
        }
        val fg = lastForegroundPackage ?: return
        if (fg == currentPackage) return

        flushCurrentSession()
        currentPackage = fg
        currentStartedAt = System.currentTimeMillis()
    }

    private fun flushCurrentSession() {
        val pkg = currentPackage ?: return
        val startedAt = currentStartedAt
        val duration = System.currentTimeMillis() - startedAt
        currentPackage = null
        if (duration < MIN_SESSION_MS) return
        onSessionEnded?.invoke(
            AppUsageEvent(
                packageName = pkg,
                appLabel = labelFor(pkg),
                startedAt = startedAt,
                durationMs = duration,
            )
        )
    }

    private fun labelFor(packageName: String): String {
        appLabelCache[packageName]?.let { return it }
        val label = try {
            val pm = packageManager
            val appInfo = pm.getApplicationInfo(packageName, PackageManager.GET_META_DATA)
            pm.getApplicationLabel(appInfo).toString()
        } catch (_: Exception) {
            packageName
        }
        appLabelCache[packageName] = label
        return label
    }

    private fun buildNotification(): android.app.Notification {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Activity tracking",
                NotificationManager.IMPORTANCE_MIN,
            )
            manager.createNotificationChannel(channel)
        }
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Activity tracking active")
            .setContentText("Logging app usage for your Daily Routine dashboard.")
            .setSmallIcon(android.R.drawable.ic_menu_recent_history)
            .setOngoing(true)
            .build()
    }
}
