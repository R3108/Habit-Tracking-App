import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:habit_tracker/models/briefing.dart';
import 'package:habit_tracker/models/habit.dart';
import 'package:habit_tracker/models/trackers/sleep_entry.dart';
import 'package:habit_tracker/models/trackers/tracker_data.dart';

final reference = DateTime(2026, 8, 26);

Habit habit(
  String id, {
  required bool Function(int age) done,
  int ageInDays = 60,
  HabitSchedule schedule = const HabitSchedule.daily(),
}) {
  return Habit(
    id: id,
    title: id,
    icon: Icons.check,
    color: const Color(0xFF1565C0),
    schedule: schedule,
    createdAt: addDays(reference, -ageInDays),
    completedDays: <DateTime>{
      for (var age = 0; age <= ageInDays; age++)
        if (done(age)) addDays(reference, -age),
    },
  );
}

DailyBriefing briefingFor(
  List<Habit> habits, {
  TrackerData trackers = const TrackerData(),
}) => DailyBriefing.build(
  habits: habits,
  trackers: trackers,
  reference: reference,
);

void main() {
  group('the headline', () {
    test('is the forecast once there is history behind it', () {
      final briefing = briefingFor([
        habit('read', done: (age) => age > 0),
        habit('walk', done: (age) => age > 0),
      ]);

      expect(briefing.headline, 'About 2 of 2 by tonight');
      expect(briefing.subhead, contains('0 done, 2 to go'));
    });

    test('says so plainly when the day is already clear', () {
      final briefing = briefingFor([habit('read', done: (age) => true)]);

      expect(briefing.headline, 'All 1 done');
      expect(briefing.items.single.tone, BriefingTone.good);
    });

    test('and when nothing was asked for at all', () {
      final briefing = briefingFor([
        habit(
          'gym',
          done: (age) => false,
          schedule: HabitSchedule.onDays({
            reference.weekday == 7 ? 1 : reference.weekday + 1,
          }),
        ),
      ]);

      expect(briefing.headline, 'Nothing scheduled today');
      expect(briefing.forecast.isEmpty, isTrue);
    });

    test('holds back the odds while the model is still learning', () {
      final briefing = briefingFor([
        habit('read', ageInDays: 3, done: (age) => age > 0),
      ]);

      expect(briefing.headline, '0 of 1 done');
      expect(briefing.subhead, contains('few more weeks'));
    });
  });

  group('the order', () {
    test('a streak decided today comes before anything else', () {
      final briefing = briefingFor([
        // Ten days running, not yet ticked today.
        habit('read', done: (age) => age >= 1 && age <= 10),
        habit('walk', done: (age) => age % 3 == 0),
      ]);

      expect(briefing.items.first.icon, Icons.local_fire_department);
      expect(briefing.items.first.text, contains('10-day streak'));
      expect(briefing.items.first.habitId, 'read');
      expect(briefing.items.first.tone, BriefingTone.warning);
    });

    test('then the habit the model expects to get away', () {
      final briefing = briefingFor([
        habit('read', done: (age) => true),
        // Managed one day in four for two months.
        habit('write', done: (age) => age % 4 == 0 && age > 0),
      ]);

      final line = briefing.items.firstWhere((i) => i.habitId == 'write');
      expect(line.text, contains('History puts "write" at'));
    });

    test('and never more than a paragraph of them', () {
      final briefing = briefingFor([
        habit('read', done: (age) => age >= 1 && age <= 10),
        habit('write', done: (age) => age % 4 == 0 && age > 0),
        habit('walk', done: (age) => age % 3 == 0 && age > 0),
      ]);

      expect(
        briefing.items.length,
        lessThanOrEqualTo(DailyBriefing.maximumItems),
      );
    });
  });

  group('today against the blueprint', () {
    /// Two habits over forty days: one kept always, one on even days only, so
    /// the share of habits kept alternates and the day can be sorted into a
    /// good third and a poor one.
    List<Habit> mixedHabits() => [
      habit('read', ageInDays: 40, done: (age) => age > 0),
      habit('walk', ageInDays: 40, done: (age) => age > 0 && age.isEven),
    ];

    TrackerData sleepOf(int todayMinutes) => TrackerData(
      sleep: <DateTime, SleepEntry>{
        for (var age = 0; age <= 40; age++)
          addDays(reference, -age): SleepEntry(
            day: addDays(reference, -age),
            bedMinutes: 0,
            wakeMinutes: age == 0
                ? todayMinutes
                : age.isEven
                ? 480
                : 360,
            quality: 3,
          ),
      },
    );

    test('names what today is short of', () {
      final briefing = briefingFor(mixedHabits(), trackers: sleepOf(300));

      expect(briefing.blueprint, isNotNull);
      expect(
        briefing.items.any((i) => i.text.contains('Your best days run above')),
        isTrue,
      );
      expect(briefing.items.any((i) => i.text.contains('5h')), isTrue);
    });

    test('and gives credit when today already matches it', () {
      final briefing = briefingFor(mixedHabits(), trackers: sleepOf(540));

      final line = briefing.items.firstWhere(
        (i) => i.text.contains('already where your best days sit'),
      );
      expect(line.tone, BriefingTone.good);
    });

    test('stays quiet about a day that was never logged', () {
      final trackers = sleepOf(300);
      final withoutToday = TrackerData(
        sleep: <DateTime, SleepEntry>{...trackers.sleep}..remove(reference),
      );

      final briefing = briefingFor(mixedHabits(), trackers: withoutToday);

      expect(briefing.blueprint, isNotNull);
      expect(
        briefing.items.any((i) => i.text.contains('best days run')),
        isFalse,
      );
    });
  });

  group('the plan itself', () {
    test('a schedule worth changing is raised, and carried on the briefing', () {
      final run = habit(
        'run',
        ageInDays: 120,
        done: (age) =>
            age > 0 && addDays(reference, -age).weekday != DateTime.friday,
      );

      final briefing = briefingFor([run]);

      expect(briefing.schedule, hasLength(1));
      expect(briefing.hasSuggestions, isTrue);
      expect(
        briefing.items.any((i) => i.text.contains('Stop asking on Fridays')),
        isTrue,
      );
    });

    test('nothing to suggest is itself a clean answer', () {
      final briefing = briefingFor([habit('read', done: (age) => age > 0)]);

      expect(briefing.hasSuggestions, isFalse);
      expect(briefing.items, isNotEmpty);
    });
  });
}
