import 'package:flutter/foundation.dart';

import 'habit.dart';

/// A measured link between two habits: how much doing one moves the other.
///
/// For every day both habits were due, the days are split by whether the
/// *trigger* was done, and the follower's completion rate is compared across
/// the two piles. "You read on 82% of the days you run, and on 31% of the days
/// you don't" is a fact about the user's own history, computed on the device,
/// and it is the sort of thing no amount of staring at a heatmap reveals.
///
/// This is correlation and nothing more. Two habits that share a cause — both
/// happen on days off, both collapse when work runs late — will show a strong
/// link with no influence between them at all. Every string this class produces
/// is phrased as an observation for that reason, never as advice.
@immutable
class HabitSynergy {
  const HabitSynergy._({
    required this.triggerId,
    required this.followerId,
    required this.withTrigger,
    required this.withoutTrigger,
    required this.daysWithTrigger,
    required this.daysWithoutTrigger,
  });

  final String triggerId;
  final String followerId;

  /// Follower's completion rate on days the trigger was done, in 0..1.
  final double withTrigger;

  /// Follower's completion rate on days the trigger was missed, in 0..1.
  final double withoutTrigger;

  final int daysWithTrigger;
  final int daysWithoutTrigger;

  /// How far back the pairing looks.
  static const int windowDays = 90;

  /// Both piles need this many days before a split means anything.
  ///
  /// Four days of "didn't run" is one bad week, and a rate built on it swings
  /// by 25 points per day. These floors are what stop the screen confidently
  /// reporting noise in a habit's second week.
  static const int _minimumWithTrigger = 8;
  static const int _minimumWithoutTrigger = 4;

  /// A split smaller than this is not worth a sentence.
  static const double _minimumGap = 0.15;

  /// Percentage-point difference between the two piles. Negative means the
  /// follower does *worse* on trigger days.
  double get gap => withTrigger - withoutTrigger;

  bool get isPositive => gap > 0;

  /// How many times more often the follower lands on trigger days.
  ///
  /// Null when the follower never happens without the trigger: the true ratio
  /// is unbounded, and "∞× more likely" reads as a bug rather than a finding.
  /// Callers fall back to [gap], which stays meaningful.
  double? get lift {
    if (withoutTrigger == 0) return null;
    return withTrigger / withoutTrigger;
  }

  int get withTriggerPercent => (withTrigger * 100).round();
  int get withoutTriggerPercent => (withoutTrigger * 100).round();

  /// Measures the [follower]-given-[trigger] link, or null when the history is
  /// too thin or the split too small to report.
  static HabitSynergy? between(
    Habit trigger,
    Habit follower, {
    DateTime? reference,
    int window = windowDays,
  }) {
    if (trigger.id == follower.id) return null;

    final today = dateOnly(reference ?? DateTime.now());
    var withDone = 0;
    var withTotal = 0;
    var withoutDone = 0;
    var withoutTotal = 0;

    for (var age = 0; age < window; age++) {
      final day = addDays(today, -age);
      // Only days that asked something of *both* habits can compare them. A day
      // the follower was never due on says nothing about the trigger.
      if (!trigger.isDueOn(day) || !follower.isDueOn(day)) continue;

      final followerDone = follower.isCompletedOn(day);
      if (trigger.isCompletedOn(day)) {
        withTotal++;
        if (followerDone) withDone++;
      } else {
        withoutTotal++;
        if (followerDone) withoutDone++;
      }
    }

    if (withTotal < _minimumWithTrigger) return null;
    if (withoutTotal < _minimumWithoutTrigger) return null;

    final synergy = HabitSynergy._(
      triggerId: trigger.id,
      followerId: follower.id,
      withTrigger: withDone / withTotal,
      withoutTrigger: withoutDone / withoutTotal,
      daysWithTrigger: withTotal,
      daysWithoutTrigger: withoutTotal,
    );

    return synergy.gap.abs() < _minimumGap ? null : synergy;
  }
}

/// The strongest links across [habits], most striking first.
///
/// Each unordered pair contributes at most one finding. Both directions are
/// measured — "reading follows running" and "running follows reading" are
/// different claims about the same two habits — but only the larger split is
/// kept, because printing both says the same thing twice and invites the reader
/// to infer a direction the data cannot support.
List<HabitSynergy> findSynergies(
  List<Habit> habits, {
  DateTime? reference,
  int window = HabitSynergy.windowDays,
  int limit = 3,
}) {
  final active = habits.where((h) => !h.archived).toList();
  final best = <String, HabitSynergy>{};

  for (var i = 0; i < active.length; i++) {
    for (var j = 0; j < active.length; j++) {
      if (i == j) continue;

      final synergy = HabitSynergy.between(
        active[i],
        active[j],
        reference: reference,
        window: window,
      );
      if (synergy == null) continue;

      // Keyed on the unordered pair so the two directions compete for one slot.
      final key = i < j ? '$i:$j' : '$j:$i';
      final incumbent = best[key];
      if (incumbent == null || synergy.gap.abs() > incumbent.gap.abs()) {
        best[key] = synergy;
      }
    }
  }

  final found = best.values.toList()
    ..sort((a, b) => b.gap.abs().compareTo(a.gap.abs()));

  return found.take(limit).toList();
}
