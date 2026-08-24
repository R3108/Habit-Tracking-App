/// Marketing version shown in Settings › About.
///
/// Kept in sync by hand with `version:` in pubspec.yaml. The alternative is
/// another plugin dependency to read the package metadata at runtime, which is
/// a lot of machinery for one string.
const String kAppVersion = '1.0.0';

const String kAppName = 'HabitFlow';

/// Where the Play listing points for the privacy policy.
///
/// Google Play requires a reachable URL on the store listing; the same text is
/// shipped in-app so the app is usable offline and the two can't drift.
const String kPrivacyPolicyUrl =
    'https://riddhiman.github.io/habitflow/privacy';

/// Shown verbatim in Settings › Privacy policy.
const String kPrivacyPolicyText = '''
HabitFlow stores everything you enter — your habits, their schedules and your
completion history — locally on this device. Nothing is uploaded, and the app
has no servers, accounts or analytics.

WHAT IS COLLECTED
Nothing. The app makes no network requests of any kind.

WHAT IS STORED ON YOUR DEVICE
• The habits you create, including title, icon, colour, schedule and note.
• The days you have marked each habit complete.
• Your app preferences, such as theme and reminder settings.

PERMISSIONS
• Notifications — used only to show the reminders you schedule yourself.
  Declining it disables reminders and nothing else.

SHARING
Your data is never shared with anyone. The backup feature copies your data to
your clipboard only when you explicitly ask for it, and where it goes from
there is entirely your choice.

DELETION
Settings › Delete all data erases everything immediately. Uninstalling the app
also removes all of it.

CONTACT
infinix26on@gmail.com
''';
