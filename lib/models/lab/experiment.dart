import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../habit.dart';

/// What an experiment concluded.
enum ExperimentVerdict {
  /// Still inside its trial window.
  running,

  /// Finished, but with too few due days on one side to compare.
  inconclusive,

  /// Finished, and the difference is larger than chance comfortably explains.
  helped,

  /// Finished, and the difference runs the wrong way by the same standard.
  hurt,

  /// Finished, and nothing separable from noise happened.
  noEffect,
}

extension ExperimentVerdictLabel on ExperimentVerdict {
  String get label => switch (this) {
    ExperimentVerdict.running => 'Running',
    ExperimentVerdict.inconclusive => 'Not enough data',
    ExperimentVerdict.helped => 'It helped',
    ExperimentVerdict.hurt => 'It hurt',
    ExperimentVerdict.noEffect => 'No clear effect',
  };
}

/// A change to a habit, declared in advance, to be judged against the stretch
/// of history immediately before it.
///
/// Every other analysis in this app is retrospective: it goes looking through
/// what already happened for something interesting, which is exactly the
/// procedure that turns noise into findings if nobody is careful. [Discovery]
/// worries about this at length and applies corrections. An experiment sidesteps
/// the problem instead of correcting for it — the hypothesis, the window and
/// the length are all fixed *before* a single day of evidence exists, so there
/// is no search to correct for. One question, asked once, answered once.
///
/// That is the entire point of the feature, and it is why the trial length
/// cannot be edited once a run is under way: an experiment you can stop when it
/// looks good is not an experiment, it is a way of generating flattering
/// numbers.
@immutable
class Experiment {
  Experiment({
    required this.id,
    required this.habitId,
    required this.change,
    required DateTime startDay,
    this.lengthDays = 21,
    this.baselineDays = 42,
    this.note = '',
    this.abandoned = false,
  }) : startDay = dateOnly(startDay);

  final String id;
  final String habitId;

  /// The one thing being changed, in the user's words: "Moved it to 6am".
  final String change;

  /// First day the change is in effect.
  final DateTime startDay;

  /// How long the trial runs.
  final int lengthDays;

  /// How far back before [startDay] the comparison reaches.
  ///
  /// Longer than the trial by default. The baseline is being used as the
  /// counterfactual — "what would have happened anyway" — and a wide baseline
  /// is a steadier estimate of that than a narrow one. It is capped rather than
  /// unlimited because a habit's behaviour a year ago is not what the next
  /// three weeks would have looked like.
  final int baselineDays;

  final String note;

  /// Abandoned runs are kept rather than deleted, and never judged.
  ///
  /// Deleting them would quietly recreate the problem the whole feature exists
  /// to avoid: if the failures disappear, the surviving experiments are a
  /// filtered sample and their verdicts stop meaning anything.
  final bool abandoned;

  /// Shortest trial the UI offers.
  static const int minimumLength = 7;

  /// Longest trial the UI offers.
  static const int maximumLength = 90;

  /// The last day the change is in effect.
  DateTime get endDay => addDays(startDay, lengthDays - 1);

  /// First day of the baseline window.
  DateTime get baselineStart => addDays(startDay, -baselineDays);

  bool isComplete({DateTime? reference}) =>
      dateOnly(reference ?? DateTime.now()).isAfter(endDay);

  /// Calendar days still to run, floored at zero.
  int daysRemaining({DateTime? reference}) {
    final today = dateOnly(reference ?? DateTime.now());
    final remaining = endDay.difference(today).inDays + 1;
    return remaining < 0 ? 0 : remaining;
  }

