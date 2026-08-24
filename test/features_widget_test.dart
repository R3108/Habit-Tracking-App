import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:habit_tracker/app.dart';
import 'package:habit_tracker/data/app_repository.dart';
import 'package:habit_tracker/models/app_settings.dart';
import 'package:habit_tracker/models/habit.dart';
import 'package:habit_tracker/screens/habit_detail_screen.dart';
import 'package:habit_tracker/screens/home_screen.dart';
import 'package:habit_tracker/screens/insights_screen.dart';

/// The scrollable belonging to [screen].
///
/// Naming it is not optional: the three tabs live in an IndexedStack, so every
/// one of their scroll views stays mounted and an unqualified finder matches
/// several at once.
Finder scrollableOf(Type screen) => find
    .descendant(of: find.byType(screen), matching: find.byType(Scrollable))
    .first;

Habit daily(
  String id,
  String title, {
  Iterable<int> done = const <int>[],
  String? anchorId,
  int ageInDays = 20,
}) {
  final today = dateOnly(DateTime.now());
  return Habit(
    id: id,
    title: title,
    icon: Icons.check_circle,
    color: const Color(0xFF1565C0),
    createdAt: addDays(today, -ageInDays),
    completedDays: done.map((d) => addDays(today, -d)).toSet(),
    anchorId: anchorId,
  );
}

