import 'package:flutter/material.dart';

import '../../models/habit.dart';
import '../../models/trackers/check_in_entry.dart';
import '../../models/trackers/custom_tracker.dart';
import '../../models/trackers/fitness_entry.dart';
import '../../models/trackers/focus_entry.dart';
import '../../models/trackers/reading_entry.dart';
import '../../models/trackers/sleep_entry.dart';
import '../../models/trackers/tracker_goals.dart';
import '../../models/trackers/tracker_kind.dart';
import '../../models/trackers/water_entry.dart';
import '../../state/tracker_store.dart';
import 'check_in_screen.dart';
import 'custom_tracker_screen.dart';
import 'fitness_screen.dart';
import 'focus_screen.dart';
import 'food_screen.dart';
import 'reading_screen.dart';
import 'sleep_screen.dart';
import 'tracker_goals_screen.dart';
import 'water_screen.dart';

/// The way in to the six trackers.
///
/// Each tile carries today's number rather than just a name, so the hub answers
/// "how am I doing" without being opened six times. A tracker with nothing in
/// it says so plainly instead of showing a zero, because a row of zeroes on a
/// fresh install reads as failure rather than as an empty notebook.
class TrackersHubScreen extends StatelessWidget {
  const TrackersHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = TrackerScope.of(context);
    final goals = store.goals;
    final today = dateOnly(DateTime.now());

    final sleep = SleepInsights.from(store.data.sleep, goals: goals);
    final water = WaterInsights.from(store.data.water, goals: goals);
    final reading = ReadingInsights.from(store.data.reading);
    final focus = FocusInsights.from(store.data.focus);
    final fitness = FitnessInsights.from(store.data.workouts);
    final todayFood = store.foodOn(today);

    final checkIn = store.checkInOn(today);

