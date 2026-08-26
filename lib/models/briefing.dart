import 'package:flutter/material.dart';

import 'blueprint.dart';
import 'daily_signal.dart';
import 'forecast.dart';
import 'goal_coach.dart';
import 'habit.dart';
import 'momentum.dart';
import 'schedule_coach.dart';
import 'trackers/tracker_data.dart';

/// How a briefing line should read — colour and icon follow from this.
enum BriefingTone { good, neutral, warning }

/// One sentence of the briefing.
@immutable
class BriefingItem {
  const BriefingItem({
    required this.icon,
    required this.text,
    this.tone = BriefingTone.neutral,
    this.habitId,
  });

  final IconData icon;
  final String text;
  final BriefingTone tone;

  /// The habit this line is about, when it is about one, so the row can open it.
  final String? habitId;
}

/// Everything the app has to say about today, in one place and in priority
/// order.
///
/// Each engine underneath answers a narrow question well and none of them
/// answers the question a person actually opens the app with, which is *what
/// should I do about today?* Momentum knows which streak is on the line, the
/// forecast knows which habit is likely to get away, the blueprint knows what
/// the good days had in them, and the two coaches know where the plan itself
/// is wrong. Read separately they are four screens of numbers; read together
/// they are a paragraph.
///
/// The ordering rule is what makes it useful: **things that are decided today
/// come first.** A streak that breaks tonight outranks a target that has been
/// mis-set for a month, however wrong the target is. Anything that can wait
/// until the weekend sits at the bottom or does not appear at all.
///
/// Nothing here is generated text in the language-model sense. Every sentence
/// is assembled from numbers computed on the device, which is the only way a
/// briefing can be both offline and true.
@immutable
class DailyBriefing {
  const DailyBriefing._({
    required this.headline,
    required this.subhead,
    required this.items,
    required this.forecast,
    required this.blueprint,
    required this.schedule,
    required this.goals,
  });

  /// The one line worth reading if only one line gets read.
  final String headline;

  final String subhead;

  /// The narrative, already ordered and capped.
  final List<BriefingItem> items;

  final DayForecast forecast;

  /// What the good days looked like, when there is enough history to say.
  final DayBlueprint? blueprint;

  /// Plan changes waiting for a decision, if any.
  final List<ScheduleSuggestion> schedule;
  final List<GoalSuggestion> goals;

  /// Lines above this are a wall of advice rather than a briefing.
  static const int maximumItems = 5;

  bool get hasSuggestions => schedule.isNotEmpty || goals.isNotEmpty;

  factory DailyBriefing.build({
    required List<Habit> habits,
    required TrackerData trackers,
    DateTime? reference,
  }) {
    final today = dateOnly(reference ?? DateTime.now());
    final active = habits.where((h) => !h.archived).toList();
    final byId = <String, Habit>{for (final habit in active) habit.id: habit};

    final forecast = DayForecast.build(active, reference: today);
    final signals = buildSignals(
      habits: active,
      trackers: trackers,
      reference: today,
    );
    final blueprint = DayBlueprint.from(signals);
    final schedule = scheduleSuggestions(active, reference: today);
    final goals = goalSuggestions(trackers, reference: today);

    final items = <BriefingItem>[
      ?_streakLine(active, byId, today),
      ?_forecastLine(forecast, byId),
      ..._blueprintLines(blueprint, today),
      ?_scheduleLine(schedule, byId),
      ?_goalLine(goals),
    ];

    if (items.isEmpty && forecast.due > 0) {
      items.add(
        BriefingItem(
          icon: Icons.check_circle_outline,
          tone: BriefingTone.good,
          text: forecast.done == forecast.due
              ? 'Everything due today is done. Nothing here needs you.'
              : 'Nothing is flagged — the checklist is the whole job today.',
        ),
      );
    }

    return DailyBriefing._(
      headline: _headline(forecast),
      subhead: _subhead(forecast),
      items: List<BriefingItem>.unmodifiable(items.take(maximumItems)),
      forecast: forecast,
      blueprint: blueprint,
      schedule: schedule,
      goals: goals,
    );
  }

  static String _headline(DayForecast forecast) {
    if (forecast.isEmpty) return 'Nothing scheduled today';
    if (forecast.done == forecast.due) return 'All ${forecast.due} done';
    if (!forecast.isReliable) {
      return '${forecast.done} of ${forecast.due} done';
    }
    return 'About ${forecast.expectedRounded} of ${forecast.due} by tonight';
  }

