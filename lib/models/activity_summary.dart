/// One entry in a [ActivitySummary]'s breakdown — one app/site's total time
/// for that day.
class ActivitySummaryEntry {
  const ActivitySummaryEntry({
    required this.label,
    required this.durationMs,
    required this.source,
  });

  final String label;
  final int durationMs;

  /// 'chrome' | 'android' | 'desktop' | 'mixed'.
  final String source;

  Map<String, dynamic> toJson() => {
    'label': label,
    'durationMs': durationMs,
    'source': source,
  };

  factory ActivitySummaryEntry.fromJson(Map<String, dynamic> json) => ActivitySummaryEntry(
    label: json['label'] as String,
    durationMs: (json['durationMs'] as num).toInt(),
    source: json['source'] as String? ?? 'unknown',
  );
}

/// A pre-aggregated rollup of one calendar day's activity — computed once
/// from the raw `activity` event log, after which the raw events for that
/// day can be safely deleted. Stored at `users/{uid}/activitySummaries/{date}`.
///
/// Exists so a growing activity log doesn't have to be re-read (and re-paid
/// for, in Firestore read quota) every time a past day's totals are needed —
/// one small summary document replaces however many raw events made up
/// that day.
class ActivitySummary {
  const ActivitySummary({
    required this.date,
    required this.totalDurationMs,
    required this.entries,
    required this.eventCount,
    this.computedAt,
  });

  /// Local calendar day, `yyyy-MM-dd`.
  final String date;
  final int totalDurationMs;
  final List<ActivitySummaryEntry> entries;

  /// How many raw events were folded into this summary — a record of scale,
  /// not needed for anything functional.
  final int eventCount;
  final DateTime? computedAt;

  Map<String, dynamic> toJson() => {
    'date': date,
    'totalDurationMs': totalDurationMs,
    'entries': entries.map((e) => e.toJson()).toList(),
    'eventCount': eventCount,
    'computedAt': (computedAt ?? DateTime.now()).toIso8601String(),
  };

  factory ActivitySummary.fromJson(Map<String, dynamic> json) => ActivitySummary(
    date: json['date'] as String,
    totalDurationMs: (json['totalDurationMs'] as num).toInt(),
    entries: (json['entries'] as List<dynamic>? ?? const [])
        .map((e) => ActivitySummaryEntry.fromJson(e as Map<String, dynamic>))
        .toList(),
    eventCount: (json['eventCount'] as num?)?.toInt() ?? 0,
    computedAt: json['computedAt'] != null
        ? DateTime.tryParse(json['computedAt'] as String)
        : null,
  );
}
