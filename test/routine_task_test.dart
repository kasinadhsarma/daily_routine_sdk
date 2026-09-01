import 'package:daily_routine_sdk/daily_routine_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RoutineTask', () {
    test('endMinuteOfDay adds duration to start', () {
      const task = RoutineTask(
        id: '1',
        title: 'Run',
        startMinuteOfDay: 360,
        durationMinutes: 45,
      );
      expect(task.endMinuteOfDay, 405);
    });

    test('occursOnWeekday for RepeatRule.custom uses customDays', () {
      const task = RoutineTask(
        id: '1',
        title: 'Gym',
        startMinuteOfDay: 420,
        repeatRule: RepeatRule.custom,
        customDays: [2, 4],
      );
      expect(task.occursOnWeekday(DateTime.tuesday), isTrue);
      expect(task.occursOnWeekday(DateTime.wednesday), isFalse);
    });

    test('toJson/fromJson round-trips', () {
      const task = RoutineTask(
        id: 'abc',
        title: 'Read',
        startMinuteOfDay: 1200,
        durationMinutes: 20,
        category: TaskCategory.study,
        repeatRule: RepeatRule.weekends,
        blockedAppPackageIds: ['com.instagram.android'],
      );
      final roundTripped = RoutineTask.fromJson(task.toJson());
      expect(roundTripped, task);
    });
  });

  group('formatMinuteOfDay', () {
    test('formats midnight and noon correctly', () {
      expect(formatMinuteOfDay(0), '12:00 AM');
      expect(formatMinuteOfDay(720), '12:00 PM');
    });
  });

  group('Result', () {
    test('fold dispatches to onSuccess/onFailure', () {
      const success = Result<int>.success(42);
      const failure = Result<int>.failure(UnknownError('boom'));

      expect(success.fold((v) => v, (e) => -1), 42);
      expect(failure.fold((v) => v, (e) => -1), -1);
    });
  });
}
