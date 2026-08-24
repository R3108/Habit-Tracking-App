import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'daily_signal.dart';

/// A measured difference between the days one signal ran high and the days it
/// ran low, in terms of another.
///
/// "On the days you slept more than 7h 10m, you kept 82% of your habits;
/// on the rest, 54%." Two numbers a person can check against their own memory,
/// which is the whole reason this is a median split rather than a correlation
/// coefficient — nobody can sanity-check an r of 0.41, and everybody can
/// sanity-check "my good sleep days were better".
///
/// This is correlation, and a *searched* correlation at that. See
/// [findDiscoveries] for what is done to keep that honest.
@immutable
class Discovery {
  const Discovery._({
    required this.driver,
    required this.outcome,
    required this.threshold,
    required this.highMean,
    required this.lowMean,
    required this.highDays,
    required this.lowDays,
    required this.effect,
  });

  final DailySignal driver;
  final DailySignal outcome;

  /// The median of the driver, which is where the days were split.
  final double threshold;

  final double highMean;
  final double lowMean;
  final int highDays;
  final int lowDays;

  /// The gap between the two group means in standard deviations of the
  /// outcome — Cohen's d. Kept as the ranking number because a raw gap is not
  /// comparable across signals measured in different units.
  final double effect;

  int get days => highDays + lowDays;

  double get difference => highMean - lowMean;

  /// True when the outcome was better on the driver's high days.
  bool get isPositive => difference > 0;

  /// How much of a difference this is, in plain words.
  String get strength => switch (effect.abs()) {
    >= 1.2 => 'Strong',
    >= 0.8 => 'Clear',
    _ => 'Modest',
  };

  /// Overlapping days needed before a pair is looked at.
  ///
  /// Two weeks is the point at which a median split stops being two handfuls of
  /// days that happen to differ.
  static const int minimumDays = 14;

  /// Days needed on each side of the split.
  static const int minimumPerSide = 5;

  /// Effect size below which a finding is not worth showing.
  ///
  /// 0.5 is a conventional "medium" effect. The gate is doing real work: with a
  /// dozen signals there are well over a hundred pairs to test, and at any
  /// looser threshold the screen would fill with noise every time.
  static const double minimumEffect = 0.5;

  /// Compares [outcome] across the high and low halves of [driver], or returns
  /// null when the two do not overlap enough to say anything.
  static Discovery? between(DailySignal driver, DailySignal outcome) {
    if (driver.id == outcome.id) return null;

    final shared = <DateTime>[
      for (final day in driver.values.keys)
        if (outcome.values.containsKey(day)) day,
    ];
    if (shared.length < minimumDays) return null;

    final driverValues = <double>[for (final day in shared) driver.values[day]!];
    final threshold = _median(driverValues);

    final high = <double>[];
    final low = <double>[];
    for (final day in shared) {
      // Ties go low, so a driver that is the same number most days — someone
      // who always logs exactly 2000ml — lands everything on one side and is
      // then rejected below, rather than being split arbitrarily.
      if (driver.values[day]! > threshold) {
        high.add(outcome.values[day]!);
      } else {
        low.add(outcome.values[day]!);
      }
    }

    if (high.length < minimumPerSide || low.length < minimumPerSide) return null;

    final spread = _standardDeviation([for (final day in shared) outcome.values[day]!]);
    // A flat outcome cannot differ between the groups, and dividing by its
    // spread would be a division by zero.
    if (spread <= 0) return null;

    final highMean = _mean(high);
    final lowMean = _mean(low);
    final effect = (highMean - lowMean) / spread;

    if (effect.abs() < minimumEffect) return null;

    return Discovery._(
      driver: driver,
      outcome: outcome,
      threshold: threshold,
      highMean: highMean,
      lowMean: lowMean,
      highDays: high.length,
      lowDays: low.length,
      effect: effect,
    );
  }

  static double _mean(List<double> values) =>
      values.reduce((a, b) => a + b) / values.length;

  static double _median(List<double> values) {
    final sorted = [...values]..sort();
    final middle = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[middle];
    return (sorted[middle - 1] + sorted[middle]) / 2;
  }

  static double _standardDeviation(List<double> values) {
    if (values.length < 2) return 0;
    final mean = _mean(values);
    final variance =
        values.fold<double>(0, (sum, v) => sum + math.pow(v - mean, 2)) /
        values.length;
    return math.sqrt(variance);
  }
}

/// The strongest findings across every pair of [signals].
///
/// This is an exploratory search, and the honest way to build one is to admit
/// what that costs. With a dozen signals there are over a hundred ordered pairs;
/// test them all at a loose threshold and a handful will look striking by luck
/// alone. Four things hold that down:
///
/// 1. A medium effect size is required, not mere statistical significance.
/// 2. Each unordered pair yields at most one finding, so the same relationship
///    cannot appear twice wearing different hats.
/// 3. The list is capped, so a quiet month cannot be padded out with the least
///    convincing findings.
/// 4. No time lags are tested. "Did Monday's workout affect Tuesday's sleep" is
///    a genuinely interesting question, and adding it would double the number
///    of comparisons for one extra answer — a bad trade against false positives.
///
/// What survives is still a pattern in one person's logs, not a finding about
/// people, and every string this produces is phrased as an observation.
List<Discovery> findDiscoveries(
  List<DailySignal> signals, {
  int limit = 5,
}) {
  final best = <String, Discovery>{};

  for (final driver in signals) {
    for (final outcome in signals) {
      final discovery = Discovery.between(driver, outcome);
      if (discovery == null) continue;

      final key = _pairKey(driver.id, outcome.id);
      final incumbent = best[key];
      if (incumbent == null || _prefer(discovery, incumbent)) {
        best[key] = discovery;
      }
    }
  }

  final found = best.values.toList()
    ..sort((a, b) => b.effect.abs().compareTo(a.effect.abs()));

  return found.take(limit).toList();
}

String _pairKey(String a, String b) =>
    a.compareTo(b) <= 0 ? '$a|$b' : '$b|$a';

/// Picks between the two readings of one pair.
///
/// A relationship between sleep and mood can be told either way round, and only
/// one of them is worth reading. Something the user is trying to *move* — mood,
/// habits kept — belongs on the outcome side; between two of those, or neither,
/// the larger effect wins.
bool _prefer(Discovery candidate, Discovery incumbent) {
  final candidateOriented = candidate.outcome.isOutcome && !candidate.driver.isOutcome;
  final incumbentOriented = incumbent.outcome.isOutcome && !incumbent.driver.isOutcome;

  if (candidateOriented != incumbentOriented) return candidateOriented;
  return candidate.effect.abs() > incumbent.effect.abs();
}
