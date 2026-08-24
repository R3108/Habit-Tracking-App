import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../habit.dart';
import 'tracker_goals.dart';

/// One night's sleep, filed under the morning it ended.
///
/// Filed by waking day rather than by bedtime because that is the only choice
/// that survives the interesting cases: someone who goes to bed at 01:30 has
/// not skipped a night, and someone who naps at 22:00 on Monday and again at
/// 02:00 has not slept twice on Monday. "The night before Tuesday morning" is
/// unambiguous; "Monday's sleep" is not.
@immutable
class SleepEntry {
  const SleepEntry({
    required this.day,
    required this.bedMinutes,
    required this.wakeMinutes,
    this.quality = 3,
    this.note = '',
  });

  /// The morning the night ended, date-only.
  final DateTime day;

  /// Times as minutes from midnight, 0..1439.
  final int bedMinutes;
  final int wakeMinutes;

  /// How it felt, 1 (awful) to 5 (excellent).
  final int quality;

  final String note;

  /// Minutes asleep, wrapping around midnight.
  ///
  /// A bedtime of 23:00 and a wake of 07:00 is eight hours, not minus sixteen.
  int get durationMinutes => (wakeMinutes - bedMinutes + 1440) % 1440;

  /// Bedtime on a scale where "late" is always a bigger number.
  ///
  /// Clock arithmetic makes 23:50 and 00:10 look twenty hours apart, which
  /// would wreck any average or spread taken over them. Anything before noon is
  /// pushed into the following day, so a night's bedtimes land in one
  /// continuous band and ordinary statistics work on them.
  int get nightBedMinutes => bedMinutes < 720 ? bedMinutes + 1440 : bedMinutes;

  /// The clock midpoint of the night, on the same shifted scale.
  ///
  /// Midpoint rather than bedtime is what chronobiology compares between work
  /// days and free days, because it absorbs the fact that a long lie-in and a
  /// late night are the same displacement.
  double get midSleepMinutes => nightBedMinutes + durationMinutes / 2;

  /// True for a night whose morning falls on a Saturday or Sunday.
  bool get isFreeNight =>
      day.weekday == DateTime.saturday || day.weekday == DateTime.sunday;

  SleepEntry copyWith({
    int? bedMinutes,
    int? wakeMinutes,
    int? quality,
    String? note,
  }) {
    return SleepEntry(
      day: day,
      bedMinutes: bedMinutes ?? this.bedMinutes,
      wakeMinutes: wakeMinutes ?? this.wakeMinutes,
      quality: quality ?? this.quality,
      note: note ?? this.note,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'bed': bedMinutes,
    'wake': wakeMinutes,
    'quality': quality,
    'note': note,
  };

  static SleepEntry? fromJson(DateTime day, Map<String, dynamic> json) {
    final bed = (json['bed'] as num?)?.toInt();
    final wake = (json['wake'] as num?)?.toInt();
    if (bed == null || wake == null) return null;

    return SleepEntry(
      day: dateOnly(day),
      bedMinutes: bed.clamp(0, 1439),
      wakeMinutes: wake.clamp(0, 1439),
      quality: ((json['quality'] as num?)?.toInt() ?? 3).clamp(1, 5),
      note: json['note'] as String? ?? '',
    );
  }
}

/// What a stretch of nights adds up to.
///
/// The three numbers past the average are the ones a sleep log can offer that a
/// bedside clock cannot: how much sleep is owed, how *regular* the schedule is,
/// and how far the weekend drags it around. Regularity in particular tracks
/// health outcomes at least as closely as duration does, and nobody notices it
/// without being shown.
@immutable
class SleepInsights {
  const SleepInsights._({
    required this.nights,
    required this.averageMinutes,
    required this.debtMinutes,
    required this.consistencyScore,
    required this.socialJetlagMinutes,
    required this.averageQuality,
    required this.goalNights,
  });

