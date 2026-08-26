import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'habit.dart';

/// One condition that moved today's odds, and by how much.
///
/// Kept alongside the probability because a bare number is not something a
/// person can act on. "62%" invites a shrug; "62% — but only 31% on the
/// Thursdays you've had" names the thing that is actually going wrong.
@immutable
class ForecastFactor {
  const ForecastFactor({
    required this.label,
    required this.weight,
    required this.days,
    required this.rate,
  });

  /// How the condition reads in a sentence: "Thursdays", "After a missed day".
  final String label;

  /// The shift this condition applied to the log-odds. Positive helps.
  final double weight;

  /// Due days this condition was measured over.
  final int days;

  /// Completion rate under the condition, in 0..1.
  final double rate;

  bool get isHelping => weight > 0;

  int get percent => (rate * 100).round();
}

/// The odds a habit gets done today, learned from that habit's own history.
///
/// This is a small naive-Bayes model, fitted on the device, per habit, on every
/// read. It starts from a recency-weighted base rate and then adds one
/// log-odds term per condition that holds today — the weekday, what happened on
/// the last day it was due, whether its stack cue has already fired.
///
/// Three things keep it from lying:
///
/// 1. **Every term is shrunk toward the base rate.** A condition seen four
///    times contributes almost nothing; one seen thirty times contributes
///    nearly its full weight. This is what stops "you've never done it on a
///    Wednesday" — said after two Wednesdays — from reading as 3%.
/// 2. **Every term is clamped.** No single condition can swing the answer by
///    more than [_maximumFactorWeight] in log-odds, so a thin coincidence
///    cannot overwhelm a year of evidence.
/// 3. **The result never reaches 0 or 100%.** People break their patterns, and
///    a model that claims certainty about a person is wrong on principle before
///    it is wrong in practice.
///
/// Naive Bayes assumes the conditions are independent, and here they are not
/// quite: a bad Thursday and a missed yesterday tend to travel together. The
/// clamping is doing double duty as the guard against that — correlated terms
/// stack, and the ceiling is what stops them stacking into nonsense.
@immutable
class HabitForecast {
  const HabitForecast._({
    required this.habitId,
    required this.probability,
    required this.baseRate,
    required this.evidence,
    required this.dueToday,
    required this.doneToday,
    required this.factors,
  });

  final String habitId;

  /// Chance the habit is completed today, in 0..1.
  ///
  /// 1.0 when it is already done — that is not a prediction, it is a fact.
  /// 0 when the habit is not due, where a forecast would be meaningless;
  /// callers should gate on [dueToday] rather than reading the number.
  final double probability;

  /// The recency-weighted completion rate the model started from.
  final double baseRate;

  /// Weight behind [baseRate], in units of "due days at full weight".
  final double evidence;

  final bool dueToday;
  final bool doneToday;

  /// The conditions holding today, strongest first.
  final List<ForecastFactor> factors;

  /// How far back the fit looks.
  static const int windowDays = 120;

  /// Days after which a due day counts for half as much in the base rate.
  ///
  /// Longer than the momentum half-life: momentum is asking "is this
  /// slipping right now", where a fortnight should dominate, while a forecast
  /// wants the settled pattern and would be jumpy on a two-week memory.
  static const double halfLifeDays = 14;

  /// Below this much weight the model is guessing, and says so.
  static const double _minimumEvidence = 4;

  /// Due days a condition needs before it is allowed to speak at all.
  static const int _minimumFactorDays = 4;

  /// The most any one condition may shift the log-odds.
  ///
  /// Wide enough that a weekday you have genuinely never managed can turn a
  /// likely day into an unlikely one — anything tighter would leave the model
  /// politely predicting 60% for something that has never once happened — and
  /// narrow enough that it cannot reach certainty on its own.
  static const double _maximumFactorWeight = 2.5;

  /// Pseudo-counts each condition is shrunk toward the base rate with.
  static const double _shrinkage = 5;

  bool get hasEnoughHistory => evidence >= _minimumEvidence;

  int get percent => (probability * 100).round();

  /// The condition doing the most work, or null when nothing stands out.
  ForecastFactor? get dominant => factors.isEmpty ? null : factors.first;

  /// The odds in words, for a card that has no room for a bar.
  String get outlook => switch (probability) {
    >= 0.8 => 'Very likely',
    >= 0.6 => 'Likely',
    >= 0.4 => 'Could go either way',
    >= 0.2 => 'Unlikely',
    _ => 'Long shot',
  };