  Experiment copyWith({String? change, String? note, bool? abandoned}) {
    return Experiment(
      id: id,
      habitId: habitId,
      change: change ?? this.change,
      startDay: startDay,
      // Deliberately not copyable: see the class comment.
      lengthDays: lengthDays,
      baselineDays: baselineDays,
      note: note ?? this.note,
      abandoned: abandoned ?? this.abandoned,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'habitId': habitId,
    'change': change,
    'startDay': encodeDay(startDay),
    'lengthDays': lengthDays,
    'baselineDays': baselineDays,
    'note': note,
    'abandoned': abandoned,
  };

  factory Experiment.fromJson(Map<String, dynamic> json) {
    return Experiment(
      id: json['id'] as String? ?? 'experiment-${DateTime.now().microsecondsSinceEpoch}',
      habitId: json['habitId'] as String? ?? '',
      change: json['change'] as String? ?? 'A change',
      startDay: decodeDay(json['startDay'] as String?) ?? DateTime.now(),
      lengthDays: ((json['lengthDays'] as num?)?.toInt() ?? 21).clamp(
        minimumLength,
        maximumLength,
      ),
      baselineDays: ((json['baselineDays'] as num?)?.toInt() ?? 42).clamp(
        7,
        365,
      ),
      note: json['note'] as String? ?? '',
      abandoned: json['abandoned'] as bool? ?? false,
    );
  }
}

/// An experiment measured against the habit it was run on.
///
/// The comparison is a two-proportion test on due days: the share kept during
/// the trial against the share kept during the baseline. Due days only, so a
/// change of schedule inside the trial cannot flatter or punish the result by
/// changing the denominator.
///
/// The p-value is reported, but the interval is what the UI leads with. A
/// p-value answers "could chance alone have produced a gap this big", which is
/// a question almost nobody actually has; the interval answers "how big is the
/// effect, and how sure are we", which is the question everybody has. A trial
/// that moves a habit by somewhere between −4 and +31 points has not found
/// anything, and saying so in those terms is far harder to misread than
/// "p = 0.09".
@immutable
class ExperimentResult {
  const ExperimentResult._({
    required this.experiment,
    required this.baselineDue,
    required this.baselineKept,
    required this.trialDue,
    required this.trialKept,
    required this.pValue,
    required this.differenceLow,
    required this.differenceHigh,
    required this.verdict,
    required this.daysRemaining,
  });

  final Experiment experiment;

  final int baselineDue;
  final int baselineKept;
  final int trialDue;
  final int trialKept;

  /// Two-sided p-value, or null when there was not enough to test.
  final double? pValue;

  /// 95% interval for the change in completion rate, in percentage points.
  ///
  /// Null alongside a null [pValue].
  final double? differenceLow;
  final double? differenceHigh;

  final ExperimentVerdict verdict;
  final int daysRemaining;

  /// Due days each side needs before a verdict is attempted.
  ///
  /// Two weeks of a daily habit, or about a month of a three-times-a-week one.
  /// Below this the interval is so wide that reporting it is worse than saying
  /// nothing, because a wide interval still looks like a measurement.
  static const int _minimumDueDays = 8;

  /// The bar for calling an effect real.
  static const double _alpha = 0.05;

  double get baselineRate => baselineDue == 0 ? 0 : baselineKept / baselineDue;
  double get trialRate => trialDue == 0 ? 0 : trialKept / trialDue;

  int get baselinePercent => (baselineRate * 100).round();
  int get trialPercent => (trialRate * 100).round();

  /// The observed change in percentage points. Positive means the trial did
  /// better.
  double get difference => (trialRate - baselineRate) * 100;

  bool get isSignificant =>
      pValue != null && pValue! < _alpha;

  /// Progress through the trial, in 0..1.
  double get progress {
    if (experiment.lengthDays == 0) return 1;
    final done = experiment.lengthDays - daysRemaining;
    return (done / experiment.lengthDays).clamp(0.0, 1.0);
  }

  /// The interval in words, which is what the card leads with.
  String get intervalText {
    final low = differenceLow, high = differenceHigh;
    if (low == null || high == null) return 'Not enough due days to measure.';
    return '${_signed(low)} to ${_signed(high)} points';
  }

  String get summary => switch (verdict) {
    ExperimentVerdict.running =>
      daysRemaining == 1
          ? 'One more day to run.'
          : '$daysRemaining days left to run.',
    ExperimentVerdict.inconclusive =>
      'Too few due days to compare — $trialDue in the trial, '
          '$baselineDue in the baseline.',
    ExperimentVerdict.helped =>
      'Kept $baselinePercent% before, $trialPercent% during. '
          'The change is larger than chance comfortably explains.',
    ExperimentVerdict.hurt =>
      'Kept $baselinePercent% before, $trialPercent% during. '
          'The drop is larger than chance comfortably explains.',
    ExperimentVerdict.noEffect =>
      'Kept $baselinePercent% before, $trialPercent% during — a gap this size '
          'turns up by chance often enough to mean nothing.',
  };

