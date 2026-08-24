import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/habit.dart';
import '../../models/trackers/fitness_entry.dart';
import '../../models/trackers/tracker_goals.dart';
import '../../models/trackers/tracker_kind.dart';
import '../../state/tracker_store.dart';
import '../../widgets/trackers/tracker_widgets.dart';

/// Fitness: active minutes against the weekly guideline, and whether the last
/// week is more than the last month has prepared you for.
class FitnessScreen extends StatelessWidget {
  const FitnessScreen({super.key});

  static const _kind = TrackerKind.fitness;

  @override
  Widget build(BuildContext context) {
    final store = TrackerScope.of(context);
    final goals = store.goals;
    final today = dateOnly(DateTime.now());
    final insights = FitnessInsights.from(store.data.workouts);

    final week = <({DateTime day, num value})>[
      for (var age = 6; age >= 0; age--)
        (
          day: addDays(today, -age),
          value: store.data.workouts
              .where((w) => w.day == addDays(today, -age))
              .fold<int>(0, (sum, w) => sum + w.minutes),
        ),
    ];

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addWorkout(context, store, today),
        backgroundColor: _kind.color,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Log a workout'),
      ),
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(title: Text(_kind.label)),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 108),
            sliver: SliverList.list(
              children: [
                Center(
                  child: GoalRing(
                    progress: insights.goalShare(goals),
                    value: '${insights.activeMinutesThisWeek}',
                    caption: 'of ${goals.activeMinutesPerWeek} min this week',
                    footnote: '${insights.sessionsThisWeek} session'
                        '${insights.sessionsThisWeek == 1 ? '' : 's'}',
                    accent: _kind.color,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Moderate intensity and above only — the guideline this is '
                  'measured against is about moderate activity, so easy '
                  'sessions are logged but not counted here.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
                _LoadCard(insights: insights),
                const SizedBox(height: 16),
                TrackerCard(
                  title: 'Last 7 days',
                  child: MiniBars(values: week, accent: _kind.color),
                ),
                const SizedBox(height: 16),
                TrackerCard(
                  title: 'This week',
                  child: Column(
                    children: [
                      TrackerStatRow(
                        icon: Icons.hotel_outlined,
                        label: 'Rest days',
                        value: '${insights.restDaysThisWeek}',
                      ),
                      TrackerStatRow(
                        icon: Icons.timer_outlined,
                        label: 'Longest session',
                        value: formatMinutes(insights.longestSessionMinutes),
                      ),
                      if (insights.byType.isNotEmpty) ...[
                        const Divider(height: 24),
                        for (final entry in insights.byType)
                          TrackerStatRow(
                            icon: Icons.circle,
                            label: entry.type.label,
                            value: formatMinutes(entry.minutes),
                          ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _WorkoutList(store: store),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addWorkout(
    BuildContext context,
    TrackerStore store,
    DateTime today,
  ) async {
    final draft = await showModalBottomSheet<
      ({WorkoutType type, int minutes, Intensity intensity, String note})
    >(
      context: context,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.92,
      ),
      builder: (_) => const _WorkoutEditor(),
    );
    if (draft == null) return;

    store.addWorkout(
      day: today,
      type: draft.type,
      minutes: draft.minutes,
      intensity: draft.intensity,
      note: draft.note,
    );
  }
}

/// Acute against chronic load — whether this week is a sensible step up.
class _LoadCard extends StatelessWidget {
  const _LoadCard({required this.insights});

  final FitnessInsights insights;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final ratio = insights.loadRatio;

    final color = switch (insights.verdict) {
      LoadVerdict.spiking => scheme.error,
      LoadVerdict.steady => TrackerKind.fitness.color,
      LoadVerdict.detraining => scheme.onSurfaceVariant,
      LoadVerdict.unknown => scheme.onSurfaceVariant,
    };

    return TrackerCard(
      title: 'Training load',
      trailing: Text(
        ratio == null ? '—' : '${ratio.toStringAsFixed(2)}×',
        style: textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            insights.verdict.label,
            style: textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            switch (insights.verdict) {
              LoadVerdict.unknown =>
                'Once there is about a month of workouts behind you, this '
                    'compares the last seven days against what your body is '
                    'used to.',
              LoadVerdict.detraining =>
                'This week is well below your recent normal. Fine as a planned '
                    'deload; worth noticing if it was not planned.',
              LoadVerdict.steady =>
                'This week is in line with the last month — the range that '
                    'builds fitness without outrunning what you are adapted to.',
              LoadVerdict.spiking =>
                'This week is a lot more than the last month has prepared you '
                    'for. Sharp jumps in load are where most overuse injuries '
                    'come from.',
            },
            style: textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const Divider(height: 24),
          TrackerStatRow(
            icon: Icons.bolt,
            label: 'This week',
            value: '${insights.acuteLoad}',
          ),
          TrackerStatRow(
            icon: Icons.timeline,
            label: 'Weekly average (4 weeks)',
            value: '${insights.chronicLoad}',
          ),
          const SizedBox(height: 6),
          Text(
            'Load is minutes times effort, so twenty minutes flat out and an '
            'hour\'s stroll do not read as the same session.',
            style: textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkoutList extends StatelessWidget {
  const _WorkoutList({required this.store});

  final TrackerStore store;

  @override
  Widget build(BuildContext context) {
    final workouts = store.data.workouts.reversed.take(10).toList();
    if (workouts.isEmpty) {
      return const TrackerCard(
        child: TrackerEmptyState(
          icon: Icons.fitness_center_outlined,
          title: 'No workouts yet',
          message:
              'Log what you did, for how long, and roughly how hard. Effort is '
              'what turns minutes into training load.',
        ),
      );
    }

    final scheme = Theme.of(context).colorScheme;

    return TrackerCard(
      title: 'Recent workouts',
      child: Column(
        children: [
          for (final workout in workouts)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: TrackerKind.fitness.color.withValues(
                  alpha: 0.16,
                ),
                child: Icon(
                  Icons.fitness_center,
                  size: 20,
                  color: TrackerKind.fitness.color,
                ),
              ),
              title: Text(
                '${workout.type.label} · ${formatMinutes(workout.minutes)}',
              ),
              subtitle: Text(
                '${DateFormat.MMMEd().format(workout.day)} · '
                '${workout.intensity.label}'
                '${workout.note.isEmpty ? '' : ' · ${workout.note}'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: IconButton(
                icon: Icon(Icons.close, color: scheme.onSurfaceVariant),
                tooltip: 'Remove',
                onPressed: () {
                  final removed = store.removeWorkout(workout.id);
                  if (removed == null) return;
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(
                      SnackBar(
                        content: const Text('Workout removed'),
                        action: SnackBarAction(
                          label: 'Undo',
                          onPressed: () => store.insertWorkout(
                            removed.index,
                            removed.workout,
                          ),
                        ),
                      ),
                    );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _WorkoutEditor extends StatefulWidget {
  const _WorkoutEditor();

  @override
  State<_WorkoutEditor> createState() => _WorkoutEditorState();
}

class _WorkoutEditorState extends State<_WorkoutEditor> {
  WorkoutType _type = WorkoutType.cardio;
  Intensity _intensity = Intensity.moderate;
  int _minutes = 30;
  final _noteController = TextEditingController();

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Log a workout', style: textTheme.headlineSmall),
              const SizedBox(height: 20),
              Text(
                'Type',
                style: textTheme.labelLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final type in WorkoutType.values)
                    ChoiceChip(
                      label: Text(type.label),
                      selected: _type == type,
                      selectedColor: TrackerKind.fitness.color.withValues(
                        alpha: 0.2,
                      ),
                      onSelected: (_) => setState(() => _type = type),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                'How hard?',
                style: textTheme.labelLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              SegmentedButton<Intensity>(
                segments: [
                  for (final intensity in Intensity.values)
                    ButtonSegment(
                      value: intensity,
                      label: Text(intensity.label),
                    ),
                ],
                selected: {_intensity},
                showSelectedIcon: false,
                onSelectionChanged: (selection) =>
                    setState(() => _intensity = selection.first),
              ),
              const SizedBox(height: 20),
              Text(
                'Time: ${formatMinutes(_minutes)}',
                style: textTheme.labelLarge,
              ),
              Slider(
                value: _minutes.toDouble(),
                min: 5,
                max: 240,
                divisions: 47,
                label: formatMinutes(_minutes),
                activeColor: TrackerKind.fitness.color,
                onChanged: (value) => setState(() => _minutes = value.round()),
              ),
              const SizedBox(height: 4),
              TextField(
                controller: _noteController,
                maxLength: 60,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Note (optional)',
                  hintText: '5k, upper body, football',
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: TrackerKind.fitness.color,
                  ),
                  onPressed: () => Navigator.pop(context, (
                    type: _type,
                    minutes: _minutes,
                    intensity: _intensity,
                    note: _noteController.text.trim(),
                  )),
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
