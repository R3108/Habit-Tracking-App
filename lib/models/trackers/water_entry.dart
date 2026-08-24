import 'package:flutter/foundation.dart';

import '../habit.dart';
import 'tracker_goals.dart';

/// What a run of days of drinking adds up to.
///
/// Water is the one tracker where the useful question is not "how did I do
/// yesterday" but "am I behind *right now*" — the answer is still actionable at
/// four in the afternoon, which is not true of sleep or a workout. [pace] is
/// the number the screen is built around.
@immutable
class WaterInsights {
  const WaterInsights._({
    required this.today,
    required this.goal,
    required this.expectedByNow,
    required this.averageMl,
    required this.daysLogged,
    required this.goalStreak,
    required this.bestDay,
  });

  final int today;
  final int goal;

  /// How much a steady drinker would have had by this time of day.
  final int expectedByNow;

  /// Mean intake across the logged days in the window.
  final int averageMl;

  final int daysLogged;

  /// Consecutive days ending today that reached the goal.
  ///
  /// Today counts only once it is met: an unfinished morning must not read as a
  /// broken streak, so the count falls back to yesterday exactly as a habit
  /// streak does.
  final int goalStreak;

  final int bestDay;

  static const int windowDays = 30;

  /// Waking hours the pace is spread across.
  ///
  /// Not midnight to midnight: nobody drinks a sixth of their day's water
  /// before 04:00, and a pace line that says they are behind at breakfast is
  /// one they will learn to ignore.
  static const int _dayStartMinutes = 7 * 60;
  static const int _dayEndMinutes = 23 * 60;

  double get share => goal == 0 ? 0 : (today / goal).clamp(0.0, 1.0);

  bool get isMet => today >= goal;

  /// How far ahead (positive) or behind (negative) the steady pace.
  int get paceDifference => today - expectedByNow;

  /// True when the day is young enough that pace means nothing yet.
  bool get isTooEarlyToJudge => expectedByNow <= 0;

  factory WaterInsights.from(
    Map<DateTime, int> log, {
    required TrackerGoals goals,
    DateTime? reference,
    int window = windowDays,
  }) {
    final now = reference ?? DateTime.now();
    final today = dateOnly(now);

    var total = 0;
    var days = 0;
    var best = 0;
    for (var age = 0; age < window; age++) {
      final ml = log[addDays(today, -age)] ?? 0;
      if (ml <= 0) continue;
      total += ml;
      days++;
      if (ml > best) best = ml;
    }

    final minutesIntoDay = now.hour * 60 + now.minute;
    final elapsed =
        ((minutesIntoDay - _dayStartMinutes) /
                (_dayEndMinutes - _dayStartMinutes))
            .clamp(0.0, 1.0);

    return WaterInsights._(
      today: log[today] ?? 0,
      goal: goals.waterMl,
      expectedByNow: (goals.waterMl * elapsed).round(),
      averageMl: days == 0 ? 0 : (total / days).round(),
      daysLogged: days,
      goalStreak: _streak(log, goals.waterMl, today),
      bestDay: best,
    );
  }

  static int _streak(Map<DateTime, int> log, int goal, DateTime today) {
    var cursor = today;
    if ((log[cursor] ?? 0) < goal) cursor = addDays(cursor, -1);

    var count = 0;
    // A year is a generous ceiling and guarantees termination on a log that
    // somehow contains every day.
    for (var i = 0; i < 366; i++) {
      if ((log[cursor] ?? 0) < goal) break;
      count++;
      cursor = addDays(cursor, -1);
    }
    return count;
  }
}

/// The quick-add buttons offered on the water screen.
///
/// Fixed sizes rather than a number pad: logging a drink has to cost one tap or
/// it will not happen at the sink, and the exact millilitre is noise against a
/// two-litre target.
const List<({String label, int ml})> kDrinkSizes = <({String label, int ml})>[
  (label: 'Glass', ml: 250),
  (label: 'Mug', ml: 350),
  (label: 'Bottle', ml: 500),
  (label: 'Large', ml: 750),
];
