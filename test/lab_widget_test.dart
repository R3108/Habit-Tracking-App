import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:habit_tracker/app.dart';
import 'package:habit_tracker/data/app_repository.dart';
import 'package:habit_tracker/models/app_settings.dart';
import 'package:habit_tracker/models/habit.dart';
import 'package:habit_tracker/models/lab/experiment.dart';

Habit habit(
  String id,
  String title, {
  required bool Function(int age) done,
  int ageInDays = 150,
}) {
  final today = dateOnly(DateTime.now());
  return Habit(
    id: id,
    title: title,
    icon: Icons.check_circle,
    color: const Color(0xFF1565C0),
    createdAt: addDays(today, -ageInDays),
    completedDays: <DateTime>{
      for (var age = 1; age <= ageInDays; age++)
        if (done(age)) addDays(today, -age),
    },
  );
}

Future<InMemoryAppRepository> pumpApp(
  WidgetTester tester,
  List<Habit> habits, {
  List<Experiment>? experiments,
}) async {
  // The lab stacks five long cards; anything shorter puts most of them below
  // the fold and turns every assertion into a scroll.
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final repository = InMemoryAppRepository(
    habits: habits,
    experiments: experiments,
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

Future<void> openLab(WidgetTester tester) async {
  await tester.tap(find.text('Insights'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Lab'));
  await tester.pumpAndSettle();
}

Future<void> openExperiments(WidgetTester tester) async {
  await openLab(tester);
  await tester.tap(find.text('Experiments'));
  await tester.pumpAndSettle();
}

void main() {
  group('the lab', () {
    testWidgets('opens from insights and shows every analysis', (tester) async {
      await pumpApp(tester, [
        habit('read', 'Read 20 pages', done: (age) => true),
        habit('run', 'Morning run', done: (age) => age % 4 != 0),
      ]);

      await openLab(tester);

      expect(find.text('Habit strength'), findsOneWidget);
      expect(find.text('Projections'), findsOneWidget);
      expect(find.text('Turning points'), findsOneWidget);
      expect(find.text('Daily load'), findsOneWidget);
    });

    testWidgets('names a habit that looks self-sustaining', (tester) async {
      await pumpApp(tester, [
        habit('read', 'Read 20 pages', done: (age) => true),
      ]);

      await openLab(tester);

      expect(find.text('Worth knowing'), findsOneWidget);
      expect(find.textContaining('self-sustaining'), findsWidgets);
    });

    testWidgets('flags a habit whose misses come in runs', (tester) async {
      await pumpApp(tester, [
        // Four consecutive misses every thirty days.
        habit('gym', 'Gym', done: (age) => age % 30 >= 4),
      ]);

      await openLab(tester);

      expect(find.textContaining('one slip tends to become a run'), findsOne);
    });

    testWidgets('reports a collapse as a turning point', (tester) async {
      await pumpApp(tester, [
        habit('run', 'Morning run', done: (age) => age > 50),
      ]);

      await openLab(tester);

      expect(find.textContaining('Dropped from'), findsWidgets);
    });

    testWidgets('says so plainly when nothing has shifted', (tester) async {
      await pumpApp(tester, [
        habit('read', 'Read 20 pages', done: (age) => true),
      ]);

      await openLab(tester);

      expect(find.textContaining('Nothing has shifted level'), findsOne);
    });

    testWidgets('an empty list has nothing to analyse', (tester) async {
      await pumpApp(tester, const <Habit>[]);

      // Insights shows its own empty state, so the lab is reached directly.
      await tester.tap(find.text('Insights'));
      await tester.pumpAndSettle();
      expect(find.text('Lab'), findsNothing);
    });
  });

  group('experiments', () {
    testWidgets('explains itself while the log is empty', (tester) async {
      await pumpApp(tester, [
        habit('read', 'Read 20 pages', done: (age) => true),
      ]);

      await openExperiments(tester);

      expect(find.text('Why this is different'), findsOneWidget);
      expect(find.text('New experiment'), findsOneWidget);
    });

    testWidgets('one can be started, and then reads as running', (
      tester,
    ) async {
      final repository = await pumpApp(tester, [
        habit('read', 'Read 20 pages', done: (age) => true),
      ]);

      await openExperiments(tester);
      await tester.tap(find.text('New experiment'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Moved it to 6am');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();

      expect(find.text('Running'), findsWidgets);
      expect(find.text('Moved it to 6am'), findsOneWidget);
      expect(repository.experiments, hasLength(1));
      expect(repository.experiments!.single.change, 'Moved it to 6am');
    });

    testWidgets('a start is refused until the change is described', (
      tester,
    ) async {
      await pumpApp(tester, [
        habit('read', 'Read 20 pages', done: (age) => true),
      ]);

      await openExperiments(tester);
      await tester.tap(find.text('New experiment'));
      await tester.pumpAndSettle();

      final start = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Start'),
      );
      expect(start.onPressed, isNull);
    });

    testWidgets('a finished trial reports its verdict', (tester) async {
      final today = dateOnly(DateTime.now());

      await pumpApp(
        tester,
        [
          // Poor for the six weeks before the trial, perfect throughout it.
          habit(
            'read',
            'Read 20 pages',
            done: (age) => age <= 21 || age % 5 < 2,
          ),
        ],
        experiments: [
          Experiment(
            id: 'e1',
            habitId: 'read',
            change: 'Moved it to 6am',
            startDay: addDays(today, -21),
          ),
        ],
      );

      await openExperiments(tester);

      expect(find.text('Finished'), findsOneWidget);
      expect(find.text('It helped'), findsOneWidget);
      expect(find.textContaining('95% interval'), findsOneWidget);
    });

    testWidgets('an unfinished trial shows progress and no verdict', (
      tester,
    ) async {
      final today = dateOnly(DateTime.now());

      await pumpApp(
        tester,
        [habit('read', 'Read 20 pages', done: (age) => true)],
        experiments: [
          Experiment(
            id: 'e1',
            habitId: 'read',
            change: 'Moved it to 6am',
            startDay: addDays(today, -5),
          ),
        ],
      );

      await openExperiments(tester);

      expect(find.text('Running'), findsWidgets);
      expect(find.text('It helped'), findsNothing);
      expect(find.textContaining('days left to run'), findsOneWidget);
      expect(find.text('End early'), findsOneWidget);
    });

    testWidgets('ending early keeps the record but never scores it', (
      tester,
    ) async {
      final today = dateOnly(DateTime.now());

      await pumpApp(
        tester,
        [habit('read', 'Read 20 pages', done: (age) => true)],
        experiments: [
          Experiment(
            id: 'e1',
            habitId: 'read',
            change: 'Moved it to 6am',
            startDay: addDays(today, -5),
          ),
        ],
      );

      await openExperiments(tester);
      await tester.tap(find.text('End early'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('End it'));
      await tester.pumpAndSettle();

      expect(find.text('Abandoned'), findsWidgets);
      expect(find.textContaining('never scored'), findsWidgets);
    });

    testWidgets('a deletion can be undone', (tester) async {
      final today = dateOnly(DateTime.now());

      await pumpApp(
        tester,
        [habit('read', 'Read 20 pages', done: (age) => true)],
        experiments: [
          Experiment(
            id: 'e1',
            habitId: 'read',
            change: 'Moved it to 6am',
            startDay: addDays(today, -5),
          ),
        ],
      );

      await openExperiments(tester);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Moved it to 6am'), findsNothing);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      expect(find.text('Moved it to 6am'), findsOneWidget);
    });
  });
}
