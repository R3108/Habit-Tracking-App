import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/habit.dart';

/// Schedules the per-habit daily reminders.
///
/// Every method is a no-op when the plugin isn't available — on the test
/// binding, on an unsupported platform, or when initialisation failed — so the
/// rest of the app can call this without guarding each site. A reminder that
/// doesn't fire is a disappointment; a crash on launch is a one-star review.
class NotificationService {
  NotificationService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  static const _channelId = 'habit_reminders';
  static const _channelName = 'Habit reminders';
  static const _channelDescription =
      'Daily nudges for the habits you asked to be reminded about';

  bool _ready = false;

  bool get isReady => _ready;

  /// Prepares the plugin and the timezone database.
  ///
  /// Safe to call more than once; only the first call does work.
  Future<void> init() async {
    if (_ready) return;
    try {
      tz_data.initializeTimeZones();
      // The timezone package has no idea which zone the device is in, and
      // scheduling against UTC would fire reminders hours off. Ask the platform.
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));

      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      _ready = true;
    } catch (error, stack) {
      // Most often: no platform implementation (tests, desktop) or an unknown
      // zone identifier. Reminders stay off; everything else keeps working.
      debugPrint('notifications unavailable: $error\n$stack');
      _ready = false;
    }
  }

  /// Asks for the Android 13+ POST_NOTIFICATIONS permission.
  ///
  /// Returns false when the user declines or the platform can't be reached.
  Future<bool> requestPermission() async {
    if (!_ready) return false;
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (android == null) return false;
      return await android.requestNotificationsPermission() ?? false;
    } catch (error) {
      debugPrint('could not request notification permission: $error');
      return false;
    }
  }

  /// Rebuilds every scheduled reminder from [habits].
  ///
  /// Cancel-then-reschedule rather than diffing: the whole set is a handful of
  /// alarms, and rebuilding from the current state makes it impossible for a
  /// stale reminder to survive an edit, an archive or a delete.
  Future<void> syncReminders(
    List<Habit> habits, {
    required bool enabled,
  }) async {
    if (!_ready) return;
    try {
      await _plugin.cancelAll();
      if (!enabled) return;

      for (final habit in habits) {
        final reminder = habit.reminder;
        if (reminder == null || habit.archived) continue;

        if (habit.schedule.frequency == HabitFrequency.specificDays) {
          for (final weekday in habit.schedule.weekdays) {
            await _scheduleWeekly(habit, weekday: weekday);
          }
        } else {
          await _scheduleDaily(habit);
        }
      }
    } catch (error) {
      debugPrint('could not sync reminders: $error');
    }
  }

  Future<void> cancelAll() async {
    if (!_ready) return;
    try {
      await _plugin.cancelAll();
    } catch (error) {
      debugPrint('could not cancel reminders: $error');
    }
  }

  Future<void> _scheduleDaily(Habit habit) => _schedule(
    id: _notificationId(habit.id, 0),
    habit: habit,
    scheduledDate: _nextOccurrence(habit.reminder!),
    repeat: DateTimeComponents.time,
  );

  Future<void> _scheduleWeekly(Habit habit, {required int weekday}) => _schedule(
    id: _notificationId(habit.id, weekday),
    habit: habit,
    scheduledDate: _nextOccurrence(habit.reminder!, weekday: weekday),
    repeat: DateTimeComponents.dayOfWeekAndTime,
  );

  Future<void> _schedule({
    required int id,
    required Habit habit,
    required tz.TZDateTime scheduledDate,
    required DateTimeComponents repeat,
  }) {
    return _plugin.zonedSchedule(
      id: id,
      title: habit.title,
      body: habit.note.isEmpty ? 'Time for your habit' : habit.note,
      scheduledDate: scheduledDate,
      payload: habit.id,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      ),
      // Inexact on purpose. Exact alarms need SCHEDULE_EXACT_ALARM or
      // USE_EXACT_ALARM, and Google Play audits apps that declare them — a
      // habit nudge that lands within a few minutes of 08:00 is not worth a
      // policy review.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: repeat,
    );
  }

  /// The next time [reminder] comes round, optionally pinned to a weekday.
  static tz.TZDateTime _nextOccurrence(TimeOfDay reminder, {int? weekday}) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      reminder.hour,
      reminder.minute,
    );

    if (weekday != null) {
      while (scheduled.weekday != weekday || !scheduled.isAfter(now)) {
        scheduled = scheduled.add(const Duration(days: 1));
      }
    } else if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  /// A stable, collision-resistant id per habit *and* weekday.
  ///
  /// Android notification ids are 32-bit, so the habit hash is masked to 24
  /// bits and shifted to leave room for the weekday (0 = the daily slot).
  static int _notificationId(String habitId, int weekday) =>
      ((habitId.hashCode & 0x00FFFFFF) << 3) | (weekday & 0x7);
}
