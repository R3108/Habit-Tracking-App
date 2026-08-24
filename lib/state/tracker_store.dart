import 'dart:async';

import 'package:flutter/material.dart';

import '../data/app_repository.dart';
import '../models/habit.dart';
import '../models/trackers/fitness_entry.dart';
import '../models/trackers/focus_entry.dart';
import '../models/trackers/food_entry.dart';
import '../models/trackers/reading_entry.dart';
import '../models/trackers/sleep_entry.dart';
import '../models/trackers/tracker_data.dart';
import '../models/trackers/tracker_goals.dart';

/// Owns the six trackers and their persistence.
///
/// Mirrors [HabitStore] deliberately, down to the debounce: a water tap and a
/// habit tick are the same kind of event, and the two stores behaving
/// differently under a burst of taps would be a bug waiting to be written.
class TrackerStore extends ChangeNotifier {
  TrackerStore({
    required this.repository,
    TrackerData? data,
    this.saveDebounce = const Duration(milliseconds: 350),
  }) : _data = data ?? const TrackerData();

  final AppRepository repository;
  final Duration saveDebounce;

  TrackerData _data;
  Timer? _saveTimer;
  var _isLoading = true;
  var _nextId = 0;

  TrackerData get data => _data;
  TrackerGoals get goals => _data.goals;
  bool get isLoading => _isLoading;

  Future<void> load() async {
    _data = await repository.loadTrackers() ?? const TrackerData();
    _isLoading = false;
    notifyListeners();
  }

  /// Timestamped so ids stay unique across a restore that merges in records
  /// written by another install.
  String _id(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}-${_nextId++}';

  // ---------------------------------------------------------------- goals

  void setGoals(TrackerGoals goals) {
    if (goals == _data.goals) return;
    _data = _data.copyWith(goals: goals);
    _commit();
  }

  // ---------------------------------------------------------------- sleep

  SleepEntry? sleepOn(DateTime day) => _data.sleep[dateOnly(day)];

  void logSleep(SleepEntry entry) {
    _data = _data.copyWith(
      sleep: <DateTime, SleepEntry>{
        ..._data.sleep,
        dateOnly(entry.day): entry,
      },
    );
    _commit();
  }

  void clearSleep(DateTime day) {
    final key = dateOnly(day);
    if (!_data.sleep.containsKey(key)) return;
    _data = _data.copyWith(
      sleep: <DateTime, SleepEntry>{..._data.sleep}..remove(key),
    );
    _commit();
  }

  // ---------------------------------------------------------------- water

  int waterOn(DateTime day) => _data.water[dateOnly(day)] ?? 0;

  /// Adds [ml] to [day], never dropping below zero.
  void addWater(DateTime day, int ml) {
    final key = dateOnly(day);
    final next = (waterOn(key) + ml).clamp(0, 100000);
    _data = _data.copyWith(
      water: <DateTime, int>{..._data.water, key: next},
    );
    _commit();
  }

  void setWater(DateTime day, int ml) {
    final key = dateOnly(day);
    _data = _data.copyWith(
      water: <DateTime, int>{..._data.water, key: ml.clamp(0, 100000)},
    );
    _commit();
  }

  // -------------------------------------------------------------- reading

  ReadingSession addReading({
    required DateTime day,
    required String book,
    required int pages,
    required int minutes,
  }) {
    final session = ReadingSession(
      id: _id('read'),
      day: dateOnly(day),
      book: book.trim(),
      pages: pages,
      minutes: minutes,
    );
    _data = _data.copyWith(
      reading: <ReadingSession>[..._data.reading, session],
    );
    _commit();
    return session;
  }

  /// Removes a session and returns it with its position, so the caller can
  /// offer an undo — the same contract [HabitStore.remove] uses.
  ({ReadingSession session, int index})? removeReading(String id) {
    final index = _data.reading.indexWhere((s) => s.id == id);
    if (index == -1) return null;

    final next = <ReadingSession>[..._data.reading];
    final removed = next.removeAt(index);
    _data = _data.copyWith(reading: next);
    _commit();
    return (session: removed, index: index);
  }

  void insertReading(int index, ReadingSession session) {
    final next = <ReadingSession>[..._data.reading];
    next.insert(index.clamp(0, next.length), session);
    _data = _data.copyWith(reading: next);
    _commit();
  }

  /// Records how long a book is, so the finish estimate has something to aim at.
  void setBookLength(String book, int totalPages) {
    final key = book.trim().toLowerCase();
    if (key.isEmpty) return;

    final next = <String, int>{..._data.bookLengths};
    if (totalPages <= 0) {
      next.remove(key);
    } else {
      next[key] = totalPages;
    }
    _data = _data.copyWith(bookLengths: next);
    _commit();
  }

  int? bookLength(String? book) {
    if (book == null) return null;
    return _data.bookLengths[book.trim().toLowerCase()];
  }

  // ----------------------------------------------------------------- food

  FoodDay foodOn(DateTime day) {
    final key = dateOnly(day);
    return _data.food[key] ?? FoodDay(day: key);
  }

