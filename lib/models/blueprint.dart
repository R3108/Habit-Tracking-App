import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'daily_signal.dart';

/// One line of the recipe: what a signal looked like on the good days.
@immutable
class BlueprintLine {
  const BlueprintLine._({
    required this.signal,
    required this.goodMedian,
    required this.poorMedian,
    required this.threshold,
    required this.goodDays,
    required this.poorDays,
    required this.separation,
  });

  final DailySignal signal;

  /// Median of this signal across the best days and the worst days.
  final double goodMedian;
  final double poorMedian;

  /// The number worth aiming at, and the point of the whole line.
  ///
  /// Not the median of the good days but their lower quartile (upper, when less
  /// is better), which makes it a promise the history can keep: *three quarters
  /// of your good days were at least this*. A median target is one half your
  /// own good days would have failed.
  final double threshold;

  final int goodDays;
  final int poorDays;

  /// Gap between the two medians in standard deviations of the signal.
  final double separation;

  /// Whether the good days had *more* of this.
  bool get higherIsBetter => goodMedian > poorMedian;

  String get thresholdLabel => signal.format(threshold);

  /// Reads the line as an instruction: "Sleep above 7h 5m".
  String get target =>
      '${signal.label} ${higherIsBetter ? 'above' : 'under'} $thresholdLabel';

  /// Whether [value] — today's reading, usually — clears the bar.
  ///
  /// Null in, null out: a day not yet logged is unknown, and guessing would put
  /// a tick or a cross against something the user never told the app.
  bool? meets(double? value) {
    if (value == null) return null;
    return higherIsBetter ? value >= threshold : value <= threshold;
  }
}

/// What the user's best days have in common — a profile, not a pairing.
///
/// The discovery search asks "does sleep move mood?" one pair at a time. This
/// asks the question people actually have: *what does a good day look like for
/// me?* It takes the days that went best by one outcome, the days that went
/// worst, and reports every other signal that separates them — a handful of
/// numbers that describe a good day all at once.
///
/// Splitting on the outcome rather than on each driver is what makes it a
/// different question, and it comes with a different bias: the extremes of any
/// noisy measure exaggerate whatever else was going on, so the gaps here are
/// wider than a fair estimate of any single relationship would be. That is
/// acceptable for a profile — nobody reads a recipe as an effect size — and it
/// is why the threshold is a quartile of the good days rather than anything
/// derived from the gap itself.
///
/// Only signals the user *controls* are profiled. Mood being higher on the days
/// more habits got done is real, circular and useless: nobody can decide to
/// have been in a better mood. What belongs in a recipe is the ingredients.
@immutable
class DayBlueprint {
  const DayBlueprint._({
    required this.outcome,
    required this.lines,
    required this.goodDays,
    required this.poorDays,
    required this.goodOutcome,
    required this.poorOutcome,
  });

  /// The signal the days were sorted by.
  final DailySignal outcome;

  /// The recipe, strongest separation first.
  final List<BlueprintLine> lines;

  final int goodDays;
  final int poorDays;

  /// Mean of the outcome inside each group, for the header.
  final double goodOutcome;
  final double poorOutcome;

  /// Logged outcome days needed before the split means anything.
  static const int minimumDays = 21;

  /// Days needed in each third.
  static const int minimumPerGroup = 7;

  /// Days a signal needs inside each group before it can join the recipe.
  static const int minimumPerSide = 5;

  /// Separation below which a line is not worth a row.
  ///
  /// Stricter than the discovery threshold, because comparing extremes against
  /// extremes flatters every gap it finds.
  static const double minimumSeparation = 0.6;

  bool get isEmpty => lines.isEmpty;

