import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/habit.dart';
import '../models/lab/automaticity.dart';
import '../models/lab/capacity.dart';
import '../models/lab/projection.dart';
import '../models/lab/turning_point.dart';
import '../state/habit_store.dart';
import '../widgets/section_card.dart';
import 'experiments_screen.dart';

/// The slow-question screen: strength, projections, turning points and load.
///
/// Separate from Insights and from Coach on purpose. Insights reports what
/// happened, Coach proposes what to change today, and everything here is about
/// the arc a habit is on over months — which is a different reading pace and
/// does not belong interleaved with either.
///
/// Stateful because the projections are a Monte Carlo simulation. Cheap enough
/// to run on a screen open (a few milliseconds for a normal list), far too
/// wasteful to run on every rebuild, so the whole analysis is computed in
/// [didChangeDependencies] — which fires exactly when the habit store notifies,
/// and therefore refreshes precisely when the underlying history has moved.
class LabScreen extends StatefulWidget {
  const LabScreen({super.key});

  @override
  State<LabScreen> createState() => _LabScreenState();
}

class _LabScreenState extends State<LabScreen> {
  List<Habit> _habits = const <Habit>[];
  List<HabitProjection> _projections = const <HabitProjection>[];
  List<AutomaticityScore> _strengths = const <AutomaticityScore>[];
  List<({Habit habit, TurningPoint point})> _turningPoints = const [];
  CapacityCurve? _capacity;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final habits = HabitScope.of(context).habits;
    _habits = habits;
    if (habits.isEmpty) return;

