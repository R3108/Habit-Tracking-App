import 'habit.dart';

/// One day's slice of the whole habit list.
///
/// [due] is zero for a day nothing was scheduled — a rest day, not a failure.
/// Renderers should treat that case as "no data" rather than 0%.
class DayCompletion {
  const DayCompletion({required this.day, required this.due, required this.done});

  final DateTime day;
  final int due;
  final int done;

  bool get hasData => due > 0;
  bool get isPerfect => due > 0 && done >= due;
  double get ratio => due == 0 ? 0 : (done / due).clamp(0.0, 1.0);
}

/// Cross-habit analytics for the insights screen.
///
/// Everything is computed once in [OverallInsights.from] and read from fields
/// afterwards, because the heatmap, the weekday chart and the summary tiles all
/// need the same day-by-day walk and it would otherwise run three times per
/// rebuild.
class OverallInsights {
  const OverallInsights._({
    required this.days,
    required this.weekdayRates,
    required this.totalCompletions,
    required this.perfectDays,
    required this.perfectDayStreak,
    required this.bestHabitStreak,
    required this.activeHabits,
    required this.thirtyDayRate,
  });

  /// Oldest first, ending today.
  final List<DayCompletion> days;

  /// Completion rate per ISO weekday, indexed 0 = Monday … 6 = Sunday.
  final List<double> weekdayRates;

  final int totalCompletions;
  final int perfectDays;

  /// Consecutive days ending today where every due habit was done.
  final int perfectDayStreak;

  final int bestHabitStreak;
  final int activeHabits;

  /// Share of due habit-days completed over the last 30 days, in 0..1.
  final double thirtyDayRate;

  static const emptyWindow = 140;

  factory OverallInsights.from(List<Habit> habits, {int window = emptyWindow}) {
    final active = habits.where((h) => !h.archived).toList();
    final today = dateOnly(DateTime.now());

    final days = <DayCompletion>[];
    final weekdayDue = List<int>.filled(7, 0);
    final weekdayDone = List<int>.filled(7, 0);

    for (var i = window - 1; i >= 0; i--) {
      final day = addDays(today, -i);
      var due = 0;
      var done = 0;
      for (final habit in active) {
        // Covers days before the habit existed, days its schedule skips, and
        // days the user planned off — none of which it can be judged on.
        if (!habit.isDueOn(day)) continue;
        due++;
        if (habit.isCompletedOn(day)) done++;
      }
      days.add(DayCompletion(day: day, due: due, done: done));
      weekdayDue[day.weekday - 1] += due;
      weekdayDone[day.weekday - 1] += done;
    }

    var perfectDays = 0;
    for (final day in days) {
      if (day.isPerfect) perfectDays++;
    }

    // Walk back from today. Today is skipped while still incomplete so an
    // in-progress morning doesn't zero out the run.
    var streak = 0;
    for (var i = days.length - 1; i >= 0; i--) {
      final day = days[i];
      if (!day.hasData) continue;
      if (day.isPerfect) {
        streak++;
      } else if (day.day == today) {
        continue;
      } else {
        break;
      }
    }

    var thirtyDue = 0;
    var thirtyDone = 0;
    for (final day in days.reversed.take(30)) {
      thirtyDue += day.due;
      thirtyDone += day.done;
    }

    return OverallInsights._(
      days: days,
      weekdayRates: <double>[
        for (var i = 0; i < 7; i++)
          weekdayDue[i] == 0 ? 0 : weekdayDone[i] / weekdayDue[i],
      ],
      totalCompletions: active.fold(0, (sum, h) => sum + h.totalCompletions),
      perfectDays: perfectDays,
      perfectDayStreak: streak,
      bestHabitStreak: active.fold(
        0,
        (best, h) => h.bestStreak > best ? h.bestStreak : best,
      ),
      activeHabits: active.length,
      thirtyDayRate: thirtyDue == 0 ? 0 : thirtyDone / thirtyDue,
    );
  }
}
