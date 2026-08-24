import 'package:flutter/material.dart';

import '../../models/habit.dart';
import '../../models/habit_icons.dart';
import '../../models/trackers/custom_tracker.dart';
import '../../state/tracker_store.dart';
import '../../util/haptics.dart';
import '../../widgets/trackers/tracker_widgets.dart';

/// One user-defined tracker.
///
/// Takes an id rather than the definition, for the same reason
/// [HabitDetailScreen] does: the store hands out immutable snapshots, and
/// holding the object would leave this screen showing a stale target the moment
/// it is edited.
class CustomTrackerScreen extends StatelessWidget {
  const CustomTrackerScreen({super.key, required this.trackerId});

  final String trackerId;

  @override
  Widget build(BuildContext context) {
    final store = TrackerScope.of(context);
    final tracker = store.customTrackerById(trackerId);

    if (tracker == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('This tracker no longer exists.')),
      );
    }

    final today = dateOnly(DateTime.now());
    final log = store.data.entriesFor(trackerId);
    final insights = CustomTrackerInsights.from(tracker, log);
    final todayValue = store.customValueOn(trackerId, today);

    final week = <({DateTime day, num value})>[
      for (var age = 6; age >= 0; age--)
        (day: addDays(today, -age), value: log[addDays(today, -age)] ?? 0),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(tracker.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit',
            onPressed: () => _edit(context, store, tracker),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete',
            onPressed: () => _confirmDelete(context, store, tracker),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Center(
            child: GoalRing(
              progress: tracker.share(todayValue),
              value: tracker.format(todayValue),
              caption: tracker.lowerIsBetter
                  ? 'stay under ${tracker.format(tracker.dailyTarget)}'
                  : 'of ${tracker.format(tracker.dailyTarget)}',
              footnote: tracker.meetsTarget(todayValue) ? 'on target' : null,
              accent: tracker.color,
            ),
          ),
          const SizedBox(height: 24),
          _Entry(
            tracker: tracker,
            value: todayValue,
            onAdd: (amount) {
              Haptics.impact(context);
              store.addCustomValue(trackerId, today, amount);
            },
            onSet: (value) {
              Haptics.tick(context);
              store.setCustomValue(trackerId, today, value);
            },
            onClear: () => store.clearCustomValue(trackerId, today),
          ),
          const SizedBox(height: 16),
          TrackerCard(
            title: 'Last 7 days',
            child: MiniBars(
              values: week,
              // A ceiling tracker has no "reach this" line to draw: a bar over
              // the target is the bad case, and colouring it as success would
              // say the opposite of what is meant.
              goal: tracker.lowerIsBetter ? null : tracker.dailyTarget,
              accent: tracker.color,
            ),
          ),
          const SizedBox(height: 16),
          TrackerCard(
            title: 'Over ${insights.daysLogged} logged days',
            child: Column(
              children: [
                TrackerStatRow(
                  icon: Icons.local_fire_department_outlined,
                  label: 'On-target streak',
                  value: '${insights.streak} day'
                      '${insights.streak == 1 ? '' : 's'}',
                  emphasis: insights.streak > 0 ? tracker.color : null,
                ),
                TrackerStatRow(
                  icon: Icons.show_chart,
                  label: 'Daily average',
                  value: tracker.format(insights.average),
                ),
                TrackerStatRow(
                  icon: Icons.emoji_events_outlined,
                  label: 'Best day',
                  value: tracker.format(insights.best),
                ),
                if (tracker.kind != CustomTrackerKind.scale)
                  TrackerStatRow(
                    icon: Icons.functions,
                    label: 'Total',
                    value: tracker.format(insights.total),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _edit(
    BuildContext context,
    TrackerStore store,
    CustomTracker tracker,
  ) async {
    final draft = await CustomTrackerEditor.show(context, initial: tracker);
    if (draft == null) return;
    store.updateCustomTracker(
      tracker.copyWith(
        name: draft.name,
        kind: draft.kind,
        iconKey: draft.iconKey,
        colorValue: draft.colorValue,
        unit: draft.unit,
        dailyTarget: draft.dailyTarget,
        step: draft.step,
        lowerIsBetter: draft.lowerIsBetter,
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    TrackerStore store,
    CustomTracker tracker,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete "${tracker.name}"?'),
        content: const Text(
          'Its whole history goes with it. You can undo this from the message '
          'that appears, but not after leaving the app.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final removed = store.removeCustomTracker(tracker.id);
    if (removed == null) return;

    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Deleted "${tracker.name}"'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => store.insertCustomTracker(
              removed.index,
              removed.tracker,
              removed.entries,
            ),
          ),
        ),
      );
  }
}

/// Today's number, entered the way this tracker's kind wants.
class _Entry extends StatelessWidget {
  const _Entry({
    required this.tracker,
    required this.value,
    required this.onAdd,
    required this.onSet,
    required this.onClear,
  });

  final CustomTracker tracker;
  final double value;
  final ValueChanged<double> onAdd;
  final ValueChanged<double> onSet;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    if (tracker.kind == CustomTrackerKind.scale) {
      return TrackerCard(
        title: 'Today',
        child: Row(
          children: [
            for (var score = 1; score <= 5; score++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: OutlinedButton(
                    onPressed: () => onSet(score.toDouble()),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: value == score
                          ? tracker.color
                          : Colors.transparent,
                      foregroundColor: value == score
                          ? Colors.white
                          : tracker.color,
                      side: BorderSide(
                        color: tracker.color.withValues(alpha: 0.5),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text('$score'),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return TrackerCard(
      title: 'Today',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: tracker.color,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: const Icon(Icons.add),
                  label: Text(tracker.format(tracker.step)),
                  onPressed: () => onAdd(tracker.step.toDouble()),
                ),
              ),
              const SizedBox(width: 10),
              IconButton.filledTonal(
                onPressed: value <= 0
                    ? null
                    : () => onAdd(-tracker.step.toDouble()),
                icon: const Icon(Icons.remove),
                tooltip: 'Take one off',
              ),
              const SizedBox(width: 4),
              IconButton(
                onPressed: value <= 0 ? null : onClear,
                icon: const Icon(Icons.close),
                tooltip: 'Clear today',
              ),
            ],
          ),
          if (tracker.lowerIsBetter) ...[
            const SizedBox(height: 10),
            Text(
              'Lower is better here, so a day with nothing logged is not the '
              'same as a day you recorded a zero — only the second one counts '
              'toward the streak.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.check),
              label: const Text('Record a clean zero'),
              onPressed: () => onSet(0),
            ),
          ],
        ],
      ),
    );
  }
}

/// What [CustomTrackerEditor] hands back.
typedef CustomTrackerDraft = ({
  String name,
  CustomTrackerKind kind,
  String iconKey,
  int colorValue,
  String unit,
  int dailyTarget,
  int step,
  bool lowerIsBetter,
});

/// Creates or edits a custom tracker.
class CustomTrackerEditor extends StatefulWidget {
  const CustomTrackerEditor({super.key, this.initial});

  final CustomTracker? initial;

  static Future<CustomTrackerDraft?> show(
    BuildContext context, {
    CustomTracker? initial,
  }) {
    return showModalBottomSheet<CustomTrackerDraft>(
      context: context,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.92,
      ),
      builder: (_) => CustomTrackerEditor(initial: initial),
    );
  }

  @override
  State<CustomTrackerEditor> createState() => _CustomTrackerEditorState();
}

class _CustomTrackerEditorState extends State<CustomTrackerEditor> {
  late final _nameController = TextEditingController(
    text: widget.initial?.name ?? '',
  );
  late final _unitController = TextEditingController(
    text: widget.initial?.unit ?? '',
  );
  late final _targetController = TextEditingController(
    text: '${widget.initial?.dailyTarget ?? 1}',
  );
  late final _stepController = TextEditingController(
    text: '${widget.initial?.step ?? 1}',
  );

  late CustomTrackerKind _kind = widget.initial?.kind ?? CustomTrackerKind.count;
  late String _iconKey = widget.initial?.iconKey ?? 'star';
  late int _color = widget.initial?.colorValue ?? kHabitPalette[3].toARGB32();
  late bool _lowerIsBetter = widget.initial?.lowerIsBetter ?? false;

  @override
  void initState() {
    super.initState();
    _nameController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _unitController.dispose();
    _targetController.dispose();
    _stepController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final accent = Color(_color);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.initial == null ? 'New tracker' : 'Edit tracker',
                style: textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _nameController,
                autofocus: widget.initial == null,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: 'What are you tracking?',
                  hintText: 'e.g. Steps, Coffees, Guitar practice',
                  prefixIcon: Icon(iconForKey(_iconKey), color: accent),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'What kind of number is it?',
                style: textTheme.labelLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              SegmentedButton<CustomTrackerKind>(
                segments: [
                  for (final kind in CustomTrackerKind.values)
                    ButtonSegment(value: kind, label: Text(kind.label)),
                ],
                selected: {_kind},
                showSelectedIcon: false,
                onSelectionChanged: (selection) =>
                    setState(() => _kind = selection.first),
              ),
              const SizedBox(height: 6),
              Text(
                _kind.blurb,
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              if (_kind == CustomTrackerKind.amount) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _unitController,
                  decoration: const InputDecoration(
                    labelText: 'Unit',
                    hintText: 'km, g, ₹',
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _targetController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Daily target',
                      ),
                    ),
                  ),
                  if (_kind.supportsQuickAdd) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _stepController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Button adds',
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Lower is better'),
                subtitle: const Text(
                  'For things you want less of — the target becomes a ceiling',
                ),
                value: _lowerIsBetter,
                activeThumbColor: accent,
                onChanged: (value) => setState(() => _lowerIsBetter = value),
              ),
              const SizedBox(height: 12),
              Text(
                'Icon',
                style: textTheme.labelLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 96,
                child: GridView.count(
                  crossAxisCount: 2,
                  scrollDirection: Axis.horizontal,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  children: [
                    for (final entry in kHabitIcons.entries)
                      _Swatch(
                        isSelected: entry.key == _iconKey,
                        background: entry.key == _iconKey
                            ? accent
                            : scheme.surfaceContainerHighest,
                        onTap: () => setState(() => _iconKey = entry.key),
                        child: Icon(
                          entry.value,
                          size: 20,
                          color: entry.key == _iconKey
                              ? Colors.white
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Colour',
                style: textTheme.labelLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final colour in kHabitPalette)
                    _Swatch(
                      isSelected: colour.toARGB32() == _color,
                      background: colour,
                      onTap: () =>
                          setState(() => _color = colour.toARGB32()),
                      child: colour.toARGB32() == _color
                          ? const Icon(Icons.check, size: 20, color: Colors.white)
                          : const SizedBox.shrink(),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: accent),
                  onPressed: _nameController.text.trim().isEmpty
                      ? null
                      : _submit,
                  child: Text(
                    widget.initial == null ? 'Create tracker' : 'Save changes',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    Navigator.pop(context, (
      name: name,
      kind: _kind,
      iconKey: _iconKey,
      colorValue: _color,
      unit: _unitController.text.trim(),
      // A target of zero is meaningful for a ceiling tracker ("no cigarettes"),
      // so it is only floored at zero rather than at one.
      dailyTarget: (int.tryParse(_targetController.text.trim()) ?? 1).clamp(
        0,
        100000,
      ),
      step: (int.tryParse(_stepController.text.trim()) ?? 1).clamp(1, 10000),
      lowerIsBetter: _lowerIsBetter,
    ));
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.isSelected,
    required this.background,
    required this.onTap,
    required this.child,
  });

  final bool isSelected;
  final Color background;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? scheme.onSurface : scheme.outlineVariant,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: child,
      ),
    );
  }
}
