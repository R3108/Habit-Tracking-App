import 'package:flutter_test/flutter_test.dart';

import 'package:habit_tracker/models/habit.dart';
import 'package:habit_tracker/models/trackers/fitness_entry.dart';
import 'package:habit_tracker/models/trackers/focus_entry.dart';
import 'package:habit_tracker/models/trackers/food_entry.dart';
import 'package:habit_tracker/models/trackers/reading_entry.dart';
import 'package:habit_tracker/models/trackers/sleep_entry.dart';
import 'package:habit_tracker/models/trackers/tracker_goals.dart';
import 'package:habit_tracker/models/trackers/water_entry.dart';

/// A Monday, so the weekday/weekend split in the sleep tests is deterministic.
/// The 14-night window ending here holds exactly four weekend mornings.
final reference = DateTime(2026, 8, 24);

const goals = TrackerGoals();

void main() {
  group('sleep', () {
    SleepEntry night(int daysAgo, {int bed = 23 * 60, int wake = 7 * 60, int quality = 3}) =>
        SleepEntry(
          day: addDays(reference, -daysAgo),
          bedMinutes: bed,
          wakeMinutes: wake,
          quality: quality,
        );

    Map<DateTime, SleepEntry> log(Iterable<SleepEntry> entries) => {
      for (final entry in entries) entry.day: entry,
    };

    test('a night that crosses midnight is not negative', () {
      expect(night(0, bed: 23 * 60, wake: 7 * 60).durationMinutes, 480);
    });

    test('a night entirely after midnight measures normally', () {
      expect(night(0, bed: 60, wake: 9 * 60).durationMinutes, 480);
    });

    test('bedtimes either side of midnight sort onto one scale', () {
      // 23:50 and 00:10 are twenty minutes apart, not twenty-three hours.
      final late = night(0, bed: 23 * 60 + 50).nightBedMinutes;
      final later = night(1, bed: 10).nightBedMinutes;
      expect((later - late).abs(), 20);
    });

    test('debt counts only the nights that fell short', () {
      // Two hours short, then two hours long: the surplus does not repay it.
      final insights = SleepInsights.from(
        log([
          night(0, bed: 23 * 60, wake: 5 * 60),
          night(1, bed: 22 * 60, wake: 8 * 60),
        ]),
        goals: goals,
        reference: reference,
      );

      expect(insights.debtMinutes, 120);
    });

    test('an identical bedtime every night scores full consistency', () {
      final insights = SleepInsights.from(
        log([for (var i = 0; i < 7; i++) night(i)]),
        goals: goals,
        reference: reference,
      );

      expect(insights.consistencyScore, 100);
      expect(insights.averageMinutes, 480);
      expect(insights.goalNights, 7);
    });

    test('a bedtime that swings two hours scores nothing', () {
      final insights = SleepInsights.from(
        log([
          for (var i = 0; i < 8; i++)
            night(i, bed: i.isEven ? 21 * 60 : 25 * 60 % 1440),
        ]),
        goals: goals,
        reference: reference,
      );

      expect(insights.consistencyScore, 0);
    });

    test('two nights are too few to grade regularity', () {
      final insights = SleepInsights.from(
        log([night(0), night(1)]),
        goals: goals,
        reference: reference,
      );

      expect(insights.consistencyScore, 0);
      expect(insights.nights, 2);
    });

    test('a later weekend shows up as body-clock drift', () {
      final entries = <SleepEntry>[];
      for (var i = 0; i < 14; i++) {
        final day = addDays(reference, -i);
        final isFree =
            day.weekday == DateTime.saturday || day.weekday == DateTime.sunday;
        entries.add(
          night(
            i,
            // Two hours later to bed and two hours later up at weekends.
            bed: isFree ? 25 * 60 % 1440 : 23 * 60,
            wake: isFree ? 9 * 60 : 7 * 60,
          ),
        );
      }

      final insights = SleepInsights.from(
        log(entries),
        goals: goals,
        reference: reference,
      );

      expect(insights.socialJetlagMinutes, 120);
    });

    test('a week of identical nights shows no drift', () {
      final insights = SleepInsights.from(
        log([for (var i = 0; i < 14; i++) night(i)]),
        goals: goals,
        reference: reference,
      );

      expect(insights.socialJetlagMinutes, 0);
    });

    test('drift is not reported without both kinds of night', () {
      // Three weekdays only.
      final insights = SleepInsights.from(
        log([night(2), night(3), night(4)]),
        goals: goals,
        reference: reference,
      );

      expect(insights.socialJetlagMinutes, isNull);
    });

    test('an empty log reports nothing rather than zeroes with meaning', () {
      final insights = SleepInsights.from(
        const {},
        goals: goals,
        reference: reference,
      );

      expect(insights.hasData, isFalse);
      expect(insights.nights, 0);
    });
  });

  group('water', () {
    Map<DateTime, int> log(Map<int, int> byDaysAgo) => {
      for (final entry in byDaysAgo.entries)
        addDays(reference, -entry.key): entry.value,
    };

    test('pace is measured against the waking day, not midnight', () {
      // 15:00 is half way between 07:00 and 23:00.
      final insights = WaterInsights.from(
        log({0: 1000}),
        goals: goals,
        reference: DateTime(2026, 8, 24, 15),
      );

      expect(insights.expectedByNow, 1000);
      expect(insights.paceDifference, 0);
    });

    test('early morning is too early to judge', () {
      final insights = WaterInsights.from(
        log({0: 0}),
        goals: goals,
        reference: DateTime(2026, 8, 24, 6),
      );

      expect(insights.isTooEarlyToJudge, isTrue);
    });

    test('being behind is reported as a negative difference', () {
      final insights = WaterInsights.from(
        log({0: 250}),
        goals: goals,
        reference: DateTime(2026, 8, 24, 15),
      );

      expect(insights.paceDifference, -750);
    });

    test('the streak counts consecutive days that met the goal', () {
      final insights = WaterInsights.from(
        log({0: 2000, 1: 2100, 2: 2000, 3: 500}),
        goals: goals,
        reference: reference,
      );

      expect(insights.goalStreak, 3);
    });

    test('an unfinished today does not break the streak', () {
      final insights = WaterInsights.from(
        log({0: 300, 1: 2000, 2: 2000}),
        goals: goals,
        reference: reference,
      );

      expect(insights.goalStreak, 2);
    });

    test('averages ignore days with nothing logged', () {
      final insights = WaterInsights.from(
        log({0: 2000, 1: 1000}),
        goals: goals,
        reference: reference,
      );

      expect(insights.daysLogged, 2);
      expect(insights.averageMl, 1500);
      expect(insights.bestDay, 2000);
    });
  });

  group('reading', () {
    ReadingSession session(
      int daysAgo, {
      String book = 'Dune',
      int pages = 20,
      int minutes = 30,
    }) => ReadingSession(
      id: 'r$daysAgo-$book-$pages',
      day: addDays(reference, -daysAgo),
      book: book,
      pages: pages,
      minutes: minutes,
    );

    test('speed pools pages and minutes across sittings', () {
      final insights = ReadingInsights.from(
        [session(0, pages: 30, minutes: 60), session(1, pages: 30, minutes: 60)],
        reference: reference,
      );

      expect(insights.pagesPerHour, 30);
    });

    test('an untimed sitting does not inflate the speed', () {
      final insights = ReadingInsights.from(
        [session(0, pages: 30, minutes: 60), session(1, pages: 200, minutes: 0)],
        reference: reference,
      );

      expect(insights.pagesPerHour, 30);
    });

    test('speed is null when nothing has been timed', () {
      final insights = ReadingInsights.from(
        [session(0, minutes: 0)],
        reference: reference,
      );

      expect(insights.pagesPerHour, isNull);
    });

    test('the current book is the most recent one', () {
      final insights = ReadingInsights.from(
        [session(5, book: 'Old'), session(0, book: 'New')],
        reference: reference,
      );

      expect(insights.currentBook, 'New');
    });

    test('pages in the current book span the whole log, not the window', () {
      final insights = ReadingInsights.from(
        [session(200, pages: 100), session(0, pages: 20)],
        reference: reference,
      );

      expect(insights.pagesInCurrentBook, 120);
    });

    test('the finish estimate follows this week\'s pace', () {
      // 70 pages in the last week is ten a day; 100 pages left is ten days.
      final insights = ReadingInsights.from(
        [for (var i = 0; i < 7; i++) session(i, pages: 10)],
        reference: reference,
      );

      expect(insights.pagesInCurrentBook, 70);
      expect(insights.daysToFinish(170), 10);
    });

    test('a finished book has no estimate left', () {
      final insights = ReadingInsights.from(
        [session(0, pages: 300)],
        reference: reference,
      );

      expect(insights.daysToFinish(300), isNull);
    });

    test('no reading this week means no estimate', () {
      final insights = ReadingInsights.from(
        [session(20, pages: 50)],
        reference: reference,
      );

      expect(insights.daysToFinish(300), isNull);
    });
  });

  group('food', () {
    Meal meal(
      int hour, {
      MealType type = MealType.lunch,
      Set<FoodTag> tags = const {},
    }) => Meal(
      id: 'm$hour-${type.name}',
      minutesFromMidnight: hour * 60,
      type: type,
      tags: tags,
    );

    test('the eating window spans first to last meal', () {
      final day = FoodDay(day: reference)
          .withMeal(meal(8, type: MealType.breakfast))
          .withMeal(meal(20, type: MealType.dinner));

      expect(day.eatingWindowMinutes, 12 * 60);
    });

    test('one meal is not a window', () {
      final day = FoodDay(day: reference).withMeal(meal(8));
      expect(day.eatingWindowMinutes, isNull);
      expect(day.firstMealMinutes, 8 * 60);
    });

    test('meals stay in time order however they are added', () {
      final day = FoodDay(day: reference)
          .withMeal(meal(20, type: MealType.dinner))
          .withMeal(meal(8, type: MealType.breakfast))
          .withMeal(meal(13, type: MealType.lunch));

      expect(
        day.meals.map((m) => m.minutesFromMidnight),
        [8 * 60, 13 * 60, 20 * 60],
      );
    });

    test('quality is the share of nourishing tags', () {
      final day = FoodDay(day: reference)
          .withMeal(meal(8, tags: {FoodTag.fruit, FoodTag.wholegrain}))
          .withMeal(meal(20, type: MealType.dinner, tags: {FoodTag.fried}));

      expect(day.qualityScore, 67);
    });

    test('an untagged day has no score rather than a zero', () {
      final day = FoodDay(day: reference).withMeal(meal(8));
      expect(day.qualityScore, isNull);
    });

    test('insights average the window across logged days', () {
      final log = <DateTime, FoodDay>{
        reference: FoodDay(day: reference)
            .withMeal(meal(8, type: MealType.breakfast))
            .withMeal(meal(18, type: MealType.dinner)),
        addDays(reference, -1): FoodDay(day: addDays(reference, -1))
            .withMeal(meal(8, type: MealType.breakfast))
            .withMeal(meal(22, type: MealType.dinner)),
      };

      final insights = FoodInsights.from(
        log,
        goals: goals,
        reference: reference,
      );

      expect(insights.daysLogged, 2);
      expect(insights.averageWindowMinutes, 12 * 60);
      // A 10-hour day is inside the 12-hour target; a 14-hour day is not.
      expect(insights.daysInsideWindow, 1);
      expect(insights.averageMealsPerDay, 2);
    });

    test('common tags come back most frequent first', () {
      final log = <DateTime, FoodDay>{
        reference: FoodDay(day: reference)
            .withMeal(meal(8, tags: {FoodTag.vegetables}))
            .withMeal(meal(13, tags: {FoodTag.vegetables, FoodTag.protein})),
      };

      final insights = FoodInsights.from(
        log,
        goals: goals,
        reference: reference,
      );

      expect(insights.commonTags.first.tag, FoodTag.vegetables);
      expect(insights.commonTags.first.count, 2);
    });

    test('an unknown tag in stored data is dropped, not guessed', () {
      final parsed = Meal.fromJson(<String, dynamic>{
        'id': 'm',
        'at': 480,
        'type': 'lunch',
        'tags': ['vegetables', 'kombucha'],
      });

      expect(parsed!.tags, {FoodTag.vegetables});
    });
  });

  group('focus', () {
    FocusSession block(int daysAgo, {int minutes = 25, String tag = ''}) =>
        FocusSession(
          id: 'f$daysAgo-$minutes-$tag',
          day: addDays(reference, -daysAgo),
          startedAtMinutes: 9 * 60,
          minutes: minutes,
          tag: tag,
        );

    test('today is counted separately from the week', () {
      final insights = FocusInsights.from(
        [block(0), block(0, minutes: 50), block(3)],
        reference: reference,
      );

      expect(insights.sessionsToday, 2);
      expect(insights.minutesToday, 75);
      expect(insights.sessionsThisWeek, 3);
    });

    test('the average is over working days, not calendar days', () {
      final insights = FocusInsights.from(
        [block(0, minutes: 60), block(10, minutes: 20)],
        reference: reference,
      );

      expect(insights.daysWorked, 2);
      expect(insights.dailyAverageMinutes, 40);
      expect(insights.bestDayMinutes, 60);
    });

    test('tags are pooled case-insensitively but shown as first typed', () {
      final insights = FocusInsights.from(
        [
          block(0, tag: 'Maths', minutes: 25),
          block(1, tag: 'maths', minutes: 25),
        ],
        reference: reference,
      );

      expect(insights.byTag, hasLength(1));
      expect(insights.byTag.first.tag, 'Maths');
      expect(insights.byTag.first.minutes, 50);
    });

    test('untagged work is not filed under an empty tag', () {
      final insights = FocusInsights.from([block(0)], reference: reference);
      expect(insights.byTag, isEmpty);
    });

    group('the running timer', () {
      test('counts down from the wall clock, not a stored remainder', () {
        final started = DateTime(2026, 8, 24, 9);
        final running = RunningTimer(
          phase: FocusPhase.focus,
          startedAt: started,
          totalMinutes: 25,
          completedFocusBlocks: 0,
        );

        expect(
          running.remainingAt(started.add(const Duration(minutes: 10))),
          const Duration(minutes: 15),
        );
      });

      test('is finished once the time is up, and does not go negative', () {
        final started = DateTime(2026, 8, 24, 9);
        final running = RunningTimer(
          phase: FocusPhase.focus,
          startedAt: started,
          totalMinutes: 25,
          completedFocusBlocks: 0,
        );

        final later = started.add(const Duration(hours: 3));
        expect(running.isFinishedAt(later), isTrue);
        expect(running.remainingAt(later), Duration.zero);
        expect(running.progressAt(later), 1.0);
      });

      test('survives a JSON round trip', () {
        final running = RunningTimer(
          phase: FocusPhase.shortBreak,
          startedAt: DateTime(2026, 8, 24, 9, 30),
          totalMinutes: 5,
          completedFocusBlocks: 2,
          tag: 'Thesis',
        );

        final restored = RunningTimer.fromJson(running.toJson())!;

        expect(restored.phase, FocusPhase.shortBreak);
        expect(restored.startedAt, running.startedAt);
        expect(restored.completedFocusBlocks, 2);
        expect(restored.tag, 'Thesis');
      });
    });
  });

  group('fitness', () {
    Workout workout(
      int daysAgo, {
      int minutes = 30,
      Intensity intensity = Intensity.moderate,
      WorkoutType type = WorkoutType.cardio,
    }) => Workout(
      id: 'w$daysAgo-$minutes-${intensity.name}',
      day: addDays(reference, -daysAgo),
      type: type,
      minutes: minutes,
      intensity: intensity,
    );

    test('easy sessions are logged but not counted as active minutes', () {
      final insights = FitnessInsights.from(
        [
          workout(0, intensity: Intensity.easy, minutes: 60),
          workout(1, intensity: Intensity.moderate, minutes: 30),
        ],
        reference: reference,
      );

      expect(insights.sessionsThisWeek, 2);
      expect(insights.activeMinutesThisWeek, 30);
    });

    test('load is minutes times effort', () {
      final insights = FitnessInsights.from(
        [workout(0, minutes: 30, intensity: Intensity.hard)],
        reference: reference,
      );

      expect(insights.acuteLoad, 90);
    });

    test('a steady month reads as sustainable', () {
      final insights = FitnessInsights.from(
        [for (var i = 0; i < 28; i++) workout(i, minutes: 30)],
        reference: reference,
      );

      expect(insights.verdict, LoadVerdict.steady);
      expect(insights.loadRatio, closeTo(1, 0.01));
    });

    test('a sudden jump reads as a spike', () {
      final insights = FitnessInsights.from(
        [
          // A quiet three weeks, then a heavy one.
          for (var i = 7; i < 28; i++) workout(i, minutes: 10),
          for (var i = 0; i < 7; i++) workout(i, minutes: 90),
        ],
        reference: reference,
      );

      expect(insights.verdict, LoadVerdict.spiking);
      expect(insights.loadRatio, greaterThan(1.5));
    });

    test('a quiet week after a heavy month reads as winding down', () {
      final insights = FitnessInsights.from(
        [for (var i = 7; i < 28; i++) workout(i, minutes: 60)],
        reference: reference,
      );

      expect(insights.verdict, LoadVerdict.detraining);
    });

    test('no history means no verdict rather than an invented one', () {
      final insights = FitnessInsights.from(const [], reference: reference);

      expect(insights.verdict, LoadVerdict.unknown);
      expect(insights.loadRatio, isNull);
    });

    test('rest days count the days without a session', () {
      final insights = FitnessInsights.from(
        [workout(0), workout(1), workout(1, minutes: 45)],
        reference: reference,
      );

      expect(insights.restDaysThisWeek, 5);
      expect(insights.longestSessionMinutes, 45);
    });

    test('type totals come back biggest first', () {
      final insights = FitnessInsights.from(
        [
          workout(0, type: WorkoutType.strength, minutes: 20),
          workout(1, type: WorkoutType.cardio, minutes: 60),
        ],
        reference: reference,
      );

      expect(insights.byType.first.type, WorkoutType.cardio);
    });
  });

  group('formatting', () {
    test('durations drop the empty parts', () {
      expect(formatMinutes(0), '0m');
      expect(formatMinutes(45), '45m');
      expect(formatMinutes(120), '2h');
      expect(formatMinutes(450), '7h 30m');
    });

    test('clock times pad and wrap', () {
      expect(formatClock(0), '00:00');
      expect(formatClock(9 * 60 + 5), '09:05');
      expect(formatClock(1450), '00:10');
    });
  });
}
