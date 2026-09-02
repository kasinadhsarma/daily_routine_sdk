import 'package:equatable/equatable.dart';

/// One completed foreground-app session, as reported by the platform's
/// usage tracker (e.g. Android's `UsageStatsManager`).
class AppUsageEvent extends Equatable {
  const AppUsageEvent({
    required this.packageName,
    required this.appLabel,
    required this.startedAt,
    required this.durationMs,
    this.windowTitle,
  });

  final String packageName;
  final String appLabel;
  final DateTime startedAt;
  final int durationMs;

  /// The focused window's title, when the platform can read it (desktop
  /// only — Android's `UsageStatsManager` has no window-title concept).
  /// This is often the most useful field for "what was I actually doing":
  /// the file open in an editor, the video playing, the browser tab.
  final String? windowTitle;

  @override
  List<Object?> get props => [packageName, appLabel, startedAt, durationMs, windowTitle];
}
