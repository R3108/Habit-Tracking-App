import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:habit_tracker/models/app_settings.dart';
import 'package:habit_tracker/models/habit.dart';
import 'package:habit_tracker/services/backup_service.dart';

/// Habits with real history, so the round-trip assertions have something to
/// lose. The starter set the app ships with is deliberately empty.
List<Habit> fixtureHabits() {
  final today = dateOnly(DateTime.now());
  return [
    Habit(
      id: 'run',
      title: 'Morning run',
      icon: Icons.directions_run,
      color: const Color(0xFF2E7D32),
      schedule: const HabitSchedule.onDays({1, 3, 5}),
      reminder: const TimeOfDay(hour: 6, minute: 30),
      createdAt: addDays(today, -30),
      completedDays: {
        for (final offset in [0, 1, 2, 4, 6, 9]) addDays(today, -offset),
      },
    ),
    Habit(
      id: 'water',
      title: 'Drink water',
      icon: Icons.local_drink,
      color: const Color(0xFF00838F),
      targetPerDay: 8,
      createdAt: addDays(today, -30),
      entries: {today: 5, addDays(today, -1): 8},
    ),
  ];
}

void main() {
  test('a backup round-trips habits and settings', () {
    final habits = fixtureHabits();
    const settings = AppSettings(
      themeMode: ThemeMode.dark,
      weekStartsOn: DateTime.sunday,
      hapticsEnabled: false,
    );

    final restored = BackupService.import(
      BackupService.export(habits: habits, settings: settings),
    );

    expect(restored.habits.map((h) => h.title), habits.map((h) => h.title));
    expect(restored.settings?.themeMode, ThemeMode.dark);
    expect(restored.settings?.weekStartsOn, DateTime.sunday);
    expect(restored.settings?.hapticsEnabled, isFalse);
  });

  test('history survives the round trip', () {
    final original = fixtureHabits().first;
    final restored = BackupService.import(
      BackupService.export(
        habits: [original],
        settings: const AppSettings(),
      ),
    ).habits.first;

    expect(restored.entries, original.entries);
    expect(restored.entries, isNotEmpty);
    expect(restored.streak, original.streak);
    expect(restored.reminder, original.reminder);
    expect(restored.schedule, original.schedule);
  });

  test('a schema v1 backup still restores under v2', () {
    // Written before habit stacking and days off existed: neither field is
    // present, and an update must read it rather than reject somebody's only
    // copy of their history.
    const payload = '{"format":"habitflow-backup","version":1,"habits":['
        '{"id":"run","title":"Morning run","icon":"run","color":3050327,'
        '"targetPerDay":1,"note":"","archived":false,'
        '"entries":{"2026-08-20":1}}]}';

    final restored = BackupService.import(payload).habits;

    expect(restored, hasLength(1));
    expect(restored.first.title, 'Morning run');
    expect(restored.first.anchorId, isNull);
    expect(restored.first.skippedDays, isEmpty);
    expect(restored.first.isCompletedOn(DateTime(2026, 8, 20)), isTrue);
  });

  test('the new fields survive an export and re-import', () {
    final today = dateOnly(DateTime.now());
    final habits = [
      fixtureHabits().first,
      fixtureHabits().last.copyWith(
        anchorId: 'run',
        skippedDays: {addDays(today, -3)},
      ),
    ];

    final restored = BackupService.import(
      BackupService.export(habits: habits, settings: const AppSettings()),
    ).habits;

    expect(restored.last.anchorId, 'run');
    expect(restored.last.isSkippedOn(addDays(today, -3)), isTrue);
  });

  group('rejects', () {
    test('empty input', () {
      expect(
        () => BackupService.import('   '),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('text that is not JSON', () {
      expect(
        () => BackupService.import('my habits: run, read'),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('JSON from some other app', () {
      expect(
        () => BackupService.import('{"habits":[]}'),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('a backup from a newer schema', () {
      expect(
        () => BackupService.import(
          '{"format":"habitflow-backup","version":99,"habits":[]}',
        ),
        throwsA(
          isA<BackupFormatException>().having(
            (e) => e.message,
            'message',
            contains('newer version'),
          ),
        ),
      );
    });

    test('a backup with nothing readable in it', () {
      expect(
        () => BackupService.import(
          '{"format":"habitflow-backup","version":1,"habits":[]}',
        ),
        throwsA(isA<BackupFormatException>()),
      );
    });
  });

  test('one corrupt habit does not sink the rest', () {
    final good = fixtureHabits().first.toJson();
    final payload =
        '{"format":"habitflow-backup","version":1,"habits":['
        '${_json(good)},"not-an-object"]}';

    expect(BackupService.import(payload).habits, hasLength(1));
  });
}

String _json(Map<String, dynamic> value) {
  // Small hand-rolled encode so the test doesn't depend on the service it is
  // checking to build its own fixture.
  final buffer = StringBuffer('{');
  var first = true;
  value.forEach((key, dynamic entry) {
    if (!first) buffer.write(',');
    first = false;
    buffer.write('"$key":${_encodeValue(entry)}');
  });
  buffer.write('}');
  return buffer.toString();
}

String _encodeValue(dynamic value) {
  if (value == null) return 'null';
  if (value is num || value is bool) return '$value';
  if (value is String) return '"${value.replaceAll('"', r'\"')}"';
  if (value is List) return '[${value.map(_encodeValue).join(',')}]';
  if (value is Map) {
    return _json(Map<String, dynamic>.from(value));
  }
  return '"$value"';
}
