import 'package:flutter/foundation.dart';

import '../habit.dart';
import 'tracker_goals.dart';

/// Which sitting a meal was.
enum MealType { breakfast, lunch, dinner, snack }

extension MealTypeLabel on MealType {
  String get label => switch (this) {
    MealType.breakfast => 'Breakfast',
    MealType.lunch => 'Lunch',
    MealType.dinner => 'Dinner',
    MealType.snack => 'Snack',
  };
}

/// What a meal was mostly made of.
///
/// Tags, not calories. A calorie count needs a food database, which means a
/// network call, an account and a privacy policy this app does not want to
/// write — and the number is guesswork anyway. What somebody *can* answer
/// honestly in three seconds at the table is whether there were vegetables on
/// the plate, and that turns out to predict more than the arithmetic does.
enum FoodTag { vegetables, fruit, protein, wholegrain, homeCooked, sugary, fried, takeaway }

extension FoodTagInfo on FoodTag {
  String get label => switch (this) {
    FoodTag.vegetables => 'Vegetables',
    FoodTag.fruit => 'Fruit',
    FoodTag.protein => 'Protein',
    FoodTag.wholegrain => 'Wholegrain',
    FoodTag.homeCooked => 'Home-cooked',
    FoodTag.sugary => 'Sugary',
    FoodTag.fried => 'Fried',
    FoodTag.takeaway => 'Takeaway',
  };

  /// Whether the tag counts toward or against the day's quality score.
  ///
  /// The split is coarse on purpose. A tracker that grades food finely enough
  /// to be argued with is one people start lying to.
  bool get isNourishing => switch (this) {
    FoodTag.vegetables ||
    FoodTag.fruit ||
    FoodTag.protein ||
    FoodTag.wholegrain ||
    FoodTag.homeCooked => true,
    FoodTag.sugary || FoodTag.fried || FoodTag.takeaway => false,
  };
}

/// One meal, at a time of day.
@immutable
class Meal {
  const Meal({
    required this.id,
    required this.minutesFromMidnight,
    required this.type,
    this.tags = const <FoodTag>{},
    this.note = '',
  });

  final String id;
  final int minutesFromMidnight;
  final MealType type;
  final Set<FoodTag> tags;
  final String note;

  int get nourishing => tags.where((t) => t.isNourishing).length;
  int get indulgent => tags.where((t) => !t.isNourishing).length;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'at': minutesFromMidnight,
    'type': type.name,
    'tags': tags.map((t) => t.name).toList(),
    'note': note,
  };

  static Meal? fromJson(Map<String, dynamic> json) {
    final at = (json['at'] as num?)?.toInt();
    if (at == null) return null;

    final rawTags = (json['tags'] as List<dynamic>?) ?? const <dynamic>[];

    return Meal(
      id: json['id'] as String? ?? 'meal-$at',
      minutesFromMidnight: at.clamp(0, 1439),
      type: MealType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => MealType.snack,
      ),
      // An unknown tag is dropped rather than defaulted: guessing that a tag
      // this build has never heard of was "vegetables" would quietly change
      // the score.
      tags: <FoodTag>{
        for (final raw in rawTags)
          for (final tag in FoodTag.values)
            if (tag.name == raw) tag,
      },
      note: json['note'] as String? ?? '',
    );
  }
}

/// A day's meals.
@immutable
class FoodDay {
  const FoodDay({required this.day, this.meals = const <Meal>[]});

  final DateTime day;

  /// Ordered by time of day.
  final List<Meal> meals;

  bool get isEmpty => meals.isEmpty;

  int? get firstMealMinutes => meals.isEmpty ? null : meals.first.minutesFromMidnight;
  int? get lastMealMinutes => meals.isEmpty ? null : meals.last.minutesFromMidnight;

  /// Minutes from the first meal to the last.
  ///
  /// The number time-restricted eating is actually about, and one nobody can
  /// work out in their head at the end of a day. Null until there are two
  /// meals to span.
  int? get eatingWindowMinutes {
    if (meals.length < 2) return null;
    return meals.last.minutesFromMidnight - meals.first.minutesFromMidnight;
  }

