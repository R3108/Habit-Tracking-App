import 'package:flutter_test/flutter_test.dart';

import 'package:habit_tracker/models/habit.dart';
import 'package:habit_tracker/models/momentum.dart';

import 'habit_test.dart' show habitDoneOn;

/// Every day from [from] days ago up to [to] days ago, inclusive.
List<int> range(int from, int to) => [
  for (var i = from; i <= to; i++) i,
];

void main() {
  final today = dateOnly(DateTime.now());

  group('score', () {
    // These fixtures pin createdAt to the first completion: the default backdates
    // it 400 days, which would put a stretch of untouched due days inside the
    // 60-day window and make a "perfect" record score less than 100.
    test('a perfect record scores 100%', () {
      final habit = habitDoneOn(range(0, 40), createdAt: addDays(today, -40));
      expect(HabitMomentum.of(habit).percent, 100);
    });

    test('an empty record scores 0%', () {
      expect(HabitMomentum.of(habitDoneOn([])).percent, 0);
    });

    test('recent days count for more than old ones', () {
      // Same number of completions either way; only their position differs.
      final recent = HabitMomentum.of(habitDoneOn(range(0, 13)));
      final old = HabitMomentum.of(habitDoneOn(range(26, 39)));

      expect(recent.score, greaterThan(old.score));
    });

    test('it is measured against due days, not calendar days', () {
      // Due on one weekday only, and every one of those was done.
      final weekday = today.weekday;
      final habit = habitDoneOn(
        [0, 7, 14, 21, 28, 35],
        schedule: HabitSchedule.onDays({weekday}),
        createdAt: addDays(today, -35),
      );

      expect(HabitMomentum.of(habit).percent, 100);
    });

    test('days planned off are invisible to it', () {
      var habit = habitDoneOn(range(3, 40), createdAt: addDays(today, -40));
      for (final day in range(0, 2)) {
        habit = habit.setSkipped(addDays(today, -day), true);
      }

      expect(HabitMomentum.of(habit).percent, 100);
    });
  });

  group('evidence', () {
    test('a brand-new habit has none, so it makes no claims', () {
      final habit = habitDoneOn([], createdAt: today);
      final momentum = HabitMomentum.of(habit);

      expect(momentum.hasEnoughHistory, isFalse);
      expect(momentum.trend, MomentumTrend.steady);
      expect(momentum.risk, HabitRisk.none);
    });

    test('a habit with a few weeks behind it has plenty', () {
      expect(HabitMomentum.of(habitDoneOn(range(0, 20))).hasEnoughHistory, isTrue);
    });
  });

  group('trend', () {
    test('rises when a bad run is followed by a good one', () {
      // Nothing for the older fortnight, everything for the recent one.
      final habit = habitDoneOn(range(0, 9), createdAt: addDays(today, -30));
      final momentum = HabitMomentum.of(habit);

      expect(momentum.trend, MomentumTrend.rising);
      expect(momentum.delta, greaterThan(0));
    });

    test('falls when a good run stops', () {
      final habit = habitDoneOn(range(8, 30));
      final momentum = HabitMomentum.of(habit);

      expect(momentum.trend, MomentumTrend.falling);
      expect(momentum.delta, lessThan(0));
    });

    test('holds steady when nothing changes', () {
      expect(
        HabitMomentum.of(habitDoneOn(range(0, 40))).trend,
        MomentumTrend.steady,
      );
    });
  });

  group('risk', () {
    test('a live streak on an unticked due day is flagged', () {
      // Done for the last four days but not today, so the streak is alive and
      // today is still in play.
      final momentum = HabitMomentum.of(habitDoneOn(range(1, 20)));

      expect(momentum.risk, HabitRisk.atRisk);
      expect(momentum.reason, contains('on the line'));
    });

    test('the same habit is clear once today is ticked', () {
      expect(HabitMomentum.of(habitDoneOn(range(0, 20))).risk, HabitRisk.none);
    });

    test('a habit with nothing to lose today is not urgent', () {
      // Two days is not yet a streak worth protecting.
      final momentum = HabitMomentum.of(
        habitDoneOn([1, 2], createdAt: addDays(today, -3)),
      );
      expect(momentum.risk, isNot(HabitRisk.atRisk));
    });

    test('a habit that is quietly slipping is put on watch', () {
      final momentum = HabitMomentum.of(habitDoneOn(range(10, 40)));

      expect(momentum.risk, HabitRisk.watch);
      expect(momentum.reason, isNotNull);
    });

    test('a habit going well is not flagged at all', () {
      final momentum = HabitMomentum.of(habitDoneOn(range(0, 40)));

      expect(momentum.risk, HabitRisk.none);
      expect(momentum.reason, isNull);
    });
  });

  group('the focus list', () {
    test('holds only flagged habits', () {
      final good = habitDoneOn(range(0, 40));
      final bad = habitDoneOn(range(12, 40));

      final focus = focusList([good, bad]);

      expect(focus, hasLength(1));
      expect(focus.first.habitId, bad.id);
    });

    test('puts a streak on the line above a slow decline', () {
      final slipping = habitDoneOn(range(12, 40));
      final urgent = habitDoneOn(range(1, 40));

      final focus = focusList([slipping, urgent]);

      expect(focus.first.risk, HabitRisk.atRisk);
    });

    test('is capped so it stays a summary', () {
      final habits = [
        for (var i = 0; i < 6; i++) habitDoneOn(range(12, 40)),
      ];
      expect(focusList(habits), hasLength(3));
    });

    test('is empty when everything is going fine', () {
      expect(focusList([habitDoneOn(range(0, 40))]), isEmpty);
    });
  });
}
