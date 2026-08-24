import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';
import '../models/habit.dart';

/// Current on-disk schema version.
///
/// Bump this whenever a stored shape changes and add a branch to
/// [decodeHabits]; readers must keep understanding older payloads or an update
/// would silently wipe somebody's history.
///
/// - v1: the original habit shape.
/// - v2: adds `anchorId` (habit stacking) and `skipped` (planned days off).
///   Both are additive and absent-means-default, so v1 payloads decode under v2
///   with no migration branch — [Habit.fromJson] already treats a missing
///   `skipped` as no days off and a missing `anchorId` as unstacked.
const int kSchemaVersion = 2;

/// Persistence boundary for everything the app remembers.
///
/// Kept abstract so tests and previews can run against
/// [InMemoryAppRepository] without touching platform channels.
abstract class AppRepository {
  /// Returns null when nothing has ever been saved, which is how the app
  /// distinguishes a first launch from a user who deleted all their habits.
  Future<List<Habit>?> loadHabits();

  Future<void> saveHabits(List<Habit> habits);

  Future<AppSettings?> loadSettings();

  Future<void> saveSettings(AppSettings settings);

  Future<void> clear();
}

/// Encodes habits into the versioned envelope written to storage.
String encodeHabits(List<Habit> habits) => jsonEncode(<String, dynamic>{
  'version': kSchemaVersion,
  'habits': habits.map((h) => h.toJson()).toList(),
});

/// Decodes the envelope written by [encodeHabits].
///
/// Returns null for anything unreadable rather than throwing: a corrupt value
/// should cost the user their history at worst, never the ability to open the
/// app.
List<Habit>? decodeHabits(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return null;

    final version = (decoded['version'] as num?)?.toInt() ?? 0;
    if (version > kSchemaVersion) {
      // Written by a newer build — refuse rather than mangle it.
      debugPrint('habit data is schema v$version, this build reads v$kSchemaVersion');
      return null;
    }

    final list = decoded['habits'];
    if (list is! List) return null;

    return <Habit>[
      for (final item in list)
        if (item is Map) Habit.fromJson(Map<String, dynamic>.from(item)),
    ];
  } on FormatException catch (error) {
    debugPrint('could not decode habit data: $error');
    return null;
  }
}

/// Default implementation, backed by shared preferences.
///
/// A habit tracker's whole history is a few tens of kilobytes of JSON even
/// after years of use, which fits comfortably in preferences and avoids
/// shipping a database engine for four columns of data.
class SharedPreferencesAppRepository implements AppRepository {
  SharedPreferencesAppRepository({this.preferences});

  static const _habitsKey = 'habitflow.habits';
  static const _settingsKey = 'habitflow.settings';

  /// Injected in tests; resolved lazily on the first read otherwise.
  SharedPreferences? preferences;

  Future<SharedPreferences> get _prefs async =>
      preferences ??= await SharedPreferences.getInstance();

  @override
  Future<List<Habit>?> loadHabits() async {
    final prefs = await _prefs;
    return decodeHabits(prefs.getString(_habitsKey));
  }

  @override
  Future<void> saveHabits(List<Habit> habits) async {
    final prefs = await _prefs;
    await prefs.setString(_habitsKey, encodeHabits(habits));
  }

  @override
  Future<AppSettings?> loadSettings() async {
    final prefs = await _prefs;
    final raw = prefs.getString(_settingsKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return AppSettings.fromJson(decoded);
    } on FormatException catch (error) {
      debugPrint('could not decode settings: $error');
      return null;
    }
  }

  @override
  Future<void> saveSettings(AppSettings settings) async {
    final prefs = await _prefs;
    await prefs.setString(_settingsKey, jsonEncode(settings.toJson()));
  }

  @override
  Future<void> clear() async {
    final prefs = await _prefs;
    await prefs.remove(_habitsKey);
    await prefs.remove(_settingsKey);
  }
}

/// Volatile repository for tests, widget previews and the demo seed.
class InMemoryAppRepository implements AppRepository {
  InMemoryAppRepository({this.habits, this.settings});

  /// Public so a test can assert on what the store wrote.
  List<Habit>? habits;
  AppSettings? settings;

  @override
  Future<List<Habit>?> loadHabits() async => habits;

  @override
  Future<void> saveHabits(List<Habit> value) async => habits = value;

  @override
  Future<AppSettings?> loadSettings() async => settings;

  @override
  Future<void> saveSettings(AppSettings value) async => settings = value;

  @override
  Future<void> clear() async {
    habits = null;
    settings = null;
  }
}
