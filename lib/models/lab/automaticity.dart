import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../habit.dart';

/// How ingrained a habit has become.
///
/// Bands rather than a bare number because the number is a composite and
/// invites false precision — "71%" reads like a measurement, "established"
/// reads like the judgement it actually is.
enum HabitStrength {
  /// Too new, or too patchy, to be running on anything but deliberate effort.
  forming,

  /// Real traction, still effortful.
  developing,

  /// Holds up on ordinary days.
  established,

  /// Survives disruption. The point of the whole exercise.
  automatic,
}

extension HabitStrengthLabel on HabitStrength {
  String get label => switch (this) {
    HabitStrength.forming => 'Forming',
    HabitStrength.developing => 'Developing',
    HabitStrength.established => 'Established',
    HabitStrength.automatic => 'Automatic',
  };
}

/// How ingrained one habit is, and what is holding it back.
///
/// Momentum answers "is this slipping right now"; this answers the slower
/// question underneath it — "if life got difficult next month, would this
/// survive?" Those come apart more often than they sound like they should. A
/// habit kept flawlessly for eleven days has excellent momentum and no
/// strength at all, and a two-year habit that has been shaky for a fortnight
/// has poor momentum and plenty of strength.
///
/// Four components, deliberately not one:
///
/// 1. **Consistency** — the recency-weighted share of due days kept. The
///    obvious ingredient, and on its own a bad measure: it cannot tell three
///    perfect weeks apart from three perfect years.
/// 2. **Resilience** — of the due days that followed a miss, how many were
///    kept. This is the component that actually separates an automatic habit
///    from a merely well-behaved one. A habit you return to the next day is
///    load-bearing; a habit where one miss reliably becomes four is being
///    carried by motivation, and motivation is what disappears in a hard week.
/// 3. **Tenure** — how long it has been practised, saturating around
///    [_tenureSaturationDays]. Repetition is what builds automaticity, and it
///    has sharply diminishing returns: the gap between two weeks and ten weeks
///    is enormous, the gap between one year and two is not.
/// 4. **Regularity** — how evenly the keeping is spread across the weekdays the
///    habit is actually due. A habit that is perfect on weekdays and absent at
///    weekends is two-thirds of a habit, and the average hides that.
///
/// Every component is reported alongside the total, because the total is only
/// useful as a way into the component that is dragging it down.
@immutable
class AutomaticityScore {
  const AutomaticityScore._({
    required this.habitId,
    required this.consistency,
    required this.resilience,
    required this.tenure,
    required this.regularity,
    required this.score,
    required this.dueDays,
    required this.daysPractised,
    required this.missesObserved,
  });

  final String habitId;

  /// Recency-weighted share of due days kept, 0..1.
  final double consistency;

  /// Share of post-miss due days kept, 0..1. Shrunk toward [consistency] when
  /// there are few misses to learn from — a habit with one recorded miss should
  /// not be called fragile or resilient on the strength of that single day.
  final double resilience;

  /// Practice length, log-scaled into 0..1.
  final double tenure;

  /// Evenness across due weekdays, 0..1.
  final double regularity;

  /// The weighted composite, 0..1.
  final double score;

  /// Due days inside the window, which is what everything above was measured
  /// over.
  final int dueDays;

  /// Calendar days since the habit was created.
  final int daysPractised;

  /// Misses that had a following due day — the sample behind [resilience].
  final int missesObserved;

  /// How far back the fit looks.
  ///
  /// Longer than the forecast window: strength is the slow-moving quantity, and
  /// a quarter of history is the shortest span over which "this survives
  /// disruption" means anything.
  static const int windowDays = 180;

  /// Days after which a due day counts half as much toward [consistency].
  ///
  /// Deliberately long. A short half-life would make this track momentum, and
  /// the app already has momentum.
  static const double halfLifeDays = 45;

  /// Where [tenure] reaches ~63% of its ceiling.
  ///
  /// 66 days is the median time to plateau in Lally et al. (2010), the study
  /// the popular "21 days" claim is a mangling of. It is a median across people
  /// and behaviours with an enormous spread, so it is used here only to set the
  /// curve's scale — never quoted at the user as a deadline.
  static const double _tenureSaturationDays = 66;

  /// Due days needed before any of this is worth saying out loud.
  static const int _minimumDueDays = 14;

