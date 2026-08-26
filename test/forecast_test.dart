import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:habit_tracker/models/forecast.dart';
import 'package:habit_tracker/models/habit.dart';

final reference = DateTime(2026, 8, 26);

/// A habit alive for [ageInDays], completed on whichever ages [done] says.
///
/// Ages count back from [reference]: 0 is the day being forecast, 1 is the last
/// day before it.
Habit habit({
  required bool Function(int age) done,
  int ageInDays = 200,
  HabitSchedule schedule = const HabitSchedule.daily(),
  String id = 'h',
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
        if (done(age)) addDays(reference, -age),
    },
  );
}

void main() {
  group('the base rate', () {
    test('a habit kept every day is very likely, but never certain', () {
      final forecast = HabitForecast.of(
        habit(done: (age) => true),
        reference: reference,
      );

      expect(forecast.probability, greaterThan(0.9));
      expect(forecast.probability, lessThan(1.0));
      expect(forecast.outlook, 'Very likely');
      expect(forecast.hasEnoughHistory, isTrue);
    });

    test('a habit never kept is a long shot, but never impossible', () {
      final forecast = HabitForecast.of(
        habit(done: (age) => false),
        reference: reference,
      );

      expect(forecast.probability, lessThan(0.15));
      expect(forecast.probability, greaterThan(0.0));
    });

    test('a habit with a few days behind it admits it is guessing', () {
      final forecast = HabitForecast.of(
        habit(done: (age) => true, ageInDays: 3),
        reference: reference,
      );

      expect(forecast.hasEnoughHistory, isFalse);
      // The prior has not washed out yet, so the answer is near a coin flip.
      expect(forecast.probability, lessThan(0.85));
    });

    test('weights recent days far above old ones', () {
      // Kept solidly for months, then dropped for the last fortnight.
      final collapsing = HabitForecast.of(
        habit(done: (age) => age > 14),
        reference: reference,
      );
      // The same total, the other way round.
      final recovering = HabitForecast.of(
        habit(done: (age) => age <= 14),
        reference: reference,
      );

      expect(collapsing.probability, lessThan(recovering.probability));
    });
  });

  group('the weekday factor', () {
    test('a weekday that never happens drags the day down', () {
      final skipsToday = habit(
        done: (age) => addDays(reference, -age).weekday != reference.weekday,
      );

      final forecast = HabitForecast.of(skipsToday, reference: reference);
      final factor = forecast.dominant!;

      expect(factor.rate, 0);
      expect(factor.isHelping, isFalse);
      // A 120-day window holds seventeen of any given weekday.
      expect(factor.days, 17);
      expect(forecast.probability, lessThan(0.5));
      // The base rate alone would have called this a good bet.
      expect(forecast.baseRate, greaterThan(0.8));
    });

    test('one thin weekday is not allowed to speak', () {
      // Three weeks old: the same never-on-this-weekday pattern, but only two
      // of that weekday have come round.
      final young = habit(
        ageInDays: 20,
        done: (age) => addDays(reference, -age).weekday != reference.weekday,
      );

      final factor = HabitForecast.of(young, reference: reference).dominant;
      expect(factor, isNull);
    });

    test('a weekday that behaves like the rest is left unmentioned', () {
      final steady = habit(done: (age) => age.isOdd);

      final forecast = HabitForecast.of(steady, reference: reference);
      expect(
        forecast.factors.where((f) => f.label.endsWith('s')).where(
          (f) => f.label != 'After a missed day' &&
              f.label != 'After a day you kept it',
        ),
        isEmpty,
      );
    });
  });

  group('the carry-over factor', () {
    // Ten kept days, then five missed, repeating: a miss means the run has
    // ended rather than that one day went wrong.
    bool domino(int age) => (age ~/ 5) % 3 != 2;

    test('reads a missed yesterday as the start of a slide', () {
      // Age 1 falls in a missed block, so yesterday was a miss.
      final slipping = habit(done: (age) => !domino(age));
      final forecast = HabitForecast.of(slipping, reference: reference);

      final factor = forecast.factors.firstWhere(
        (f) => f.label == 'After a missed day',
      );
      expect(factor.isHelping, isFalse);
    });

    test('and a kept yesterday as the run continuing', () {
      final running = habit(done: domino);
      final forecast = HabitForecast.of(running, reference: reference);

      final factor = forecast.factors.firstWhere(
        (f) => f.label == 'After a day you kept it',
      );
      expect(factor.isHelping, isTrue);
    });
  });

  group('the anchor factor', () {
    test('counts only once the cue has actually fired', () {
      final anchor = habit(id: 'anchor', done: (age) => age.isEven);
      // Follows the anchor almost every time it happens.
      final follower = habit(
        id: 'follower',
        done: (age) => age.isEven && age % 6 != 0,
      );

      final withCue = HabitForecast.of(
        follower,
        reference: reference,
        anchor: anchor.toggle(reference),
      );
      final withoutCue = HabitForecast.of(
        follower,
        reference: reference,
        anchor: anchor,
      );

      expect(withCue.factors.map((f) => f.label), contains('After "anchor"'));
      // An unticked anchor says nothing: the day is not over.
      expect(withoutCue.factors.map((f) => f.label), isNot(contains('After "anchor"')));
      expect(withCue.probability, greaterThan(withoutCue.probability));
    });
  });

  group('days that need no forecast', () {
    test('a habit already done today is a fact, not a prediction', () {
      final done = habit(done: (age) => true).toggle(reference);
      final forecast = HabitForecast.of(done, reference: reference);

      expect(forecast.doneToday, isTrue);
      expect(forecast.probability, 1);
      expect(forecast.factors, isEmpty);
    });

    test('a habit not due today is left alone', () {
      final weekend = habit(
        done: (age) => true,
        schedule: HabitSchedule.onDays({
          reference.weekday == 7 ? 1 : reference.weekday + 1,
        }),
      );

      final forecast = HabitForecast.of(weekend, reference: reference);
      expect(forecast.dueToday, isFalse);
      expect(forecast.factors, isEmpty);
    });
  });

  group('the day as a whole', () {
    test('expects the sum of the parts', () {
      final forecast = DayForecast.build([
        habit(id: 'certain', done: (age) => true),
        habit(id: 'never', done: (age) => false),
      ], reference: reference);

      expect(forecast.due, 2);
      expect(forecast.done, 0);
      expect(forecast.expected, greaterThan(0.9));
      expect(forecast.expected, lessThan(1.2));
      expect(forecast.expectedRounded, 1);
    });

    test('counts a day already ticked as the certainty it is', () {
      final forecast = DayForecast.build([
        habit(id: 'done', done: (age) => true).toggle(reference),
        habit(id: 'never', done: (age) => false),
      ], reference: reference);

      expect(forecast.done, 1);
      expect(forecast.remaining, hasLength(1));
      expect(forecast.remaining.single.habitId, 'never');
    });

    test('puts the one most likely to get away first', () {
      final forecast = DayForecast.build([
        habit(id: 'safe', done: (age) => true),
        habit(id: 'shaky', done: (age) => age % 3 == 0),
      ], reference: reference);

      expect(forecast.forecasts.first.habitId, 'shaky');
      expect(forecast.weakest?.habitId, 'shaky');
    });

    test('names nothing as weakest when everything looks safe', () {
      final forecast = DayForecast.build([
        habit(id: 'a', done: (age) => true),
        habit(id: 'b', done: (age) => true),
      ], reference: reference);

      expect(forecast.weakest, isNull);
    });

    test('says it is still learning on a young list', () {
      final forecast = DayForecast.build([
        habit(id: 'a', ageInDays: 2, done: (age) => true),
        habit(id: 'b', ageInDays: 2, done: (age) => true),
      ], reference: reference);

      expect(forecast.isReliable, isFalse);
    });

    test('an empty day forecasts nothing', () {
      final forecast = DayForecast.build(const [], reference: reference);
      expect(forecast.isEmpty, isTrue);
      expect(forecast.isReliable, isTrue);
    });
  });
}
