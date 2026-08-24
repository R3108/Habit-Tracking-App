import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/habit.dart';
import '../state/habit_store.dart';
import '../state/settings_store.dart';
import '../widgets/habit_editor_sheet.dart';
import '../widgets/month_calendar.dart';
import '../widgets/stat_tile.dart';

/// One habit's history and statistics.
///
/// Takes an id rather than a [Habit] because the store hands out immutable
/// snapshots: holding the object would leave this screen showing stale data the
/// moment a day is ticked on it.
class HabitDetailScreen extends StatefulWidget {
  const HabitDetailScreen({super.key, required this.habitId});

  final String habitId;

  @override
  State<HabitDetailScreen> createState() => _HabitDetailScreenState();
}

class _HabitDetailScreenState extends State<HabitDetailScreen> {
  late DateTime _month = DateTime(
    DateTime.now().year,
    DateTime.now().month,
  );

  void _shiftMonth(int months) {
    setState(() => _month = DateTime(_month.year, _month.month + months));
  }

  Future<void> _edit(Habit habit) async {
    final store = HabitScope.of(context);
    final draft = await HabitEditorSheet.show(context, initial: habit);
    if (draft == null) return;

    store.update(
      habit.copyWith(
        title: draft.title,
        icon: draft.icon,
        color: draft.color,
        schedule: draft.schedule,
        targetPerDay: draft.targetPerDay,
        note: draft.note,
        reminder: draft.reminder,
        clearReminder: draft.reminder == null,
      ),
    );
  }

  Future<void> _confirmDelete(Habit habit) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete "${habit.title}"?'),
        content: const Text(
          'Its whole history goes with it. Archiving keeps the history and '
          'hides the habit instead.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    HabitScope.of(context).remove(habit.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final store = HabitScope.of(context);
    final settings = SettingsScope.of(context).settings;
    final habit = store.byId(widget.habitId);

    // The habit can vanish under us — deleted from the long-press menu on the
    // screen below, or wiped by a backup restore.
    if (habit == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('This habit no longer exists.')),
      );
    }

    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(habit.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit',
            onPressed: () => _edit(habit),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'archive':
                  store.setArchived(habit.id, !habit.archived);
                case 'delete':
                  _confirmDelete(habit);
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'archive',
                child: Text(habit.archived ? 'Restore' : 'Archive'),
              ),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _HabitHeader(habit: habit),
          const SizedBox(height: 20),
          _StatGrid(habit: habit),
          const SizedBox(height: 24),
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        DateFormat('MMMM yyyy').format(_month),
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      tooltip: 'Previous month',
                      onPressed: () => _shiftMonth(-1),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      tooltip: 'Next month',
                      // Nothing to see in the future; the calendar would be
                      // entirely inert.
                      onPressed:
                          _month.isBefore(
                            DateTime(DateTime.now().year, DateTime.now().month),
                          )
                          ? () => _shiftMonth(1)
                          : null,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                MonthCalendar(
                  habit: habit,
                  month: _month,
                  weekStartsOn: settings.weekStartsOn,
                  onToggleDay: (day) => store.toggle(habit.id, day),
                ),
                const SizedBox(height: 12),
                Text(
                  'Tap any past day to correct it.',
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (habit.note.isNotEmpty) ...[
            const SizedBox(height: 16),
            _Card(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.sticky_note_2_outlined,
                    size: 20,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(habit.note, style: textTheme.bodyMedium),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          _Card(
            child: Column(
              children: [
                _DetailRow(
                  icon: Icons.repeat,
                  label: 'Repeats',
                  value: habit.schedule.label,
                ),
                const SizedBox(height: 12),
                _DetailRow(
                  icon: Icons.alarm,
                  label: 'Reminder',
                  value: habit.reminder == null
                      ? 'Off'
                      : habit.reminder!.format(context),
                ),
                const SizedBox(height: 12),
                _DetailRow(
                  icon: Icons.event_available,
                  label: 'Tracking since',
                  value: DateFormat.yMMMd().format(habit.createdAt),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HabitHeader extends StatelessWidget {
  const _HabitHeader({required this.habit});

  final Habit habit;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: habit.color.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(habit.icon, size: 28, color: habit.color),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                habit.title,
                style: textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                habit.archived
                    ? 'Archived · ${habit.schedule.label}'
                    : habit.schedule.label,
                style: textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.habit});

  final Habit habit;

  @override
  Widget build(BuildContext context) {
    final rate = (habit.completionRateInLast(30) * 100).round();

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.7,
      children: [
        StatTile(
          icon: Icons.local_fire_department,
          value: '${habit.streak}',
          label: 'Current streak',
          accent: habit.color,
        ),
        StatTile(
          icon: Icons.emoji_events_outlined,
          value: '${habit.bestStreak}',
          label: 'Best streak',
          accent: habit.color,
        ),
        StatTile(
          icon: Icons.check_circle_outline,
          value: '${habit.totalCompletions}',
          label: 'Total completions',
          accent: habit.color,
        ),
        StatTile(
          icon: Icons.percent,
          value: '$rate%',
          label: 'Last 30 days',
          accent: habit.color,
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Icon(icon, size: 20, color: scheme.onSurfaceVariant),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// Bordered container used for every block on this screen.
class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: child,
    );
  }
}
