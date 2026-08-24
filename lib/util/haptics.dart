import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/settings_store.dart';

/// Haptic feedback that respects the user's setting.
///
/// Reads the switch through the context rather than taking a flag at every call
/// site, so adding feedback somewhere new can't accidentally ignore it.
abstract final class Haptics {
  /// A light tick — ticking a habit, moving through a picker.
  static void tick(BuildContext context) {
    if (!_enabled(context)) return;
    HapticFeedback.selectionClick();
  }

  /// A firmer bump for something completed or destroyed.
  static void impact(BuildContext context) {
    if (!_enabled(context)) return;
    HapticFeedback.mediumImpact();
  }

  static bool _enabled(BuildContext context) {
    // getInheritedWidgetOfExactType: reading a preference must not make the
    // caller rebuild every time any other setting changes.
    final scope = context.getInheritedWidgetOfExactType<SettingsScope>();
    return scope?.notifier?.settings.hapticsEnabled ?? true;
  }
}
