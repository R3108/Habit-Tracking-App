import 'package:flutter/material.dart';

import '../../models/habit.dart';
import '../../models/trackers/food_entry.dart';
import '../../models/trackers/tracker_goals.dart';
import '../../models/trackers/tracker_kind.dart';
import '../../state/tracker_store.dart';
import '../../widgets/trackers/tracker_widgets.dart';

/// Food: when you ate and roughly what, without a calorie database.
class FoodScreen extends StatefulWidget {
  const FoodScreen({super.key});

  static const kind = TrackerKind.food;

  @override
  State<FoodScreen> createState() => _FoodScreenState();
}

class _FoodScreenState extends State<FoodScreen> {
  DateTime _day = dateOnly(DateTime.now());

  bool get _isToday => _day == dateOnly(DateTime.now());

  void _shiftDay(int days) {
    final next = addDays(_day, days);
    // Nothing to log in the future, and a forward arrow that walks into empty
    // days is a control with no purpose.
    if (next.isAfter(dateOnly(DateTime.now()))) return;
    setState(() => _day = next);
  }

  @override
  Widget build(BuildContext context) {
    final store = TrackerScope.of(context);
    final goals = store.goals;
    final day = store.foodOn(_day);
    final insights = FoodInsights.from(store.data.food, goals: goals);
    final window = day.eatingWindowMinutes;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addMeal(store),
        backgroundColor: FoodScreen.kind.color,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Log a meal'),
      ),
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(title: Text(FoodScreen.kind.label)),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 108),
            sliver: SliverList.list(
              children: [
                _DayStepper(
                  day: _day,
                  canGoForward: !_isToday,
                  onShift: _shiftDay,
                ),
                const SizedBox(height: 16),
                _WindowCard(
                  windowMinutes: window,
                  goalMinutes: goals.eatingWindowMinutes,
                  firstMeal: day.firstMealMinutes,
                  lastMeal: day.lastMealMinutes,
                  quality: day.qualityScore,
                ),
                const SizedBox(height: 16),
                TrackerCard(
                  title: 'The day',
                  child: day.isEmpty
                      ? const TrackerEmptyState(
                          icon: Icons.restaurant_outlined,
                          title: 'Nothing logged',
                          message:
                              'Log meals as they happen. No calorie counting — '
                              'just when you ate and roughly what was on the '
                              'plate, which is the part you can answer '
                              'honestly.',
                        )
                      : Column(
                          children: [
                            for (final meal in day.meals)
                              _MealTile(
                                meal: meal,
                                onRemove: () => store.removeMeal(_day, meal.id),
                              ),
                          ],
                        ),
                ),
                const SizedBox(height: 16),
                if (insights.hasData) _PatternCard(insights: insights, goals: goals),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addMeal(TrackerStore store) async {
    final now = TimeOfDay.now();
    final draft = await showModalBottomSheet<
      ({int minutes, MealType type, Set<FoodTag> tags, String note})
    >(
      context: context,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.92,
      ),
      builder: (_) => _MealEditor(initialTime: now),
    );
    if (draft == null) return;

    store.addMeal(
      day: _day,
      minutesFromMidnight: draft.minutes,
      type: draft.type,
      tags: draft.tags,
      note: draft.note,
    );
  }
}

class _DayStepper extends StatelessWidget {
  const _DayStepper({
    required this.day,
    required this.canGoForward,
    required this.onShift,
  });

  final DateTime day;
  final bool canGoForward;
  final ValueChanged<int> onShift;

  @override
  Widget build(BuildContext context) {
    final today = dateOnly(DateTime.now());
    final label = day == today
        ? 'Today'
        : day == addDays(today, -1)
        ? 'Yesterday'
        : '${day.day}/${day.month}';

    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          tooltip: 'Previous day',
          onPressed: () => onShift(-1),
        ),
        Expanded(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          tooltip: 'Next day',
          onPressed: canGoForward ? () => onShift(1) : null,
        ),
      ],
    );
  }
}

/// The eating window: first meal to last, against the target.
class _WindowCard extends StatelessWidget {
  const _WindowCard({
    required this.windowMinutes,
    required this.goalMinutes,
    required this.firstMeal,
    required this.lastMeal,
    required this.quality,
  });

  final int? windowMinutes;
  final int goalMinutes;
  final int? firstMeal;
  final int? lastMeal;
  final int? quality;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final window = windowMinutes;

