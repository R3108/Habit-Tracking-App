import 'package:flutter/material.dart';

import '../models/habit.dart';
import '../util/haptics.dart';

/// One habit row: icon, title, schedule, streak, and a completion control.
///
/// The control is the only thing that toggles; the rest of the card opens the
/// habit's detail screen. Splitting the two means the fast daily action stays a
/// single tap while history is still one tap away, instead of the two competing
/// for the same gesture.
class HabitCard extends StatelessWidget {
  const HabitCard({
    super.key,
    required this.habit,
    required this.day,
    required this.onToggle,
    required this.onIncrement,
    required this.onOpen,
    required this.onEdit,
    required this.onArchive,
    required this.onDelete,
    required this.onDayOff,
    this.anchor,
    this.isCued = false,
  });

  final Habit habit;
  final DateTime day;

  /// The habit this one is stacked behind, already resolved, or null.
  final Habit? anchor;

  /// True when the anchor has been completed on [day] — the cue has fired.
  final bool isCued;

  final VoidCallback onToggle;
  final VoidCallback onIncrement;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onArchive;
  final VoidCallback onDelete;
  final VoidCallback onDayOff;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isDone = habit.isCompletedOn(day);

    // A fired cue is worth pointing at, but only while it is still actionable:
    // once the habit itself is done the highlight has nothing left to prompt.
    final showCue = isCued && !isDone;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Dismissible(
        key: ValueKey('dismiss-${habit.id}'),
        direction: DismissDirection.endToStart,
        onDismissed: (_) => onDelete(),
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 24),
          decoration: BoxDecoration(
            color: scheme.errorContainer,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Icon(Icons.delete_outline, color: scheme.onErrorContainer),
        ),
        child: Material(
          color: isDone
              ? habit.color.withValues(alpha: 0.10)
              : scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            onTap: onOpen,
            onLongPress: () => _showMenu(context),
            borderRadius: BorderRadius.circular(18),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isDone
                      ? habit.color.withValues(alpha: 0.40)
                      : showCue
                      ? habit.color.withValues(alpha: 0.55)
                      : scheme.outlineVariant,
                  width: showCue ? 1.5 : 1,
                ),
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
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
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            // Struck through rather than greyed out, so a
                            // completed habit stays readable.
                            decoration: isDone
                                ? TextDecoration.lineThrough
                                : TextDecoration.none,
                            color: isDone
                                ? scheme.onSurfaceVariant
                                : scheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        if (anchor case final anchor?)
                          _StackHint(
                            anchor: anchor,
                            hasFired: showCue,
                            accent: habit.color,
                          ),
                        _SubtitleRow(habit: habit, day: day),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Keyed so tests (and the framework, across a reorder) can
                  // tell one row's control from the next.
                  if (habit.isCountable)
                    _CountButton(
                      key: ValueKey('toggle-${habit.id}'),
                      habit: habit,
                      day: day,
                      onIncrement: onIncrement,
                      onComplete: onToggle,
                    )
                  else
                    _CheckButton(
                      key: ValueKey('toggle-${habit.id}'),
                      isDone: isDone,
                      color: habit.color,
                      label: habit.title,
                      onTap: onToggle,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showMenu(BuildContext context) async {
    Haptics.tick(context);
    final action = await showModalBottomSheet<String>(
      context: context,
      // Scrollable because the menu is now tall enough to overflow the sheet's
      // default 9/16-of-screen ceiling on a short device, and a bottom sheet
      // that clips its last action is a menu with an unreachable Delete.
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(habit.icon, color: habit.color),
                title: Text(habit.title),
                subtitle: Text(habit.schedule.label),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.insights),
                title: const Text('View history'),
                onTap: () => Navigator.pop(sheetContext, 'open'),
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit habit'),
                onTap: () => Navigator.pop(sheetContext, 'edit'),
              ),
              ListTile(
                leading: const Icon(Icons.beach_access_outlined),
                title: const Text('Take the day off'),
                subtitle: const Text(
                  "Doesn't count as a miss — the streak survives",
                ),
                onTap: () => Navigator.pop(sheetContext, 'dayOff'),
              ),
              ListTile(
                leading: const Icon(Icons.inventory_2_outlined),
                title: const Text('Archive'),
                subtitle: const Text('Hides it but keeps the history'),
                onTap: () => Navigator.pop(sheetContext, 'archive'),
              ),
              ListTile(
                leading: Icon(
                  Icons.delete_outline,
                  color: Theme.of(sheetContext).colorScheme.error,
                ),
                title: Text(
                  'Delete',
                  style: TextStyle(
                    color: Theme.of(sheetContext).colorScheme.error,
                  ),
                ),
                onTap: () => Navigator.pop(sheetContext, 'delete'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );

    switch (action) {
      case 'open':
        onOpen();
      case 'edit':
        onEdit();
      case 'dayOff':
        onDayOff();
      case 'archive':
        onArchive();
      case 'delete':
        onDelete();
    }
  }
}

/// "After Meditate" — the cue this habit is stacked behind.
///
/// Turns from a hint into a prompt once the anchor is done, which is the only
/// moment the stack is telling the user something they don't already know.
class _StackHint extends StatelessWidget {
  const _StackHint({
    required this.anchor,
    required this.hasFired,
    required this.accent,
  });

