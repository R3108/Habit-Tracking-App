import 'package:flutter/material.dart';

import 'habit_icons.dart';

/// Strips the time component so a day can be used as a map/set key.
///
/// Every date that reaches [Habit.entries] goes through here, which also keeps
/// arithmetic safe across daylight-saving boundaries where subtracting 24 hours
/// can land on 23:00 the previous day.
DateTime dateOnly(DateTime day) => DateTime(day.year, day.month, day.day);

/// Formats [day] as `YYYY-MM-DD`, the on-disk form of a date.
///
/// Shared with the trackers so every stored day in the app parses the same way,
/// and so a hand-edited backup reads as dates rather than epoch integers.
String encodeDay(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

/// Reads a day written by [encodeDay], or null if it is unreadable.
DateTime? decodeDay(String? raw) {
  if (raw == null) return null;
  final parsed = DateTime.tryParse(raw);
  return parsed == null ? null : dateOnly(parsed);
}

/// Moves [day] by whole calendar days.
///
/// Prefer this over `add(Duration(days: n))`: on the morning the clocks go
/// forward, midnight plus 24 hours is 23:00 *the same day*, which turns a
/// day-walking loop into an infinite one. Overflowing the day field instead
/// lets [DateTime] normalise the result.
DateTime addDays(DateTime day, int days) =>
    DateTime(day.year, day.month, day.day + days);

/// How often a habit is expected to be done.
enum HabitFrequency {
  /// Every day.
  daily,

  /// Only on chosen weekdays — "gym on Mon/Wed/Fri".
  specificDays,

  /// A weekly quota the user can spend on any days — "run 3× a week".
  timesPerWeek,
}

/// When a habit counts as due, and how much of it a full week asks for.
@immutable
class HabitSchedule {
  const HabitSchedule({
    this.frequency = HabitFrequency.daily,
    this.weekdays = everyDay,
    this.timesPerWeek = 3,
  });

  const HabitSchedule.daily() : this();

  const HabitSchedule.onDays(Set<int> days)
    : this(frequency: HabitFrequency.specificDays, weekdays: days);

  const HabitSchedule.timesAWeek(int times)
    : this(frequency: HabitFrequency.timesPerWeek, timesPerWeek: times);

  /// ISO weekday numbers: 1 = Monday … 7 = Sunday, matching [DateTime.weekday].
  static const Set<int> everyDay = <int>{1, 2, 3, 4, 5, 6, 7};

  final HabitFrequency frequency;
  final Set<int> weekdays;
  final int timesPerWeek;

  /// Whether the habit is expected on [day].
  ///
  /// A [HabitFrequency.timesPerWeek] habit is due every day: the user picks
  /// which days to spend the quota on, so no single day can be a miss.
  bool isDueOn(DateTime day) => switch (frequency) {
    HabitFrequency.daily => true,
    HabitFrequency.specificDays => weekdays.contains(day.weekday),
    HabitFrequency.timesPerWeek => true,
  };

  /// How many completions a full week of this schedule asks for.
  int get weeklyTarget => switch (frequency) {
    HabitFrequency.daily => 7,
    HabitFrequency.specificDays => weekdays.length,
    HabitFrequency.timesPerWeek => timesPerWeek.clamp(1, 7),
  };

  static const _shortNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  /// Human-readable summary for cards and detail headers.
  String get label => switch (frequency) {
    HabitFrequency.daily => 'Every day',
    HabitFrequency.timesPerWeek => '$timesPerWeek× a week',
    HabitFrequency.specificDays when weekdays.length == 7 => 'Every day',
    HabitFrequency.specificDays when weekdays.isEmpty => 'No days selected',
    HabitFrequency.specificDays when _isWeekdaysOnly => 'Weekdays',
    HabitFrequency.specificDays when _isWeekendOnly => 'Weekends',
    HabitFrequency.specificDays =>
      (weekdays.toList()..sort()).map((d) => _shortNames[d - 1]).join(', '),
  };

  bool get _isWeekdaysOnly =>
      weekdays.length == 5 && !weekdays.contains(6) && !weekdays.contains(7);

  bool get _isWeekendOnly =>
      weekdays.length == 2 && weekdays.contains(6) && weekdays.contains(7);

  HabitSchedule copyWith({
    HabitFrequency? frequency,
    Set<int>? weekdays,
    int? timesPerWeek,
  }) {
    return HabitSchedule(
      frequency: frequency ?? this.frequency,
      weekdays: weekdays ?? this.weekdays,
      timesPerWeek: timesPerWeek ?? this.timesPerWeek,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'frequency': frequency.name,
    'weekdays': (weekdays.toList()..sort()),
    'timesPerWeek': timesPerWeek,
  };

  factory HabitSchedule.fromJson(Map<String, dynamic> json) {
    final rawDays = (json['weekdays'] as List<dynamic>?) ?? const <dynamic>[];
    final days = rawDays
        .map((d) => (d as num).toInt())
        .where((d) => d >= 1 && d <= 7)
        .toSet();

    return HabitSchedule(
      frequency: HabitFrequency.values.firstWhere(
        (f) => f.name == json['frequency'],
        orElse: () => HabitFrequency.daily,
      ),
      weekdays: days.isEmpty ? everyDay : days,
      timesPerWeek: ((json['timesPerWeek'] as num?)?.toInt() ?? 3).clamp(1, 7),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is HabitSchedule &&
      other.frequency == frequency &&
      other.timesPerWeek == timesPerWeek &&
      other.weekdays.length == weekdays.length &&
      other.weekdays.containsAll(weekdays);

  @override
  int get hashCode => Object.hash(
    frequency,
    timesPerWeek,
    Object.hashAllUnordered(weekdays),
  );
}

/// A single tracked habit plus its completion history.
///
/// History is a date-only → count map rather than a set of days, so a habit can
/// carry a per-day target ("drink water 8×") and still answer the simple
/// "was this done?" question through [isCompletedOn].
@immutable
class Habit {
  Habit({
    required this.id,
    required this.title,
    required this.icon,
    required this.color,
    Set<DateTime> completedDays = const {},
    Map<DateTime, int> entries = const {},
    this.targetPerDay = 1,
    this.schedule = const HabitSchedule.daily(),
    this.reminder,
    this.note = '',
    this.archived = false,
    this.anchorId,
    Set<DateTime> skippedDays = const {},
    DateTime? createdAt,
  }) : entries = _normalise(entries, completedDays, targetPerDay),
       skippedDays = _normaliseSkips(skippedDays, entries, completedDays),
       createdAt = dateOnly(
         createdAt ?? _earliestOf(entries, completedDays) ?? DateTime.now(),
       );

  final String id;
  final String title;
  final IconData icon;
  final Color color;

  /// Date-only day → how many times the habit was logged that day.
  ///
  /// Only positive counts are stored; clearing a day removes its key.
  final Map<DateTime, int> entries;

  /// How many logs a single day needs before it counts as complete.
  final int targetPerDay;

  final HabitSchedule schedule;

  /// Local time of the daily reminder, or null for no reminder.
  final TimeOfDay? reminder;

  final String note;
  final bool archived;

  /// The habit this one is stacked behind, or null when it stands alone.
  ///
  /// "After I meditate, I read" — the anchor is the cue. Stored as an id rather
  /// than a reference because habits are immutable snapshots: holding the object
  /// would pin a stale copy of the anchor's history inside this one.
  ///
  /// The id may dangle. A habit deleted from under its followers leaves them
  /// pointing at nothing, and every reader treats an unresolvable anchor as "no
  /// anchor" rather than as an error — losing the cue must never cost the habit.
  final String? anchorId;

  /// Days deliberately taken off: illness, holiday, a rest week.
  ///
  /// A skipped day is not due, so it neither breaks a streak nor counts against
  /// a completion rate — it is stepped over exactly like a day the schedule
  /// never asked for. That is the whole point: without it, the only way to
  /// protect a 40-day streak through a week's flu is to lie and tick the boxes,
  /// which corrupts the history the app exists to keep honest.
  final Set<DateTime> skippedDays;

  final DateTime createdAt;

  static Map<DateTime, int> _normalise(
    Map<DateTime, int> entries,
    Set<DateTime> completedDays,
    int targetPerDay,
  ) {
    final target = targetPerDay < 1 ? 1 : targetPerDay;
    final out = <DateTime, int>{};
    for (final entry in entries.entries) {
      if (entry.value > 0) out[dateOnly(entry.key)] = entry.value;
    }
    // Explicit completions win: they mean "done", whatever the count says.
    for (final day in completedDays) {
      out[dateOnly(day)] = target;
    }
    return Map<DateTime, int>.unmodifiable(out);
  }

  /// Drops any skip for a day that has history against it.
  ///
  /// Doing something on a day you had written off is not a contradiction to
  /// resolve later — it just means the day was not off after all. Resolving it
  /// here rather than at each call site means [copyWith], and therefore every
  /// mutation, cannot leave a day both worked and skipped.
  static Set<DateTime> _normaliseSkips(
    Set<DateTime> skipped,
    Map<DateTime, int> entries,
    Set<DateTime> completedDays,
  ) {
    final worked = <DateTime>{
      for (final entry in entries.entries)
        if (entry.value > 0) dateOnly(entry.key),
      for (final day in completedDays) dateOnly(day),
    };
    return Set<DateTime>.unmodifiable(<DateTime>{
      for (final day in skipped)
        if (!worked.contains(dateOnly(day))) dateOnly(day),
    });
  }

  static DateTime? _earliestOf(
    Map<DateTime, int> entries,
    Set<DateTime> completedDays,
  ) {
    DateTime? earliest;
    for (final day in <DateTime>[...entries.keys, ...completedDays]) {
      if (earliest == null || day.isBefore(earliest)) earliest = day;
    }
    return earliest;
  }

  /// Logs needed for a day to count as done — never below one.
  int get effectiveTarget => targetPerDay < 1 ? 1 : targetPerDay;

  /// True when the habit tracks a count rather than a yes/no.
  bool get isCountable => effectiveTarget > 1;

  int progressOn(DateTime day) => entries[dateOnly(day)] ?? 0;

  bool isCompletedOn(DateTime day) => progressOn(day) >= effectiveTarget;

  bool isSkippedOn(DateTime day) => skippedDays.contains(dateOnly(day));

  /// Whether this habit is actually expected on [day].
  ///
  /// Three things can excuse a day, and every caller wants all three: the habit
  /// did not exist yet, the schedule doesn't ask for it, or the user planned the
  /// day off. [HabitSchedule.isDueOn] answers only the middle one, so prefer
  /// this everywhere a day is being judged.
  bool isDueOn(DateTime day) {
    final key = dateOnly(day);
    if (key.isBefore(createdAt)) return false;
    if (skippedDays.contains(key)) return false;
    return schedule.isDueOn(key);
  }

  /// Returns a copy with [day] marked as planned time off, or cleared.
  ///
  /// Skipping a day it has history on would be thrown away by the constructor's
  /// normalisation, so the completion is cleared first — the user asking for a
  /// day off on a day they already ticked means they want the tick gone.
  Habit setSkipped(DateTime day, bool skipped) {
    final key = dateOnly(day);
    if (isSkippedOn(key) == skipped) return this;

    final next = Set<DateTime>.of(skippedDays);
    if (skipped) {
      next.add(key);
      final entries = Map<DateTime, int>.of(this.entries)..remove(key);
      return copyWith(entries: entries, skippedDays: next);
    }
    next.remove(key);
    return copyWith(skippedDays: next);
  }

  /// Planned days off inside the last [days] days, for the "shields used" count.
  int skipsInLast(int days) {
    final today = dateOnly(DateTime.now());
    var count = 0;
    for (var i = 0; i < days; i++) {
      if (isSkippedOn(addDays(today, -i))) count++;
    }
    return count;
  }

  /// Days that reached the target, for callers that only care about done/not.
  Set<DateTime> get completedDays => <DateTime>{
    for (final entry in entries.entries)
      if (entry.value >= effectiveTarget) entry.key,
  };

  int get totalCompletions => completedDays.length;

  /// The first day with any history, or [createdAt] when there is none.
  DateTime get firstLoggedDay {
    DateTime? earliest;
    for (final day in entries.keys) {
      if (earliest == null || day.isBefore(earliest)) earliest = day;
    }
    return earliest ?? createdAt;
  }

  /// Returns a copy with [day] flipped between done and not-done.
  Habit toggle(DateTime day) {
    final key = dateOnly(day);
    final next = Map<DateTime, int>.of(entries);
    if (isCompletedOn(key)) {
      next.remove(key);
    } else {
      next[key] = effectiveTarget;
    }
    return copyWith(entries: next);
  }

  /// Adds one log to [day], stopping at the target.
  Habit increment(DateTime day) {
    final key = dateOnly(day);
    final current = progressOn(key);
    if (current >= effectiveTarget) return this;
    return copyWith(entries: {...entries, key: current + 1});
  }

  /// Removes one log from [day], clearing the day at zero.
  Habit decrement(DateTime day) {
    final key = dateOnly(day);
    final current = progressOn(key);
    if (current <= 0) return this;
    final next = Map<DateTime, int>.of(entries);
    if (current == 1) {
      next.remove(key);
    } else {
      next[key] = current - 1;
    }
    return copyWith(entries: next);
  }

  /// Consecutive completed *due* days ending today.
  ///
  /// A day the schedule doesn't ask for is stepped over rather than counted, so
  /// a Mon/Wed/Fri habit keeps its streak across the weekend. A day the user
  /// planned off is stepped over the same way — that is what a shield buys. A
  /// due day that hasn't been marked yet doesn't break the streak either: the
  /// count falls back to the previous due day, so an unticked morning doesn't
  /// read as a miss.
  int get streak => streakAsOf(DateTime.now());

  int streakAsOf(DateTime reference) {
    var cursor = dateOnly(reference);
    if (!isCompletedOn(cursor)) cursor = addDays(cursor, -1);

    // A streak cannot reach back past the first thing ever logged, which also
    // guarantees the loop terminates for a schedule with no due days at all.
    final floor = firstLoggedDay;
    var count = 0;
    while (!cursor.isBefore(floor)) {
      if (!isDueOn(cursor)) {
        cursor = addDays(cursor, -1);
        continue;
      }
      if (!isCompletedOn(cursor)) break;
      count++;
      cursor = addDays(cursor, -1);
    }
    return count;
  }

  /// The longest run of consecutive due days ever completed.
  int get bestStreak {
    if (entries.isEmpty) return 0;

    final today = dateOnly(DateTime.now());
    var best = 0;
    var run = 0;
    var cursor = firstLoggedDay;

    while (!cursor.isAfter(today)) {
      if (isDueOn(cursor)) {
        if (isCompletedOn(cursor)) {
          run++;
          if (run > best) best = run;
        } else if (cursor != today) {
          // Today is still in play, so an unmarked today isn't yet a break.
          run = 0;
        }
      }
      cursor = addDays(cursor, 1);
    }
    return best;
  }

  /// How many of the last [days] days (including today) were completed.
  int completionsInLast(int days) {
    final today = dateOnly(DateTime.now());
    var count = 0;
    for (var i = 0; i < days; i++) {
      if (isCompletedOn(addDays(today, -i))) count++;
    }
    return count;
  }

  /// How many of the last [days] days the schedule actually asked for.
  ///
  /// Days before the habit existed don't count against it — a habit added
  /// yesterday shouldn't show a 3% month — and neither do days planned off.
  int dueDaysInLast(int days) {
    final today = dateOnly(DateTime.now());
    var count = 0;
    for (var i = 0; i < days; i++) {
      if (isDueOn(addDays(today, -i))) count++;
    }
    return count;
  }

  /// Completion rate over the last [days] days, in 0..1.
  double completionRateInLast(int days) {
    final due = dueDaysInLast(days);
    if (due == 0) return 0;
    return (completionsInLast(days) / due).clamp(0.0, 1.0);
  }

  /// Completions inside the week containing [day], starting on [weekStartsOn].
  int completionsInWeekOf(DateTime day, {int weekStartsOn = DateTime.monday}) {
    final start = startOfWeek(day, weekStartsOn: weekStartsOn);
    var count = 0;
    for (var i = 0; i < 7; i++) {
      if (isCompletedOn(addDays(start, i))) count++;
    }
    return count;
  }

  Habit copyWith({
    String? title,
    IconData? icon,
    Color? color,
    Map<DateTime, int>? entries,
    int? targetPerDay,
    HabitSchedule? schedule,
    String? note,
    bool? archived,
    Set<DateTime>? skippedDays,
    // Passing null for a reminder should be able to *clear* it, which an
    // ordinary nullable parameter cannot express. The anchor has the same
    // problem: unstacking a habit *is* setting it to null.
    bool clearReminder = false,
    TimeOfDay? reminder,
    bool clearAnchor = false,
    String? anchorId,
  }) {
    return Habit(
      id: id,
      title: title ?? this.title,
      icon: icon ?? this.icon,
      color: color ?? this.color,
      entries: entries ?? this.entries,
      targetPerDay: targetPerDay ?? this.targetPerDay,
      schedule: schedule ?? this.schedule,
      reminder: clearReminder ? null : (reminder ?? this.reminder),
      note: note ?? this.note,
      archived: archived ?? this.archived,
      anchorId: clearAnchor ? null : (anchorId ?? this.anchorId),
      skippedDays: skippedDays ?? this.skippedDays,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'title': title,
    'icon': keyForIcon(icon),
    'color': color.toARGB32(),
    'targetPerDay': targetPerDay,
    'schedule': schedule.toJson(),
    'reminder': reminder == null
        ? null
        : reminder!.hour * 60 + reminder!.minute,
    'note': note,
    'archived': archived,
    'anchorId': anchorId,
    'skipped': (skippedDays.toList()..sort()).map(_encodeDay).toList(),
    'createdAt': _encodeDay(createdAt),
    // Compact on purpose: a year of daily history is ~365 short strings, and
    // the whole payload has to fit comfortably in shared preferences.
    'entries': <String, int>{
      for (final entry in entries.entries) _encodeDay(entry.key): entry.value,
    },
  };

  factory Habit.fromJson(Map<String, dynamic> json) {
    final rawEntries =
        (json['entries'] as Map<dynamic, dynamic>?) ?? const <dynamic, dynamic>{};
    final entries = <DateTime, int>{};
    for (final entry in rawEntries.entries) {
      final day = _decodeDay(entry.key as String?);
      final count = (entry.value as num?)?.toInt() ?? 0;
      if (day != null && count > 0) entries[day] = count;
    }

    final reminderMinutes = (json['reminder'] as num?)?.toInt();

    // Absent in schema v1 payloads, which is exactly what an empty set means.
    final rawSkips = (json['skipped'] as List<dynamic>?) ?? const <dynamic>[];
    final skipped = <DateTime>{
      for (final raw in rawSkips) ?_decodeDay(raw as String?),
    };

    // An anchor pointing at this very habit is the one cycle a single habit can
    // create on its own, and it would make the stack resolver spin.
    final anchorId = json['anchorId'] as String?;
    final id = json['id'] as String? ?? UniqueKey().toString();

    return Habit(
      id: id,
      title: json['title'] as String? ?? 'Habit',
      icon: iconForKey(json['icon'] as String?),
      color: Color((json['color'] as num?)?.toInt() ?? 0xFF2E7D32),
      entries: entries,
      targetPerDay: ((json['targetPerDay'] as num?)?.toInt() ?? 1).clamp(1, 99),
      schedule: json['schedule'] is Map
          ? HabitSchedule.fromJson(
              Map<String, dynamic>.from(json['schedule'] as Map),
            )
          : const HabitSchedule.daily(),
      reminder: reminderMinutes == null
          ? null
          : TimeOfDay(
              hour: (reminderMinutes ~/ 60).clamp(0, 23),
              minute: (reminderMinutes % 60).clamp(0, 59),
            ),
      note: json['note'] as String? ?? '',
      archived: json['archived'] as bool? ?? false,
      anchorId: anchorId == id ? null : anchorId,
      skippedDays: skipped,
      createdAt: _decodeDay(json['createdAt'] as String?),
    );
  }

  static String _encodeDay(DateTime day) => encodeDay(day);

  static DateTime? _decodeDay(String? raw) => decodeDay(raw);
}

/// The first day of the week containing [day].
///
/// [weekStartsOn] is an ISO weekday: [DateTime.monday] or [DateTime.sunday].
DateTime startOfWeek(DateTime day, {int weekStartsOn = DateTime.monday}) {
  final target = dateOnly(day);
  final offset = (target.weekday - weekStartsOn + 7) % 7;
  return addDays(target, -offset);
}
