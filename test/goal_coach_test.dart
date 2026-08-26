import 'package:flutter_test/flutter_test.dart';

import 'package:habit_tracker/models/goal_coach.dart';
import 'package:habit_tracker/models/habit.dart';
import 'package:habit_tracker/models/trackers/custom_tracker.dart';
import 'package:habit_tracker/models/trackers/fitness_entry.dart';
import 'package:habit_tracker/models/trackers/sleep_entry.dart';
import 'package:habit_tracker/models/trackers/tracker_data.dart';
import 'package:habit_tracker/models/trackers/tracker_goals.dart';

final reference = DateTime(2026, 8, 26);

/// [nights] nights of sleep, each of [minutes] measured from a midnight bedtime.
Map<DateTime, SleepEntry> sleepLog(int nights, int Function(int age) minutes) {
  return <DateTime, SleepEntry>{
    for (var age = 1; age <= nights; age++)
      addDays(reference, -age): SleepEntry(
        day: addDays(reference, -age),
        bedMinutes: 0,
        wakeMinutes: minutes(age),
        quality: 3,
      ),
  };
}

Map<DateTime, int> waterLog(int days, int Function(int age) ml) =>
    <DateTime, int>{
      for (var age = 1; age <= days; age++) addDays(reference, -age): ml(age),
    };

GoalSuggestion? only(List<GoalSuggestion> suggestions, String id) {
  for (final suggestion in suggestions) {
    if (suggestion.id == id) return suggestion;
  }
  return null;
}

void main() {
  group('a target out of reach', () {
    test('comes down to what the last month actually managed', () {
      final data = TrackerData(sleep: sleepLog(20, (age) => 400));

      final suggestion = only(
        goalSuggestions(data, reference: reference),
        'sleep',
      )!;

      expect(suggestion.isEasing, isTrue);
      expect(suggestion.headline, 'Ease to 6h 45m');
      expect(suggestion.currentLabel, '8h');
      expect(suggestion.hitPercent, 0);
      expect(suggestion.samples, 20);
      expect(suggestion.rationale, contains('Met on 0 of the last 20 nights'));
    });

    test('and applying it returns the goals with only that changed', () {
      final data = TrackerData(sleep: sleepLog(20, (age) => 400));
      final suggestion =
          only(goalSuggestions(data, reference: reference), 'sleep')!
              as TrackerGoalSuggestion;

      const before = TrackerGoals();
      final after = suggestion.apply(before);

      expect(after.sleepMinutes, 405);
      expect(after.waterMl, before.waterMl);
    });
  });

  group('a target that has stopped asking', () {
    test('goes up', () {
      final data = TrackerData(water: waterLog(20, (age) => 3000));

      final suggestion = only(
        goalSuggestions(data, reference: reference),
        'water',
      )!;

      expect(suggestion.isEasing, isFalse);
      expect(suggestion.headline, 'Raise to 3000 ml');
      expect(suggestion.hitPercent, 100);
      expect(suggestion.rationale, contains('stopped asking'));
    });
  });

  group('a target that is working', () {
    test('is left alone', () {
      // Half the nights over eight hours, half under: exactly what a target is
      // supposed to look like.
      final data = TrackerData(
        sleep: sleepLog(20, (age) => age.isEven ? 500 : 450),
      );

      expect(only(goalSuggestions(data, reference: reference), 'sleep'), isNull);
    });

    test('and so is one with barely any history behind it', () {
      final data = TrackerData(sleep: sleepLog(6, (age) => 400));

      expect(only(goalSuggestions(data, reference: reference), 'sleep'), isNull);
    });

    test('a nudge too small to bother anyone is not offered', () {
      // Missed every night, but by four minutes.
      final data = TrackerData(sleep: sleepLog(20, (age) => 476));

      expect(only(goalSuggestions(data, reference: reference), 'sleep'), isNull);
    });
  });

  group('a ceiling', () {
    test('eases upward, not downward', () {
      const tracker = CustomTracker(
        id: 't1',
        name: 'Coffees',
        kind: CustomTrackerKind.count,
        dailyTarget: 2,
        lowerIsBetter: true,
      );

      final data = TrackerData(
        customTrackers: const [tracker],
        customEntries: {
          't1': {
            for (var age = 1; age <= 20; age++) addDays(reference, -age): 4,
          },
        },
      );

      final suggestion = only(
        goalSuggestions(data, reference: reference),
        'custom:t1',
      )! as CustomGoalSuggestion;

      expect(suggestion.isEasing, isTrue);
      expect(suggestion.proposedTarget, 4);
      expect(suggestion.apply().dailyTarget, 4);
      expect(suggestion.apply().lowerIsBetter, isTrue);
    });

    test('a tracker with no target is a diary, and is left alone', () {
      const tracker = CustomTracker(
        id: 't1',
        name: 'Weight',
        kind: CustomTrackerKind.amount,
        dailyTarget: 0,
      );

      final data = TrackerData(
        customTrackers: const [tracker],
        customEntries: {
          't1': {
            for (var age = 1; age <= 20; age++) addDays(reference, -age): 70,
          },
        },
      );

      expect(
        only(goalSuggestions(data, reference: reference), 'custom:t1'),
        isNull,
      );
    });
  });

  group('the weekly one', () {
    test('is measured in weeks, empty ones included', () {
      final data = TrackerData(
        workouts: <Workout>[
          for (var week = 0; week < 8; week++)
            Workout(
              id: 'w$week',
              day: addDays(reference, -(3 + week * 7)),
              type: WorkoutType.cardio,
              minutes: 60,
            ),
        ],
      );

      final suggestion = only(
        goalSuggestions(data, reference: reference),
        'fitness',
      )!;

      expect(suggestion.isEasing, isTrue);
      expect(suggestion.proposedLabel, '60 a week');
      expect(suggestion.samples, greaterThanOrEqualTo(6));
    });

    test('easy sessions do not count toward it', () {
      final data = TrackerData(
        workouts: <Workout>[
          for (var week = 0; week < 8; week++)
            Workout(
              id: 'w$week',
              day: addDays(reference, -(3 + week * 7)),
              type: WorkoutType.walk,
              minutes: 200,
              intensity: Intensity.easy,
            ),
        ],
      );

      final suggestion = only(
        goalSuggestions(data, reference: reference),
        'fitness',
      );

      // Every week reads as zero active minutes, which is a training problem
      // rather than a target problem — but the target really is out of reach,
      // and the honest floor is the one the clamp allows.
      expect(suggestion?.isEasing, isTrue);
      expect(suggestion?.proposedLabel, '30 a week');
    });
  });

  group('the list', () {
    test('leads with the target that is furthest out', () {
      final data = TrackerData(
        // Never once met.
        sleep: sleepLog(20, (age) => 360),
        // Met on about a quarter of days: wrong, but less wrong.
        water: waterLog(20, (age) => age % 4 == 0 ? 2100 : 1500),
      );

      final suggestions = goalSuggestions(data, reference: reference);

      expect(suggestions.first.id, 'sleep');
      expect(suggestions.map((s) => s.id), contains('water'));
    });

    test('is capped', () {
      final data = TrackerData(
        sleep: sleepLog(20, (age) => 360),
        water: waterLog(20, (age) => 500),
      );

      expect(goalSuggestions(data, reference: reference, limit: 1), hasLength(1));
    });

    test('an empty app has nothing to tune', () {
      expect(goalSuggestions(const TrackerData(), reference: reference), isEmpty);
    });
  });
}
