import 'package:flutter/material.dart';

import '../models/habit.dart';
import '../models/insights.dart';

/// Contribution-graph view of the last few months.
///
/// Columns are weeks, rows are weekdays. Painted rather than built from widgets
/// because a 20-week grid is 140 cells: as [Container]s that is 140 render
/// objects re-laid-out on every scroll frame, and as one [CustomPaint] it is a
/// few hundred `drawRRect` calls.
class CompletionHeatmap extends StatelessWidget {
  const CompletionHeatmap({
    super.key,
    required this.days,
    required this.accent,
    this.weekStartsOn = DateTime.monday,
    this.onSelect,
  });

  /// Oldest first, ending today.
  final List<DayCompletion> days;
  final Color accent;
  final int weekStartsOn;
  final ValueChanged<DayCompletion>? onSelect;

  static const _rowLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final labelStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant,
      fontSize: 9,
    );

    if (days.isEmpty) return const SizedBox.shrink();

    // Rows are ordered from the configured week start, so a Sunday-first user
    // sees Sunday on top rather than a rotated Monday grid.
    final rowOrder = <int>[
      for (var i = 0; i < 7; i++) ((weekStartsOn - 1 + i) % 7) + 1,
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        const labelWidth = 16.0;
        const gap = 3.0;
        final leadingBlanks =
            (days.first.day.weekday - weekStartsOn + 7) % 7;
        final columns = ((days.length + leadingBlanks) / 7).ceil();
        final cell =
            ((constraints.maxWidth - labelWidth - gap * (columns + 1)) /
                    columns)
                .clamp(8.0, 22.0);
        final height = cell * 7 + gap * 6;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: labelWidth,
              height: height,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final weekday in rowOrder)
                    SizedBox(
                      height: cell,
                      // Every other row only: seven stacked letters at this
                      // size is a smear.
                      child: rowOrder.indexOf(weekday).isEven
                          ? Text(_rowLabels[weekday - 1], style: labelStyle)
                          : null,
                    ),
                ],
              ),
            ),
            Expanded(
              child: GestureDetector(
                onTapUp: onSelect == null
                    ? null
                    : (details) => _handleTap(
                        details.localPosition,
                        cell: cell,
                        gap: gap,
                        leadingBlanks: leadingBlanks,
                      ),
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _HeatmapPainter(
                    days: days,
                    accent: accent,
                    emptyColor: scheme.surfaceContainerHighest,
                    restColor: scheme.surfaceContainerHighest.withValues(
                      alpha: 0.45,
                    ),
                    todayOutline: scheme.onSurface,
                    cell: cell,
                    gap: gap,
                    leadingBlanks: leadingBlanks,
                  ),
                  child: SizedBox(height: height),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _handleTap(
    Offset position, {
    required double cell,
    required double gap,
    required int leadingBlanks,
  }) {
    final column = (position.dx / (cell + gap)).floor();
    final row = (position.dy / (cell + gap)).floor();
    if (column < 0 || row < 0 || row > 6) return;

    final index = column * 7 + row - leadingBlanks;
    if (index < 0 || index >= days.length) return;
    onSelect!(days[index]);
  }
}

class _HeatmapPainter extends CustomPainter {
  _HeatmapPainter({
    required this.days,
    required this.accent,
    required this.emptyColor,
    required this.restColor,
    required this.todayOutline,
    required this.cell,
    required this.gap,
    required this.leadingBlanks,
  });

  final List<DayCompletion> days;
  final Color accent;
  final Color emptyColor;
  final Color restColor;
  final Color todayOutline;
  final double cell;
  final double gap;
  final int leadingBlanks;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final radius = Radius.circular(cell * 0.28);
    final today = dateOnly(DateTime.now());

    for (var i = 0; i < days.length; i++) {
      final slot = i + leadingBlanks;
      final rect = Rect.fromLTWH(
        (slot ~/ 7) * (cell + gap),
        (slot % 7) * (cell + gap),
        cell,
        cell,
      );
      if (rect.left > size.width) break;

      final day = days[i];
      paint.color = _colorFor(day);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, radius), paint);

      if (day.day == today) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect.deflate(0.5), radius),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = todayOutline,
        );
      }
    }
  }

  /// Four steps rather than a continuous ramp: at this cell size a smooth
  /// gradient is indistinguishable, and banding makes "most days" legible.
  Color _colorFor(DayCompletion day) {
    if (!day.hasData) return restColor;
    if (day.done == 0) return emptyColor;
    final ratio = day.ratio;
    if (ratio >= 1) return accent;
    if (ratio >= 0.66) return accent.withValues(alpha: 0.72);
    if (ratio >= 0.33) return accent.withValues(alpha: 0.48);
    return accent.withValues(alpha: 0.26);
  }

  @override
  bool shouldRepaint(_HeatmapPainter old) =>
      old.days != days ||
      old.accent != accent ||
      old.cell != cell ||
      old.leadingBlanks != leadingBlanks;
}

/// "Less → More" key for the heatmap.
class HeatmapLegend extends StatelessWidget {
  const HeatmapLegend({super.key, required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text('Less', style: style),
        const SizedBox(width: 6),
        for (final alpha in const [0.0, 0.26, 0.48, 0.72, 1.0])
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Container(
              width: 11,
              height: 11,
              decoration: BoxDecoration(
                color: alpha == 0
                    ? scheme.surfaceContainerHighest
                    : accent.withValues(alpha: alpha),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        const SizedBox(width: 6),
        Text('More', style: style),
      ],
    );
  }
}
