# HabitFlow

A private, offline habit and wellbeing tracker for Android. Habits, schedules,
history and every tracker log live only on the device — no accounts, no servers,
no analytics, no network calls.

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

## The six trackers

A second top-level tab. These are not habits with extra fields — each needs a
shape the day-by-day tick model cannot express (two clock times, a book title, a
set of meal tags), so each gets its own typed model and its own screen. They sit
alongside the habit list rather than replacing any of it.

The interesting part of each is the metric a plain log cannot give you:

**Sleep** — bedtime, wake time, a quality rating.
- Filed under the morning the night *ended*, so a 01:30 bedtime is not a skipped
  night and two naps are not two nights
- **Sleep debt** over 14 nights, floored per night: a ten-hour Sunday does not
  repay a four-hour Tuesday
- **Bedtime consistency**, 0–100, from the spread of bedtimes. Bedtimes either
  side of midnight are mapped onto one continuous scale first — on a raw clock,
  23:50 and 00:10 look twenty hours apart and wreck every average taken over them
- **Social jetlag** — how far the midpoint of sleep shifts between work nights
  and free nights. Reported only with at least two of each; one Saturday against
  nine weekdays is an anecdote

**Water** — one tap per drink, fixed sizes rather than a number pad.
- **Pace**: how much a steady drinker would have had by *this hour*, spread over
  07:00–23:00 rather than midnight to midnight
- The only tracker here that judges a day before it ends, which is justified
  because being 400 ml down at 3pm is fixable by 4pm

**Reading** — book, pages, minutes.
- Pages *and* minutes, because either alone says nothing: the two together give
  a **reading speed** (pooled over timed sittings, so an untimed one cannot
  inflate it)
- Tell it how long a book is and it projects a **finish date** from your
  pages-per-day — how fast you read matters far less than whether you open it

**Food** — meal times and tags, no calorie counting.
- A calorie count needs a food database, a network call and an account. What
  somebody can answer honestly in three seconds at the table is whether there
  were vegetables on the plate
- **Eating window** from first meal to last — the number time-restricted eating
  is actually about, and one nobody works out in their head
- A coarse nourishing/indulgent balance. Deliberately coarse: a tracker precise
  enough to argue with is one people start lying to

**Focus** — a Pomodoro timer and the log of work it produces.
- The timer stores a *start time*, not a countdown, so it survives the app being
  killed and is still right when you come back
- Only completed focus phases are recorded. Breaks are not work, and a session
  abandoned after four minutes is not a pomodoro
- Minutes per tag, so "where did the week go" has an answer

**Fitness** — type, duration, effort.
- **Active minutes** counts moderate and above only, because the weekly
  guideline it is measured against is about moderate activity
- Load is minutes × effort, so twenty minutes flat out and an hour's stroll do
  not read as the same session
- **Acute:chronic load ratio** — this week's load against the four-week weekly
  average. Sharp jumps are where overuse injuries come from. Withheld entirely
  until there is a month of history, because the ratio is meaningless without a
  baseline and inventing one is worse than admitting you don't know yet

**Check-in** — mood and energy, 1–5 each.
- The only thing here that measures how a day *went* rather than what was done,
  which makes it the outcome everything else can be tested against
- Five points, not ten: nobody can reliably tell a 6 from a 7 about their own
  Tuesday, and a scale finer than the judgement behind it only adds noise
- One tap is enough — the other half defaults to the middle

**Your own trackers** — anything the six do not cover.
- Four shapes: a count, a duration, an amount with a unit you name, or a 1–5
  rating
- **Lower is better** flips the target into a ceiling, for the things you want
  less of. The progress bar empties as the number climbs, so a full bar always
  means "good day" whichever direction the tracker runs
- A day with no entry is *unknown*, not zero. For a ceiling tracker those are
  opposites, and conflating them would score every unlogged day as perfect

## Discoveries

The six trackers, the check-in, your own trackers and the habit list all
recorded different things in different shapes, and nothing could be compared
with anything else until they shared a form. `DailySignal` is that form: a
label, a unit, and a sparse day → value map. Sparse matters — an unlogged day is
unknown, not zero, and treating it as zero would invent bad days that never
happened.

With that in place, every signal can be compared against every other:

> On days your sleep was above 7h 10m, your mood averaged 4.2/5 — against
> 2.8/5 on the rest. *Strong difference · 24 days compared.*

A median split rather than a correlation coefficient, because nobody can
sanity-check an *r* of 0.41 against their own memory and everybody can
sanity-check "my good sleep days were better".

This is an exploratory search, and the honest way to build one is to admit what
that costs. With a dozen signals there are over a hundred ordered pairs; test
them all loosely and a few will look striking by luck alone. Four things hold
that down:

1. A **medium effect size** is required — not mere statistical significance.
2. Each unordered pair yields **at most one finding**, so the same relationship
   cannot appear twice wearing different hats.
3. The list is **capped**, so a quiet month cannot be padded out with the least
   convincing results.
4. **No time lags are tested.** "Did Monday's workout affect Tuesday's sleep" is
   a genuinely interesting question, and adding it would double the comparisons
   for one extra answer — a bad trade against false positives.

What survives is a pattern in one person's logs, not a finding about people. The
UI says so, and every string is phrased as an observation.

**The rest**
- Material 3 with six seed colours, light/dark/auto
- Backup and restore as plain text, so data can move between devices — the
  backup carries the tracker logs too
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
    daily_signal.dart       one shape everything in the app can be read as
    discovery.dart          the cross-tracker search built on it
    trackers/               one file per tracker: entry type + its metrics
      tracker_data.dart     the whole tracker snapshot, and its codec
      tracker_goals.dart    every target, plus duration/clock formatting
      tracker_kind.dart     which trackers exist, and how each presents itself
  screens/                  home, insights, detail, settings, archive,
                            onboarding, weekly review
    trackers/               the hub, the six tracker screens, and targets
  services/                 notifications, backup encode/decode
  state/                    HabitStore, SettingsStore, TrackerStore
                            (ChangeNotifier + scopes)
  theme/app_theme.dart      Material 3 theme from a seed colour
  util/haptics.dart         feedback that respects the user's setting
  widgets/                  cards, pickers, heatmap, charts, calendar, focus
    trackers/               ring, mini bar chart, card, stat row, empty state
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

Two on-disk schemas, versioned independently because they live under different
preference keys and can move separately:

- `kSchemaVersion` (habits), currently **2**. v2 added `anchorId` and `skipped`;
  both are absent-means-default, so v1 payloads still decode without a migration
  branch.
- `kTrackerSchemaVersion` (trackers), currently **2**. v2 added `checkIns`,
  `customTrackers` and `customEntries`, all absent-means-empty.

A backup carries both. The tracker section is optional and separately versioned,
so a backup written before the trackers existed restores its habits and leaves
the logs alone — `BackupContents.trackers` is null in that case, and null means
"leave what is there", never "wipe six trackers".

## Running it

```bash
flutter pub get
flutter test          # 311 tests
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
