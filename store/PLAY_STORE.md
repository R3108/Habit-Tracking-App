# Play Store release guide — HabitFlow

Application ID: **`com.riddhiman.habitflow`** (permanent once published)

---

## 1. One-time setup

### Upload keystore

```bat
keytool -genkey -v -keystore %USERPROFILE%\habitflow-upload.jks ^
  -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Copy `android/key.properties.example` to `android/key.properties` and fill in
the four values. Both the `.jks` and `key.properties` are git-ignored.

> Back the keystore up offline. Losing it means the app can never be updated
> again unless Play App Signing is enabled and Google resets the upload key.

The build reads `key.properties` if it exists and falls back to debug signing if
it doesn't — so a missing keystore produces a *runnable but unpublishable*
build rather than a build failure. Check the signing before uploading:

```bat
keytool -printcert -jarfile build\app\outputs\bundle\release\app-release.aab
```

### Play Console

- Create the app, set it to **Free**, category **Health & Fitness**.
- Enable **Play App Signing** (recommended — Google holds the signing key and
  the upload key stays recoverable).

---

## 2. Every release

1. Bump `version:` in `pubspec.yaml` — `1.0.0+1` → `1.0.1+2`. The build number
   after `+` becomes `versionCode` and **must increase on every upload**.
2. `flutter test && flutter analyze`
3. `flutter build appbundle --release`
4. Upload `build/app/outputs/bundle/release/app-release.aab`
5. Upload `build/app/outputs/mapping/release/mapping.txt` in the same release,
   or Play Console crash reports stay obfuscated.

---

## 3. Store listing copy

**App name (30 max)**

```
HabitFlow: Habit Tracker
```

**Short description (80 max)**

```
Offline habit tracker with sleep, water, food, focus and fitness built in.
```

**Full description (4000 max)**

```
HabitFlow helps you build habits that stick — and keeps every bit of it on your
own phone. No account, no sign-up, no servers, no ads.

TRACK WHAT MATTERS
• Simple tick-off habits, or counted ones like "drink 8 glasses of water"
• Repeat every day, on chosen weekdays, or a flexible number of times a week
• Forgot to log yesterday? Step back a day and fix it in one tap
• Archive a habit to pause it without losing its history

STREAKS THAT ARE HONEST
Your streak only counts the days you actually scheduled. A gym habit set to
Monday, Wednesday and Friday keeps its streak straight through the weekend
instead of breaking every Saturday.

SEE THE WHOLE PICTURE
• A colour-coded heatmap of the last twenty weeks
• Completion rate by weekday, so you can see which day keeps tripping you up
• Current and best streak, total completions and a 30-day success rate
• Ten milestones to unlock as your history grows

SIX BUILT-IN TRACKERS
• Sleep — hours, bedtime regularity, sleep debt and weekend body-clock drift
• Water — one tap per drink, plus whether you're ahead or behind for the hour
• Reading — pages and minutes, a reading speed, and a finish date for your book
• Food — meal times, your eating window, and balance without calorie counting
• Focus — a Pomodoro timer, and where your deep work actually went
• Fitness — active minutes, and whether this week is more than you're used to

GENTLE REMINDERS
Give any habit a time and HabitFlow will nudge you on the days it's due.
Reminders survive a restart and can be paused whenever you like.

YOURS, AND ONLY YOURS
HabitFlow never talks to the internet. There is nothing to sign up for and
nothing to leak. Back up your data as plain text whenever you want, and delete
all of it in two taps.

