import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/habit.dart';
import '../state/habit_store.dart';
import '../state/settings_store.dart';
import '../widgets/day_selector.dart';
import '../widgets/habit_card.dart';
import '../widgets/habit_editor_sheet.dart';
import 'habit_detail_screen.dart';

/// The daily checklist.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// The day the list is showing. Defaults to today, but the day strip can
  /// point it at any of the last seven days.
  DateTime _selectedDay = dateOnly(DateTime.now());

  /// Reordering is a mode rather than a gesture.
  ///
  /// The normal list already spends long-press on the habit menu and a
  /// horizontal swipe on delete; adding drag-to-reorder on top of those makes
  /// every one of them fire by accident. A mode also lets the list show *every*
  /// active habit while ordering, not just the ones due today.
  bool _reordering = false;

  Future<void> _addHabit() async {
    final store = HabitScope.of(context);
    final draft = await HabitEditorSheet.show(context);
    if (draft == null) return;

    store.add(
      title: draft.title,
      icon: draft.icon,
      color: draft.color,
      schedule: draft.schedule,
      targetPerDay: draft.targetPerDay,
      reminder: draft.reminder,
      note: draft.note,
    );
  }

  Future<void> _editHabit(Habit habit) async {
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

  void _openHabit(Habit habit) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HabitDetailScreen(habitId: habit.id),
      ),
    );
  }

  void _archiveHabit(HabitStore store, Habit habit) {
    store.setArchived(habit.id, true);
    _notify(
      'Archived "${habit.title}"',
      undoLabel: 'Undo',
      onUndo: () => store.setArchived(habit.id, false),
    );
  }

  void _deleteHabit(HabitStore store, Habit habit) {
    final removed = store.remove(habit.id);
    if (removed == null) return;
    _notify(
      'Deleted "${habit.title}"',
      undoLabel: 'Undo',
      onUndo: () => store.insert(removed.index, removed.habit),
    );
  }

  void _notify(String message, {String? undoLabel, VoidCallback? onUndo}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          action: undoLabel == null || onUndo == null
              ? null
              : SnackBarAction(label: undoLabel, onPressed: onUndo),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final store = HabitScope.of(context);
    final settings = SettingsScope.of(context).settings;

    final due = store.dueOn(_selectedDay);
    final completed = store.completedOn(_selectedDay);
    final resting = store.habits
        .where((h) => !due.contains(h) && !_selectedDay.isBefore(h.createdAt))
        .toList();

    return Scaffold(
      // Hidden while ordering: it would sit on top of the drag handle of the
      // last row, and adding a habit mid-drag has nowhere sensible to land.
      floatingActionButton: _reordering
          ? null
          : FloatingActionButton.extended(
              onPressed: _addHabit,
              icon: const Icon(Icons.add),
              label: const Text('New habit'),
            ),
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            title: Text(_reordering ? 'Reorder habits' : 'Today'),
            actions: [
              if (_reordering)
                TextButton(
                  onPressed: () => setState(() => _reordering = false),
                  child: const Text('Done'),
                )
              else ...[
                if (_selectedDay != dateOnly(DateTime.now()))
                  IconButton(
                    icon: const Icon(Icons.today_outlined),
                    tooltip: 'Jump to today',
                    onPressed: () =>
                        setState(() => _selectedDay = dateOnly(DateTime.now())),
                  ),
                if (store.habits.length > 1)
                  IconButton(
                    icon: const Icon(Icons.swap_vert),
                    tooltip: 'Reorder habits',
                    onPressed: () => setState(() => _reordering = true),
                  ),
              ],
            ],
          ),
          if (!_reordering)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SummaryCard(
                      day: _selectedDay,
                      completed: completed,
                      total: due.length,
                    ),
                    const SizedBox(height: 20),
                    DaySelector(
                      selectedDay: _selectedDay,
                      onSelect: (day) => setState(() => _selectedDay = day),
                      completedCountFor: store.completedOn,
                      dueCountFor: store.dueCountOn,
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          if (_reordering)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
              sliver: SliverReorderableList(
                itemCount: store.habits.length,
                onReorderItem: store.reorder,
                itemBuilder: (context, index) {
                  final habit = store.habits[index];
                  return _ReorderTile(
                    key: ValueKey('reorder-${habit.id}'),
                    habit: habit,
                    index: index,
                  );
                },
              ),
            )
          else if (store.habits.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyState(),
            )
          else ...[
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList.builder(
                itemCount: due.length,
                itemBuilder: (context, index) {
                  final habit = due[index];
                  return HabitCard(
                    key: ValueKey(habit.id),
                    habit: habit,
                    day: _selectedDay,
                    onToggle: () => store.toggle(habit.id, _selectedDay),
                    onIncrement: () => store.increment(habit.id, _selectedDay),
                    onOpen: () => _openHabit(habit),
                    onEdit: () => _editHabit(habit),
                    onArchive: () => _archiveHabit(store, habit),
                    onDelete: () => _deleteHabit(store, habit),
                  );
                },
              ),
            ),
            if (due.isEmpty)
              const SliverToBoxAdapter(child: _RestDayNotice()),
            if (resting.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                sliver: SliverToBoxAdapter(
                  child: _RestingSection(
                    habits: resting,
                    day: _selectedDay,
                    onOpen: _openHabit,
                    weekStartsOn: settings.weekStartsOn,
                  ),
                ),
              ),
            // Clears the extended FAB and the navigation bar.
            const SliverToBoxAdapter(child: SizedBox(height: 108)),
          ],
        ],
      ),
    );
  }
}

