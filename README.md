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

**The coach** — see [below](#the-coach) for how each part works
- Odds for every habit due today, fitted per habit from its own history
- A written briefing that puts the thing decided *today* at the top
- Concrete schedule changes, and retuned tracker targets, applied in one tap
- A profile of what your best days had in common

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

## The coach

Its own screen, reached from Today and from Insights. Five things feed it, all
computed on the device from the logs you already keep. Nothing here is generated
prose in the language-model sense — every sentence is assembled from numbers, on
a phone, offline, which is the only way a briefing can be both private and true.

**1. Today's odds** — a small naive-Bayes model per habit, fitted on every read.

It starts from a recency-weighted base rate (half-life a fortnight) and adds one
log-odds term per condition that holds today:

- the weekday — *"Thursdays run at 31% across 17 of them"*
- what happened the last day it was due, which is the one thing no chart shows:
  for some people a miss is a blip, for others it is the first domino
- whether its stack cue has already fired — counted only once it *has*, because
  an anchor still unticked at noon says nothing

Three guards keep it honest. Every term is **shrunk toward the base rate**, so a
condition seen four times contributes almost nothing and one seen thirty
contributes nearly its full weight. Every term is **clamped**, so no single
coincidence can swing the answer on its own. And the result **never reaches 0 or
100%** — people break their patterns, which is rather the point of tracking them.

Summed across the list it gives the line on Today: *about four of five by
tonight*. An expected count is the sum of the individual probabilities, which
holds whether or not the habits are independent — expectation is linear either
way.

**2. The briefing** — the four engines below, ordered.

Each one answers a narrow question well and none of them answers the one people
actually open the app with: *what should I do about today?* The ordering rule is
what makes it useful — **things that are decided today come first.** A streak
that breaks tonight outranks a mis-set target, however wrong the target is.

**3. Schedule changes** — the only part of the app that proposes, rather than
describes.

Three rules, one suggestion per habit, each applied in a tap and undoable:

- **Drop a weekday** when one is far below the rest and has a dozen chances
  behind it: *"Fridays run at 8% against 79% on your other days."*
- **Switch to a quota** when the habit happens often enough but never on a
  predictable day. The case this exists for is someone who genuinely goes to the
  gym four times most weeks, has five fixed days scheduled, and reads as a 70%
  failure forever. A quota is not a lower standard — it is the standard they are
  already meeting, written down accurately.
- **Ease or raise a quota** that the median week has been clear of in either
  direction for six weeks.

A schedule change moves what the app *expects*, not what you do: ease a quota and
tomorrow's percentage rises without a single extra thing being done. That is
worth doing when the plan is wrong, and worth knowing you did — so the screen
says it, and every suggestion names the trade.

**4. Targets** — the tracker goals, checked against what actually happened.

The defaults are public-health numbers: eight hours, two litres, a hundred and
fifty minutes. A fine place to start and a poor place to stay. A target nobody
reaches stops being a target and becomes a daily reminder of failing; one that is
cleared without noticing has quietly stopped asking for anything.

One rule produces both directions: the proposal is always **the level you would
have met on about six days in ten** — the 40th percentile of what you logged, or
the 60th for a ceiling like the eating window. Whether that is a step down or a
step up is a fact about the history, not a judgement about you.

**5. Blueprint of a good day** — a profile, where Discoveries is a pairing.

Discoveries asks "does sleep move mood?" one pair at a time. This asks the
question people actually have: *what does a good day look like for me?* It takes
the best third of days by habits kept, the worst third, and reports every other
signal that separates them:

> **Sleep above 7h 5m** — median 7h 40m on the good days against 6h 20m on the
> poor ones · 14 and 13 days

The target is the good days' *lower quartile*, not their median: a median target
is one half your own best days would have failed. Only things you control are
profiled — mood being higher on the days more habits got done is true, circular
and no use to anybody.

Comparing extremes flatters every gap it finds, so the threshold for a line is
stricter than the discovery search's, and the screen says to read it as a shape
rather than a measurement. It is also, as ever, correlation: a good day can cause
an early night as easily as the other way round.

**The lab**
- **Habit strength** — how ingrained each habit is, from consistency, recovery
  after a miss, time practised and evenness across the week
- **Projections** — a two-state Markov chain simulated forward, for streak odds
  and milestone arrivals rather than a single day's chance
- **Turning points** — change-point detection over the history, for the dates a
  habit genuinely changed level
- **Daily load** — what you actually finish as a function of how much you take
  on, and whether the last habit added is costing the others
- **Experiments** — a change declared in advance, judged against the stretch
  before it, with a window that cannot be moved once it starts

**The rest**
- Material 3 with six seed colours, light/dark/auto
- Backup and restore as plain text, so data can move between devices — the
  backup carries the tracker logs and the experiment log too
- Onboarding, haptics, week-start preference, full delete

## The lab

Its own screen, reached from Insights. The coach is about today; everything here
is about the arc a habit is on over months, which is a different reading pace and
does not belong interleaved with it.

**1. Habit strength** — how ingrained a habit is, which is not how it went lately.

Momentum already answers *"is this slipping right now"*. This answers the slower
question underneath it: *if next month got difficult, would this survive?* Those
come apart constantly — a habit kept flawlessly for eleven days has excellent
momentum and no strength, and a two-year habit having a shaky fortnight has the
reverse. Four components, reported separately because the total is only useful as
a way into whichever one is dragging it down:

- **consistency**, recency-weighted with a 45-day half-life — deliberately much
  slower than momentum's ten, or this would just be momentum again
- **resilience** — of the due days that followed a miss, how many were kept
- **tenure**, on a saturating curve scaled to 66 days (the median in Lally et
  al. 2010, the study the "21 days" claim is a mangling of — used to set the
  curve's shape, never quoted at you as a deadline)
- **regularity** — evenness across the weekdays the habit is actually due

Resilience is the one that earns its place. A 90% habit whose misses arrive in
runs is one bad week from being a 40% habit, and it reads as perfectly healthy
right up until it isn't: *"kept 87% of the time, but only 34% of the days after a
miss — one slip tends to become a run."* No average can show that.

**2. Projections** — where a habit is heading, simulated rather than averaged.

Streaks are path-dependent, so an average cannot answer questions about them. A
habit kept 80% of the time reaches a 30-day streak readily if its misses are
isolated and almost never if they cluster, and those two histories have identical
completion rates. So the simulation is a **two-state Markov chain**: the chance of
keeping the habit depends on whether the last due day was kept. Both rates are
fitted from the habit's own history, shrunk toward its base rate, and then 1,500
futures are rolled forward honouring the real schedule.

It reports the chance the current run survives the month, the odds and typical
arrival of the next milestone, and expected completions over the quarter. Two
deliberate refusals: a milestone a perfect run could not reach inside the horizon
is **not offered at all** rather than shown at 0%, and when fewer than half the
futures arrive, **no median is claimed** — reporting the median of only the runs
that worked answers a much rosier question than the one being asked.

**3. Turning points** — the dates a habit changed level.

Binary segmentation over the due days, treating each as a Bernoulli trial. For
every candidate split, "one rate throughout" is compared against "one rate before,
another after" by likelihood ratio; the best split survives only if it clears a
threshold that **rises with the number of positions searched**, because keeping
the best of many noisy statistics is the classic way to find change points in
pure noise. A minimum segment of 12 due days stops a bad fortnight counting as a
new level, and a minimum swing of 20 points stops a real-but-trivial shift being
reported at all.

Most habits have no turning points, and returning nothing for them is the feature
working. A rolling average would always move, and a person reading one will
always find a story in it.

**4. Daily load** — what you finish, by how much you take on.

Everything else in the app is about one habit. This is about the list, and the
failure it detects is invisible from inside any single habit: adding the eighth
habit does not make the eighth habit fail, it makes two of the other seven fail,
and each of those looks like an unrelated problem with its own explanation.

Days are grouped by how many habits were due and each group reports the mean
completed. Rising and still rising means headroom; flattening means the extra
habits are being carried for nothing; falling means they are displacing
completions that would otherwise have happened. Two caveats are printed on the
card rather than buried: this is observational, and a count of habits is not a
measure of effort.

**5. Experiments** — the only prospective thing in the app.

Every other analysis here is retrospective — it searches history for what stands
out, which is exactly the procedure that turns noise into findings if nobody is
careful. Discoveries applies corrections for this. An experiment sidesteps it
instead: the hypothesis, the window and the length are all fixed *before* any
evidence exists, so there is no search to correct for.

That is why **the window cannot be moved once a trial starts**. An experiment you
can stop when it looks good is not an experiment, it is a way of generating
flattering numbers, so ending one early marks it abandoned and it is never
scored. Abandoned runs stay in the log for the same reason: if the failures
disappeared, the survivors would be a filtered sample.

The comparison is a two-proportion test on due days, and the card leads with the
**interval**, not the p-value. *"Somewhere between −4 and +31 points"* is far
harder to misread than *"p = 0.09"*, and it answers the question people actually
have — how big is this, and how sure are we.

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
    blueprint.dart          what the best days had in common, built on it too
    forecast.dart           the per-habit odds model, and the day's expectation
    schedule_coach.dart     schedule changes the history argues for
    goal_coach.dart         tracker targets retuned to what is being hit
    briefing.dart           all of the above, ordered into a paragraph
    lab/                    the slow questions: months, not today
      automaticity.dart     how ingrained a habit is, and what holds it back
      projection.dart       Markov chain + Monte Carlo, for streaks ahead
      turning_point.dart    change-point detection over the due days
      capacity.dart         what gets finished, by how much is taken on
      experiment.dart       a pre-registered trial and its two-proportion test
      experiment_data.dart  the experiment log's own versioned codec
    trackers/               one file per tracker: entry type + its metrics
      tracker_data.dart     the whole tracker snapshot, and its codec
      tracker_goals.dart    every target, plus duration/clock formatting
      tracker_kind.dart     which trackers exist, and how each presents itself
  screens/                  home, insights, detail, settings, archive,
                            onboarding, weekly review, coach, lab, experiments
    trackers/               the hub, the six tracker screens, and targets
  services/                 notifications, backup encode/decode
  state/                    HabitStore, SettingsStore, TrackerStore,
                            ExperimentStore
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
- **Analytics are derived, never stored.** Momentum, correlations, badges, the
  review and every forecast are computed from `entries` on every read, so
  restoring a backup lights up exactly what the history has earned and nothing
  can drift. The forecast model in particular is *fitted* on each read rather
  than trained and saved: there are no weights to persist, migrate or corrupt,
  and no way for a stale model to outlive the history it came from.
- **Nothing changes itself.** The coach proposes schedule and target changes and
  never applies one. A tracker that quietly lowered your goals overnight would be
  a tracker whose numbers meant nothing.

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
flutter test          # 389 tests
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
