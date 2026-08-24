import 'dart:async';

import 'package:flutter/material.dart';

import '../data/app_repository.dart';
import '../models/habit.dart';
import '../models/habit_icons.dart';
import '../services/notification_service.dart';

/// Owns the habit list, its persistence and the reminders derived from it.
///
/// Mutations are synchronous against the in-memory list — the UI must never
/// wait on disk to tick a checkbox — and the write is debounced behind them.
class HabitStore extends ChangeNotifier {
  HabitStore({
    required this.repository,
    this.notifications,
    List<Habit>? habits,
    this.saveDebounce = const Duration(milliseconds: 350),
  }) : _habits = habits == null ? <Habit>[] : List<Habit>.of(habits);

  final AppRepository repository;
  final NotificationService? notifications;

  /// How long to batch rapid edits before writing. Zero in tests.
  final Duration saveDebounce;

  final List<Habit> _habits;
  Timer? _saveTimer;
  var _nextId = 0;
  var _isLoading = true;
  var _remindersEnabled = true;

  /// True until [load] has finished, so the UI can hold a splash rather than
  /// flashing an empty state over data that is about to arrive.
  bool get isLoading => _isLoading;

  /// Everything, archived included, in user-defined order.
  List<Habit> get allHabits => List.unmodifiable(_habits);

  /// The habits that still count — what every screen but the archive shows.
  List<Habit> get habits =>
      List.unmodifiable(_habits.where((h) => !h.archived));

  List<Habit> get archivedHabits =>
      List.unmodifiable(_habits.where((h) => h.archived));

  bool get isEmpty => habits.isEmpty;

  Habit? byId(String id) {
    for (final habit in _habits) {
      if (habit.id == id) return habit;
    }
    return null;
  }

  /// Reads stored habits, falling back to the first-launch sample set.
  ///
  /// A null result from the repository means "never saved", which is the only
  /// case that seeds demo data — a user who deleted every habit gets their
  /// empty list back, not four suggestions.
  Future<void> load() async {
    final stored = await repository.loadHabits();
    _habits
      ..clear()
      ..addAll(stored ?? starterHabits());
    _nextId = _habits.length;
    _isLoading = false;
    notifyListeners();
    await notifications?.syncReminders(_habits, enabled: _remindersEnabled);
  }

  /// Mirrors the master reminder switch and re-syncs the schedule.
  Future<void> setRemindersEnabled(bool enabled) async {
    if (_remindersEnabled == enabled) return;
    _remindersEnabled = enabled;
    await notifications?.syncReminders(_habits, enabled: enabled);
  }

  void toggle(String id, DateTime day) {
    _mutate(id, (habit) => habit.toggle(day));
  }

  void increment(String id, DateTime day) {
    _mutate(id, (habit) => habit.increment(day));
  }

  void decrement(String id, DateTime day) {
    _mutate(id, (habit) => habit.decrement(day));
  }

  void setArchived(String id, bool archived) {
    _mutate(id, (habit) => habit.copyWith(archived: archived));
  }

  /// Marks [day] as planned time off for [id], or clears it.
  void setSkipped(String id, DateTime day, bool skipped) {
    _mutate(id, (habit) => habit.setSkipped(day, skipped));
  }

  /// Stacks [id] behind [anchorId], or unstacks it when [anchorId] is null.
  ///
  /// Refuses silently rather than throwing when the link would close a loop:
  /// this is called straight from a picker, and the picker has already filtered
  /// the illegal choices out. The check stays because a restored backup or a
  /// later edit can make a previously fine link cyclic.
  void setAnchor(String id, String? anchorId) {
    if (anchorId != null && wouldCycle(id, anchorId)) return;
    _mutate(
      id,
      (habit) => habit.copyWith(
        anchorId: anchorId,
        clearAnchor: anchorId == null,
      ),
    );
  }

