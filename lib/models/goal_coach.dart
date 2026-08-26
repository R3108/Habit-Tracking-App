import 'package:flutter/material.dart';

import 'habit.dart';
import 'trackers/custom_tracker.dart';
import 'trackers/fitness_entry.dart';
import 'trackers/tracker_data.dart';
import 'trackers/tracker_goals.dart';

/// A target the history says is set wrong, and the number to set it to.
///
/// The defaults in [TrackerGoals] are public-health numbers: eight hours, two
/// litres, a hundred and fifty minutes. They are a reasonable place to start
/// and a poor place to stay. A target nobody reaches stops being a target and
/// becomes a daily reminder of failing — and one that is cleared without
/// noticing has quietly stopped asking for anything.
///
/// So each target is checked against what actually happened, and the proposal
/// is always the same thing: **the level you would have met on about six days
/// in ten.** Whether that is a step down or a step up is a fact about the
/// history, not a judgement about the user, which is why one rule produces both.
///
/// Nothing moves on its own. Every suggestion is applied by the user, in a tap
/// they can undo — a tracker that rewrites its own goals overnight is a tracker
/// whose numbers mean nothing.
@immutable
sealed class GoalSuggestion {
  const GoalSuggestion({
    required this.id,
    required this.label,
    required this.icon,
    required this.currentLabel,
    required this.proposedLabel,
    required this.rationale,
    required this.isEasing,
    required this.samples,
    required this.hitRate,
  });

  /// Stable identity for the row: `sleep`, `water`, `custom:<trackerId>`.
  final String id;

  /// The tracker's name, as its own screen writes it.
  final String label;

  final IconData icon;

  /// The target now, and the one proposed, already formatted.
  final String currentLabel;
  final String proposedLabel;

  final String rationale;

  /// True when the target is coming down (or, for a ceiling, going up).
  final bool isEasing;

  /// Days — or weeks, for the fitness goal — behind the numbers.
  final int samples;

  /// Share of those that met the current target, in 0..1.
  final double hitRate;

  String get headline => '${isEasing ? 'Ease' : 'Raise'} to $proposedLabel';

  int get hitPercent => (hitRate * 100).round();

  /// How badly the target is mis-set, for ranking. Distance from the middle of
  /// the band a target is left alone in.
  double get urgency => (hitRate - _comfortableMidpoint).abs();

  /// Logged days a goal needs before it is judged.
  static const int minimumDays = 12;

  /// Below this the target is out of reach; above it, it has stopped asking.
  static const double _tooHard = 0.30;
  static const double _tooEasy = 0.85;
  static const double _comfortableMidpoint = (_tooHard + _tooEasy) / 2;

  /// Where a proposal aims: met on roughly six days in ten.
  static const double _landing = 0.6;
}

/// A change to one of the built-in targets.
final class TrackerGoalSuggestion extends GoalSuggestion {
  const TrackerGoalSuggestion({
    required super.id,
    required super.label,
    required super.icon,
    required super.currentLabel,
    required super.proposedLabel,
    required super.rationale,
    required super.isEasing,
    required super.samples,
    required super.hitRate,
    required this.apply,
  });

  /// The goals as they would be with this suggestion taken.
  ///
  /// Returns a whole [TrackerGoals] rather than mutating one, so the caller can
  /// keep the old value for an undo without copying anything by hand.
  final TrackerGoals Function(TrackerGoals goals) apply;
}

/// A change to one custom tracker's daily target.
final class CustomGoalSuggestion extends GoalSuggestion {
  const CustomGoalSuggestion({
    required super.id,
    required super.label,
    required super.icon,
    required super.currentLabel,
    required super.proposedLabel,
    required super.rationale,
    required super.isEasing,
    required super.samples,
    required super.hitRate,
    required this.tracker,
    required this.proposedTarget,
  });

  final CustomTracker tracker;
  final int proposedTarget;

  /// The tracker as it would be with this suggestion taken.
  CustomTracker apply() => tracker.copyWith(dailyTarget: proposedTarget);
}

