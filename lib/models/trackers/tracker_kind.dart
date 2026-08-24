import 'package:flutter/material.dart';

/// The six trackers, and how each one presents itself.
///
/// Icon and colour live on the enum rather than being chosen at each call site
/// so a tracker looks the same on the hub, in its own header and in any summary
/// that appears later — the colour is how somebody finds the water screen
/// without reading, and it only works if it never moves.
///
/// Every [IconData] here is a compile-time constant, for the same tree-shaking
/// reason [kHabitIcons] exists.
enum TrackerKind {
  sleep(
    label: 'Sleep',
    blurb: 'Hours, regularity and sleep debt',
    icon: Icons.bedtime_outlined,
    color: Color(0xFF3F51B5),
  ),
  water(
    label: 'Water',
    blurb: 'Intake against a daily target',
    icon: Icons.water_drop_outlined,
    color: Color(0xFF0288D1),
  ),
  reading(
    label: 'Reading',
    blurb: 'Pages, pace and what you finish',
    icon: Icons.menu_book_outlined,
    color: Color(0xFF6D4C41),
  ),
  food(
    label: 'Food',
    blurb: 'Meals, timing and balance',
    icon: Icons.restaurant_outlined,
    color: Color(0xFF2E7D32),
  ),
  focus(
    label: 'Focus',
    blurb: 'Pomodoro sessions and deep work',
    icon: Icons.timer_outlined,
    color: Color(0xFFC62828),
  ),
  fitness(
    label: 'Fitness',
    blurb: 'Workouts, active minutes and load',
    icon: Icons.fitness_center_outlined,
    color: Color(0xFFEF6C00),
  );

  const TrackerKind({
    required this.label,
    required this.blurb,
    required this.icon,
    required this.color,
  });

  final String label;
  final String blurb;
  final IconData icon;
  final Color color;
}