  /// Whether pointing [id] at [anchorId] would create a cycle.
  ///
  /// Walks up from the proposed anchor looking for [id]. The step budget is a
  /// backstop for a chain that is *already* circular in stored data — a fresh
  /// cycle can't be longer than the habit list.
  bool wouldCycle(String id, String anchorId) {
    if (id == anchorId) return true;
    var cursor = byId(anchorId);
    for (var steps = 0; cursor != null && steps <= _habits.length; steps++) {
      if (cursor.id == id) return true;
      final next = cursor.anchorId;
      if (next == null) return false;
      cursor = byId(next);
    }
    return true;
  }

  /// The habit [habit] is stacked behind, or null when it stands alone.
  ///
  /// Resolves to null for a dangling id and for an archived anchor: a cue you
  /// can no longer see is not a cue.
  Habit? anchorOf(Habit habit) {
    final id = habit.anchorId;
    if (id == null) return null;
    final anchor = byId(id);
    return anchor == null || anchor.archived ? null : anchor;
  }

  /// The active habits stacked directly behind [id], in list order.
  List<Habit> followersOf(String id) => List.unmodifiable(
    _habits.where((h) => !h.archived && h.anchorId == id),
  );

  /// Replaces a habit wholesale — what the editor hands back on save.
  ///
  /// The incoming anchor is validated here rather than trusted, because this is
  /// the one door every edit comes through. The editor already hides the
  /// choices that would loop; this catches the ones it couldn't know about, such
  /// as a link that only became cyclic because another habit was re-stacked
  /// while the sheet was open.
  void update(Habit habit) {
    final index = _habits.indexWhere((h) => h.id == habit.id);
    if (index == -1) return;

    final anchorId = habit.anchorId;
    _habits[index] = anchorId != null && wouldCycle(habit.id, anchorId)
        ? habit.copyWith(clearAnchor: true)
        : habit;
    _commit();
  }

  Habit add({
    required String title,
    required IconData icon,
    required Color color,
    HabitSchedule schedule = const HabitSchedule.daily(),
    int targetPerDay = 1,
    TimeOfDay? reminder,
    String note = '',
    String? anchorId,
  }) {
    final habit = Habit(
      // Timestamped rather than a bare counter so ids stay unique across a
      // restore that merges in habits saved by another install.
      id: 'habit-${DateTime.now().microsecondsSinceEpoch}-${_nextId++}',
      title: title,
      icon: icon,
      color: color,
      schedule: schedule,
      targetPerDay: targetPerDay,
      reminder: reminder,
      note: note,
      // A brand-new habit has no followers, so no id it can point at is
      // reachable from it — this can never be the link that closes a cycle.
      anchorId: anchorId,
    );
    _habits.add(habit);
    _commit();
    return habit;
  }

  /// Removes [id] and returns it with its original position, so the caller can
  /// offer an undo.
  ({Habit habit, int index})? remove(String id) {
    final index = _habits.indexWhere((h) => h.id == id);
    if (index == -1) return null;
    final removed = _habits.removeAt(index);
    _commit();
    return (habit: removed, index: index);
  }

  void insert(int index, Habit habit) {
    _habits.insert(index.clamp(0, _habits.length), habit);
    _commit();
  }

  /// Moves a habit within the active list.
  ///
  /// Both indices address the *active* habits, and [newIndex] is the
  /// destination after the moved item is taken out — the contract of
  /// `SliverReorderableList.onReorderItem`. Archived habits are interleaved in
  /// the backing list, so the move is anchored on whichever habit currently
  /// holds the destination rather than done by raw index.
  void reorder(int oldIndex, int newIndex) {
    final active = habits;
    if (oldIndex < 0 || oldIndex >= active.length) return;
    final target = newIndex.clamp(0, active.length - 1);
    if (target == oldIndex) return;

    final moved = active[oldIndex];
    final anchor = active[target];
    _habits.remove(moved);
    final anchorIndex = _habits.indexOf(anchor);
    _habits.insert(
      target > oldIndex ? anchorIndex + 1 : anchorIndex,
      moved,
    );
    _commit();
  }

