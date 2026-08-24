import 'package:flutter/material.dart';

import 'data/app_repository.dart';
import 'screens/onboarding_screen.dart';
import 'screens/root_shell.dart';
import 'services/notification_service.dart';
import 'state/habit_store.dart';
import 'state/settings_store.dart';
import 'theme/app_theme.dart';

/// Root widget: owns the two stores, wires them to the repository and picks the
/// first screen once both have loaded.
class HabitFlowApp extends StatefulWidget {
  const HabitFlowApp({
    super.key,
    required this.repository,
    this.notifications,
    this.saveDebounce = const Duration(milliseconds: 350),
  });

  final AppRepository repository;
  final NotificationService? notifications;
  final Duration saveDebounce;

  @override
  State<HabitFlowApp> createState() => _HabitFlowAppState();
}

class _HabitFlowAppState extends State<HabitFlowApp> {
  // Owned here so they outlive navigation and are disposed with the app.
  late final SettingsStore _settings = SettingsStore(
    repository: widget.repository,
  );
  late final HabitStore _habits = HabitStore(
    repository: widget.repository,
    notifications: widget.notifications,
    saveDebounce: widget.saveDebounce,
  );

  @override
  void initState() {
    super.initState();
    _settings.addListener(_syncReminderSwitch);
    _bootstrap();
  }

  @override
  void dispose() {
    _settings.removeListener(_syncReminderSwitch);
    _habits.dispose();
    _settings.dispose();
    super.dispose();
  }

  /// Settings must land before habits: the master reminder switch decides
  /// whether loading habits should schedule anything at all.
  Future<void> _bootstrap() async {
    await _settings.load();
    await _habits.setRemindersEnabled(_settings.settings.remindersEnabled);
    await _habits.load();
  }

  void _syncReminderSwitch() {
    _habits.setRemindersEnabled(_settings.settings.remindersEnabled);
  }

  @override
  Widget build(BuildContext context) {
    return SettingsScope(
      store: _settings,
      child: HabitScope(
        store: _habits,
        // MaterialApp sits *inside* a listener because the theme is rebuilt
        // from settings; an InheritedNotifier above it would never reach it.
        child: ListenableBuilder(
          listenable: _settings,
          builder: (context, _) {
            final settings = _settings.settings;
            return MaterialApp(
              title: 'HabitFlow',
              debugShowCheckedModeBanner: false,
              themeMode: settings.themeMode,
              theme: buildAppTheme(
                brightness: Brightness.light,
                seed: settings.seedColor,
              ),
              darkTheme: buildAppTheme(
                brightness: Brightness.dark,
                seed: settings.seedColor,
              ),
              home: const _StartupGate(),
            );
          },
        ),
      ),
    );
  }
}

/// Holds a splash until both stores have loaded, then routes to onboarding or
/// the app proper.
class _StartupGate extends StatelessWidget {
  const _StartupGate();

  @override
  Widget build(BuildContext context) {
    final habits = HabitScope.of(context);
    final settings = SettingsScope.of(context);

    if (habits.isLoading || settings.isLoading) return const _SplashScreen();
    if (!settings.settings.onboardingComplete) return const OnboardingScreen();
    return const RootShell();
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_graph, size: 56, color: scheme.primary),
            const SizedBox(height: 20),
            SizedBox(
              width: 96,
              child: LinearProgressIndicator(
                minHeight: 3,
                backgroundColor: scheme.surfaceContainerHighest,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
