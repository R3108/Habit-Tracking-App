import 'package:flutter/material.dart';

import '../state/habit_store.dart';
import '../state/settings_store.dart';

/// First-launch introduction.
///
/// Three pages, and the notification permission is asked for on the last one
/// rather than at launch: a permission prompt that arrives before the user
/// knows what the app does is the one they reflexively decline.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  static const _pages = <({IconData icon, String title, String body})>[
    (
      icon: Icons.check_circle_outline,
      title: 'Build the habit',
      body:
          'Add what you want to do, pick the days it should happen, and tick '
          'it off. Missed yesterday? Tap back a day and fix it.',
    ),
    (
      icon: Icons.local_fire_department,
      title: 'Watch the streak',
      body:
          'Every habit tracks its current and best run. Rest days never break '
          'a streak — only the days you actually scheduled count.',
    ),
    (
      icon: Icons.notifications_active_outlined,
      title: 'Get a nudge',
      body:
          'Give a habit a reminder time and HabitFlow will tap you on the '
          'shoulder. You can change or switch these off at any time.',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _isLastPage => _page == _pages.length - 1;

  Future<void> _next() async {
    if (!_isLastPage) {
      await _controller.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    await _finish(askForNotifications: true);
  }

  Future<void> _finish({required bool askForNotifications}) async {
    final settings = SettingsScope.of(context);
    final habits = HabitScope.of(context);

    var granted = false;
    if (askForNotifications) {
      granted = await habits.notifications?.requestPermission() ?? false;
    }

    // Declining is a real answer: leave the master switch off rather than
    // promising reminders the OS will silently swallow.
    await settings.update(
      settings.settings.copyWith(
        onboardingComplete: true,
        remindersEnabled: granted,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => _finish(askForNotifications: false),
                child: const Text('Skip'),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (page) => setState(() => _page = page),
                itemBuilder: (context, index) {
                  final page = _pages[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            color: scheme.primaryContainer,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            page.icon,
                            size: 56,
                            color: scheme.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(height: 40),
                        Text(
                          page.title,
                          textAlign: TextAlign.center,
                          style: textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          page.body,
                          textAlign: TextAlign.center,
                          style: textTheme.bodyLarge?.copyWith(
                            color: scheme.onSurfaceVariant,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _pages.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 240),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _page ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _page
                          ? scheme.primary
                          : scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 32, 32, 24),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _next,
                  child: Text(
                    _isLastPage ? 'Turn on reminders' : 'Next',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