  /// Swaps in a restored backup.
  void replaceAll(List<Habit> habits) {
    _habits
      ..clear()
      ..addAll(habits);
    _nextId = _habits.length;
    _commit();
  }

  Future<void> clearAll() async {
    _habits.clear();
    _nextId = 0;
    notifyListeners();
    await repository.saveHabits(const <Habit>[]);
    await notifications?.cancelAll();
  }

  /// Habits actually expected on [day], newest history included.
  ///
  /// [Habit.isDueOn] covers the habit's own life, its schedule and any planned
  /// day off, so a shielded day drops out of the checklist and out of the
  /// denominator on the progress ring — which is what "day off" has to mean for
  /// the ring to stay honest.
  List<Habit> dueOn(DateTime day) {
    final target = dateOnly(day);
    return <Habit>[
      for (final habit in _habits)
        if (!habit.archived && habit.isDueOn(target)) habit,
    ];
  }

  /// How many of the habits due on [day] are done.
  int completedOn(DateTime day) =>
      dueOn(day).where((h) => h.isCompletedOn(day)).length;

  int dueCountOn(DateTime day) => dueOn(day).length;

  void _mutate(String id, Habit Function(Habit habit) change) {
    final index = _habits.indexWhere((h) => h.id == id);
    if (index == -1) return;
    final next = change(_habits[index]);
    if (identical(next, _habits[index])) return;
    _habits[index] = next;
    _commit();
  }

  void _commit() {
    notifyListeners();
    _scheduleSave();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    if (saveDebounce == Duration.zero) {
      unawaited(flush());
      return;
    }
    _saveTimer = Timer(saveDebounce, () => unawaited(flush()));
  }

  /// Writes pending changes immediately. Called on dispose and by tests.
  Future<void> flush() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    await repository.saveHabits(_habits);
    await notifications?.syncReminders(_habits, enabled: _remindersEnabled);
  }

  @override
  void dispose() {
    // Fire-and-forget: the framework won't await us, but the write is cheap and
    // losing the last tick of the session would be worse than a stray future.
    if (_saveTimer?.isActive ?? false) unawaited(flush());
    _saveTimer?.cancel();
    super.dispose();
  }
}

/// The starter set offered on a genuine first launch.
///
/// Four habits, no history. It is tempting to seed a plausible few weeks of
/// completions so the streaks and the heatmap have something to show off, but
/// that hands the user a "12-day streak" they never earned — which makes every
/// number in the app meaningless on the day they most need to trust it. The
/// insights screen is allowed to look empty until there is something real in
/// it.
///
/// The four cover the shapes the app supports, so editing one is a decent way
/// to discover the rest: a weekday schedule, a plain daily habit, a counted
/// one, and a flexible weekly quota.
List<Habit> starterHabits() {
  return <Habit>[
    Habit(
      id: 'seed-0',
      title: 'Morning run',
      icon: kHabitIcons['run']!,
      color: kHabitPalette[0],
      schedule: const HabitSchedule.onDays({1, 3, 5}),
    ),
    Habit(
      id: 'seed-1',
      title: 'Read 20 pages',
      icon: kHabitIcons['book']!,
      color: kHabitPalette[1],
    ),
    Habit(
      id: 'seed-2',
      title: 'Drink water',
      icon: kHabitIcons['water']!,
      color: kHabitPalette[2],
      targetPerDay: 8,
    ),
    Habit(
      id: 'seed-3',
      title: 'Meditate',
      icon: kHabitIcons['meditate']!,
      color: kHabitPalette[3],
      schedule: const HabitSchedule.timesAWeek(3),
    ),
  ];
}

/// Exposes a [HabitStore] to the subtree and rebuilds dependents on change.
class HabitScope extends InheritedNotifier<HabitStore> {
  const HabitScope({super.key, required HabitStore store, required super.child})
    : super(notifier: store);

  static HabitStore of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<HabitScope>();
    assert(scope?.notifier != null, 'No HabitScope found above this widget');
    return scope!.notifier!;
  }
}
