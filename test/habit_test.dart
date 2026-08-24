import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:habit_tracker/models/habit.dart';

Habit habitDoneOn(
  List<int> daysAgo, {
  HabitSchedule schedule = const HabitSchedule.daily(),
  int targetPerDay = 1,
  DateTime? createdAt,
}) {
  final today = dateOnly(DateTime.now());
  return Habit(
    id: 'test',
    title: 'Test',
    icon: Icons.check,
    color: const Color(0xFF000000),
    schedule: schedule,
    targetPerDay: targetPerDay,
    createdAt: createdAt ?? addDays(today, -400),
    completedDays: daysAgo.map((d) => addDays(today, -d)).toSet(),
  );
}

void main() {
  group('streak', () {
    test('is zero with no completions', () {
      expect(habitDoneOn([]).streak, 0);
    });

    test('counts consecutive days ending today', () {
      expect(habitDoneOn([0, 1, 2]).streak, 3);
    });

    test('survives an unmarked today by counting back from yesterday', () {
      expect(habitDoneOn([1, 2, 3]).streak, 3);
    });

    test('breaks on a missed day', () {
      expect(habitDoneOn([0, 1, 3, 4]).streak, 2);
    });

    test('is zero when the last completion is older than yesterday', () {
      expect(habitDoneOn([2, 3, 4]).streak, 0);
    });

    test('steps over days the schedule does not ask for', () {
      // Due only on the weekday of "three days ago" and its neighbours are
      // skipped, so a gap between two due days is not a miss.
      final today = dateOnly(DateTime.now());
      final weekday = addDays(today, -3).weekday;
      final habit = habitDoneOn(
        [3, 10],
        schedule: HabitSchedule.onDays({weekday}),
      );
      expect(habit.streak, 2);
    });

    test('cannot reach back before the first logged day', () {
      // A schedule with no due days would otherwise walk backwards forever.
      final habit = habitDoneOn([0], schedule: const HabitSchedule.onDays({}));
      expect(habit.streak, isNonNegative);
    });
  });

  group('bestStreak', () {
    test('is zero with no history', () {
      expect(habitDoneOn([]).bestStreak, 0);
    });

    test('finds the longest run, not the current one', () {
      expect(habitDoneOn([0, 1, 5, 6, 7, 8]).bestStreak, 4);
    });

    test('does not let an unmarked today end the run', () {
      expect(habitDoneOn([1, 2, 3]).bestStreak, 3);
    });
  });

  group('toggle', () {
    test('marks an unmarked day and leaves the original untouched', () {
      final habit = habitDoneOn([]);
      final today = DateTime.now();

      final toggled = habit.toggle(today);

      expect(toggled.isCompletedOn(today), isTrue);
      expect(habit.isCompletedOn(today), isFalse);
    });

    test('clears an already-marked day', () {
      final habit = habitDoneOn([0]);
      expect(
        habit.toggle(DateTime.now()).isCompletedOn(DateTime.now()),
        isFalse,
      );
    });

    test('ignores the time component of the given date', () {
      final habit = habitDoneOn([0]);
      final laterToday = dateOnly(
        DateTime.now(),
      ).add(const Duration(hours: 23));
      expect(habit.isCompletedOn(laterToday), isTrue);
    });
  });

  group('count targets', () {
    test('a day is incomplete until it reaches the target', () {
      final today = DateTime.now();
      var habit = habitDoneOn([], targetPerDay: 3);

      habit = habit.increment(today);
      expect(habit.progressOn(today), 1);
      expect(habit.isCompletedOn(today), isFalse);

      habit = habit.increment(today).increment(today);
      expect(habit.isCompletedOn(today), isTrue);
    });

    test('increment stops at the target', () {
      final today = DateTime.now();
      var habit = habitDoneOn([], targetPerDay: 2);
      for (var i = 0; i < 5; i++) {
        habit = habit.increment(today);
      }
      expect(habit.progressOn(today), 2);
    });

    test('decrement clears the day at zero', () {
      final today = DateTime.now();
      final habit = habitDoneOn([], targetPerDay: 2).increment(today);
      expect(habit.decrement(today).progressOn(today), 0);
      expect(habit.decrement(today).entries, isEmpty);
    });

    test('toggle fills the whole day', () {
      final today = DateTime.now();
      final habit = habitDoneOn([], targetPerDay: 8).toggle(today);
      expect(habit.progressOn(today), 8);
    });
  });

  group('completion windows', () {
    test('completionsInLast counts only the requested window', () {
      expect(habitDoneOn([0, 1, 8, 9]).completionsInLast(7), 2);
    });

    test('dueDaysInLast ignores days before the habit existed', () {
      final today = dateOnly(DateTime.now());
      final habit = habitDoneOn([0], createdAt: addDays(today, -2));
      expect(habit.dueDaysInLast(30), 3);
    });

    test('the rate is measured against due days, not calendar days', () {
      final today = dateOnly(DateTime.now());
      final habit = habitDoneOn(
        [0, 1],
        createdAt: addDays(today, -1),
      );
      expect(habit.completionRateInLast(30), 1.0);
    });
  });

  group('schedule', () {
    test('daily is due every day', () {
      const schedule = HabitSchedule.daily();
      expect(schedule.isDueOn(DateTime(2026, 8, 23)), isTrue);
      expect(schedule.weeklyTarget, 7);
    });

    test('specific days are due only on those weekdays', () {
      const schedule = HabitSchedule.onDays({1, 3, 5});
      expect(schedule.isDueOn(DateTime(2026, 8, 24)), isTrue); // Monday
      expect(schedule.isDueOn(DateTime(2026, 8, 25)), isFalse); // Tuesday
      expect(schedule.weeklyTarget, 3);
    });

    test('a weekly quota is due any day but targets the quota', () {
      const schedule = HabitSchedule.timesAWeek(3);
      expect(schedule.isDueOn(DateTime(2026, 8, 25)), isTrue);
      expect(schedule.weeklyTarget, 3);
    });

    test('labels collapse the common cases', () {
      expect(const HabitSchedule.onDays({1, 2, 3, 4, 5}).label, 'Weekdays');
      expect(const HabitSchedule.onDays({6, 7}).label, 'Weekends');
      expect(const HabitSchedule.onDays({2, 4}).label, 'Tue, Thu');
    });
  });

  group('json', () {
    test('round-trips every field', () {
      final today = dateOnly(DateTime.now());
      final original = Habit(
        id: 'round-trip',
        title: 'Drink water',
        icon: Icons.local_drink,
        color: const Color(0xFF00838F),
        targetPerDay: 8,
        schedule: const HabitSchedule.onDays({1, 3, 5}),
        reminder: const TimeOfDay(hour: 7, minute: 45),
        note: 'A glass an hour',
        archived: true,
        createdAt: addDays(today, -30),
        entries: {today: 5, addDays(today, -1): 8},
      );

      final restored = Habit.fromJson(original.toJson());

      expect(restored.id, original.id);
      expect(restored.title, original.title);
      expect(restored.icon.codePoint, original.icon.codePoint);
      expect(restored.color, original.color);
      expect(restored.targetPerDay, 8);
      expect(restored.schedule, original.schedule);
      expect(restored.reminder, const TimeOfDay(hour: 7, minute: 45));
      expect(restored.note, 'A glass an hour');
      expect(restored.archived, isTrue);
      expect(restored.createdAt, original.createdAt);
      expect(restored.entries, original.entries);
    });

    test('survives missing and unknown fields', () {
      final restored = Habit.fromJson(<String, dynamic>{
        'title': 'Sparse',
        'icon': 'no-such-icon',
      });

      expect(restored.title, 'Sparse');
      expect(restored.targetPerDay, 1);
      expect(restored.schedule.frequency, HabitFrequency.daily);
      expect(restored.reminder, isNull);
    });

    test('an icon dropped from the catalogue falls back rather than throwing', () {
      final json = Habit.fromJson(<String, dynamic>{'icon': 'retired'});
      expect(json.icon.codePoint, Icons.check_circle.codePoint);
    });
  });

  group('date helpers', () {
    test('addDays crosses month and year boundaries', () {
      expect(addDays(DateTime(2026, 12, 31), 1), DateTime(2027, 1, 1));
      expect(addDays(DateTime(2026, 3, 1), -1), DateTime(2026, 2, 28));
    });

    test('startOfWeek respects the configured first day', () {
      final wednesday = DateTime(2026, 8, 26);
      expect(startOfWeek(wednesday), DateTime(2026, 8, 24));
      expect(
        startOfWeek(wednesday, weekStartsOn: DateTime.sunday),
        DateTime(2026, 8, 23),
      );
    });
  });
}
