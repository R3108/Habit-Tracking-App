# HabitFlow

A private, offline habit tracker for Android. Habits, schedules and history live
only on the device — no accounts, no servers, no analytics, no network calls.

Package: `com.riddhiman.habitflow` · Flutter 3.47 · Dart 3.13

## Features

**Tracking**
- Yes/no habits and counted habits ("drink water 8×") with a progress ring
- Three schedules: every day, chosen weekdays, or a flexible weekly quota
- A rolling seven-day strip for catching up on a day you forgot to tick
- Swipe to delete with undo; archive to hide a habit but keep its history
- Edit anything after the fact, including the schedule

**Streaks and insights**
- Current and best streak per habit, counting only days the schedule asked for —
  rest days step over, they don't break the run
- A contribution heatmap of the last 20 weeks
- Completion rate by weekday, to show where the misses cluster
- Ten milestone badges, derived from history rather than stored

**Reminders**
- Per-habit reminder times, repeated on that habit's scheduled weekdays
- Scheduled *inexactly* on purpose, so the app needs no exact-alarm permission
- Survive a reboot; a master switch pauses them without forgetting the times

**The rest**
- Material 3 with six seed colours, light/dark/auto
- Backup and restore as plain text, so data can move between devices
- Onboarding, haptics, week-start preference, full delete

## Project layout

```
lib/
  app.dart                  root widget; owns both stores and the startup gate
  app_info.dart             version, privacy policy text
  data/app_repository.dart  persistence boundary + shared-preferences impl
  models/                   Habit, HabitSchedule, AppSettings, insights, badges
  screens/                  home, insights, detail, settings, archive, onboarding
  services/                 notifications, backup encode/decode
  state/                    HabitStore, SettingsStore (ChangeNotifier + scopes)
  theme/app_theme.dart      Material 3 theme from a seed colour
  util/haptics.dart         feedback that respects the user's setting
  widgets/                  cards, pickers, heatmap, charts, calendar
```

Two rules the code sticks to:

- **Persistence never blocks the UI.** Mutations apply to the in-memory list
  synchronously; the write to disk is debounced behind them.
- **Icons are const.** Habit icons are stored by key against a fixed catalogue
  (`models/habit_icons.dart`). A single runtime-built `IconData` would break
  release builds, which tree-shake the Material icon font.

## Running it

```bash
flutter pub get
flutter test          # 63 tests
flutter analyze       # clean
flutter run
```

### Windows build notes

Two environment quirks on this machine, neither of them project bugs:

- `flutter pub get` needs **Developer Mode** enabled for plugin symlinks:
  `start ms-settings:developers`.
- **Avast's Web/Mail Shield** intercepts HTTPS and re-signs certificates with
  its own root CA. Windows trusts it, the JDK doesn't, so every Gradle and
  `sdkmanager` download fails with `PKIX path building failed`. Fixed in
  `%USERPROFILE%\.gradle\gradle.properties`, which points the JVM at a copy of
  the JDK truststore with the Avast root imported. That file documents how to
  rebuild it, and it can be deleted if HTTPS scanning is ever turned off.

## Shipping to Play

See [`store/PLAY_STORE.md`](store/PLAY_STORE.md) for the release checklist,
listing copy and the data-safety answers.

Short version:

1. Create the upload keystore and `android/key.properties`
   (see `android/key.properties.example`).
2. Bump `version:` in `pubspec.yaml`.
3. `flutter build appbundle --release`
4. Upload `build/app/outputs/bundle/release/app-release.aab`, plus the mapping
   file from `build/app/outputs/mapping/release/mapping.txt`.
