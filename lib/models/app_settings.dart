import 'package:flutter/material.dart';

/// User-facing preferences, persisted separately from habit data so a backup
/// restore can bring history back without overwriting how the app looks.
@immutable
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.seedColor = const Color(0xFF2E7D32),
    this.weekStartsOn = DateTime.monday,
    this.remindersEnabled = true,
    this.hapticsEnabled = true,
    this.onboardingComplete = false,
  });

  final ThemeMode themeMode;

  /// Drives the whole Material 3 colour scheme.
  final Color seedColor;

  /// ISO weekday the week grid starts on: [DateTime.monday] or
  /// [DateTime.sunday].
  final int weekStartsOn;

  /// Master switch. Turning it off cancels every scheduled reminder without
  /// forgetting the per-habit times, so turning it back on restores them.
  final bool remindersEnabled;

  final bool hapticsEnabled;
  final bool onboardingComplete;

  AppSettings copyWith({
    ThemeMode? themeMode,
    Color? seedColor,
    int? weekStartsOn,
    bool? remindersEnabled,
    bool? hapticsEnabled,
    bool? onboardingComplete,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      seedColor: seedColor ?? this.seedColor,
      weekStartsOn: weekStartsOn ?? this.weekStartsOn,
      remindersEnabled: remindersEnabled ?? this.remindersEnabled,
      hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
      onboardingComplete: onboardingComplete ?? this.onboardingComplete,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.themeMode == themeMode &&
      other.seedColor == seedColor &&
      other.weekStartsOn == weekStartsOn &&
      other.remindersEnabled == remindersEnabled &&
      other.hapticsEnabled == hapticsEnabled &&
      other.onboardingComplete == onboardingComplete;

  @override
  int get hashCode => Object.hash(
    themeMode,
    seedColor,
    weekStartsOn,
    remindersEnabled,
    hapticsEnabled,
    onboardingComplete,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'themeMode': themeMode.name,
    'seedColor': seedColor.toARGB32(),
    'weekStartsOn': weekStartsOn,
    'remindersEnabled': remindersEnabled,
    'hapticsEnabled': hapticsEnabled,
    'onboardingComplete': onboardingComplete,
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final weekStart = (json['weekStartsOn'] as num?)?.toInt();

    return AppSettings(
      themeMode: ThemeMode.values.firstWhere(
        (m) => m.name == json['themeMode'],
        orElse: () => ThemeMode.system,
      ),
      seedColor: Color((json['seedColor'] as num?)?.toInt() ?? 0xFF2E7D32),
      weekStartsOn: weekStart == DateTime.sunday
          ? DateTime.sunday
          : DateTime.monday,
      remindersEnabled: json['remindersEnabled'] as bool? ?? true,
      hapticsEnabled: json['hapticsEnabled'] as bool? ?? true,
      onboardingComplete: json['onboardingComplete'] as bool? ?? false,
    );
  }
}
