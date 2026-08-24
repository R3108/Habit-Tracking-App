import 'package:flutter/foundation.dart';

import '../habit.dart';

/// A day's mood and energy, on the coarsest scale that still carries signal.
///
/// Everything else in the app measures what you *did*. This is the only thing
/// that measures how it went, which makes it the outcome every other tracker
/// can be tested against: "I ran four times this week" is an input, and without
/// something like this the app can never say whether it mattered.
///
/// Five points, not ten. People cannot reliably tell a 6 from a 7 about their
/// own Tuesday, and a scale finer than the judgement behind it just adds noise
/// to every correlation drawn from it.
@immutable
class CheckIn {
  const CheckIn({
    required this.day,
    required this.mood,
    required this.energy,
    this.note = '',
  });

  final DateTime day;

  /// 1 (rough) to 5 (great).
  final int mood;

  /// 1 (drained) to 5 (energised).
  final int energy;

  final String note;

  /// The two averaged, for a single "how was the day" number.
  double get overall => (mood + energy) / 2;

  CheckIn copyWith({int? mood, int? energy, String? note}) => CheckIn(
    day: day,
    mood: mood ?? this.mood,
    energy: energy ?? this.energy,
    note: note ?? this.note,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'mood': mood,
    'energy': energy,
    'note': note,
  };

  static CheckIn? fromJson(DateTime day, Map<String, dynamic> json) {
    final mood = (json['mood'] as num?)?.toInt();
    final energy = (json['energy'] as num?)?.toInt();
    if (mood == null || energy == null) return null;

    return CheckIn(
      day: dateOnly(day),
      mood: mood.clamp(1, 5),
      energy: energy.clamp(1, 5),
      note: json['note'] as String? ?? '',
    );
  }
}

/// Labels for the five points, so the scale means the same thing every time it
/// is shown.
const List<String> kMoodLabels = <String>[
  'Rough',
  'Low',
  'Fine',
  'Good',
  'Great',
];

const List<String> kEnergyLabels = <String>[
  'Drained',
  'Tired',
  'Steady',
  'Lively',
  'Buzzing',
];

/// What a run of check-ins adds up to.
@immutable
class CheckInInsights {
  const CheckInInsights._({
    required this.daysLogged,
    required this.averageMood,
    required this.averageEnergy,
    required this.moodTrend,
    required this.bestWeekday,
    required this.worstWeekday,
    required this.streak,
  });

  final int daysLogged;
  final double averageMood;
  final double averageEnergy;

  /// Change in average mood against the previous window of the same length.
  /// Null when there is no earlier window to compare with.
  final double? moodTrend;

  /// ISO weekday with the highest and lowest average mood, or null when the
  /// window has too few distinct weekdays to rank them.
  final int? bestWeekday;
  final int? worstWeekday;

  /// Consecutive days ending today (or yesterday) with a check-in.
  final int streak;

  static const int windowDays = 30;

  bool get hasData => daysLogged > 0;

  /// A weekday needs this many days behind it before it is called best or
  /// worst — one bad Monday is not a pattern.
  static const int _minimumPerWeekday = 2;

  factory CheckInInsights.from(
    Map<DateTime, CheckIn> log, {
    DateTime? reference,
    int window = windowDays,
  }) {
    final today = dateOnly(reference ?? DateTime.now());

    var moodTotal = 0;
    var energyTotal = 0;
    var days = 0;
    final byWeekday = <int, List<int>>{};

    for (var age = 0; age < window; age++) {
      final entry = log[addDays(today, -age)];
      if (entry == null) continue;

      days++;
      moodTotal += entry.mood;
      energyTotal += entry.energy;
      (byWeekday[entry.day.weekday] ??= <int>[]).add(entry.mood);
    }

    if (days == 0) {
      return const CheckInInsights._(
        daysLogged: 0,
        averageMood: 0,
        averageEnergy: 0,
        moodTrend: null,
        bestWeekday: null,
        worstWeekday: null,
        streak: 0,
      );
    }

    // The window before this one, for the trend.
    var priorTotal = 0;
    var priorDays = 0;
    for (var age = window; age < window * 2; age++) {
      final entry = log[addDays(today, -age)];
      if (entry == null) continue;
      priorDays++;
      priorTotal += entry.mood;
    }

    final ranked =
        byWeekday.entries
            .where((e) => e.value.length >= _minimumPerWeekday)
            .map(
              (e) => (
                weekday: e.key,
                mean: e.value.reduce((a, b) => a + b) / e.value.length,
              ),
            )
            .toList()
          ..sort((a, b) => b.mean.compareTo(a.mean));

    return CheckInInsights._(
      daysLogged: days,
      averageMood: moodTotal / days,
      averageEnergy: energyTotal / days,
      moodTrend: priorDays == 0
          ? null
          : (moodTotal / days) - (priorTotal / priorDays),
      // Naming a best and a worst needs at least two weekdays to compare, or
      // the same day would be both.
      bestWeekday: ranked.length < 2 ? null : ranked.first.weekday,
      worstWeekday: ranked.length < 2 ? null : ranked.last.weekday,
      streak: _streak(log, today),
    );
  }

  static int _streak(Map<DateTime, CheckIn> log, DateTime today) {
    var cursor = today;
    // Today not being logged yet must not read as a broken run — the same rule
    // habit streaks follow.
    if (!log.containsKey(cursor)) cursor = addDays(cursor, -1);

    var count = 0;
    for (var i = 0; i < 366; i++) {
      if (!log.containsKey(cursor)) break;
      count++;
      cursor = addDays(cursor, -1);
    }
    return count;
  }
}
