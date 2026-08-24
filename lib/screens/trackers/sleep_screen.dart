import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/habit.dart';
import '../../models/trackers/sleep_entry.dart';
import '../../models/trackers/tracker_goals.dart';
import '../../models/trackers/tracker_kind.dart';
import '../../state/tracker_store.dart';
import '../../util/haptics.dart';
import '../../widgets/trackers/tracker_widgets.dart';

/// Sleep: how long, how regular, and how much is owed.
class SleepScreen extends StatelessWidget {
  const SleepScreen({super.key});

  static const _kind = TrackerKind.sleep;

  @override
  Widget build(BuildContext context) {
    final store = TrackerScope.of(context);
    final goals = store.goals;
    final today = dateOnly(DateTime.now());
    final insights = SleepInsights.from(store.data.sleep, goals: goals);

    // Last night is the night that ended this morning; before it is filled in,
    // the screen leads with the night before rather than an empty ring.
    final lastNight = store.sleepOn(today) ?? store.sleepOn(addDays(today, -1));

    final nights = <({DateTime day, num value})>[
      for (var age = 13; age >= 0; age--)
        (
          day: addDays(today, -age),
          value: store.sleepOn(addDays(today, -age))?.durationMinutes ?? 0,
        ),
    ];

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _logSleep(context, store, today),
        backgroundColor: _kind.color,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: Text(store.sleepOn(today) == null ? 'Log a night' : 'Edit last night'),
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
                    progress: (lastNight?.durationMinutes ?? 0) /
                        goals.sleepMinutes,
                    value: lastNight == null
                        ? '—'
                        : formatMinutes(lastNight.durationMinutes),
                    caption: lastNight == null
                        ? 'nothing logged'
                        : 'target ${formatMinutes(goals.sleepMinutes)}',
                    footnote: lastNight == null
                        ? null
                        : '${formatClock(lastNight.bedMinutes)} → '
                              '${formatClock(lastNight.wakeMinutes)}',
                    accent: _kind.color,
                  ),
                ),
                const SizedBox(height: 24),
                TrackerCard(
                  title: 'Last 14 nights',
                  child: MiniBars(
                    values: nights,
                    goal: goals.sleepMinutes,
                    accent: _kind.color,
                  ),
                ),
                const SizedBox(height: 16),
                if (!insights.hasData)
                  const TrackerCard(
                    child: TrackerEmptyState(
                      icon: Icons.bedtime_outlined,
                      title: 'No nights logged yet',
                      message:
                          'Log a couple of nights and this starts reporting '
                          'your average, how much sleep you are owed, and how '
                          'steady your bedtime is.',
                    ),
                  )
                else ...[
                  TrackerCard(
                    title: 'Over ${insights.nights} nights',
                    child: Column(
                      children: [
                        TrackerStatRow(
                          icon: Icons.schedule,
                          label: 'Average night',
                          value: formatMinutes(insights.averageMinutes),
                        ),
                        TrackerStatRow(
                          icon: Icons.check_circle_outline,
                          label: 'Nights at target',
                          value: '${insights.goalNights}/${insights.nights}',
                        ),
                        TrackerStatRow(
                          icon: Icons.sentiment_satisfied_alt_outlined,
                          label: 'Average quality',
                          value: '${insights.averageQuality.toStringAsFixed(1)}'
                              '/5',
                        ),
                        TrackerStatRow(
                          icon: Icons.account_balance_outlined,
                          label: 'Sleep debt',
                          value: formatMinutes(insights.debtMinutes),
                          emphasis: insights.debtMinutes > 240
                              ? Theme.of(context).colorScheme.error
                              : null,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _RegularityCard(insights: insights),
                ],
                const SizedBox(height: 16),
                _RecentNights(store: store, today: today),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _logSleep(
    BuildContext context,
    TrackerStore store,
    DateTime today,
  ) async {
    final existing = store.sleepOn(today);
    final entry = await showModalBottomSheet<SleepEntry>(
      context: context,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.92,
      ),
      builder: (_) => _SleepEditor(day: today, initial: existing),
    );
    if (entry != null) store.logSleep(entry);
  }
}

/// Regularity and body-clock drift, the two things a clock alone cannot show.
class _RegularityCard extends StatelessWidget {
  const _RegularityCard({required this.insights});

  final SleepInsights insights;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final jetlag = insights.socialJetlagMinutes;

    return TrackerCard(
      title: 'Regularity',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Bedtime consistency',
                  style: textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              Text(
                '${insights.consistencyScore}/100',
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: insights.consistencyScore / 100,
              minHeight: 6,
              backgroundColor: scheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation(TrackerKind.sleep.color),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            insights.consistencyScore >= 70
                ? 'Your bedtime barely moves. Going to bed at a steady hour '
                      'tracks health outcomes about as closely as total hours '
                      'do, and it is the half most people never look at.'
                : 'Your bedtime moves around a fair amount. Pulling it into a '
                      'narrower window is usually easier than finding an extra '
                      'hour, and counts for about as much.',
            style: textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          if (jetlag != null) ...[
            const Divider(height: 28),
            TrackerStatRow(
              icon: Icons.swap_horiz,
              label: 'Weekend body-clock shift',
              value: formatMinutes(jetlag),
              emphasis: jetlag >= 60 ? scheme.error : null,
            ),
            const SizedBox(height: 4),
            Text(
              jetlag >= 60
                  ? 'The middle of your night lands ${formatMinutes(jetlag)} '
                        'later at weekends. That is the jet lag of a real '
                        'time-zone hop, taken every week without the holiday.'
                  : 'Your weekends barely shift your body clock, which is the '
                        'harder half of sleeping well.',
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RecentNights extends StatelessWidget {
  const _RecentNights({required this.store, required this.today});

  final TrackerStore store;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final entries = <SleepEntry>[
      for (var age = 0; age < 7; age++) ?store.sleepOn(addDays(today, -age)),
    ];
    if (entries.isEmpty) return const SizedBox.shrink();

    return TrackerCard(
      title: 'Recent nights',
      child: Column(
        children: [
          for (final entry in entries)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: TrackerKind.sleep.color.withValues(
                  alpha: 0.16,
                ),
                child: Text(
                  '${entry.quality}',
                  style: TextStyle(
                    color: TrackerKind.sleep.color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              title: Text(formatMinutes(entry.durationMinutes)),
              subtitle: Text(
                '${DateFormat.MMMEd().format(entry.day)} · '
                '${formatClock(entry.bedMinutes)} → '
                '${formatClock(entry.wakeMinutes)}',
              ),
              trailing: IconButton(
                icon: Icon(Icons.close, color: scheme.onSurfaceVariant),
                tooltip: 'Remove',
                onPressed: () {
                  Haptics.tick(context);
                  store.clearSleep(entry.day);
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// Bedtime, wake time and how it felt.
class _SleepEditor extends StatefulWidget {
  const _SleepEditor({required this.day, this.initial});

  final DateTime day;
  final SleepEntry? initial;

  @override
  State<_SleepEditor> createState() => _SleepEditorState();
}

class _SleepEditorState extends State<_SleepEditor> {
  late TimeOfDay _bed = _toTime(widget.initial?.bedMinutes ?? 23 * 60);
  late TimeOfDay _wake = _toTime(widget.initial?.wakeMinutes ?? 7 * 60);
  late int _quality = widget.initial?.quality ?? 3;
  late final _noteController = TextEditingController(
    text: widget.initial?.note ?? '',
  );

  static TimeOfDay _toTime(int minutes) =>
      TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);

  int get _bedMinutes => _bed.hour * 60 + _bed.minute;
  int get _wakeMinutes => _wake.hour * 60 + _wake.minute;
  int get _duration => (_wakeMinutes - _bedMinutes + 1440) % 1440;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pick({required bool isBed}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isBed ? _bed : _wake,
    );
    if (picked == null) return;
    setState(() {
      if (isBed) {
        _bed = picked;
      } else {
        _wake = picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.initial == null ? 'Log last night' : 'Edit last night',
                style: textTheme.headlineSmall,
              ),
              const SizedBox(height: 4),
              Text(
                'Filed under ${DateFormat.MMMEd().format(widget.day)}, the '
                'morning it ended.',
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: _TimeField(
                      label: 'Asleep at',
                      value: _bed.format(context),
                      icon: Icons.bedtime_outlined,
                      onTap: () => _pick(isBed: true),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _TimeField(
                      label: 'Woke at',
                      value: _wake.format(context),
                      icon: Icons.wb_sunny_outlined,
                      onTap: () => _pick(isBed: false),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  formatMinutes(_duration),
                  style: textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: TrackerKind.sleep.color,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'How did it feel?',
                style: textTheme.labelLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (var score = 1; score <= 5; score++)
                    _QualityDot(
                      score: score,
                      isSelected: _quality == score,
                      onTap: () => setState(() => _quality = score),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _noteController,
                maxLength: 60,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Note (optional)',
                  hintText: 'Woke at 3am, noisy street',
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: TrackerKind.sleep.color,
                  ),
                  onPressed: () => Navigator.pop(
                    context,
                    SleepEntry(
                      day: widget.day,
                      bedMinutes: _bedMinutes,
                      wakeMinutes: _wakeMinutes,
                      quality: _quality,
                      note: _noteController.text.trim(),
                    ),
                  ),
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

class _TimeField extends StatelessWidget {
  const _TimeField({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: scheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QualityDot extends StatelessWidget {
  const _QualityDot({
    required this.score,
    required this.isSelected,
    required this.onTap,
  });

  final int score;
  final bool isSelected;
  final VoidCallback onTap;

  static const _faces = [
    Icons.sentiment_very_dissatisfied,
    Icons.sentiment_dissatisfied,
    Icons.sentiment_neutral,
    Icons.sentiment_satisfied,
    Icons.sentiment_very_satisfied,
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = TrackerKind.sleep.color;

    return Semantics(
      selected: isSelected,
      button: true,
      label: 'Quality $score of 5',
      child: InkResponse(
        onTap: onTap,
        radius: 28,
        child: Container(
          width: 52,
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isSelected
                ? color.withValues(alpha: 0.18)
                : Colors.transparent,
            border: Border.all(
              color: isSelected ? color : scheme.outlineVariant,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Icon(
            _faces[score - 1],
            color: isSelected ? color : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
