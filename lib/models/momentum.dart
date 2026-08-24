import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'habit.dart';

/// Which way a habit's momentum has moved over the last week.
enum MomentumTrend { rising, steady, falling }

/// How much attention a habit wants today.
enum HabitRisk {
  /// Nothing to flag.
  none,

  /// Slipping, but nothing is on the line today.
  watch,

  /// Due today, still unticked, and a real streak rides on it.
  atRisk,
}

/// A recency-weighted read on how a single habit is actually going.
///
/// The 30-day completion rate elsewhere in the app answers "how much of the
/// last month did I do?", which is the right question for a report and the
/// wrong one for a nudge: a habit kept perfectly for three weeks and then
/// dropped for nine days still reads as a healthy 70%. Momentum weights recent
/// due days far more heavily than old ones, so the same history reads as a
/// collapse — which is what the user needs to hear while it is still fixable.
///
/// Only *due* days are weighed. A Mon/Wed/Fri habit is not punished for the
/// weekend, and a day the user planned off is invisible here exactly as it is
/// to the streak.
@immutable
class HabitMomentum {
  const HabitMomentum._({
    required this.habitId,
    required this.score,
    required this.delta,
    required this.evidence,
    required this.streak,
    required this.dueToday,
    required this.doneToday,
  });

  final String habitId;

  /// Recency-weighted share of due days completed, in 0..1.
  final double score;

  /// [score] minus the same measure taken a week ago.
  final double delta;

  /// Total weight behind [score], in units of "due days at full weight".
  ///
  /// A habit three days old has almost no evidence, and a score built on two
  /// due days should not be allowed to announce a trend. Readers gate on
  /// [hasEnoughHistory] rather than reading this directly.
  final double evidence;

  final int streak;
  final bool dueToday;
  final bool doneToday;

  /// How far back the weighting looks.
  static const int windowDays = 60;

  /// Days after which a due day counts for half as much.
  ///
  /// Ten days means roughly the last fortnight dominates while the month before
  /// it still registers — short enough to react inside a bad week, long enough
  /// that one missed Tuesday doesn't cry wolf.
  static const double halfLifeDays = 10;

  /// Below this much weight the score is noise rather than a signal.
  static const double _minimumEvidence = 3;

  bool get hasEnoughHistory => evidence >= _minimumEvidence;

  MomentumTrend get trend {
    if (!hasEnoughHistory) return MomentumTrend.steady;
    if (delta >= 0.07) return MomentumTrend.rising;
    if (delta <= -0.07) return MomentumTrend.falling;
    return MomentumTrend.steady;
  }

  HabitRisk get risk {
    // A live streak on an unticked due day outranks everything: it is the one
    // case where acting today changes the outcome.
    if (dueToday && !doneToday && streak >= 3) return HabitRisk.atRisk;
    if (!hasEnoughHistory) return HabitRisk.none;
    if (trend == MomentumTrend.falling && score < 0.7) return HabitRisk.watch;
    if (score < 0.35) return HabitRisk.watch;
    return HabitRisk.none;
  }

  /// Score as a percentage, for display.
  int get percent => (score * 100).round();

  /// One line explaining why this habit is being flagged, or null when it is
  /// not. Written for a card, so it names the stake rather than the metric.
  String? get reason => switch (risk) {
    HabitRisk.atRisk => '$streak-day streak on the line',
    HabitRisk.watch when trend == MomentumTrend.falling =>
      'Down ${(delta.abs() * 100).round()} points this week',
    HabitRisk.watch => 'Only $percent% of due days lately',
    HabitRisk.none => null,
  };

  /// Sorts the most pressing first: at-risk before watch, then by how far the
  /// habit has fallen.
  static int compareByUrgency(HabitMomentum a, HabitMomentum b) {
    final byRisk = b.risk.index.compareTo(a.risk.index);
    if (byRisk != 0) return byRisk;
    final byStreak = b.streak.compareTo(a.streak);
    if (a.risk == HabitRisk.atRisk && byStreak != 0) return byStreak;
    return a.score.compareTo(b.score);
  }

  /// Measures [habit] as of [reference] (default today).
  factory HabitMomentum.of(Habit habit, {DateTime? reference}) {
    final today = dateOnly(reference ?? DateTime.now());
    final current = _weigh(habit, today);
    // The comparison point is the same calculation run a week earlier, so the
    // delta reflects a real change in behaviour rather than the window sliding.
    final previous = _weigh(habit, addDays(today, -7));

    return HabitMomentum._(
      habitId: habit.id,
      score: current.score,
      delta: previous.evidence >= _minimumEvidence
          ? current.score - previous.score
          : 0,
      evidence: current.evidence,
      streak: habit.streakAsOf(today),
      dueToday: habit.isDueOn(today),
      doneToday: habit.isCompletedOn(today),
    );
  }

  /// Weighted completion over the [windowDays] due days ending at [asOf].
  static ({double score, double evidence}) _weigh(Habit habit, DateTime asOf) {
    var weightedDue = 0.0;
    var weightedDone = 0.0;

    for (var age = 0; age < windowDays; age++) {
      final day = addDays(asOf, -age);
      if (!habit.isDueOn(day)) continue;

      final weight = math.pow(0.5, age / halfLifeDays).toDouble();
      weightedDue += weight;
      if (habit.isCompletedOn(day)) weightedDone += weight;
    }

    if (weightedDue == 0) return (score: 0, evidence: 0);
    return (score: weightedDone / weightedDue, evidence: weightedDue);
  }
}

/// Momentum for every habit in [habits], in the same order.
List<HabitMomentum> momentumFor(List<Habit> habits, {DateTime? reference}) =>
    <HabitMomentum>[
      for (final habit in habits)
        HabitMomentum.of(habit, reference: reference),
    ];

/// The habits worth surfacing on the home screen today, most pressing first.
///
/// Capped rather than exhaustive: a "focus" list that shows six things is a
/// second checklist, and the user already has one of those below it.
List<HabitMomentum> focusList(
  List<Habit> habits, {
  DateTime? reference,
  int limit = 3,
}) {
  final flagged =
      momentumFor(habits, reference: reference)
          .where((m) => m.risk != HabitRisk.none)
          .toList()
        ..sort(HabitMomentum.compareByUrgency);

  return flagged.take(limit).toList();
}