  /// Fits the model for [habit] as of [reference] (default today).
  ///
  /// [anchor] is the habit this one is stacked behind, when it has one. Its cue
  /// only counts once it has actually fired: an anchor still unticked at noon
  /// says nothing, because the day is not over and the user may yet do both.
  factory HabitForecast.of(
    Habit habit, {
    DateTime? reference,
    Habit? anchor,
  }) {
    final today = dateOnly(reference ?? DateTime.now());
    final dueToday = habit.isDueOn(today);
    final doneToday = habit.isCompletedOn(today);

    final base = _weightedBase(habit, today);

    if (!dueToday || doneToday) {
      return HabitForecast._(
        habitId: habit.id,
        probability: doneToday ? 1 : 0,
        baseRate: base.rate,
        evidence: base.evidence,
        dueToday: dueToday,
        doneToday: doneToday,
        factors: const <ForecastFactor>[],
      );
    }

    // The days the model was actually fitted on: due, inside the window, and
    // strictly before today. Today is what is being predicted, so including it
    // would be reading the answer off the back of the paper.
    final history = <DateTime>[
      for (var age = windowDays; age >= 1; age--)
        if (habit.isDueOn(addDays(today, -age))) addDays(today, -age),
    ];

    final factors = <ForecastFactor>[
      ?_weekdayFactor(habit, history, today, base.rate),
      ?_carryOverFactor(habit, history, today, base.rate),
      ?_anchorFactor(habit, anchor, history, today, base.rate),
    ]..sort((a, b) => b.weight.abs().compareTo(a.weight.abs()));

    var logOdds = _logit(base.rate);
    for (final factor in factors) {
      logOdds += factor.weight;
    }

    return HabitForecast._(
      habitId: habit.id,
      // Never 0 and never 1: see the class comment.
      probability: _sigmoid(logOdds).clamp(0.02, 0.98),
      baseRate: base.rate,
      evidence: base.evidence,
      dueToday: true,
      doneToday: false,
      factors: List<ForecastFactor>.unmodifiable(factors),
    );
  }

  /// The recency-weighted completion rate, with a Laplace prior at 50%.
  ///
  /// The prior is what a habit with three days of history is entitled to say
  /// about itself: nothing. It washes out within a fortnight of real days.
  static ({double rate, double evidence}) _weightedBase(
    Habit habit,
    DateTime today,
  ) {
    var weightedDue = 0.0;
    var weightedDone = 0.0;

    for (var age = 1; age <= windowDays; age++) {
      final day = addDays(today, -age);
      if (!habit.isDueOn(day)) continue;

      final weight = math.pow(0.5, age / halfLifeDays).toDouble();
      weightedDue += weight;
      if (habit.isCompletedOn(day)) weightedDone += weight;
    }

    return (
      rate: (weightedDone + 1) / (weightedDue + 2),
      evidence: weightedDue,
    );
  }

  /// "Thursdays": the same weekday as today.
  static ForecastFactor? _weekdayFactor(
    Habit habit,
    List<DateTime> history,
    DateTime today,
    double base,
  ) {
    const names = [
      'Mondays',
      'Tuesdays',
      'Wednesdays',
      'Thursdays',
      'Fridays',
      'Saturdays',
      'Sundays',
    ];

    return _factor(
      label: names[today.weekday - 1],
      days: <DateTime>[
        for (final day in history)
          if (day.weekday == today.weekday) day,
      ],
      habit: habit,
      base: base,
    );
  }

  /// What tends to happen the day after a kept day, and after a missed one.
  ///
  /// The single most useful thing in the model, and the one a chart cannot
  /// show: for some people a miss is a blip, and for others it is the first
  /// domino. Measured on consecutive *due* days, so a Mon/Wed/Fri habit
  /// compares Wednesday against Monday rather than against a Tuesday it was
  /// never asked about.
  static ForecastFactor? _carryOverFactor(
    Habit habit,
    List<DateTime> history,
    DateTime today,
    double base,
  ) {
    if (history.isEmpty) return null;

    final previous = history.last;
    // A due day three weeks back is not "yesterday" in any useful sense, and
    // the run it belonged to has nothing to say about today.
    if (today.difference(previous).inDays > 8) return null;

    final keptPrevious = habit.isCompletedOn(previous);

    final matching = <DateTime>[
      for (var i = 1; i < history.length; i++)
        if (habit.isCompletedOn(history[i - 1]) == keptPrevious) history[i],
    ];

    return _factor(
      label: keptPrevious ? 'After a day you kept it' : 'After a missed day',
      days: matching,
      habit: habit,
      base: base,
    );
  }

