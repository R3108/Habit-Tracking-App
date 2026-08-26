import 'package:flutter_test/flutter_test.dart';

import 'package:habit_tracker/models/habit.dart';
import 'package:habit_tracker/models/lab/turning_point.dart';

import 'lab_fixtures.dart';

void main() {
  group('finding a change', () {
    test('a habit that collapsed is caught, on roughly the right day', () {
      // Perfect until 60 days ago, nothing since.
      final points = findTurningPoints(
        labHabit(done: (age) => age > 60, ageInDays: 180),
        reference: labReference,
      );

      expect(points, isNotEmpty);
      final first = points.first;
      expect(first.isImprovement, isFalse);
      expect(first.beforeRate, greaterThan(0.9));
      expect(first.afterRate, lessThan(0.1));

      // Within a few days of the real switch. Exactness is not the claim —
      // the detector reports where the level changed, not when the user
      // decided it would.
      final expected = addDays(labReference, -60);
      expect(first.day.difference(expected).inDays.abs(), lessThanOrEqualTo(3));
    });

    test('a partial drop is caught too', () {
      // ~90% for the first stretch, ~40% since.
      final points = findTurningPoints(
        labHabit(
          done: (age) => age > 70 ? age % 10 != 0 : age % 5 < 2,
          ageInDays: 180,
        ),
        reference: labReference,
      );

      expect(points, isNotEmpty);
      expect(points.first.isImprovement, isFalse);
      expect(points.first.swing, greaterThan(20));
    });

    test('an improvement reads as one', () {
      // Poor at first, then near-perfect.
      final points = findTurningPoints(
        labHabit(done: (age) => age <= 70, ageInDays: 180),
        reference: labReference,
      );

      expect(points, isNotEmpty);
      expect(points.first.isImprovement, isTrue);
      expect(points.first.description, startsWith('Picked up'));
    });
  });

  group('declining to find one', () {
    test('a steady habit has no turning points', () {
      // 70%, evenly spread, for the whole window.
      final points = findTurningPoints(
        labHabit(done: (age) => age % 10 < 7, ageInDays: 180),
        reference: labReference,
      );

      expect(points, isEmpty);
    });

    test('a habit kept throughout has none either', () {
      expect(
        findTurningPoints(
          labHabit(done: (age) => true, ageInDays: 180),
          reference: labReference,
        ),
        isEmpty,
      );
    });

    test('a five-day dip is a dip, not a new level', () {
      final points = findTurningPoints(
        labHabit(
          done: (age) => age < 30 || age > 34,
          ageInDays: 180,
        ),
        reference: labReference,
      );

      expect(points, isEmpty);
    });

    test('too little history to have a level at all', () {
      expect(
        findTurningPoints(
          labHabit(done: (age) => age > 8, ageInDays: 16),
          reference: labReference,
        ),
        isEmpty,
      );
    });
  });

  group('across the list', () {
    test('recent shifts are reported, newest first', () {
      final found = findRecentTurningPoints(
        <Habit>[
          labHabit(done: (age) => age > 30, ageInDays: 180, id: 'recent'),
          labHabit(done: (age) => age > 90, ageInDays: 180, id: 'older'),
        ],
        reference: labReference,
      );

      expect(found, hasLength(2));
      expect(found.first.habit.id, 'recent');
      expect(found.first.point.day.isAfter(found.last.point.day), isTrue);
    });

    test('a shift from a year ago is history, not news', () {
      final found = findRecentTurningPoints(
        <Habit>[
          labHabit(done: (age) => age > 250, ageInDays: 340, id: 'ancient'),
        ],
        reference: labReference,
        withinDays: 120,
      );

      expect(found, isEmpty);
    });

    test('archived habits are skipped', () {
      final found = findRecentTurningPoints(
        <Habit>[
          labHabit(
            done: (age) => age > 40,
            ageInDays: 180,
            id: 'gone',
          ).copyWith(archived: true),
        ],
        reference: labReference,
      );

      expect(found, isEmpty);
    });
  });
}