    final summaries = <TrackerKind, ({String value, double progress})?>{
      TrackerKind.checkIn: checkIn == null
          ? null
          : (
              value:
                  '${kMoodLabels[checkIn.mood - 1]} · '
                  '${kEnergyLabels[checkIn.energy - 1]}',
              progress: checkIn.overall / 5,
            ),
      TrackerKind.sleep: store.sleepOn(today) == null
          ? (sleep.hasData
                ? (
                    value: formatMinutes(sleep.averageMinutes),
                    progress: sleep.averageMinutes / goals.sleepMinutes,
                  )
                : null)
          : (
              value: formatMinutes(store.sleepOn(today)!.durationMinutes),
              progress:
                  store.sleepOn(today)!.durationMinutes / goals.sleepMinutes,
            ),
      TrackerKind.water: water.today == 0
          ? null
          : (value: '${water.today} ml', progress: water.share),
      TrackerKind.reading: reading.minutesToday == 0
          ? null
          : (
              value: formatMinutes(reading.minutesToday),
              progress: reading.minutesToday / goals.readingMinutes,
            ),
      TrackerKind.food: todayFood.isEmpty
          ? null
          : (
              value:
                  '${todayFood.meals.length} meal'
                  '${todayFood.meals.length == 1 ? '' : 's'}',
              progress: (todayFood.meals.length / 3).clamp(0.0, 1.0),
            ),
      TrackerKind.focus: focus.sessionsToday == 0
          ? null
          : (
              value: '${focus.sessionsToday}× · ${formatMinutes(focus.minutesToday)}',
              progress: focus.goalShare(goals),
            ),
      TrackerKind.fitness: fitness.sessionsThisWeek == 0
          ? null
          : (
              value: '${fitness.activeMinutesThisWeek} min this week',
              progress: fitness.goalShare(goals),
            ),
    };

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            title: const Text('Trackers'),
            actions: [
              IconButton(
                icon: const Icon(Icons.tune),
                tooltip: 'Targets',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const TrackerGoalsScreen(),
                  ),
                ),
              ),
            ],
          ),
          if (store.runningTimer case final timer?)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              sliver: SliverToBoxAdapter(
                child: _RunningTimerBanner(
                  timer: timer,
                  onOpen: () => _open(context, TrackerKind.focus),
                ),
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
            sliver: SliverList.list(
              children: [
                for (final kind in TrackerKind.values) ...[
                  _TrackerTile(
                    kind: kind,
                    summary: summaries[kind],
                    onTap: () => _open(context, kind),
                  ),
                  const SizedBox(height: 12),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Your own',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('New tracker'),
                      onPressed: () => _createTracker(context, store),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                if (store.data.activeCustomTrackers.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      'The six above each compute something specific to them. '
                      'For anything else — steps, coffees, guitar practice — '
                      'make your own and it gets the honest generic treatment: '
                      'a target, a streak, an average and a week of bars.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                else
                  for (final tracker in store.data.activeCustomTrackers) ...[
                    _CustomTrackerTile(
                      tracker: tracker,
                      today: store.customValueOn(tracker.id, today),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              CustomTrackerScreen(trackerId: tracker.id),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                const SizedBox(height: 8),
                Text(
                  'Every number here is worked out on this device from what you '
                  'log. Nothing is uploaded, and no tracker needs a permission '
                  'the app does not already have.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _createTracker(BuildContext context, TrackerStore store) async {
    final draft = await CustomTrackerEditor.show(context);
    if (draft == null) return;

    final tracker = store.addCustomTracker(
      name: draft.name,
      kind: draft.kind,
      iconKey: draft.iconKey,
      colorValue: draft.colorValue,
      unit: draft.unit,
      dailyTarget: draft.dailyTarget,
      step: draft.step,
      lowerIsBetter: draft.lowerIsBetter,
    );

    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CustomTrackerScreen(trackerId: tracker.id),
      ),
    );
  }

  void _open(BuildContext context, TrackerKind kind) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => switch (kind) {
          TrackerKind.checkIn => const CheckInScreen(),
          TrackerKind.sleep => const SleepScreen(),
          TrackerKind.water => const WaterScreen(),
          TrackerKind.reading => const ReadingScreen(),
          TrackerKind.food => const FoodScreen(),
          TrackerKind.focus => const FocusScreen(),
          TrackerKind.fitness => const FitnessScreen(),
        },
      ),
    );
  }
}

class _TrackerTile extends StatelessWidget {
  const _TrackerTile({
    required this.kind,
    required this.summary,
    required this.onTap,
  });

  final TrackerKind kind;
  final ({String value, double progress})? summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final summary = this.summary;

    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: kind.color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(kind.icon, color: kind.color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      kind.label,
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      summary?.value ?? kind.blurb,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(
                        color: summary == null
                            ? scheme.onSurfaceVariant
                            : kind.color,
                        fontWeight: summary == null
                            ? FontWeight.w400
                            : FontWeight.w700,
                      ),
                    ),
                    if (summary != null) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: summary.progress.clamp(0.0, 1.0),
                          minHeight: 5,
                          backgroundColor: scheme.surfaceContainerHighest,
                          valueColor: AlwaysStoppedAnimation(kind.color),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// A user-defined tracker on the hub.
///
/// Shows the same shape as a built-in tile, but always shows today's number
/// even when it is zero: for a tracker the user made themselves, a blank row is
/// indistinguishable from one that is broken.
class _CustomTrackerTile extends StatelessWidget {
  const _CustomTrackerTile({
    required this.tracker,
    required this.today,
    required this.onTap,
  });

  final CustomTracker tracker;
  final double today;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: tracker.color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(tracker.icon, color: tracker.color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tracker.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${tracker.format(today)} · '
                      '${tracker.lowerIsBetter ? 'under' : 'of'} '
                      '${tracker.format(tracker.dailyTarget)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(
                        color: tracker.color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: tracker.share(today),
                        minHeight: 5,
                        backgroundColor: scheme.surfaceContainerHighest,
                        valueColor: AlwaysStoppedAnimation(tracker.color),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// Surfaces a pomodoro left running, from wherever the user ends up.
class _RunningTimerBanner extends StatelessWidget {
  const _RunningTimerBanner({required this.timer, required this.onOpen});

  final RunningTimer timer;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final remaining = timer.remainingAt(DateTime.now());
    final minutes = remaining.inMinutes;

    return Material(
      color: scheme.tertiaryContainer,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(Icons.timer, color: scheme.onTertiaryContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  remaining == Duration.zero
                      ? '${timer.phase.label} finished — tap to bank it'
                      : '${timer.phase.label} running · '
                            '${minutes + 1} min left',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onTertiaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.onTertiaryContainer),
            ],
          ),
        ),
      ),
    );
  }
}