  static String _subhead(DayForecast forecast) {
    if (forecast.isEmpty) {
      return 'A rest day, by the schedule you set.';
    }
    if (forecast.done == forecast.due) {
      return 'Nothing outstanding.';
    }
    if (!forecast.isReliable) {
      return 'A few more weeks of history and the odds below get worth reading.';
    }
    return '${forecast.done} done, ${forecast.due - forecast.done} to go — the '
        'estimate is your own history, not a target.';
  }

  /// A streak that is decided today. Nothing outranks this.
  static BriefingItem? _streakLine(
    List<Habit> habits,
    Map<String, Habit> byId,
    DateTime today,
  ) {
    final focus = focusList(habits, reference: today, limit: 3);
    for (final entry in focus) {
      if (entry.risk != HabitRisk.atRisk) continue;
      final habit = byId[entry.habitId];
      if (habit == null) continue;

      return BriefingItem(
        icon: Icons.local_fire_department,
        tone: BriefingTone.warning,
        habitId: habit.id,
        text: '"${habit.title}" carries a ${entry.streak}-day streak into '
            'tonight, and it is still unticked.',
      );
    }
    return null;
  }

  /// The habit the model expects to be the one that gets away.
  static BriefingItem? _forecastLine(
    DayForecast forecast,
    Map<String, Habit> byId,
  ) {
    final weakest = forecast.weakest;
    if (weakest == null) return null;

    final habit = byId[weakest.habitId];
    if (habit == null) return null;

    final factor = weakest.dominant;
    final because = factor == null || factor.isHelping
        ? ''
        : ' ${factor.label} have run at ${factor.percent}% across '
              '${factor.days} of them.';

    return BriefingItem(
      icon: Icons.trending_down,
      tone: weakest.probability < 0.4
          ? BriefingTone.warning
          : BriefingTone.neutral,
      habitId: habit.id,
      text: 'History puts "${habit.title}" at ${weakest.percent}% today.'
          '$because',
    );
  }

  /// Where today already sits against the profile of a good day.
  ///
  /// Misses first and capped at two: a briefing that lists five things you are
  /// short of is a list of reasons today is already lost, which is the opposite
  /// of the point. One line of credit is allowed when nothing is short.
  static List<BriefingItem> _blueprintLines(
    DayBlueprint? blueprint,
    DateTime today,
  ) {
    if (blueprint == null) return const <BriefingItem>[];

    final misses = <BriefingItem>[];
    final hits = <BriefingItem>[];

    for (final line in blueprint.lines) {
      final value = line.signal.values[today];
      switch (line.meets(value)) {
        case null:
          continue;
        case false:
          misses.add(
            BriefingItem(
              icon: Icons.flag_outlined,
              text: 'Your best days run '
                  '${line.higherIsBetter ? 'above' : 'under'} '
                  '${line.thresholdLabel} of ${line.signal.label.toLowerCase()}'
                  ' — today is on ${line.signal.format(value!)}.',
            ),
          );
        case true:
          hits.add(
            BriefingItem(
              icon: Icons.verified_outlined,
              tone: BriefingTone.good,
              text: '${line.signal.label} is already where your best days sit '
                  '(${line.signal.format(value!)}).',
            ),
          );
      }
    }

    if (misses.isNotEmpty) return misses.take(2).toList();
    return hits.take(1).toList();
  }

  static BriefingItem? _scheduleLine(
    List<ScheduleSuggestion> suggestions,
    Map<String, Habit> byId,
  ) {
    if (suggestions.isEmpty) return null;

    final suggestion = suggestions.first;
    final habit = byId[suggestion.habitId];
    if (habit == null) return null;

    return BriefingItem(
      icon: Icons.edit_calendar_outlined,
      habitId: habit.id,
      text: '"${habit.title}" is being asked for on days it never happens. '
          '${suggestion.headline} — the change is below.',
    );
  }

  static BriefingItem? _goalLine(List<GoalSuggestion> suggestions) {
    if (suggestions.isEmpty) return null;

    final suggestion = suggestions.first;
    return BriefingItem(
      icon: Icons.tune,
      text: suggestion.isEasing
          ? 'Your ${suggestion.label.toLowerCase()} target is met '
                '${suggestion.hitPercent}% of the time. It is asking for more '
                'than the last month gave.'
          : 'Your ${suggestion.label.toLowerCase()} target is met '
                '${suggestion.hitPercent}% of the time — it has stopped '
                'asking for anything.',
    );
  }
}
