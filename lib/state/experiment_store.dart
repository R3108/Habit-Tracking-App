import 'dart:async';

import 'package:flutter/material.dart';

import '../data/app_repository.dart';
import '../models/habit.dart';
import '../models/lab/experiment.dart';

/// Owns the experiment log and its persistence.
///
/// Mirrors [HabitStore]: synchronous in memory, debounced to disk. The list is
/// small — a user runs a handful of these a year, not a hundred — so it is kept
/// whole in memory and rewritten entirely on each change.
class ExperimentStore extends ChangeNotifier {
  ExperimentStore({
    required this.repository,
    List<Experiment>? experiments,
    this.saveDebounce = const Duration(milliseconds: 350),
  }) : _experiments = experiments == null
           ? <Experiment>[]
           : List<Experiment>.of(experiments);

  final AppRepository repository;

  /// How long to batch rapid edits before writing. Zero in tests.
  final Duration saveDebounce;

  final List<Experiment> _experiments;
  Timer? _saveTimer;
  var _nextId = 0;
  var _isLoading = true;

  bool get isLoading => _isLoading;

  /// Everything ever run, newest start date first.
  ///
  /// Abandoned runs are included: hiding them would make the visible set a
  /// filtered sample, which is the bias the feature exists to avoid.
  List<Experiment> get all {
    final sorted = List<Experiment>.of(_experiments)
      ..sort((a, b) => b.startDay.compareTo(a.startDay));
    return List<Experiment>.unmodifiable(sorted);
  }

  bool get isEmpty => _experiments.isEmpty;

  Experiment? byId(String id) {
    for (final experiment in _experiments) {
      if (experiment.id == id) return experiment;
    }
    return null;
  }

  /// The runs still inside their trial window.
  List<Experiment> running({DateTime? reference}) => List.unmodifiable(
    all.where(
      (e) => !e.abandoned && !e.isComplete(reference: reference),
    ),
  );

  /// The runs that have finished and can be judged.
  List<Experiment> finished({DateTime? reference}) => List.unmodifiable(
    all.where((e) => !e.abandoned && e.isComplete(reference: reference)),
  );

  /// Whether [habitId] already has a run in flight.
  ///
  /// Two overlapping experiments on one habit cannot both be measured — each
  /// would be the other's uncontrolled variable, and the baseline of the second
  /// would be contaminated by the first.
  bool hasRunning(String habitId, {DateTime? reference}) =>
      running(reference: reference).any((e) => e.habitId == habitId);

  Future<void> load() async {
    final stored = await repository.loadExperiments();
    _experiments
      ..clear()
      ..addAll(stored ?? const <Experiment>[]);
    _nextId = _experiments.length;
    _isLoading = false;
    notifyListeners();
  }

  /// Starts a run. [startDay] defaults to today.
  Experiment start({
    required String habitId,
    required String change,
    DateTime? startDay,
    int lengthDays = 21,
    int baselineDays = 42,
    String note = '',
  }) {
    final experiment = Experiment(
      id: 'experiment-${DateTime.now().microsecondsSinceEpoch}-${_nextId++}',
      habitId: habitId,
      change: change,
      startDay: startDay ?? DateTime.now(),
      lengthDays: lengthDays.clamp(
        Experiment.minimumLength,
        Experiment.maximumLength,
      ),
      baselineDays: baselineDays.clamp(7, 365),
      note: note,
    );
    _experiments.add(experiment);
    _commit();
    return experiment;
  }

  /// Ends a run without a verdict.
  ///
  /// The record stays. An abandoned experiment is evidence about the change
  /// being tried — usually that it was unworkable — and deleting it would erase
  /// that while making every surviving run look more successful than the set
  /// really was.
  void abandon(String id) {
    _mutate(id, (experiment) => experiment.copyWith(abandoned: true));
  }

  void setNote(String id, String note) {
    _mutate(id, (experiment) => experiment.copyWith(note: note));
  }

  /// Removes a run entirely, returning it with its position so the caller can
  /// offer an undo.
  ({Experiment experiment, int index})? remove(String id) {
    final index = _experiments.indexWhere((e) => e.id == id);
    if (index == -1) return null;
    final removed = _experiments.removeAt(index);
    _commit();
    return (experiment: removed, index: index);
  }

  void insert(int index, Experiment experiment) {
    _experiments.insert(index.clamp(0, _experiments.length), experiment);
    _commit();
  }

  /// Swaps in a restored backup.
  void replaceAll(List<Experiment> experiments) {
    _experiments
      ..clear()
      ..addAll(experiments);
    _nextId = _experiments.length;
    _commit();
  }

  /// Drops runs whose habit no longer exists.
  ///
  /// An experiment is measured against its habit's history, so one whose habit
  /// was deleted can never be scored again — it is not a record any more, just
  /// a row that will always read "not enough data".
  void pruneOrphans(List<Habit> habits) {
    final ids = <String>{for (final habit in habits) habit.id};
    final before = _experiments.length;
    _experiments.removeWhere((e) => !ids.contains(e.habitId));
    if (_experiments.length != before) _commit();
  }

  Future<void> clearAll() async {
    _experiments.clear();
    _nextId = 0;
    notifyListeners();
    await repository.saveExperiments(const <Experiment>[]);
  }

  void _mutate(String id, Experiment Function(Experiment) change) {
    final index = _experiments.indexWhere((e) => e.id == id);
    if (index == -1) return;
    _experiments[index] = change(_experiments[index]);
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
    await repository.saveExperiments(_experiments);
  }

  @override
  void dispose() {
    if (_saveTimer?.isActive ?? false) unawaited(flush());
    _saveTimer?.cancel();
    super.dispose();
  }
}

/// Exposes an [ExperimentStore] to the subtree and rebuilds dependents on
/// change.
class ExperimentScope extends InheritedNotifier<ExperimentStore> {
  const ExperimentScope({
    super.key,
    required ExperimentStore store,
    required super.child,
  }) : super(notifier: store);

  static ExperimentStore of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<ExperimentScope>();
    assert(scope?.notifier != null, 'No ExperimentScope found above this widget');
    return scope!.notifier!;
  }
}