/// Every target worth a second look, most mis-set first.
List<GoalSuggestion> goalSuggestions(
  TrackerData data, {
  DateTime? reference,
  int window = 30,
  int limit = 4,
}) {
  final today = dateOnly(reference ?? DateTime.now());
  final goals = data.goals;

  bool inWindow(DateTime day) =>
      !day.isAfter(today) && !day.isBefore(addDays(today, -(window - 1)));

  final found = <GoalSuggestion>[
    ?_sleep(data, goals, inWindow),
    ?_water(data, goals, inWindow),
    ?_reading(data, goals, inWindow),
    ?_focus(data, goals, inWindow),
    ?_eatingWindow(data, goals, inWindow),
    ?_fitness(data, goals, today),
    for (final tracker in data.activeCustomTrackers)
      ?_custom(tracker, data.entriesFor(tracker.id), inWindow),
  ]..sort((a, b) => b.urgency.compareTo(a.urgency));

  return found.take(limit).toList();
}

GoalSuggestion? _sleep(
  TrackerData data,
  TrackerGoals goals,
  bool Function(DateTime day) inWindow,
) {
  final nights = <double>[
    for (final entry in data.sleep.entries)
      if (inWindow(entry.key)) entry.value.durationMinutes.toDouble(),
  ];

  final tuned = _recalibrate(
    values: nights,
    target: goals.sleepMinutes,
    grain: 15,
    // The bounds here are the target editor's slider range, not the wider one
    // the stored value is clamped to. A suggestion the slider cannot represent
    // would apply fine and then show as something else on the targets screen.
    min: 4 * 60,
    max: 11 * 60,
  );
  if (tuned == null) return null;

  return TrackerGoalSuggestion(
    id: 'sleep',
    label: 'Sleep',
    icon: Icons.bedtime_outlined,
    currentLabel: formatMinutes(goals.sleepMinutes),
    proposedLabel: formatMinutes(tuned.proposed),
    rationale: _rationale(tuned, 'nights', formatMinutes(tuned.proposed)),
    isEasing: tuned.easing,
    samples: nights.length,
    hitRate: tuned.hitRate,
    apply: (current) => current.copyWith(sleepMinutes: tuned.proposed),
  );
}

GoalSuggestion? _water(
  TrackerData data,
  TrackerGoals goals,
  bool Function(DateTime day) inWindow,
) {
  final days = <double>[
    for (final entry in data.water.entries)
      if (inWindow(entry.key) && entry.value > 0) entry.value.toDouble(),
  ];

  final tuned = _recalibrate(
    values: days,
    target: goals.waterMl,
    grain: 100,
    min: 500,
    max: 5000,
  );
  if (tuned == null) return null;

  return TrackerGoalSuggestion(
    id: 'water',
    label: 'Water',
    icon: Icons.water_drop_outlined,
    currentLabel: '${goals.waterMl} ml',
    proposedLabel: '${tuned.proposed} ml',
    rationale: _rationale(tuned, 'days', '${tuned.proposed} ml'),
    isEasing: tuned.easing,
    samples: days.length,
    hitRate: tuned.hitRate,
    apply: (current) => current.copyWith(waterMl: tuned.proposed),
  );
}

GoalSuggestion? _reading(
  TrackerData data,
  TrackerGoals goals,
  bool Function(DateTime day) inWindow,
) {
  // Days with no session at all are left out rather than counted as zero: the
  // target is "how long a sitting should be", and a day nobody opened a book is
  // not a short sitting.
  final byDay = <DateTime, double>{};
  for (final session in data.reading) {
    if (!inWindow(session.day)) continue;
    byDay[session.day] = (byDay[session.day] ?? 0) + session.minutes;
  }

  final tuned = _recalibrate(
    values: byDay.values.toList(),
    target: goals.readingMinutes,
    grain: 5,
    min: 5,
    max: 180,
  );
  if (tuned == null) return null;

  return TrackerGoalSuggestion(
    id: 'reading',
    label: 'Reading',
    icon: Icons.menu_book_outlined,
    currentLabel: formatMinutes(goals.readingMinutes),
    proposedLabel: formatMinutes(tuned.proposed),
    rationale: _rationale(tuned, 'days you read', formatMinutes(tuned.proposed)),
    isEasing: tuned.easing,
    samples: byDay.length,
    hitRate: tuned.hitRate,
    apply: (current) => current.copyWith(readingMinutes: tuned.proposed),
  );
}

