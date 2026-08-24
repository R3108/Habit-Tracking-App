import 'package:flutter/material.dart';

/// Completion rate by weekday.
///
/// The useful question this answers is "which day do I keep dropping?", so bars
/// are drawn against a full-height track: a 40% Wednesday has to *look* like a
/// hole next to a 90% Monday, which a bare bar on white doesn't.
class WeekdayChart extends StatelessWidget {
  const WeekdayChart({
    super.key,
    required this.rates,
    required this.accent,
    this.weekStartsOn = DateTime.monday,
  });

  /// Seven values in 0..1, indexed 0 = Monday … 6 = Sunday.
  final List<double> rates;
  final Color accent;
  final int weekStartsOn;

  static const _labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final order = <int>[
      for (var i = 0; i < 7; i++) (weekStartsOn - 1 + i) % 7,
    ];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final index in order)
          Expanded(
            child: Semantics(
              label:
                  '${_labels[index]}, ${(rates[index] * 100).round()} percent',
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${(rates[index] * 100).round()}',
                    style: textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 96,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: SizedBox(
                            width: double.infinity,
                            height: 96,
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: TweenAnimationBuilder<double>(
                                tween: Tween(
                                  end: rates[index].clamp(0.0, 1.0),
                                ),
                                duration: const Duration(milliseconds: 420),
                                curve: Curves.easeOutCubic,
                                builder: (context, value, _) => Container(
                                  height: (96 * value).clamp(3.0, 96.0),
                                  decoration: BoxDecoration(
                                    color: accent,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _labels[index],
                    style: textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