/// A habit as it appears while reordering: no swipe, no toggle, just a handle.
class _ReorderTile extends StatelessWidget {
  const _ReorderTile({
    super.key,
    required this.habit,
    required this.index,
  });

  final Habit habit;
  final int index;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: habit.color.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(habit.icon, color: habit.color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    habit.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    habit.schedule.label,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            ReorderableDragStartListener(
              index: index,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(
                  Icons.drag_handle,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Headline card: how much of the selected day is done.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.day,
    required this.completed,
    required this.total,
  });

  final DateTime day;
  final int completed;
  final int total;

  String get _dayLabel {
    final today = dateOnly(DateTime.now());
    final target = dateOnly(day);
    if (target == today) return 'Today';
    if (target == addDays(today, -1)) return 'Yesterday';
    return DateFormat('EEEE, MMMM d').format(target);
  }

  String get _message {
    if (total == 0) return 'Nothing scheduled — enjoy the day off';
    if (completed == total) return 'All done — nice work';
    if (completed == 0) return '$total to go';
    return '$completed of $total complete';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final progress = total == 0 ? 0.0 : completed / total;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _dayLabel,
                  style: textTheme.titleMedium?.copyWith(
                    color: scheme.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _message,
                  style: textTheme.bodyMedium?.copyWith(
                    color: scheme.onPrimaryContainer.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 56,
            height: 56,
            child: Stack(
              alignment: Alignment.center,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(end: progress),
                  duration: const Duration(milliseconds: 340),
                  curve: Curves.easeOut,
                  builder: (context, value, _) => SizedBox.expand(
                    child: CircularProgressIndicator(
                      value: value,
                      strokeWidth: 5,
                      backgroundColor: scheme.onPrimaryContainer.withValues(
                        alpha: 0.15,
                      ),
                      valueColor: AlwaysStoppedAnimation(
                        scheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ),
                Text(
                  '${(progress * 100).round()}%',
                  style: textTheme.labelSmall?.copyWith(
                    color: scheme.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
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

/// Shown when habits exist but none are scheduled for the selected day.
class _RestDayNotice extends StatelessWidget {
  const _RestDayNotice();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(
          children: [
            Icon(Icons.weekend_outlined, color: scheme.onSurfaceVariant),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                'Rest day. Nothing is scheduled for this date.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Habits that exist but aren't due on the selected day.
///
/// Collapsed by default: they're the answer to "where did my gym habit go?",
/// not part of today's work, and putting them in the main list would inflate
/// the denominator on the progress ring.
class _RestingSection extends StatefulWidget {
  const _RestingSection({
    required this.habits,
    required this.day,
    required this.onOpen,
    required this.weekStartsOn,
  });

  final List<Habit> habits;
  final DateTime day;
  final ValueChanged<Habit> onOpen;
  final int weekStartsOn;

  @override
  State<_RestingSection> createState() => _RestingSectionState();
}

class _RestingSectionState extends State<_RestingSection> {
  var _expanded = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Text(
                  'Not scheduled today (${widget.habits.length})',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
        if (_expanded)
          for (final habit in widget.habits)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: habit.color.withValues(alpha: 0.16),
                child: Icon(habit.icon, size: 20, color: habit.color),
              ),
              title: Text(habit.title),
              subtitle: Text(habit.schedule.label),
              trailing: Text(
                '${habit.completionsInWeekOf(widget.day, weekStartsOn: widget.weekStartsOn)}'
                '/${habit.schedule.weeklyTarget}',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              onTap: () => widget.onOpen(habit),
            ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 64,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text('No habits yet', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Tap “New habit” to start tracking something.',
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
