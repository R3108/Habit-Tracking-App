import 'package:flutter/foundation.dart';

import '../habit.dart';

/// What one day's worth of load actually produced, averaged over every day the
/// user carried that much.
@immutable
class CapacityPoint {
  const CapacityPoint._({
    required this.load,
    required this.days,
    required this.completions,
  });

  /// Habits due on such a day.
  final int load;

  /// Days observed carrying this load — the sample behind [completions].
  final int days;

  /// Mean habits actually completed on those days.
  final double completions;

  /// Share of the load that got done, in 0..1.
  double get rate => load == 0 ? 0 : (completions / load).clamp(0.0, 1.0);

  int get percent => (rate * 100).round();
}

/// How much a person actually gets done as a function of how much they take on.
///
/// Every other piece of advice in this app is about one habit. This is about
/// the list, and it exists because the failure it detects is invisible from
/// inside any single habit: adding the eighth habit does not make the eighth
/// habit fail, it makes two of the other seven fail, and each of those looks
/// like an unrelated problem with its own unrelated explanation.
///
/// The method is deliberately blunt. Days are grouped by how many habits were
/// due, and each group reports the mean number completed. If completions rise
/// with load and keep rising, the user has headroom. If they flatten, extra
/// habits are being carried at no benefit. If they *fall*, the extra habits are
/// costing completions that would otherwise have happened — the case worth
/// interrupting someone about.
///
/// Two honest caveats, both surfaced in the UI rather than buried:
///
/// - **This is observational.** Heavy days and light days differ in more than
///   load; a Sunday with nine habits due is not a Tuesday with three. Nothing
///   here establishes that the load *caused* the drop.
/// - **Load is a count, not a cost.** Ten one-minute habits and three hard ones
///   look identical to this, and are not.
///
/// The verdict is therefore phrased as something to consider, never as an
/// instruction to delete habits.
@immutable
class CapacityCurve {
  const CapacityCurve._({
    required this.points,
    required this.currentLoad,
    required this.bestLoad,
    required this.leanestLoad,
    required this.daysObserved,
  });

  /// One entry per load level with enough days behind it, lightest first.
  final List<CapacityPoint> points;

  /// Habits due today.
  final int currentLoad;

  /// The load that produced the most completions, or null when the curve is
  /// too thin to have a shape.
  final int? bestLoad;

  /// The lightest load that got within [_indifference] of the best.
  ///
  /// Usually the more useful of the two: if six habits and nine habits both
  /// finish about five, six is the honest number, and the other three are
  /// costing attention for nothing.
  final int? leanestLoad;

  /// Days the whole curve was built from.
  final int daysObserved;

  /// How far back the walk goes.
  static const int windowDays = 120;

  /// Days a load level needs before it is plotted at all.
  ///
  /// Below this the mean is noise, and a single heroic Saturday would otherwise
  /// establish "you can do eleven".
  static const int _minimumDaysPerLoad = 5;

  /// Load levels needed before the curve is allowed a verdict.
  static const int _minimumLevels = 3;

  /// Completions within this of the peak count as the same as the peak.
  static const double _indifference = 0.4;

  /// Completions below the peak before overcommitment is called.
  ///
  /// Wider than [_indifference]: saying "you have taken on too much" is a
  /// strong claim, and it should cost a visible half-habit a day to earn it.
  static const double _overcommitmentCost = 0.6;

  bool get hasEnoughHistory => points.length >= _minimumLevels;

  CapacityPoint? get atCurrentLoad {
    for (final point in points) {
      if (point.load == currentLoad) return point;
    }
    return null;
  }

  CapacityPoint? get atBestLoad {
    for (final point in points) {
      if (point.load == bestLoad) return point;
    }
    return null;
  }

  /// True when today's load is past the point of diminishing returns *and* the
  /// shortfall is big enough to be worth mentioning.
  bool get isOvercommitted {
    final best = atBestLoad;
    final current = atCurrentLoad;
    if (!hasEnoughHistory || best == null || current == null) return false;
    if (currentLoad <= (bestLoad ?? 0)) return false;
    return current.completions < best.completions - _overcommitmentCost;
  }