  /// Measures [experiment] against [habit] as of [reference].
  ///
  /// Returns a running result when the trial has not finished, so the UI can
  /// show progress without ever showing a verdict early — glancing at a
  /// half-finished experiment and stopping it because it looks good is the
  /// exact failure this feature is built to prevent.
  factory ExperimentResult.of(
    Experiment experiment,
    Habit habit, {
    DateTime? reference,
  }) {
    final today = dateOnly(reference ?? DateTime.now());
    final remaining = experiment.daysRemaining(reference: today);
    final complete = experiment.isComplete(reference: today);

    final baseline = _tally(
      habit,
      from: experiment.baselineStart,
      to: addDays(experiment.startDay, -1),
    );

    // The trial never counts days that have not happened yet.
    final trialEnd = complete
        ? experiment.endDay
        : addDays(today, -1);
    final trial = _tally(habit, from: experiment.startDay, to: trialEnd);

    if (experiment.abandoned || !complete) {
      return ExperimentResult._(
        experiment: experiment,
        baselineDue: baseline.due,
        baselineKept: baseline.kept,
        trialDue: trial.due,
        trialKept: trial.kept,
        pValue: null,
        differenceLow: null,
        differenceHigh: null,
        verdict: ExperimentVerdict.running,
        daysRemaining: remaining,
      );
    }

    if (baseline.due < _minimumDueDays || trial.due < _minimumDueDays) {
      return ExperimentResult._(
        experiment: experiment,
        baselineDue: baseline.due,
        baselineKept: baseline.kept,
        trialDue: trial.due,
        trialKept: trial.kept,
        pValue: null,
        differenceLow: null,
        differenceHigh: null,
        verdict: ExperimentVerdict.inconclusive,
        daysRemaining: 0,
      );
    }

    final p1 = trial.kept / trial.due;
    final p2 = baseline.kept / baseline.due;

    // Pooled standard error for the test: under the null the two windows share
    // one rate, so the pooled estimate is the right one to test against.
    final pooled = (trial.kept + baseline.kept) / (trial.due + baseline.due);
    final se = math.sqrt(
      pooled * (1 - pooled) * (1 / trial.due + 1 / baseline.due),
    );
    final z = se == 0 ? 0.0 : (p1 - p2) / se;
    final p = 2 * (1 - _normalCdf(z.abs()));

    // Unpooled standard error for the interval: here the two rates are not
    // assumed equal — that is the whole thing being estimated.
    final seDiff = math.sqrt(
      p1 * (1 - p1) / trial.due + p2 * (1 - p2) / baseline.due,
    );
    final margin = 1.96 * seDiff * 100;
    final diff = (p1 - p2) * 100;

    final verdict = p >= _alpha
        ? ExperimentVerdict.noEffect
        : (p1 > p2 ? ExperimentVerdict.helped : ExperimentVerdict.hurt);

    return ExperimentResult._(
      experiment: experiment,
      baselineDue: baseline.due,
      baselineKept: baseline.kept,
      trialDue: trial.due,
      trialKept: trial.kept,
      pValue: p.clamp(0.0, 1.0),
      differenceLow: diff - margin,
      differenceHigh: diff + margin,
      verdict: verdict,
      daysRemaining: 0,
    );
  }

  /// Due days and kept days in an inclusive date range.
  static ({int due, int kept}) _tally(
    Habit habit, {
    required DateTime from,
    required DateTime to,
  }) {
    var due = 0, kept = 0;
    var cursor = dateOnly(from);
    final last = dateOnly(to);

    while (!cursor.isAfter(last)) {
      if (habit.isDueOn(cursor)) {
        due++;
        if (habit.isCompletedOn(cursor)) kept++;
      }
      cursor = addDays(cursor, 1);
    }
    return (due: due, kept: kept);
  }
}

String _signed(double value) {
  final rounded = value.round();
  return rounded > 0 ? '+$rounded' : '$rounded';
}

/// Standard normal CDF.
///
/// Built on the Abramowitz & Stegun 7.1.26 rational approximation to erf, whose
/// error tops out around 1.5e-7 — several orders of magnitude finer than
/// anything that could change a verdict at the 5% line, and it keeps the app
/// free of a statistics dependency for one function.
double _normalCdf(double x) => 0.5 * (1 + _erf(x / math.sqrt2));

double _erf(double x) {
  const a1 = 0.254829592;
  const a2 = -0.284496736;
  const a3 = 1.421413741;
  const a4 = -1.453152027;
  const a5 = 1.061405429;
  const p = 0.3275911;

  final sign = x < 0 ? -1.0 : 1.0;
  final ax = x.abs();

  final t = 1 / (1 + p * ax);
  final y =
      1 -
      (((((a5 * t + a4) * t) + a3) * t + a2) * t + a1) * t * math.exp(-ax * ax);

  return sign * y;
}
