import 'package:flutter_test/flutter_test.dart';

import 'package:habit_tracker/models/habit.dart';
import 'package:habit_tracker/models/trackers/check_in_entry.dart';
import 'package:habit_tracker/models/trackers/custom_tracker.dart';

/// A Monday, so weekday grouping is deterministic.
final reference = DateTime(2026, 8, 24);

void main() {
  group('the check-in', () {
    CheckIn entry(int daysAgo, {int mood = 3, int energy = 3}) => CheckIn(
      day: addDays(reference, -daysAgo),
      mood: mood,
      energy: energy,
    );

    Map<DateTime, CheckIn> log(Iterable<CheckIn> entries) => {
      for (final e in entries) e.day: e,
    };

    test('overall averages the two halves', () {
      expect(entry(0, mood: 4, energy: 2).overall, 3);
      expect(entry(0, mood: 5, energy: 4).overall, 4.5);
    });

    test('averages what was logged', () {
      final insights = CheckInInsights.from(
        log([
          entry(0, mood: 5, energy: 3),
          entry(1, mood: 3, energy: 1),
        ]),
        reference: reference,
      );

      expect(insights.daysLogged, 2);
      expect(insights.averageMood, 4);
      expect(insights.averageEnergy, 2);
    });

    test('the streak survives an unlogged today', () {
      final insights = CheckInInsights.from(
        log([entry(1), entry(2), entry(3)]),
        reference: reference,
      );

      expect(insights.streak, 3);
    });

    test('the streak breaks on a missed day', () {
      final insights = CheckInInsights.from(
        log([entry(0), entry(1), entry(3)]),
        reference: reference,
      );

      expect(insights.streak, 2);
    });

    test('the trend compares against the month before', () {
      final insights = CheckInInsights.from(
        log([
          for (var i = 0; i < 30; i++) entry(i, mood: 4),
          for (var i = 30; i < 60; i++) entry(i, mood: 2),
        ]),
        reference: reference,
      );

      expect(insights.moodTrend, 2);
    });

    test('there is no trend without an earlier month', () {
      final insights = CheckInInsights.from(
        log([for (var i = 0; i < 5; i++) entry(i)]),
        reference: reference,
      );

      expect(insights.moodTrend, isNull);
    });

    test('a weekday needs more than one day behind it to be ranked', () {
      // Four days, so four distinct weekdays with one entry each.
      final insights = CheckInInsights.from(
        log([for (var i = 0; i < 4; i++) entry(i, mood: i + 1)]),
        reference: reference,
      );

      expect(insights.bestWeekday, isNull);
      expect(insights.worstWeekday, isNull);
    });

    test('a repeated weekday pattern is ranked', () {
      // Four weeks: Mondays great, everything else poor.
      final entries = <CheckIn>[];
      for (var i = 0; i < 28; i++) {
        final day = addDays(reference, -i);
        entries.add(
          entry(i, mood: day.weekday == DateTime.monday ? 5 : 2),
        );
      }

      final insights = CheckInInsights.from(
        log(entries),
        reference: reference,
      );

      expect(insights.bestWeekday, DateTime.monday);
      expect(insights.worstWeekday, isNot(DateTime.monday));
    });

    test('an empty log makes no claims', () {
      final insights = CheckInInsights.from(const {}, reference: reference);

      expect(insights.hasData, isFalse);
      expect(insights.bestWeekday, isNull);
      expect(insights.streak, 0);
    });

    test('round-trips through JSON', () {
      final original = entry(0, mood: 5, energy: 2);
      final restored = CheckIn.fromJson(original.day, original.toJson())!;

      expect(restored.mood, 5);
      expect(restored.energy, 2);
    });

    test('a value out of range is clamped rather than trusted', () {
      final restored = CheckIn.fromJson(reference, <String, dynamic>{
        'mood': 99,
        'energy': -4,
      })!;

      expect(restored.mood, 5);
      expect(restored.energy, 1);
    });
  });

  group('a custom tracker', () {
    const steps = CustomTracker(
      id: 'steps',
      name: 'Steps',
      kind: CustomTrackerKind.count,
      dailyTarget: 10000,
      step: 1000,
    );

    const coffees = CustomTracker(
      id: 'coffee',
      name: 'Coffees',
      kind: CustomTrackerKind.count,
      dailyTarget: 2,
      lowerIsBetter: true,
    );

    Map<DateTime, double> log(Map<int, double> byDaysAgo) => {
      for (final e in byDaysAgo.entries) addDays(reference, -e.key): e.value,
    };

    test('a floor target is met by going over', () {
      expect(steps.meetsTarget(10000), isTrue);
      expect(steps.meetsTarget(9999), isFalse);
      expect(steps.share(5000), 0.5);
    });

    test('a ceiling target is met by staying under', () {
      expect(coffees.meetsTarget(2), isTrue);
      expect(coffees.meetsTarget(3), isFalse);
      // The bar empties as the number climbs, so full always means "good day".
      expect(coffees.share(0), 1.0);
      expect(coffees.share(1), 0.5);
      expect(coffees.share(4), 0.0);
    });

    test('formatting follows the kind', () {
      const duration = CustomTracker(
        id: 'd',
        name: 'Practice',
        kind: CustomTrackerKind.duration,
      );
      const amount = CustomTracker(
        id: 'a',
        name: 'Run',
        kind: CustomTrackerKind.amount,
        unit: 'km',
      );
      const rating = CustomTracker(
        id: 'r',
        name: 'Focus',
        kind: CustomTrackerKind.scale,
      );

      expect(duration.format(90), '1h 30m');
      expect(amount.format(5.5), '5.5 km');
      expect(rating.format(4), '4/5');
      expect(steps.format(8000), '8000');
    });

    test('a day with no entry is unknown, not a zero', () {
      // Three logged days out of ten: the average is over what exists.
      final insights = CustomTrackerInsights.from(
        steps,
        log({0: 12000, 1: 8000, 2: 10000}),
        reference: reference,
      );

      expect(insights.daysLogged, 3);
      expect(insights.average, 10000);
      expect(insights.total, 30000);
    });

    test('an unlogged day does not score as a perfect ceiling day', () {
      // Nothing logged at all. If absence counted as zero coffees, this would
      // read as a flawless month.
      final insights = CustomTrackerInsights.from(
        coffees,
        const {},
        reference: reference,
      );

      expect(insights.daysLogged, 0);
      expect(insights.streak, 0);
    });

    test('a recorded zero is a good day for a ceiling tracker', () {
      final insights = CustomTrackerInsights.from(
        coffees,
        log({0: 0, 1: 1, 2: 0}),
        reference: reference,
      );

      expect(insights.streak, 3);
      expect(insights.best, 0);
    });

    test('best means lowest when lower is better', () {
      final insights = CustomTrackerInsights.from(
        coffees,
        log({0: 3, 1: 1, 2: 5}),
        reference: reference,
      );

      expect(insights.best, 1);
    });

    test('best means highest otherwise', () {
      final insights = CustomTrackerInsights.from(
        steps,
        log({0: 3000, 1: 14000, 2: 9000}),
        reference: reference,
      );

      expect(insights.best, 14000);
    });

    test('the streak survives an unmet today', () {
      final insights = CustomTrackerInsights.from(
        steps,
        log({0: 200, 1: 12000, 2: 11000}),
        reference: reference,
      );

      expect(insights.streak, 2);
    });

    test('round-trips through JSON', () {
      final restored = CustomTracker.fromJson(coffees.toJson())!;

      expect(restored.id, 'coffee');
      expect(restored.name, 'Coffees');
      expect(restored.lowerIsBetter, isTrue);
      expect(restored.dailyTarget, 2);
    });

    test('an icon dropped from the catalogue falls back rather than throwing', () {
      final restored = CustomTracker.fromJson(<String, dynamic>{
        'id': 'x',
        'name': 'X',
        'iconKey': 'no-such-icon',
      })!;

      expect(restored.icon.codePoint, isNotNull);
    });

    test('a record with no id is dropped rather than given one', () {
      // An invented id would collide with the entry map on the next load.
      expect(CustomTracker.fromJson(<String, dynamic>{'name': 'X'}), isNull);
    });
  });
}
