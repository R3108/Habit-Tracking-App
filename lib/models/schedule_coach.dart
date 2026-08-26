import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'habit.dart';

/// What a suggestion proposes doing to a schedule.
enum ScheduleChange {
  /// Stop asking for a weekday that is almost never kept.
  dropWeekday,

  /// Trade fixed days for a weekly quota, when the misses move around.
  switchToQuota,

  /// Lower a weekly quota to what is actually being hit.
  easeQuota,

  /// Raise a weekly quota that is being beaten every week.
  raiseQuota,
}

/// A concrete change to one habit's schedule, with the evidence for it.
///
/// Every other analysis in the app describes; this one prescribes, and applying
/// it is a single tap. That is a real difference in kind, so the bar is higher:
/// a suggestion is only made when the history is long enough to have earned it,
/// the gap is wide enough to matter, and the change is one the user could have
/// reasoned their way to from the same numbers.
///
/// A schedule change moves what the app *expects*, not what the user does. Ease
/// a quota and tomorrow's completion rate rises without a single extra thing
/// being done. That is legitimate — a plan nobody can keep is worse than a
/// smaller plan that gets kept — but it must never be smuggled in as progress,
/// so every string here names the trade, and the screen says it too.
@immutable
class ScheduleSuggestion {
  const ScheduleSuggestion._({
    required this.habitId,
    required this.change,
    required this.proposed,
    required this.headline,
    required this.rationale,
    required this.daysConsidered,
    required this.impact,
  });

  final String habitId;
  final ScheduleChange change;

  /// The schedule to swap in, ready to hand to the store.
  final HabitSchedule proposed;

  /// The change in three or four words: "Drop Fridays".
  final String headline;

  /// Why, in numbers the user can check against their own memory.
  final String rationale;

  final int daysConsidered;

  /// Roughly how many missed due days a window like the last one would stop
  /// producing. Used only for ranking — it is not shown, because "saves you 9
  /// failures" is precisely the framing this feature must avoid.
  final int impact;

  /// How far back the coach looks: twelve weeks, so every weekday has a dozen
  /// chances to show its pattern.
  static const int windowDays = 84;

  /// A habit younger than this has not lived long enough to be re-planned.
  static const int minimumAgeDays = 28;

  /// Due days needed in the window before any suggestion is made.
  static const int minimumDueDays = 21;

  /// Times a weekday must have come round before it can be called a problem.
  static const int minimumPerWeekday = 4;

  /// The gap between the worst weekday and the rest that makes it the problem
  /// rather than a bad run.
  static const double minimumWeekdayGap = 0.35;
}

/// The changes worth offering across [habits], most useful first.
///
/// At most one suggestion per habit: offering two ways to rewrite the same
/// schedule turns a prompt into a form, and the second-best idea is never worth
/// that. Capped overall for the same reason the discovery list is — a screen of
/// nine suggestions is a screen nobody reads.
List<ScheduleSuggestion> scheduleSuggestions(
  List<Habit> habits, {
  DateTime? reference,
  int window = ScheduleSuggestion.windowDays,
  int limit = 3,
}) {
  final today = dateOnly(reference ?? DateTime.now());

  final found = <ScheduleSuggestion>[
    for (final habit in habits)
      if (!habit.archived)
        ?_suggestFor(habit, today: today, window: window),
  ]..sort((a, b) => b.impact.compareTo(a.impact));

  return found.take(limit).toList();
}

/// The single best change for one habit, or null when its plan already fits.
///
/// Order matters. Dropping a weekday is the most surgical change available and
/// leaves the rest of the schedule intact, so it is tried first; rewriting a
/// fixed schedule into a quota is the largest change, so it is tried last.
ScheduleSuggestion? _suggestFor(
  Habit habit, {
  required DateTime today,
  required int window,
}) {
  if (today.difference(habit.createdAt).inDays <
      ScheduleSuggestion.minimumAgeDays) {
    return null;
  }

  final stats = _WeekdayStats.of(habit, today: today, window: window);
  if (stats.dueDays < ScheduleSuggestion.minimumDueDays) return null;

  return switch (habit.schedule.frequency) {
    HabitFrequency.timesPerWeek => _quotaChange(habit, stats),
    _ => _dropWeekday(habit, stats) ?? _switchToQuota(habit, stats),
  };
}

