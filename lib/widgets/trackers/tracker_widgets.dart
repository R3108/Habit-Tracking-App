import 'package:flutter/material.dart';

import '../../models/habit.dart';

/// A progress ring with a headline value inside it.
///
/// Used as the top-of-screen readout on the trackers that have a daily target.
/// The ring is capped at 100% while the number is not: going past a water goal
/// is worth seeing, but a ring that wraps around twice is unreadable.
class GoalRing extends StatelessWidget {
  const GoalRing({
    super.key,
    required this.progress,
    required this.value,
    required this.caption,
    required this.accent,
    this.size = 148,
    this.footnote,
  });

  final double progress;
  final String value;
  final String caption;
  final String? footnote;
  final Color accent;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(end: progress.clamp(0.0, 1.0)),
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeOut,
            builder: (context, animated, _) => SizedBox.expand(
              child: CircularProgressIndicator(
                value: animated,
                strokeWidth: 10,
                strokeCap: StrokeCap.round,
                backgroundColor: accent.withValues(alpha: 0.16),
                valueColor: AlwaysStoppedAnimation(accent),
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  value,
                  maxLines: 1,
                  style: textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                caption,
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              if (footnote != null) ...[
                const SizedBox(height: 2),
                Text(
                  footnote!,
                  style: textTheme.labelSmall?.copyWith(color: accent),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// A short run of daily bars, newest on the right.
///
/// Deliberately unlabelled apart from the weekday initials: at this size a
/// value axis would cost more room than it explains, and the goal line does the
/// job of telling the eye what "enough" looks like.
class MiniBars extends StatelessWidget {
  const MiniBars({
    super.key,
    required this.values,
    required this.accent,
    this.goal,
    this.height = 96,
  });

  /// Oldest first, ending today. Zero means "nothing logged".
  final List<({DateTime day, num value})> values;

  /// Drawn as a dashed reference line when given.
  final num? goal;

  final Color accent;
  final double height;

  static const _initials = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (values.isEmpty) return const SizedBox.shrink();

    final today = dateOnly(DateTime.now());
    final peak = values
        .map((v) => v.value)
        .fold<num>(goal ?? 0, (max, v) => v > max ? v : max);
    // A flat run of zeroes would divide by zero; one is as good a scale as any
    // for a chart with nothing in it.
    final scale = peak <= 0 ? 1 : peak;

    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final entry in values)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          heightFactor: (entry.value / scale).clamp(0.0, 1.0),
                          child: Container(
                            decoration: BoxDecoration(
                              color: entry.value <= 0
                                  ? scheme.surfaceContainerHighest
                                  : (goal != null && entry.value >= goal!)
                                  ? accent
                                  : accent.withValues(alpha: 0.45),
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(4),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _initials[entry.day.weekday - 1],
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: entry.day == today
                            ? accent
                            : scheme.onSurfaceVariant,
                        fontWeight: entry.day == today
                            ? FontWeight.w700
                            : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Bordered block used for every section on a tracker screen.
class TrackerCard extends StatelessWidget {
  const TrackerCard({super.key, required this.child, this.title, this.trailing});

  final String? title;
  final Widget? trailing;
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    title!,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 14),
          ],
          child,
        ],
      ),
    );
  }
}

/// A label and a value on one line, for the readouts under a chart.
class TrackerStatRow extends StatelessWidget {
  const TrackerStatRow({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.emphasis,
  });

  final String label;
  final String value;
  final IconData? icon;

  /// Colours the value when it is worth drawing the eye to.
  final Color? emphasis;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: scheme.onSurfaceVariant),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(
              label,
              style: textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            value,
            style: textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: emphasis,
            ),
          ),
        ],
      ),
    );
  }
}

/// The "nothing here yet" block shared by the tracker screens.
class TrackerEmptyState extends StatelessWidget {
  const TrackerEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 8),
      child: Column(
        children: [
          Icon(icon, size: 48, color: scheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
