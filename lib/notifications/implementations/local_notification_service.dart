import 'package:daily_routine_sdk/error/app_error.dart';
import 'package:daily_routine_sdk/error/result.dart';
import 'package:daily_routine_sdk/models/routine_task.dart';
import 'package:daily_routine_sdk/notifications/config/local_notification_channel_config.dart';
import 'package:daily_routine_sdk/notifications/notification_service.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// `flutter_local_notifications`-backed [NotificationService]. Reserves 8
/// notification ids per task (`baseId + 0..7`): `0..6` for a specific
/// ISO weekday (Monday=0..Sunday=6, used by `weekdays`/`weekends`/`custom`
/// repeat rules, which may need several concurrently-scheduled
/// notifications), and `7` for a single daily-repeating or one-off
/// reminder (`once`/`daily` repeat rules).
class LocalNotificationService implements NotificationService {
  LocalNotificationService({required this._config});

  final LocalNotificationChannelConfig _config;
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const int _slotsPerTask = 8;

  @override
  Future<void> initialize() async {
    tz_data.initializeTimeZones();
    try {
      final localTimezone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(localTimezone.identifier));
    } catch (_) {
      // Falls back to whatever `timezone` defaults to (UTC) if the device
      // timezone can't be resolved.
    }

    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        linux: LinuxInitializationSettings(defaultActionName: 'Open'),
        macOS: DarwinInitializationSettings(),
      ),
    );

    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          AndroidNotificationChannel(
            _config.channelId,
            _config.channelName,
            description: _config.channelDescription,
          ),
        );
  }

  @override
  Future<Result<bool>> requestPermission() async {
    try {
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();
      final androidGranted = await androidPlugin?.requestNotificationsPermission();
      // Android 12+ (API 31+) also gates exact-time scheduling behind this
      // separate permission; request it so alarmClock/exactAllowWhileIdle
      // reminders don't silently fall back to inexact delivery.
      await androidPlugin?.requestExactAlarmsPermission();
      final iosGranted = await _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
      final macGranted = await _plugin
          .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
      return Result.success(
        androidGranted ?? iosGranted ?? macGranted ?? true,
      );
    } catch (e, st) {
      return Result.failure(
        PermissionError(
          'Failed to request notification permission.',
          cause: e,
          stackTrace: st,
        ),
      );
    }
  }

  @override
  Future<void> scheduleTaskReminder(RoutineTask task) async {
    await cancelReminder(task.id);
    if (!task.reminderEnabled) return;

    final hour = task.startMinuteOfDay ~/ 60;
    final minute = task.startMinuteOfDay % 60;
    final details = task.isAlarm ? _alarmDetails() : _reminderDetails();
    // `alarmClock` is the only Android schedule mode that reliably fires
    // (and wakes the device) through Doze/battery-optimization exactly on
    // time — appropriate for a "must not sleep through this" task; it also
    // shows the alarm-clock icon in the status bar, which is desirable
    // here, not a side effect to work around.
    final scheduleMode = task.isAlarm
        ? AndroidScheduleMode.alarmClock
        : AndroidScheduleMode.exactAllowWhileIdle;
    final body = task.isAlarm ? "Time to get up — don't snooze it away." : 'Coming up now';

    switch (task.repeatRule) {
      case RepeatRule.once:
        await _zonedSchedule(
          _baseId(task.id) + 7,
          task.title,
          body,
          _nextInstance(hour, minute),
          details,
          androidScheduleMode: scheduleMode,
        );
      case RepeatRule.daily:
        await _zonedSchedule(
          _baseId(task.id) + 7,
          task.title,
          body,
          _nextInstance(hour, minute),
          details,
          androidScheduleMode: scheduleMode,
          matchDateTimeComponents: DateTimeComponents.time,
        );
      case RepeatRule.weekdays:
        for (var isoWeekday = 1; isoWeekday <= 5; isoWeekday++) {
          await _scheduleWeekly(task, isoWeekday, hour, minute, body, details, scheduleMode);
        }
      case RepeatRule.weekends:
        for (final isoWeekday in [6, 7]) {
          await _scheduleWeekly(task, isoWeekday, hour, minute, body, details, scheduleMode);
        }
      case RepeatRule.custom:
        for (final isoWeekday in task.customDays) {
          await _scheduleWeekly(task, isoWeekday, hour, minute, body, details, scheduleMode);
        }
    }
  }

  NotificationDetails _reminderDetails() => NotificationDetails(
    android: AndroidNotificationDetails(
      _config.channelId,
      _config.channelName,
      channelDescription: _config.channelDescription,
    ),
    iOS: const DarwinNotificationDetails(),
    macOS: const DarwinNotificationDetails(),
    linux: const LinuxNotificationDetails(),
  );

  /// Full-screen, max-priority, alarm-audio-stream treatment — as close to
  /// a real alarm-clock app as a local notification can get without a
  /// separate native alarm implementation. Falls back to a merely loud
  /// notification on platforms without an equivalent (desktop/Linux).
  NotificationDetails _alarmDetails() => NotificationDetails(
    android: AndroidNotificationDetails(
      _config.channelId,
      _config.channelName,
      channelDescription: _config.channelDescription,
      importance: Importance.max,
      priority: Priority.high,
      category: AndroidNotificationCategory.alarm,
      audioAttributesUsage: AudioAttributesUsage.alarm,
      fullScreenIntent: true,
      ongoing: true,
      autoCancel: false,
    ),
    iOS: const DarwinNotificationDetails(
      interruptionLevel: InterruptionLevel.timeSensitive,
      sound: 'default',
    ),
    macOS: const DarwinNotificationDetails(
      interruptionLevel: InterruptionLevel.timeSensitive,
      sound: 'default',
    ),
    linux: const LinuxNotificationDetails(urgency: LinuxNotificationUrgency.critical),
  );

  Future<void> _scheduleWeekly(
    RoutineTask task,
    int isoWeekday,
    int hour,
    int minute,
    String body,
    NotificationDetails details,
    AndroidScheduleMode scheduleMode,
  ) {
    return _zonedSchedule(
      _baseId(task.id) + (isoWeekday - 1),
      task.title,
      body,
      _nextInstanceOfWeekday(isoWeekday, hour, minute),
      details,
      androidScheduleMode: scheduleMode,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
    );
  }

  /// Thin wrapper around `zonedSchedule` that swallows [UnimplementedError]
  /// and falls back to inexact scheduling when the exact-alarm permission
  /// isn't granted.
  ///
  /// Not every platform's notification backend supports OS-level scheduled
  /// delivery — Linux's D-Bus notifications can only show a notification
  /// immediately, so [FlutterLocalNotificationsPlugin] throws there. Skip
  /// the reminder on those platforms instead of crashing the caller.
  ///
  /// On Android 12+ (API 31+), `alarmClock`/`exactAllowWhileIdle` require the
  /// user to have granted "Alarms & reminders" in system settings (requested
  /// in [requestPermission]); until then the plugin throws a
  /// `PlatformException(exact_alarms_not_permitted)`. Retrying with
  /// `inexactAllowWhileIdle` keeps the reminder roughly on time instead of
  /// losing it (and crashing the caller) entirely.
  Future<void> _zonedSchedule(
    int id,
    String title,
    String body,
    tz.TZDateTime scheduledDate,
    NotificationDetails details, {
    required AndroidScheduleMode androidScheduleMode,
    DateTimeComponents? matchDateTimeComponents,
  }) async {
    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        scheduledDate,
        details,
        androidScheduleMode: androidScheduleMode,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: matchDateTimeComponents,
      );
    } on UnimplementedError {
      // No OS-level scheduling on this platform — nothing to fall back to.
    } on PlatformException catch (e) {
      if (e.code != 'exact_alarms_not_permitted') rethrow;
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        scheduledDate,
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: matchDateTimeComponents,
      );
    }
  }

  @override
  Future<void> cancelReminder(String taskId) async {
    final base = _baseId(taskId);
    for (var i = 0; i < _slotsPerTask; i++) {
      await _plugin.cancel(base + i);
    }
  }

  @override
  Future<void> cancelAllReminders() => _plugin.cancelAll();

  /// Reserves [_slotsPerTask] consecutive, always-positive ids per task,
  /// spaced out so ranges from different tasks never collide.
  int _baseId(String taskId) => (taskId.hashCode & 0x0FFFFFFF) * _slotsPerTask;

  tz.TZDateTime _nextInstance(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  tz.TZDateTime _nextInstanceOfWeekday(int isoWeekday, int hour, int minute) {
    var scheduled = _nextInstance(hour, minute);
    while (scheduled.weekday != isoWeekday) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }
}
