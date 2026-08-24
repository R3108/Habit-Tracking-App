import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../habit.dart';
import 'check_in_entry.dart';
import 'custom_tracker.dart';
import 'fitness_entry.dart';
import 'focus_entry.dart';
import 'food_entry.dart';
import 'reading_entry.dart';
import 'sleep_entry.dart';
import 'tracker_goals.dart';

/// Everything the six trackers remember, in one snapshot.
///
/// One aggregate rather than six stores, written under a single key. The
/// trackers are read together on every hub screen and saved together on every
/// edit, and six independently-versioned blobs would buy nothing but six ways
/// for a restore to land half-applied.
///
/// Immutable, like [Habit]: mutations rebuild the snapshot and the store swaps
/// it in. The collections here are hundreds of small records after years of
/// use, so copying one on a button tap is not worth the bug surface of shared
/// mutable state.
@immutable
class TrackerData {
  const TrackerData({
    this.goals = const TrackerGoals(),
    this.sleep = const <DateTime, SleepEntry>{},
    this.water = const <DateTime, int>{},
    this.reading = const <ReadingSession>[],
    this.bookLengths = const <String, int>{},
    this.food = const <DateTime, FoodDay>{},
    this.focus = const <FocusSession>[],
    this.workouts = const <Workout>[],
    this.checkIns = const <DateTime, CheckIn>{},
    this.customTrackers = const <CustomTracker>[],
    this.customEntries = const <String, Map<DateTime, double>>{},
    this.runningTimer,
  });

  final TrackerGoals goals;

  /// Keyed by the morning the night ended.
  final Map<DateTime, SleepEntry> sleep;

  /// Millilitres per day.
  final Map<DateTime, int> water;

  final List<ReadingSession> reading;

  /// Total pages per book, keyed by lower-cased title, for finish estimates.
  final Map<String, int> bookLengths;

  final Map<DateTime, FoodDay> food;
  final List<FocusSession> focus;
  final List<Workout> workouts;

  /// One mood-and-energy reading a day.
  final Map<DateTime, CheckIn> checkIns;

  /// User-defined trackers, in the order they were created.
  final List<CustomTracker> customTrackers;

  /// Custom tracker id → that tracker's day → value.
  ///
  /// Kept beside the definitions rather than inside them so that editing a
  /// tracker's name or target is a cheap swap of one small object, instead of
  /// rebuilding a map with a year of history in it.
  final Map<String, Map<DateTime, double>> customEntries;

  /// A pomodoro left running, or null. Survives a restart; see [RunningTimer].
  final RunningTimer? runningTimer;

  bool get isEmpty =>
      sleep.isEmpty &&
      water.isEmpty &&
      reading.isEmpty &&
      food.isEmpty &&
      focus.isEmpty &&
      workouts.isEmpty &&
      checkIns.isEmpty &&
      customTrackers.isEmpty;

  /// Custom trackers still in use, in list order.
  List<CustomTracker> get activeCustomTrackers =>
      customTrackers.where((t) => !t.archived).toList();

  Map<DateTime, double> entriesFor(String trackerId) =>
      customEntries[trackerId] ?? const <DateTime, double>{};

