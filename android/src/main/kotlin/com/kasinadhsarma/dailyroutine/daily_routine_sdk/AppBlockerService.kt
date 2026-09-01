package com.kasinadhsarma.dailyroutine.daily_routine_sdk

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat

/**
 * Foreground service that polls [UsageStatsManager] once a second for the
 * current foreground app, and whenever it matches [EXTRA_PACKAGE_IDS],
 * brings [BlockScreenActivity] to the front instead.
 *
 * This is a best-effort deterrent (same approach most consumer "screen time"
 * apps use before they get an Accessibility Service or a full MDM profile);
 * it is not a kernel-level sandbox.
 */
class AppBlockerService : Service() {

    companion object {
        const val CHANNEL_ID = "app_blocker_channel"
        const val NOTIFICATION_ID = 4242
        const val EXTRA_PACKAGE_IDS = "packageIds"
        const val ACTION_START = "com.kasinadhsarma.dailyroutine.daily_routine_sdk.START"
        const val ACTION_STOP = "com.kasinadhsarma.dailyroutine.daily_routine_sdk.STOP"

        var onAppBlocked: ((String) -> Unit)? = null
    }

    private val handler = Handler(Looper.getMainLooper())
    private var blockedPackageIds: Set<String> = emptySet()
    private var lastBlockedAt = 0L

    private val pollRunnable = object : Runnable {
        override fun run() {
            checkForegroundApp()
            handler.postDelayed(this, 1000L)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopSelf()
                return START_NOT_STICKY
            }
            else -> {
                blockedPackageIds =
                    intent?.getStringArrayListExtra(EXTRA_PACKAGE_IDS)?.toSet() ?: emptySet()
                startForeground(NOTIFICATION_ID, buildNotification())
                handler.removeCallbacks(pollRunnable)
                handler.post(pollRunnable)
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacks(pollRunnable)
        super.onDestroy()
    }

    private fun checkForegroundApp() {
        if (blockedPackageIds.isEmpty()) return
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
        if (fg == packageName) return
        if (blockedPackageIds.contains(fg)) {
            val now = System.currentTimeMillis()
            if (now - lastBlockedAt < 1500) return
            lastBlockedAt = now
            onAppBlocked?.invoke(fg)
            val blockIntent = Intent(this, BlockScreenActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                putExtra(BlockScreenActivity.EXTRA_BLOCKED_PACKAGE, fg)
            }
            startActivity(blockIntent)
        }
    }

    private fun buildNotification(): android.app.Notification {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Focus session",
                NotificationManager.IMPORTANCE_LOW,
            )
            manager.createNotificationChannel(channel)
        }
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Focus session active")
            .setContentText("Blocking distracting apps until your routine task ends.")
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setOngoing(true)
            .build()
    }
}