/// Proposes losing the one weekday that is dragging the habit down.
ScheduleSuggestion? _dropWeekday(Habit habit, _WeekdayStats stats) {
  final scheduled = <int>[
    for (var weekday = 1; weekday <= 7; weekday++)
      if (habit.schedule.isDueOn(_anyDayWithWeekday(weekday)) &&
          stats.due[weekday - 1] >= ScheduleSuggestion.minimumPerWeekday)
        weekday,
  ];
  // Below three days there is no "rest of the schedule" left to compare
  // against, and dropping one would halve the habit rather than tune it.
  if (scheduled.length < 3) return null;

  final worst = scheduled.reduce(
    (a, b) => stats.rate(a) <= stats.rate(b) ? a : b,
  );

  var otherDue = 0;
  var otherDone = 0;
  for (final weekday in scheduled) {
    if (weekday == worst) continue;
    otherDue += stats.due[weekday - 1];
    otherDone += stats.done[weekday - 1];
  }
  if (otherDue == 0) return null;

  final worstRate = stats.rate(worst);
  final otherRate = otherDone / otherDue;
  if (otherRate - worstRate < ScheduleSuggestion.minimumWeekdayGap) return null;
  // A weekday kept half the time is a weekday worth keeping.
  if (worstRate > 0.4) return null;

  final remaining = <int>{
    for (final weekday in scheduled)
      if (weekday != worst) weekday,
    // Weekdays the schedule asks for but that have not come round often enough
    // to judge stay in: silence is not evidence against them.
    for (var weekday = 1; weekday <= 7; weekday++)
      if (habit.schedule.isDueOn(_anyDayWithWeekday(weekday)) &&
          stats.due[weekday - 1] < ScheduleSuggestion.minimumPerWeekday)
        weekday,
  };

  final name = _weekdayNames[worst - 1];
  return ScheduleSuggestion._(
    habitId: habit.id,
    change: ScheduleChange.dropWeekday,
    proposed: HabitSchedule.onDays(remaining),
    headline: 'Stop asking on $name',
    rationale:
        '$name run at ${(worstRate * 100).round()}% against '
        '${(otherRate * 100).round()}% on your other days, over '
        '${stats.due[worst - 1]} of them. Taking the day out of the schedule '
        'leaves the habit where it works.',
    daysConsidered: stats.dueDays,
    impact: stats.due[worst - 1] - stats.done[worst - 1],
  );
}

/// Proposes a weekly quota when the habit happens often enough but never on a
/// predictable day.
///
/// The case this exists for: someone who genuinely goes to the gym four times
/// most weeks, has it scheduled for five fixed days, and reads as a 70% failure
/// forever. The quota is not a lower standard — it is the standard they are
/// already meeting, written down accurately.
ScheduleSuggestion? _switchToQuota(Habit habit, _WeekdayStats stats) {
  final rate = stats.overallRate;
  // Above 80% the schedule is basically working; below 35% the problem is not
  // the shape of the plan, and a quota would just be a quieter failure.
  if (rate < 0.35 || rate > 0.8) return null;

  // A clustered miss is the other suggestion's job. This one is for misses that
  // move around.
  if (stats.weekdaySpread >= ScheduleSuggestion.minimumWeekdayGap) return null;

  final weekly = stats.weeklyCompletions;
  if (weekly.length < 6) return null;

  final typical = _median(weekly).round().clamp(1, 6);
  final target = habit.schedule.weeklyTarget;
  if (typical >= target) return null;
  if (stats.weeklySpread > 1.2) return null;

  return ScheduleSuggestion._(
    habitId: habit.id,
    change: ScheduleChange.switchToQuota,
    proposed: HabitSchedule.timesAWeek(typical),
    headline: 'Try $typical× a week',
    rationale:
        'You finish this about $typical days in most weeks, but rarely the '
        'same $typical — no single weekday is the problem. A quota counts what '
        'you actually do instead of marking $target fixed days and missing '
        '${target - typical} of them.',
    daysConsidered: stats.dueDays,
    impact: stats.dueDays - stats.doneDays,
  );
}

/// Retunes a quota that has drifted away from reality in either direction.
ScheduleSuggestion? _quotaChange(Habit habit, _WeekdayStats stats) {
  final weekly = stats.weeklyCompletions;
  if (weekly.length < 6) return null;

  final typical = _median(weekly).round();
  final target = habit.schedule.timesPerWeek;

  // Two clear of the target in either direction. One is a rounding argument.
  if (typical <= target - 2) {
    final proposed = typical.clamp(1, 7);
    return ScheduleSuggestion._(
      habitId: habit.id,
      change: ScheduleChange.easeQuota,
      proposed: HabitSchedule.timesAWeek(proposed),
      headline: 'Ease to $proposed× a week',
      rationale:
          'The quota says $target× and the median week has been $typical for '
          '${weekly.length} weeks. A target you land on is worth more than one '
          'you aim at — you can put it back up once $proposed is boring.',
      daysConsidered: stats.dueDays,
      impact: (target - typical) * 4,
    );
  }

  if (typical >= target + 1 && weekly.length >= 6) {
    final beaten = weekly.where((w) => w > target).length;
    // Beating it now and then is not the same as having outgrown it.
    if (beaten * 3 < weekly.length * 2) return null;

    final proposed = typical.clamp(1, 7);
    if (proposed == target) return null;

    return ScheduleSuggestion._(
      habitId: habit.id,
      change: ScheduleChange.raiseQuota,
      proposed: HabitSchedule.timesAWeek(proposed),
      headline: 'Raise to $proposed× a week',
      rationale:
          'You have beaten the $target× quota in $beaten of the last '
          '${weekly.length} weeks, with a median of $typical. The target is no '
          'longer the thing holding the habit up.',
      daysConsidered: stats.dueDays,
      impact: (typical - target) * 3,
    );
  }

  return null;
}

