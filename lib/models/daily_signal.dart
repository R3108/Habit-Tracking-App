import 'package:flutter/foundation.dart';

import 'habit.dart';
import 'insights.dart';
import 'trackers/custom_tracker.dart';
import 'trackers/tracker_data.dart';
import 'trackers/tracker_goals.dart';

/// How a signal's numbers should be written out.
enum SignalUnit { minutes, millilitres, count, score, percent, pages }

/// One number a day, from anywhere in the app.
///
/// The app records six built-in trackers, any number of custom ones, a daily
/// check-in and a habit list, each in its own shape. Nothing could be compared
/// with anything else until they shared a form. This is that form: a label, a
/// unit, and a sparse day → value map.
///
/// Sparse on purpose. A day with no entry is *unknown*, not zero, and the
/// difference matters enormously — treating an unlogged Sunday as "drank 0ml"
/// would invent a bad day that never happened and drag every comparison drawn
/// from it.
@immutable
class DailySignal {
  const DailySignal({
    required this.id,
    required this.label,
    required this.unit,
    required this.values,
    this.isOutcome = false,
  });

  final String id;
  final String label;
  final SignalUnit unit;

  /// Date-only → value, holding only the days that were actually recorded.
  final Map<DateTime, double> values;

  /// True for the things a person wants to move rather than to do: how the day
  /// felt, how much of the plan survived. Used to prefer the more useful
  /// direction when a pair could be read either way.
  final bool isOutcome;

  int get days => values.length;

  String format(double value) => switch (unit) {
    SignalUnit.minutes => formatMinutes(value.round()),
    SignalUnit.millilitres => '${value.round()} ml',
    SignalUnit.count => _trim(value),
    SignalUnit.score => '${_trim(value)}/5',
    SignalUnit.percent => '${value.round()}%',
    SignalUnit.pages => '${value.round()} pages',
  };

  static String _trim(double value) {
    if (value == value.roundToDouble()) return '${value.round()}';
    return value.toStringAsFixed(1);
  }
}

/// Every signal the app can currently offer, over the last [window] days.
///
/// A signal with fewer than a handful of days is left out rather than included
/// and then rejected downstream, because an empty tracker should not appear in
/// a list of things the user could correlate.
List<DailySignal> buildSignals({
  required List<Habit> habits,
  required TrackerData trackers,
  DateTime? reference,
  int window = 90,
  int minimumDays = 8,
}) {
  final today = dateOnly(reference ?? DateTime.now());
  final signals = <DailySignal>[];

  void add(
    String id,
    String label,
    SignalUnit unit,
    Map<DateTime, double> values, {
    bool isOutcome = false,
  }) {
    if (values.length < minimumDays) return;
    signals.add(
      DailySignal(
        id: id,
        label: label,
        unit: unit,
        values: values,
        isOutcome: isOutcome,
      ),
    );
  }

  bool inWindow(DateTime day) =>
      !day.isAfter(today) && !day.isBefore(addDays(today, -(window - 1)));

  // --- habits ------------------------------------------------------------
  // Reuses the day-by-day walk the insights screen already does, so "how much
  // of the plan survived" means exactly the same thing here as it does there.
  final active = habits.where((h) => !h.archived).toList();
  if (active.isNotEmpty) {
    final overall = OverallInsights.from(active, window: window);
    add(
      'habits',
      'Habits kept',
      SignalUnit.percent,
      <DateTime, double>{
        for (final day in overall.days)
          if (day.hasData) day.day: day.ratio * 100,
      },
      isOutcome: true,
    );
  }

  // --- check-in ----------------------------------------------------------
  add(
    'mood',
    'Mood',
    SignalUnit.score,
    <DateTime, double>{
      for (final entry in trackers.checkIns.entries)
        if (inWindow(entry.key)) entry.key: entry.value.mood.toDouble(),
    },
    isOutcome: true,
  );
  add(
    'energy',
    'Energy',
    SignalUnit.score,
    <DateTime, double>{
      for (final entry in trackers.checkIns.entries)
        if (inWindow(entry.key)) entry.key: entry.value.energy.toDouble(),
    },
    isOutcome: true,
  );

  // --- sleep -------------------------------------------------------------
  add('sleep', 'Sleep', SignalUnit.minutes, <DateTime, double>{
    for (final entry in trackers.sleep.entries)
      if (inWindow(entry.key)) entry.key: entry.value.durationMinutes.toDouble(),
  });
  add('sleepQuality', 'Sleep quality', SignalUnit.score, <DateTime, double>{
    for (final entry in trackers.sleep.entries)
      if (inWindow(entry.key)) entry.key: entry.value.quality.toDouble(),
  });

  // --- water -------------------------------------------------------------
  add('water', 'Water', SignalUnit.millilitres, <DateTime, double>{
    for (final entry in trackers.water.entries)
      if (inWindow(entry.key)) entry.key: entry.value.toDouble(),
  });

  // --- reading, focus, fitness ------------------------------------------
  // Session lists rather than day maps, so they are summed per day first.
  add(
    'reading',
    'Reading',
    SignalUnit.minutes,
    _sumByDay(
      trackers.reading.where((s) => inWindow(s.day)),
      (s) => s.day,
      (s) => s.minutes.toDouble(),
    ),
  );
  add(
    'focus',
    'Focus',
    SignalUnit.minutes,
    _sumByDay(
      trackers.focus.where((s) => inWindow(s.day)),
      (s) => s.day,
      (s) => s.minutes.toDouble(),
    ),
  );
  add(
    'fitness',
    'Exercise',
    SignalUnit.minutes,
    _sumByDay(
      trackers.workouts.where((w) => inWindow(w.day)),
      (w) => w.day,
      (w) => w.minutes.toDouble(),
    ),
  );

  // --- food --------------------------------------------------------------
  add('eatingWindow', 'Eating window', SignalUnit.minutes, <DateTime, double>{
    for (final entry in trackers.food.entries)
      if (inWindow(entry.key))
        if (entry.value.eatingWindowMinutes case final span?)
          entry.key: span.toDouble(),
  });

  // --- custom trackers ---------------------------------------------------
  for (final tracker in trackers.customTrackers) {
    if (tracker.archived) continue;
    final log = trackers.customEntries[tracker.id];
    if (log == null) continue;

    add(
      'custom:${tracker.id}',
      tracker.name,
      switch (tracker.kind) {
        CustomTrackerKind.duration => SignalUnit.minutes,
        CustomTrackerKind.scale => SignalUnit.score,
        _ => SignalUnit.count,
      },
      <DateTime, double>{
        for (final entry in log.entries)
          if (inWindow(entry.key)) entry.key: entry.value,
      },
    );
  }

  return signals;
}

Map<DateTime, double> _sumByDay<T>(
  Iterable<T> items,
  DateTime Function(T item) dayOf,
  double Function(T item) valueOf,
) {
  final out = <DateTime, double>{};
  for (final item in items) {
    final day = dateOnly(dayOf(item));
    out[day] = (out[day] ?? 0) + valueOf(item);
  }
  return out;
}