  /// True when completions were still climbing at the heaviest load observed —
  /// there is no evidence of a ceiling yet.
  bool get hasHeadroom {
    if (!hasEnoughHistory || points.length < 2) return false;
    return bestLoad == points.last.load;
  }

  /// Extra completions bought by the last habit added, at the current load.
  ///
  /// Null when either side of the comparison is missing. Negative means the
  /// habit is not merely free-riding — it is displacing something.
  double? get marginalReturn {
    CapacityPoint? here, below;
    for (final point in points) {
      if (point.load == currentLoad) here = point;
      if (point.load == currentLoad - 1) below = point;
    }
    if (here == null || below == null) return null;
    return here.completions - below.completions;
  }

  /// A sentence for the card.
  String get summary {
    if (!hasEnoughHistory) {
      return 'Not enough variety in your daily load yet to see a pattern.';
    }
    final best = atBestLoad;
    if (best == null) return 'No clear pattern in how load affects completions.';

    if (isOvercommitted) {
      final lean = leanestLoad ?? best.load;
      return 'You finish most on days with about $lean due. Today has '
          '$currentLoad, and days like that have averaged '
          '${_oneDecimal(atCurrentLoad?.completions ?? 0)} completed.';
    }
    if (hasHeadroom) {
      return 'Completions were still rising at ${best.load} due a day — no '
          'ceiling visible in your history yet.';
    }
    final lean = leanestLoad;
    if (lean != null && lean < best.load) {
      return '$lean habits a day has finished about as much as ${best.load} '
          'does — the extra ones are not adding output.';
    }
    return 'Your best days carry about ${best.load}, finishing '
        '${_oneDecimal(best.completions)}.';
  }

  /// Builds the curve from the whole habit list.
  factory CapacityCurve.from(List<Habit> habits, {DateTime? reference}) {
    final today = dateOnly(reference ?? DateTime.now());
    final active = <Habit>[for (final h in habits) if (!h.archived) h];

    // Load level → (days at that level, completions summed across them).
    final daysAt = <int, int>{};
    final doneAt = <int, int>{};
    var observed = 0;

    // Today is excluded: it is half-finished by definition, and counting it
    // would drag whatever load today happens to carry toward zero.
    for (var age = windowDays; age >= 1; age--) {
      final day = addDays(today, -age);

      var load = 0;
      var done = 0;
      for (final habit in active) {
        if (!habit.isDueOn(day)) continue;
        load++;
        if (habit.isCompletedOn(day)) done++;
      }

      // A day with nothing due says nothing about capacity.
      if (load == 0) continue;

      observed++;
      daysAt[load] = (daysAt[load] ?? 0) + 1;
      doneAt[load] = (doneAt[load] ?? 0) + done;
    }

    final points = <CapacityPoint>[
      for (final entry in daysAt.entries)
        if (entry.value >= _minimumDaysPerLoad)
          CapacityPoint._(
            load: entry.key,
            days: entry.value,
            completions: (doneAt[entry.key] ?? 0) / entry.value,
          ),
    ]..sort((a, b) => a.load.compareTo(b.load));

    int? best;
    var bestCompletions = double.negativeInfinity;
    for (final point in points) {
      if (point.completions > bestCompletions) {
        bestCompletions = point.completions;
        best = point.load;
      }
    }

    int? leanest;
    if (best != null) {
      for (final point in points) {
        if (point.completions >= bestCompletions - _indifference) {
          leanest = point.load;
          break;
        }
      }
    }

    var currentLoad = 0;
    for (final habit in active) {
      if (habit.isDueOn(today)) currentLoad++;
    }

    return CapacityCurve._(
      points: List<CapacityPoint>.unmodifiable(points),
      currentLoad: currentLoad,
      bestLoad: best,
      leanestLoad: leanest,
      daysObserved: observed,
    );
  }
}

String _oneDecimal(double value) => value.toStringAsFixed(1);
