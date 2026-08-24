import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/habit.dart';
import '../util/haptics.dart';

/// A month of one habit's history, tappable to fix up a missed day.
///
/// Days outside the habit's life or in the future are inert rather than hidden,
/// so the grid keeps its shape and the eye can still count weeks down a column.
///
/// Tap toggles the completion; long-press marks the day as planned time off.
/// Two gestures on one cell is a real cost, but the alternative — a separate
/// "days off" editor — would divorce the decision from the history it is being
/// made against, and the calendar is precisely where a user notices the week
/// they were away.
class MonthCalendar extends StatelessWidget {
  const MonthCalendar({
    super.key,
    required this.habit,
    required this.month,
    required this.onToggleDay,
    required this.onToggleDayOff,
    this.weekStartsOn = DateTime.monday,
  });

  final Habit habit;

  /// Any day inside the month to render.
  final DateTime month;

  final ValueChanged<DateTime> onToggleDay;
  final ValueChanged<DateTime> onToggleDayOff;
  final int weekStartsOn;

  static const _labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final today = dateOnly(DateTime.now());

    final first = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leadingBlanks = (first.weekday - weekStartsOn + 7) % 7;
    final cellCount = leadingBlanks + daysInMonth;
    final rows = (cellCount / 7).ceil();

    final headerOrder = <int>[
      for (var i = 0; i < 7; i++) (weekStartsOn - 1 + i) % 7,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (final index in headerOrder)
              Expanded(
                child: Center(
                  child: Text(
                    _labels[index],
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        for (var row = 0; row < rows; row++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                for (var column = 0; column < 7; column++)
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        final dayNumber = row * 7 + column - leadingBlanks + 1;
                        if (dayNumber < 1 || dayNumber > daysInMonth) {
                          return const SizedBox(height: 40);
                        }
                        final day = DateTime(
                          month.year,
                          month.month,
                          dayNumber,
                        );
                        return _DayCell(
                          habit: habit,
                          day: day,
                          isToday: day == today,
                          isEditable:
                              !day.isAfter(today) &&
                              !day.isBefore(habit.createdAt),
                          onTap: () {
                            Haptics.tick(context);
                            onToggleDay(day);
                          },
                          onLongPress: () {
                            Haptics.impact(context);
                            onToggleDayOff(day);
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.habit,
    required this.day,
    required this.isToday,
    required this.isEditable,
    required this.onTap,
    required this.onLongPress,
  });

  final Habit habit;
  final DateTime day;
  final bool isToday;
  final bool isEditable;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isOff = habit.isSkippedOn(day);
    // The raw schedule, not [Habit.isDueOn]: a day off still needs to be drawn
    // as a day that *would* have been due, or it becomes indistinguishable from
    // a weekend and the user loses track of what they set aside.
    final isDue = habit.schedule.isDueOn(day);
    final progress = habit.progressOn(day);
    final isDone = habit.isCompletedOn(day);
    final isPartial = progress > 0 && !isDone;

    final Color background;
    final Color foreground;
    if (isDone) {
      background = habit.color;
      foreground = Colors.white;
    } else if (isPartial) {
      background = habit.color.withValues(alpha: 0.30);
      foreground = scheme.onSurface;
    } else if (isOff) {
      background = Colors.transparent;
      foreground = scheme.primary;
    } else if (isDue && isEditable) {
      background = scheme.surfaceContainerHighest;
      foreground = scheme.onSurfaceVariant;
    } else {
      background = Colors.transparent;
      foreground = scheme.onSurfaceVariant.withValues(alpha: 0.45);
    }

    final Border? border;
    if (isToday) {
      border = Border.all(color: scheme.onSurface, width: 1.5);
    } else if (isOff) {
      border = Border.all(color: scheme.primary.withValues(alpha: 0.55));
    } else if (isDue && !isDone && !isPartial && isEditable) {
      border = Border.all(color: scheme.outlineVariant);
    } else {
      border = null;
    }

    return Semantics(
      button: isEditable,
      label:
          '${DateFormat.MMMMd().format(day)}, '
          '${isOff
              ? 'day off'
              : isDone
              ? 'done'
              : isDue
              ? 'not done'
              : 'not scheduled'}',
      child: InkResponse(
        onTap: isEditable ? onTap : null,
        onLongPress: isEditable ? onLongPress : null,
        radius: 22,
        child: SizedBox(
          height: 40,
          child: Center(
            child: Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: background,
                shape: BoxShape.circle,
                border: border,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${day.day}',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: foreground,
                      fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                      height: 1,
                    ),
                  ),
                  // A dot rather than an icon: at 34px a glyph next to a
                  // two-digit date is unreadable, and the dot only has to say
                  // "this one is different" — the colour says the rest.
                  if (isOff)
                    Container(
                      margin: const EdgeInsets.only(top: 2),
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
