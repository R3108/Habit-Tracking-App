import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:habit_tracker/app.dart';
import 'package:habit_tracker/data/app_repository.dart';
import 'package:habit_tracker/models/app_settings.dart';
import 'package:habit_tracker/models/habit.dart';
import 'package:habit_tracker/models/trackers/sleep_entry.dart';
import 'package:habit_tracker/models/trackers/tracker_data.dart';
import 'package:habit_tracker/screens/coach_screen.dart';
import 'package:habit_tracker/screens/insights_screen.dart';

Habit habit(
  String id,
  String title, {
  required bool Function(int age) done,
  int ageInDays = 120,
}) {
  final today = dateOnly(DateTime.now());
  return Habit(
    id: id,
    title: title,
    icon: Icons.check_circle,
    color: const Color(0xFF1565C0),
    createdAt: addDays(today, -ageInDays),
    completedDays: <DateTime>{
      for (var age = 0; age <= ageInDays; age++)
        if (done(age)) addDays(today, -age),
    },
  );
}

Future<InMemoryAppRepository> pumpApp(
  WidgetTester tester,
  List<Habit> habits, {
  TrackerData? trackers,
}) async {
  // Taller than the default surface: the coach is a long screen and the
  // sections under test would otherwise sit below an 800x600 fold.
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final repository = InMemoryAppRepository(
    habits: habits,
    trackers: trackers,
    settings: const AppSettings(
      onboardingComplete: true,
      remindersEnabled: false,
      hapticsEnabled: false,
    ),
  );

  await tester.pumpWidget(
    HabitFlowApp(repository: repository, saveDebounce: Duration.zero),
  );
  await tester.pumpAndSettle();
  return repository;
}

Future<void> openCoach(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Coach'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Today carries the forecast and opens the coach', (tester) async {
    await pumpApp(tester, [
      habit('read', 'Read 20 pages', done: (age) => age > 0),
      habit('walk', 'Evening walk', done: (age) => age > 0),
    ]);

    expect(find.textContaining('by tonight'), findsOneWidget);

    await tester.tap(find.textContaining('by tonight'));
    await tester.pumpAndSettle();

    expect(find.byType(CoachScreen), findsOneWidget);
    expect(find.text("Today's odds"), findsOneWidget);
  });

  testWidgets('the odds name the condition behind them', (tester) async {
    final today = dateOnly(DateTime.now());
    await pumpApp(tester, [
      // Kept every day except this weekday, for four months.
      habit(
        'run',
        'Morning run',
        done: (age) =>
            age > 0 && addDays(today, -age).weekday != today.weekday,
      ),
    ]);

    await openCoach(tester);

    // The briefing says it too, which is the point of the briefing.
    expect(find.textContaining('run at 0%'), findsWidgets);
  });

  testWidgets('a schedule suggestion applies and can be undone', (
    tester,
  ) async {
    final today = dateOnly(DateTime.now());
    // A daily habit kept every day but Friday.
    await pumpApp(tester, [
      habit(
        'run',
        'Morning run',
        done: (age) =>
            age > 0 && addDays(today, -age).weekday != DateTime.friday,
      ),
    ]);

    await openCoach(tester);
    expect(find.text('Schedule changes'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Apply'), 200);
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    // The suggestion is gone because the schedule it argued with is gone.
    expect(find.text('Stop asking on Fridays'), findsNothing);
    expect(find.textContaining('Morning run'), findsWidgets);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Stop asking on Fridays'), findsWidgets);
  });

  testWidgets('a target suggestion applies from the coach', (tester) async {
    final today = dateOnly(DateTime.now());

    await pumpApp(
      tester,
      [habit('read', 'Read 20 pages', done: (age) => age > 0)],
      trackers: TrackerData(
        sleep: <DateTime, SleepEntry>{
          for (var age = 1; age <= 20; age++)
            addDays(today, -age): SleepEntry(
              day: addDays(today, -age),
              bedMinutes: 0,
              wakeMinutes: 400,
              quality: 3,
            ),
        },
      ),
    );

    await openCoach(tester);

    expect(find.text('Targets'), findsOneWidget);
    expect(find.textContaining('Ease to 6h 45m'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Apply'), 200);
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Sleep target'), findsOneWidget);
    expect(find.textContaining('Ease to 6h 45m'), findsNothing);
  });

  testWidgets('the blueprint appears on Insights once the days differ', (
    tester,
  ) async {
    final today = dateOnly(DateTime.now());

    await pumpApp(
      tester,
      [
        habit('read', 'Read 20 pages', ageInDays: 40, done: (age) => true),
        habit(
          'walk',
          'Evening walk',
          ageInDays: 40,
          done: (age) => age.isEven,
        ),
      ],
      trackers: TrackerData(
        sleep: <DateTime, SleepEntry>{
          for (var age = 0; age <= 40; age++)
            addDays(today, -age): SleepEntry(
              day: addDays(today, -age),
              bedMinutes: 0,
              wakeMinutes: age.isEven ? 480 : 360,
              quality: 3,
            ),
        },
      ),
    );

    await tester.tap(find.byIcon(Icons.insights_outlined));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Blueprint of a good day'),
      300,
      scrollable: find
          .descendant(
            of: find.byType(InsightsScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );

    expect(find.text('Blueprint of a good day'), findsOneWidget);
    expect(find.textContaining('Sleep above'), findsOneWidget);
  });

  testWidgets('an empty app offers no way in at all', (tester) async {
    await pumpApp(tester, const <Habit>[]);

    // Nothing to coach, so the entry points stay away rather than leading to a
    // screen that can only apologise.
    expect(find.byTooltip('Coach'), findsNothing);
    expect(find.textContaining('by tonight'), findsNothing);
  });
}
