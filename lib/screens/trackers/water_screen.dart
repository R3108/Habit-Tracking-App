import 'package:flutter/material.dart';

import '../../models/habit.dart';
import '../../models/trackers/tracker_kind.dart';
import '../../models/trackers/water_entry.dart';
import '../../state/tracker_store.dart';
import '../../util/haptics.dart';
import '../../widgets/trackers/tracker_widgets.dart';

/// Water: one tap to log, and an answer to "am I behind right now".
class WaterScreen extends StatelessWidget {
  const WaterScreen({super.key});

  static const _kind = TrackerKind.water;

  @override
  Widget build(BuildContext context) {
    final store = TrackerScope.of(context);
    final goals = store.goals;
    final today = dateOnly(DateTime.now());
    final insights = WaterInsights.from(store.data.water, goals: goals);

    final week = <({DateTime day, num value})>[
      for (var age = 6; age >= 0; age--)
        (day: addDays(today, -age), value: store.waterOn(addDays(today, -age))),
    ];

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            title: Text(_kind.label),
            actions: [
              IconButton(
                icon: const Icon(Icons.undo),
                tooltip: 'Undo last drink',
                onPressed: insights.today <= 0
                    ? null
                    : () {
                        Haptics.tick(context);
                        store.addWater(today, -goals.glassMl);
                      },
              ),
            ],
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            sliver: SliverList.list(
              children: [
                Center(
                  child: GoalRing(
                    progress: insights.share,
                    value: '${insights.today}',
                    caption: 'of ${goals.waterMl} ml',
                    footnote: insights.isMet
                        ? 'target reached'
                        : '${goals.waterMl - insights.today} ml to go',
                    accent: _kind.color,
                  ),
                ),
                const SizedBox(height: 20),
                _PaceCard(insights: insights),
                const SizedBox(height: 16),
                TrackerCard(
                  title: 'Log a drink',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          for (final size in kDrinkSizes)
                            _DrinkButton(
                              label: size.label,
                              ml: size.ml,
                              onTap: () {
                                Haptics.impact(context);
                                store.addWater(today, size.ml);
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Tap once per drink. The exact millilitre does not '
                        'matter against a two-litre target, and a number pad '
                        'at the sink is a log that never gets kept.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TrackerCard(
                  title: 'Last 7 days',
                  child: MiniBars(
                    values: week,
                    goal: goals.waterMl,
                    accent: _kind.color,
                  ),
                ),
                const SizedBox(height: 16),
                TrackerCard(
                  title: 'Over ${insights.daysLogged} logged days',
                  child: Column(
                    children: [
                      TrackerStatRow(
                        icon: Icons.local_fire_department_outlined,
                        label: 'Goal streak',
                        value: '${insights.goalStreak} day'
                            '${insights.goalStreak == 1 ? '' : 's'}',
                        emphasis: insights.goalStreak > 0 ? _kind.color : null,
                      ),
                      TrackerStatRow(
                        icon: Icons.show_chart,
                        label: 'Daily average',
                        value: '${insights.averageMl} ml',
                      ),
                      TrackerStatRow(
                        icon: Icons.emoji_events_outlined,
                        label: 'Best day',
                        value: '${insights.bestDay} ml',
                      ),
                    ],
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

/// Ahead or behind the steady pace for this hour of the day.
///
/// The only tracker in the app that judges a day before it is over, which is
/// justified here and nowhere else: unlike a missed workout, being 400ml down
/// at 3pm is entirely fixable by 4pm.
class _PaceCard extends StatelessWidget {
  const _PaceCard({required this.insights});

  final WaterInsights insights;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (insights.isTooEarlyToJudge) {
      return TrackerCard(
        child: Row(
          children: [
            Icon(Icons.wb_twilight, color: scheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'The day is young — pace starts from 07:00.',
                style: textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final difference = insights.paceDifference;
    final isAhead = difference >= 0;
    final color = isAhead ? TrackerKind.water.color : scheme.error;

    return TrackerCard(
      child: Row(
        children: [
          Icon(isAhead ? Icons.trending_up : Icons.trending_down, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isAhead
                      ? '${difference.abs()} ml ahead of pace'
                      : '${difference.abs()} ml behind pace',
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'A steady day would be at ${insights.expectedByNow} ml by now.',
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

class _DrinkButton extends StatelessWidget {
  const _DrinkButton({
    required this.label,
    required this.ml,
    required this.onTap,
  });

  final String label;
  final int ml;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = TrackerKind.water.color;

    return SizedBox(
      width: 96,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color.withValues(alpha: 0.5)),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.local_drink_outlined, size: 20, color: color),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(
              '$ml ml',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
