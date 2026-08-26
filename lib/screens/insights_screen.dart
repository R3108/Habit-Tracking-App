import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/achievement.dart';
import '../models/blueprint.dart';
import '../models/daily_signal.dart';
import '../models/discovery.dart';
import '../models/habit.dart';
import '../models/insights.dart';
import '../models/synergy.dart';
import '../state/habit_store.dart';
import '../state/settings_store.dart';
import '../state/tracker_store.dart';
import '../widgets/heatmap.dart';
import '../widgets/section_card.dart';
import '../widgets/stat_tile.dart';
import '../widgets/weekday_chart.dart';
import 'coach_screen.dart';
import 'habit_detail_screen.dart';
import 'lab_screen.dart';
import 'weekly_review_screen.dart';

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
    final synergies = findSynergies(habits);
    // One walk over the trackers feeds both searches: the pairwise one, and the
    // profile of the days that went best.
    final signals = buildSignals(
      habits: habits,
      trackers: TrackerScope.of(context).data,
    );
    final discoveries = findDiscoveries(signals);
    final blueprint = DayBlueprint.from(signals);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(title: const Text('Insights')),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
            sliver: SliverList.list(
              children: [
                _Banner(
                  icon: Icons.auto_stories_outlined,
                  title: 'Weekly review',
                  subtitle: 'What the last seven days actually say',
                  onOpen: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const WeeklyReviewScreen(),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _Banner(
                  icon: Icons.auto_awesome,
                  title: 'Coach',
                  subtitle: "Today's odds, and where the plan is wrong",
                  onOpen: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const CoachScreen()),
                  ),
                ),
                const SizedBox(height: 12),
                _Banner(
                  icon: Icons.science_outlined,
                  title: 'Lab',
                  subtitle: 'Strength, projections and experiments',
                  onOpen: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const LabScreen()),
                  ),
                ),
                const SizedBox(height: 16),
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
                SectionCard(
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
                SectionCard(
                  title: 'By weekday',
                  subtitle: 'Where the misses cluster',
                  child: WeekdayChart(
                    rates: insights.weekdayRates,
                    accent: scheme.primary,
                    weekStartsOn: settings.weekStartsOn,
                  ),
                ),
                if (discoveries.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  SectionCard(
                    title: 'Discoveries',
                    subtitle: 'What your trackers say about each other',
                    child: Column(
                      children: [
                        for (final discovery in discoveries)
                          _DiscoveryRow(discovery: discovery),
                        const SizedBox(height: 4),
                        Text(
                          'Found by comparing every tracker against every '
                          'other, so treat these as leads rather than facts — '
                          'search hard enough and coincidences turn up. Only '
                          'sizeable differences over at least two weeks are '
                          'shown.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (blueprint != null) ...[
                  const SizedBox(height: 16),
                  SectionCard(
                    title: 'Blueprint of a good day',
                    subtitle: 'What your best days had in common',
                    child: _BlueprintBody(blueprint: blueprint),
                  ),
                ],
                if (synergies.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  SectionCard(
                    title: 'Connections',
                    subtitle: 'Habits that move together',
                    child: Column(
                      children: [
                        for (final synergy in synergies)
                          _SynergyRow(
                            synergy: synergy,
                            trigger: store.byId(synergy.triggerId),
                            follower: store.byId(synergy.followerId),
                          ),
                        const SizedBox(height: 4),
                        Text(
                          'Patterns in your own history, not advice. Two habits '
                          'can move together because something else drives both.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                SectionCard(
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
                SectionCard(
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

/// Entry point to one of the written screens, at the top where it will be seen.
class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onOpen,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Material(
      color: scheme.secondaryContainer,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, color: scheme.onSecondaryContainer),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: textTheme.titleSmall?.copyWith(
                        color: scheme.onSecondaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: textTheme.bodySmall?.copyWith(
                        color: scheme.onSecondaryContainer.withValues(
                          alpha: 0.85,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.onSecondaryContainer),
            ],
          ),
        ),
      ),
    );
  }
}

/// One cross-tracker finding.
///
/// Leads with the two group means rather than the effect size, for the same
/// reason [_SynergyRow] leads with two rates: "82% against 54%" is a comparison
/// anybody can check against their own memory, and a Cohen's d of 0.9 is not.
class _DiscoveryRow extends StatelessWidget {
  const _DiscoveryRow({required this.discovery});

  final Discovery discovery;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final driver = discovery.driver;
    final outcome = discovery.outcome;
    final better = discovery.isPositive;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            better ? Icons.arrow_upward : Icons.arrow_downward,
            size: 20,
            color: better ? scheme.primary : scheme.error,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    style: textTheme.bodyMedium,
                    children: [
                      const TextSpan(text: 'On days your '),
                      TextSpan(
                        text: driver.label.toLowerCase(),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      TextSpan(
                        text: ' was above ${driver.format(discovery.threshold)}'
                            ', your ',
                      ),
                      TextSpan(
                        text: outcome.label.toLowerCase(),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      TextSpan(
                        text: ' averaged '
                            '${outcome.format(discovery.highMean)} — against '
                            '${outcome.format(discovery.lowMean)} on the rest.',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${discovery.strength} difference · '
                  '${discovery.days} days compared',
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One measured link between two habits.
///
/// Leads with the two rates rather than a multiplier: "78% against 34%" is a
/// comparison anybody can check against their own memory, while "2.3× more
/// likely" is a statistic the reader has to take on trust.
class _SynergyRow extends StatelessWidget {
  const _SynergyRow({
    required this.synergy,
    required this.trigger,
    required this.follower,
  });

  final HabitSynergy synergy;
  final Habit? trigger;
  final Habit? follower;

  @override
  Widget build(BuildContext context) {
    final trigger = this.trigger;
    final follower = this.follower;
    // Either habit can be deleted between the pairing and this build.
    if (trigger == null || follower == null) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final positive = synergy.isPositive;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            positive ? Icons.trending_up : Icons.trending_down,
            size: 20,
            color: positive ? scheme.primary : scheme.error,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    style: textTheme.bodyMedium,
                    children: [
                      const TextSpan(text: 'On days you do '),
                      TextSpan(
                        text: trigger.title,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: trigger.color,
                        ),
                      ),
                      TextSpan(text: positive ? ', you also ' : ', you '),
                      TextSpan(
                        text: follower.title,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: follower.color,
                        ),
                      ),
                      TextSpan(
                        text: positive ? ' far more often.' : ' far less often.',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${synergy.withTriggerPercent}% against '
                  '${synergy.withoutTriggerPercent}% on other days '
                  '· ${synergy.daysWithTrigger + synergy.daysWithoutTrigger} days compared',
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The profile of the days that went best, read as a recipe.
class _BlueprintBody extends StatelessWidget {
  const _BlueprintBody({required this.blueprint});

  final DayBlueprint blueprint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final outcome = blueprint.outcome;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Your best ${blueprint.goodDays} days averaged '
          '${outcome.format(blueprint.goodOutcome)} '
          '${outcome.label.toLowerCase()}, against '
          '${outcome.format(blueprint.poorOutcome)} on the '
          '${blueprint.poorDays} worst. This is what else was different:',
          style: textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        for (final line in blueprint.lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  line.higherIsBetter
                      ? Icons.arrow_upward
                      : Icons.arrow_downward,
                  size: 20,
                  color: scheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        line.target,
                        style: textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Median ${line.signal.format(line.goodMedian)} on the '
                        'good days against '
                        '${line.signal.format(line.poorMedian)} on the poor '
                        'ones · ${line.goodDays} and ${line.poorDays} days',
                        style: textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        Text(
          'The target is the level three quarters of your good days cleared, '
          'not their average — an average target is one half your own best '
          'days would have failed. Comparing extremes flatters every gap it '
          'finds, so read this as a shape rather than a measurement, and note '
          'that a good day can cause an early night as easily as the other way '
          'round.',
          style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
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
