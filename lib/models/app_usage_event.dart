import 'package:equatable/equatable.dart';

/// One completed foreground-app session, as reported by the platform's
/// usage tracker (e.g. Android's `UsageStatsManager`).
class AppUsageEvent extends Equatable {
  const AppUsageEvent({
    required this.packageName,
    required this.appLabel,
    required this.startedAt,
    required this.durationMs,
  });

  final String packageName;
  final String appLabel;
  final DateTime startedAt;
  final int durationMs;

  @override
  List<Object?> get props => [packageName, appLabel, startedAt, durationMs];
}
