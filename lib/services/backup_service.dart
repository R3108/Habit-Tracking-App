import 'dart:convert';

import '../data/app_repository.dart';
import '../models/app_settings.dart';
import '../models/habit.dart';

/// Raised when a pasted backup isn't something this app wrote.
class BackupFormatException implements Exception {
  const BackupFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// What a decoded backup contains.
typedef BackupContents = ({List<Habit> habits, AppSettings? settings});

/// Reads and writes the plain-text backup users move between devices.
///
/// Deliberately a *document* rather than a file handed to the OS: the app asks
/// for no storage permissions, declares no file access in its Play data-safety
/// form, and the user can paste the text anywhere they already trust. The cost
/// is a manual copy/paste, which for a once-a-year restore is a fair trade.
abstract final class BackupService {
  static const _magic = 'habitflow-backup';

  /// Pretty-printed so a user who opens it in a notes app sees something
  /// legible rather than one enormous line.
  static String export({
    required List<Habit> habits,
    required AppSettings settings,
  }) {
    return const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
      'format': _magic,
      'version': kSchemaVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'habits': habits.map((h) => h.toJson()).toList(),
      'settings': settings.toJson(),
    });
  }

  /// Parses text produced by [export].
  ///
  /// Throws [BackupFormatException] with something the UI can show, rather than
  /// letting a raw [FormatException] reach the user.
  static BackupContents import(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      throw const BackupFormatException('Nothing to import.');
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(trimmed);
    } on FormatException {
      throw const BackupFormatException(
        "That doesn't look like a HabitFlow backup — expected the JSON text "
        'copied from Settings › Back up data.',
      );
    }

    if (decoded is! Map<String, dynamic>) {
      throw const BackupFormatException('The backup is not in the right shape.');
    }
    if (decoded['format'] != _magic) {
      throw const BackupFormatException(
        'This backup was written by a different app.',
      );
    }

    final version = (decoded['version'] as num?)?.toInt() ?? 0;
    if (version > kSchemaVersion) {
      throw BackupFormatException(
        'This backup came from a newer version of HabitFlow (v$version). '
        'Update the app and try again.',
      );
    }

    final rawHabits = decoded['habits'];
    if (rawHabits is! List) {
      throw const BackupFormatException('The backup has no habits in it.');
    }

    final habits = <Habit>[];
    for (final item in rawHabits) {
      if (item is! Map) continue;
      try {
        habits.add(Habit.fromJson(Map<String, dynamic>.from(item)));
      } on Object {
        // One malformed habit shouldn't cost the user the other forty.
        continue;
      }
    }

    if (habits.isEmpty) {
      throw const BackupFormatException(
        'No readable habits were found in that backup.',
      );
    }

    AppSettings? settings;
    final rawSettings = decoded['settings'];
    if (rawSettings is Map) {
      try {
        settings = AppSettings.fromJson(
          Map<String, dynamic>.from(rawSettings),
        );
      } on Object {
        settings = null;
      }
    }

    return (habits: habits, settings: settings);
  }
}