Material You design, light and dark themes, six accent colours.
```

**Tags:** habit tracker, streak, routine, daily goals, self improvement

---

## 4. Data safety form

Answer as follows — all of it is verifiable from the source:

| Question | Answer |
|---|---|
| Does your app collect or share any user data? | **No** |
| Is all user data encrypted in transit? | N/A (no data leaves the device) |
| Do you provide a way to request data deletion? | **Yes** — Settings › Delete all data |

### Health data — read this before submitting

Since 1.1.0 the app stores sleep times, meals, and workouts. That is health and
fitness data, and it changes what needs checking even though the answers above
stay the same:

- Play's data-safety form defines *collection* as transmitting data off the
  device. Nothing here is transmitted, so **No** remains correct — but the claim
  now covers health data, so the "no `INTERNET` permission" check below is more
  load-bearing than it was. Re-run it every release.
- The app touches **no** health platform: no Health Connect, no Google Fit, no
  sensors, no `BODY_SENSORS`, no `ACTIVITY_RECOGNITION`. Every figure is typed in
  by the user. The Health Connect declaration form therefore does not apply —
  **verify this is still true** before each submission, because adding a step
  counter or a Health Connect read would pull the app into that policy and
  require the declaration form plus a demo video.
- The category is already **Health & Fitness**, which is still right.
- `PRIVACY_POLICY.md` enumerates the health data explicitly. Play checks the
  policy against the form; keep the two in step.

The app gives no medical advice and makes no diagnostic claim. The one place it
comes close is the fitness screen's training-load ratio, which is worded as an
observation about the user's own logged history rather than as guidance.

The app makes no network requests. `INTERNET` is not declared in the app's own
manifest; verify what the merged manifest ends up with before submitting:

```bat
findstr /C:"uses-permission" build\app\intermediates\merged_manifests\release\AndroidManifest.xml
```

Verified on the 1.0.0 build — the merged manifest contains exactly:

```
android.permission.POST_NOTIFICATIONS
android.permission.RECEIVE_BOOT_COMPLETED
android.permission.VIBRATE
com.riddhiman.habitflow.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION
```

The last one is added by AndroidX Core. It is signature-level and app-private —
it lets the app's own broadcast receivers stay unexported — and needs no
justification on the listing.

Re-check after adding any plugin. If one pulls in `INTERNET`, remove it
explicitly so the no-data-collection claim stays true:

```xml
<uses-permission android:name="android.permission.INTERNET" tools:node="remove" />
```

### Permissions declaration

No sensitive permission is used, so **no declaration form is required**.

This is deliberate: reminders are scheduled with
`AndroidScheduleMode.inexactAllowWhileIdle`, so the app needs neither
`SCHEDULE_EXACT_ALARM` nor `USE_EXACT_ALARM` — both of which trigger a Play
review and can be revoked by the user. The cost is that a reminder may arrive a
few minutes late, which for a habit nudge is not worth a policy review.

---

## 5. Assets checklist

| Asset | Requirement | Status |
|---|---|---|
| App icon | 512×512 PNG, 32-bit, no transparency | ✅ `store/icon-512.png` |
| Feature graphic | 1024×500 PNG/JPG | ⬜ **to create** |
| Phone screenshots | 2–8, min 320px, 16:9 or 9:16 | ⬜ **to capture** |
| Privacy policy URL | publicly reachable | ⬜ **to host** |

### Screenshots

Capture on a device or emulator:

```bat
flutter run --release
adb exec-out screencap -p > store\screenshot-1.png
```

Worth showing, in order: the Today list with a few streaks running, the insights
heatmap, a habit's detail calendar, the editor with a weekday schedule.

### Privacy policy

`PRIVACY_POLICY.md` in the repo root is the text to publish. It needs a public
URL — GitHub Pages is the least-effort option:

1. Push the repo to GitHub.
2. Settings › Pages → deploy from `main`.
3. Put the policy at `docs/privacy.md`.
4. Set `kPrivacyPolicyUrl` in `lib/app_info.dart` to the resulting URL and use
   the same URL in the Play Console listing.

---

## 6. Pre-launch checks

Verified for 1.0.0 on 24 Aug 2026:

- [x] `flutter test` — 249 passing
- [x] `flutter analyze` — clean
- [x] `flutter build appbundle --release` — `app-release.aab`, 50.3 MB
- [x] Merged manifest declares no `INTERNET` permission
- [x] Material icon font tree-shaken to 11.6 KB (99.3% smaller)

Still to do before the first upload:

- [ ] Real upload keystore in `android/key.properties` — the bundle above is
      **debug-signed** and Play will reject it
- [ ] Release build installs and opens on a physical device
- [ ] Add a habit, restart the app, confirm it is still there
- [ ] Set a reminder a couple of minutes out and confirm it fires
- [ ] Toggle dark mode and check every screen
- [ ] Back up, delete all data, restore — history comes back intact
- [ ] Feature graphic and screenshots
- [ ] Privacy policy hosted at a public URL

### Regression checks for each later release

- [ ] `flutter test` passes
- [ ] `flutter analyze` clean
- [ ] Release build installs and opens on a physical device
- [ ] Add a habit, restart the app, confirm it is still there
- [ ] Set a reminder a couple of minutes out and confirm it fires
- [ ] Toggle dark mode and check every screen
- [ ] Back up, delete all data, restore — history comes back intact
- [ ] Version code is higher than the last upload
- [ ] `mapping.txt` uploaded with the bundle
