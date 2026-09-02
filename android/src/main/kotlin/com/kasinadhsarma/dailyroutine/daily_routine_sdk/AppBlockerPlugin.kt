package com.kasinadhsarma.dailyroutine.daily_routine_sdk

import android.app.AppOpsManager
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.net.Uri
import android.os.Build
import android.os.Process
import android.provider.Settings
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/** AppBlockerPlugin */
class AppBlockerPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private lateinit var usageEventChannel: EventChannel
    private lateinit var applicationContext: Context
    private var eventSink: EventChannel.EventSink? = null
    private var usageEventSink: EventChannel.EventSink? = null

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = flutterPluginBinding.applicationContext
        methodChannel =
            MethodChannel(flutterPluginBinding.binaryMessenger, "daily_routine_sdk/app_blocker")
        methodChannel.setMethodCallHandler(this)

        eventChannel =
            EventChannel(
                flutterPluginBinding.binaryMessenger,
                "daily_routine_sdk/app_blocker/events",
            )
        eventChannel.setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                    eventSink = sink
                    AppBlockerService.onAppBlocked = { pkg -> eventSink?.success(pkg) }
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                    AppBlockerService.onAppBlocked = null
                }
            },
        )

        usageEventChannel =
            EventChannel(
                flutterPluginBinding.binaryMessenger,
                "daily_routine_sdk/app_usage/events",
            )
        usageEventChannel.setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                    usageEventSink = sink
                    AppUsageTrackerService.onSessionEnded = { event ->
                        usageEventSink?.success(
                            mapOf(
                                "packageName" to event.packageName,
                                "appLabel" to event.appLabel,
                                "startedAt" to event.startedAt,
                                "durationMs" to event.durationMs,
                            )
                        )
                    }
                }

                override fun onCancel(arguments: Any?) {
                    usageEventSink = null
                    AppUsageTrackerService.onSessionEnded = null
                }
            },
        )
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        usageEventChannel.setStreamHandler(null)
    }

    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        when (call.method) {
            "hasUsageAccess" -> result.success(hasUsageAccess())
            "requestUsageAccess" -> {
                requestUsageAccess()
                result.success(null)
            }
            "getInstalledApps" -> result.success(getInstalledApps())
            "startBlocking" -> {
                val packageIds = (call.argument<List<String>>("packageIds") ?: emptyList())
                startBlocking(packageIds)
                result.success(null)
            }
            "stopBlocking" -> {
                stopBlocking()
                result.success(null)
            }
            "startUsageTracking" -> {
                startUsageTracking()
                result.success(null)
            }
            "stopUsageTracking" -> {
                stopUsageTracking()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun hasUsageAccess(): Boolean {
        val appOps = applicationContext.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                appOps.unsafeCheckOpNoThrow(
                    AppOpsManager.OPSTR_GET_USAGE_STATS,
                    Process.myUid(),
                    applicationContext.packageName,
                )
            } else {
                @Suppress("DEPRECATION")
                appOps.checkOpNoThrow(
                    AppOpsManager.OPSTR_GET_USAGE_STATS,
                    Process.myUid(),
                    applicationContext.packageName,
                )
            }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    private fun requestUsageAccess() {
        val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            data = Uri.parse("package:${applicationContext.packageName}")
        }
        try {
            applicationContext.startActivity(intent)
        } catch (_: Exception) {
            val fallback = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            applicationContext.startActivity(fallback)
        }
    }

    private fun getInstalledApps(): List<Map<String, String>> {
        val pm = applicationContext.packageManager
        val launcherIntent = Intent(Intent.ACTION_MAIN, null).apply {
            addCategory(Intent.CATEGORY_LAUNCHER)
        }
        val resolveInfos = pm.queryIntentActivities(launcherIntent, 0)
        return resolveInfos
            .mapNotNull { info ->
                val appInfo: ApplicationInfo = info.activityInfo?.applicationInfo ?: return@mapNotNull null
                if (appInfo.packageName == applicationContext.packageName) return@mapNotNull null
                mapOf(
                    "packageId" to appInfo.packageName,
                    "displayName" to pm.getApplicationLabel(appInfo).toString(),
                )
            }
            .distinctBy { it["packageId"] }
            .sortedBy { it["displayName"] }
    }

    private fun startBlocking(packageIds: List<String>) {
        val intent = Intent(applicationContext, AppBlockerService::class.java).apply {
            action = AppBlockerService.ACTION_START
            putStringArrayListExtra(AppBlockerService.EXTRA_PACKAGE_IDS, ArrayList(packageIds))
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            applicationContext.startForegroundService(intent)
        } else {
            applicationContext.startService(intent)
        }
    }

    private fun stopBlocking() {
        val intent = Intent(applicationContext, AppBlockerService::class.java).apply {
            action = AppBlockerService.ACTION_STOP
        }
        applicationContext.startService(intent)
    }

    private fun startUsageTracking() {
        val intent = Intent(applicationContext, AppUsageTrackerService::class.java).apply {
            action = AppUsageTrackerService.ACTION_START
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            applicationContext.startForegroundService(intent)
        } else {
            applicationContext.startService(intent)
        }
    }

    private fun stopUsageTracking() {
        val intent = Intent(applicationContext, AppUsageTrackerService::class.java).apply {
            action = AppUsageTrackerService.ACTION_STOP
        }
        applicationContext.startService(intent)
    }
}
