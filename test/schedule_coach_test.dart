import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:habit_tracker/models/habit.dart';
import 'package:habit_tracker/models/schedule_coach.dart';

final reference = DateTime(2026, 8, 26);

Habit habit({
  required bool Function(int age) done,
  HabitSchedule schedule = const HabitSchedule.daily(),
  int ageInDays = 120,
  String id = 'h',
  String title = 'Morning run',
}) {
  return Habit(
    id: id,
    title: title,
    icon: Icons.check,
    color: const Color(0xFF1565C0),
    schedule: schedule,
    createdAt: addDays(reference, -ageInDays),
    completedDays: <DateTime>{
      for (var age = 1; age <= ageInDays; age++)
        if (done(age)) addDays(reference, -age),
    },
  );
}

/// The ISO weekday sitting [age] days before the reference.
int weekdayAt(int age) => addDays(reference, -age).weekday;

void main() {
  group('dropping a weekday', () {
    test('names the day that never happens', () {
      // Every day but Friday, for twelve weeks.
      final run = habit(done: (age) => weekdayAt(age) != DateTime.friday);

      final suggestion = scheduleSuggestions([run], reference: reference).single;

      expect(suggestion.change, ScheduleChange.dropWeekday);
      expect(suggestion.headline, 'Stop asking on Fridays');
      expect(suggestion.rationale, contains('0%'));
      expect(suggestion.proposed.frequency, HabitFrequency.specificDays);
      expect(suggestion.proposed.weekdays, isNot(contains(DateTime.friday)));
      expect(suggestion.proposed.weekdays, hasLength(6));
    });

    test('leaves a weekday that is merely worse than the others alone', () {
      // Fridays at two thirds against a perfect rest of the week: bad, but not
      // the kind of bad a schedule change fixes.
      final run = habit(
        done: (age) => weekdayAt(age) != DateTime.friday || age % 21 != 0,
      );

      expect(scheduleSuggestions([run], reference: reference), isEmpty);
    });

    test('will not carve a two-day schedule down to one', () {
      final run = habit(
        schedule: const HabitSchedule.onDays({DateTime.monday, DateTime.friday}),
        done: (age) => weekdayAt(age) != DateTime.friday,
      );

      final suggestions = scheduleSuggestions([run], reference: reference);
      expect(
        suggestions.where((s) => s.change == ScheduleChange.dropWeekday),
        isEmpty,
      );
    });
  });

  group('switching to a quota', () {
    test('offers one when the habit happens often but never on a set day', () {
      // Four days out of every seven, rotating a day each week, so no weekday
      // stands out as the problem.
      final gym = habit(
        title: 'Gym',
        done: (age) {
          final week = (age - 1) ~/ 7;
          final dayInWeek = (age - 1) % 7;
          return (dayInWeek + week) % 7 < 4;
        },
      );

      final suggestion = scheduleSuggestions([gym], reference: reference).single;

      expect(suggestion.change, ScheduleChange.switchToQuota);
      expect(suggestion.proposed.frequency, HabitFrequency.timesPerWeek);
      expect(suggestion.proposed.timesPerWeek, 4);
      expect(suggestion.headline, 'Try 4× a week');
    });

    test('says nothing when the misses cluster on one day instead', () {
      final run = habit(done: (age) => weekdayAt(age) != DateTime.friday);

      final suggestion = scheduleSuggestions([run], reference: reference).single;
      expect(suggestion.change, isNot(ScheduleChange.switchToQuota));
    });

    test('says nothing when the habit is barely happening at all', () {
      // A quota would dress a collapse up as a plan.
      final gym = habit(done: (age) => age % 5 == 0);

      expect(scheduleSuggestions([gym], reference: reference), isEmpty);
    });
  });

  group('retuning a quota', () {
    test('eases one that is missed by two every week', () {
      final swim = habit(
        title: 'Swim',
        schedule: const HabitSchedule.timesAWeek(5),
        done: (age) => (age - 1) % 7 < 2,
      );

      final suggestion = scheduleSuggestions([swim], reference: reference).single;

      expect(suggestion.change, ScheduleChange.easeQuota);
      expect(suggestion.proposed.timesPerWeek, 2);
      expect(suggestion.rationale, contains('median week'));
    });

    test('raises one that is beaten week after week', () {
      final swim = habit(
        title: 'Swim',
        schedule: const HabitSchedule.timesAWeek(2),
        done: (age) => (age - 1) % 7 < 4,
      );

      final suggestion = scheduleSuggestions([swim], reference: reference).single;

      expect(suggestion.change, ScheduleChange.raiseQuota);
      expect(suggestion.proposed.timesPerWeek, 4);
    });

    test('leaves a quota that is being met alone', () {
      final swim = habit(
        schedule: const HabitSchedule.timesAWeek(3),
        done: (age) => (age - 1) % 7 < 3,
      );

      expect(scheduleSuggestions([swim], reference: reference), isEmpty);
    });
  });

  group('holding back', () {
    test('a habit too young to have a pattern is left alone', () {
      final fresh = habit(
        ageInDays: 20,
        done: (age) => weekdayAt(age) != DateTime.friday,
      );

      expect(scheduleSuggestions([fresh], reference: reference), isEmpty);
    });

    test('an archived habit is not re-planned', () {
      final run = habit(
        done: (age) => weekdayAt(age) != DateTime.friday,
      ).copyWith(archived: true);

      expect(scheduleSuggestions([run], reference: reference), isEmpty);
    });

    test('a schedule that fits produces nothing', () {
      final read = habit(done: (age) => true);

      expect(scheduleSuggestions([read], reference: reference), isEmpty);
    });

    test('one habit yields at most one suggestion', () {
      final run = habit(done: (age) => weekdayAt(age) != DateTime.friday);

      expect(
        scheduleSuggestions([run], reference: reference),
        hasLength(1),
      );
    });

    test('the list is capped', () {
      final habits = <Habit>[
        for (var i = 0; i < 5; i++)
          habit(
            id: 'h$i',
            title: 'Habit $i',
            done: (age) => weekdayAt(age) != DateTime.friday,
          ),
      ];

      expect(
        scheduleSuggestions(habits, reference: reference, limit: 2),
        hasLength(2),
      );
    });
  });
}
