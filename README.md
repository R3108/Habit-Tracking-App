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

**Habit stacking**
- Anchor a habit to one you already keep: "after I meditate, I read"
- The card names its cue, and lights up the moment the anchor is ticked
- Cycles are refused, and a deleted anchor degrades to no anchor rather than
  stranding its followers

**Planned days off**
- Mark a day as deliberately off — illness, holiday, a rest week
- It stops being due, so it neither breaks the streak nor dents the completion
  rate: it is stepped over exactly like a day the schedule never asked for
- Set from the habit menu for today, or by long-pressing any day in the calendar
- Exists so that protecting a 40-day streak through a week's flu doesn't require
  lying to the app

**Momentum**
- A recency-weighted completion score per habit, half-life ten days, measured
  over due days only
- The flat 30-day rate says a habit dropped nine days ago is "70% healthy";
  momentum says it is collapsing, while that is still fixable
- Drives a focus card on Today, which surfaces a live streak about to break —
  and stays hidden on a short list, where it would just be the list twice

**Connections**
- Pairwise correlation between habits, computed on the device: "you finish
  Reading on 82% of the days you run, against 31% of the days you don't"
- Reported only when both piles of days are big enough to mean something
- Phrased as an observation throughout, because it is correlation and nothing
  more

**Weekly review**
- A written summary of the last seven days, generated from the history: what
  moved, which habit is climbing, which is slipping, the weakest weekday, one
  correlation, and the next badge
- A *rolling* seven days against the seven before, not the calendar week —
  otherwise every Monday morning compares two days against seven and reports a
  collapse

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
    momentum.dart           recency-weighted score, trend, risk, focus list
    synergy.dart            pairwise correlation between habits
    weekly_review.dart      the written seven-day summary
  screens/                  home, insights, detail, settings, archive,
                            onboarding, weekly review
  services/                 notifications, backup encode/decode
  state/                    HabitStore, SettingsStore (ChangeNotifier + scopes)
  theme/app_theme.dart      Material 3 theme from a seed colour
  util/haptics.dart         feedback that respects the user's setting
  widgets/                  cards, pickers, heatmap, charts, calendar, focus
```

Rules the code sticks to:

- **Persistence never blocks the UI.** Mutations apply to the in-memory list
  synchronously; the write to disk is debounced behind them.
- **Icons are const.** Habit icons are stored by key against a fixed catalogue
  (`models/habit_icons.dart`). A single runtime-built `IconData` would break
  release builds, which tree-shake the Material icon font.
- **`Habit.isDueOn` is the only question worth asking.** Three separate things
  excuse a day — the habit did not exist yet, the schedule skips it, the user
  planned it off — and every caller wants all three. `HabitSchedule.isDueOn`
  answers only the middle one, and reaching for it directly is how a day off
  ends up counted as a miss.
- **Analytics are derived, never stored.** Momentum, correlations, badges and
  the review are computed from `entries` on every read, so restoring a backup
  lights up exactly what the history has earned and nothing can drift.

The on-disk schema is versioned (`kSchemaVersion`, currently 2). v2 added
`anchorId` and `skipped`; both are absent-means-default, so v1 payloads still
decode without a migration branch.

## Running it

```bash
flutter pub get
flutter test          # 156 tests
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
