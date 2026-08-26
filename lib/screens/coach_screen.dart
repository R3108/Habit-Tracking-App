import 'package:flutter/material.dart';

import '../models/briefing.dart';
import '../models/forecast.dart';
import '../models/goal_coach.dart';
import '../models/habit.dart';
import '../models/schedule_coach.dart';
import '../state/habit_store.dart';
import '../state/tracker_store.dart';
import '../widgets/section_card.dart';
import 'habit_detail_screen.dart';

/// Today, read back to the user — and the two places the plan itself is wrong.
///
/// The only screen in the app that proposes changing anything. Everything on it
/// is a suggestion with the evidence attached and a button that applies it in
/// one tap, undoable; nothing here ever moves on its own. An app that quietly
/// lowered your targets while you slept would be an app whose numbers meant
/// nothing.
class CoachScreen extends StatelessWidget {
  const CoachScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final habitStore = HabitScope.of(context);
    final trackerStore = TrackerScope.of(context);
    final habits = habitStore.habits;

    if (habits.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Coach')),
        body: const _NothingToCoach(),
      );
    }

    final briefing = DailyBriefing.build(
      habits: habits,
      trackers: trackerStore.data,
    );
    final outstanding = briefing.forecast.remaining;

    return Scaffold(
      appBar: AppBar(title: const Text('Coach')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _BriefingHeadline(briefing: briefing),
          const SizedBox(height: 16),
          for (final item in briefing.items) ...[
            _BriefingTile(
              item: item,
              onOpen: item.habitId == null
                  ? null
                  : () => _openHabit(context, item.habitId!),
            ),
            const SizedBox(height: 8),
          ],
          if (outstanding.isNotEmpty) ...[
            const SizedBox(height: 8),
            SectionCard(
              title: "Today's odds",
              subtitle: 'What your own history says about each one',
              child: Column(
                children: [
                  for (final forecast in outstanding)
                    if (habitStore.byId(forecast.habitId) case final habit?)
                      _OddsRow(
                        forecast: forecast,
                        habit: habit,
                        onTap: () => _openHabit(context, habit.id),
                      ),
                  const SizedBox(height: 4),
                  _Footnote(
                    text: briefing.forecast.isReliable
                        ? 'Fitted per habit from its own last few months: the '
                              'weekday, what happened last time it was due, and '
                              'whether its cue has fired. Odds, not verdicts — '
                              'people break their patterns, which is rather the '
                              'point of tracking them.'
                        : 'Still learning. A habit needs a few weeks of due '
                              'days before these are worth reading.',
                  ),
                ],
              ),
            ),
          ],
          if (briefing.schedule.isNotEmpty) ...[
            const SizedBox(height: 16),
            SectionCard(
              title: 'Schedule changes',
              subtitle: 'Where the plan and the history disagree',
              child: Column(
                children: [
                  for (final suggestion in briefing.schedule)
                    if (habitStore.byId(suggestion.habitId) case final habit?)
                      _ScheduleCard(
                        suggestion: suggestion,
                        habit: habit,
                        onApply: () =>
                            _applySchedule(context, habitStore, suggestion, habit),
                      ),
                  const _Footnote(
                    text: 'A schedule change moves what the app expects, not '
                        'what you do — ease a quota and tomorrow\'s percentage '
                        'rises without a single extra thing being done. That is '
                        'worth doing when the plan is wrong, and worth knowing '
                        'you did.',
                  ),
                ],
              ),
            ),
          ],
          if (briefing.goals.isNotEmpty) ...[
            const SizedBox(height: 16),
            SectionCard(
              title: 'Targets',
              subtitle: 'Aimed at what you would hit six days in ten',
              child: Column(
                children: [
                  for (final suggestion in briefing.goals)
                    _GoalCard(
                      suggestion: suggestion,
                      onApply: () =>
                          _applyGoal(context, trackerStore, suggestion),
                    ),
                  const _Footnote(
                    text: 'The starting numbers are public-health defaults. A '
                        'target you have never once reached has stopped being a '
                        'target, and one you clear without noticing has stopped '
                        'asking.',
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          _Footnote(
            text: 'Everything on this screen is worked out on this device from '
                'the logs you keep. Nothing is sent anywhere, and no two people '
                'get the same page.',
          ),
        ],
      ),
    );
  }

  void _openHabit(BuildContext context, String habitId) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HabitDetailScreen(habitId: habitId),
      ),
    );
  }

  void _applySchedule(
    BuildContext context,
    HabitStore store,
    ScheduleSuggestion suggestion,
    Habit habit,
  ) {
    final previous = habit.schedule;
    store.update(habit.copyWith(schedule: suggestion.proposed));

    _notify(
      context,
      '"${habit.title}" — now ${suggestion.proposed.label.toLowerCase()}',
      onUndo: () {
        final current = store.byId(habit.id);
        if (current != null) {
          store.update(current.copyWith(schedule: previous));
        }
      },
    );
  }

  void _applyGoal(
    BuildContext context,
    TrackerStore store,
    GoalSuggestion suggestion,
  ) {
    switch (suggestion) {
      case TrackerGoalSuggestion():
        final previous = store.goals;
        store.setGoals(suggestion.apply(previous));
        _notify(
          context,
          '${suggestion.label} target — ${suggestion.proposedLabel}',
          onUndo: () => store.setGoals(previous),
        );

      case CustomGoalSuggestion():
        final previous = suggestion.tracker;
        store.updateCustomTracker(suggestion.apply());
        _notify(
          context,
          '${suggestion.label} target — ${suggestion.proposedLabel}',
          onUndo: () => store.updateCustomTracker(previous),
        );
    }
  }

  void _notify(BuildContext context, String message, {VoidCallback? onUndo}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          action: onUndo == null
              ? null
              : SnackBarAction(label: 'Undo', onPressed: onUndo),
        ),
      );
  }
}

