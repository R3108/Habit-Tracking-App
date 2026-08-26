import 'package:flutter_test/flutter_test.dart';

import 'package:habit_tracker/data/app_repository.dart';
import 'package:habit_tracker/models/habit.dart';
import 'package:habit_tracker/models/lab/experiment.dart';
import 'package:habit_tracker/models/lab/experiment_data.dart';
import 'package:habit_tracker/state/experiment_store.dart';

import 'lab_fixtures.dart';

/// A finished 21-day trial: it ran up to and including yesterday.
Experiment finishedTrial({
  String id = 'e1',
  String habitId = 'h',
  int lengthDays = 21,
  int baselineDays = 42,
}) {
  return Experiment(
    id: id,
    habitId: habitId,
    change: 'Moved it to 6am',
    startDay: addDays(labReference, -lengthDays),
    lengthDays: lengthDays,
    baselineDays: baselineDays,
  );
}

void main() {
  group('the window', () {
    test('a trial that has not closed yet is still running', () {
      final experiment = Experiment(
        id: 'e',
        habitId: 'h',
        change: 'Moved it to 6am',
        startDay: addDays(labReference, -5),
      );

      expect(experiment.isComplete(reference: labReference), isFalse);
      expect(experiment.daysRemaining(reference: labReference), 16);
    });

    test('a trial that ran out yesterday is complete', () {
      final experiment = finishedTrial();

      expect(experiment.isComplete(reference: labReference), isTrue);
      expect(experiment.daysRemaining(reference: labReference), 0);
      expect(experiment.endDay, addDays(labReference, -1));
    });

    test('the baseline sits immediately before the trial', () {
      final experiment = finishedTrial();

      expect(experiment.baselineStart, addDays(labReference, -63));
      expect(
        experiment.startDay.difference(experiment.baselineStart).inDays,
        42,
      );
    });

    test('the length cannot be edited once it exists', () {
      final experiment = finishedTrial();
      final edited = experiment.copyWith(change: 'Something else');

      expect(edited.change, 'Something else');
      // The one thing copyWith deliberately refuses to carry a new value for.
      expect(edited.lengthDays, experiment.lengthDays);
      expect(edited.startDay, experiment.startDay);
    });
  });

  group('the verdict', () {
    test('a real improvement is called one', () {
      // 40% through the baseline, kept every day of the trial.
      final habit = labHabit(done: (age) => age <= 21 || age % 5 < 2);
      final result = ExperimentResult.of(
        finishedTrial(),
        habit,
        reference: labReference,
      );

      expect(result.verdict, ExperimentVerdict.helped);
      expect(result.isSignificant, isTrue);
      expect(result.trialPercent, 100);
      expect(result.baselinePercent, closeTo(40, 5));
      expect(result.summary, contains('larger than chance'));
    });

    test('a real decline is called one', () {
      // Kept through the baseline, dropped through the trial.
      final habit = labHabit(done: (age) => age > 21 && age % 5 < 4);
      final result = ExperimentResult.of(
        finishedTrial(),
        habit,
        reference: labReference,
      );

      expect(result.verdict, ExperimentVerdict.hurt);
      expect(result.difference, lessThan(0));
    });

    test('no change reads as no clear effect', () {
      final habit = labHabit(done: (age) => age % 2 == 0);
      final result = ExperimentResult.of(
        finishedTrial(),
        habit,
        reference: labReference,
      );

      expect(result.verdict, ExperimentVerdict.noEffect);
      expect(result.isSignificant, isFalse);
      expect(result.summary, contains('turns up by chance'));
    });

    test('a small change on few days is not mistaken for a finding', () {
      // 12 kept of 21 against 21 of 42 — a nine-point gap on a thin sample.
      final habit = labHabit(
        done: (age) => age <= 21 ? age % 7 < 4 : age % 2 == 0,
      );
      final result = ExperimentResult.of(
        finishedTrial(),
        habit,
        reference: labReference,
      );

      expect(result.verdict, ExperimentVerdict.noEffect);
      // The interval straddles zero, which is the honest way to say it.
      expect(result.differenceLow, lessThan(0));
      expect(result.differenceHigh, greaterThan(0));
    });

    test('too few due days each side declines to answer', () {
      // Mondays only: three due days inside a 21-day trial.
      final habit = labHabit(
        done: (age) => true,
        schedule: const HabitSchedule.onDays({1}),
      );
      final result = ExperimentResult.of(
        finishedTrial(),
        habit,
        reference: labReference,
      );

      expect(result.verdict, ExperimentVerdict.inconclusive);
      expect(result.pValue, isNull);
      expect(result.intervalText, contains('Not enough due days'));
    });

    test('a running trial is never scored early', () {
      final experiment = Experiment(
        id: 'e',
        habitId: 'h',
        change: 'Moved it to 6am',
        startDay: addDays(labReference, -5),
      );
      // A trial going spectacularly well so far.
      final habit = labHabit(done: (age) => age <= 5 || age % 5 < 2);

      final result = ExperimentResult.of(
        experiment,
        habit,
        reference: labReference,
      );

      expect(result.verdict, ExperimentVerdict.running);
      expect(result.pValue, isNull);
      expect(result.progress, greaterThan(0));
      expect(result.progress, lessThan(1));
      expect(result.summary, contains('days left'));
    });

    test('an abandoned trial is never scored at all', () {
      final habit = labHabit(done: (age) => age <= 21 || age % 5 < 2);
      final result = ExperimentResult.of(
        finishedTrial().copyWith(abandoned: true),
        habit,
        reference: labReference,
      );

      expect(result.verdict, ExperimentVerdict.running);
      expect(result.pValue, isNull);
    });
  });

  group('the interval', () {
    test('brackets the observed difference', () {
      final habit = labHabit(done: (age) => age <= 21 || age % 5 < 2);
      final result = ExperimentResult.of(
        finishedTrial(),
        habit,
        reference: labReference,
      );

      expect(result.differenceLow, lessThan(result.difference));
      expect(result.differenceHigh, greaterThan(result.difference));
      expect(result.intervalText, contains('points'));
    });

    test('a decisive result keeps the whole interval on one side of zero', () {
      final habit = labHabit(done: (age) => age <= 21 || age % 5 < 2);
      final result = ExperimentResult.of(
        finishedTrial(),
        habit,
        reference: labReference,
      );

      expect(result.differenceLow, greaterThan(0));
    });
  });

  group('storage', () {
    test('an experiment survives a round trip', () {
      final original = finishedTrial(id: 'x', habitId: 'run');
      final restored = Experiment.fromJson(original.toJson());

      expect(restored.id, 'x');
      expect(restored.habitId, 'run');
      expect(restored.change, original.change);
      expect(restored.startDay, original.startDay);
      expect(restored.lengthDays, original.lengthDays);
      expect(restored.baselineDays, original.baselineDays);
      expect(restored.abandoned, isFalse);
    });

    test('a list survives the envelope', () {
      final restored = decodeExperiments(
        encodeExperiments(<Experiment>[
          finishedTrial(id: 'a'),
          finishedTrial(id: 'b').copyWith(abandoned: true),
        ]),
      );

      expect(restored, hasLength(2));
      expect(restored!.map((e) => e.id), <String>['a', 'b']);
      expect(restored.last.abandoned, isTrue);
    });

    test('unreadable payloads are null rather than a crash', () {
      expect(decodeExperiments(null), isNull);
      expect(decodeExperiments(''), isNull);
      expect(decodeExperiments('not json'), isNull);
      expect(decodeExperiments('{"version":99,"experiments":[]}'), isNull);
    });
  });

  group('the store', () {
    late InMemoryAppRepository repository;
    late ExperimentStore store;

    setUp(() {
      repository = InMemoryAppRepository();
      store = ExperimentStore(
        repository: repository,
        saveDebounce: Duration.zero,
      );
    });

    test('starts empty and never seeds anything', () async {
      await store.load();

      expect(store.isEmpty, isTrue);
      expect(store.isLoading, isFalse);
    });

    test('a started run is persisted and reads as running', () async {
      await store.load();
      store.start(habitId: 'h', change: 'Earlier', lengthDays: 14);
      await store.flush();

      expect(repository.experiments, hasLength(1));
      expect(store.running(), hasLength(1));
      expect(store.finished(), isEmpty);
      expect(store.hasRunning('h'), isTrue);
      expect(store.hasRunning('other'), isFalse);
    });

    test('abandoning keeps the record', () async {
      await store.load();
      final experiment = store.start(habitId: 'h', change: 'Earlier');
      store.abandon(experiment.id);
      await store.flush();

      expect(store.all, hasLength(1));
      expect(store.byId(experiment.id)?.abandoned, isTrue);
      // Abandoned runs are neither running nor scoreable.
      expect(store.running(), isEmpty);
      expect(store.finished(), isEmpty);
    });

    test('a removal can be undone', () async {
      await store.load();
      final experiment = store.start(habitId: 'h', change: 'Earlier');

      final removed = store.remove(experiment.id);
      expect(removed, isNotNull);
      expect(store.isEmpty, isTrue);

      store.insert(removed!.index, removed.experiment);
      expect(store.all, hasLength(1));
      expect(store.byId(experiment.id), isNotNull);
    });

    test('runs whose habit is gone are pruned', () async {
      await store.load();
      store.start(habitId: 'kept', change: 'A');
      store.start(habitId: 'deleted', change: 'B');

      store.pruneOrphans(<Habit>[labHabit(done: (_) => true, id: 'kept')]);

      expect(store.all, hasLength(1));
      expect(store.all.single.habitId, 'kept');
    });

    test('the newest run sorts first', () async {
      await store.load();
      store.start(
        habitId: 'h',
        change: 'Older',
        startDay: addDays(labReference, -60),
      );
      store.start(
        habitId: 'g',
        change: 'Newer',
        startDay: addDays(labReference, -2),
      );

      expect(store.all.first.change, 'Newer');
    });

    test('clearing wipes the log on disk too', () async {
      await store.load();
      store.start(habitId: 'h', change: 'Earlier');
      await store.flush();
      await store.clearAll();

      expect(store.isEmpty, isTrue);
      expect(repository.experiments, isEmpty);
    });
  });
}