  int get nourishingCount => meals.fold(0, (sum, m) => sum + m.nourishing);
  int get indulgentCount => meals.fold(0, (sum, m) => sum + m.indulgent);

  /// 0..100 from the balance of tags across the day, or null when nothing was
  /// tagged. Half marks for a day tagged evenly both ways.
  int? get qualityScore {
    final total = nourishingCount + indulgentCount;
    if (total == 0) return null;
    return (100 * nourishingCount / total).round();
  }

  FoodDay withMeal(Meal meal) {
    final next = <Meal>[...meals.where((m) => m.id != meal.id), meal]
      ..sort((a, b) => a.minutesFromMidnight.compareTo(b.minutesFromMidnight));
    return FoodDay(day: day, meals: next);
  }

  FoodDay withoutMeal(String id) =>
      FoodDay(day: day, meals: meals.where((m) => m.id != id).toList());

  List<Map<String, dynamic>> toJson() =>
      meals.map((m) => m.toJson()).toList();

  static FoodDay fromJson(DateTime day, List<dynamic> raw) {
    final meals = <Meal>[
      for (final item in raw)
        if (item is Map) ?Meal.fromJson(Map<String, dynamic>.from(item)),
    ]..sort((a, b) => a.minutesFromMidnight.compareTo(b.minutesFromMidnight));

    return FoodDay(day: dateOnly(day), meals: meals);
  }
}

/// What the food log adds up to over a stretch of days.
@immutable
class FoodInsights {
  const FoodInsights._({
    required this.daysLogged,
    required this.averageWindowMinutes,
    required this.averageMealsPerDay,
    required this.averageQuality,
    required this.daysInsideWindow,
    required this.commonTags,
  });

  final int daysLogged;

  /// Mean eating window across days that had one, or null.
  final int? averageWindowMinutes;

  final double averageMealsPerDay;

  /// Mean quality score across days that had tags, or null.
  final int? averageQuality;

  /// Days whose window came in at or under the goal.
  final int daysInsideWindow;

  /// Tags by how often they appeared, most first.
  final List<({FoodTag tag, int count})> commonTags;

  static const int windowDays = 14;

  bool get hasData => daysLogged > 0;

  factory FoodInsights.from(
    Map<DateTime, FoodDay> log, {
    required TrackerGoals goals,
    DateTime? reference,
    int window = windowDays,
  }) {
    final today = dateOnly(reference ?? DateTime.now());

    var days = 0;
    var meals = 0;
    var windowTotal = 0;
    var windowDaysCounted = 0;
    var insideWindow = 0;
    var qualityTotal = 0;
    var qualityDays = 0;
    final tagCounts = <FoodTag, int>{};

    for (var age = 0; age < window; age++) {
      final entry = log[addDays(today, -age)];
      if (entry == null || entry.isEmpty) continue;

      days++;
      meals += entry.meals.length;

      final span = entry.eatingWindowMinutes;
      if (span != null) {
        windowTotal += span;
        windowDaysCounted++;
        if (span <= goals.eatingWindowMinutes) insideWindow++;
      }

      final quality = entry.qualityScore;
      if (quality != null) {
        qualityTotal += quality;
        qualityDays++;
      }

      for (final meal in entry.meals) {
        for (final tag in meal.tags) {
          tagCounts[tag] = (tagCounts[tag] ?? 0) + 1;
        }
      }
    }

    final common =
        tagCounts.entries
            .map((e) => (tag: e.key, count: e.value))
            .toList()
          ..sort((a, b) => b.count.compareTo(a.count));

    return FoodInsights._(
      daysLogged: days,
      averageWindowMinutes: windowDaysCounted == 0
          ? null
          : (windowTotal / windowDaysCounted).round(),
      averageMealsPerDay: days == 0 ? 0 : meals / days,
      averageQuality: qualityDays == 0
          ? null
          : (qualityTotal / qualityDays).round(),
      daysInsideWindow: insideWindow,
      commonTags: common,
    );
  }
}