    return TrackerCard(
      title: 'Eating window',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (window == null)
            Text(
              firstMeal == null
                  ? 'Log two meals and this shows the span from your first to '
                        'your last — the number time-restricted eating is '
                        'actually about.'
                  : 'One meal so far, at ${formatClock(firstMeal!)}.',
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            )
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  formatMinutes(window),
                  style: textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: window <= goalMinutes
                        ? FoodScreen.kind.color
                        : scheme.error,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${formatClock(firstMeal!)} → ${formatClock(lastMeal!)}',
                  style: textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (window / goalMinutes).clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: scheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation(
                  window <= goalMinutes ? FoodScreen.kind.color : scheme.error,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              window <= goalMinutes
                  ? 'Inside your ${formatMinutes(goalMinutes)} target.'
                  : '${formatMinutes(window - goalMinutes)} over your '
                        '${formatMinutes(goalMinutes)} target.',
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          if (quality != null) ...[
            const Divider(height: 28),
            TrackerStatRow(
              icon: Icons.eco_outlined,
              label: 'Balance today',
              value: '$quality% nourishing',
              emphasis: quality! >= 60 ? FoodScreen.kind.color : null,
            ),
          ],
        ],
      ),
    );
  }
}

class _MealTile extends StatelessWidget {
  const _MealTile({required this.meal, required this.onRemove});

  final Meal meal;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 52,
            child: Text(
              formatClock(meal.minutesFromMidnight),
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: FoodScreen.kind.color,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  meal.type.label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (meal.tags.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final tag in meal.tags)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: tag.isNourishing
                                ? FoodScreen.kind.color.withValues(alpha: 0.14)
                                : scheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            tag.label,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: tag.isNourishing
                                      ? FoodScreen.kind.color
                                      : scheme.onSurfaceVariant,
                                ),
                          ),
                        ),
                    ],
                  ),
                ],
                if (meal.note.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    meal.note,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, size: 20, color: scheme.onSurfaceVariant),
            tooltip: 'Remove',
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

class _PatternCard extends StatelessWidget {
  const _PatternCard({required this.insights, required this.goals});

  final FoodInsights insights;
  final TrackerGoals goals;

  @override
  Widget build(BuildContext context) {
    return TrackerCard(
      title: 'Over ${insights.daysLogged} logged days',
      child: Column(
        children: [
          TrackerStatRow(
            icon: Icons.hourglass_bottom_outlined,
            label: 'Average window',
            value: insights.averageWindowMinutes == null
                ? '—'
                : formatMinutes(insights.averageWindowMinutes!),
          ),
          TrackerStatRow(
            icon: Icons.check_circle_outline,
            label: 'Days inside target',
            value: '${insights.daysInsideWindow}/${insights.daysLogged}',
          ),
          TrackerStatRow(
            icon: Icons.restaurant_menu,
            label: 'Meals a day',
            value: insights.averageMealsPerDay.toStringAsFixed(1),
          ),
          TrackerStatRow(
            icon: Icons.eco_outlined,
            label: 'Average balance',
            value: insights.averageQuality == null
                ? '—'
                : '${insights.averageQuality}% nourishing',
          ),
          if (insights.commonTags.isNotEmpty) ...[
            const Divider(height: 28),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Most common: '
                '${insights.commonTags.take(3).map((t) => t.tag.label.toLowerCase()).join(', ')}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MealEditor extends StatefulWidget {
  const _MealEditor({required this.initialTime});

  final TimeOfDay initialTime;

  @override
  State<_MealEditor> createState() => _MealEditorState();
}

class _MealEditorState extends State<_MealEditor> {
  late TimeOfDay _time = widget.initialTime;
  late MealType _type = _guessType(widget.initialTime);
  final _tags = <FoodTag>{};
  final _noteController = TextEditingController();

  /// Picks the likely sitting from the clock, so the common case is no taps.
  static MealType _guessType(TimeOfDay time) {
    final hour = time.hour;
    if (hour < 11) return MealType.breakfast;
    if (hour < 15) return MealType.lunch;
    if (hour < 21) return MealType.dinner;
    return MealType.snack;
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Log a meal', style: textTheme.headlineSmall),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'At ${_time.format(context)}',
                      style: textTheme.titleMedium,
                    ),
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.schedule),
                    label: const Text('Change'),
                    onPressed: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: _time,
                      );
                      if (picked != null) setState(() => _time = picked);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SegmentedButton<MealType>(
                segments: [
                  for (final type in MealType.values)
                    ButtonSegment(value: type, label: Text(type.label)),
                ],
                selected: {_type},
                showSelectedIcon: false,
                onSelectionChanged: (selection) =>
                    setState(() => _type = selection.first),
              ),
              const SizedBox(height: 20),
              Text(
                'What was on the plate?',
                style: textTheme.labelLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final tag in FoodTag.values)
                    FilterChip(
                      label: Text(tag.label),
                      selected: _tags.contains(tag),
                      selectedColor: tag.isNourishing
                          ? FoodScreen.kind.color.withValues(alpha: 0.2)
                          : scheme.surfaceContainerHighest,
                      onSelected: (selected) => setState(() {
                        if (selected) {
                          _tags.add(tag);
                        } else {
                          _tags.remove(tag);
                        }
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _noteController,
                maxLength: 60,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Note (optional)',
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: FoodScreen.kind.color,
                  ),
                  onPressed: () => Navigator.pop(context, (
                    minutes: _time.hour * 60 + _time.minute,
                    type: _type,
                    tags: Set<FoodTag>.of(_tags),
                    note: _noteController.text.trim(),
                  )),
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
