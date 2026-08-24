import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/habit.dart';
import '../../models/trackers/check_in_entry.dart';
import '../../models/trackers/tracker_kind.dart';
import '../../state/tracker_store.dart';
import '../../util/haptics.dart';
import '../../widgets/trackers/tracker_widgets.dart';

/// Mood and energy: the one thing here that measures how it went rather than
/// what was done.
class CheckInScreen extends StatelessWidget {
  const CheckInScreen({super.key});

  static const _kind = TrackerKind.checkIn;
  static const _weekdayNames = [
    'Mondays',
    'Tuesdays',
    'Wednesdays',
    'Thursdays',
    'Fridays',
    'Saturdays',
    'Sundays',
  ];

  @override
  Widget build(BuildContext context) {
    final store = TrackerScope.of(context);
    final today = dateOnly(DateTime.now());
    final insights = CheckInInsights.from(store.data.checkIns);
    final todayEntry = store.checkInOn(today);

    final fortnight = <({DateTime day, num value})>[
      for (var age = 13; age >= 0; age--)
        (
          day: addDays(today, -age),
          value: store.checkInOn(addDays(today, -age))?.overall ?? 0,
        ),
    ];

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(title: Text(_kind.label)),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            sliver: SliverList.list(
              children: [
                _TodayCard(
                  entry: todayEntry,
                  onMood: (value) => _update(store, today, mood: value),
                  onEnergy: (value) => _update(store, today, energy: value),
                ),
                const SizedBox(height: 16),
                if (!insights.hasData)
                  const TrackerCard(
                    child: TrackerEmptyState(
                      icon: Icons.mood,
                      title: 'Nothing recorded yet',
                      message:
                          'Everything else here measures what you did. This '
                          'measures how it went — which is what makes it '
                          'possible to ask whether any of the rest mattered.',
                    ),
                  )
                else ...[
                  TrackerCard(
                    title: 'Last 14 days',
                    child: MiniBars(
                      values: fortnight,
                      goal: 4,
                      accent: _kind.color,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TrackerCard(
                    title: 'Over ${insights.daysLogged} days',
                    child: Column(
                      children: [
                        TrackerStatRow(
                          icon: Icons.mood,
                          label: 'Average mood',
                          value: '${insights.averageMood.toStringAsFixed(1)}/5',
                        ),
                        TrackerStatRow(
                          icon: Icons.bolt,
                          label: 'Average energy',
                          value:
                              '${insights.averageEnergy.toStringAsFixed(1)}/5',
                        ),
                        if (insights.moodTrend case final trend?)
                          TrackerStatRow(
                            icon: trend >= 0
                                ? Icons.trending_up
                                : Icons.trending_down,
                            label: 'Against the month before',
                            value:
                                '${trend >= 0 ? '+' : ''}'
                                '${trend.toStringAsFixed(1)}',
                            emphasis: trend >= 0
                                ? _kind.color
                                : Theme.of(context).colorScheme.error,
                          ),
                        TrackerStatRow(
                          icon: Icons.local_fire_department_outlined,
                          label: 'Check-in streak',
                          value: '${insights.streak} day'
                              '${insights.streak == 1 ? '' : 's'}',
                        ),
                      ],
                    ),
                  ),
                  if (insights.bestWeekday case final best?) ...[
                    const SizedBox(height: 16),
                    TrackerCard(
                      title: 'By weekday',
                      child: Text(
                        '${_weekdayNames[best - 1]} are your best days so far, '
                        'and ${_weekdayNames[insights.worstWeekday! - 1].toLowerCase()} '
                        'your hardest. Worth knowing before you schedule '
                        'something demanding.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ],
                const SizedBox(height: 16),
                _RecentDays(store: store, today: today),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Writes one half of the check-in, defaulting the other to the middle of the
  /// scale so a single tap is always enough to record something.
  void _update(
    TrackerStore store,
    DateTime day, {
    int? mood,
    int? energy,
  }) {
    final existing = store.checkInOn(day);
    store.logCheckIn(
      existing?.copyWith(mood: mood, energy: energy) ??
          CheckIn(day: day, mood: mood ?? 3, energy: energy ?? 3),
    );
  }
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({
    required this.entry,
    required this.onMood,
    required this.onEnergy,
  });

  final CheckIn? entry;
  final ValueChanged<int> onMood;
  final ValueChanged<int> onEnergy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return TrackerCard(
      title: 'Today',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Scale(
            caption: 'Mood',
            labels: kMoodLabels,
            selected: entry?.mood,
            icon: Icons.mood,
            onSelect: onMood,
          ),
          const SizedBox(height: 20),
          _Scale(
            caption: 'Energy',
            labels: kEnergyLabels,
            selected: entry?.energy,
            icon: Icons.bolt,
            onSelect: onEnergy,
          ),
          if (entry == null) ...[
            const SizedBox(height: 14),
            Text(
              'Tap either row. The other defaults to the middle, so one tap is '
              'enough on a day you cannot be bothered.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Scale extends StatelessWidget {
  const _Scale({
    required this.caption,
    required this.labels,
    required this.selected,
    required this.icon,
    required this.onSelect,
  });

  final String caption;
  final List<String> labels;
  final int? selected;
  final IconData icon;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = TrackerKind.checkIn.color;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: scheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Text(
              caption,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const Spacer(),
            if (selected != null)
              Text(
                labels[selected! - 1],
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (var score = 1; score <= 5; score++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Semantics(
                    selected: selected == score,
                    button: true,
                    label: '$caption ${labels[score - 1]}',
                    child: InkWell(
                      onTap: () {
                        Haptics.tick(context);
                        onSelect(score);
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        height: 46,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: selected == score
                              ? color
                              : color.withValues(
                                  // A gentle ramp, so the row reads as a scale
                                  // even before anything is chosen.
                                  alpha: 0.06 + score * 0.03,
                                ),
                          border: Border.all(
                            color: selected == score
                                ? color
                                : scheme.outlineVariant,
                          ),
                        ),
                        child: Text(
                          '$score',
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: selected == score
                                    ? Colors.white
                                    : scheme.onSurfaceVariant,
                              ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _RecentDays extends StatelessWidget {
  const _RecentDays({required this.store, required this.today});

  final TrackerStore store;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final entries = <CheckIn>[
      for (var age = 0; age < 7; age++) ?store.checkInOn(addDays(today, -age)),
    ];
    if (entries.isEmpty) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;

    return TrackerCard(
      title: 'Recent days',
      child: Column(
        children: [
          for (final entry in entries)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: TrackerKind.checkIn.color.withValues(
                  alpha: 0.16,
                ),
                child: Text(
                  entry.overall.toStringAsFixed(
                    entry.overall == entry.overall.roundToDouble() ? 0 : 1,
                  ),
                  style: TextStyle(
                    color: TrackerKind.checkIn.color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              title: Text(
                '${kMoodLabels[entry.mood - 1]} · '
                '${kEnergyLabels[entry.energy - 1]}',
              ),
              subtitle: Text(DateFormat.MMMEd().format(entry.day)),
              trailing: IconButton(
                icon: Icon(Icons.close, color: scheme.onSurfaceVariant),
                tooltip: 'Remove',
                onPressed: () => store.clearCheckIn(entry.day),
              ),
            ),
        ],
      ),
    );
  }
}
