import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:habit_tracker/models/daily_signal.dart';
import 'package:habit_tracker/models/discovery.dart';
import 'package:habit_tracker/models/habit.dart';
import 'package:habit_tracker/models/trackers/check_in_entry.dart';
import 'package:habit_tracker/models/trackers/custom_tracker.dart';
import 'package:habit_tracker/models/trackers/fitness_entry.dart';
import 'package:habit_tracker/models/trackers/tracker_data.dart';

final reference = DateTime(2026, 8, 24);

/// A signal whose values run backwards from [reference]: index 0 is today.
DailySignal signal(
  String id,
  List<double> values, {
  bool isOutcome = false,
  SignalUnit unit = SignalUnit.count,
}) {
  return DailySignal(
    id: id,
    label: id,
    unit: unit,
    isOutcome: isOutcome,
    values: <DateTime, double>{
      for (var i = 0; i < values.length; i++)
        addDays(reference, -i): values[i],
    },
  );
}

/// Alternating low/high, for a driver with a clean median split.
List<double> alternating(int days, double low, double high) =>
    [for (var i = 0; i < days; i++) i.isEven ? high : low];

void main() {
  group('a single comparison', () {
    test('finds a clear difference between the two halves', () {
      final driver = signal('sleep', alternating(20, 1, 10));
      // Better on the driver's high days, which are the even indices.
      final outcome = signal(
        'habits',
        [for (var i = 0; i < 20; i++) i.isEven ? 90 : 50],
        isOutcome: true,
      );

      final found = Discovery.between(driver, outcome)!;

      expect(found.highMean, 90);
      expect(found.lowMean, 50);
      expect(found.highDays, 10);
      expect(found.lowDays, 10);
      expect(found.isPositive, isTrue);
      expect(found.effect, greaterThan(1.2));
      expect(found.strength, 'Strong');
    });

    test('reports a difference the other way as negative', () {
      final driver = signal('screen time', alternating(20, 1, 10));
      final outcome = signal(
        'mood',
        [for (var i = 0; i < 20; i++) i.isEven ? 2 : 5],
        isOutcome: true,
      );

      final found = Discovery.between(driver, outcome)!;

      expect(found.isPositive, isFalse);
      expect(found.difference, -3);
    });

    test('says nothing when the two are unrelated', () {
      // The outcome drifts steadily while the driver alternates, so the split
      // separates almost nothing.
      final driver = signal('water', alternating(20, 1, 10));
      final outcome = signal(
        'mood',
        [for (var i = 0; i < 20; i++) i.toDouble()],
        isOutcome: true,
      );

      expect(Discovery.between(driver, outcome), isNull);
    });

    test('refuses a pair with too few shared days', () {
      final driver = signal('sleep', alternating(10, 1, 10));
      final outcome = signal('mood', alternating(10, 2, 5), isOutcome: true);

      expect(Discovery.between(driver, outcome), isNull);
    });

    test('refuses a driver that never varies', () {
      // Ties fall on the low side, so a flat driver leaves the high half empty
      // rather than splitting arbitrarily.
      final driver = signal('water', [for (var i = 0; i < 20; i++) 2000]);
      final outcome = signal('mood', alternating(20, 2, 5), isOutcome: true);

      expect(Discovery.between(driver, outcome), isNull);
    });

    test('refuses a flat outcome rather than dividing by its spread', () {
      final driver = signal('sleep', alternating(20, 1, 10));
      final outcome = signal('mood', [for (var i = 0; i < 20; i++) 3]);

      expect(Discovery.between(driver, outcome), isNull);
    });

    test('refuses a difference too small to matter', () {
      final driver = signal('sleep', alternating(20, 1, 10));
      // A tenth of a point apart against a wide spread.
      final outcome = signal('mood', [
        for (var i = 0; i < 20; i++) (i.isEven ? 3.1 : 3.0) + (i % 5),
      ]);

      expect(Discovery.between(driver, outcome), isNull);
    });

    test('compares only the days both signals recorded', () {
      final driver = signal('sleep', alternating(30, 1, 10));
      // Half as many days: the comparison must use the 16 that overlap.
      final outcome = DailySignal(
        id: 'mood',
        label: 'mood',
        unit: SignalUnit.score,
        isOutcome: true,
        values: <DateTime, double>{
          for (var i = 0; i < 16; i++)
            addDays(reference, -i): i.isEven ? 5 : 2,
        },
      );

      final found = Discovery.between(driver, outcome)!;
      expect(found.days, 16);
    });

    test('a signal is never compared with itself', () {
      final only = signal('sleep', alternating(20, 1, 10));
      expect(Discovery.between(only, only), isNull);
    });
  });

  group('the search', () {
    test('keeps one finding per pair, not one per direction', () {
      final sleep = signal('sleep', alternating(20, 1, 10));
      final mood = signal(
        'mood',
        [for (var i = 0; i < 20; i++) i.isEven ? 5 : 2],
        isOutcome: true,
      );

      expect(findDiscoveries([sleep, mood]), hasLength(1));
    });

    test('puts the thing you want to move on the outcome side', () {
      final sleep = signal('sleep', alternating(20, 1, 10));
      final mood = signal(
        'mood',
        [for (var i = 0; i < 20; i++) i.isEven ? 5 : 2],
        isOutcome: true,
      );

      final found = findDiscoveries([sleep, mood]).single;

      expect(found.driver.id, 'sleep');
      expect(found.outcome.id, 'mood');
    });

    test('ranks the biggest effect first', () {
      final driver = signal('sleep', alternating(20, 1, 10));
      final strong = signal(
        'mood',
        [for (var i = 0; i < 20; i++) i.isEven ? 5 : 1],
        isOutcome: true,
      );
      final weaker = signal(
        'habits',
        [for (var i = 0; i < 20; i++) (i.isEven ? 70 : 50) + (i % 3) * 5],
        isOutcome: true,
      );

      final found = findDiscoveries([driver, strong, weaker]);

      expect(found.length, greaterThanOrEqualTo(2));
      expect(
        found.first.effect.abs(),
        greaterThanOrEqualTo(found.last.effect.abs()),
      );
    });

    test('respects the limit', () {
      final signals = [
        for (var i = 0; i < 6; i++)
          signal('s$i', [for (var d = 0; d < 20; d++) d.isEven ? 10 : 1]),
      ];

      expect(findDiscoveries(signals, limit: 2), hasLength(2));
    });

    test('finds nothing in an empty app', () {
      expect(findDiscoveries(const []), isEmpty);
    });
  });

  group('building signals', () {
    test('a day never logged is absent, not zero', () {
      final trackers = TrackerData(
        water: {reference: 2000, addDays(reference, -2): 1500},
      );

      final signals = buildSignals(
        habits: const [],
        trackers: trackers,
        reference: reference,
        minimumDays: 1,
      );
      final water = signals.firstWhere((s) => s.id == 'water');

      expect(water.days, 2);
      expect(water.values.containsKey(addDays(reference, -1)), isFalse);
    });

    test('a tracker with barely any history is left out entirely', () {
      final trackers = TrackerData(water: {reference: 2000});

      final signals = buildSignals(
        habits: const [],
        trackers: trackers,
        reference: reference,
      );

      expect(signals.where((s) => s.id == 'water'), isEmpty);
    });

    test('sessions on the same day are summed', () {
      final trackers = TrackerData(
        workouts: [
          for (var i = 0; i < 8; i++)
            Workout(
              id: 'a$i',
              day: addDays(reference, -i),
              type: WorkoutType.cardio,
              minutes: 30,
            ),
          Workout(
            id: 'extra',
            day: reference,
            type: WorkoutType.strength,
            minutes: 20,
          ),
        ],
      );

      final signals = buildSignals(
        habits: const [],
        trackers: trackers,
        reference: reference,
      );
      final fitness = signals.firstWhere((s) => s.id == 'fitness');

      expect(fitness.values[reference], 50);
      expect(fitness.days, 8);
    });

    test('mood and energy are separate signals, both outcomes', () {
      final trackers = TrackerData(
        checkIns: {
          for (var i = 0; i < 10; i++)
            addDays(reference, -i): CheckIn(
              day: addDays(reference, -i),
              mood: 4,
              energy: 2,
            ),
        },
      );

      final signals = buildSignals(
        habits: const [],
        trackers: trackers,
        reference: reference,
      );

      final mood = signals.firstWhere((s) => s.id == 'mood');
      final energy = signals.firstWhere((s) => s.id == 'energy');

      expect(mood.values[reference], 4);
      expect(energy.values[reference], 2);
      expect(mood.isOutcome, isTrue);
      expect(energy.isOutcome, isTrue);
    });

    test('a custom tracker becomes a signal of its own', () {
      const tracker = CustomTracker(
        id: 't1',
        name: 'Steps',
        kind: CustomTrackerKind.count,
        dailyTarget: 10000,
      );
      final trackers = TrackerData(
        customTrackers: const [tracker],
        customEntries: {
          't1': {
            for (var i = 0; i < 10; i++) addDays(reference, -i): 8000 + i * 100,
          },
        },
      );

      final signals = buildSignals(
        habits: const [],
        trackers: trackers,
        reference: reference,
      );
      final steps = signals.firstWhere((s) => s.id == 'custom:t1');

      expect(steps.label, 'Steps');
      expect(steps.days, 10);
    });

    test('an archived custom tracker is left out', () {
      const tracker = CustomTracker(
        id: 't1',
        name: 'Steps',
        kind: CustomTrackerKind.count,
        archived: true,
      );
      final trackers = TrackerData(
        customTrackers: const [tracker],
        customEntries: {
          't1': {
            for (var i = 0; i < 10; i++) addDays(reference, -i): 8000,
          },
        },
      );

      final signals = buildSignals(
        habits: const [],
        trackers: trackers,
        reference: reference,
      );

      expect(signals.where((s) => s.id == 'custom:t1'), isEmpty);
    });

    test('habits become a percentage-kept signal marked as an outcome', () {
      final habit = Habit(
        id: 'read',
        title: 'Read',
        icon: Icons.check,
        color: const Color(0xFF000000),
        createdAt: addDays(reference, -20),
        completedDays: {
          for (var i = 0; i < 20; i += 2) addDays(reference, -i),
        },
      );

      final signals = buildSignals(
        habits: [habit],
        trackers: const TrackerData(),
        reference: reference,
      );
      final habits = signals.firstWhere((s) => s.id == 'habits');

      expect(habits.isOutcome, isTrue);
      expect(habits.values[reference], 100);
      expect(habits.values[addDays(reference, -1)], 0);
    });
  });

  group('formatting', () {
    test('each unit reads the way its tracker would write it', () {
      expect(signal('a', const [90], unit: SignalUnit.minutes).format(90), '1h 30m');
      expect(
        signal('a', const [1], unit: SignalUnit.millilitres).format(1500),
        '1500 ml',
      );
      expect(signal('a', const [1], unit: SignalUnit.score).format(4.5), '4.5/5');
      expect(signal('a', const [1], unit: SignalUnit.percent).format(82.4), '82%');
      expect(signal('a', const [1], unit: SignalUnit.count).format(12), '12');
    });
  });
}
