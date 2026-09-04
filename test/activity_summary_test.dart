import 'package:daily_routine_sdk/daily_routine_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ActivitySummary', () {
    test('toJson/fromJson round-trips', () {
      final summary = ActivitySummary(
        date: '2026-09-04',
        totalDurationMs: 60000,
        entries: const [
          ActivitySummaryEntry(label: 'github.com', durationMs: 40000, source: 'chrome'),
          ActivitySummaryEntry(label: 'com.instagram.android', durationMs: 20000, source: 'android'),
        ],
        eventCount: 12,
        computedAt: DateTime(2026, 9, 5),
      );
      final roundTripped = ActivitySummary.fromJson(summary.toJson());
      expect(roundTripped.date, summary.date);
      expect(roundTripped.totalDurationMs, summary.totalDurationMs);
      expect(roundTripped.eventCount, summary.eventCount);
      expect(roundTripped.entries.length, 2);
      expect(roundTripped.entries.first.label, 'github.com');
      expect(roundTripped.entries.first.durationMs, 40000);
    });

    test('fromJson defaults missing eventCount to 0 and entries to empty', () {
      final summary = ActivitySummary.fromJson({
        'date': '2026-09-04',
        'totalDurationMs': 0,
      });
      expect(summary.eventCount, 0);
      expect(summary.entries, isEmpty);
    });
  });
}