  TrackerData copyWith({
    TrackerGoals? goals,
    Map<DateTime, SleepEntry>? sleep,
    Map<DateTime, int>? water,
    List<ReadingSession>? reading,
    Map<String, int>? bookLengths,
    Map<DateTime, FoodDay>? food,
    List<FocusSession>? focus,
    List<Workout>? workouts,
    Map<DateTime, CheckIn>? checkIns,
    List<CustomTracker>? customTrackers,
    Map<String, Map<DateTime, double>>? customEntries,
    RunningTimer? runningTimer,
    bool clearTimer = false,
  }) {
    return TrackerData(
      goals: goals ?? this.goals,
      sleep: sleep ?? this.sleep,
      water: water ?? this.water,
      reading: reading ?? this.reading,
      bookLengths: bookLengths ?? this.bookLengths,
      food: food ?? this.food,
      focus: focus ?? this.focus,
      workouts: workouts ?? this.workouts,
      checkIns: checkIns ?? this.checkIns,
      customTrackers: customTrackers ?? this.customTrackers,
      customEntries: customEntries ?? this.customEntries,
      runningTimer: clearTimer ? null : (runningTimer ?? this.runningTimer),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'goals': goals.toJson(),
    'sleep': <String, dynamic>{
      for (final entry in sleep.entries)
        encodeDay(entry.key): entry.value.toJson(),
    },
    'water': <String, int>{
      for (final entry in water.entries)
        if (entry.value > 0) encodeDay(entry.key): entry.value,
    },
    'reading': reading.map((s) => s.toJson()).toList(),
    'bookLengths': bookLengths,
    'food': <String, dynamic>{
      for (final entry in food.entries)
        if (entry.value.meals.isNotEmpty)
          encodeDay(entry.key): entry.value.toJson(),
    },
    'focus': focus.map((s) => s.toJson()).toList(),
    'workouts': workouts.map((w) => w.toJson()).toList(),
    'checkIns': <String, dynamic>{
      for (final entry in checkIns.entries)
        encodeDay(entry.key): entry.value.toJson(),
    },
    'customTrackers': customTrackers.map((t) => t.toJson()).toList(),
    'customEntries': <String, dynamic>{
      for (final tracker in customEntries.entries)
        tracker.key: <String, double>{
          for (final day in tracker.value.entries)
            encodeDay(day.key): day.value,
        },
    },
    'runningTimer': runningTimer?.toJson(),
  };

  factory TrackerData.fromJson(Map<String, dynamic> json) {
    final sleep = <DateTime, SleepEntry>{};
    if (json['sleep'] case final Map<dynamic, dynamic> raw) {
      for (final entry in raw.entries) {
        final day = decodeDay(entry.key as String?);
        if (day == null || entry.value is! Map) continue;
        final parsed = SleepEntry.fromJson(
          day,
          Map<String, dynamic>.from(entry.value as Map),
        );
        if (parsed != null) sleep[day] = parsed;
      }
    }

    final water = <DateTime, int>{};
    if (json['water'] case final Map<dynamic, dynamic> raw) {
      for (final entry in raw.entries) {
        final day = decodeDay(entry.key as String?);
        final ml = (entry.value as num?)?.toInt() ?? 0;
        if (day != null && ml > 0) water[day] = ml;
      }
    }

    final food = <DateTime, FoodDay>{};
    if (json['food'] case final Map<dynamic, dynamic> raw) {
      for (final entry in raw.entries) {
        final day = decodeDay(entry.key as String?);
        if (day == null || entry.value is! List) continue;
        final parsed = FoodDay.fromJson(day, entry.value as List<dynamic>);
        if (parsed.meals.isNotEmpty) food[day] = parsed;
      }
    }

    final bookLengths = <String, int>{};
    if (json['bookLengths'] case final Map<dynamic, dynamic> raw) {
      for (final entry in raw.entries) {
        final pages = (entry.value as num?)?.toInt() ?? 0;
        if (entry.key is String && pages > 0) {
          bookLengths[entry.key as String] = pages;
        }
      }
    }

    final checkIns = <DateTime, CheckIn>{};
    if (json['checkIns'] case final Map<dynamic, dynamic> raw) {
      for (final entry in raw.entries) {
        final day = decodeDay(entry.key as String?);
        if (day == null || entry.value is! Map) continue;
        final parsed = CheckIn.fromJson(
          day,
          Map<String, dynamic>.from(entry.value as Map),
        );
        if (parsed != null) checkIns[day] = parsed;
      }
    }

    final customEntries = <String, Map<DateTime, double>>{};
    if (json['customEntries'] case final Map<dynamic, dynamic> raw) {
      for (final tracker in raw.entries) {
        if (tracker.key is! String || tracker.value is! Map) continue;
        final days = <DateTime, double>{};
        for (final day in (tracker.value as Map).entries) {
          final parsed = decodeDay(day.key as String?);
          final value = (day.value as num?)?.toDouble();
          if (parsed != null && value != null) days[parsed] = value;
        }
        if (days.isNotEmpty) customEntries[tracker.key as String] = days;
      }
    }

    return TrackerData(
      goals: json['goals'] is Map
          ? TrackerGoals.fromJson(
              Map<String, dynamic>.from(json['goals'] as Map),
            )
          : const TrackerGoals(),
      sleep: sleep,
      water: water,
      reading: _list(json['reading'], ReadingSession.fromJson),
      bookLengths: bookLengths,
      food: food,
      focus: _list(json['focus'], FocusSession.fromJson),
      workouts: _list(json['workouts'], Workout.fromJson),
      checkIns: checkIns,
      customTrackers: _list(json['customTrackers'], CustomTracker.fromJson),
      customEntries: customEntries,
      runningTimer: json['runningTimer'] is Map
          ? RunningTimer.fromJson(
              Map<String, dynamic>.from(json['runningTimer'] as Map),
            )
          : null,
    );
  }

  /// Decodes a list, dropping anything unreadable.
  ///
  /// One corrupt workout must not cost the user the other two hundred — the
  /// same rule the backup importer follows.
  static List<T> _list<T>(
    Object? raw,
    T? Function(Map<String, dynamic> json) parse,
  ) {
    if (raw is! List) return <T>[];
    return <T>[
      for (final item in raw)
        if (item is Map) ?parse(Map<String, dynamic>.from(item)),
    ];
  }
}

/// Current on-disk schema version for the tracker blob.
///
/// Versioned separately from the habit data because the two are written under
/// different keys and can move independently.
///
/// - v1: the six built-in trackers and their goals.
/// - v2: adds `checkIns`, `customTrackers` and `customEntries`. All three are
///   additive and absent-means-empty, so v1 payloads decode under v2 with no
///   migration branch.
const int kTrackerSchemaVersion = 2;

String encodeTrackers(TrackerData data) => jsonEncode(<String, dynamic>{
  'version': kTrackerSchemaVersion,
  'trackers': data.toJson(),
});

/// Decodes the envelope written by [encodeTrackers].
///
/// Null for anything unreadable, never a throw: a corrupt tracker blob should
/// cost the user their logs at worst, never the ability to open the app.
TrackerData? decodeTrackers(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return null;

    final version = (decoded['version'] as num?)?.toInt() ?? 0;
    if (version > kTrackerSchemaVersion) {
      debugPrint(
        'tracker data is schema v$version, this build reads '
        'v$kTrackerSchemaVersion',
      );
      return null;
    }

    final body = decoded['trackers'];
    if (body is! Map) return null;
    return TrackerData.fromJson(Map<String, dynamic>.from(body));
  } on FormatException catch (error) {
    debugPrint('could not decode tracker data: $error');
    return null;
  }
}
