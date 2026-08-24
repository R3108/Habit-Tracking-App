import 'package:flutter/material.dart';

import '../data/app_repository.dart';
import '../models/app_settings.dart';

/// Owns [AppSettings] and writes each change straight through.
///
/// Settings change one tap at a time, so there's nothing to debounce here —
/// unlike habit ticks, which can arrive in bursts.
class SettingsStore extends ChangeNotifier {
  SettingsStore({required this.repository, AppSettings? initial})
    : _settings = initial ?? const AppSettings();

  final AppRepository repository;
  AppSettings _settings;
  var _isLoading = true;

  AppSettings get settings => _settings;
  bool get isLoading => _isLoading;

  Future<void> load() async {
    _settings = await repository.loadSettings() ?? const AppSettings();
    _isLoading = false;
    notifyListeners();
  }

  Future<void> update(AppSettings next) async {
    if (next == _settings) return;
    _settings = next;
    notifyListeners();
    await repository.saveSettings(next);
  }

  Future<void> setThemeMode(ThemeMode mode) =>
      update(_settings.copyWith(themeMode: mode));

  Future<void> setSeedColor(Color color) =>
      update(_settings.copyWith(seedColor: color));

  Future<void> setWeekStartsOn(int weekday) =>
      update(_settings.copyWith(weekStartsOn: weekday));

  Future<void> setRemindersEnabled(bool enabled) =>
      update(_settings.copyWith(remindersEnabled: enabled));

  Future<void> setHapticsEnabled(bool enabled) =>
      update(_settings.copyWith(hapticsEnabled: enabled));

  Future<void> completeOnboarding() =>
      update(_settings.copyWith(onboardingComplete: true));
}

/// Exposes a [SettingsStore] to the subtree and rebuilds dependents on change.
class SettingsScope extends InheritedNotifier<SettingsStore> {
  const SettingsScope({
    super.key,
    required SettingsStore store,
    required super.child,
  }) : super(notifier: store);

  static SettingsStore of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<SettingsScope>();
    assert(scope?.notifier != null, 'No SettingsScope found above this widget');
    return scope!.notifier!;
  }
}