/// A habit's window, sliced by weekday and by week.
///
/// Computed in one walk. The three suggestion rules each need a different cut
/// of the same days, and walking twelve weeks three times per habit per rebuild
/// is the sort of thing that shows up as jank on the one screen that shows it.
class _WeekdayStats {
  _WeekdayStats._({
    required this.due,
    required this.done,
    required this.weeklyCompletions,
    required this.dueDays,
    required this.doneDays,
  });

  /// Due and completed counts per ISO weekday, indexed 0 = Monday.
  final List<int> due;
  final List<int> done;

  /// Completions in each whole week of the window, oldest first.
  final List<int> weeklyCompletions;

  final int dueDays;
  final int doneDays;

  double get overallRate => dueDays == 0 ? 0 : doneDays / dueDays;

  double rate(int weekday) =>
      due[weekday - 1] == 0 ? 0 : done[weekday - 1] / due[weekday - 1];

  /// The gap between the best and worst weekday that has enough days behind it.
  ///
  /// Zero when fewer than three weekdays qualify: with two there is nothing to
  /// call a spread, and calling one of them "worst" would be a coin toss.
  double get weekdaySpread {
    final scored = <double>[
      for (var weekday = 1; weekday <= 7; weekday++)
        if (due[weekday - 1] >= ScheduleSuggestion.minimumPerWeekday)
          rate(weekday),
    ];
    if (scored.length < 3) return 0;

    var lowest = scored.first;
    var highest = scored.first;
    for (final value in scored) {
      if (value < lowest) lowest = value;
      if (value > highest) highest = value;
    }
    return highest - lowest;
  }

  /// Standard deviation of the weekly completion counts.
  double get weeklySpread {
    if (weeklyCompletions.length < 2) return 0;
    final mean =
        weeklyCompletions.reduce((a, b) => a + b) / weeklyCompletions.length;
    var sum = 0.0;
    for (final week in weeklyCompletions) {
      sum += (week - mean) * (week - mean);
    }
    return math.sqrt(sum / weeklyCompletions.length);
  }

  factory _WeekdayStats.of(
    Habit habit, {
    required DateTime today,
    required int window,
  }) {
    final due = List<int>.filled(7, 0);
    final done = List<int>.filled(7, 0);
    var dueDays = 0;
    var doneDays = 0;

    for (var age = 1; age <= window; age++) {
      final day = addDays(today, -age);
      if (!habit.isDueOn(day)) continue;

      due[day.weekday - 1]++;
      dueDays++;
      if (habit.isCompletedOn(day)) {
        done[day.weekday - 1]++;
        doneDays++;
      }
    }

    // Whole weeks only, counted back from yesterday. A part-week at either end
    // would look like a bad week and drag the median down.
    final weekly = <int>[];
    for (var start = 7; start <= window; start += 7) {
      var count = 0;
      for (var offset = 0; offset < 7; offset++) {
        if (habit.isCompletedOn(addDays(today, -(start - offset)))) count++;
      }
      weekly.insert(0, count);
    }

    return _WeekdayStats._(
      due: due,
      done: done,
      weeklyCompletions: weekly,
      dueDays: dueDays,
      doneDays: doneDays,
    );
  }
}

const List<String> _weekdayNames = <String>[
  'Mondays',
  'Tuesdays',
  'Wednesdays',
  'Thursdays',
  'Fridays',
  'Saturdays',
  'Sundays',
];

/// Any concrete date with the given ISO weekday, for asking a schedule whether
/// it covers that weekday at all.
DateTime _anyDayWithWeekday(int weekday) => DateTime(2024, 1, weekday);

double _median(List<int> values) {
  final sorted = [...values]..sort();
  final middle = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[middle].toDouble();
  return (sorted[middle - 1] + sorted[middle]) / 2;
}
