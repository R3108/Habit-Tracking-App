import 'package:flutter/foundation.dart';

import '../habit.dart';
import 'tracker_goals.dart';

/// Which part of the pomodoro cycle is running.
enum FocusPhase { focus, shortBreak, longBreak }

extension FocusPhaseLabel on FocusPhase {
  String get label => switch (this) {
    FocusPhase.focus => 'Focus',
    FocusPhase.shortBreak => 'Break',
    FocusPhase.longBreak => 'Long break',
  };

  bool get isWork => this == FocusPhase.focus;
}

/// A finished block of focused work.
///
/// Only completed focus phases are recorded. Breaks are not work, and a session
/// abandoned after four minutes is not a pomodoro — logging either would make
/// the daily total flattering and useless.
@immutable
class FocusSession {
  const FocusSession({
    required this.id,
    required this.day,
    required this.startedAtMinutes,
    required this.minutes,
    this.tag = '',
  });

  final String id;
  final DateTime day;

  /// Clock time the block began, as minutes from midnight.
  final int startedAtMinutes;

  final int minutes;

  /// What was being worked on. Free text, matched case-insensitively.
  final String tag;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'day': encodeDay(day),
    'at': startedAtMinutes,
    'minutes': minutes,
    'tag': tag,
  };

  static FocusSession? fromJson(Map<String, dynamic> json) {
    final day = decodeDay(json['day'] as String?);
    if (day == null) return null;

    return FocusSession(
      id: json['id'] as String? ?? 'focus-${day.millisecondsSinceEpoch}',
      day: day,
      startedAtMinutes: ((json['at'] as num?)?.toInt() ?? 0).clamp(0, 1439),
      minutes: ((json['minutes'] as num?)?.toInt() ?? 0).clamp(0, 1440),
      tag: json['tag'] as String? ?? '',
    );
  }
}

/// A timer that is currently running, persisted so it survives the app dying.
///
/// Stored as a wall-clock start time and a length rather than as a countdown,
/// which is what makes it recoverable: a remaining-seconds field stops ticking
/// the moment the process is killed, while a start time can be compared against
/// the clock whenever the app comes back and still be right.
///
/// This is not a background timer. Android will not deliver a notification for
/// it without a foreground service, and the app declares no such permission —
/// so the countdown is honest about only being live while the screen is open.
@immutable
class RunningTimer {
  const RunningTimer({
    required this.phase,
    required this.startedAt,
    required this.totalMinutes,
    required this.completedFocusBlocks,
    this.tag = '',
  });

  final FocusPhase phase;
  final DateTime startedAt;
  final int totalMinutes;

  /// Focus blocks finished in this run, so the cycle knows when a long break
  /// is due.
  final int completedFocusBlocks;

  final String tag;

  Duration get total => Duration(minutes: totalMinutes);

  Duration elapsedAt(DateTime now) {
    final elapsed = now.difference(startedAt);
    return elapsed.isNegative ? Duration.zero : elapsed;
  }

  Duration remainingAt(DateTime now) {
    final left = total - elapsedAt(now);
    return left.isNegative ? Duration.zero : left;
  }

  bool isFinishedAt(DateTime now) => remainingAt(now) == Duration.zero;

  double progressAt(DateTime now) {
    if (totalMinutes <= 0) return 1;
    return (elapsedAt(now).inSeconds / (totalMinutes * 60)).clamp(0.0, 1.0);
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'phase': phase.name,
    'startedAt': startedAt.toIso8601String(),
    'totalMinutes': totalMinutes,
    'completedFocusBlocks': completedFocusBlocks,
    'tag': tag,
  };

  static RunningTimer? fromJson(Map<String, dynamic> json) {
    final startedAt = DateTime.tryParse(json['startedAt'] as String? ?? '');
    if (startedAt == null) return null;

    return RunningTimer(
      phase: FocusPhase.values.firstWhere(
        (p) => p.name == json['phase'],
        orElse: () => FocusPhase.focus,
      ),
      startedAt: startedAt,
      totalMinutes: ((json['totalMinutes'] as num?)?.toInt() ?? 25).clamp(
        1,
        1440,
      ),
      completedFocusBlocks:
          ((json['completedFocusBlocks'] as num?)?.toInt() ?? 0).clamp(0, 999),
      tag: json['tag'] as String? ?? '',
    );
  }
}

/// What the focus log adds up to.
@immutable
class FocusInsights {
  const FocusInsights._({
    required this.sessionsToday,
    required this.minutesToday,
    required this.minutesThisWeek,
    required this.sessionsThisWeek,
    required this.dailyAverageMinutes,
    required this.bestDayMinutes,
    required this.byTag,
    required this.daysWorked,
  });

  final int sessionsToday;
  final int minutesToday;
  final int minutesThisWeek;
  final int sessionsThisWeek;

  /// Mean across days that had any focus at all, not across the whole window:
  /// dividing by thirty when the app was installed a week ago says nothing.
  final int dailyAverageMinutes;

  final int bestDayMinutes;

  /// Minutes per tag over the window, biggest first.
  final List<({String tag, int minutes})> byTag;

  final int daysWorked;

  static const int windowDays = 30;

  double goalShare(TrackerGoals goals) {
    final target = goals.focusSessionsPerDay;
    if (target <= 0) return 0;
    return (sessionsToday / target).clamp(0.0, 1.0);
  }

  factory FocusInsights.from(
    List<FocusSession> sessions, {
    DateTime? reference,
    int window = windowDays,
  }) {
    final today = dateOnly(reference ?? DateTime.now());
    final windowStart = addDays(today, -(window - 1));
    final weekStart = addDays(today, -6);

    var sessionsToday = 0;
    var minutesToday = 0;
    var minutesThisWeek = 0;
    var sessionsThisWeek = 0;
    final perDay = <DateTime, int>{};
    final perTag = <String, int>{};

    for (final session in sessions) {
      if (session.day.isBefore(windowStart) || session.day.isAfter(today)) {
        continue;
      }

      perDay[session.day] = (perDay[session.day] ?? 0) + session.minutes;

      final tag = session.tag.trim();
      if (tag.isNotEmpty) {
        final key = tag.toLowerCase();
        perTag[key] = (perTag[key] ?? 0) + session.minutes;
      }

      if (!session.day.isBefore(weekStart)) {
        minutesThisWeek += session.minutes;
        sessionsThisWeek++;
      }
      if (session.day == today) {
        sessionsToday++;
        minutesToday += session.minutes;
      }
    }

    // Restores each tag's original casing from the first session that used it,
    // so a screen does not shout "maths" back at somebody who typed "Maths".
    final display = <String, String>{};
    for (final session in sessions) {
      final tag = session.tag.trim();
      if (tag.isEmpty) continue;
      display.putIfAbsent(tag.toLowerCase(), () => tag);
    }

    final byTag =
        perTag.entries
            .map((e) => (tag: display[e.key] ?? e.key, minutes: e.value))
            .toList()
          ..sort((a, b) => b.minutes.compareTo(a.minutes));

    final totals = perDay.values.toList();

    return FocusInsights._(
      sessionsToday: sessionsToday,
      minutesToday: minutesToday,
      minutesThisWeek: minutesThisWeek,
      sessionsThisWeek: sessionsThisWeek,
      dailyAverageMinutes: totals.isEmpty
          ? 0
          : (totals.reduce((a, b) => a + b) / totals.length).round(),
      bestDayMinutes: totals.isEmpty ? 0 : totals.reduce((a, b) => a > b ? a : b),
      byTag: byTag,
      daysWorked: perDay.length,
    );
  }
}
