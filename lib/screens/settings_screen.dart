import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_info.dart';
import '../services/backup_service.dart';
import '../state/habit_store.dart';
import '../state/settings_store.dart';
import '../state/tracker_store.dart';
import '../theme/app_theme.dart';
import 'archive_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settingsStore = SettingsScope.of(context);
    final habitStore = HabitScope.of(context);
    final settings = settingsStore.settings;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(title: const Text('Settings')),
          SliverList.list(
            children: [
              const _SectionHeader('Appearance'),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.light,
                      icon: Icon(Icons.light_mode_outlined),
                      label: Text('Light'),
                    ),
                    ButtonSegment(
                      value: ThemeMode.system,
                      icon: Icon(Icons.brightness_auto_outlined),
                      label: Text('Auto'),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      icon: Icon(Icons.dark_mode_outlined),
                      label: Text('Dark'),
                    ),
                  ],
                  selected: {settings.themeMode},
                  showSelectedIcon: false,
                  onSelectionChanged: (selection) =>
                      settingsStore.setThemeMode(selection.first),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Row(
                  children: [
                    for (final seed in kThemeSeeds)
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: _SeedSwatch(
                          seed: seed,
                          isSelected: seed.color == settings.seedColor,
                          onTap: () => settingsStore.setSeedColor(seed.color),
                        ),
                      ),
                  ],
                ),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.vibration),
                title: const Text('Haptic feedback'),
                subtitle: const Text('A small buzz when you tick something off'),
                value: settings.hapticsEnabled,
                onChanged: settingsStore.setHapticsEnabled,
              ),
              const Divider(height: 32),

              const _SectionHeader('Schedule'),
              ListTile(
                leading: const Icon(Icons.calendar_view_week),
                title: const Text('Week starts on'),
                trailing: SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: DateTime.monday, label: Text('Mon')),
                    ButtonSegment(value: DateTime.sunday, label: Text('Sun')),
                  ],
                  selected: {settings.weekStartsOn},
                  showSelectedIcon: false,
                  onSelectionChanged: (selection) =>
                      settingsStore.setWeekStartsOn(selection.first),
                ),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.notifications_outlined),
                title: const Text('Reminders'),
                subtitle: Text(
                  settings.remindersEnabled
                      ? 'Habits with a reminder time will notify you'
                      : 'All reminders are paused',
                ),
                value: settings.remindersEnabled,
                onChanged: (value) =>
                    _setReminders(context, settingsStore, habitStore, value),
              ),
              const Divider(height: 32),

              const _SectionHeader('Data'),
              ListTile(
                leading: const Icon(Icons.inventory_2_outlined),
                title: const Text('Archived habits'),
                subtitle: Text('${habitStore.archivedHabits.length} archived'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ArchiveScreen(),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.backup_outlined),
                title: const Text('Back up data'),
                subtitle: const Text('Copy everything as text you can save'),
                onTap: () => _exportBackup(context),
              ),
              ListTile(
                leading: const Icon(Icons.restore),
                title: const Text('Restore from backup'),
                subtitle: const Text('Replaces the habits on this device'),
                onTap: () => _importBackup(context),
              ),
              ListTile(
                leading: Icon(
                  Icons.delete_forever_outlined,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(
                  'Delete all data',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
                onTap: () => _confirmWipe(context),
              ),
              const Divider(height: 32),

              const _SectionHeader('About'),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('Version'),
                trailing: Text(kAppVersion),
              ),
              ListTile(
                leading: const Icon(Icons.privacy_tip_outlined),
                title: const Text('Privacy policy'),
                subtitle: const Text('Everything stays on this device'),
                onTap: () => _showPrivacyPolicy(context),
              ),
              const SizedBox(height: 96),
            ],
          ),
        ],
      ),
    );
  }

  /// Turning reminders on has to clear the Android 13+ runtime permission
  /// before the switch can honestly claim anything will arrive.
  Future<void> _setReminders(
    BuildContext context,
    SettingsStore settingsStore,
    HabitStore habitStore,
    bool enabled,
  ) async {
    if (!enabled) {
      await settingsStore.setRemindersEnabled(false);
      return;
    }

    final granted =
        await habitStore.notifications?.requestPermission() ?? false;
    await settingsStore.setRemindersEnabled(granted);

    if (!granted && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Notifications are blocked for HabitFlow. Turn them on in '
              'your system settings to use reminders.',
            ),
          ),
        );
    }
  }

  Future<void> _exportBackup(BuildContext context) async {
    final payload = BackupService.export(
      habits: HabitScope.of(context).allHabits,
      settings: SettingsScope.of(context).settings,
      trackers: TrackerScope.of(context).data,
    );

    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Back up data'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Copy this text somewhere safe. Pasting it into Restore on '
                'any device brings your habits back.',
              ),
              const SizedBox(height: 16),
              Flexible(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      dialogContext,
                    ).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      payload,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.copy_all),
            label: const Text('Copy'),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: payload));
              if (!dialogContext.mounted) return;
              Navigator.pop(dialogContext);
              ScaffoldMessenger.of(dialogContext)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  const SnackBar(content: Text('Backup copied to clipboard')),
                );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _importBackup(BuildContext context) async {
    final controller = TextEditingController();
    final habitStore = HabitScope.of(context);
    final settingsStore = SettingsScope.of(context);
    final trackerStore = TrackerScope.of(context);

    final raw = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Restore from backup'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Paste a HabitFlow backup. This replaces every habit currently '
              'on this device.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              maxLines: 6,
              minLines: 4,
              decoration: const InputDecoration(hintText: 'Paste backup text'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton.icon(
            icon: const Icon(Icons.content_paste),
            label: const Text('Paste'),
            onPressed: () async {
              final data = await Clipboard.getData(Clipboard.kTextPlain);
              controller.text = data?.text ?? '';
            },
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Restore'),
          ),
        ],
      ),
    );

    controller.dispose();
    if (raw == null || !context.mounted) return;

    try {
      final contents = BackupService.import(raw);
      habitStore.replaceAll(contents.habits);
      // Null means the backup predates the trackers. Leaving the existing logs
      // alone is the only safe reading of that: an old export must not be able
      // to silently delete six trackers' worth of history.
      if (contents.trackers != null) {
        trackerStore.replaceAll(contents.trackers!);
      }
      if (contents.settings != null) {
        // Onboarding is a property of this install, not of the backup.
        await settingsStore.update(
          contents.settings!.copyWith(onboardingComplete: true),
        );
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Restored ${contents.habits.length} habits'),
          ),
        );
    } on BackupFormatException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _confirmWipe(BuildContext context) async {
    final habitStore = HabitScope.of(context);
    final trackerStore = TrackerScope.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete all data?'),
        content: const Text(
          'Every habit, all of its history, and every tracker log — sleep, '
          'water, reading, food, focus and fitness — is removed from this '
          'device. This cannot be undone.',
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
            child: const Text('Delete everything'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await habitStore.clearAll();
    await trackerStore.clearAll();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('All data deleted')));
  }

  Future<void> _showPrivacyPolicy(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Privacy policy'),
        content: const SingleChildScrollView(
          child: Text(kPrivacyPolicyText),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
    child: Text(
      title,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: Theme.of(context).colorScheme.primary,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _SeedSwatch extends StatelessWidget {
  const _SeedSwatch({
    required this.seed,
    required this.isSelected,
    required this.onTap,
  });

  final ({String name, Color color}) seed;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: isSelected,
      button: true,
      label: seed.name,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: seed.color,
            shape: BoxShape.circle,
            border: Border.all(
              color: isSelected
                  ? Theme.of(context).colorScheme.onSurface
                  : Colors.transparent,
              width: 2,
            ),
          ),
          child: isSelected
              ? const Icon(Icons.check, size: 20, color: Colors.white)
              : null,
        ),
      ),
    );
  }
}
