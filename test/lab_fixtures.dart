import 'package:flutter/material.dart';

import 'package:habit_tracker/models/habit.dart';

/// The day every lab test measures from.
///
/// A Wednesday, which matters for the schedule-aware tests: a Mon/Wed/Fri habit
/// is due on it, so "today" is never accidentally a rest day.
final labReference = DateTime(2026, 8, 26);

/// A habit alive for [ageInDays], completed on whichever ages [done] says.
///
/// Ages count back from [labReference]: 1 is the last day before it. Age 0 —
/// the reference day itself — is deliberately never completed by this builder,
/// because every analysis in the lab excludes today on the grounds that it may
/// simply not have happened yet. Tests that need a completed today should add
/// it explicitly.
///
/// Shared rather than copied into each test file: five suites measuring the
/// same history need to be measuring *the same* history, and a builder that
/// drifted between them would produce disagreements that look like bugs in the
/// models.
Habit labHabit({
  required bool Function(int age) done,
  int ageInDays = 200,
  HabitSchedule schedule = const HabitSchedule.daily(),
  String id = 'h',
  String? title,
  Set<DateTime> extraCompletions = const <DateTime>{},
}) {
  return Habit(
    id: id,
    title: title ?? id,
    icon: Icons.check,
    color: const Color(0xFF1565C0),
    schedule: schedule,
    createdAt: addDays(labReference, -ageInDays),
    completedDays: <DateTime>{
      for (var age = 1; age <= ageInDays; age++)
        if (done(age)) addDays(labReference, -age),
      ...extraCompletions,
    },
  );
}
