import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/achievement.dart';
import '../models/habit.dart';
import '../models/insights.dart';
import '../state/habit_store.dart';
import '../state/settings_store.dart';
import '../widgets/heatmap.dart';
import '../widgets/stat_tile.dart';
import '../widgets/weekday_chart.dart';
import 'habit_detail_screen.dart';

/// Cross-habit statistics: the "am I actually doing this?" screen.
class InsightsScreen extends StatelessWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = HabitScope.of(context);
    final settings = SettingsScope.of(context).settings;
    final scheme = Theme.of(context).colorScheme;
    final habits = store.habits;

    if (habits.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Insights')),
        body: const _EmptyInsights(),
      );
    }

    final insights = OverallInsights.from(habits);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(title: const Text('Insights')),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
            sliver: SliverList.list(
              children: [
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.7,
                  children: [
                    StatTile(
                      icon: Icons.done_all,
                      value: '${insights.perfectDayStreak}',
                      label: 'Perfect-day streak',
                    ),
                    StatTile(
                      icon: Icons.percent,
                      value: '${(insights.thirtyDayRate * 100).round()}%',
                      label: 'Last 30 days',
                    ),
                    StatTile(
                      icon: Icons.local_fire_department,
                      value: '${insights.bestHabitStreak}',
                      label: 'Longest streak',
                    ),
                    StatTile(
                      icon: Icons.check_circle_outline,
                      value: '${insights.totalCompletions}',
                      label: 'Total completions',
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _Section(
                  title: 'Consistency',
                  subtitle: 'Every day since ${DateFormat.MMMd().format(insights.days.first.day)}',
                  child: Column(
                    children: [
                      CompletionHeatmap(
                        days: insights.days,
                        accent: scheme.primary,
                        weekStartsOn: settings.weekStartsOn,
                        onSelect: (day) => _showDayDetail(context, day),
                      ),
                      const SizedBox(height: 12),
                      HeatmapLegend(accent: scheme.primary),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _Section(
                  title: 'By weekday',
                  subtitle: 'Where the misses cluster',
                  child: WeekdayChart(
                    rates: insights.weekdayRates,
                    accent: scheme.primary,
                    weekStartsOn: settings.weekStartsOn,
                  ),
                ),
                const SizedBox(height: 16),
                _Section(
                  title: 'Habits',
                  subtitle: 'Last 30 days',
                  child: Column(
                    children: [
                      for (final habit in habits)
                        _HabitRow(
                          habit: habit,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  HabitDetailScreen(habitId: habit.id),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _Section(
                  title: 'Milestones',
                  subtitle:
                      '${kAchievements.where((a) => a.isUnlocked(insights)).length}'
                      ' of ${kAchievements.length} unlocked',
                  child: _AchievementGrid(insights: insights),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showDayDetail(BuildContext context, DayCompletion day) {
    final label = DateFormat.yMMMEd().format(day.day);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 2),
          content: Text(
            day.hasData
                ? '$label — ${day.done} of ${day.due} done'
                : '$label — nothing scheduled',
          ),
        ),
      );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.child,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

/// One habit's 30-day bar in the habits section.
class _HabitRow extends StatelessWidget {
  const _HabitRow({required this.habit, required this.onTap});

  final Habit habit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rate = habit.completionRateInLast(30);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Icon(habit.icon, size: 20, color: habit.color),
            const SizedBox(width: 12),
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    habit.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: rate,
                      minHeight: 6,
                      backgroundColor: scheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation(habit.color),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 40,
              child: Text(
                '${(rate * 100).round()}%',
                textAlign: TextAlign.end,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AchievementGrid extends StatelessWidget {
  const _AchievementGrid({required this.insights});

  final OverallInsights insights;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final achievement in kAchievements)
          _AchievementBadge(achievement: achievement, insights: insights),
      ],
    );
  }
}

class _AchievementBadge extends StatelessWidget {
  const _AchievementBadge({required this.achievement, required this.insights});

  final Achievement achievement;
  final OverallInsights insights;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final unlocked = achievement.isUnlocked(insights);

    return Tooltip(
      message: unlocked
          ? achievement.description
          : '${achievement.description} '
                '(${achievement.valueFrom(insights)}/${achievement.threshold})',
      child: Semantics(
        label: '${achievement.title}, '
            '${unlocked ? 'unlocked' : 'locked'}',
        child: Container(
          width: 76,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
          decoration: BoxDecoration(
            color: unlocked
                ? scheme.primaryContainer
                : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                unlocked ? achievement.icon : Icons.lock_outline,
                size: 22,
                color: unlocked
                    ? scheme.onPrimaryContainer
                    : scheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
              const SizedBox(height: 8),
              Text(
                achievement.title,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: unlocked
                      ? scheme.onPrimaryContainer
                      : scheme.onSurfaceVariant,
                  fontWeight: unlocked ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyInsights extends StatelessWidget {
  const _EmptyInsights();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.insights, size: 64, color: scheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              'Nothing to chart yet',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Add a habit and tick a few days — streaks, heatmaps and '
              'milestones show up here.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