GoalSuggestion? _focus(
  TrackerData data,
  TrackerGoals goals,
  bool Function(DateTime day) inWindow,
) {
  final byDay = <DateTime, double>{};
  for (final session in data.focus) {
    if (!inWindow(session.day)) continue;
    byDay[session.day] = (byDay[session.day] ?? 0) + 1;
  }

  final tuned = _recalibrate(
    values: byDay.values.toList(),
    target: goals.focusSessionsPerDay,
    grain: 1,
    min: 1,
    max: 16,
  );
  if (tuned == null) return null;

  String sessions(int count) => '$count session${count == 1 ? '' : 's'} a day';

  return TrackerGoalSuggestion(
    id: 'focus',
    label: 'Focus sessions',
    icon: Icons.timer_outlined,
    currentLabel: sessions(goals.focusSessionsPerDay),
    proposedLabel: sessions(tuned.proposed),
    rationale: _rationale(tuned, 'days you worked', sessions(tuned.proposed)),
    isEasing: tuned.easing,
    samples: byDay.length,
    hitRate: tuned.hitRate,
    apply: (current) => current.copyWith(focusSessionsPerDay: tuned.proposed),
  );
}

GoalSuggestion? _eatingWindow(
  TrackerData data,
  TrackerGoals goals,
  bool Function(DateTime day) inWindow,
) {
  final windows = <double>[
    for (final entry in data.food.entries)
      if (inWindow(entry.key))
        if (entry.value.eatingWindowMinutes case final span?) span.toDouble(),
  ];

  final tuned = _recalibrate(
    values: windows,
    target: goals.eatingWindowMinutes,
    grain: 15,
    min: 4 * 60,
    max: 16 * 60,
    // The only ceiling among the built-ins: a shorter window is the goal.
    lowerIsBetter: true,
  );
  if (tuned == null) return null;

  return TrackerGoalSuggestion(
    id: 'eatingWindow',
    label: 'Eating window',
    icon: Icons.restaurant_outlined,
    currentLabel: formatMinutes(goals.eatingWindowMinutes),
    proposedLabel: formatMinutes(tuned.proposed),
    rationale: _rationale(
      tuned,
      'days you logged meals',
      formatMinutes(tuned.proposed),
    ),
    isEasing: tuned.easing,
    samples: windows.length,
    hitRate: tuned.hitRate,
    apply: (current) => current.copyWith(eatingWindowMinutes: tuned.proposed),
  );
}

/// The one weekly target, measured in whole weeks rather than days.
///
/// A week with no workout in it counts as zero rather than being skipped —
/// unlike every other goal here — because that is exactly what the weekly
/// guideline is about, and dropping the empty weeks would measure "how hard I
/// train when I train" instead. Weeks before the first logged workout are still
/// left out: they are not rest weeks, they are weeks before the tracker existed.
GoalSuggestion? _fitness(
  TrackerData data,
  TrackerGoals goals,
  DateTime today,
) {
  if (data.workouts.isEmpty) return null;

  var earliest = data.workouts.first.day;
  for (final workout in data.workouts) {
    if (workout.day.isBefore(earliest)) earliest = workout.day;
  }

  const weeksConsidered = 8;
  final weeks = <double>[];
  for (var index = 1; index <= weeksConsidered; index++) {
    final start = addDays(today, -(index * 7));
    if (start.isBefore(earliest)) break;

    var minutes = 0;
    for (final workout in data.workouts) {
      if (!workout.intensity.isModerateOrAbove) continue;
      if (workout.day.isBefore(start)) continue;
      if (!workout.day.isBefore(addDays(start, 7))) continue;
      minutes += workout.minutes;
    }
    weeks.add(minutes.toDouble());
  }

  final tuned = _recalibrate(
    values: weeks,
    target: goals.activeMinutesPerWeek,
    grain: 10,
    min: 30,
    max: 600,
    minimumSamples: 6,
  );
  if (tuned == null) return null;

  return TrackerGoalSuggestion(
    id: 'fitness',
    label: 'Active minutes',
    icon: Icons.fitness_center,
    currentLabel: '${goals.activeMinutesPerWeek} a week',
    proposedLabel: '${tuned.proposed} a week',
    rationale: _rationale(tuned, 'weeks', '${tuned.proposed} minutes a week'),
    isEasing: tuned.easing,
    samples: weeks.length,
    hitRate: tuned.hitRate,
    apply: (current) => current.copyWith(activeMinutesPerWeek: tuned.proposed),
  );
}

