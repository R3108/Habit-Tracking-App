import 'package:flutter/foundation.dart';

/// The targets every tracker measures itself against.
///
/// Held in one place, and persisted with the tracker data rather than with
/// [AppSettings], because these are part of what the user is tracking rather
/// than how the app looks: a restored backup should bring back the fact that
/// you were aiming at seven hours, not reset you to eight.
///
/// The defaults are the mainstream public-health ones, chosen so the app has
/// something honest to say on day one. They are not advice, and every one of
/// them is editable.
@immutable
class TrackerGoals {
  const TrackerGoals({
    this.sleepMinutes = 8 * 60,
    this.waterMl = 2000,
    this.glassMl = 250,
    this.readingMinutes = 30,
    this.focusSessionsPerDay = 4,
    this.focusMinutes = 25,
    this.breakMinutes = 5,
    this.longBreakMinutes = 15,
    this.sessionsBeforeLongBreak = 4,
    this.activeMinutesPerWeek = 150,
    this.eatingWindowMinutes = 12 * 60,
  });

  /// Nightly sleep target.
  final int sleepMinutes;

  /// Daily water target, and the size of one tap on the quick-add button.
  final int waterMl;
  final int glassMl;

  final int readingMinutes;

  /// Pomodoro shape: how many sessions a day, and how long each part runs.
  final int focusSessionsPerDay;
  final int focusMinutes;
  final int breakMinutes;
  final int longBreakMinutes;
  final int sessionsBeforeLongBreak;

  /// The WHO's weekly moderate-activity guideline, which is a *weekly* number
  /// on purpose — a daily target turns one rest day into a failure.
  final int activeMinutesPerWeek;

  /// The window from first meal to last that the user is aiming to stay inside.
  final int eatingWindowMinutes;

  double get sleepHours => sleepMinutes / 60;

  TrackerGoals copyWith({
    int? sleepMinutes,
    int? waterMl,
    int? glassMl,
    int? readingMinutes,
    int? focusSessionsPerDay,
    int? focusMinutes,
    int? breakMinutes,
    int? longBreakMinutes,
    int? sessionsBeforeLongBreak,
    int? activeMinutesPerWeek,
    int? eatingWindowMinutes,
  }) {
    return TrackerGoals(
      sleepMinutes: sleepMinutes ?? this.sleepMinutes,
      waterMl: waterMl ?? this.waterMl,
      glassMl: glassMl ?? this.glassMl,
      readingMinutes: readingMinutes ?? this.readingMinutes,
      focusSessionsPerDay: focusSessionsPerDay ?? this.focusSessionsPerDay,
      focusMinutes: focusMinutes ?? this.focusMinutes,
      breakMinutes: breakMinutes ?? this.breakMinutes,
      longBreakMinutes: longBreakMinutes ?? this.longBreakMinutes,
      sessionsBeforeLongBreak:
          sessionsBeforeLongBreak ?? this.sessionsBeforeLongBreak,
      activeMinutesPerWeek: activeMinutesPerWeek ?? this.activeMinutesPerWeek,
      eatingWindowMinutes: eatingWindowMinutes ?? this.eatingWindowMinutes,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'sleepMinutes': sleepMinutes,
    'waterMl': waterMl,
    'glassMl': glassMl,
    'readingMinutes': readingMinutes,
    'focusSessionsPerDay': focusSessionsPerDay,
    'focusMinutes': focusMinutes,
    'breakMinutes': breakMinutes,
    'longBreakMinutes': longBreakMinutes,
    'sessionsBeforeLongBreak': sessionsBeforeLongBreak,
    'activeMinutesPerWeek': activeMinutesPerWeek,
    'eatingWindowMinutes': eatingWindowMinutes,
  };

  factory TrackerGoals.fromJson(Map<String, dynamic> json) {
    int read(String key, int fallback, int min, int max) =>
        ((json[key] as num?)?.toInt() ?? fallback).clamp(min, max);

    return TrackerGoals(
      sleepMinutes: read('sleepMinutes', 8 * 60, 4 * 60, 12 * 60),
      waterMl: read('waterMl', 2000, 250, 8000),
      glassMl: read('glassMl', 250, 50, 1000),
      readingMinutes: read('readingMinutes', 30, 5, 480),
      focusSessionsPerDay: read('focusSessionsPerDay', 4, 1, 20),
      focusMinutes: read('focusMinutes', 25, 5, 120),
      breakMinutes: read('breakMinutes', 5, 1, 60),
      longBreakMinutes: read('longBreakMinutes', 15, 1, 60),
      sessionsBeforeLongBreak: read('sessionsBeforeLongBreak', 4, 2, 12),
      activeMinutesPerWeek: read('activeMinutesPerWeek', 150, 30, 2000),
      eatingWindowMinutes: read('eatingWindowMinutes', 12 * 60, 4 * 60, 24 * 60),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TrackerGoals &&
      other.sleepMinutes == sleepMinutes &&
      other.waterMl == waterMl &&
      other.glassMl == glassMl &&
      other.readingMinutes == readingMinutes &&
      other.focusSessionsPerDay == focusSessionsPerDay &&
      other.focusMinutes == focusMinutes &&
      other.breakMinutes == breakMinutes &&
      other.longBreakMinutes == longBreakMinutes &&
      other.sessionsBeforeLongBreak == sessionsBeforeLongBreak &&
      other.activeMinutesPerWeek == activeMinutesPerWeek &&
      other.eatingWindowMinutes == eatingWindowMinutes;

  @override
  int get hashCode => Object.hash(
    sleepMinutes,
    waterMl,
    glassMl,
    readingMinutes,
    focusSessionsPerDay,
    focusMinutes,
    breakMinutes,
    longBreakMinutes,
    sessionsBeforeLongBreak,
    activeMinutesPerWeek,
    eatingWindowMinutes,
  );
}

/// Formats a duration in minutes as "7h 30m", dropping empty parts.
String formatMinutes(int minutes) {
  if (minutes <= 0) return '0m';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  if (hours == 0) return '${rest}m';
  if (rest == 0) return '${hours}h';
  return '${hours}h ${rest}m';
}

/// Formats minutes-from-midnight as a 24-hour clock time.
String formatClock(int minutesFromMidnight) {
  final normalised = minutesFromMidnight % 1440;
  final hours = (normalised ~/ 60).toString().padLeft(2, '0');
  final minutes = (normalised % 60).toString().padLeft(2, '0');
  return '$hours:$minutes';
}
