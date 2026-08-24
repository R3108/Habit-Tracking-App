import 'package:flutter/material.dart';

import 'achievement.dart';
import 'habit.dart';
import 'insights.dart';
import 'momentum.dart';
import 'synergy.dart';

/// How a review line should read — colour and icon follow from this.
enum ReviewTone { good, neutral, warning }

/// One sentence of the review.
@immutable
class ReviewLine {
  const ReviewLine({
    required this.icon,
    required this.text,
    this.tone = ReviewTone.neutral,
  });

  final IconData icon;
  final String text;
  final ReviewTone tone;
}

/// An on-device summary of the last seven days.
///
/// Every number here is already somewhere on the insights screen. The point of
/// this class is that a chart asks the user to do the reading, and most people
/// glance at a heatmap and take away "looks fine". A written line — "Tuesdays
/// are your weakest day, at 34%" — costs the same data and lands.
///
/// A *rolling* seven days compared against the seven before it, deliberately
/// not the calendar week. A review opened on a Tuesday would otherwise compare
/// two days against a full seven and announce a collapse every Monday morning.
/// The cost is that "this week" means "since last Tuesday", which the screen
/// says out loud.
@immutable
class WeeklyReview {
  const WeeklyReview._({
    required this.from,
    required this.to,
    required this.due,
    required this.done,
    required this.previousDue,
    required this.previousDone,
    required this.perfectDays,
    required this.daysOff,
    required this.lines,
    required this.nextMilestone,
    required this.nextMilestoneValue,
  });

  /// First and last day covered, inclusive.
  final DateTime from;
  final DateTime to;

  final int due;
  final int done;
  final int previousDue;
  final int previousDone;

  final int perfectDays;

  /// Planned days off taken across all habits in the window.
  final int daysOff;

  /// The narrative, already ordered for display.
  final List<ReviewLine> lines;

  /// The nearest badge still locked, or null once they are all earned.
  final Achievement? nextMilestone;
  final int nextMilestoneValue;

  static const int windowDays = 7;

  double get rate => due == 0 ? 0 : done / due;
  double get previousRate => previousDue == 0 ? 0 : previousDone / previousDue;

  int get percent => (rate * 100).round();

  /// Change in percentage points against the previous seven days.
  ///
  /// Null when there is no previous window to compare against — a first week
  /// has not improved or declined, and claiming either would be an invention.
  int? get deltaPoints =>
      previousDue == 0 ? null : ((rate - previousRate) * 100).round();

  /// True when the window has nothing in it — a fresh install, or a week
  /// entirely taken off.
  bool get isEmpty => due == 0;

  factory WeeklyReview.from(
    List<Habit> habits, {
    DateTime? reference,
    int weekStartsOn = DateTime.monday,
  }) {
    final active = habits.where((h) => !h.archived).toList();
    final today = dateOnly(reference ?? DateTime.now());
    final from = addDays(today, -(windowDays - 1));

    var due = 0;
    var done = 0;
    var perfectDays = 0;
    var daysOff = 0;
    var previousDue = 0;
    var previousDone = 0;

    for (var age = 0; age < windowDays * 2; age++) {
      final day = addDays(today, -age);
      final isThisWeek = age < windowDays;

      var dayDue = 0;
      var dayDone = 0;
      for (final habit in active) {
        if (isThisWeek && habit.isSkippedOn(day)) daysOff++;
        if (!habit.isDueOn(day)) continue;
        dayDue++;
        if (habit.isCompletedOn(day)) dayDone++;
      }

      if (isThisWeek) {
        due += dayDue;
        done += dayDone;
        if (dayDue > 0 && dayDone >= dayDue) perfectDays++;
      } else {
        previousDue += dayDue;
        previousDone += dayDone;
      }
    }

    final insights = OverallInsights.from(active);
    final milestone = kAchievements
        .where((a) => !a.isUnlocked(insights))
        .firstOrNull;

    return WeeklyReview._(
      from: from,
      to: today,
      due: due,
      done: done,
      previousDue: previousDue,
      previousDone: previousDone,
      perfectDays: perfectDays,
      daysOff: daysOff,
      lines: _buildLines(
        habits: active,
        insights: insights,
        reference: today,
        due: due,
        done: done,
        previousDue: previousDue,
        previousDone: previousDone,
        perfectDays: perfectDays,
        daysOff: daysOff,
      ),
      nextMilestone: milestone,
      nextMilestoneValue: milestone?.valueFrom(insights) ?? 0,
    );
  }

