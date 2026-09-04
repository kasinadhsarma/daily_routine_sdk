import 'package:equatable/equatable.dart';

enum RepeatRule { once, daily, weekdays, weekends, custom }

enum TaskCategory { health, work, study, personal, chores, mindfulness, other }

/// A single scheduled item in a user's daily routine.
class RoutineTask extends Equatable {
  const RoutineTask({
    required this.id,
    required this.title,
    required this.startMinuteOfDay,
    this.durationMinutes = 30,
    this.category = TaskCategory.other,
    this.repeatRule = RepeatRule.daily,
    this.customDays = const <int>[],
    this.reminderEnabled = true,
    this.isAlarm = false,
    this.blockedAppPackageIds = const <String>[],
    this.isCompletedToday = false,
    this.completedDate,
    this.notes = '',
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String title;

  /// Minutes since midnight, e.g. 6:30am == 390.
  final int startMinuteOfDay;
  final int durationMinutes;
  final TaskCategory category;
  final RepeatRule repeatRule;

  /// Used when [repeatRule] is [RepeatRule.custom]. 1 = Monday .. 7 = Sunday.
  final List<int> customDays;
  final bool reminderEnabled;

  /// If true, [NotificationService.scheduleTaskReminder] schedules this
  /// task's reminder as a full-screen, device-waking alarm (Android's
  /// `AndroidScheduleMode.alarmClock` + a full-screen intent) instead of a
  /// normal notification — for tasks like an early wake-up you can't risk
  /// sleeping through. Has no effect on platforms where local notifications
  /// can't wake the device (desktop, web).
  final bool isAlarm;

  /// App/process identifiers to block while this task's session is active.
  final List<String> blockedAppPackageIds;

  /// Raw persisted completion flag — do not read this directly to decide
  /// whether today's occurrence is done, since it's never cleared on its
  /// own; use [isCompletedForToday] instead. It only means anything when
  /// paired with [completedDate], which records which calendar day it was
  /// set for.
  final bool isCompletedToday;

  /// The local calendar day (`yyyy-MM-dd`) [isCompletedToday] applies to —
  /// set whenever the task is marked complete. A recurring task's
  /// completion should only ever reflect *today*; without this, a task
  /// checked off once would show as complete forever afterward, since
  /// nothing else clears the flag.
  final String? completedDate;

  final String notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  int get endMinuteOfDay => startMinuteOfDay + durationMinutes;

  /// Today's local date as `yyyy-MM-dd`, matching [completedDate]'s format.
  static String todayKey() {
    final now = DateTime.now();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return '${now.year}-$month-$day';
  }

  /// Whether this task's *current* occurrence (today) has been completed —
  /// the flag reset automatically as soon as the calendar day changes,
  /// since it's derived from [completedDate] rather than read as a raw
  /// stored boolean.
  bool get isCompletedForToday => isCompletedToday && completedDate == todayKey();

  bool occursOnWeekday(int isoWeekday) {
    switch (repeatRule) {
      case RepeatRule.once:
        return true;
      case RepeatRule.daily:
        return true;
      case RepeatRule.weekdays:
        return isoWeekday >= 1 && isoWeekday <= 5;
      case RepeatRule.weekends:
        return isoWeekday == 6 || isoWeekday == 7;
      case RepeatRule.custom:
        return customDays.contains(isoWeekday);
    }
  }

  RoutineTask copyWith({
    String? id,
    String? title,
    int? startMinuteOfDay,
    int? durationMinutes,
    TaskCategory? category,
    RepeatRule? repeatRule,
    List<int>? customDays,
    bool? reminderEnabled,
    bool? isAlarm,
    List<String>? blockedAppPackageIds,
    bool? isCompletedToday,
    String? completedDate,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return RoutineTask(
      id: id ?? this.id,
      title: title ?? this.title,
      startMinuteOfDay: startMinuteOfDay ?? this.startMinuteOfDay,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      category: category ?? this.category,
      repeatRule: repeatRule ?? this.repeatRule,
      customDays: customDays ?? this.customDays,
      reminderEnabled: reminderEnabled ?? this.reminderEnabled,
      isAlarm: isAlarm ?? this.isAlarm,
      blockedAppPackageIds: blockedAppPackageIds ?? this.blockedAppPackageIds,
      isCompletedToday: isCompletedToday ?? this.isCompletedToday,
      completedDate: completedDate ?? this.completedDate,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'startMinuteOfDay': startMinuteOfDay,
    'durationMinutes': durationMinutes,
    'category': category.name,
    'repeatRule': repeatRule.name,
    'customDays': customDays,
    'reminderEnabled': reminderEnabled,
    'isAlarm': isAlarm,
    'blockedAppPackageIds': blockedAppPackageIds,
    'isCompletedToday': isCompletedToday,
    'completedDate': completedDate,
    'notes': notes,
    'createdAt': createdAt?.toIso8601String(),
    'updatedAt': updatedAt?.toIso8601String(),
  };

  factory RoutineTask.fromJson(Map<String, dynamic> json) => RoutineTask(
    id: json['id'] as String,
    title: json['title'] as String,
    startMinuteOfDay: json['startMinuteOfDay'] as int,
    durationMinutes: json['durationMinutes'] as int? ?? 30,
    category: TaskCategory.values.firstWhere(
      (c) => c.name == json['category'],
      orElse: () => TaskCategory.other,
    ),
    repeatRule: RepeatRule.values.firstWhere(
      (r) => r.name == json['repeatRule'],
      orElse: () => RepeatRule.daily,
    ),
    customDays: (json['customDays'] as List<dynamic>? ?? const []).cast<int>(),
    reminderEnabled: json['reminderEnabled'] as bool? ?? true,
    isAlarm: json['isAlarm'] as bool? ?? false,
    blockedAppPackageIds:
        (json['blockedAppPackageIds'] as List<dynamic>? ?? const [])
            .cast<String>(),
    isCompletedToday: json['isCompletedToday'] as bool? ?? false,
    completedDate: json['completedDate'] as String?,
    notes: json['notes'] as String? ?? '',
    createdAt: json['createdAt'] != null
        ? DateTime.tryParse(json['createdAt'] as String)
        : null,
    updatedAt: json['updatedAt'] != null
        ? DateTime.tryParse(json['updatedAt'] as String)
        : null,
  );

  @override
  List<Object?> get props => [
    id,
    title,
    startMinuteOfDay,
    durationMinutes,
    category,
    repeatRule,
    customDays,
    reminderEnabled,
    isAlarm,
    blockedAppPackageIds,
    isCompletedToday,
    completedDate,
    notes,
  ];
}
