import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/habit.dart';
import '../models/lab/experiment.dart';
import '../state/experiment_store.dart';
import '../state/habit_store.dart';
import '../util/haptics.dart';
import '../widgets/section_card.dart';

/// The experiment log: what is running, and what finished runs concluded.
///
/// The screen is built around one rule, and most of its design follows from it:
/// a trial cannot be shortened, extended or backdated once it starts. That is
/// what separates this from every other number in the app. Everything else here
/// is measured *after* the fact from history that was recorded for other
/// reasons, and is therefore vulnerable to the user going looking for a
/// flattering window. An experiment fixes the window first, so there is no
/// window left to choose.
class ExperimentsScreen extends StatelessWidget {
  const ExperimentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final experiments = ExperimentScope.of(context);
    final habits = HabitScope.of(context);
    final today = dateOnly(DateTime.now());

    final running = experiments.running(reference: today);
    final finished = experiments.finished(reference: today);
    final abandoned = experiments.all.where((e) => e.abandoned).toList();

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: habits.habits.isEmpty
            ? null
            : () => _startExperiment(context),
        icon: const Icon(Icons.add),
        label: const Text('New experiment'),
      ),
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(title: const Text('Experiments')),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
            sliver: SliverList.list(
              children: [
                if (experiments.isEmpty) const _Explainer(),

                if (running.isNotEmpty) ...[
                  SectionCard(
                    title: 'Running',
                    subtitle: 'No verdict until the window closes',
                    child: Column(
                      children: [
                        for (final experiment in running)
                          _ExperimentTile(
                            experiment: experiment,
                            habit: habits.byId(experiment.habitId),
                            today: today,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                if (finished.isNotEmpty) ...[
                  SectionCard(
                    title: 'Finished',
                    subtitle: 'What each change was actually worth',
                    child: Column(
                      children: [
                        for (final experiment in finished)
                          _ExperimentTile(
                            experiment: experiment,
                            habit: habits.byId(experiment.habitId),
                            today: today,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                if (abandoned.isNotEmpty)
                  SectionCard(
                    title: 'Abandoned',
                    subtitle: 'Kept on purpose — see the note below',
                    child: Column(
                      children: [
                        for (final experiment in abandoned)
                          _ExperimentTile(
                            experiment: experiment,
                            habit: habits.byId(experiment.habitId),
                            today: today,
                          ),
                        const SizedBox(height: 4),
                        Text(
                          'Abandoned runs stay in the log. If the ones that '
                          'went badly disappeared, the rest would look better '
                          'than they were.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
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

  Future<void> _startExperiment(BuildContext context) async {
    final store = ExperimentScope.of(context);
    final habitStore = HabitScope.of(context);
    final today = dateOnly(DateTime.now());

    // A habit already under test cannot host a second trial: each would be the
    // other's uncontrolled variable.
    final available = habitStore.habits
        .where((h) => !store.hasRunning(h.id, reference: today))
        .toList();

    if (available.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Every habit already has an experiment running.',
            ),
          ),
        );
      return;
    }

    final result = await showModalBottomSheet<_NewExperiment>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _NewExperimentSheet(habits: available),
    );

    if (result == null || !context.mounted) return;

    store.start(
      habitId: result.habitId,
      change: result.change,
      startDay: today,
      lengthDays: result.lengthDays,
      baselineDays: result.baselineDays,
    );

    if (!context.mounted) return;
    Haptics.tick(context);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            'Running until '
            '${DateFormat.MMMd().format(addDays(today, result.lengthDays - 1))}',
          ),
        ),
      );
  }
}

/// One experiment, with its verdict or its progress.
class _ExperimentTile extends StatelessWidget {
  const _ExperimentTile({
    required this.experiment,
    required this.habit,
    required this.today,
  });

  final Experiment experiment;
  final Habit? habit;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final target = habit;

    // A run whose habit is gone can never be scored. It is pruned at startup,
    // so this is only reachable mid-session, right after a deletion.
    if (target == null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(
          '"${experiment.change}" — the habit behind this was deleted.',
          style: textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      );
    }

    final result = ExperimentResult.of(experiment, target, reference: today);
    final tone = switch (result.verdict) {
      ExperimentVerdict.helped => scheme.primary,
      ExperimentVerdict.hurt => scheme.error,
      _ => scheme.onSurfaceVariant,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(target.icon, size: 18, color: target.color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  experiment.change,
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _VerdictChip(
                label: experiment.abandoned
                    ? 'Abandoned'
                    : result.verdict.label,
                colour: experiment.abandoned ? scheme.onSurfaceVariant : tone,
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            '${target.title} · '
            '${DateFormat.MMMd().format(experiment.startDay)}'
            '–${DateFormat.MMMd().format(experiment.endDay)}',
            style: textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),

          if (!experiment.abandoned &&
              result.verdict == ExperimentVerdict.running) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: result.progress,
                minHeight: 6,
                backgroundColor: scheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation<Color>(target.color),
              ),
            ),
            const SizedBox(height: 6),
          ],

          Text(
            experiment.abandoned
                ? 'Ended early, so it was never scored.'
                : result.summary,
            style: textTheme.bodySmall?.copyWith(color: scheme.onSurface),
          ),

          if (result.pValue != null) ...[
            const SizedBox(height: 6),
            Text(
              'Change: ${result.intervalText} (95% interval), '
              'p = ${result.pValue!.toStringAsFixed(3)}',
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            Text(
              'Kept ${result.trialKept}/${result.trialDue} due days during, '
              '${result.baselineKept}/${result.baselineDue} before.',
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
              ),
            ),
          ],

          const SizedBox(height: 6),
          Row(
            children: [
              if (!experiment.abandoned &&
                  result.verdict == ExperimentVerdict.running)
                TextButton(
                  onPressed: () => _confirmAbandon(context, experiment),
                  child: const Text('End early'),
                ),
              TextButton(
                onPressed: () => _delete(context, experiment),
                child: Text(
                  'Delete',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmAbandon(
    BuildContext context,
    Experiment experiment,
  ) async {
    final store = ExperimentScope.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('End this experiment?'),
        content: const Text(
          'It will be kept in the log as abandoned, and never scored. '
          'Stopping a trial once you can see how it is going is exactly what '
          'makes a result meaningless, so there is no way to end one and keep '
          'the verdict.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep running'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('End it'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    store.abandon(experiment.id);
  }

  void _delete(BuildContext context, Experiment experiment) {
    final store = ExperimentScope.of(context);
    final removed = store.remove(experiment.id);
    if (removed == null) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('Experiment deleted'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => store.insert(removed.index, removed.experiment),
          ),
        ),
      );
  }
}

class _VerdictChip extends StatelessWidget {
  const _VerdictChip({required this.label, required this.colour});

  final String label;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: colour,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// What the caller hands back from the creation sheet.
class _NewExperiment {
  const _NewExperiment({
    required this.habitId,
    required this.change,
    required this.lengthDays,
    required this.baselineDays,
  });

  final String habitId;
  final String change;
  final int lengthDays;
  final int baselineDays;
}

class _NewExperimentSheet extends StatefulWidget {
  const _NewExperimentSheet({required this.habits});

  final List<Habit> habits;

  @override
  State<_NewExperimentSheet> createState() => _NewExperimentSheetState();
}

class _NewExperimentSheetState extends State<_NewExperimentSheet> {
  late String _habitId = widget.habits.first.id;
  final _change = TextEditingController();
  int _length = 21;

  /// Trial lengths offered.
  ///
  /// Nothing under a week: a shorter window cannot hold enough due days for the
  /// comparison to say anything, and offering it would only produce a queue of
  /// "not enough data" verdicts.
  static const _lengths = <int>[7, 14, 21, 30, 60];

  /// The baseline is derived rather than chosen.
  ///
  /// Twice the trial, capped at 90 days. Wider than the trial because it is
  /// standing in for "what would have happened anyway" and a steadier estimate
  /// of that is worth having; capped because the user of six months ago is not
  /// a good control for the user of next month. Deriving it also removes a knob
  /// that could be turned until the answer came out nicely.
  int get _baseline => (_length * 2).clamp(14, 90);

  @override
  void dispose() {
    _change.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final today = dateOnly(DateTime.now());

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'New experiment',
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'One change, one habit, and a window fixed before you start.',
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),

            DropdownButtonFormField<String>(
              initialValue: _habitId,
              decoration: const InputDecoration(
                labelText: 'Habit',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final habit in widget.habits)
                  DropdownMenuItem<String>(
                    value: habit.id,
                    child: Text(habit.title, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _habitId = value);
              },
            ),
            const SizedBox(height: 16),

            TextField(
              controller: _change,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'What are you changing?',
                hintText: 'Moved it to 6am',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 20),

            Text('Run it for', style: textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final length in _lengths)
                  ChoiceChip(
                    label: Text('$length days'),
                    selected: _length == length,
                    onSelected: (_) => setState(() => _length = length),
                  ),
              ],
            ),
            const SizedBox(height: 16),

            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Runs ${DateFormat.MMMd().format(today)} to '
                    '${DateFormat.MMMd().format(addDays(today, _length - 1))}, '
                    'compared against the $_baseline days before it.',
                    style: textTheme.bodySmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'The window cannot be changed once it starts, and there is '
                    'no verdict until it closes.',
                    style: textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _change.text.trim().isEmpty
                      ? null
                      : () => Navigator.pop(
                          context,
                          _NewExperiment(
                            habitId: _habitId,
                            change: _change.text.trim(),
                            lengthDays: _length,
                            baselineDays: _baseline,
                          ),
                        ),
                  child: const Text('Start'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown once, while the log is empty, to explain why this is not just another
/// chart.
class _Explainer extends StatelessWidget {
  const _Explainer();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return SectionCard(
      title: 'Why this is different',
      subtitle: 'Everything else here reads the past',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Insights and the coach look back through what you have already '
            'done and pick out what stands out. That is useful, but anything '
            'found that way can be a coincidence that happened to catch the '
            'eye.',
            style: textTheme.bodySmall?.copyWith(color: scheme.onSurface),
          ),
          const SizedBox(height: 10),
          Text(
            'An experiment asks one question, fixes the window before there is '
            'any evidence, and then reports whatever comes out — including '
            '"nothing". You cannot shorten it because it is going badly, or '
            'stretch it because it nearly worked.',
            style: textTheme.bodySmall?.copyWith(color: scheme.onSurface),
          ),
          const SizedBox(height: 10),
          Text(
            'Try: move a habit to a different time, stack it behind another '
            'one, halve the target, or drop a weekday. One thing at a time.',
            style: textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
