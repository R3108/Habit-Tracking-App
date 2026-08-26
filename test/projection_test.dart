import 'package:flutter_test/flutter_test.dart';

import 'package:habit_tracker/models/habit.dart';
import 'package:habit_tracker/models/lab/projection.dart';

import 'lab_fixtures.dart';

void main() {
  group('the transition rates', () {
    test('a habit always kept expects to go on being kept', () {
      final projection = HabitProjection.of(
        labHabit(done: (age) => true),
        reference: labReference,
      );

      expect(projection.hasEnoughHistory, isTrue);
      expect(projection.afterKept, greaterThan(0.9));
      // Ninety days, all due, nearly all kept.
      expect(projection.expectedCompletions, greaterThan(80));
    });

    test('a habit never kept expects little', () {
      final projection = HabitProjection.of(
        labHabit(done: (age) => false),
        reference: labReference,
      );

      expect(projection.afterMissed, lessThan(0.15));
      expect(projection.expectedCompletions, lessThan(15));
      expect(projection.currentStreak, 0);
      expect(projection.holdProbability, 0);
    });

    test('clustered misses are separated from isolated ones', () {
      final clustered = HabitProjection.of(
        labHabit(done: (age) => age % 30 >= 4),
        reference: labReference,
      );
      final isolated = HabitProjection.of(
        labHabit(done: (age) => age % 8 != 0),
        reference: labReference,
      );

      expect(clustered.missesCluster, isTrue);
      expect(clustered.afterMissed, lessThan(clustered.afterKept - 0.15));

      // Roughly the same overall rate, and a completely different shape.
      expect(isolated.missesCluster, isFalse);
    });

    test('too few due days is admitted rather than simulated over', () {
      final projection = HabitProjection.of(
        labHabit(done: (age) => true, ageInDays: 8),
        reference: labReference,
      );

      expect(projection.hasEnoughHistory, isFalse);
      expect(projection.missesCluster, isFalse);
    });
  });

  group('milestones', () {
    test('a reliable habit is likely to reach the next milestone', () {
      // One miss twelve days back, so the current run is eleven and the next
      // milestone — fourteen — is close enough to be worth naming.
      final projection = HabitProjection.of(
        labHabit(done: (age) => age != 12),
        reference: labReference,
      );

      expect(projection.currentStreak, 11);
      final milestone = projection.nextMilestone;
      expect(milestone, isNotNull);
      expect(milestone!.target, 14);
      expect(milestone.probability, greaterThan(0.5));
      expect(milestone.isLikely, isTrue);
      expect(milestone.medianDays, isNotNull);
    });

    test('a milestone a perfect run could not reach is not offered', () {
      // A 200-day streak has 365 next, and ninety days cannot bridge that.
      final projection = HabitProjection.of(
        labHabit(done: (age) => true),
        reference: labReference,
      );

      expect(projection.currentStreak, 200);
      expect(projection.nextMilestone, isNull);
    });

    test('an unreliable habit is not, and no median is claimed', () {
      // A run is broken roughly every third due day, so a 7-day streak inside
      // the horizon is a long shot.
      final projection = HabitProjection.of(
        labHabit(done: (age) => age % 3 != 0),
        reference: labReference,
      );

      final milestone = projection.nextMilestone;
      expect(milestone, isNotNull);
      expect(milestone!.probability, lessThan(0.5));
      expect(milestone.medianDays, isNull);
    });

    test('a habit past the last milestone has nothing left to aim at', () {
      final projection = HabitProjection.of(
        labHabit(done: (age) => true, ageInDays: 400),
        reference: labReference,
      );

      expect(projection.currentStreak, greaterThan(365));
      expect(projection.nextMilestone, isNull);
    });
  });

  group('holding a streak', () {
    test('a solid run is likely to survive the month', () {
      final projection = HabitProjection.of(
        labHabit(done: (age) => true),
        reference: labReference,
      );

      expect(projection.currentStreak, greaterThan(100));
      expect(projection.holdProbability, greaterThan(0.5));
    });

    test('a shaky run is not', () {
      final projection = HabitProjection.of(
        labHabit(done: (age) => age % 4 != 0),
        reference: labReference,
      );

      expect(projection.holdProbability, lessThan(0.3));
    });
  });

  group('determinism', () {
    test('the same history and seed give the same numbers', () {
      final habit = labHabit(done: (age) => age % 5 != 0);

      final first = HabitProjection.of(
        habit,
        reference: labReference,
        seed: 99,
      );
      final second = HabitProjection.of(
        habit,
        reference: labReference,
        seed: 99,
      );

      expect(second.expectedCompletions, first.expectedCompletions);
      expect(second.holdProbability, first.holdProbability);
      expect(
        second.nextMilestone?.probability,
        first.nextMilestone?.probability,
      );
    });
  });

  group('the list', () {
    test('live streaks come first, weakest hold at the top', () {
      final projections = projectHabits(
        <Habit>[
          labHabit(done: (age) => true, id: 'solid'),
          labHabit(done: (age) => age % 4 != 0, id: 'shaky'),
          labHabit(done: (age) => false, id: 'dormant'),
        ],
        reference: labReference,
      );

      expect(projections, hasLength(3));
      expect(projections.first.habitId, 'shaky');
      expect(projections[1].habitId, 'solid');
      // No streak at all, so it sorts below both.
      expect(projections.last.habitId, 'dormant');
    });

    test('archived habits are left out', () {
      final projections = projectHabits(
        <Habit>[
          labHabit(done: (age) => true, id: 'kept'),
          labHabit(done: (age) => true, id: 'gone').copyWith(archived: true),
        ],
        reference: labReference,
      );

      expect(projections, hasLength(1));
      expect(projections.single.habitId, 'kept');
    });

    test('a schedule is honoured when rolling futures forward', () {
      // Three due days a week, so ninety days cannot yield ninety completions.
      final projection = HabitProjection.of(
        labHabit(
          done: (age) => true,
          schedule: const HabitSchedule.onDays({1, 3, 5}),
        ),
        reference: labReference,
      );

      expect(projection.expectedCompletions, lessThan(45));
      expect(projection.expectedCompletions, greaterThan(30));
    });
  });
}
