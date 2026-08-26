import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../habit.dart';

/// A date where a habit's completion rate genuinely changed level.
///
/// Not a dip, not a bad fortnight — a shift big enough and lasting enough that
/// describing the history with one rate before it and another after it fits
/// substantially better than describing it with a single rate throughout.
@immutable
class TurningPoint {
  const TurningPoint._({
    required this.habitId,
    required this.day,
    required this.beforeRate,
    required this.afterRate,
    required this.beforeDays,
    required this.afterDays,
    required this.statistic,
  });

  final String habitId;

  /// The first due day that belongs to the *new* level.
  final DateTime day;

  final double beforeRate;
  final double afterRate;

  /// Due days on each side, which is what the two rates were measured over.
  final int beforeDays;
  final int afterDays;

  /// The likelihood-ratio statistic behind the split. Higher is stronger
  /// evidence; see [_thresholdFor] for what counts as enough.
  final double statistic;

  bool get isImprovement => afterRate > beforeRate;

  /// Size of the shift in percentage points, always positive.
  int get swing => ((afterRate - beforeRate).abs() * 100).round();

  int get beforePercent => (beforeRate * 100).round();
  int get afterPercent => (afterRate * 100).round();

  /// How the change reads in a sentence.
  String get description => isImprovement
      ? 'Picked up from $beforePercent% to $afterPercent%'
      : 'Dropped from $beforePercent% to $afterPercent%';
}

/// Finds the dates a habit changed level, strongest evidence first.
///
/// This is binary segmentation over the habit's own due days, treating each as
/// a Bernoulli trial. For every candidate split the fit of "one rate for the
/// whole span" is compared against "one rate before, another after" by
/// likelihood ratio; the best split is kept if it clears [_thresholdFor], and
/// the two halves are then searched recursively.
///
/// Why this rather than a rolling average, which is far easier to write and to
/// draw: a rolling average always moves, so a person reading one will always
/// find a story in it. This answers a narrower question with a defensible
/// no — most habits have no turning points, and returning an empty list for
/// them is the feature working, not failing.
///
/// Three guards keep it honest:
///
/// 1. **A search-corrected threshold.** Testing ~n candidate positions and
///    keeping the best would manufacture change points out of coin flips, so
///    the bar rises with the number of positions searched.
/// 2. **A minimum segment.** A "level" measured over six days is not a level.
/// 3. **A minimum swing.** A statistically real shift from 71% to 78% is not
///    something anybody needs to be told about.
List<TurningPoint> findTurningPoints(
  Habit habit, {
  DateTime? reference,
  int windowDays = 365,
  int maxPoints = 3,
}) {
  final today = dateOnly(reference ?? DateTime.now());

  // Oldest first. Today is excluded: it may not have happened yet.
  final days = <DateTime>[
    for (var age = windowDays; age >= 1; age--)
      if (habit.isDueOn(addDays(today, -age))) addDays(today, -age),
  ];

  if (days.length < _minimumSegment * 2) return const <TurningPoint>[];

  final kept = <bool>[for (final day in days) habit.isCompletedOn(day)];

  // Prefix sums so any segment's success count is a single subtraction; the
  // recursion below is otherwise quadratic for no reason.
  final prefix = List<int>.filled(kept.length + 1, 0);
  for (var i = 0; i < kept.length; i++) {
    prefix[i + 1] = prefix[i] + (kept[i] ? 1 : 0);
  }

  final found = <TurningPoint>[];
  _segment(
    habit: habit,
    days: days,
    prefix: prefix,
    lo: 0,
    hi: kept.length,
    total: kept.length,
    out: found,
    budget: maxPoints,
  );

  found.sort((a, b) => b.statistic.compareTo(a.statistic));
  return List<TurningPoint>.unmodifiable(found.take(maxPoints));
}

/// Due days a level has to span before it is called a level.
const int _minimumSegment = 12;

/// Percentage points a shift must move before it is worth reporting.
const double _minimumSwing = 0.20;

