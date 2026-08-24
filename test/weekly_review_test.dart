import 'package:flutter_test/flutter_test.dart';

import 'package:habit_tracker/models/habit.dart';
import 'package:habit_tracker/models/weekly_review.dart';

import 'synergy_test.dart' show habitWith;

/// Every day from [from] to [to] days ago, inclusive.
List<int> range(int from, int to) => [
  for (var i = from; i <= to; i++) i,
];

void main() {
  final today = dateOnly(DateTime.now());

  group('the window', () {
    test('covers seven days ending today', () {
      final review = WeeklyReview.from([habitWith('a', const [])]);

      expect(review.to, today);
      expect(review.from, addDays(today, -6));
    });

    test('counts only what fell inside it', () {
      // Done every day for a fortnight: seven due, seven done.
      final review = WeeklyReview.from([
        habitWith('a', range(0, 13), ageInDays: 13),
      ]);

      expect(review.due, 7);
      expect(review.done, 7);
      expect(review.percent, 100);
    });

    test('is empty when nothing was ever scheduled', () {
      final review = WeeklyReview.from(const <Habit>[]);

      expect(review.isEmpty, isTrue);
      expect(review.lines, isEmpty);
    });
  });

  group('the comparison', () {
    test('reports a rise against the week before', () {
      final review = WeeklyReview.from([
        habitWith('a', range(0, 6), ageInDays: 13),
      ]);

      expect(review.previousDue, 7);
      expect(review.previousDone, 0);
      expect(review.deltaPoints, 100);
      expect(
        review.lines.first.tone,
        ReviewTone.good,
      );
    });

    test('reports a fall the other way round', () {
      final review = WeeklyReview.from([
        habitWith('a', range(7, 13), ageInDays: 13),
      ]);

      expect(review.deltaPoints, -100);
      expect(review.lines.first.tone, ReviewTone.warning);
    });

    test('makes no claim when there is no previous week', () {
      // Created six days ago, so the older window holds nothing to compare to.
      final review = WeeklyReview.from([
        habitWith('a', range(0, 5), ageInDays: 5),
      ]);

      expect(review.previousDue, 0);
      expect(review.deltaPoints, isNull);
    });
  });

  group('perfect days', () {
    test('counts days where everything due was done', () {
      final review = WeeklyReview.from([
        habitWith('a', range(0, 6), ageInDays: 20),
        habitWith('b', range(0, 3), ageInDays: 20),
      ]);

      expect(review.perfectDays, 4);
    });

    test('does not count a day nothing was due on', () {
      final weekday = today.weekday;
      final review = WeeklyReview.from([
        Habit(
          id: 'weekly',
          title: 'Weekly',
          icon: habitWith('x', const []).icon,
          color: habitWith('x', const []).color,
          schedule: HabitSchedule.onDays({weekday}),
          createdAt: addDays(today, -20),
          completedDays: {today},
        ),
      ]);

      expect(review.perfectDays, 1);
    });
  });

  group('days off', () {
    test('are counted and kept out of the denominator', () {
      final review = WeeklyReview.from([
        habitWith(
          'a',
          range(0, 4),
          ageInDays: 20,
          daysOff: const [5, 6],
        ),
      ]);

      expect(review.daysOff, 2);
      expect(review.due, 5);
      expect(review.percent, 100);
    });

    test('get a line of their own so a quiet week reads as planned', () {
      final review = WeeklyReview.from([
        habitWith('a', range(0, 4), ageInDays: 20, daysOff: const [5, 6]),
      ]);

      expect(
        review.lines.any((l) => l.text.contains('planned day')),
        isTrue,
      );
    });
  });

  group('the narrative', () {
    test('names the habit that is slipping', () {
      final review = WeeklyReview.from([
        habitWith('steady', range(0, 40), ageInDays: 40),
        habitWith('slipping', range(20, 40), ageInDays: 40),
      ]);

      expect(
        review.lines.any(
          (l) => l.text.contains('slipping') && l.tone == ReviewTone.warning,
        ),
        isTrue,
      );
    });

    test('reports a correlation when the history supports one', () {
      final even = [for (var i = 0; i <= 89; i += 2) i];
      final review = WeeklyReview.from([
        habitWith('run', even),
        habitWith('read', even),
      ]);

      expect(review.lines.any((l) => l.text.contains('of the days you')), isTrue);
    });

    test('says nothing about a weekday spread that is not there', () {
      final review = WeeklyReview.from([
        habitWith('a', range(0, 60), ageInDays: 60),
      ]);

      expect(review.lines.any((l) => l.text.contains('weakest day')), isFalse);
    });
  });

  group('the next milestone', () {
    test('is the nearest badge still locked', () {
      final review = WeeklyReview.from([habitWith('a', const [])]);

      expect(review.nextMilestone?.id, 'first_step');
      expect(review.nextMilestoneValue, 0);
    });

    test('moves on once one is earned', () {
      final review = WeeklyReview.from([
        habitWith('a', range(0, 6), ageInDays: 20),
      ]);

      expect(review.nextMilestone?.id, isNot('first_step'));
    });
  });
}
