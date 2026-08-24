import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'data/app_repository.dart';
import 'services/notification_service.dart';

export 'app.dart' show HabitFlowApp;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Started before the first frame so a reminder scheduled during load has a
  // live plugin to talk to. Failures inside init() are swallowed there — the
  // app must open whether or not notifications are available.
  final notifications = NotificationService();
  await notifications.init();

  runApp(
    HabitFlowApp(
      repository: SharedPreferencesAppRepository(),
      notifications: notifications,
    ),
  );
}
