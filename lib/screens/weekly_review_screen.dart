import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/weekly_review.dart';
import '../state/habit_store.dart';
import '../state/settings_store.dart';

/// The written summary of the last seven days.
///
/// A full screen rather than a card on Insights: the review reads as prose, and
/// prose wedged between two charts gets skimmed. Reaching it is a deliberate
/// act, which is also the right frame for the one screen in the app that offers
/// an opinion about how things are going.
class WeeklyReviewScreen extends StatelessWidget {
  const WeeklyReviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = HabitScope.of(context);
    final settings = SettingsScope.of(context).settings;
    final review = WeeklyReview.from(
      store.habits,
      weekStartsOn: settings.weekStartsOn,
    );

    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Weekly review')),
      body: review.isEmpty
          ? const _NothingToReview()
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                _Headline(review: review),
                const SizedBox(height: 20),
                for (final line in review.lines) ...[
                  _LineTile(line: line),
                  const SizedBox(height: 4),
                ],
                if (review.nextMilestone case final milestone?) ...[
                  const SizedBox(height: 16),
                  _NextMilestone(
                    title: milestone.title,
                    description: milestone.description,
                    icon: milestone.icon,
                    value: review.nextMilestoneValue,
                    threshold: milestone.threshold,
                  ),
                ],
                const SizedBox(height: 20),
                Text(
                  'Covers ${DateFormat.MMMd().format(review.from)} to '
                  '${DateFormat.MMMd().format(review.to)} — a rolling seven '
                  'days, so it stays comparable whichever day you open it. '
                  'Everything here is worked out on this device.',
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
    );
  }
}

/// The one number the screen exists to deliver, plus its movement.
class _Headline extends StatelessWidget {
  const _Headline({required this.review});

  final WeeklyReview review;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final delta = review.deltaPoints;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Last seven days',
            style: textTheme.titleMedium?.copyWith(
              color: scheme.onPrimaryContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '${review.percent}%',
                style: textTheme.displaySmall?.copyWith(
                  color: scheme.onPrimaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 10),
              if (delta != null && delta != 0)
                Text(
                  '${delta > 0 ? '+' : ''}$delta pts',
                  style: textTheme.titleMedium?.copyWith(
                    color: scheme.onPrimaryContainer.withValues(alpha: 0.85),
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${review.done} of ${review.due} scheduled things done'
            '${review.perfectDays > 0 ? ' · ${review.perfectDays} clean days' : ''}',
            style: textTheme.bodyMedium?.copyWith(
              color: scheme.onPrimaryContainer.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }
}

class _LineTile extends StatelessWidget {
  const _LineTile({required this.line});

  final ReviewLine line;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final color = switch (line.tone) {
      ReviewTone.good => scheme.primary,
      ReviewTone.warning => scheme.error,
      ReviewTone.neutral => scheme.onSurfaceVariant,
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(line.icon, size: 20, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              line.text,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _NextMilestone extends StatelessWidget {
  const _NextMilestone({
    required this.title,
    required this.description,
    required this.icon,
    required this.value,
    required this.threshold,
  });

  final String title;
  final String description;
  final IconData icon;
  final int value;
  final int threshold;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final progress = threshold == 0 ? 0.0 : (value / threshold).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: scheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Next up: $title',
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '$value/$threshold',
                style: textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _NothingToReview extends StatelessWidget {
  const _NothingToReview();

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
              Icons.auto_stories_outlined,
              size: 64,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'No week to review yet',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Once a few scheduled days have gone by, this turns your history '
              'into something you can actually read.',
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
