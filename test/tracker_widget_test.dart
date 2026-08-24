import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:habit_tracker/app.dart';
import 'package:habit_tracker/data/app_repository.dart';
import 'package:habit_tracker/models/app_settings.dart';
import 'package:habit_tracker/models/habit.dart';
import 'package:habit_tracker/models/trackers/check_in_entry.dart';
import 'package:habit_tracker/models/trackers/custom_tracker.dart';
import 'package:habit_tracker/models/trackers/focus_entry.dart';
import 'package:habit_tracker/models/trackers/sleep_entry.dart';
import 'package:habit_tracker/models/trackers/tracker_data.dart';
import 'package:habit_tracker/models/trackers/tracker_goals.dart';
import 'package:habit_tracker/screens/insights_screen.dart';

/// One plain habit, so the Today tab has something to render and the trackers
/// are reached the way a user reaches them.
List<Habit> fixtureHabits() => [
  Habit(
    id: 'read',
    title: 'Read 20 pages',
    icon: Icons.menu_book,
    color: const Color(0xFF1565C0),
    createdAt: addDays(dateOnly(DateTime.now()), -10),
  ),
];

Future<void> pumpApp(WidgetTester tester, {TrackerData? trackers}) async {
  // Taller than the 800x600 default: the tracker screens are ring-plus-cards,
  // and on the default surface almost everything needs scrolling into view.
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    HabitFlowApp(
      repository: InMemoryAppRepository(
        habits: fixtureHabits(),
        settings: const AppSettings(
          onboardingComplete: true,
          remindersEnabled: false,
          hapticsEnabled: false,
        ),
        trackers: trackers,
      ),
      saveDebounce: Duration.zero,
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> openTrackers(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.monitor_heart_outlined));
  await tester.pumpAndSettle();
}

