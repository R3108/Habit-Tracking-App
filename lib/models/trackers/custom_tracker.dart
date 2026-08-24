import 'package:flutter/material.dart';

import '../habit.dart';
import '../habit_icons.dart';
import 'tracker_goals.dart';

/// What a custom tracker measures, which decides how it is entered and shown.
enum CustomTrackerKind {
  /// Whole things: cigarettes not smoked, pages written, glasses of wine.
  count,

  /// Minutes, shown as "1h 30m".
  duration,

  /// An amount with a unit the user names: grams, rupees, kilometres.
  amount,

  /// A 1–5 judgement, like the daily check-in.
  scale,
}

extension CustomTrackerKindInfo on CustomTrackerKind {
  String get label => switch (this) {
    CustomTrackerKind.count => 'Count',
    CustomTrackerKind.duration => 'Duration',
    CustomTrackerKind.amount => 'Amount',
    CustomTrackerKind.scale => 'Rating',
  };

  String get blurb => switch (this) {
    CustomTrackerKind.count => 'Whole things you tally up',
    CustomTrackerKind.duration => 'Minutes, shown as hours',
    CustomTrackerKind.amount => 'A number with your own unit',
    CustomTrackerKind.scale => 'A 1–5 judgement each day',
  };

  /// Whether a bigger number is what the user is aiming at.
  ///
  /// Not a property of the kind — a count can be pages written (more is
  /// better) or cigarettes (fewer is), which is why [CustomTracker.lowerIsBetter]
  /// exists separately.
  bool get supportsQuickAdd => this != CustomTrackerKind.scale;
}

/// A tracker the user defined.
///
/// Six built-in trackers cover the common ground and each earns its bespoke
/// screen by computing something specific — sleep debt, training load. This is
/// the escape hatch for everything else: it stores a number a day against a
/// target and does the honest generic things with it (progress, streak, average,
/// a week of bars) without pretending to domain knowledge it does not have.
@immutable
class CustomTracker {
  const CustomTracker({
    required this.id,
    required this.name,
    required this.kind,
    this.iconKey = 'star',
    this.colorValue = 0xFF6A1B9A,
    this.unit = '',
    this.dailyTarget = 1,
    this.step = 1,
    this.lowerIsBetter = false,
    this.archived = false,
  });

  final String id;
  final String name;
  final CustomTrackerKind kind;

  /// Key into [kHabitIcons] — stored by key for the same tree-shaking reason
  /// habits are.
  final String iconKey;

  final int colorValue;

  /// Free text for [CustomTrackerKind.amount]: "km", "g", "₹".
  final String unit;

  final int dailyTarget;

  /// How much one tap of the quick-add button adds.
  final int step;

  /// True when the target is a ceiling rather than a floor — "under two coffees"
  /// rather than "over ten thousand steps". Flips what counts as a good day
  /// everywhere the tracker is scored.
  final bool lowerIsBetter;

  final bool archived;

  IconData get icon => iconForKey(iconKey);
  Color get color => Color(colorValue);

  /// Renders [value] the way this tracker's kind wants it.
  String format(num value) => switch (kind) {
    CustomTrackerKind.duration => formatMinutes(value.round()),
    CustomTrackerKind.amount when unit.isNotEmpty =>
      '${_trim(value)} ${unit.trim()}',
    CustomTrackerKind.scale => '${_trim(value)}/5',
    _ => _trim(value),
  };

  static String _trim(num value) {
    if (value == value.roundToDouble()) return '${value.round()}';
    return value.toStringAsFixed(1);
  }

  /// Whether [value] hits the target, respecting [lowerIsBetter].
  bool meetsTarget(num value) =>
      lowerIsBetter ? value <= dailyTarget : value >= dailyTarget;

  /// Progress toward the target in 0..1.
  ///
  /// For a ceiling tracker the bar empties as the number climbs, so a full bar
  /// always means "good day" whichever direction the tracker runs.
  double share(num value) {
    if (dailyTarget <= 0) return value > 0 ? 1 : 0;
    if (!lowerIsBetter) return (value / dailyTarget).clamp(0.0, 1.0);
    return (1 - (value / dailyTarget)).clamp(0.0, 1.0);
  }

