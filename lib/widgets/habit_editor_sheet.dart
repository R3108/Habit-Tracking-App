import 'package:flutter/material.dart';

import '../models/habit.dart';
import '../models/habit_icons.dart';

/// What [HabitEditorSheet] hands back when the user confirms.
typedef HabitDraft = ({
  String title,
  IconData icon,
  Color color,
  HabitSchedule schedule,
  int targetPerDay,
  TimeOfDay? reminder,
  String note,
});

/// Creates or edits a habit.
///
/// One sheet for both because the fields are identical — a separate "edit"
/// screen would be the same form with a different button, and would drift.
class HabitEditorSheet extends StatefulWidget {
  const HabitEditorSheet({super.key, this.initial});

  /// The habit being edited, or null when creating one.
  final Habit? initial;

  /// Shows the sheet and resolves to the draft, or null if dismissed.
  static Future<HabitDraft?> show(BuildContext context, {Habit? initial}) {
    return showModalBottomSheet<HabitDraft>(
      context: context,
      isScrollControlled: true,
      // Leaves the top of the screen visible so the sheet still reads as a
      // sheet on a tall form.
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.92,
      ),
      builder: (_) => HabitEditorSheet(initial: initial),
    );
  }

  @override
  State<HabitEditorSheet> createState() => _HabitEditorSheetState();
}

class _HabitEditorSheetState extends State<HabitEditorSheet> {
  late final _titleController = TextEditingController(
    text: widget.initial?.title ?? '',
  );
  late final _noteController = TextEditingController(
    text: widget.initial?.note ?? '',
  );

  late IconData _icon = widget.initial?.icon ?? kHabitIcons['run']!;
  late Color _color = widget.initial?.color ?? kHabitPalette.first;
  late HabitSchedule _schedule =
      widget.initial?.schedule ?? const HabitSchedule.daily();
  late int _targetPerDay = widget.initial?.targetPerDay ?? 1;
  late TimeOfDay? _reminder = widget.initial?.reminder;

  bool get _isEditing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    // Keeps the submit button's enabled state in sync as the user types.
    _titleController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;

    // A "specific days" habit with nothing selected would never be due again,
    // so fall back to daily rather than quietly stranding it.
    final schedule =
        _schedule.frequency == HabitFrequency.specificDays &&
            _schedule.weekdays.isEmpty
        ? const HabitSchedule.daily()
        : _schedule;

    Navigator.pop(context, (
      title: title,
      icon: _icon,
      color: _color,
      schedule: schedule,
      targetPerDay: _targetPerDay,
      reminder: _reminder,
      note: _noteController.text.trim(),
    ));
  }

  Future<void> _pickReminder() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _reminder ?? const TimeOfDay(hour: 8, minute: 0),
    );
    if (picked != null) setState(() => _reminder = picked);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      // Lifts the sheet above the keyboard while typing.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                children: [
                  Text(
                    _isEditing ? 'Edit habit' : 'New habit',
                    style: textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _titleController,
                    autofocus: !_isEditing,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: 'What do you want to do?',
                      hintText: 'e.g. Walk 10,000 steps',
                      prefixIcon: Icon(_icon, color: _color),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _SectionLabel('Icon'),
                  const SizedBox(height: 8),
                  _IconPicker(
                    selected: _icon,
                    color: _color,
                    onSelect: (icon) => setState(() => _icon = icon),
                  ),
                  const SizedBox(height: 20),
                  _SectionLabel('Colour'),
                  const SizedBox(height: 8),
                  _ColourPicker(
                    selected: _color,
                    onSelect: (color) => setState(() => _color = color),
                  ),
                  const SizedBox(height: 24),
                  _SectionLabel('Repeat'),
                  const SizedBox(height: 8),
                  _FrequencyPicker(
                    schedule: _schedule,
                    accent: _color,
                    onChanged: (schedule) =>
                        setState(() => _schedule = schedule),
                  ),
                  const SizedBox(height: 24),
                  _SectionLabel('Daily goal'),
                  const SizedBox(height: 4),
                  _TargetStepper(
                    value: _targetPerDay,
                    onChanged: (value) => setState(() => _targetPerDay = value),
                  ),
                  const SizedBox(height: 16),
                  _SectionLabel('Reminder'),
                  const SizedBox(height: 4),
                  _ReminderRow(
                    reminder: _reminder,
                    onPick: _pickReminder,
                    onClear: () => setState(() => _reminder = null),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _noteController,
                    textCapitalization: TextCapitalization.sentences,
                    maxLength: 80,
                    decoration: const InputDecoration(
                      labelText: 'Note (optional)',
                      helperText: 'Shown in the reminder notification',
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _titleController.text.trim().isEmpty
                      ? null
                      : _submit,
                  style: FilledButton.styleFrom(backgroundColor: _color),
                  child: Text(_isEditing ? 'Save changes' : 'Add habit'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(context).textTheme.labelLarge?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );
}

class _IconPicker extends StatelessWidget {
  const _IconPicker({
    required this.selected,
    required this.color,
    required this.onSelect,
  });

  final IconData selected;
  final Color color;
  final ValueChanged<IconData> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: 96,
      child: GridView.count(
        crossAxisCount: 2,
        scrollDirection: Axis.horizontal,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        children: [
          for (final icon in kHabitIcons.values)
            _Swatch(
              isSelected: icon.codePoint == selected.codePoint,
              background: icon.codePoint == selected.codePoint
                  ? color
                  : scheme.surfaceContainerHighest,
              borderColor: icon.codePoint == selected.codePoint
                  ? color
                  : scheme.outlineVariant,
              onTap: () => onSelect(icon),
              child: Icon(
                icon,
                size: 20,
                color: icon.codePoint == selected.codePoint
                    ? Colors.white
                    : scheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

class _ColourPicker extends StatelessWidget {
  const _ColourPicker({required this.selected, required this.onSelect});

  final Color selected;
  final ValueChanged<Color> onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final color in kHabitPalette)
          _Swatch(
            isSelected: color == selected,
            background: color,
            borderColor: color == selected
                ? Theme.of(context).colorScheme.onSurface
                : Colors.transparent,
            onTap: () => onSelect(color),
            child: color == selected
                ? const Icon(Icons.check, size: 20, color: Colors.white)
                : const SizedBox.shrink(),
          ),
      ],
    );
  }
}

/// Square tile used by both pickers.
class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.isSelected,
    required this.background,
    required this.borderColor,
    required this.onTap,
    required this.child,
  });

  final bool isSelected;
  final Color background;
  final Color borderColor;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
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
            color: borderColor,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: child,
      ),
    );
  }
}