Future<void> openTracker(WidgetTester tester, String label) async {
  await openTrackers(tester);
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  final today = dateOnly(DateTime.now());

  group('the hub', () {
    testWidgets('lists every built-in tracker', (tester) async {
      await pumpApp(tester);
      await openTrackers(tester);

      for (final label in const [
        'Check-in',
        'Sleep',
        'Water',
        'Reading',
        'Food',
        'Focus',
        'Fitness',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
    });

    testWidgets('describes an untouched tracker instead of showing a zero', (
      tester,
    ) async {
      await pumpApp(tester);
      await openTrackers(tester);

      expect(find.text('Intake against a daily target'), findsOneWidget);
    });

    testWidgets('shows today\'s number once something is logged', (
      tester,
    ) async {
      await pumpApp(
        tester,
        trackers: TrackerData(water: {today: 750}),
      );
      await openTrackers(tester);

      expect(find.text('750 ml'), findsOneWidget);
      expect(find.text('Intake against a daily target'), findsNothing);
    });

    testWidgets('surfaces a pomodoro left running', (tester) async {
      await pumpApp(
        tester,
        trackers: TrackerData(
          runningTimer: RunningTimer(
            phase: FocusPhase.focus,
            startedAt: DateTime.now(),
            totalMinutes: 25,
            completedFocusBlocks: 0,
          ),
        ),
      );
      await openTrackers(tester);

      expect(find.textContaining('Focus running'), findsOneWidget);
    });
  });

  group('water', () {
    testWidgets('a quick-add button logs a drink', (tester) async {
      await pumpApp(tester);
      await openTracker(tester, 'Water');

      expect(find.text('0'), findsOneWidget);

      await tester.tap(find.text('Glass'));
      await tester.pumpAndSettle();

      expect(find.text('250'), findsOneWidget);
    });

    testWidgets('the undo action takes a glass back off', (tester) async {
      await pumpApp(tester, trackers: TrackerData(water: {today: 500}));
      await openTracker(tester, 'Water');

      await tester.tap(find.byIcon(Icons.undo));
      await tester.pumpAndSettle();

      expect(find.text('250'), findsOneWidget);
    });

    testWidgets('shows the pace card, or says why it cannot yet', (
      tester,
    ) async {
      await pumpApp(tester);
      await openTracker(tester, 'Water');

      // Which of the two renders depends on the clock when the suite runs, so
      // the assertion is that exactly one does — never both, never neither.
      final tooEarly = find.textContaining('The day is young');
      final pace = find.textContaining('A steady day would be at');
      expect(tooEarly.evaluate().length + pace.evaluate().length, 1);
    });
  });

  group('sleep', () {
    testWidgets('invites a first night when the log is empty', (tester) async {
      await pumpApp(tester);
      await openTracker(tester, 'Sleep');

      expect(find.text('No nights logged yet'), findsOneWidget);
      expect(find.text('Log a night'), findsOneWidget);
    });

    testWidgets('reports duration and regularity once nights exist', (
      tester,
    ) async {
      final sleep = <DateTime, SleepEntry>{
        for (var age = 0; age < 7; age++)
          addDays(today, -age): SleepEntry(
            day: addDays(today, -age),
            bedMinutes: 23 * 60,
            wakeMinutes: 7 * 60,
          ),
      };

      await pumpApp(tester, trackers: TrackerData(sleep: sleep));
      await openTracker(tester, 'Sleep');

      expect(find.text('8h'), findsWidgets);
      expect(find.text('100/100'), findsOneWidget);
      expect(find.text('Edit last night'), findsOneWidget);
    });
  });

  group('focus', () {
    testWidgets('starting the timer swaps the controls for a countdown', (
      tester,
    ) async {
      await pumpApp(tester);
      await openTracker(tester, 'Focus');

      expect(find.text('Start 25 minutes'), findsOneWidget);

      await tester.tap(find.text('Start 25 minutes'));
      await tester.pumpAndSettle();

      expect(find.text('Give up'), findsOneWidget);
      expect(find.text('Finish now'), findsOneWidget);
    });

    testWidgets('finishing early still banks the session', (tester) async {
      await pumpApp(tester);
      await openTracker(tester, 'Focus');

      await tester.tap(find.text('Start 25 minutes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Finish now'));
      await tester.pumpAndSettle();

      expect(find.textContaining('25 minutes banked'), findsOneWidget);
      expect(find.text('Start 25 minutes'), findsOneWidget);
    });

    testWidgets('giving up records nothing', (tester) async {
      await pumpApp(tester);
      await openTracker(tester, 'Focus');

      await tester.tap(find.text('Start 25 minutes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Give up'));
      await tester.pumpAndSettle();

      expect(find.text('Start 25 minutes'), findsOneWidget);
      expect(find.text('1 of 4'), findsNothing);
    });
  });

  group('fitness', () {
    testWidgets('withholds a load verdict until there is a baseline', (
      tester,
    ) async {
      await pumpApp(tester);
      await openTracker(tester, 'Fitness');

      expect(find.text('Building a baseline'), findsOneWidget);
    });

    testWidgets('logging a workout updates active minutes', (tester) async {
      await pumpApp(tester);
      await openTracker(tester, 'Fitness');

      await tester.tap(find.text('Log a workout'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // The editor defaults to 30 moderate minutes.
      expect(find.text('30'), findsWidgets);
      expect(find.text('1 session'), findsOneWidget);
    });
  });

  group('food', () {
    testWidgets('explains the eating window before there is one', (
      tester,
    ) async {
      await pumpApp(tester);
      await openTracker(tester, 'Food');

      expect(find.text('Eating window'), findsOneWidget);
      expect(find.text('Nothing logged'), findsOneWidget);
    });
  });

  group('the check-in', () {
    testWidgets('one tap records the day, defaulting the other half', (
      tester,
    ) async {
      await pumpApp(tester);
      await openTracker(tester, 'Check-in');

      expect(find.textContaining('Nothing recorded yet'), findsOneWidget);

      // The mood row's "5".
      await tester.tap(find.text('5').first);
      await tester.pumpAndSettle();

      expect(find.text('Great'), findsOneWidget);
      // Energy defaulted to the middle rather than being left unset.
      expect(find.text('Steady'), findsOneWidget);
    });

    testWidgets('the hub shows the day once it is recorded', (tester) async {
      await pumpApp(
        tester,
        trackers: TrackerData(
          checkIns: {today: CheckIn(day: today, mood: 4, energy: 2)},
        ),
      );
      await openTrackers(tester);

      expect(find.text('Good · Tired'), findsOneWidget);
    });
  });

  group('custom trackers', () {
    testWidgets('the hub explains them before any exist', (tester) async {
      await pumpApp(tester);
      await openTrackers(tester);

      expect(find.text('Your own'), findsOneWidget);
      expect(find.text('New tracker'), findsOneWidget);
    });

    testWidgets('one can be created and then logged against', (tester) async {
      await pumpApp(tester);
      await openTrackers(tester);

      await tester.tap(find.text('New tracker'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'Steps');
      await tester.pump();
      await tester.tap(find.text('Create tracker'));
      await tester.pumpAndSettle();

      // Lands straight on the new tracker's screen.
      expect(find.text('Steps'), findsWidgets);

      await tester.tap(find.byIcon(Icons.add).first);
      await tester.pumpAndSettle();

      expect(find.text('1'), findsWidgets);
    });

    testWidgets('a ceiling tracker offers a clean zero', (tester) async {
      await pumpApp(
        tester,
        trackers: const TrackerData(
          customTrackers: [
            CustomTracker(
              id: 'coffee',
              name: 'Coffees',
              kind: CustomTrackerKind.count,
              dailyTarget: 2,
              lowerIsBetter: true,
            ),
          ],
        ),
      );
      await openTrackers(tester);
      await tester.tap(find.text('Coffees'));
      await tester.pumpAndSettle();

      expect(find.text('Record a clean zero'), findsOneWidget);
      expect(find.textContaining('stay under'), findsOneWidget);
    });
  });

  group('discoveries', () {
    testWidgets('are absent until there is something to find', (tester) async {
      await pumpApp(tester);

      await tester.tap(find.byIcon(Icons.insights_outlined));
      await tester.pumpAndSettle();

      expect(find.text('Discoveries'), findsNothing);
    });

    testWidgets('report a real difference across two trackers', (tester) async {
      // Twenty days: sleep alternates long/short, mood follows it.
      final sleep = <DateTime, SleepEntry>{};
      final checkIns = <DateTime, CheckIn>{};
      for (var i = 0; i < 20; i++) {
        final day = addDays(today, -i);
        final slept = i.isEven;
        sleep[day] = SleepEntry(
          day: day,
          bedMinutes: 23 * 60,
          wakeMinutes: slept ? 8 * 60 : 4 * 60,
        );
        checkIns[day] = CheckIn(day: day, mood: slept ? 5 : 2, energy: 3);
      }

      await pumpApp(
        tester,
        trackers: TrackerData(sleep: sleep, checkIns: checkIns),
      );

      await tester.tap(find.byIcon(Icons.insights_outlined));
      await tester.pumpAndSettle();

      final insightsList = find
          .descendant(
            of: find.byType(InsightsScreen),
            matching: find.byType(Scrollable),
          )
          .first;

      await tester.scrollUntilVisible(
        find.text('Discoveries'),
        200,
        scrollable: insightsList,
      );

      expect(find.text('Discoveries'), findsOneWidget);
      expect(find.textContaining('On days your sleep'), findsOneWidget);
      expect(find.textContaining('days compared'), findsWidgets);
    });
  });

  group('targets', () {
    testWidgets('a changed target is reflected on the tracker', (tester) async {
      await pumpApp(
        tester,
        trackers: const TrackerData(goals: TrackerGoals(waterMl: 3000)),
      );
      await openTracker(tester, 'Water');

      expect(find.text('of 3000 ml'), findsOneWidget);
    });

    testWidgets('the targets screen opens from the hub', (tester) async {
      await pumpApp(tester);
      await openTrackers(tester);

      await tester.tap(find.byIcon(Icons.tune));
      await tester.pumpAndSettle();

      expect(find.text('Targets'), findsWidgets);
      expect(find.text('Nightly sleep'), findsOneWidget);
      expect(find.text('Active minutes a week'), findsOneWidget);
    });
  });
}
