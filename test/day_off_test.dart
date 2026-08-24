import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:habit_tracker/data/app_repository.dart';
import 'package:habit_tracker/models/habit.dart';
import 'package:habit_tracker/models/insights.dart';
import 'package:habit_tracker/state/habit_store.dart';

import 'habit_test.dart' show habitDoneOn;

void main() {
  final today = dateOnly(DateTime.now());

  group('a planned day off', () {
    test('does not break a streak it sits in the middle of', () {
      // Done today and three days ago; the two days between are taken off.
      final habit = habitDoneOn([0, 3])
          .setSkipped(addDays(today, -1), true)
          .setSkipped(addDays(today, -2), true);

      expect(habit.streak, 2);
    });

    test('without the shield the same history breaks', () {
      expect(habitDoneOn([0, 3]).streak, 1);
    });

    test('is stepped over by the best streak too', () {
      final habit = habitDoneOn([1, 2, 5, 6])
          .setSkipped(addDays(today, -3), true)
          .setSkipped(addDays(today, -4), true);

      expect(habit.bestStreak, 4);
    });

    test('drops out of the due-day count, so the rate is unhurt', () {
      final habit = habitDoneOn(
        [0, 1],
        createdAt: addDays(today, -3),
      ).setSkipped(addDays(today, -2), true).setSkipped(addDays(today, -3), true);

      expect(habit.dueDaysInLast(30), 2);
      expect(habit.completionRateInLast(30), 1.0);
    });

    test('is not due, but the schedule still says it would have been', () {
      final habit = habitDoneOn([]).setSkipped(today, true);

      expect(habit.isDueOn(today), isFalse);
      expect(habit.schedule.isDueOn(today), isTrue);
      expect(habit.isSkippedOn(today), isTrue);
    });

    test('clears the completion on a day that was already ticked', () {
      final habit = habitDoneOn([0]).setSkipped(today, true);

      expect(habit.isCompletedOn(today), isFalse);
      expect(habit.isSkippedOn(today), isTrue);
    });

    test('cannot survive work being logged against the day', () {
      // The constructor resolves the contradiction rather than leaving a day
      // that is both worked and written off.
      final habit = habitDoneOn([]).setSkipped(today, true).toggle(today);

      expect(habit.isCompletedOn(today), isTrue);
      expect(habit.isSkippedOn(today), isFalse);
    });

    test('can be taken back', () {
      final habit = habitDoneOn([]).setSkipped(today, true).setSkipped(today, false);

      expect(habit.isSkippedOn(today), isFalse);
      expect(habit.isDueOn(today), isTrue);
    });

    test('returns the same instance when nothing would change', () {
      final habit = habitDoneOn([]);
      expect(identical(habit.setSkipped(today, false), habit), isTrue);
    });

    test('counts toward the shields-used readout', () {
      final habit = habitDoneOn([])
          .setSkipped(today, true)
          .setSkipped(addDays(today, -40), true);

      expect(habit.skipsInLast(30), 1);
      expect(habit.skipsInLast(60), 2);
    });

    test('round-trips through JSON', () {
      final habit = habitDoneOn([]).setSkipped(addDays(today, -1), true);
      final restored = Habit.fromJson(habit.toJson());

      expect(restored.skippedDays, habit.skippedDays);
      expect(restored.isSkippedOn(addDays(today, -1)), isTrue);
    });

    test('is absent from a schema v1 payload without complaint', () {
      final restored = Habit.fromJson(<String, dynamic>{'title': 'Old'});
      expect(restored.skippedDays, isEmpty);
    });
  });

  group('the rest of the app agrees', () {
    test('a shielded habit leaves the day\'s checklist', () async {
      final store = HabitStore(
        repository: InMemoryAppRepository(
          habits: [
            Habit(
              id: 'gym',
              title: 'Gym',
              icon: Icons.abc,
              color: Colors.red,
              createdAt: addDays(today, -10),
            ),
          ],
        ),
        saveDebounce: Duration.zero,
      );
      await store.load();

      expect(store.dueCountOn(today), 1);
      store.setSkipped('gym', today, true);
      expect(store.dueCountOn(today), 0);
    });

    test('a shielded day is not counted as a miss by the insights walk', () {
      final habit = habitDoneOn(
        [0],
        createdAt: addDays(today, -1),
      ).setSkipped(addDays(today, -1), true);

      final insights = OverallInsights.from([habit], window: 2);
      final yesterday = insights.days.first;

      expect(yesterday.hasData, isFalse);
      expect(insights.thirtyDayRate, 1.0);
    });
  });
}
