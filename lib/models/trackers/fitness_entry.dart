import 'package:flutter/foundation.dart';

import '../habit.dart';
import 'tracker_goals.dart';

/// The shape of a workout.
enum WorkoutType { cardio, strength, mobility, sport, walk }

extension WorkoutTypeLabel on WorkoutType {
  String get label => switch (this) {
    WorkoutType.cardio => 'Cardio',
    WorkoutType.strength => 'Strength',
    WorkoutType.mobility => 'Mobility',
    WorkoutType.sport => 'Sport',
    WorkoutType.walk => 'Walk',
  };
}

/// How hard it was, on the coarsest scale that still carries information.
enum Intensity { easy, moderate, hard }

extension IntensityInfo on Intensity {
  String get label => switch (this) {
    Intensity.easy => 'Easy',
    Intensity.moderate => 'Moderate',
    Intensity.hard => 'Hard',
  };

  /// The multiplier used to turn minutes into training load.
  ///
  /// This is session-RPE in its simplest form: load is duration times
  /// perceived effort. Twenty minutes flat out and an hour's stroll are not
  /// the same stimulus, and a tracker that adds raw minutes cannot tell them
  /// apart.
  int get weight => switch (this) {
    Intensity.easy => 1,
    Intensity.moderate => 2,
    Intensity.hard => 3,
  };

  /// Whether this counts toward the weekly moderate-activity guideline.
  bool get isModerateOrAbove => this != Intensity.easy;
}

/// One session.
@immutable
class Workout {
  const Workout({
    required this.id,
    required this.day,
    required this.type,
    required this.minutes,
    this.intensity = Intensity.moderate,
    this.note = '',
  });

  final String id;
  final DateTime day;
  final WorkoutType type;
  final int minutes;
  final Intensity intensity;
  final String note;

  int get load => minutes * intensity.weight;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'day': encodeDay(day),
    'type': type.name,
    'minutes': minutes,
    'intensity': intensity.name,
    'note': note,
  };

  static Workout? fromJson(Map<String, dynamic> json) {
    final day = decodeDay(json['day'] as String?);
    if (day == null) return null;

    return Workout(
      id: json['id'] as String? ?? 'workout-${day.millisecondsSinceEpoch}',
      day: day,
      type: WorkoutType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => WorkoutType.cardio,
      ),
      minutes: ((json['minutes'] as num?)?.toInt() ?? 0).clamp(0, 1440),
      intensity: Intensity.values.firstWhere(
        (i) => i.name == json['intensity'],
        orElse: () => Intensity.moderate,
      ),
      note: json['note'] as String? ?? '',
    );
  }
}

/// How the current week's training compares with what the body is used to.
enum LoadVerdict {
  /// Not enough history to say anything.
  unknown,

  /// Training has dropped well below the recent norm.
  detraining,

  /// In the range that sustains and builds fitness.
  steady,

  /// Ramping up faster than the base supports.
  spiking,
}

extension LoadVerdictLabel on LoadVerdict {
  String get label => switch (this) {
    LoadVerdict.unknown => 'Building a baseline',
    LoadVerdict.detraining => 'Winding down',
    LoadVerdict.steady => 'Sustainable',
    LoadVerdict.spiking => 'Ramping up fast',
  };
}

/// What the workout log adds up to.
@immutable
class FitnessInsights {
  const FitnessInsights._({
    required this.activeMinutesThisWeek,
    required this.sessionsThisWeek,
    required this.acuteLoad,
    required this.chronicLoad,
    required this.byType,
    required this.restDaysThisWeek,
    required this.longestSessionMinutes,
  });

  /// Minutes at moderate intensity or above over the last seven days.
  ///
  /// Easy sessions are deliberately excluded: the guideline this is measured
  /// against is about moderate activity, and counting a gentle walk toward it
  /// would let the app congratulate somebody for missing the point.
  final int activeMinutesThisWeek;

  final int sessionsThisWeek;

  /// Training load over the last 7 days.
  final int acuteLoad;

  /// Average weekly load over the last 28 days — what the body is adapted to.
  final int chronicLoad;

  /// Minutes per workout type over the window, biggest first.
  final List<({WorkoutType type, int minutes})> byType;

  final int restDaysThisWeek;
  final int longestSessionMinutes;

  static const int acuteDays = 7;
  static const int chronicDays = 28;

  /// Acute load against chronic load.
  ///
  /// The ratio sports science uses to spot a training spike: doing far more
  /// this week than the last month has prepared you for is where injuries
  /// come from. Null until there is a month of history to divide by, because
  /// the number is meaningless without a baseline — and a tracker that invents
  /// one is worse than a tracker that admits it does not know yet.
  double? get loadRatio {
    if (chronicLoad <= 0) return null;
    return acuteLoad / chronicLoad;
  }

  LoadVerdict get verdict {
    final ratio = loadRatio;
    if (ratio == null) return LoadVerdict.unknown;
    if (ratio < 0.8) return LoadVerdict.detraining;
    if (ratio > 1.5) return LoadVerdict.spiking;
    return LoadVerdict.steady;
  }

  double goalShare(TrackerGoals goals) {
    if (goals.activeMinutesPerWeek <= 0) return 0;
    return (activeMinutesThisWeek / goals.activeMinutesPerWeek).clamp(0.0, 1.0);
  }

  factory FitnessInsights.from(
    List<Workout> workouts, {
    DateTime? reference,
  }) {
    final today = dateOnly(reference ?? DateTime.now());
    final weekStart = addDays(today, -(acuteDays - 1));
    final monthStart = addDays(today, -(chronicDays - 1));

    var activeMinutes = 0;
    var sessionsThisWeek = 0;
    var acute = 0;
    var chronic = 0;
    var longest = 0;
    final trainedDays = <DateTime>{};
    final perType = <WorkoutType, int>{};

    for (final workout in workouts) {
      if (workout.day.isAfter(today) || workout.day.isBefore(monthStart)) {
        continue;
      }

      chronic += workout.load;
      perType[workout.type] = (perType[workout.type] ?? 0) + workout.minutes;

      if (!workout.day.isBefore(weekStart)) {
        acute += workout.load;
        sessionsThisWeek++;
        trainedDays.add(workout.day);
        if (workout.intensity.isModerateOrAbove) {
          activeMinutes += workout.minutes;
        }
        if (workout.minutes > longest) longest = workout.minutes;
      }
    }

    final byType =
        perType.entries
            .map((e) => (type: e.key, minutes: e.value))
            .toList()
          ..sort((a, b) => b.minutes.compareTo(a.minutes));

    return FitnessInsights._(
      activeMinutesThisWeek: activeMinutes,
      sessionsThisWeek: sessionsThisWeek,
      acuteLoad: acute,
      // Per *week*, so it is the same unit as the acute load and the two can be
      // divided. Four weeks of 28 days is the point of choosing that window.
      chronicLoad: (chronic / (chronicDays / acuteDays)).round(),
      byType: byType,
      restDaysThisWeek: acuteDays - trainedDays.length,
      longestSessionMinutes: longest,
    );
  }
}
