import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/habit.dart';
import '../../models/trackers/focus_entry.dart';
import '../../models/trackers/tracker_goals.dart';
import '../../models/trackers/tracker_kind.dart';
import '../../state/tracker_store.dart';
import '../../util/haptics.dart';
import '../../widgets/trackers/tracker_widgets.dart';

/// Focus: a pomodoro timer and the log of work it produces.
///
/// The ticking is a one-second [Timer] that only exists while this screen is
/// mounted. Nothing about the countdown is stored in it — the truth is the
/// start time held by [TrackerStore], and this widget merely asks the clock
/// what that means every second. Leaving the screen and coming back therefore
/// shows the right number, and so does killing the app.
class FocusScreen extends StatefulWidget {
  const FocusScreen({super.key});

  static const kind = TrackerKind.focus;

  @override
  State<FocusScreen> createState() => _FocusScreenState();
}

class _FocusScreenState extends State<FocusScreen> {
  Timer? _ticker;
  String _tag = '';

  /// Set once a finished phase has been banked, so the same completion is not
  /// recorded twice by two rebuilds arriving in the same second.
  bool _banking = false;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = TrackerScope.of(context);
    final goals = store.goals;
    final today = dateOnly(DateTime.now());
    final insights = FocusInsights.from(store.data.focus);
    final timer = store.runningTimer;