  CustomTracker copyWith({
    String? name,
    CustomTrackerKind? kind,
    String? iconKey,
    int? colorValue,
    String? unit,
    int? dailyTarget,
    int? step,
    bool? lowerIsBetter,
    bool? archived,
  }) {
    return CustomTracker(
      id: id,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      iconKey: iconKey ?? this.iconKey,
      colorValue: colorValue ?? this.colorValue,
      unit: unit ?? this.unit,
      dailyTarget: dailyTarget ?? this.dailyTarget,
      step: step ?? this.step,
      lowerIsBetter: lowerIsBetter ?? this.lowerIsBetter,
      archived: archived ?? this.archived,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'kind': kind.name,
    'iconKey': iconKey,
    'color': colorValue,
    'unit': unit,
    'dailyTarget': dailyTarget,
    'step': step,
    'lowerIsBetter': lowerIsBetter,
    'archived': archived,
  };

  static CustomTracker? fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String?;
    if (id == null) return null;

    return CustomTracker(
      id: id,
      name: json['name'] as String? ?? 'Tracker',
      kind: CustomTrackerKind.values.firstWhere(
        (k) => k.name == json['kind'],
        orElse: () => CustomTrackerKind.count,
      ),
      // An icon dropped from the catalogue must not cost the user their
      // tracker; iconForKey falls back rather than throwing.
      iconKey: json['iconKey'] as String? ?? 'star',
      colorValue: (json['color'] as num?)?.toInt() ?? 0xFF6A1B9A,
      unit: json['unit'] as String? ?? '',
      dailyTarget: ((json['dailyTarget'] as num?)?.toInt() ?? 1).clamp(0, 100000),
      step: ((json['step'] as num?)?.toInt() ?? 1).clamp(1, 10000),
      lowerIsBetter: json['lowerIsBetter'] as bool? ?? false,
      archived: json['archived'] as bool? ?? false,
    );
  }
}

/// The generic readout for one custom tracker.
@immutable
class CustomTrackerInsights {
  const CustomTrackerInsights._({
    required this.today,
    required this.daysLogged,
    required this.average,
    required this.best,
    required this.streak,
    required this.total,
  });

  final double today;
  final int daysLogged;
  final double average;

  /// The best day in the window — the lowest number for a ceiling tracker.
  final double best;

  /// Consecutive days ending today that met the target.
  final int streak;

  final double total;

  static const int windowDays = 30;

  factory CustomTrackerInsights.from(
    CustomTracker tracker,
    Map<DateTime, double> log, {
    DateTime? reference,
    int window = windowDays,
  }) {
    final today = dateOnly(reference ?? DateTime.now());

    var total = 0.0;
    var days = 0;
    double? best;

    for (var age = 0; age < window; age++) {
      final value = log[addDays(today, -age)];
      // A day with no entry is unknown, not zero. For a ceiling tracker those
      // are opposites, and treating them the same would score every unlogged
      // day as a perfect one.
      if (value == null) continue;

      total += value;
      days++;
      if (best == null ||
          (tracker.lowerIsBetter ? value < best : value > best)) {
        best = value;
      }
    }

    return CustomTrackerInsights._(
      today: log[today] ?? 0,
      daysLogged: days,
      average: days == 0 ? 0 : total / days,
      best: best ?? 0,
      streak: _streak(tracker, log, today),
      total: total,
    );
  }

  static int _streak(
    CustomTracker tracker,
    Map<DateTime, double> log,
    DateTime today,
  ) {
    bool met(DateTime day) {
      final value = log[day];
      if (value == null) return false;
      return tracker.meetsTarget(value);
    }

    var cursor = today;
    if (!met(cursor)) cursor = addDays(cursor, -1);

    var count = 0;
    for (var i = 0; i < 366; i++) {
      if (!met(cursor)) break;
      count++;
      cursor = addDays(cursor, -1);
    }
    return count;
  }
}