  /// Misses needed before [resilience] speaks with its own voice.
  static const double _resilienceShrinkage = 4;

  static const double _wConsistency = 0.40;
  static const double _wResilience = 0.25;
  static const double _wTenure = 0.20;
  static const double _wRegularity = 0.15;

  bool get hasEnoughHistory => dueDays >= _minimumDueDays;

  int get percent => (score * 100).round();

  HabitStrength get strength => switch (score) {
    >= 0.80 => HabitStrength.automatic,
    >= 0.60 => HabitStrength.established,
    >= 0.35 => HabitStrength.developing,
    _ => HabitStrength.forming,
  };

  /// True when the habit is kept well but does not come back from a miss.
  ///
  /// The most useful thing this class finds, and invisible in every other
  /// number the app shows: a 90% habit whose misses cluster into runs is one
  /// bad week from being a 40% habit, and it reads as healthy right up until
  /// it isn't.
  bool get isFragile =>
      hasEnoughHistory &&
      missesObserved >= 4 &&
      consistency >= 0.6 &&
      resilience < consistency - 0.25;

  /// True when the habit looks self-sustaining and could stop being managed.
  ///
  /// Requires real tenure as well as a high score, because a month of
  /// perfection scores well on everything except the one thing that cannot be
  /// hurried.
  bool get isReadyToGraduate =>
      hasEnoughHistory &&
      strength == HabitStrength.automatic &&
      daysPractised >= _tenureSaturationDays &&
      consistency >= 0.85 &&
      resilience >= 0.6;

  /// The component holding the score back, or null when nothing stands out.
  ///
  /// Compared as weighted shortfalls rather than raw values: a weak component
  /// that barely counts is not the thing to go and fix.
  ({String label, double value})? get weakest {
    if (!hasEnoughHistory) return null;

    final shortfalls = <({String label, double value, double weighted})>[
      (
        label: 'Consistency',
        value: consistency,
        weighted: (1 - consistency) * _wConsistency,
      ),
      (
        label: 'Recovery after a miss',
        value: resilience,
        weighted: (1 - resilience) * _wResilience,
      ),
      (
        label: 'Time practised',
        value: tenure,
        weighted: (1 - tenure) * _wTenure,
      ),
      (
        label: 'Evenness across the week',
        value: regularity,
        weighted: (1 - regularity) * _wRegularity,
      ),
    ]..sort((a, b) => b.weighted.compareTo(a.weighted));

    final worst = shortfalls.first;
    // Everything above 80% is fine; naming a "weakest" there is manufacturing a
    // problem to report.
    if (worst.value >= 0.8) return null;
    return (label: worst.label, value: worst.value);
  }

  /// A sentence for the card, phrased as description rather than instruction.
  String get summary {
    if (!hasEnoughHistory) {
      return 'Not enough due days yet — this needs about '
          '$_minimumDueDays to say anything useful.';
    }
    if (isReadyToGraduate) {
      return 'This looks self-sustaining. It may not need managing any more.';
    }
    if (isFragile) {
      return 'Kept often, but a miss tends to become a run of them.';
    }
    final weak = weakest;
    if (weak == null) return 'Holding up well on every measure.';
    return '${weak.label} is what is holding this back.';
  }

  /// Measures [habit] as of [reference] (default today).
  factory AutomaticityScore.of(Habit habit, {DateTime? reference}) {
    final today = dateOnly(reference ?? DateTime.now());

    // Oldest first, so "the next due day" is the next element. Today is
    // excluded: it may simply not have happened yet, and counting an unticked
    // morning as a miss would punish the habit for the hour.
    final history = <DateTime>[
      for (var age = windowDays; age >= 1; age--)
        if (habit.isDueOn(addDays(today, -age))) addDays(today, -age),
    ];

    final daysPractised = today.difference(habit.createdAt).inDays;

    if (history.isEmpty) {
      return AutomaticityScore._(
        habitId: habit.id,
        consistency: 0,
        resilience: 0,
        tenure: _tenureCurve(daysPractised),
        regularity: 0,
        score: 0,
        dueDays: 0,
        daysPractised: daysPractised,
        missesObserved: 0,
      );
    }

    final consistency = _consistency(habit, history, today);
    final recovery = _resilience(habit, history, consistency);
    final tenure = _tenureCurve(daysPractised);
    final regularity = _regularity(habit, history);

    final score =
        consistency * _wConsistency +
        recovery.rate * _wResilience +
        tenure * _wTenure +
        regularity * _wRegularity;

    return AutomaticityScore._(
      habitId: habit.id,
      consistency: consistency,
      resilience: recovery.rate,
      tenure: tenure,
      regularity: regularity,
      score: score.clamp(0.0, 1.0),
      dueDays: history.length,
      daysPractised: daysPractised,
      missesObserved: recovery.observed,
    );
  }

