import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:habit_tracker/app.dart';
import 'package:habit_tracker/data/app_repository.dart';
import 'package:habit_tracker/models/app_settings.dart';
import 'package:habit_tracker/models/habit.dart';
import 'package:habit_tracker/screens/insights_screen.dart';

/// Two plain daily habits, one already done today.
///
/// The demo seed is deliberately not used here: half of it is scheduled on
/// specific weekdays, so what the list shows would depend on the day the suite
/// happens to run.
List<Habit> fixtureHabits() {
  final today = dateOnly(DateTime.now());
  return [
    Habit(
      id: 'read',
      title: 'Read 20 pages',
      icon: Icons.menu_book,
      color: const Color(0xFF1565C0),
      createdAt: addDays(today, -10),
    ),
    Habit(
      id: 'walk',
      title: 'Evening walk',
      icon: Icons.directions_walk,
      color: const Color(0xFF2E7D32),
      completedDays: {today},
      createdAt: addDays(today, -10),
    ),
  ];
}

Future<void> pumpApp(
  WidgetTester tester, {
  List<Habit>? habits,
  AppSettings settings = const AppSettings(
    onboardingComplete: true,
    remindersEnabled: false,
    hapticsEnabled: false,
  ),
}) async {
  await tester.pumpWidget(
    HabitFlowApp(
      repository: InMemoryAppRepository(
        habits: habits ?? fixtureHabits(),
        settings: settings,
      ),
      // No NotificationService: nothing in the widget tree may reach a platform
      // channel that doesn't exist under the test binding.
      saveDebounce: Duration.zero,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders the stored habits', (tester) async {
    await pumpApp(tester);

    // SliverAppBar.large paints its title twice (collapsed and expanded).
    expect(find.text('Today'), findsWidgets);
    expect(find.text('Read 20 pages'), findsOneWidget);
    expect(find.text('Evening walk'), findsOneWidget);
  });

  testWidgets('shows progress for the selected day', (tester) async {
    await pumpApp(tester);
    expect(find.text('1 of 2 complete'), findsOneWidget);
  });

  // The first row is used throughout: at the 800x600 test surface the extended
  // FAB sits on top of the last card's check button, exactly as it would on a
  // short list on a phone.
  testWidgets('the check button toggles completion', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byKey(const ValueKey('toggle-read')));
    await tester.pumpAndSettle();
    expect(find.text('All done — nice work'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('toggle-read')));
    await tester.pumpAndSettle();
    expect(find.text('1 of 2 complete'), findsOneWidget);
  });

  testWidgets('tapping the card body opens the habit, not the checkbox', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.text('Read 20 pages'));
    await tester.pumpAndSettle();

    expect(find.text('Current streak'), findsOneWidget);
    expect(find.text('Best streak'), findsOneWidget);
    // Still unticked: opening a habit must not have toggled it on the way.
    expect(find.text('Total completions'), findsOneWidget);
  });

  testWidgets('adding a habit appends it to the list', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('New habit'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Stretch');
    await tester.pump();
    await tester.tap(find.text('Add habit'));
    await tester.pumpAndSettle();

    // The new habit is untracked today, so the denominator grows but not the
    // completed count.
    expect(find.text('1 of 3 complete'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Stretch'), 120);
    expect(find.text('Stretch'), findsOneWidget);
  });

  testWidgets('a swipe deletes with an undo', (tester) async {
    await pumpApp(tester);

    await tester.drag(
      find.text('Read 20 pages'),
      const Offset(-500, 0),
    );
    await tester.pumpAndSettle();

    expect(find.text('Read 20 pages'), findsNothing);
    expect(find.text('Undo'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('Read 20 pages'), findsOneWidget);
  });

  testWidgets('reorder mode swaps the list for drag handles', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byIcon(Icons.swap_vert));
    await tester.pumpAndSettle();

    expect(find.text('Reorder habits'), findsWidgets);
    expect(find.byIcon(Icons.drag_handle), findsNWidgets(2));
    // The day strip and the swipe-to-delete rows are gone while ordering.
    expect(find.byKey(const ValueKey('toggle-read')), findsNothing);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('toggle-read')), findsOneWidget);
  });

  testWidgets('an empty store shows the empty state', (tester) async {
    await pumpApp(tester, habits: const <Habit>[]);

    expect(find.text('No habits yet'), findsOneWidget);
  });

  testWidgets('onboarding is shown on a first launch', (tester) async {
    await pumpApp(tester, settings: const AppSettings());

    expect(find.text('Build the habit'), findsOneWidget);

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    expect(find.text('Today'), findsWidgets);
  });

  testWidgets('the insights tab charts the history', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byIcon(Icons.insights_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Perfect-day streak'), findsOneWidget);

    // The charts sit below the stat grid, off the 600px test surface. The
    // scrollable has to be named: the other two tabs are still mounted inside
    // the IndexedStack, and the stat grid is itself a (non-scrolling) viewport.
    final insightsList = find
        .descendant(
          of: find.byType(InsightsScreen),
          matching: find.byType(Scrollable),
        )
        .first;

    await tester.scrollUntilVisible(
      find.text('Consistency'),
      200,
      scrollable: insightsList,
    );
    expect(find.text('Consistency'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Milestones'),
      200,
      scrollable: insightsList,
    );
    expect(find.text('Milestones'), findsOneWidget);
  });

  testWidgets('settings can switch the theme mode', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Appearance'), findsOneWidget);

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
  });
}
