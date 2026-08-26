import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:habit_tracker/models/habit.dart';
import 'package:habit_tracker/models/lab/capacity.dart';

/// A Wednesday and a Monday, so the "today" the curve reads can be moved
/// between a middling load and the heaviest one.
final wednesday = DateTime(2026, 8, 26);
final monday = DateTime(2026, 8, 31);

/// A habit whose completions are decided by which weekday a day falls on.
///
/// Built here rather than from the shared fixture because these tests care
/// about the *shape of the day* rather than about ages counting back — the
/// whole analysis is a function of how many habits happen to be due together.
Habit loadHabit({
  required String id,
  required HabitSchedule schedule,
  required bool Function(DateTime day) done,
  required DateTime reference,
  int ageInDays = 150,
}) {
  return Habit(
    id: id,
    title: id,
    icon: Icons.check,
    color: const Color(0xFF1565C0),
    schedule: schedule,
    createdAt: addDays(reference, -ageInDays),
    completedDays: <DateTime>{
      for (var age = 1; age <= ageInDays; age++)
        if (schedule.isDueOn(addDays(reference, -age)) &&
            done(addDays(reference, -age)))
          addDays(reference, -age),
    },
  );
}

/// Three load levels with a deliberate peak in the middle.
///
/// - Mon: 8 due, 3 done — the extra habits displace nothing but add nothing.
/// - Tue/Wed: 7 due, 4 done — the best the list ever manages.
/// - Thu–Sun: 3 due, 3 done — clean, but less finished overall.
List<Habit> shapedList(DateTime reference) {
  const midweek = HabitSchedule.onDays({1, 2, 3});
  const mondayOnly = HabitSchedule.onDays({1});

  return <Habit>[
    for (var i = 0; i < 3; i++)
      loadHabit(
        id: 'daily$i',
        schedule: const HabitSchedule.daily(),
        done: (_) => true,
        reference: reference,
      ),
    // The one midweek habit that actually happens, and never on a Monday.
    loadHabit(
      id: 'midweek-kept',
      schedule: midweek,
      done: (day) => day.weekday != DateTime.monday,
      reference: reference,
    ),
    for (var i = 0; i < 3; i++)
      loadHabit(
        id: 'midweek-dropped$i',
        schedule: midweek,
        done: (_) => false,
        reference: reference,
      ),
    loadHabit(
      id: 'monday-only',
      schedule: mondayOnly,
      done: (_) => false,
      reference: reference,
    ),
  ];
}

void main() {
  test('the fixture days are the weekdays the tests assume', () {
    expect(wednesday.weekday, DateTime.wednesday);
    expect(monday.weekday, DateTime.monday);
  });

  group('the curve', () {
    test('reports one point per load level with enough days behind it', () {
      final curve = CapacityCurve.from(
        shapedList(wednesday),
        reference: wednesday,
      );

      expect(curve.hasEnoughHistory, isTrue);
      expect(curve.points.map((p) => p.load), <int>[3, 7, 8]);
      // Lightest first, so the shape reads left to right.
      expect(curve.points.first.load, 3);
      expect(curve.points.last.load, 8);
    });

    test('finds the load that actually finishes the most', () {
      final curve = CapacityCurve.from(
        shapedList(wednesday),
        reference: wednesday,
      );

      expect(curve.bestLoad, 7);
      expect(curve.atBestLoad?.completions, closeTo(4, 0.001));
      // Three habits, all kept: a clean day, but less done than a busy one.
      expect(curve.points.first.completions, closeTo(3, 0.001));
      expect(curve.points.first.percent, 100);
    });

    test('the heaviest days are not the most productive ones', () {
      final curve = CapacityCurve.from(
        shapedList(wednesday),
        reference: wednesday,
      );

      expect(curve.points.last.completions, closeTo(3, 0.001));
      expect(curve.hasHeadroom, isFalse);
    });
  });

  group('the verdict', () {
    test('a day past the peak is called overcommitted', () {
      final curve = CapacityCurve.from(
        shapedList(monday),
        reference: monday,
      );

      expect(curve.currentLoad, 8);
      expect(curve.bestLoad, 7);
      expect(curve.isOvercommitted, isTrue);
      expect(curve.summary, contains('You finish most'));
    });

    test('a day at the peak is not', () {
      final curve = CapacityCurve.from(
        shapedList(wednesday),
        reference: wednesday,
      );

      expect(curve.currentLoad, 7);
      expect(curve.isOvercommitted, isFalse);
    });

    test('the last habit added is shown to be costing completions', () {
      final curve = CapacityCurve.from(
        shapedList(monday),
        reference: monday,
      );

      // Going from seven due to eight loses a completion rather than adding
      // one, which is the finding the whole analysis exists for.
      expect(curve.marginalReturn, closeTo(-1, 0.001));
    });

    test('headroom is reported when completions were still climbing', () {
      // Load rises with the weekday and everything is always kept, so the
      // heaviest day observed is also the most productive.
      final habits = <Habit>[
        for (var i = 1; i <= 5; i++)
          loadHabit(
            id: 'tier$i',
            schedule: HabitSchedule.onDays({for (var d = i; d <= 7; d++) d}),
            done: (_) => true,
            reference: wednesday,
          ),
      ];

      final curve = CapacityCurve.from(habits, reference: wednesday);

      expect(curve.hasEnoughHistory, isTrue);
      expect(curve.hasHeadroom, isTrue);
      expect(curve.isOvercommitted, isFalse);
      expect(curve.summary, contains('no ceiling'));
    });
  });

  group('declining to judge', () {
    test('a list with only one load level says so', () {
      final habits = <Habit>[
        for (var i = 0; i < 3; i++)
          loadHabit(
            id: 'daily$i',
            schedule: const HabitSchedule.daily(),
            done: (_) => true,
            reference: wednesday,
          ),
      ];

      final curve = CapacityCurve.from(habits, reference: wednesday);

      expect(curve.points, hasLength(1));
      expect(curve.hasEnoughHistory, isFalse);
      expect(curve.summary, contains('Not enough variety'));
    });

    test('an empty list has nothing to measure', () {
      final curve = CapacityCurve.from(
        const <Habit>[],
        reference: wednesday,
      );

      expect(curve.points, isEmpty);
      expect(curve.daysObserved, 0);
      expect(curve.currentLoad, 0);
      expect(curve.isOvercommitted, isFalse);
    });

    test('archived habits are not part of the load', () {
      final habits = <Habit>[
        loadHabit(
          id: 'live',
          schedule: const HabitSchedule.daily(),
          done: (_) => true,
          reference: wednesday,
        ),
        loadHabit(
          id: 'archived',
          schedule: const HabitSchedule.daily(),
          done: (_) => true,
          reference: wednesday,
        ).copyWith(archived: true),
      ];

      final curve = CapacityCurve.from(habits, reference: wednesday);

      expect(curve.currentLoad, 1);
      expect(curve.points.single.load, 1);
    });
  });
}