  /// Recency-weighted completion rate with a Laplace prior at 50%.
  static double _consistency(
    Habit habit,
    List<DateTime> history,
    DateTime today,
  ) {
    var weightedDue = 0.0;
    var weightedDone = 0.0;

    for (final day in history) {
      final age = today.difference(day).inDays;
      final weight = math.pow(0.5, age / halfLifeDays).toDouble();
      weightedDue += weight;
      if (habit.isCompletedOn(day)) weightedDone += weight;
    }

    return ((weightedDone + 1) / (weightedDue + 2)).clamp(0.0, 1.0);
  }

  /// Share of the due days following a miss that were kept.
  ///
  /// Shrunk toward [base], so a habit with two recorded misses is described as
  /// roughly as resilient as it is consistent rather than as a triumph or a
  /// disaster. Consecutive *due* days, so a Mon/Wed/Fri habit compares Wednesday
  /// against Monday and not against a Tuesday nobody asked about.
  static ({double rate, int observed}) _resilience(
    Habit habit,
    List<DateTime> history,
    double base,
  ) {
    var followed = 0;
    var recovered = 0;

    for (var i = 1; i < history.length; i++) {
      if (habit.isCompletedOn(history[i - 1])) continue;
      // A miss whose next due day is three weeks away says nothing about
      // bouncing back; the run was over either way.
      if (history[i].difference(history[i - 1]).inDays > 8) continue;
      followed++;
      if (habit.isCompletedOn(history[i])) recovered++;
    }

    if (followed == 0) {
      // Never missed inside the window. That is not the same as "recovers
      // perfectly", but it is certainly not a weakness, so it inherits the
      // consistency it has earned instead of scoring zero.
      return (rate: base, observed: 0);
    }

    final shrunk =
        (recovered + _resilienceShrinkage * base) /
        (followed + _resilienceShrinkage);
    return (rate: shrunk.clamp(0.0, 1.0), observed: followed);
  }

  /// Practice length on a saturating curve.
  static double _tenureCurve(int days) {
    if (days <= 0) return 0;
    return 1 - math.exp(-days / _tenureSaturationDays);
  }

  /// Evenness of keeping across the weekdays the habit is actually due.
  ///
  /// Measured as one minus the mean absolute deviation of the per-weekday rates
  /// around their own mean, normalised so that a habit split perfectly into
  /// "always" and "never" days scores 0. Weekdays with fewer than two due days
  /// are left out rather than counted as a 0% or 100% they haven't earned.
  static double _regularity(Habit habit, List<DateTime> history) {
    final due = <int, int>{};
    final done = <int, int>{};

    for (final day in history) {
      due[day.weekday] = (due[day.weekday] ?? 0) + 1;
      if (habit.isCompletedOn(day)) {
        done[day.weekday] = (done[day.weekday] ?? 0) + 1;
      }
    }

    final rates = <double>[
      for (final entry in due.entries)
        if (entry.value >= 2) (done[entry.key] ?? 0) / entry.value,
    ];

    // One weekday cannot be uneven with itself.
    if (rates.length < 2) return 1;

    final mean = rates.reduce((a, b) => a + b) / rates.length;
    var deviation = 0.0;
    for (final rate in rates) {
      deviation += (rate - mean).abs();
    }
    deviation /= rates.length;

    // The worst achievable mean absolute deviation for values in 0..1 is 0.5,
    // reached by a half-always/half-never split.
    return (1 - deviation / 0.5).clamp(0.0, 1.0);
  }
}

/// Scores every active habit, strongest first.
List<AutomaticityScore> scoreAutomaticity(
  List<Habit> habits, {
  DateTime? reference,
}) {
  final scores = <AutomaticityScore>[
    for (final habit in habits)
      if (!habit.archived) AutomaticityScore.of(habit, reference: reference),
  ]..sort((a, b) => b.score.compareTo(a.score));

  return List<AutomaticityScore>.unmodifiable(scores);
}
