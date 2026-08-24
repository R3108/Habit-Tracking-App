import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:habit_tracker/data/app_repository.dart';
import 'package:habit_tracker/models/habit.dart';
import 'package:habit_tracker/state/habit_store.dart';

HabitStore storeWith(InMemoryAppRepository repository) =>
    HabitStore(repository: repository, saveDebounce: Duration.zero);

void main() {
  group('load', () {
    test('seeds the starter set only when nothing has ever been saved', () async {
      final store = storeWith(InMemoryAppRepository());
      await store.load();

      expect(store.isLoading, isFalse);
      expect(store.habits, isNotEmpty);
    });

    test('an empty saved list stays empty', () async {
      // A user who deleted every habit must not be handed the samples back.
      final store = storeWith(InMemoryAppRepository(habits: const <Habit>[]));
      await store.load();

      expect(store.habits, isEmpty);
    });

    test('restores what was saved', () async {
      final repository = InMemoryAppRepository();
      final first = storeWith(repository);
      await first.load();
      first.add(title: 'Floss', icon: Icons.brush, color: Colors.teal);
      await first.flush();

      final second = storeWith(repository);
      await second.load();

      expect(second.habits.map((h) => h.title), contains('Floss'));
    });
  });

  group('persistence', () {
    test('a toggle is written through the repository', () async {
      final repository = InMemoryAppRepository();
      final store = storeWith(repository);
      await store.load();

      final habit = store.habits.first;
      store.toggle(habit.id, DateTime.now());
      await store.flush();

      final saved = decodeHabits(encodeHabits(repository.habits!))!;
      expect(
        saved.firstWhere((h) => h.id == habit.id).isCompletedOn(DateTime.now()),
        !habit.isCompletedOn(DateTime.now()),
      );
    });

    test('the encoded envelope survives a decode', () {
      final habits = starterHabits();
      final decoded = decodeHabits(encodeHabits(habits));

      expect(decoded, isNotNull);
      expect(decoded!.length, habits.length);
      expect(decoded.first.title, habits.first.title);
    });

    test('unreadable stored data decodes to null rather than throwing', () {
      expect(decodeHabits('not json at all'), isNull);
      expect(decodeHabits('{"version":999,"habits":[]}'), isNull);
      expect(decodeHabits(null), isNull);
    });
  });

  group('mutations', () {
    late HabitStore store;

    setUp(() async {
      store = storeWith(InMemoryAppRepository(habits: const <Habit>[]));
      await store.load();
      store
        ..add(title: 'A', icon: Icons.abc, color: Colors.red)
        ..add(title: 'B', icon: Icons.abc, color: Colors.green)
        ..add(title: 'C', icon: Icons.abc, color: Colors.blue);
    });

    test('add appends in order', () {
      expect(store.habits.map((h) => h.title), ['A', 'B', 'C']);
    });

    test('remove hands back the index so it can be undone', () {
      final removed = store.remove(store.habits[1].id)!;
      expect(store.habits.map((h) => h.title), ['A', 'C']);

      store.insert(removed.index, removed.habit);
      expect(store.habits.map((h) => h.title), ['A', 'B', 'C']);
    });

    test('archiving hides a habit without deleting it', () {
      final id = store.habits.first.id;
      store.setArchived(id, true);

      expect(store.habits.map((h) => h.title), ['B', 'C']);
      expect(store.archivedHabits.map((h) => h.title), ['A']);
      expect(store.byId(id), isNotNull);
    });

    // Indices follow SliverReorderableList.onReorderItem: newIndex is the
    // destination *after* the moved item has been taken out.
    test('reorder moves a habit down the list', () {
      store.reorder(0, 2);
      expect(store.habits.map((h) => h.title), ['B', 'C', 'A']);
    });

    test('reorder moves a habit one place down', () {
      store.reorder(0, 1);
      expect(store.habits.map((h) => h.title), ['B', 'A', 'C']);
    });

    test('reorder moves a habit up the list', () {
      store.reorder(2, 0);
      expect(store.habits.map((h) => h.title), ['C', 'A', 'B']);
    });

    test('reorder ignores out-of-range and no-op moves', () {
      store.reorder(1, 1);
      store.reorder(9, 0);
      expect(store.habits.map((h) => h.title), ['A', 'B', 'C']);
    });

    test('reorder keeps archived habits out of the way', () {
      store.setArchived(store.habits[1].id, true);
      store.reorder(0, 2);
      expect(store.habits.map((h) => h.title), ['C', 'A']);
    });
  });

  group('due days', () {
    test('only counts habits the schedule asks for', () async {
      final today = dateOnly(DateTime.now());
      final store = storeWith(
        InMemoryAppRepository(
          habits: [
            Habit(
              id: 'daily',
              title: 'Daily',
              icon: Icons.abc,
              color: Colors.red,
              createdAt: addDays(today, -10),
            ),
            Habit(
              id: 'never-today',
              title: 'Other days',
              icon: Icons.abc,
              color: Colors.blue,
              // Every weekday except today's.
              schedule: HabitSchedule.onDays(
                {1, 2, 3, 4, 5, 6, 7}..remove(today.weekday),
              ),
              createdAt: addDays(today, -10),
            ),
          ],
        ),
      );
      await store.load();

      expect(store.dueOn(today).map((h) => h.id), ['daily']);
      expect(store.dueCountOn(today), 1);
    });

    test('a habit is not due before it was created', () async {
      final today = dateOnly(DateTime.now());
      final store = storeWith(InMemoryAppRepository(habits: const <Habit>[]));
      await store.load();
      store.add(title: 'New', icon: Icons.abc, color: Colors.red);

      expect(store.dueOn(today), hasLength(1));
      expect(store.dueOn(addDays(today, -1)), isEmpty);
    });
  });

  test('clearAll empties the store and the repository', () async {
    final repository = InMemoryAppRepository();
    final store = storeWith(repository);
    await store.load();

    await store.clearAll();

    expect(store.habits, isEmpty);
    expect(repository.habits, isEmpty);
  });
}