  /// Builds the recipe, or returns null when nothing has enough history.
  ///
  /// The outcome is chosen rather than passed: habits kept is the thing the app
  /// exists to move, and mood is the fallback for someone who tracks their days
  /// without keeping a habit list.
  static DayBlueprint? from(List<DailySignal> signals, {int limit = 4}) {
    final outcome = _pickOutcome(signals);
    if (outcome == null || outcome.days < minimumDays) return null;

    final values = outcome.values.values.toList()..sort();
    final low = _percentile(values, 1 / 3);
    final high = _percentile(values, 2 / 3);
    // A flat outcome has no best days to profile, and splitting it would sort
    // identical days into "good" and "poor" by nothing at all.
    if (high <= low) return null;

    final good = <DateTime>[];
    final poor = <DateTime>[];
    for (final entry in outcome.values.entries) {
      if (entry.value >= high) {
        good.add(entry.key);
      } else if (entry.value <= low) {
        poor.add(entry.key);
      }
    }
    if (good.length < minimumPerGroup || poor.length < minimumPerGroup) {
      return null;
    }

    final lines = <BlueprintLine>[
      for (final signal in signals)
        if (signal.id != outcome.id && !signal.isOutcome)
          ?_line(signal, good: good, poor: poor),
    ]..sort((a, b) => b.separation.compareTo(a.separation));

    if (lines.isEmpty) return null;

    return DayBlueprint._(
      outcome: outcome,
      lines: List<BlueprintLine>.unmodifiable(lines.take(limit)),
      goodDays: good.length,
      poorDays: poor.length,
      goodOutcome: _mean(<double>[for (final day in good) outcome.values[day]!]),
      poorOutcome: _mean(<double>[for (final day in poor) outcome.values[day]!]),
    );
  }

  static DailySignal? _pickOutcome(List<DailySignal> signals) {
    for (final id in const <String>['habits', 'mood']) {
      for (final signal in signals) {
        if (signal.id == id) return signal;
      }
    }
    return null;
  }

  static BlueprintLine? _line(
    DailySignal signal, {
    required List<DateTime> good,
    required List<DateTime> poor,
  }) {
    final goodValues = <double>[
      for (final day in good) ?signal.values[day],
    ];
    final poorValues = <double>[
      for (final day in poor) ?signal.values[day],
    ];
    if (goodValues.length < minimumPerSide) return null;
    if (poorValues.length < minimumPerSide) return null;

    // Spread is taken over both groups together, so the yardstick is the
    // signal's own variability rather than either group's.
    final spread = _standardDeviation(<double>[...goodValues, ...poorValues]);
    if (spread <= 0) return null;

    final goodMedian = _percentile(goodValues..sort(), 0.5);
    final poorMedian = _percentile(poorValues..sort(), 0.5);
    final separation = (goodMedian - poorMedian).abs() / spread;
    if (separation < minimumSeparation) return null;

    final higherIsBetter = goodMedian > poorMedian;
    return BlueprintLine._(
      signal: signal,
      goodMedian: goodMedian,
      poorMedian: poorMedian,
      threshold: _percentile(goodValues, higherIsBetter ? 0.25 : 0.75),
      goodDays: goodValues.length,
      poorDays: poorValues.length,
      separation: separation,
    );
  }

  /// Linearly interpolated percentile of an already-sorted list.
  static double _percentile(List<double> sorted, double fraction) {
    if (sorted.isEmpty) return 0;
    if (sorted.length == 1) return sorted.first;

    final position = fraction * (sorted.length - 1);
    final lower = position.floor();
    final upper = position.ceil();
    if (lower == upper) return sorted[lower];
    return sorted[lower] + (sorted[upper] - sorted[lower]) * (position - lower);
  }

  static double _mean(List<double> values) =>
      values.isEmpty ? 0 : values.reduce((a, b) => a + b) / values.length;

  static double _standardDeviation(List<double> values) {
    if (values.length < 2) return 0;
    final mean = _mean(values);
    final variance =
        values.fold<double>(0, (sum, v) => sum + math.pow(v - mean, 2)) /
        values.length;
    return math.sqrt(variance);
  }
}
