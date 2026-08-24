import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/habit.dart';
import '../util/haptics.dart';

/// A month of one habit's history, tappable to fix up a missed day.
///
/// Days outside the habit's life or in the future are inert rather than hidden,
/// so the grid keeps its shape and the eye can still count weeks down a column.
class MonthCalendar extends StatelessWidget {
  const MonthCalendar({
    super.key,
    required this.habit,
    required this.month,
    required this.onToggleDay,
    this.weekStartsOn = DateTime.monday,
  });

  final Habit habit;

  /// Any day inside the month to render.
  final DateTime month;

  final ValueChanged<DateTime> onToggleDay;
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
  });

  final Habit habit;
  final DateTime day;
  final bool isToday;
  final bool isEditable;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
    } else if (isDue && isEditable) {
      background = scheme.surfaceContainerHighest;
      foreground = scheme.onSurfaceVariant;
    } else {
      background = Colors.transparent;
      foreground = scheme.onSurfaceVariant.withValues(alpha: 0.45);
    }

    return Semantics(
      button: isEditable,
      label: '${DateFormat.MMMMd().format(day)}, '
          '${isDone ? 'done' : isDue ? 'not done' : 'not scheduled'}',
      child: InkResponse(
        onTap: isEditable ? onTap : null,
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
                border: isToday
                    ? Border.all(color: scheme.onSurface, width: 1.5)
                    : (isDue && !isDone && !isPartial && isEditable
                          ? Border.all(color: scheme.outlineVariant)
                          : null),
              ),
              child: Text(
                '${day.day}',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: foreground,
                  fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