Future<void> pumpApp(WidgetTester tester, List<Habit> habits) async {
  // Taller than the 800x600 default. These features add a card above the
  // checklist and two below the stat grid, and on the default surface the
  // extended FAB lands on top of the very control under test — an artefact of
  // the test window, not of any phone.
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    HabitFlowApp(
      repository: InMemoryAppRepository(
        habits: habits,
        settings: const AppSettings(
          onboardingComplete: true,
          remindersEnabled: false,
          hapticsEnabled: false,
        ),
      ),
      saveDebounce: Duration.zero,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('the focus card', () {
    testWidgets('appears when a streak is on the line today', (tester) async {
      await pumpApp(tester, [
        // Ten days running, but not yet today.
        daily('read', 'Read 20 pages', done: [for (var i = 1; i <= 10; i++) i]),
        daily('walk', 'Evening walk', done: const [0]),
      ]);

      expect(find.text('Worth doing today'), findsOneWidget);
      expect(find.textContaining('10-day streak on the line'), findsOneWidget);
    });

    testWidgets('stays hidden on a short list where nothing is urgent', (
      tester,
    ) async {
      await pumpApp(tester, [
        daily('read', 'Read 20 pages', done: const [0]),
        daily('walk', 'Evening walk', done: const [0]),
      ]);

      expect(find.text('Worth doing today'), findsNothing);
      expect(find.text('Keep an eye on'), findsNothing);
    });

    testWidgets('clears once the habit is ticked', (tester) async {
      await pumpApp(tester, [
        daily('read', 'Read 20 pages', done: [for (var i = 1; i <= 10; i++) i]),
        daily('walk', 'Evening walk', done: const [0]),
      ]);

      expect(find.text('Worth doing today'), findsOneWidget);

      // The card pushes the checklist past the 600px test surface.
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('toggle-read')),
        120,
        scrollable: scrollableOf(HomeScreen),
      );
      await tester.tap(find.byKey(const ValueKey('toggle-read')));
      await tester.pumpAndSettle();

      expect(find.text('Worth doing today'), findsNothing);
    });
  });

  group('habit stacking', () {
    testWidgets('a stacked habit names its anchor', (tester) async {
      await pumpApp(tester, [
        daily('walk', 'Evening walk'),
        daily('read', 'Read 20 pages', anchorId: 'walk'),
      ]);

      expect(find.text('After "Evening walk"'), findsOneWidget);
    });

    testWidgets('the hint turns into a prompt once the anchor is done', (
      tester,
    ) async {
      await pumpApp(tester, [
        daily('walk', 'Evening walk'),
        daily('read', 'Read 20 pages', anchorId: 'walk'),
      ]);

      await tester.tap(find.byKey(const ValueKey('toggle-walk')));
      await tester.pumpAndSettle();

      expect(find.text('"Evening walk" done — you\'re up'), findsOneWidget);
    });

    testWidgets('a dangling anchor shows nothing rather than breaking', (
      tester,
    ) async {
      await pumpApp(tester, [
        daily('read', 'Read 20 pages', anchorId: 'deleted-habit'),
      ]);

      expect(find.text('Read 20 pages'), findsOneWidget);
      expect(find.textContaining('After'), findsNothing);
    });
  });

  group('a day off', () {
    testWidgets('takes the habit out of the checklist', (tester) async {
      await pumpApp(tester, [
        daily('read', 'Read 20 pages'),
        daily('walk', 'Evening walk', done: const [0]),
      ]);

      expect(find.text('1 of 2 complete'), findsOneWidget);

      await tester.longPress(find.text('Read 20 pages'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Take the day off'));
      await tester.pumpAndSettle();

      expect(find.text('All done — nice work'), findsOneWidget);
      expect(find.textContaining('Streak protected'), findsOneWidget);
    });

    testWidgets('can be undone from the snackbar', (tester) async {
      await pumpApp(tester, [
        daily('read', 'Read 20 pages'),
        daily('walk', 'Evening walk', done: const [0]),
      ]);

      await tester.longPress(find.text('Read 20 pages'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Take the day off'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      expect(find.text('1 of 2 complete'), findsOneWidget);
    });
  });

  group('the insights screen', () {
    testWidgets('offers the weekly review and opens it', (tester) async {
      await pumpApp(tester, [
        daily('read', 'Read 20 pages', done: const [0, 1, 2, 3]),
      ]);

      await tester.tap(find.byIcon(Icons.insights_outlined));
      await tester.pumpAndSettle();

      expect(find.text('Weekly review'), findsOneWidget);

      await tester.tap(find.text('Weekly review'));
      await tester.pumpAndSettle();

      expect(find.text('Last seven days'), findsOneWidget);
      expect(find.textContaining('scheduled things done'), findsOneWidget);
    });

    testWidgets('charts a connection between two linked habits', (
      tester,
    ) async {
      final even = [for (var i = 0; i <= 89; i += 2) i];
      await pumpApp(tester, [
        daily('run', 'Morning run', done: even, ageInDays: 90),
        daily('read', 'Read 20 pages', done: even, ageInDays: 90),
      ]);

      await tester.tap(find.byIcon(Icons.insights_outlined));
      await tester.pumpAndSettle();

      final insightsList = find
          .descendant(
            of: find.byType(InsightsScreen),
            matching: find.byType(Scrollable),
          )
          .first;

      await tester.scrollUntilVisible(
        find.text('Connections'),
        200,
        scrollable: insightsList,
      );
      expect(find.text('Connections'), findsOneWidget);
      expect(find.textContaining('On days you do '), findsOneWidget);
    });
  });

  group('the habit detail screen', () {
    testWidgets('shows momentum for a habit with history', (tester) async {
      // An unbroken record for its whole life: 100%, and flat week on week.
      await pumpApp(tester, [
        daily(
          'read',
          'Read 20 pages',
          done: [for (var i = 0; i <= 14; i++) i],
          ageInDays: 14,
        ),
      ]);

      await tester.tap(find.text('Read 20 pages'));
      await tester.pumpAndSettle();

      // The momentum card sits below the stat grid, off the test surface.
      await tester.scrollUntilVisible(
        find.text('Momentum'),
        120,
        scrollable: scrollableOf(HabitDetailScreen),
      );
      expect(find.text('Momentum'), findsOneWidget);
      expect(find.textContaining('Steady'), findsOneWidget);
    });

    testWidgets('holds off on momentum until there is history', (tester) async {
      await pumpApp(tester, [daily('new', 'Brand new', ageInDays: 0)]);

      await tester.tap(find.text('Brand new'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Momentum'),
        120,
        scrollable: scrollableOf(HabitDetailScreen),
      );
      expect(find.text('New'), findsOneWidget);
      expect(find.textContaining('Not enough history yet'), findsOneWidget);
    });
  });
}