  final Habit anchor;
  final bool hasFired;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = hasFired ? accent : scheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          Icon(
            hasFired ? Icons.arrow_forward : Icons.link,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              hasFired
                  ? '"${anchor.title}" done — you\'re up'
                  : 'After "${anchor.title}"',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: hasFired ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Streak, schedule and this-week progress, in one line that degrades
/// gracefully on a narrow screen.
class _SubtitleRow extends StatelessWidget {
  const _SubtitleRow({required this.habit, required this.day});

  final Habit habit;
  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: scheme.onSurfaceVariant);
    final streak = habit.streak;
    final weekly = habit.completionsInWeekOf(day);

    return DefaultTextStyle.merge(
      style: style,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      child: Row(
        children: [
          if (streak > 0) ...[
            Icon(Icons.local_fire_department, size: 14, color: habit.color),
            const SizedBox(width: 3),
            Text(
              '$streak',
              style: style?.copyWith(
                color: habit.color,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text('  ·  ', style: style),
          ],
          Flexible(
            child: Text(
              '$weekly/${habit.schedule.weeklyTarget} this week',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Circular checkbox for a yes/no habit.
class _CheckButton extends StatelessWidget {
  const _CheckButton({
    super.key,
    required this.isDone,
    required this.color,
    required this.label,
    required this.onTap,
  });

  final bool isDone;
  final Color color;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Semantics(
      checked: isDone,
      label: label,
      button: true,
      child: InkResponse(
        onTap: () {
          Haptics.impact(context);
          onTap();
        },
        radius: 26,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDone ? color : Colors.transparent,
              border: Border.all(
                color: isDone ? color : scheme.outline,
                width: 2,
              ),
            ),
            child: isDone
                ? const Icon(Icons.check, size: 20, color: Colors.white)
                : null,
          ),
        ),
      ),
    );
  }
}

/// Progress ring for a habit with a daily count target.
///
/// Tapping adds one; long-pressing fills or clears the day, which is the
/// escape hatch for "I did all eight and forgot to log them".
class _CountButton extends StatelessWidget {
  const _CountButton({
    super.key,
    required this.habit,
    required this.day,
    required this.onIncrement,
    required this.onComplete,
  });

  final Habit habit;
  final DateTime day;
  final VoidCallback onIncrement;
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final progress = habit.progressOn(day);
    final target = habit.effectiveTarget;
    final isDone = progress >= target;

    return Semantics(
      value: '$progress of $target',
      button: true,
      label: habit.title,
      child: InkResponse(
        onTap: () {
          Haptics.tick(context);
          onIncrement();
        },
        onLongPress: () {
          Haptics.impact(context);
          onComplete();
        },
        radius: 28,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: SizedBox(
            width: 40,
            height: 40,
            child: Stack(
              alignment: Alignment.center,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(end: progress / target),
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOut,
                  builder: (context, value, _) => SizedBox.expand(
                    child: CircularProgressIndicator(
                      value: value,
                      strokeWidth: 3.5,
                      backgroundColor: scheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation(habit.color),
                    ),
                  ),
                ),
                if (isDone)
                  Icon(Icons.check, size: 18, color: habit.color)
                else
                  Text(
                    '$progress',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
