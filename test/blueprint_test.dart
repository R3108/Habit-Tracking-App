import 'package:flutter_test/flutter_test.dart';

import 'package:habit_tracker/models/blueprint.dart';
import 'package:habit_tracker/models/daily_signal.dart';
import 'package:habit_tracker/models/habit.dart';

final reference = DateTime(2026, 8, 26);

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

/// Thirty days that went well on the even indices and badly on the odd ones.
DailySignal habitsOutcome([int days = 30]) => signal(
  'habits',
  [for (var i = 0; i < days; i++) i.isEven ? 90 : 40],
  isOutcome: true,
  unit: SignalUnit.percent,
);

/// A driver that is [good] on the days the outcome went well and [poor] on the
/// rest.
DailySignal split(String id, double good, double poor, [int days = 30]) =>
    signal(id, [for (var i = 0; i < days; i++) i.isEven ? good : poor]);

void main() {
  group('building the recipe', () {
    test('profiles what the best days had more of', () {
      final blueprint = DayBlueprint.from([
        habitsOutcome(),
        split('sleep', 480, 380),
      ])!;

      final line = blueprint.lines.single;
      expect(line.signal.id, 'sleep');
      expect(line.higherIsBetter, isTrue);
      expect(line.goodMedian, 480);
      expect(line.poorMedian, 380);
      expect(line.goodDays, 15);
      expect(line.poorDays, 15);
      expect(blueprint.goodOutcome, 90);
      expect(blueprint.poorOutcome, 40);
    });

    test('and what they had less of', () {
      final blueprint = DayBlueprint.from([
        habitsOutcome(),
        split('screen time', 60, 240),
      ])!;

      final line = blueprint.lines.single;
      expect(line.higherIsBetter, isFalse);
      expect(line.target, 'screen time under 60');
    });

    test('aims at the level three quarters of the good days cleared', () {
      // Good days spread from 400 to 540, so the median is 470 and the lower
      // quartile — the number a person could actually promise — is 435.
      final varied = signal('sleep', [
        for (var i = 0; i < 30; i++) i.isEven ? 400 + (i ~/ 2) * 10 : 300,
      ]);

      final line = DayBlueprint.from([habitsOutcome(), varied])!.lines.single;

      expect(line.goodMedian, 470);
      expect(line.threshold, 435);
    });

    test('ranks the sharpest separation first', () {
      final blueprint = DayBlueprint.from([
        habitsOutcome(),
        split('sleep', 480, 380),
        // The same direction, but a gap the signal's own noise nearly swallows.
        signal('water', [
          for (var i = 0; i < 30; i++)
            (i.isEven ? 2200 : 2100) + ((i ~/ 2) % 2) * 200,
        ]),
      ])!;

      expect(blueprint.lines.first.signal.id, 'sleep');
      expect(
        blueprint.lines.first.separation,
        greaterThan(blueprint.lines.last.separation),
      );
    });

    test('respects the limit', () {
      final blueprint = DayBlueprint.from([
        habitsOutcome(),
        for (var i = 0; i < 5; i++) split('driver$i', 100, 20),
      ], limit: 2)!;

      expect(blueprint.lines, hasLength(2));
    });
  });

  group('what it refuses to say', () {
    test('nothing at all without an outcome to sort the days by', () {
      expect(DayBlueprint.from([split('sleep', 480, 380)]), isNull);
    });

    test('nothing until three weeks of days have gone by', () {
      expect(
        DayBlueprint.from([habitsOutcome(14), split('sleep', 480, 380, 14)]),
        isNull,
      );
    });

    test('nothing when the outcome never varies', () {
      final flat = signal(
        'habits',
        [for (var i = 0; i < 30; i++) 100],
        isOutcome: true,
      );

      expect(DayBlueprint.from([flat, split('sleep', 480, 380)]), isNull);
    });

    test('leaves out a driver that was the same either way', () {
      final blueprint = DayBlueprint.from([
        habitsOutcome(),
        split('sleep', 480, 380),
        signal('water', [for (var i = 0; i < 30; i++) 2000]),
      ])!;

      expect(blueprint.lines.map((l) => l.signal.id), ['sleep']);
    });

    test('leaves out a driver logged on too few of the good days', () {
      final sparse = DailySignal(
        id: 'sleep',
        label: 'sleep',
        unit: SignalUnit.minutes,
        values: <DateTime, double>{
          // Four good days and four poor ones: not enough either side.
          for (var i = 0; i < 8; i++) addDays(reference, -i): i.isEven ? 480 : 380,
        },
      );

      expect(DayBlueprint.from([habitsOutcome(), sparse]), isNull);
    });

    test('never profiles another outcome, however cleanly it splits', () {
      // Mood is higher on the good days by construction. True, circular, and
      // no use to anybody: nobody can decide to have been in a better mood.
      final mood = signal(
        'mood',
        [for (var i = 0; i < 30; i++) i.isEven ? 5 : 2],
        isOutcome: true,
      );

      expect(DayBlueprint.from([habitsOutcome(), mood]), isNull);
    });

    test('falls back to mood when there are no habits to sort by', () {
      final mood = signal(
        'mood',
        [for (var i = 0; i < 30; i++) i.isEven ? 5 : 2],
        isOutcome: true,
      );

      final blueprint = DayBlueprint.from([mood, split('sleep', 480, 380)])!;
      expect(blueprint.outcome.id, 'mood');
    });
  });

  group('checking a day against it', () {
    test('a day that clears the bar passes, one that does not fails', () {
      final line = DayBlueprint.from([
        habitsOutcome(),
        split('sleep', 480, 380),
      ])!.lines.single;

      expect(line.meets(500), isTrue);
      expect(line.meets(480), isTrue);
      expect(line.meets(420), isFalse);
    });

    test('a day never logged is unknown rather than failed', () {
      final line = DayBlueprint.from([
        habitsOutcome(),
        split('sleep', 480, 380),
      ])!.lines.single;

      expect(line.meets(null), isNull);
    });

    test('a ceiling reads the other way round', () {
      final line = DayBlueprint.from([
        habitsOutcome(),
        split('screen time', 60, 240),
      ])!.lines.single;

      expect(line.meets(30), isTrue);
      expect(line.meets(200), isFalse);
    });
  });
}
