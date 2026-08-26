import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../habit.dart';

/// The odds of reaching a particular streak, and how long it is likely to take.
@immutable
class StreakProjection {
  const StreakProjection._({
    required this.target,
    required this.probability,
    required this.medianDays,
    required this.optimisticDays,
  });

  /// The streak length being aimed at.
  final int target;

  /// Chance of getting there inside the horizon, in 0..1.
  final double probability;

  /// Calendar days to the median arrival, or null when fewer than half the
  /// simulated futures got there at all.
  ///
  /// Null is the honest answer in that case. Reporting the median of only the
  /// runs that succeeded would answer "how long does it take when it works",
  /// which is a different and much rosier question than the one being asked.
  final int? medianDays;

  /// Calendar days to the 10th-percentile arrival — the good run.
  final int? optimisticDays;

  int get percent => (probability * 100).round();

  bool get isLikely => probability >= 0.5;
}

/// Where a habit is heading, simulated forward from its own history.
///
/// The forecast answers "will this happen today". This answers the questions
/// that live further out — will the current run survive the month, when does a
/// hundred-day streak actually arrive, how many completions is the next quarter
/// worth — and those cannot be read off a single day's odds, because streaks
/// are path-dependent. A habit kept 80% of the time reaches a 30-day streak
/// readily if its misses are isolated and almost never if they arrive in
/// clusters, and the difference between those two histories is invisible to any
/// average.
///
/// So the simulation is a two-state Markov chain rather than a coin flip: the
/// chance of keeping the habit depends on whether the previous due day was
/// kept. Those two rates are estimated from the habit's own history, shrunk
/// toward its base rate so a thin sample cannot produce a dramatic claim, and
/// then several thousand futures are rolled forward day by day, honouring the
/// real schedule.
///
/// What it deliberately does *not* model: that the user might read this and act
/// differently, that January is not October, that the reason for a slump could
/// still be present. It is an extrapolation of the past, and the UI says so.
@immutable
class HabitProjection {
  const HabitProjection._({
    required this.habitId,
    required this.afterKept,
    required this.afterMissed,
    required this.baseRate,
    required this.dueDaysObserved,
    required this.currentStreak,
    required this.expectedCompletions,
    required this.holdProbability,
    required this.nextMilestone,
  });

  final String habitId;

  /// Chance of keeping it, given the previous due day was kept.
  final double afterKept;

  /// Chance of keeping it, given the previous due day was missed.
  final double afterMissed;

  /// The plain completion rate the two above were shrunk toward.
  final double baseRate;

  /// Due days the estimates were fitted on.
  final int dueDaysObserved;

  final int currentStreak;

  /// Completions expected over the next [horizonDays].
  final double expectedCompletions;

  /// Chance the current streak is still unbroken in [holdDays].
  ///
  /// Zero when there is no streak to hold — there is nothing to say about
  /// keeping a run that hasn't started.
  final double holdProbability;

  /// The next round-number streak worth aiming at.
  ///
  /// Null when there isn't one that could arrive inside [horizonDays] — either
  /// the habit is past the last milestone, or the next one is further away than
  /// a perfect run could reach.
  final StreakProjection? nextMilestone;

  /// How far forward the simulation runs.
  static const int horizonDays = 90;

  /// The window [holdProbability] asks about.
  static const int holdDays = 30;

  /// How far back the fit looks.
  static const int windowDays = 180;

  /// Futures rolled per question.
  ///
  /// Enough that the reported percentage is stable to about a point, which is
  /// all the precision a percentage on a card can carry anyway, and cheap
  /// enough that a list of habits projects in a few milliseconds.
  static const int _trials = 1500;

  /// Pseudo-counts each transition rate is shrunk toward the base rate with.
  static const double _shrinkage = 5;

  /// Due days needed before the two transition rates mean anything.
  static const int _minimumDueDays = 12;

  /// Streaks worth naming. Past the last one, the habit has made its point.
  static const List<int> milestones = <int>[7, 14, 30, 60, 100, 180, 365];

  bool get hasEnoughHistory => dueDaysObserved >= _minimumDueDays;

  /// True when a miss tends to be followed by another.
  ///
  /// The single fact this class knows that no average does. Worth surfacing
  /// on its own: it is the difference between "protect the streak" being
  /// motivational fluff and being the correct advice.
  bool get missesCluster => hasEnoughHistory && afterMissed < afterKept - 0.15;