    _projections = projectHabits(habits);
    _strengths = scoreAutomaticity(habits);
    _turningPoints = findRecentTurningPoints(habits);
    _capacity = CapacityCurve.from(habits);
  }

  Habit? _habitById(String id) {
    for (final habit in _habits) {
      if (habit.id == id) return habit;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_habits.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Lab')),
        body: const _EmptyLab(),
      );
    }

    final capacity = _capacity;
    final graduating = _strengths.where((s) => s.isReadyToGraduate).toList();
    final fragile = _strengths.where((s) => s.isFragile).toList();

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(title: const Text('Lab')),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
            sliver: SliverList.list(
              children: [
                _Banner(
                  icon: Icons.science_outlined,
                  title: 'Experiments',
                  subtitle: 'Test one change, decided in advance',
                  onOpen: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ExperimentsScreen(),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                if (graduating.isNotEmpty || fragile.isNotEmpty) ...[
                  SectionCard(
                    title: 'Worth knowing',
                    subtitle: 'What the strength scores turned up',
                    child: Column(
                      children: [
                        for (final score in graduating)
                          _NoteRow(
                            icon: Icons.workspace_premium_outlined,
                            tone: _NoteTone.good,
                            title: _habitById(score.habitId)?.title ?? 'Habit',
                            body:
                                'Looks self-sustaining after '
                                '${score.daysPractised} days. It may not need '
                                'managing any more.',
                          ),
                        for (final score in fragile)
                          _NoteRow(
                            icon: Icons.link_off,
                            tone: _NoteTone.warning,
                            title: _habitById(score.habitId)?.title ?? 'Habit',
                            body:
                                'Kept ${(score.consistency * 100).round()}% of '
                                'the time, but only '
                                '${(score.resilience * 100).round()}% of the '
                                'days after a miss — one slip tends to become '
                                'a run.',
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                SectionCard(
                  title: 'Habit strength',
                  subtitle: 'How ingrained each one is, not how it went lately',
                  child: Column(
                    children: [
                      for (final score in _strengths)
                        _StrengthRow(
                          habit: _habitById(score.habitId),
                          score: score,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                SectionCard(
                  title: 'Projections',
                  subtitle:
                      'Simulated forward from your own history, '
                      '${HabitProjection.horizonDays} days out',
                  child: Column(
                    children: [
                      for (final projection in _projections)
                        _ProjectionRow(
                          habit: _habitById(projection.habitId),
                          projection: projection,
                        ),
                      const SizedBox(height: 4),
                      const _Caveat(
                        'An extrapolation of what you have done, not a '
                        'prediction of what you will do.',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                SectionCard(
                  title: 'Turning points',
                  subtitle: 'Dates a habit genuinely changed level',
                  child: _turningPoints.isEmpty
                      ? const _Quiet(
                          'Nothing has shifted level in the last few months. '
                          'Most habits never do — that is the usual answer, '
                          'not a missing one.',
                        )
                      : Column(
                          children: [
                            for (final found in _turningPoints)
                              _TurningPointRow(
                                habit: found.habit,
                                point: found.point,
                              ),
                          ],
                        ),
                ),

                if (capacity != null) ...[
                  const SizedBox(height: 16),
                  SectionCard(
                    title: 'Daily load',
                    subtitle: 'What you finish, by how much you take on',
                    child: _CapacityBody(curve: capacity),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One habit's strength, with the component that is holding it back.
class _StrengthRow extends StatelessWidget {
  const _StrengthRow({required this.habit, required this.score});

  final Habit? habit;
  final AutomaticityScore score;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                habit?.icon ?? Icons.check_circle_outline,
                size: 18,
                color: habit?.color ?? scheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  habit?.title ?? 'Habit',
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                score.hasEnoughHistory
                    ? score.strength.label
                    : 'Too new',
                style: textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: score.hasEnoughHistory ? score.score : 0,
              minHeight: 6,
              backgroundColor: scheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(
                habit?.color ?? scheme.primary,
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            score.summary,
            style: textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// One habit's forward outlook.
class _ProjectionRow extends StatelessWidget {
  const _ProjectionRow({required this.habit, required this.projection});

  final Habit? habit;
  final HabitProjection projection;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final lines = <String>[];
    if (projection.currentStreak > 0) {
      lines.add(
        'A ${projection.currentStreak}-day run, with a '
        '${(projection.holdProbability * 100).round()}% chance of surviving '
        'the next ${HabitProjection.holdDays} days.',
      );
    }

    final milestone = projection.nextMilestone;
    if (milestone != null && projection.hasEnoughHistory) {
      final median = milestone.medianDays;
      lines.add(
        median == null
            ? 'A ${milestone.target}-day streak: ${milestone.percent}% likely '
                  'within ${HabitProjection.horizonDays} days.'
            : 'A ${milestone.target}-day streak: ${milestone.percent}% likely, '
                  'typically about $median days away.',
      );
    }

    if (projection.missesCluster) {
      lines.add(
        'Misses cluster — ${(projection.afterKept * 100).round()}% after a kept '
        'day, ${(projection.afterMissed * 100).round()}% after a missed one.',
      );
    }

    if (!projection.hasEnoughHistory) {
      lines
        ..clear()
        ..add('Not enough due days yet to simulate anything useful.');
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                habit?.icon ?? Icons.check_circle_outline,
                size: 18,
                color: habit?.color ?? scheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  habit?.title ?? 'Habit',
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (projection.hasEnoughHistory)
                Text(
                  '${projection.expectedCompletions.round()} expected',
                  style: textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                line,
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TurningPointRow extends StatelessWidget {
  const _TurningPointRow({required this.habit, required this.point});

  final Habit habit;
  final TurningPoint point;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final tone = point.isImprovement ? scheme.primary : scheme.error;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            point.isImprovement ? Icons.trending_up : Icons.trending_down,
            size: 18,
            color: tone,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  habit.title,
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${point.description}, around '
                  '${DateFormat.MMMd().format(point.day)}',
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  'Measured over ${point.beforeDays} due days before and '
                  '${point.afterDays} after.',
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.75),
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

/// The capacity curve as a row of bars, one per observed load.
class _CapacityBody extends StatelessWidget {
  const _CapacityBody({required this.curve});

  final CapacityCurve curve;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (!curve.hasEnoughHistory) {
      return _Quiet(curve.summary);
    }

    var peak = 0.0;
    for (final point in curve.points) {
      if (point.completions > peak) peak = point.completions;
    }
    if (peak <= 0) peak = 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final point in curve.points)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 52,
                  child: Text(
                    '${point.load} due',
                    style: textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: point.load == curve.currentLoad
                          ? FontWeight.w700
                          : FontWeight.w400,
                    ),
                  ),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (point.completions / peak).clamp(0.0, 1.0),
                      minHeight: 12,
                      backgroundColor: scheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        point.load == curve.bestLoad
                            ? scheme.primary
                            : scheme.primary.withValues(alpha: 0.45),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 62,
                  child: Text(
                    '${point.completions.toStringAsFixed(1)} done',
                    style: textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 6),
        Text(
          curve.summary,
          style: textTheme.bodySmall?.copyWith(color: scheme.onSurface),
        ),
        const SizedBox(height: 8),
        const _Caveat(
          'Heavy days differ from light days in more than load, and a count '
          'is not a measure of effort. This shows a pattern, not a cause.',
        ),
      ],
    );
  }
}

enum _NoteTone { good, warning }

class _NoteRow extends StatelessWidget {
  const _NoteRow({
    required this.icon,
    required this.tone,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final _NoteTone tone;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final colour = tone == _NoteTone.good ? scheme.primary : scheme.error;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: colour),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
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

/// A muted line for the cases where the honest answer is "nothing to report".
class _Quiet extends StatelessWidget {
  const _Quiet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
    );
  }
}

/// The small print under an analysis that could otherwise be over-read.
class _Caveat extends StatelessWidget {
  const _Caveat(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.info_outline,
          size: 14,
          color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant.withValues(alpha: 0.85),
              fontSize: 11.5,
            ),
          ),
        ),
      ],
    );
  }
}

/// Tappable header that opens another screen. Mirrors the one on Insights.
class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onOpen,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Material(
      color: scheme.primaryContainer,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, color: scheme.onPrimaryContainer),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: textTheme.bodySmall?.copyWith(
                        color: scheme.onPrimaryContainer.withValues(
                          alpha: 0.85,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: scheme.onPrimaryContainer,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyLab extends StatelessWidget {
  const _EmptyLab();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.science_outlined, size: 48, color: scheme.primary),
            const SizedBox(height: 16),
            Text(
              'Nothing to analyse yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Add a habit and keep it for a few weeks. Everything here is '
              'measured from your own history, so it needs some.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
