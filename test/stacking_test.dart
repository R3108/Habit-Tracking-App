import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:habit_tracker/data/app_repository.dart';
import 'package:habit_tracker/models/habit.dart';
import 'package:habit_tracker/state/habit_store.dart';

Future<HabitStore> storeWithThree() async {
  final store = HabitStore(
    repository: InMemoryAppRepository(habits: const <Habit>[]),
    saveDebounce: Duration.zero,
  );
  await store.load();
  store
    ..add(title: 'A', icon: Icons.abc, color: Colors.red)
    ..add(title: 'B', icon: Icons.abc, color: Colors.green)
    ..add(title: 'C', icon: Icons.abc, color: Colors.blue);
  return store;
}

void main() {
  late HabitStore store;
  late String a;
  late String b;
  late String c;

  setUp(() async {
    store = await storeWithThree();
    a = store.habits[0].id;
    b = store.habits[1].id;
    c = store.habits[2].id;
  });

  group('anchors', () {
    test('stacking resolves both ways', () {
      store.setAnchor(b, a);

      expect(store.anchorOf(store.byId(b)!)!.title, 'A');
      expect(store.followersOf(a).map((h) => h.title), ['B']);
    });

    test('unstacking clears the link', () {
      store.setAnchor(b, a);
      store.setAnchor(b, null);

      expect(store.byId(b)!.anchorId, isNull);
      expect(store.followersOf(a), isEmpty);
    });

    test('a chain of three is allowed', () {
      store.setAnchor(b, a);
      store.setAnchor(c, b);

      expect(store.anchorOf(store.byId(c)!)!.title, 'B');
      expect(store.anchorOf(store.byId(b)!)!.title, 'A');
    });

    test('an anchor added at creation time sticks', () {
      final made = store.add(
        title: 'D',
        icon: Icons.abc,
        color: Colors.orange,
        anchorId: a,
      );
      expect(store.anchorOf(made)!.title, 'A');
    });
  });

  group('cycles', () {
    test('a habit cannot be stacked behind itself', () {
      expect(store.wouldCycle(a, a), isTrue);

      store.setAnchor(a, a);
      expect(store.byId(a)!.anchorId, isNull);
    });

    test('a direct loop is refused', () {
      store.setAnchor(b, a);
      store.setAnchor(a, b);

      expect(store.byId(a)!.anchorId, isNull);
      expect(store.byId(b)!.anchorId, a);
    });

    test('a loop through a third habit is refused', () {
      store.setAnchor(b, a);
      store.setAnchor(c, b);
      store.setAnchor(a, c);

      expect(store.byId(a)!.anchorId, isNull);
    });

    test('update strips a cyclic anchor rather than storing it', () {
      store.setAnchor(b, a);
      // Goes around setAnchor entirely, the way the editor sheet does.
      store.update(store.byId(a)!.copyWith(anchorId: b));

      expect(store.byId(a)!.anchorId, isNull);
    });

    test('a self-referencing anchor in stored data is dropped on read', () {
      final restored = Habit.fromJson(<String, dynamic>{
        'id': 'loop',
        'title': 'Loop',
        'anchorId': 'loop',
      });
      expect(restored.anchorId, isNull);
    });
  });

  group('a missing anchor', () {
    test('resolves to none once the anchor is deleted', () {
      store.setAnchor(b, a);
      store.remove(a);

      // The id is deliberately left dangling so an undo restores the stack.
      expect(store.byId(b)!.anchorId, a);
      expect(store.anchorOf(store.byId(b)!), isNull);
    });

    test('comes back when the deletion is undone', () {
      store.setAnchor(b, a);
      final removed = store.remove(a)!;
      store.insert(removed.index, removed.habit);

      expect(store.anchorOf(store.byId(b)!)!.title, 'A');
    });

    test('resolves to none while the anchor is archived', () {
      store.setAnchor(b, a);
      store.setArchived(a, true);

      expect(store.anchorOf(store.byId(b)!), isNull);
    });

    test('drops an archived habit from the follower list', () {
      store.setAnchor(b, a);
      store.setArchived(b, true);

      expect(store.followersOf(a), isEmpty);
    });
  });

  test('the anchor survives a JSON round trip', () {
    store.setAnchor(b, a);
    final restored = Habit.fromJson(store.byId(b)!.toJson());
    expect(restored.anchorId, a);
  });
}
