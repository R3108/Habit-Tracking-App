import 'package:flutter_test/flutter_test.dart';

import 'package:habit_tracker/data/app_repository.dart';
import 'package:habit_tracker/models/habit.dart';
import 'package:habit_tracker/models/trackers/check_in_entry.dart';
import 'package:habit_tracker/models/trackers/custom_tracker.dart';
import 'package:habit_tracker/models/trackers/fitness_entry.dart';
import 'package:habit_tracker/models/trackers/focus_entry.dart';
import 'package:habit_tracker/models/trackers/food_entry.dart';
import 'package:habit_tracker/models/trackers/sleep_entry.dart';
import 'package:habit_tracker/models/trackers/tracker_data.dart';
import 'package:habit_tracker/models/trackers/tracker_goals.dart';
import 'package:habit_tracker/state/tracker_store.dart';

Future<TrackerStore> freshStore([InMemoryAppRepository? repository]) async {
  final store = TrackerStore(
    repository: repository ?? InMemoryAppRepository(),
    saveDebounce: Duration.zero,
  );
  await store.load();
  return store;
}

void main() {
  final today = dateOnly(DateTime.now());

  group('load', () {
    test('an install with no tracker data starts empty', () async {
      final store = await freshStore();

      expect(store.isLoading, isFalse);
      expect(store.data.isEmpty, isTrue);
      expect(store.goals, const TrackerGoals());
    });

    test('what was saved comes back', () async {
      final repository = InMemoryAppRepository();
      final first = await freshStore(repository);
      first.addWater(today, 500);
      await first.flush();

      final second = await freshStore(repository);
      expect(second.waterOn(today), 500);
    });
  });

  group('water', () {
    test('adding accumulates through the day', () async {
      final store = await freshStore();
      store
        ..addWater(today, 250)
        ..addWater(today, 350);

      expect(store.waterOn(today), 600);
    });

    test('a negative add is the undo button, and cannot go below zero', () async {
      final store = await freshStore();
      store
        ..addWater(today, 250)
        ..addWater(today, -1000);

      expect(store.waterOn(today), 0);
    });
  });

  group('sleep', () {
    test('logging then clearing leaves nothing behind', () async {
      final store = await freshStore();
      store.logSleep(
        SleepEntry(day: today, bedMinutes: 23 * 60, wakeMinutes: 7 * 60),
      );
      expect(store.sleepOn(today), isNotNull);

      store.clearSleep(today);
      expect(store.sleepOn(today), isNull);
    });

    test('a second entry for the same night replaces the first', () async {
      final store = await freshStore();
      store
        ..logSleep(
          SleepEntry(day: today, bedMinutes: 23 * 60, wakeMinutes: 7 * 60),
        )
        ..logSleep(
          SleepEntry(day: today, bedMinutes: 22 * 60, wakeMinutes: 6 * 60),
        );

      expect(store.data.sleep, hasLength(1));
      expect(store.sleepOn(today)!.bedMinutes, 22 * 60);
    });
  });

  group('reading', () {
    test('a removed sitting can be put back where it was', () async {
      final store = await freshStore();
      store.addReading(day: today, book: 'A', pages: 10, minutes: 15);
      final middle = store.addReading(
        day: today,
        book: 'B',
        pages: 10,
        minutes: 15,
      );
      store.addReading(day: today, book: 'C', pages: 10, minutes: 15);

      final removed = store.removeReading(middle.id)!;
      expect(store.data.reading.map((s) => s.book), ['A', 'C']);

      store.insertReading(removed.index, removed.session);
      expect(store.data.reading.map((s) => s.book), ['A', 'B', 'C']);
    });

    test('a book length is keyed case-insensitively', () async {
      final store = await freshStore();
      store.setBookLength('Dune', 412);

      expect(store.bookLength('dune'), 412);
      expect(store.bookLength('  DUNE '), 412);
    });

    test('setting a length to zero forgets it', () async {
      final store = await freshStore();
      store
        ..setBookLength('Dune', 412)
        ..setBookLength('Dune', 0);

      expect(store.bookLength('Dune'), isNull);
    });
  });

  group('food', () {
    test('a day with its last meal removed is dropped, not left empty', () async {
      final store = await freshStore();
      final meal = store.addMeal(
        day: today,
        minutesFromMidnight: 8 * 60,
        type: MealType.breakfast,
      );
      expect(store.data.food, hasLength(1));

      store.removeMeal(today, meal.id);
      expect(store.data.food, isEmpty);
      expect(store.foodOn(today).isEmpty, isTrue);
    });

    test('a day never logged still answers with an empty day', () async {
      final store = await freshStore();
      expect(store.foodOn(today).meals, isEmpty);
    });
  });

  group('the focus timer', () {
    test('a finished focus phase is banked as a session', () async {
      final store = await freshStore();
      store.startTimer(phase: FocusPhase.focus, minutes: 25, tag: 'Maths');

      final session = store.completeTimer();

      expect(session, isNotNull);
      expect(session!.minutes, 25);
      expect(session.tag, 'Maths');
      expect(store.data.focus, hasLength(1));
      expect(store.runningTimer, isNull);
    });

    test('a finished break records nothing', () async {
      final store = await freshStore();
      store.startTimer(phase: FocusPhase.shortBreak, minutes: 5);

      expect(store.completeTimer(), isNull);
      expect(store.data.focus, isEmpty);
      expect(store.runningTimer, isNull);
    });

    test('giving up records nothing', () async {
      final store = await freshStore();
      store.startTimer(phase: FocusPhase.focus, minutes: 25);
      store.cancelTimer();

      expect(store.data.focus, isEmpty);
      expect(store.runningTimer, isNull);
    });

    test('a running timer survives a reload', () async {
      final repository = InMemoryAppRepository();
      final first = await freshStore(repository);
      first.startTimer(phase: FocusPhase.focus, minutes: 25, tag: 'Thesis');
      await first.flush();

      final second = await freshStore(repository);
      expect(second.runningTimer, isNotNull);
      expect(second.runningTimer!.tag, 'Thesis');
      // Banking it after the restart still writes the session, which is the
      // whole point of persisting the start time rather than a countdown.
      expect(second.completeTimer(), isNotNull);
    });

    test('work logged by hand lands in the same log', () async {
      final store = await freshStore();
      store.logFocus(day: today, minutes: 40, tag: 'Reading');

      expect(store.data.focus, hasLength(1));
      expect(store.data.focus.first.minutes, 40);
    });
  });

  group('fitness', () {
    test('a removed workout can be undone', () async {
      final store = await freshStore();
      final workout = store.addWorkout(
        day: today,
        type: WorkoutType.cardio,
        minutes: 30,
      );

      final removed = store.removeWorkout(workout.id)!;
      expect(store.data.workouts, isEmpty);

      store.insertWorkout(removed.index, removed.workout);
      expect(store.data.workouts, hasLength(1));
    });
  });

  group('the check-in', () {
    test('logging then clearing leaves nothing behind', () async {
      final store = await freshStore();
      store.logCheckIn(CheckIn(day: today, mood: 4, energy: 2));

      expect(store.checkInOn(today)!.mood, 4);

      store.clearCheckIn(today);
      expect(store.checkInOn(today), isNull);
    });

    test('a second entry for the same day replaces the first', () async {
      final store = await freshStore();
      store
        ..logCheckIn(CheckIn(day: today, mood: 2, energy: 2))
        ..logCheckIn(CheckIn(day: today, mood: 5, energy: 5));

      expect(store.data.checkIns, hasLength(1));
      expect(store.checkInOn(today)!.mood, 5);
    });
  });

  group('custom trackers', () {
    test('a new tracker starts with no history', () async {
      final store = await freshStore();
      final tracker = store.addCustomTracker(
        name: 'Steps',
        kind: CustomTrackerKind.count,
        dailyTarget: 10000,
        step: 1000,
      );

      expect(store.data.customTrackers, hasLength(1));
      expect(store.customValueOn(tracker.id, today), 0);
    });

    test('adding accumulates through the day', () async {
      final store = await freshStore();
      final tracker = store.addCustomTracker(
        name: 'Steps',
        kind: CustomTrackerKind.count,
        step: 1000,
      );

      store
        ..addCustomValue(tracker.id, today, 1000)
        ..addCustomValue(tracker.id, today, 500);

      expect(store.customValueOn(tracker.id, today), 1500);
    });

    test('a recorded zero is kept, and only clearing removes the day', () async {
      // The distinction is the whole point for a ceiling tracker: zero is the
      // best possible day, and absence means the day was never answered.
      final store = await freshStore();
      final tracker = store.addCustomTracker(
        name: 'Coffees',
        kind: CustomTrackerKind.count,
        lowerIsBetter: true,
      );

      store.setCustomValue(tracker.id, today, 0);
      expect(store.data.entriesFor(tracker.id).containsKey(today), isTrue);

      store.clearCustomValue(tracker.id, today);
      expect(store.data.entriesFor(tracker.id).containsKey(today), isFalse);
    });

    test('editing keeps the history', () async {
      final store = await freshStore();
      final tracker = store.addCustomTracker(
        name: 'Steps',
        kind: CustomTrackerKind.count,
      );
      store.addCustomValue(tracker.id, today, 8000);

      store.updateCustomTracker(
        tracker.copyWith(name: 'Daily steps', dailyTarget: 12000),
      );

      expect(store.customTrackerById(tracker.id)!.name, 'Daily steps');
      expect(store.customValueOn(tracker.id, today), 8000);
    });

    test('deleting takes the history with it, and undo brings both back', () async {
      final store = await freshStore();
      final tracker = store.addCustomTracker(
        name: 'Steps',
        kind: CustomTrackerKind.count,
      );
      store.addCustomValue(tracker.id, today, 8000);

      final removed = store.removeCustomTracker(tracker.id)!;
      expect(store.data.customTrackers, isEmpty);
      expect(store.data.entriesFor(tracker.id), isEmpty);

      store.insertCustomTracker(
        removed.index,
        removed.tracker,
        removed.entries,
      );
      expect(store.data.customTrackers, hasLength(1));
      expect(store.customValueOn(tracker.id, today), 8000);
    });

    test('archiving hides a tracker without deleting it', () async {
      final store = await freshStore();
      final tracker = store.addCustomTracker(
        name: 'Steps',
        kind: CustomTrackerKind.count,
      );

      store.updateCustomTracker(tracker.copyWith(archived: true));

      expect(store.data.activeCustomTrackers, isEmpty);
      expect(store.customTrackerById(tracker.id), isNotNull);
    });
  });

  group('persistence', () {
    test('every tracker survives an encode and decode', () async {
      final store = await freshStore();
      store
        ..setGoals(const TrackerGoals(sleepMinutes: 450, waterMl: 2500))
        ..logSleep(
          SleepEntry(
            day: today,
            bedMinutes: 23 * 60 + 30,
            wakeMinutes: 7 * 60,
            quality: 4,
            note: 'Woke once',
          ),
        )
        ..addWater(today, 750)
        ..addReading(day: today, book: 'Dune', pages: 32, minutes: 45)
        ..setBookLength('Dune', 412)
        ..addMeal(
          day: today,
          minutesFromMidnight: 8 * 60,
          type: MealType.breakfast,
          tags: {FoodTag.fruit, FoodTag.wholegrain},
          note: 'Porridge',
        )
        ..logFocus(day: today, minutes: 25, tag: 'Maths')
        ..addWorkout(
          day: today,
          type: WorkoutType.strength,
          minutes: 40,
          intensity: Intensity.hard,
          note: 'Upper body',
        )
        ..logCheckIn(
          CheckIn(day: today, mood: 4, energy: 2, note: 'Long day'),
        );

      final custom = store.addCustomTracker(
        name: 'Coffees',
        kind: CustomTrackerKind.count,
        dailyTarget: 2,
        lowerIsBetter: true,
        iconKey: 'food',
      );
      store.setCustomValue(custom.id, today, 1);

      final restored = decodeTrackers(encodeTrackers(store.data))!;

      expect(restored.goals.sleepMinutes, 450);
      expect(restored.goals.waterMl, 2500);
      expect(restored.sleep[today]!.quality, 4);
      expect(restored.sleep[today]!.note, 'Woke once');
      expect(restored.sleep[today]!.durationMinutes, 450);
      expect(restored.water[today], 750);
      expect(restored.reading.single.book, 'Dune');
      expect(restored.reading.single.pages, 32);
      expect(restored.bookLengths['dune'], 412);
      expect(restored.food[today]!.meals.single.tags, {
        FoodTag.fruit,
        FoodTag.wholegrain,
      });
      expect(restored.food[today]!.meals.single.note, 'Porridge');
      expect(restored.focus.single.tag, 'Maths');
      expect(restored.workouts.single.intensity, Intensity.hard);
      expect(restored.workouts.single.note, 'Upper body');
      expect(restored.checkIns[today]!.mood, 4);
      expect(restored.checkIns[today]!.note, 'Long day');
      expect(restored.customTrackers.single.name, 'Coffees');
      expect(restored.customTrackers.single.lowerIsBetter, isTrue);
      expect(restored.customTrackers.single.iconKey, 'food');
      expect(restored.entriesFor(custom.id)[today], 1);
    });

    test('a schema v1 blob still decodes under v2', () {
      // Written before the check-in and custom trackers existed. All three new
      // sections are absent-means-empty, so there is no migration branch.
      const payload = '{"version":1,"trackers":{"water":{"2026-08-20":1500}}}';

      final restored = decodeTrackers(payload)!;

      expect(restored.water[DateTime(2026, 8, 20)], 1500);
      expect(restored.checkIns, isEmpty);
      expect(restored.customTrackers, isEmpty);
      expect(restored.customEntries, isEmpty);
    });

    test('custom entries for a deleted tracker are dropped on read', () async {
      final store = await freshStore();
      final tracker = store.addCustomTracker(
        name: 'Steps',
        kind: CustomTrackerKind.count,
      );
      store.addCustomValue(tracker.id, today, 8000);
      store.removeCustomTracker(tracker.id);

      final restored = decodeTrackers(encodeTrackers(store.data))!;

      expect(restored.customTrackers, isEmpty);
      expect(restored.customEntries, isEmpty);
    });

    test('an empty snapshot round-trips to an empty snapshot', () {
      final restored = decodeTrackers(encodeTrackers(const TrackerData()))!;
      expect(restored.isEmpty, isTrue);
    });

    test('unreadable data decodes to null rather than throwing', () {
      expect(decodeTrackers('not json'), isNull);
      expect(decodeTrackers('{"version":999,"trackers":{}}'), isNull);
      expect(decodeTrackers(null), isNull);
      expect(decodeTrackers(''), isNull);
    });

    test('one corrupt record does not sink the rest', () {
      const payload = '{"version":1,"trackers":{"workouts":['
          '{"id":"a","day":"2026-08-20","type":"cardio","minutes":30},'
          '{"id":"b","type":"cardio","minutes":30},'
          '"nonsense"]}}';

      final restored = decodeTrackers(payload)!;
      // The middle record has no day, so there is nothing to file it under.
      expect(restored.workouts, hasLength(1));
      expect(restored.workouts.single.id, 'a');
    });

    test('goals out of range are clamped rather than trusted', () {
      const payload =
          '{"version":1,"trackers":{"goals":{"sleepMinutes":99999,"waterMl":1}}}';

      final restored = decodeTrackers(payload)!;
      expect(restored.goals.sleepMinutes, 12 * 60);
      expect(restored.goals.waterMl, 250);
    });

    test('clearAll empties the store and the repository', () async {
      final repository = InMemoryAppRepository();
      final store = await freshStore(repository);
      store.addWater(today, 500);
      await store.flush();

      await store.clearAll();

      expect(store.data.isEmpty, isTrue);
      expect(repository.trackers!.isEmpty, isTrue);
    });
  });
}
