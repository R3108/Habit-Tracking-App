import 'package:flutter/material.dart';

/// The fixed catalogue of icons a habit can use.
///
/// Habits are stored on disk by *key*, never by code point, because every
/// [IconData] the app can build has to be a compile-time constant. Flutter's
/// release builds tree-shake the Material icon font down to the glyphs it can
/// prove are reachable, and a single `IconData(someRuntimeInt)` anywhere in the
/// program disables that pass with a build error. Round-tripping through this
/// map keeps the constants const and the font small.
const Map<String, IconData> kHabitIcons = <String, IconData>{
  'run': Icons.directions_run,
  'book': Icons.menu_book,
  'water': Icons.local_drink,
  'meditate': Icons.self_improvement,
  'gym': Icons.fitness_center,
  'sleep': Icons.bedtime,
  'code': Icons.code,
  'music': Icons.music_note,
  'art': Icons.brush,
  'plant': Icons.eco,
  'walk': Icons.directions_walk,
  'bike': Icons.directions_bike,
  'yoga': Icons.sports_gymnastics,
  'food': Icons.restaurant,
  'pill': Icons.medication,
  'money': Icons.savings,
  'clean': Icons.cleaning_services,
  'study': Icons.school,
  'write': Icons.edit_note,
  'call': Icons.call,
  'sun': Icons.wb_sunny,
  'heart': Icons.favorite,
  'star': Icons.star,
  'check': Icons.check_circle,
};

/// Fallback used whenever a stored key is unknown — an icon removed in a later
/// version must never cost the user their habit.
const String kDefaultIconKey = 'check';

IconData iconForKey(String? key) => kHabitIcons[key] ?? kHabitIcons[kDefaultIconKey]!;

/// Reverse lookup for serialisation.
///
/// Matching on [IconData.codePoint] rather than identity means an icon built
/// from `Icons.x` elsewhere in the app still resolves to its key.
String keyForIcon(IconData icon) {
  for (final entry in kHabitIcons.entries) {
    if (entry.value.codePoint == icon.codePoint) return entry.key;
  }
  return kDefaultIconKey;
}

/// Colours offered in the habit editor. Stored as ARGB ints, so removing one
/// here does not orphan habits that already use it.
const List<Color> kHabitPalette = <Color>[
  Color(0xFF2E7D32),
  Color(0xFF1565C0),
  Color(0xFF00838F),
  Color(0xFF6A1B9A),
  Color(0xFFC62828),
  Color(0xFFEF6C00),
  Color(0xFFAD1457),
  Color(0xFF4E342E),
  Color(0xFF37474F),
  Color(0xFF558B2F),
];
