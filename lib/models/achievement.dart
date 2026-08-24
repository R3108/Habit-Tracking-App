import 'package:flutter/material.dart';

import 'insights.dart';

/// Which running total a badge is measured against.
enum AchievementMetric { completions, bestStreak, perfectDays, habitsTracked }

/// A milestone badge.
///
/// Progress is derived from [OverallInsights] every time it's read rather than
/// stored, so a badge can never drift out of sync with the history behind it —
/// and restoring a backup lights up the badges that history has earned.
@immutable
class Achievement {
  const Achievement({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.metric,
    required this.threshold,
  });

  final String id;
  final String title;
  final String description;
  final IconData icon;
  final AchievementMetric metric;
  final int threshold;

  int valueFrom(OverallInsights insights) => switch (metric) {
    AchievementMetric.completions => insights.totalCompletions,
    AchievementMetric.bestStreak => insights.bestHabitStreak,
    AchievementMetric.perfectDays => insights.perfectDays,
    AchievementMetric.habitsTracked => insights.activeHabits,
  };

  bool isUnlocked(OverallInsights insights) =>
      valueFrom(insights) >= threshold;

  double progress(OverallInsights insights) =>
      (valueFrom(insights) / threshold).clamp(0.0, 1.0);
}

/// Ordered easiest-first so the grid reads as a ladder.
const List<Achievement> kAchievements = <Achievement>[
  Achievement(
    id: 'first_step',
    title: 'First step',
    description: 'Complete a habit for the first time',
    icon: Icons.flag,
    metric: AchievementMetric.completions,
    threshold: 1,
  ),
  Achievement(
    id: 'getting_going',
    title: 'Getting going',
    description: 'Reach a 3-day streak',
    icon: Icons.local_fire_department,
    metric: AchievementMetric.bestStreak,
    threshold: 3,
  ),
  Achievement(
    id: 'full_week',
    title: 'Full week',
    description: 'Reach a 7-day streak',
    icon: Icons.calendar_view_week,
    metric: AchievementMetric.bestStreak,
    threshold: 7,
  ),
  Achievement(
    id: 'flawless_day',
    title: 'Flawless',
    description: 'Finish everything due on a single day',
    icon: Icons.done_all,
    metric: AchievementMetric.perfectDays,
    threshold: 1,
  ),
  Achievement(
    id: 'half_century',
    title: 'Half century',
    description: 'Log 50 completions',
    icon: Icons.military_tech,
    metric: AchievementMetric.completions,
    threshold: 50,
  ),
  Achievement(
    id: 'portfolio',
    title: 'Portfolio',
    description: 'Track 5 habits at once',
    icon: Icons.dashboard_customize,
    metric: AchievementMetric.habitsTracked,
    threshold: 5,
  ),
  Achievement(
    id: 'perfect_week',
    title: 'Perfect week',
    description: 'Finish everything due, 7 days over',
    icon: Icons.workspace_premium,
    metric: AchievementMetric.perfectDays,
    threshold: 7,
  ),
  Achievement(
    id: 'monthly',
    title: 'Month strong',
    description: 'Reach a 30-day streak',
    icon: Icons.calendar_month,
    metric: AchievementMetric.bestStreak,
    threshold: 30,
  ),
  Achievement(
    id: 'century',
    title: 'Century',
    description: 'Log 100 completions',
    icon: Icons.emoji_events,
    metric: AchievementMetric.completions,
    threshold: 100,
  ),
  Achievement(
    id: 'unstoppable',
    title: 'Unstoppable',
    description: 'Reach a 100-day streak',
    icon: Icons.bolt,
    metric: AchievementMetric.bestStreak,
    threshold: 100,
  ),
];
