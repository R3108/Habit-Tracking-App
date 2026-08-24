import 'package:flutter/material.dart';

import '../models/habit.dart';
import '../models/momentum.dart';

/// The handful of habits worth a second look today.
///
/// Sits above the checklist rather than inside it, and never offers a tick of
/// its own: the list below is the only place a habit gets completed, so there
/// is exactly one control per habit per day and no chance of the two disagreeing
/// about what has been done.
///
/// Hidden entirely when nothing is flagged — a "needs attention (0)" header is
/// a permanent reminder that the app is watching, which is the opposite of what
/// a good week should feel like.
class FocusCard extends StatelessWidget {
  const FocusCard({
    super.key,
    required this.entries,
    required this.habitFor,
    required this.onOpen,
  });

  final List<HabitMomentum> entries;

  /// Resolves an id to the habit behind it, or null if it has since gone.
  final Habit? Function(String id) habitFor;

  final ValueChanged<Habit> onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final rows = <({HabitMomentum momentum, Habit habit})>[
      for (final entry in entries)
        if (habitFor(entry.habitId) case final habit?)
          (momentum: entry, habit: habit),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();

    final urgent = rows.any((r) => r.momentum.risk == HabitRisk.atRisk);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: urgent
              ? scheme.error.withValues(alpha: 0.45)
              : scheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                urgent ? Icons.priority_high : Icons.visibility_outlined,
                size: 18,
                color: urgent ? scheme.error : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                urgent ? 'Worth doing today' : 'Keep an eye on',
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final row in rows)
            _FocusRow(
              habit: row.habit,
              momentum: row.momentum,
              onTap: () => onOpen(row.habit),
            ),
        ],
      ),
    );
  }
}

class _FocusRow extends StatelessWidget {
  const _FocusRow({
    required this.habit,
    required this.momentum,
    required this.onTap,
  });

  final Habit habit;
  final HabitMomentum momentum;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final reason = momentum.reason;
    final isUrgent = momentum.risk == HabitRisk.atRisk;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Icon(habit.icon, size: 20, color: habit.color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    habit.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (reason != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      reason,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(
                        color: isUrgent ? scheme.error : scheme.onSurfaceVariant,
                        fontWeight: isUrgent ? FontWeight.w600 : null,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            MomentumChip(momentum: momentum),
          ],
        ),
      ),
    );
  }
}

/// Compact momentum readout: a percentage plus which way it is moving.
///
/// Shared by the focus card and the detail screen so one habit never shows two
/// differently-shaped versions of the same number.
class MomentumChip extends StatelessWidget {
  const MomentumChip({super.key, required this.momentum, this.accent});

  final HabitMomentum momentum;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (!momentum.hasEnoughHistory) {
      return Text(
        'New',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      );
    }

    final (icon, color) = switch (momentum.trend) {
      MomentumTrend.rising => (Icons.trending_up, accent ?? scheme.primary),
      MomentumTrend.falling => (Icons.trending_down, scheme.error),
      MomentumTrend.steady => (Icons.trending_flat, scheme.onSurfaceVariant),
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(
          '${momentum.percent}%',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}