  /// Builds the narrative, best news first.
  ///
  /// Order is deliberate: the opening line is whatever went *well*, because a
  /// review that leads with failures is one the user stops opening, and the
  /// habits that need attention are the ones they then never read about.
  static List<ReviewLine> _buildLines({
    required List<Habit> habits,
    required OverallInsights insights,
    required DateTime reference,
    required int due,
    required int done,
    required int previousDue,
    required int previousDone,
    required int perfectDays,
    required int daysOff,
  }) {
    final lines = <ReviewLine>[];
    if (habits.isEmpty || due == 0) return lines;

    final rate = done / due;
    final previousRate = previousDue == 0 ? 0.0 : previousDone / previousDue;
    final byId = <String, Habit>{for (final h in habits) h.id: h};

    // 1. The headline movement.
    if (previousDue > 0) {
      final points = ((rate - previousRate) * 100).round();
      if (points >= 5) {
        lines.add(ReviewLine(
          icon: Icons.trending_up,
          tone: ReviewTone.good,
          text: 'Up $points points on the week before — '
              '${(rate * 100).round()}% of everything due.',
        ));
      } else if (points <= -5) {
        lines.add(ReviewLine(
          icon: Icons.trending_down,
          tone: ReviewTone.warning,
          text: 'Down ${points.abs()} points on the week before, at '
              '${(rate * 100).round()}%.',
        ));
      } else {
        lines.add(ReviewLine(
          icon: Icons.trending_flat,
          text: 'Holding steady at ${(rate * 100).round()}%, '
              'about the same as last week.',
        ));
      }
    }

    // 2. Perfect days.
    if (perfectDays >= 5) {
      lines.add(ReviewLine(
        icon: Icons.done_all,
        tone: ReviewTone.good,
        text: '$perfectDays clean days out of seven.',
      ));
    } else if (perfectDays > 0) {
      lines.add(ReviewLine(
        icon: Icons.done_all,
        text: '$perfectDays day${perfectDays == 1 ? '' : 's'} where everything '
            'due got done.',
      ));
    }

    // 3. The habit carrying the week, and the one being carried.
    final momentum = momentumFor(habits, reference: reference)
        .where((m) => m.hasEnoughHistory)
        .toList();

    if (momentum.isNotEmpty) {
      final rising = momentum
          .where((m) => m.trend == MomentumTrend.rising)
          .toList()
        ..sort((a, b) => b.delta.compareTo(a.delta));

      if (rising.isNotEmpty && byId[rising.first.habitId] != null) {
        final best = rising.first;
        lines.add(ReviewLine(
          icon: Icons.rocket_launch_outlined,
          tone: ReviewTone.good,
          text: '"${byId[best.habitId]!.title}" is climbing — up '
              '${(best.delta * 100).round()} points, now at ${best.percent}%.',
        ));
      }

      final weakest = momentum.reduce((a, b) => a.score <= b.score ? a : b);
      if (weakest.score < 0.5 && byId[weakest.habitId] != null) {
        lines.add(ReviewLine(
          icon: Icons.warning_amber_outlined,
          tone: ReviewTone.warning,
          text: '"${byId[weakest.habitId]!.title}" is the one slipping, at '
              '${weakest.percent}% of its due days.',
        ));
      }
    }

    // 4. The weakest weekday, which is the most actionable thing here: it can
    //    be fixed by moving a schedule rather than by trying harder.
    final weekdayLine = _weekdayLine(insights);
    if (weekdayLine != null) lines.add(weekdayLine);

    // 5. One correlation, if the history supports it.
    final synergies = findSynergies(habits, reference: reference, limit: 1);
    if (synergies.isNotEmpty) {
      final link = synergies.first;
      final trigger = byId[link.triggerId];
      final follower = byId[link.followerId];
      if (trigger != null && follower != null) {
        lines.add(ReviewLine(
          icon: link.isPositive ? Icons.link : Icons.link_off,
          tone: link.isPositive ? ReviewTone.good : ReviewTone.neutral,
          text: link.isPositive
              ? 'You finish "${follower.title}" on '
                  '${link.withTriggerPercent}% of the days you do '
                  '"${trigger.title}", against '
                  '${link.withoutTriggerPercent}% otherwise.'
              : '"${follower.title}" drops to ${link.withTriggerPercent}% on '
                  '"${trigger.title}" days, from '
                  '${link.withoutTriggerPercent}%.',
        ));
      }
    }

    // 6. Shields, so a quiet week reads as planned rather than as a failure.
    if (daysOff > 0) {
      lines.add(ReviewLine(
        icon: Icons.beach_access_outlined,
        text: '$daysOff planned day${daysOff == 1 ? '' : 's'} off — not '
            'counted against anything.',
      ));
    }

    return lines;
  }

  /// Names the weakest weekday, when one stands out.
  static ReviewLine? _weekdayLine(OverallInsights insights) {
    const names = [
      'Mondays',
      'Tuesdays',
      'Wednesdays',
      'Thursdays',
      'Fridays',
      'Saturdays',
      'Sundays',
    ];

    // A zero rate here can mean "never due on that weekday" rather than "always
    // missed", and calling a rest day a weakness would be nonsense.
    final scored = <int>[
      for (var i = 0; i < 7; i++)
        if (insights.weekdayRates[i] > 0) i,
    ];
    if (scored.length < 4) return null;

    final worst = scored.reduce(
      (a, b) => insights.weekdayRates[a] <= insights.weekdayRates[b] ? a : b,
    );
    final best = scored.reduce(
      (a, b) => insights.weekdayRates[a] >= insights.weekdayRates[b] ? a : b,
    );

    final spread = insights.weekdayRates[best] - insights.weekdayRates[worst];
    if (spread < 0.2) return null;

    return ReviewLine(
      icon: Icons.event_busy_outlined,
      text: '${names[worst]} are your weakest day at '
          '${(insights.weekdayRates[worst] * 100).round()}%, against '
          '${(insights.weekdayRates[best] * 100).round()}% on '
          '${names[best].toLowerCase()}.',
    );
  }
}