  /// Nights with data inside the window.
  final int nights;

  final int averageMinutes;

  /// Total sleep owed against the goal across the window, floored at zero per
  /// night — a ten-hour Sunday does not repay a four-hour Tuesday, and pretending
  /// it does is how a log talks somebody out of a real deficit.
  final int debtMinutes;

  /// 0..100, from the spread of bedtimes. 100 is the same time every night.
  final int consistencyScore;

  /// How far the mid-point of sleep shifts between work nights and free
  /// nights. Null when the window has too little of one kind to compare.
  final int? socialJetlagMinutes;

  final double averageQuality;

  /// Nights that met or beat the target.
  final int goalNights;

  static const int windowDays = 14;

  bool get hasData => nights > 0;

  double get goalShare => nights == 0 ? 0 : goalNights / nights;

  /// A bedtime spread of this many minutes scores zero.
  ///
  /// Two hours either side of the mean is genuinely irregular sleep; anything
  /// past it is not worth grading more finely.
  static const double _spreadForZero = 120;

  factory SleepInsights.from(
    Map<DateTime, SleepEntry> log, {
    required TrackerGoals goals,
    DateTime? reference,
    int window = windowDays,
  }) {
    final today = dateOnly(reference ?? DateTime.now());
    final entries = <SleepEntry>[
      for (var age = 0; age < window; age++) ?log[addDays(today, -age)],
    ];

    if (entries.isEmpty) {
      return const SleepInsights._(
        nights: 0,
        averageMinutes: 0,
        debtMinutes: 0,
        consistencyScore: 0,
        socialJetlagMinutes: null,
        averageQuality: 0,
        goalNights: 0,
      );
    }

    var totalMinutes = 0;
    var debt = 0;
    var goalNights = 0;
    var quality = 0;
    for (final entry in entries) {
      totalMinutes += entry.durationMinutes;
      quality += entry.quality;
      final short = goals.sleepMinutes - entry.durationMinutes;
      if (short > 0) debt += short;
      if (entry.durationMinutes >= goals.sleepMinutes) goalNights++;
    }

    final bedtimes = entries.map((e) => e.nightBedMinutes.toDouble()).toList();
    final spread = _standardDeviation(bedtimes);
    // A single night has no spread to speak of; calling that perfect regularity
    // would hand out a 100 for one tap.
    final consistency = entries.length < 3
        ? 0
        : (100 * (1 - math.min(spread / _spreadForZero, 1))).round();

    return SleepInsights._(
      nights: entries.length,
      averageMinutes: (totalMinutes / entries.length).round(),
      debtMinutes: debt,
      consistencyScore: consistency,
      socialJetlagMinutes: _socialJetlag(entries),
      averageQuality: quality / entries.length,
      goalNights: goalNights,
    );
  }

  /// Difference between the average mid-sleep on free nights and on work
  /// nights, in minutes.
  ///
  /// Null unless both groups have at least two nights: one Saturday against
  /// nine weekdays is an anecdote, and reporting it as a body-clock finding
  /// would be worse than saying nothing.
  static int? _socialJetlag(List<SleepEntry> entries) {
    final free = entries.where((e) => e.isFreeNight).toList();
    final work = entries.where((e) => !e.isFreeNight).toList();
    if (free.length < 2 || work.length < 2) return null;

    final freeMid =
        free.fold<double>(0, (sum, e) => sum + e.midSleepMinutes) / free.length;
    final workMid =
        work.fold<double>(0, (sum, e) => sum + e.midSleepMinutes) / work.length;

    return (freeMid - workMid).abs().round();
  }

  static double _standardDeviation(List<double> values) {
    if (values.length < 2) return 0;
    final mean = values.reduce((a, b) => a + b) / values.length;
    final variance =
        values.fold<double>(0, (sum, v) => sum + math.pow(v - mean, 2)) /
        values.length;
    return math.sqrt(variance);
  }
}