/// The bar a split must clear, given how many positions were searched.
///
/// The base is the 99.9th percentile of chi-squared with one degree of freedom,
/// which is what the likelihood ratio is distributed as under "no change here".
/// The `2 * ln(n)` term is the price of having looked at n places for the best
/// one — without it, the maximum of many noisy statistics clears any fixed bar
/// routinely, which is the classic way change-point detectors end up finding
/// change points in pure noise.
double _thresholdFor(int n) => 10.83 + 2 * math.log(math.max(n, 2));

void _segment({
  required Habit habit,
  required List<DateTime> days,
  required List<int> prefix,
  required int lo,
  required int hi,
  required int total,
  required List<TurningPoint> out,
  required int budget,
}) {
  if (budget <= 0) return;
  final n = hi - lo;
  if (n < _minimumSegment * 2) return;

  final whole = _logLikelihood(prefix, lo, hi);

  var bestStat = 0.0;
  var bestSplit = -1;

  // Every split that leaves a real segment on both sides.
  for (var split = lo + _minimumSegment; split <= hi - _minimumSegment; split++) {
    final stat =
        2 *
        (_logLikelihood(prefix, lo, split) +
            _logLikelihood(prefix, split, hi) -
            whole);
    if (stat > bestStat) {
      bestStat = stat;
      bestSplit = split;
    }
  }

  if (bestSplit < 0 || bestStat < _thresholdFor(total)) return;

  final beforeRate = _rate(prefix, lo, bestSplit);
  final afterRate = _rate(prefix, bestSplit, hi);
  if ((afterRate - beforeRate).abs() < _minimumSwing) return;

  out.add(
    TurningPoint._(
      habitId: habit.id,
      day: days[bestSplit],
      beforeRate: beforeRate,
      afterRate: afterRate,
      beforeDays: bestSplit - lo,
      afterDays: hi - bestSplit,
      statistic: bestStat,
    ),
  );

  // Recurse into both halves. The budget is shared, so a habit with one
  // dramatic change and several marginal ones reports the dramatic one.
  _segment(
    habit: habit,
    days: days,
    prefix: prefix,
    lo: lo,
    hi: bestSplit,
    total: total,
    out: out,
    budget: budget - 1,
  );
  _segment(
    habit: habit,
    days: days,
    prefix: prefix,
    lo: bestSplit,
    hi: hi,
    total: total,
    out: out,
    budget: budget - 1,
  );
}

double _rate(List<int> prefix, int lo, int hi) {
  final n = hi - lo;
  if (n <= 0) return 0;
  return (prefix[hi] - prefix[lo]) / n;
}

/// Log-likelihood of a segment under its own maximum-likelihood rate.
///
/// A segment that is all successes or all failures has a rate of 1 or 0 and a
/// log-likelihood of exactly zero — `0 * log(0)` is taken as 0 here, which is
/// the standard convention and the right one: a perfect run is perfectly
/// explained by "the rate is 1".
double _logLikelihood(List<int> prefix, int lo, int hi) {
  final n = hi - lo;
  if (n <= 0) return 0;
  final successes = prefix[hi] - prefix[lo];
  final failures = n - successes;
  final p = successes / n;

  var out = 0.0;
  if (successes > 0) out += successes * math.log(p);
  if (failures > 0) out += failures * math.log(1 - p);
  return out;
}

/// The most recent turning point across every active habit, newest first.
///
/// The screen shows a handful, and "what changed lately" is almost always the
/// question being asked — a shift from eight months ago is history, not news.
List<({Habit habit, TurningPoint point})> findRecentTurningPoints(
  List<Habit> habits, {
  DateTime? reference,
  int withinDays = 120,
}) {
  final today = dateOnly(reference ?? DateTime.now());
  final cutoff = addDays(today, -withinDays);

  final out = <({Habit habit, TurningPoint point})>[];
  for (final habit in habits) {
    if (habit.archived) continue;
    for (final point in findTurningPoints(habit, reference: today)) {
      if (point.day.isBefore(cutoff)) continue;
      out.add((habit: habit, point: point));
    }
  }

  out.sort((a, b) => b.point.day.compareTo(a.point.day));
  return List<({Habit habit, TurningPoint point})>.unmodifiable(out);
}