  /// Days the stack cue had already fired.
  static ForecastFactor? _anchorFactor(
    Habit habit,
    Habit? anchor,
    List<DateTime> history,
    DateTime today,
    double base,
  ) {
    if (anchor == null || !anchor.isCompletedOn(today)) return null;

    return _factor(
      label: 'After "${anchor.title}"',
      days: <DateTime>[
        for (final day in history)
          if (anchor.isCompletedOn(day)) day,
      ],
      habit: habit,
      base: base,
    );
  }

  /// Turns a set of comparable days into a shrunken, clamped log-odds shift.
  ///
  /// Returns null when the condition has too few days behind it, or when what
  /// it has to say is indistinguishable from the base rate — a factor list of
  /// "Thursdays: exactly average" is noise dressed as insight.
  static ForecastFactor? _factor({
    required String label,
    required List<DateTime> days,
    required Habit habit,
    required double base,
  }) {
    if (days.length < _minimumFactorDays) return null;

    var done = 0;
    for (final day in days) {
      if (habit.isCompletedOn(day)) done++;
    }

    final shrunk = (done + _shrinkage * base) / (days.length + _shrinkage);
    final weight = (_logit(shrunk) - _logit(base)).clamp(
      -_maximumFactorWeight,
      _maximumFactorWeight,
    );
    if (weight.abs() < 0.25) return null;

    return ForecastFactor(
      label: label,
      weight: weight,
      days: days.length,
      rate: done / days.length,
    );
  }

  static double _logit(double p) {
    final safe = p.clamp(0.001, 0.999);
    return math.log(safe / (1 - safe));
  }

  static double _sigmoid(double x) => 1 / (1 + math.exp(-x));
}

/// Today's odds across the whole list.
@immutable
class DayForecast {
  const DayForecast._({
    required this.forecasts,
    required this.due,
    required this.done,
    required this.expected,
    required this.confident,
  });

  /// One entry per habit due today, least likely first — which is the order the
  /// user can do something about.
  final List<HabitForecast> forecasts;

  final int due;
  final int done;

  /// Completions the model expects by tonight, today's ticks included.
  ///
  /// The sum of independent probabilities, which is exactly right for an
  /// expected count even though the individual habits are not independent —
  /// expectation is linear whether or not they are.
  final double expected;

  /// How many of the outstanding forecasts have enough history to be worth
  /// anything. Below half the list, the screen says it is still learning.
  final int confident;

  bool get isEmpty => due == 0;

  /// Habits still outstanding, in the same least-likely-first order.
  List<HabitForecast> get remaining =>
      forecasts.where((f) => !f.doneToday).toList();

  int get expectedRounded => expected.round();

  /// True once there is enough history for the numbers to be worth showing.
  bool get isReliable {
    final outstanding = remaining;
    if (outstanding.isEmpty) return true;
    return confident * 2 >= outstanding.length;
  }

  /// The habit most likely to be the one that gets away, or null when
  /// everything outstanding looks safe.
  HabitForecast? get weakest {
    for (final forecast in remaining) {
      if (forecast.hasEnoughHistory && forecast.probability < 0.6) {
        return forecast;
      }
    }
    return null;
  }

  factory DayForecast.build(List<Habit> habits, {DateTime? reference}) {
    final active = habits.where((h) => !h.archived).toList();
    final byId = <String, Habit>{for (final habit in active) habit.id: habit};
    final today = dateOnly(reference ?? DateTime.now());

    final forecasts = <HabitForecast>[
      for (final habit in active)
        if (habit.isDueOn(today))
          HabitForecast.of(
            habit,
            reference: today,
            anchor: habit.anchorId == null ? null : byId[habit.anchorId],
          ),
    ]..sort((a, b) => a.probability.compareTo(b.probability));

    var done = 0;
    var expected = 0.0;
    var confident = 0;
    for (final forecast in forecasts) {
      if (forecast.doneToday) done++;
      expected += forecast.probability;
      if (!forecast.doneToday && forecast.hasEnoughHistory) confident++;
    }

    return DayForecast._(
      forecasts: List<HabitForecast>.unmodifiable(forecasts),
      due: forecasts.length,
      done: done,
      expected: expected,
      confident: confident,
    );
  }
}
