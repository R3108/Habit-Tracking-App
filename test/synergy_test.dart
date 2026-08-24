import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:habit_tracker/models/habit.dart';
import 'package:habit_tracker/models/synergy.dart';

/// A daily habit with a distinct id, done on the listed days-ago.
///
/// Distinct ids matter here in a way they don't elsewhere: the pairing is keyed
/// on them, and two habits sharing an id would compare a habit with itself.
Habit habitWith(
  String id,
  Iterable<int> daysAgo, {
  int ageInDays = 90,
  Iterable<int> daysOff = const <int>[],
}) {
  final today = dateOnly(DateTime.now());
  return Habit(
    id: id,
    title: id,
    icon: Icons.check,
    color: const Color(0xFF000000),
    createdAt: addDays(today, -ageInDays),
    completedDays: daysAgo.map((d) => addDays(today, -d)).toSet(),
    skippedDays: daysOff.map((d) => addDays(today, -d)).toSet(),
  );
}

Iterable<int> evenDays(int upTo) sync* {
  for (var i = 0; i <= upTo; i += 2) {
    yield i;
  }
}

Iterable<int> oddDays(int upTo) sync* {
  for (var i = 1; i <= upTo; i += 2) {
    yield i;
  }
}

void main() {
  group('a measured pair', () {
    test('finds a habit that only happens alongside another', () {
      final run = habitWith('run', evenDays(89));
      final read = habitWith('read', evenDays(89));

      final synergy = HabitSynergy.between(run, read)!;

      expect(synergy.withTriggerPercent, 100);
      expect(synergy.withoutTriggerPercent, 0);
      expect(synergy.isPositive, isTrue);
      expect(synergy.gap, 1.0);
    });

    test('finds a habit that displaces another', () {
      final run = habitWith('run', evenDays(89));
      final read = habitWith('read', oddDays(89));

      final synergy = HabitSynergy.between(run, read)!;

      expect(synergy.isPositive, isFalse);
      expect(synergy.withTriggerPercent, 0);
      expect(synergy.withoutTriggerPercent, 100);
    });

    test('reports nothing when the two are unrelated', () {
      final run = habitWith('run', evenDays(89));
      final read = habitWith('read', List.generate(90, (i) => i));

      expect(HabitSynergy.between(run, read), isNull);
    });

    test('reports nothing for a split too small to matter', () {
      // Reading happens on every run day and on all but a handful of the rest:
      // a real difference, but well under the reporting floor.
      final run = habitWith('run', evenDays(89));
      final read = habitWith(
        'read',
        List.generate(90, (i) => i).where((d) => d.isEven || d > 11),
      );

      expect(HabitSynergy.between(run, read), isNull);
    });

    test('refuses to compare a habit with itself', () {
      final run = habitWith('run', evenDays(89));
      expect(HabitSynergy.between(run, run), isNull);
    });

    test('leaves the lift unstated when the follower never happens alone', () {
      final run = habitWith('run', evenDays(89));
      final read = habitWith('read', evenDays(89));

      expect(HabitSynergy.between(run, read)!.lift, isNull);
    });

    test('states the lift when there is something to divide by', () {
      // Read on every run day, and on a quarter of the others.
      final run = habitWith('run', evenDays(89));
      final read = habitWith(
        'read',
        [...evenDays(89), ...oddDays(89).where((d) => d % 8 == 1)],
      );

      expect(HabitSynergy.between(run, read)!.lift, greaterThan(2));
    });
  });

  group('thin history', () {
    test('a habit with barely any trigger days is not reported', () {
      final run = habitWith('run', [0, 2], ageInDays: 6);
      final read = habitWith('read', [0, 2], ageInDays: 6);

      expect(HabitSynergy.between(run, read), isNull);
    });

    test('a habit almost never missed gives no comparison group', () {
      // 89 run days against one miss: nothing to hold the other pile up.
      final run = habitWith('run', List.generate(90, (i) => i).skip(1));
      final read = habitWith('read', evenDays(89));

      expect(HabitSynergy.between(run, read), isNull);
    });
  });

  group('days off', () {
    test('are excluded from the comparison entirely', () {
      // Reading is skipped on the first ten run days, so those days must not
      // be counted as evidence that running fails to bring reading with it.
      final run = habitWith('run', evenDays(89));
      final read = habitWith(
        'read',
        evenDays(89).where((d) => d > 10),
        daysOff: evenDays(10),
      );

      final synergy = HabitSynergy.between(run, read)!;
      expect(synergy.withTriggerPercent, 100);
    });
  });

  group('findSynergies', () {
    test('keeps one finding per pair, not one per direction', () {
      final run = habitWith('run', evenDays(89));
      final read = habitWith('read', evenDays(89));

      expect(findSynergies([run, read]), hasLength(1));
    });

    test('ranks the most striking split first', () {
      final run = habitWith('run', evenDays(89));
      final read = habitWith('read', evenDays(89));
      // Weakly linked to running: follows it two thirds of the time.
      final stretch = habitWith(
        'stretch',
        evenDays(89).where((d) => d % 6 != 0),
      );

      final found = findSynergies([run, read, stretch]);

      expect(found.first.gap.abs(), greaterThanOrEqualTo(found.last.gap.abs()));
    });

    test('ignores archived habits', () {
      final run = habitWith('run', evenDays(89));
      final read = habitWith('read', evenDays(89)).copyWith(archived: true);

      expect(findSynergies([run, read]), isEmpty);
    });

    test('is empty for a single habit', () {
      expect(findSynergies([habitWith('run', evenDays(89))]), isEmpty);
    });

    test('respects the limit', () {
      final habits = [
        for (var i = 0; i < 5; i++) habitWith('h$i', evenDays(89)),
      ];
      expect(findSynergies(habits, limit: 2), hasLength(2));
    });
  });
}