class _FrequencyPicker extends StatelessWidget {
  const _FrequencyPicker({
    required this.schedule,
    required this.accent,
    required this.onChanged,
  });

  final HabitSchedule schedule;
  final Color accent;
  final ValueChanged<HabitSchedule> onChanged;

  static const _dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<HabitFrequency>(
          segments: const [
            ButtonSegment(
              value: HabitFrequency.daily,
              label: Text('Daily'),
            ),
            ButtonSegment(
              value: HabitFrequency.specificDays,
              label: Text('Days'),
            ),
            ButtonSegment(
              value: HabitFrequency.timesPerWeek,
              label: Text('Weekly'),
            ),
          ],
          selected: {schedule.frequency},
          showSelectedIcon: false,
          onSelectionChanged: (selection) =>
              onChanged(schedule.copyWith(frequency: selection.first)),
        ),
        if (schedule.frequency == HabitFrequency.specificDays) ...[
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var weekday = 1; weekday <= 7; weekday++)
                _DayToggle(
                  label: _dayLabels[weekday - 1],
                  isSelected: schedule.weekdays.contains(weekday),
                  accent: accent,
                  onTap: () {
                    final next = Set<int>.of(schedule.weekdays);
                    if (!next.remove(weekday)) next.add(weekday);
                    onChanged(schedule.copyWith(weekdays: next));
                  },
                ),
            ],
          ),
          if (schedule.weekdays.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Pick at least one day, or this saves as daily.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.error,
                ),
              ),
            ),
        ],
        if (schedule.frequency == HabitFrequency.timesPerWeek) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${schedule.timesPerWeek} times a week',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              Slider(
                value: schedule.timesPerWeek.toDouble(),
                min: 1,
                max: 7,
                divisions: 6,
                label: '${schedule.timesPerWeek}',
                onChanged: (value) =>
                    onChanged(schedule.copyWith(timesPerWeek: value.round())),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _DayToggle extends StatelessWidget {
  const _DayToggle({
    required this.label,
    required this.isSelected,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isSelected ? accent : scheme.surfaceContainerHighest,
          border: Border.all(
            color: isSelected ? accent : scheme.outlineVariant,
          ),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: isSelected ? Colors.white : scheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// How many logs a day needs. One means a plain checkbox.
class _TargetStepper extends StatelessWidget {
  const _TargetStepper({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            value <= 1 ? 'Once — a simple tick' : '$value times a day',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        IconButton.filledTonal(
          onPressed: value <= 1 ? null : () => onChanged(value - 1),
          icon: const Icon(Icons.remove),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          onPressed: value >= 20 ? null : () => onChanged(value + 1),
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }
}

class _ReminderRow extends StatelessWidget {
  const _ReminderRow({
    required this.reminder,
    required this.onPick,
    required this.onClear,
  });

  final TimeOfDay? reminder;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final reminder = this.reminder;

    return Row(
      children: [
        Expanded(
          child: Text(
            // Deliberately not "every day": the schedule above decides which
            // days it repeats on, and this row only owns the time.
            reminder == null
                ? 'No reminder'
                : 'At ${reminder.format(context)} on scheduled days',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        if (reminder != null)
          IconButton(
            onPressed: onClear,
            icon: const Icon(Icons.clear),
            tooltip: 'Remove reminder',
          ),
        TextButton.icon(
          onPressed: onPick,
          icon: const Icon(Icons.alarm),
          label: Text(reminder == null ? 'Set' : 'Change'),
        ),
      ],
    );
  }
}