GoalSuggestion? _custom(
  CustomTracker tracker,
  Map<DateTime, double> log,
  bool Function(DateTime day) inWindow,
) {
  // A tracker with no target is a diary, not a goal, and has nothing to tune.
  if (tracker.dailyTarget <= 0) return null;

  final values = <double>[
    for (final entry in log.entries)
      if (inWindow(entry.key)) entry.value,
  ];

  final tuned = _recalibrate(
    values: values,
    target: tracker.dailyTarget,
    grain: tracker.step < 1 ? 1 : tracker.step,
    min: tracker.lowerIsBetter ? 0 : 1,
    max: 100000,
    lowerIsBetter: tracker.lowerIsBetter,
  );
  if (tuned == null) return null;

  return CustomGoalSuggestion(
    id: 'custom:${tracker.id}',
    label: tracker.name,
    icon: tracker.icon,
    currentLabel: tracker.format(tracker.dailyTarget),
    proposedLabel: tracker.format(tuned.proposed),
    rationale: _rationale(
      tuned,
      'days you logged it',
      tracker.format(tuned.proposed),
    ),
    isEasing: tuned.easing,
    samples: values.length,
    hitRate: tuned.hitRate,
    tracker: tracker,
    proposedTarget: tuned.proposed,
  );
}

/// The measurement behind one suggestion.
typedef _Tuned = ({
  int proposed,
  double hitRate,
  int hits,
  int samples,
  bool easing,
});

/// Decides whether a target is mis-set, and what to move it to.
///
/// Returns null for the case that should be the common one: a target that is
/// being met often enough to mean something and missed often enough to ask for
/// something. Silence is the right output for a goal that is working.
_Tuned? _recalibrate({
  required List<double> values,
  required int target,
  required int grain,
  required int min,
  required int max,
  bool lowerIsBetter = false,
  int minimumSamples = GoalSuggestion.minimumDays,
}) {
  if (values.length < minimumSamples) return null;

  var hits = 0;
  for (final value in values) {
    if (lowerIsBetter ? value <= target : value >= target) hits++;
  }
  final hitRate = hits / values.length;

  final tooHard = hitRate < GoalSuggestion._tooHard;
  final tooEasy = hitRate > GoalSuggestion._tooEasy;
  if (!tooHard && !tooEasy) return null;

  final sorted = [...values]..sort();
  // Both directions aim at the same landing point, which is what lets one rule
  // both rescue an impossible target and retire an outgrown one: the level met
  // on roughly six samples in ten. For a floor that is the 40th percentile,
  // since six in ten sit above it; for a ceiling, the 60th.
  final fraction = lowerIsBetter
      ? GoalSuggestion._landing
      : 1 - GoalSuggestion._landing;

  final raw = _percentile(sorted, fraction);
  final proposed = ((raw / grain).round() * grain).clamp(min, max);
  if (proposed == target) return null;

  // A nudge smaller than the tracker's own grain, or than a twentieth of the
  // target, is not worth interrupting anybody for.
  final change = (proposed - target).abs();
  if (change < grain || change * 20 < target) return null;

  return (
    proposed: proposed,
    hitRate: hitRate,
    hits: hits,
    samples: values.length,
    easing: lowerIsBetter ? proposed > target : proposed < target,
  );
}

String _rationale(_Tuned tuned, String noun, String proposedLabel) {
  final met = 'Met on ${tuned.hits} of the last ${tuned.samples} $noun.';
  return tuned.easing
      ? '$met $proposedLabel is what you would have managed on about six in '
            'ten — a target you land on is worth more than one you aim at, and '
            'it can go back up once it is boring.'
      : '$met The target has stopped asking for anything. $proposedLabel would '
            'still be a six-in-ten day.';
}

double _percentile(List<double> sorted, double fraction) {
  if (sorted.isEmpty) return 0;
  if (sorted.length == 1) return sorted.first;

  final position = fraction * (sorted.length - 1);
  final lower = position.floor();
  final upper = position.ceil();
  if (lower == upper) return sorted[lower];
  return sorted[lower] + (sorted[upper] - sorted[lower]) * (position - lower);
}