  /// Fits and simulates [habit] as of [reference] (default today).
  ///
  /// [seed] fixes the random stream. It defaults to a constant so that the same
  /// history always projects to the same numbers — a card whose percentage
  /// flickered on every rebuild would look broken, and would be.
  factory HabitProjection.of(
    Habit habit, {
    DateTime? reference,
    int seed = 0x5EED,
  }) {
    final today = dateOnly(reference ?? DateTime.now());

    // Oldest first; today excluded, since it may not have happened yet.
    final history = <DateTime>[
      for (var age = windowDays; age >= 1; age--)
        if (habit.isDueOn(addDays(today, -age))) addDays(today, -age),
    ];

    var kept = 0;
    for (final day in history) {
      if (habit.isCompletedOn(day)) kept++;
    }
    // Laplace prior at 50%, matching the rest of the app's estimators.
    final base = history.isEmpty
        ? 0.5
        : ((kept + 1) / (history.length + 2)).clamp(0.02, 0.98);

    final transitions = _transitions(habit, history, base);
    final streak = habit.streakAsOf(today);

    // The chain's starting state: what happened on the most recent due day that
    // has actually resolved. Today counts only if it is already done — an
    // unticked morning is not yet a miss.
    final startKept = habit.isCompletedOn(today)
        ? true
        : (history.isEmpty ? true : habit.isCompletedOn(history.last));

    // The schedule for the horizon, resolved once. Asking the schedule inside
    // the trial loop instead would build a [DateTime] on every one of the
    // hundred-odd thousand steps below, which dominated the whole simulation
    // when it was written that way.
    //
    // Future skips are unknowable, so the schedule alone decides. Using
    // isDueOn would fold in today's skip set, which says nothing about whether
    // the user will take a day off in six weeks.
    final dueOnOffset = <bool>[
      for (var offset = 1; offset <= horizonDays; offset++)
        habit.schedule.isDueOn(addDays(today, offset)),
    ];

    final rng = math.Random(seed);
    final sim = _simulate(
      dueOnOffset: dueOnOffset,
      afterKept: transitions.afterKept,
      afterMissed: transitions.afterMissed,
      startKept: startKept,
      startStreak: streak,
      rng: rng,
    );

    // The next milestone worth naming is the next one that could actually
    // arrive inside the horizon. A habit on a 200-day run has 365 ahead of it
    // and no way to get there in ninety days, and reporting "365-day streak: 0%
    // likely" would be technically true and completely useless — the honest
    // answer there is that there is nothing to aim at yet.
    var reachableDueDays = 0;
    for (var offset = 1; offset <= horizonDays; offset++) {
      if (habit.schedule.isDueOn(addDays(today, offset))) reachableDueDays++;
    }
    final ceiling = streak + reachableDueDays;

    final target = milestones.firstWhere(
      (m) => m > streak && m <= ceiling,
      orElse: () => -1,
    );

    return HabitProjection._(
      habitId: habit.id,
      afterKept: transitions.afterKept,
      afterMissed: transitions.afterMissed,
      baseRate: base,
      dueDaysObserved: history.length,
      currentStreak: streak,
      expectedCompletions: sim.expectedCompletions,
      holdProbability: streak == 0 ? 0 : sim.holdProbability,
      nextMilestone: target == -1
          ? null
          : _projectTarget(target, sim.daysToStreak[target]!),
    );
  }

  /// The two transition rates, each shrunk toward [base].
  ///
  /// Consecutive due days only, and only when they are genuinely adjacent: a
  /// gap of more than eight days means the run was over regardless of what
  /// happened, and pairing across it would invent a transition nobody made.
  static ({double afterKept, double afterMissed}) _transitions(
    Habit habit,
    List<DateTime> history,
    double base,
  ) {
    var keptAfterKept = 0, totalAfterKept = 0;
    var keptAfterMissed = 0, totalAfterMissed = 0;

    for (var i = 1; i < history.length; i++) {
      if (history[i].difference(history[i - 1]).inDays > 8) continue;
      final previous = habit.isCompletedOn(history[i - 1]);
      final current = habit.isCompletedOn(history[i]);

      if (previous) {
        totalAfterKept++;
        if (current) keptAfterKept++;
      } else {
        totalAfterMissed++;
        if (current) keptAfterMissed++;
      }
    }

    double shrink(int hits, int total) =>
        ((hits + _shrinkage * base) / (total + _shrinkage)).clamp(0.02, 0.98);

    return (
      afterKept: shrink(keptAfterKept, totalAfterKept),
      afterMissed: shrink(keptAfterMissed, totalAfterMissed),
    );
  }

