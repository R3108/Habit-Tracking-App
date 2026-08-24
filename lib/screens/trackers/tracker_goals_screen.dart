import 'package:flutter/material.dart';

import '../../models/trackers/tracker_goals.dart';
import '../../models/trackers/tracker_kind.dart';
import '../../state/tracker_store.dart';
import '../../widgets/trackers/tracker_widgets.dart';

/// Every tracker's target, in one place.
///
/// Grouped by tracker rather than presented as a flat list of numbers, so the
/// colour tells you which screen a slider is going to change before you read
/// the label.
class TrackerGoalsScreen extends StatelessWidget {
  const TrackerGoalsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = TrackerScope.of(context);
    final goals = store.goals;

    return Scaffold(
      appBar: AppBar(title: const Text('Targets')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _GoalGroup(
            kind: TrackerKind.sleep,
            children: [
              _GoalSlider(
                label: 'Nightly sleep',
                value: goals.sleepMinutes,
                min: 4 * 60,
                max: 11 * 60,
                step: 15,
                format: formatMinutes,
                accent: TrackerKind.sleep.color,
                onChanged: (value) =>
                    store.setGoals(goals.copyWith(sleepMinutes: value)),
              ),
            ],
          ),
          _GoalGroup(
            kind: TrackerKind.water,
            children: [
              _GoalSlider(
                label: 'Daily water',
                value: goals.waterMl,
                min: 500,
                max: 5000,
                step: 100,
                format: (value) => '$value ml',
                accent: TrackerKind.water.color,
                onChanged: (value) =>
                    store.setGoals(goals.copyWith(waterMl: value)),
              ),
              _GoalSlider(
                label: 'Undo step',
                value: goals.glassMl,
                min: 50,
                max: 750,
                step: 50,
                format: (value) => '$value ml',
                accent: TrackerKind.water.color,
                onChanged: (value) =>
                    store.setGoals(goals.copyWith(glassMl: value)),
              ),
            ],
          ),
          _GoalGroup(
            kind: TrackerKind.reading,
            children: [
              _GoalSlider(
                label: 'Daily reading',
                value: goals.readingMinutes,
                min: 5,
                max: 180,
                step: 5,
                format: formatMinutes,
                accent: TrackerKind.reading.color,
                onChanged: (value) =>
                    store.setGoals(goals.copyWith(readingMinutes: value)),
              ),
            ],
          ),
          _GoalGroup(
            kind: TrackerKind.food,
            children: [
              _GoalSlider(
                label: 'Eating window',
                value: goals.eatingWindowMinutes,
                min: 4 * 60,
                max: 16 * 60,
                step: 30,
                format: formatMinutes,
                accent: TrackerKind.food.color,
                onChanged: (value) =>
                    store.setGoals(goals.copyWith(eatingWindowMinutes: value)),
              ),
            ],
          ),
          _GoalGroup(
            kind: TrackerKind.focus,
            children: [
              _GoalSlider(
                label: 'Session length',
                value: goals.focusMinutes,
                min: 5,
                max: 90,
                step: 5,
                format: formatMinutes,
                accent: TrackerKind.focus.color,
                onChanged: (value) =>
                    store.setGoals(goals.copyWith(focusMinutes: value)),
              ),
              _GoalSlider(
                label: 'Short break',
                value: goals.breakMinutes,
                min: 1,
                max: 30,
                step: 1,
                format: formatMinutes,
                accent: TrackerKind.focus.color,
                onChanged: (value) =>
                    store.setGoals(goals.copyWith(breakMinutes: value)),
              ),
              _GoalSlider(
                label: 'Long break',
                value: goals.longBreakMinutes,
                min: 5,
                max: 45,
                step: 5,
                format: formatMinutes,
                accent: TrackerKind.focus.color,
                onChanged: (value) =>
                    store.setGoals(goals.copyWith(longBreakMinutes: value)),
              ),
              _GoalSlider(
                label: 'Sessions a day',
                value: goals.focusSessionsPerDay,
                min: 1,
                max: 16,
                step: 1,
                format: (value) => '$value',
                accent: TrackerKind.focus.color,
                onChanged: (value) =>
                    store.setGoals(goals.copyWith(focusSessionsPerDay: value)),
              ),
            ],
          ),
          _GoalGroup(
            kind: TrackerKind.fitness,
            children: [
              _GoalSlider(
                label: 'Active minutes a week',
                value: goals.activeMinutesPerWeek,
                min: 30,
                max: 600,
                step: 10,
                format: (value) => '$value min',
                accent: TrackerKind.fitness.color,
                onChanged: (value) => store.setGoals(
                  goals.copyWith(activeMinutesPerWeek: value),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'The defaults are the mainstream public-health figures, so the app '
            'has something honest to say on day one. They are not advice, and '
            'nothing here is sent anywhere.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _GoalGroup extends StatelessWidget {
  const _GoalGroup({required this.kind, required this.children});

  final TrackerKind kind;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TrackerCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(kind.icon, size: 20, color: kind.color),
                const SizedBox(width: 10),
                Text(
                  kind.label,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: kind.color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _GoalSlider extends StatelessWidget {
  const _GoalSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.format,
    required this.accent,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final int step;
  final String Function(int value) format;
  final Color accent;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            Text(
              format(value),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        Slider(
          value: value.clamp(min, max).toDouble(),
          min: min.toDouble(),
          max: max.toDouble(),
          divisions: ((max - min) / step).round(),
          activeColor: accent,
          onChanged: (raw) => onChanged(raw.round()),
        ),
      ],
    );
  }
}