  Meal addMeal({
    required DateTime day,
    required int minutesFromMidnight,
    required MealType type,
    Set<FoodTag> tags = const <FoodTag>{},
    String note = '',
  }) {
    final meal = Meal(
      id: _id('meal'),
      minutesFromMidnight: minutesFromMidnight,
      type: type,
      tags: tags,
      note: note,
    );
    final key = dateOnly(day);
    _data = _data.copyWith(
      food: _foodWith(key, foodOn(key).withMeal(meal)),
    );
    _commit();
    return meal;
  }

  void removeMeal(DateTime day, String id) {
    final key = dateOnly(day);
    final next = foodOn(key).withoutMeal(id);
    _data = _data.copyWith(food: _foodWith(key, next));
    _commit();
  }

  /// A day with no meals left is removed rather than stored empty, so
  /// "days logged" counts days somebody actually recorded something on.
  Map<DateTime, FoodDay> _foodWith(DateTime key, FoodDay day) {
    final next = <DateTime, FoodDay>{..._data.food};
    if (day.meals.isEmpty) {
      next.remove(key);
    } else {
      next[key] = day;
    }
    return next;
  }

  // ---------------------------------------------------------------- focus

  RunningTimer? get runningTimer => _data.runningTimer;

  void startTimer({
    required FocusPhase phase,
    required int minutes,
    String tag = '',
    int completedFocusBlocks = 0,
  }) {
    _data = _data.copyWith(
      runningTimer: RunningTimer(
        phase: phase,
        startedAt: DateTime.now(),
        totalMinutes: minutes,
        completedFocusBlocks: completedFocusBlocks,
        tag: tag,
      ),
    );
    _commit();
  }

  /// Abandons the running timer without recording anything.
  void cancelTimer() {
    if (_data.runningTimer == null) return;
    _data = _data.copyWith(clearTimer: true);
    _commit();
  }

  /// Banks a finished focus phase and clears the timer.
  ///
  /// A break finishing records nothing: the log is of work done, and a screen
  /// showing "6 sessions" that counted three coffees would be worthless.
  /// Returns the session written, or null for a break.
  FocusSession? completeTimer() {
    final timer = _data.runningTimer;
    if (timer == null) return null;

    if (!timer.phase.isWork) {
      _data = _data.copyWith(clearTimer: true);
      _commit();
      return null;
    }

    final session = FocusSession(
      id: _id('focus'),
      day: dateOnly(timer.startedAt),
      startedAtMinutes: timer.startedAt.hour * 60 + timer.startedAt.minute,
      minutes: timer.totalMinutes,
      tag: timer.tag,
    );

    _data = _data.copyWith(
      focus: <FocusSession>[..._data.focus, session],
      clearTimer: true,
    );
    _commit();
    return session;
  }

  /// Logs a block of focus that happened away from the timer.
  FocusSession logFocus({
    required DateTime day,
    required int minutes,
    String tag = '',
    int? startedAtMinutes,
  }) {
    final now = DateTime.now();
    final session = FocusSession(
      id: _id('focus'),
      day: dateOnly(day),
      startedAtMinutes: startedAtMinutes ?? now.hour * 60 + now.minute,
      minutes: minutes,
      tag: tag.trim(),
    );
    _data = _data.copyWith(focus: <FocusSession>[..._data.focus, session]);
    _commit();
    return session;
  }

  void removeFocus(String id) {
    final next = _data.focus.where((s) => s.id != id).toList();
    if (next.length == _data.focus.length) return;
    _data = _data.copyWith(focus: next);
    _commit();
  }

  // -------------------------------------------------------------- fitness

  Workout addWorkout({
    required DateTime day,
    required WorkoutType type,
    required int minutes,
    Intensity intensity = Intensity.moderate,
    String note = '',
  }) {
    final workout = Workout(
      id: _id('workout'),
      day: dateOnly(day),
      type: type,
      minutes: minutes,
      intensity: intensity,
      note: note,
    );
    _data = _data.copyWith(workouts: <Workout>[..._data.workouts, workout]);
    _commit();
    return workout;
  }

  ({Workout workout, int index})? removeWorkout(String id) {
    final index = _data.workouts.indexWhere((w) => w.id == id);
    if (index == -1) return null;

    final next = <Workout>[..._data.workouts];
    final removed = next.removeAt(index);
    _data = _data.copyWith(workouts: next);
    _commit();
    return (workout: removed, index: index);
  }

  void insertWorkout(int index, Workout workout) {
    final next = <Workout>[..._data.workouts];
    next.insert(index.clamp(0, next.length), workout);
    _data = _data.copyWith(workouts: next);
    _commit();
  }

  // ----------------------------------------------------------------- data

  /// Swaps in a restored backup.
  void replaceAll(TrackerData data) {
    _data = data;
    _commit();
  }

  Future<void> clearAll() async {
    _data = const TrackerData();
    notifyListeners();
    await repository.saveTrackers(_data);
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
    await repository.saveTrackers(_data);
  }

  @override
  void dispose() {
    if (_saveTimer?.isActive ?? false) unawaited(flush());
    _saveTimer?.cancel();
    super.dispose();
  }
}

/// Exposes a [TrackerStore] to the subtree and rebuilds dependents on change.
class TrackerScope extends InheritedNotifier<TrackerStore> {
  const TrackerScope({
    super.key,
    required TrackerStore store,
    required super.child,
  }) : super(notifier: store);

  static TrackerStore of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<TrackerScope>();
    assert(scope?.notifier != null, 'No TrackerScope found above this widget');
    return scope!.notifier!;
  }
}