  /// Rolls [_trials] futures and collects every answer in one pass.
  ///
  /// One pass rather than one per question: the walk is the expensive part, and
  /// re-running it for each milestone would multiply the cost for no gain.
  static _SimulationResult _simulate({
    required List<bool> dueOnOffset,
    required double afterKept,
    required double afterMissed,
    required bool startKept,
    required int startStreak,
    required math.Random rng,
  }) {
    final daysTo = <int, List<int>>{
      for (final m in milestones)
        if (m > startStreak) m: <int>[],
    };
    var completionsTotal = 0;
    var heldTotal = 0;

    for (var trial = 0; trial < _trials; trial++) {
      var streak = startStreak;
      var lastKept = startKept;
      var completions = 0;
      var stillHolding = true;
      final hit = <int>{};

      for (var offset = 1; offset <= horizonDays; offset++) {
        if (!dueOnOffset[offset - 1]) continue;

        final p = lastKept ? afterKept : afterMissed;
        final success = rng.nextDouble() < p;

        if (success) {
          streak++;
          completions++;
          lastKept = true;
          for (final target in daysTo.keys) {
            if (streak >= target && hit.add(target)) {
              daysTo[target]!.add(offset);
            }
          }
        } else {
          streak = 0;
          lastKept = false;
          if (offset <= holdDays) stillHolding = false;
        }
      }

      completionsTotal += completions;
      if (stillHolding) heldTotal++;
    }

    // Runs that never got there are recorded as "beyond the horizon" so the
    // percentiles below are taken over all futures rather than the lucky ones.
    final padded = <int, List<int>>{};
    for (final entry in daysTo.entries) {
      final list = List<int>.of(entry.value)
        ..addAll(
          List<int>.filled(_trials - entry.value.length, horizonDays + 1),
        )
        ..sort();
      padded[entry.key] = list;
    }

    return _SimulationResult(
      daysToStreak: padded,
      expectedCompletions: completionsTotal / _trials,
      holdProbability: heldTotal / _trials,
    );
  }

  static StreakProjection _projectTarget(int target, List<int> sortedDays) {
    int? percentile(double q) {
      if (sortedDays.isEmpty) return null;
      final index = ((sortedDays.length - 1) * q).round();
      final value = sortedDays[index];
      return value > horizonDays ? null : value;
    }

    var reached = 0;
    for (final day in sortedDays) {
      if (day <= horizonDays) reached++;
    }

    return StreakProjection._(
      target: target,
      probability: sortedDays.isEmpty ? 0 : reached / sortedDays.length,
      medianDays: percentile(0.5),
      optimisticDays: percentile(0.1),
    );
  }
}

/// Everything one batch of simulated futures answers.
@immutable
class _SimulationResult {
  const _SimulationResult({
    required this.daysToStreak,
    required this.expectedCompletions,
    required this.holdProbability,
  });

  /// Milestone → sorted days-to-arrival across every trial, with futures that
  /// never arrived padded past the horizon.
  final Map<int, List<int>> daysToStreak;
  final double expectedCompletions;
  final double holdProbability;
}

/// Projects every active habit, most fragile run first.
///
/// Ordered by how likely the current streak is to break, because a run about to
/// be lost is the only thing on this screen that is urgent.
List<HabitProjection> projectHabits(
  List<Habit> habits, {
  DateTime? reference,
  int seed = 0x5EED,
}) {
  final out = <HabitProjection>[
    for (final habit in habits)
      if (!habit.archived)
        HabitProjection.of(habit, reference: reference, seed: seed),
  ]..sort((a, b) {
    // Habits with a live streak first, weakest hold at the top; then the rest
    // by how much is expected of them.
    final aHas = a.currentStreak > 0, bHas = b.currentStreak > 0;
    if (aHas != bHas) return aHas ? -1 : 1;
    if (aHas && bHas) return a.holdProbability.compareTo(b.holdProbability);
    return b.expectedCompletions.compareTo(a.expectedCompletions);
  });

  return List<HabitProjection>.unmodifiable(out);
}