/// The one line worth reading if only one line gets read.
class _BriefingHeadline extends StatelessWidget {
  const _BriefingHeadline({required this.briefing});

  final DailyBriefing briefing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, color: scheme.onPrimaryContainer),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  briefing.headline,
                  style: textTheme.titleLarge?.copyWith(
                    color: scheme.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            briefing.subhead,
            style: textTheme.bodyMedium?.copyWith(
              color: scheme.onPrimaryContainer.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }
}

class _BriefingTile extends StatelessWidget {
  const _BriefingTile({required this.item, this.onOpen});

  final BriefingItem item;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final color = switch (item.tone) {
      BriefingTone.good => scheme.primary,
      BriefingTone.warning => scheme.error,
      BriefingTone.neutral => scheme.onSurfaceVariant,
    };

    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(item.icon, size: 20, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  item.text,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              if (onOpen != null)
                Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: scheme.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One habit's odds for today, with the condition doing the most work.
class _OddsRow extends StatelessWidget {
  const _OddsRow({
    required this.forecast,
    required this.habit,
    required this.onTap,
  });

  final HabitForecast forecast;
  final Habit habit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final factor = forecast.dominant;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(habit.icon, size: 20, color: habit.color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          habit.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodyMedium,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        forecast.hasEnoughHistory
                            ? '${forecast.percent}%'
                            : '—',
                        style: textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: forecast.hasEnoughHistory
                          ? forecast.probability
                          : 0,
                      minHeight: 6,
                      backgroundColor: scheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation(habit.color),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    !forecast.hasEnoughHistory
                        ? 'Not enough due days yet'
                        : factor == null
                        ? '${forecast.outlook} · nothing unusual about today'
                        : '${forecast.outlook} · ${factor.label.toLowerCase()} '
                              'run at ${factor.percent}% '
                              '(${factor.days} days)',
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
    );
  }
}

/// A proposed schedule change, with its evidence and one button.
class _ScheduleCard extends StatelessWidget {
  const _ScheduleCard({
    required this.suggestion,
    required this.habit,
    required this.onApply,
  });

  final ScheduleSuggestion suggestion;
  final Habit habit;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(habit.icon, size: 18, color: habit.color),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${suggestion.headline} · "${habit.title}"',
                    style: textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(suggestion.rationale, style: textTheme.bodySmall),
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  '${habit.schedule.label} → ${suggestion.proposed.label}',
                  style: textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                FilledButton.tonal(
                  onPressed: onApply,
                  child: const Text('Apply'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A proposed target change.
class _GoalCard extends StatelessWidget {
  const _GoalCard({required this.suggestion, required this.onApply});

  final GoalSuggestion suggestion;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(suggestion.icon, size: 18, color: scheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${suggestion.label} · ${suggestion.headline}',
                    style: textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(suggestion.rationale, style: textTheme.bodySmall),
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  '${suggestion.currentLabel} → ${suggestion.proposedLabel}',
                  style: textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                FilledButton.tonal(
                  onPressed: onApply,
                  child: const Text('Apply'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Footnote extends StatelessWidget {
  const _Footnote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _NothingToCoach extends StatelessWidget {
  const _NothingToCoach();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.auto_awesome, size: 64, color: scheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              'Nothing to coach yet',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Add a habit or two. Once there are a few weeks of days behind '
              'them, this screen works out what your good days have in common '
              'and where the plan is asking for the wrong thing.',
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
