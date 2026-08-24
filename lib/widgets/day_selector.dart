import 'package:flutter/material.dart';

import '../models/habit.dart';
import '../util/haptics.dart';

/// Horizontal strip of the last seven days, oldest first.
///
/// A rolling window rather than the calendar week on purpose: the reason to
/// leave today is almost always "I forgot to tick something yesterday", and a
/// Monday-anchored week hides most of that on a Monday.
class DaySelector extends StatelessWidget {
  const DaySelector({
    super.key,
    required this.selectedDay,
    required this.onSelect,
    required this.completedCountFor,
    required this.dueCountFor,
  });

  final DateTime selectedDay;
  final ValueChanged<DateTime> onSelect;

  /// Habits completed on a given day, for the fill indicator.
  final int Function(DateTime day) completedCountFor;

  /// Habits the schedule asked for on a given day.
  final int Function(DateTime day) dueCountFor;

  static const _weekdayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final today = dateOnly(DateTime.now());
    final days = List.generate(7, (i) => addDays(today, -(6 - i)));

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (final day in days)
          _DayCell(
            day: day,
            label: _weekdayLetters[day.weekday - 1],
            isSelected: day == dateOnly(selectedDay),
            isToday: day == today,
            completed: completedCountFor(day),
            due: dueCountFor(day),
            onTap: () {
              Haptics.tick(context);
              onSelect(day);
            },
          ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.label,
    required this.isSelected,
    required this.isToday,
    required this.completed,
    required this.due,
    required this.onTap,
  });

  final DateTime day;
  final String label;
  final bool isSelected;
  final bool isToday;
  final int completed;
  final int due;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final progress = due == 0 ? 0.0 : (completed / due).clamp(0.0, 1.0);
    final allDone = due > 0 && completed >= due;

    return Semantics(
      selected: isSelected,
      button: true,
      label: due == 0
          ? '${day.day}, nothing scheduled'
          : '${day.day}, $completed of $due habits done',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 36,
                    height: 36,
                    child: CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 3,
                      backgroundColor: scheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation(
                        allDone
                            ? scheme.primary
                            : scheme.primary.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                  Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isSelected ? scheme.primary : Colors.transparent,
                    ),
                    child: Text(
                      '${day.day}',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: isSelected
                            ? scheme.onPrimary
                            : scheme.onSurface,
                        fontWeight: isToday
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
