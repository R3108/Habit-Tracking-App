import 'package:flutter_test/flutter_test.dart';

import 'package:habit_tracker/models/habit.dart';
import 'package:habit_tracker/models/lab/automaticity.dart';

import 'lab_fixtures.dart';

void main() {
  group('the composite', () {
    test('a long, perfectly kept habit reads as automatic', () {
      final score = AutomaticityScore.of(
        labHabit(done: (age) => true),
        reference: labReference,
      );

      expect(score.hasEnoughHistory, isTrue);
      expect(score.strength, HabitStrength.automatic);
      expect(score.isReadyToGraduate, isTrue);
      expect(score.weakest, isNull);
    });

    test('a habit two weeks old is still forming, however well it went', () {
      final score = AutomaticityScore.of(
        labHabit(done: (age) => true, ageInDays: 15),
        reference: labReference,
      );

      // Consistency is perfect and tenure is not, which is the entire point:
      // the one thing a composite must not let a habit buy its way out of.
      expect(score.consistency, greaterThan(0.85));
      expect(score.tenure, lessThan(0.3));
      expect(score.isReadyToGraduate, isFalse);
      expect(score.strength, isNot(HabitStrength.automatic));
    });

    test('a habit with almost no due days declines to judge', () {
      final score = AutomaticityScore.of(
        labHabit(done: (age) => true, ageInDays: 5),
        reference: labReference,
      );

      expect(score.hasEnoughHistory, isFalse);
      expect(score.summary, contains('Not enough due days'));
      expect(score.weakest, isNull);
    });

    test('a habit that never happened scores near the floor', () {
      final score = AutomaticityScore.of(
        labHabit(done: (age) => false),
        reference: labReference,
      );

      expect(score.strength, HabitStrength.forming);
      expect(score.consistency, lessThan(0.15));
    });
  });

  group('resilience', () {
    test('isolated misses recover, and the habit is not called fragile', () {
      // One miss every ten days, each followed by a kept day.
      final score = AutomaticityScore.of(
        labHabit(done: (age) => age % 10 != 0),
        reference: labReference,
      );

      expect(score.missesObserved, greaterThan(4));
      expect(score.resilience, greaterThan(0.85));
      expect(score.isFragile, isFalse);
    });

    test('clustered misses are caught even though the average looks fine', () {
      // Four consecutive misses every thirty days: ~87% kept overall, but a
      // miss is followed by another miss three times out of four.
      final score = AutomaticityScore.of(
        labHabit(done: (age) => age % 30 >= 4),
        reference: labReference,
      );

      expect(score.consistency, greaterThan(0.75));
      expect(score.resilience, lessThan(score.consistency - 0.25));
      expect(score.isFragile, isTrue);
      expect(score.summary, contains('run of them'));
    });

    test('a habit that never missed inherits its consistency', () {
      final score = AutomaticityScore.of(
        labHabit(done: (age) => true),
        reference: labReference,
      );

      expect(score.missesObserved, 0);
      expect(score.resilience, closeTo(score.consistency, 0.001));
    });

    test('a miss whose next due day is weeks away is not counted', () {
      // Mon/Wed/Fri, missing only the very first due day in the window. The
      // following due day is two days later, so this one *is* counted — the
      // guard is about gaps, and the test pins that the ordinary case survives
      // it rather than being silently dropped.
      final score = AutomaticityScore.of(
        labHabit(
          done: (age) => age != 180,
          schedule: const HabitSchedule.onDays({1, 3, 5}),
        ),
        reference: labReference,
      );

      expect(score.dueDays, greaterThan(20));
      expect(score.consistency, greaterThan(0.9));
    });
  });

  group('regularity', () {
    test('an even habit scores full marks', () {
      final score = AutomaticityScore.of(
        labHabit(done: (age) => age % 2 == 0),
        reference: labReference,
      );

      // Every weekday is hit at the same rate, so there is no unevenness for
      // this component to find.
      expect(score.regularity, greaterThan(0.8));
    });

    test('a weekday-only pattern is marked down', () {
      final score = AutomaticityScore.of(
        labHabit(
          done: (age) {
            final day = addDays(labReference, -age);
            return day.weekday <= 5;
          },
        ),
        reference: labReference,
      );

      expect(score.regularity, lessThan(0.5));
      expect(score.weakest?.label, 'Evenness across the week');
    });
  });

  group('the list', () {
    test('scores every active habit, strongest first', () {
      final scores = scoreAutomaticity(
        <Habit>[
          labHabit(done: (age) => age % 3 == 0, id: 'patchy'),
          labHabit(done: (age) => true, id: 'solid'),
        ],
        reference: labReference,
      );

      expect(scores, hasLength(2));
      expect(scores.first.habitId, 'solid');
      expect(scores.first.score, greaterThan(scores.last.score));
    });

    test('archived habits are left out', () {
      final scores = scoreAutomaticity(
        <Habit>[
          labHabit(done: (age) => true, id: 'kept'),
          labHabit(done: (age) => true, id: 'gone').copyWith(archived: true),
        ],
        reference: labReference,
      );

      expect(scores, hasLength(1));
      expect(scores.single.habitId, 'kept');
    });
  });
}
