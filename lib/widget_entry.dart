import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:lumina/config/dependencies.dart';
import 'package:lumina/data/services/ble/reactive_ble_service.dart';
import 'package:lumina/data/services/home_store.dart';
import 'package:lumina/data/services/timings.dart';
import 'package:lumina/domain/models/widget_action.dart';

/// Runs in a background isolate when a home-screen widget is tapped.
///
/// If the app is running, it has the proxy connection, so the tap is handed
/// to it. Otherwise this isolate connects, sends one command and
/// disconnects.
@pragma('vm:entry-point')
Future<void> widgetTapped(Uri? uri) async {
  final action = WidgetAction.fromUri(uri);
  if (action == null) return;
  const timings = Timings();
  final deps = Dependencies(
    ble: ReactiveBleService(interactive: false, timings: timings),
    store: SecureHomeStore(),
  );
  final widgets = deps.widgets;
  // The One light widget draws its own light; the others all lights.
  Future<void> show(WidgetStatus s) => switch (action) {
    ToggleLightAction(:final addr) => widgets.showLight(addr, s),
    _ => widgets.show(s),
  };
  // The last known state, not what the widget shows (busy or Retry).
  final wasOn = action is ToggleLightAction
      ? await widgets.lastLightOn(action.addr) ?? false
      : await widgets.lastOn() ?? await widgets.lastStatus() == WidgetStatus.on;
  await show(WidgetStatus.busy);

  final viaApp = await widgets.askApp(action);
  if (viaApp != null) {
    await show(viaApp);
    return;
  }

  var status = WidgetStatus.unavailable;
  try {
    await deps.home.load();
    status = await deps.widgetAction(action, wasOn: wasOn);
    // Writes are queued in the platform; let the last one go out before
    // the link closes.
    await Future<void>.delayed(timings.writeFlush);
  } catch (e) {
    debugPrint('[lumina] Widget action failed: $e');
  } finally {
    await deps.connection.disconnect();
    await show(status);
    // Every light followed an all-lights action.
    if (action is! ToggleLightAction && status != WidgetStatus.unavailable) {
      for (final l in deps.home.home.ready) {
        await widgets.showLight(l.addr, status);
      }
    }
    deps.dispose();
  }
}