    final week = <({DateTime day, num value})>[
      for (var age = 6; age >= 0; age--)
        (
          day: addDays(today, -age),
          value: store.data.focus
              .where((s) => s.day == addDays(today, -age))
              .fold<int>(0, (sum, s) => sum + s.minutes),
        ),
    ];

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(title: Text(FocusScreen.kind.label)),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            sliver: SliverList.list(
              children: [
                _TimerPanel(
                  timer: timer,
                  goals: goals,
                  tag: _tag,
                  onTagChanged: (value) => _tag = value,
                  onStart: (phase, minutes) => store.startTimer(
                    phase: phase,
                    minutes: minutes,
                    tag: _tag,
                    completedFocusBlocks:
                        timer?.completedFocusBlocks ?? insights.sessionsToday,
                  ),
                  onCancel: () {
                    Haptics.tick(context);
                    store.cancelTimer();
                  },
                  onComplete: () => _bank(store, goals),
                ),
                const SizedBox(height: 20),
                TrackerCard(
                  title: 'Today',
                  child: Column(
                    children: [
                      TrackerStatRow(
                        icon: Icons.timer_outlined,
                        label: 'Sessions',
                        value: '${insights.sessionsToday}'
                            ' of ${goals.focusSessionsPerDay}',
                        emphasis:
                            insights.sessionsToday >= goals.focusSessionsPerDay
                            ? FocusScreen.kind.color
                            : null,
                      ),
                      TrackerStatRow(
                        icon: Icons.schedule,
                        label: 'Focused time',
                        value: formatMinutes(insights.minutesToday),
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: insights.goalShare(goals),
                          minHeight: 6,
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                          valueColor: AlwaysStoppedAnimation(
                            FocusScreen.kind.color,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TrackerCard(
                  title: 'Last 7 days',
                  child: MiniBars(
                    values: week,
                    goal: goals.focusSessionsPerDay * goals.focusMinutes,
                    accent: FocusScreen.kind.color,
                  ),
                ),
                const SizedBox(height: 16),
                if (insights.byTag.isNotEmpty) ...[
                  TrackerCard(
                    title: 'Where the time went',
                    child: Column(
                      children: [
                        for (final entry in insights.byTag.take(6))
                          TrackerStatRow(
                            icon: Icons.label_outline,
                            label: entry.tag,
                            value: formatMinutes(entry.minutes),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                TrackerCard(
                  title: 'Last 30 days',
                  child: Column(
                    children: [
                      TrackerStatRow(
                        icon: Icons.calendar_today_outlined,
                        label: 'Days with focus',
                        value: '${insights.daysWorked}',
                      ),
                      TrackerStatRow(
                        icon: Icons.show_chart,
                        label: 'Average working day',
                        value: formatMinutes(insights.dailyAverageMinutes),
                      ),
                      TrackerStatRow(
                        icon: Icons.emoji_events_outlined,
                        label: 'Best day',
                        value: formatMinutes(insights.bestDayMinutes),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Banks the finished phase and queues whatever comes next in the cycle.
  void _bank(TrackerStore store, TrackerGoals goals) {
    if (_banking) return;
    _banking = true;

    final timer = store.runningTimer;
    if (timer == null) {
      _banking = false;
      return;
    }

    final wasWork = timer.phase.isWork;
    store.completeTimer();

    if (mounted) {
      Haptics.impact(context);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 2),
            content: Text(
              wasWork
                  ? '${timer.totalMinutes} minutes banked'
                  : 'Break over — back to it',
            ),
          ),
        );
    }
    _banking = false;
  }
}

/// The countdown, and the controls around it.
class _TimerPanel extends StatelessWidget {
  const _TimerPanel({
    required this.timer,
    required this.goals,
    required this.tag,
    required this.onTagChanged,
    required this.onStart,
    required this.onCancel,
    required this.onComplete,
  });

  final RunningTimer? timer;
  final TrackerGoals goals;
  final String tag;
  final ValueChanged<String> onTagChanged;
  final void Function(FocusPhase phase, int minutes) onStart;
  final VoidCallback onCancel;
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final timer = this.timer;
    final now = DateTime.now();

    if (timer == null) {
      return TrackerCard(
        child: Column(
          children: [
            Center(
              child: GoalRing(
                progress: 0,
                value: '${goals.focusMinutes}',
                caption: 'minutes',
                accent: FocusScreen.kind.color,
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              onChanged: onTagChanged,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Working on (optional)',
                hintText: 'Calculus, thesis, Spanish',
                prefixIcon: Icon(Icons.label_outline),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: FocusScreen.kind.color,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: const Icon(Icons.play_arrow),
                label: Text('Start ${goals.focusMinutes} minutes'),
                onPressed: () =>
                    onStart(FocusPhase.focus, goals.focusMinutes),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'The countdown runs while this screen is open, and is worked out '
              'from the start time — so closing the app and coming back still '
              'shows the right number. It cannot buzz in the background: that '
              'needs a permission this app deliberately does not ask for.',
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    final remaining = timer.remainingAt(now);
    final finished = timer.isFinishedAt(now);
    final minutes = remaining.inMinutes.toString().padLeft(2, '0');
    final seconds = (remaining.inSeconds % 60).toString().padLeft(2, '0');

    return TrackerCard(
      child: Column(
        children: [
          Text(
            timer.phase.label + (timer.tag.isEmpty ? '' : ' · ${timer.tag}'),
            style: textTheme.labelLarge?.copyWith(
              color: FocusScreen.kind.color,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: GoalRing(
              progress: timer.progressAt(now),
              value: finished ? 'Done' : '$minutes:$seconds',
              caption: finished
                  ? 'tap to bank it'
                  : 'of ${timer.totalMinutes} min',
              accent: timer.phase.isWork
                  ? FocusScreen.kind.color
                  : scheme.tertiary,
              size: 168,
            ),
          ),
          const SizedBox(height: 20),
          if (finished)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: FocusScreen.kind.color,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: const Icon(Icons.check),
                label: Text(
                  timer.phase.isWork ? 'Bank this session' : 'Finish break',
                ),
                onPressed: onComplete,
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.stop),
                    label: const Text('Give up'),
                    onPressed: onCancel,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: FocusScreen.kind.color,
                    ),
                    icon: const Icon(Icons.done_all),
                    label: const Text('Finish now'),
                    onPressed: onComplete,
                  ),
                ),
              ],
            ),
          if (finished && timer.phase.isWork) ...[
            const SizedBox(height: 10),
            Text(
              _nextBreakHint(timer, goals),
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  /// Which break the cycle owes after this block.
  static String _nextBreakHint(RunningTimer timer, TrackerGoals goals) {
    final blocks = timer.completedFocusBlocks + 1;
    final isLong = blocks % goals.sessionsBeforeLongBreak == 0;
    final minutes = isLong ? goals.longBreakMinutes : goals.breakMinutes;
    return isLong
        ? 'That is $blocks in a row — take the long $minutes-minute break.'
        : 'Take $minutes minutes before the next one.';
  }
}
