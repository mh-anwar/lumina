import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/foundation.dart' show listEquals;

import 'package:lumina/data/services/home_widget_service.dart';
import 'package:lumina/data/services/timings.dart';
import 'package:lumina/domain/models/widget_action.dart';

/// A widget tap handed to the running app, which answers with the status
/// the widget should show.
class WidgetRequest {
  final WidgetAction action;
  final void Function(WidgetStatus status) reply;
  const WidgetRequest(this.action, this.reply);
}

/// The home-screen widgets: what they show, and taps passed between the
/// widget's background isolate and the running app.
class WidgetRepository {
  WidgetRepository({
    required this._service,
    this.portName = defaultPortName,
    this.timings = const Timings(),
  });

  final HomeWidgetService _service;
  final Timings timings;

  /// Where the running app listens for widget taps. Tests use their own.
  final String portName;
  static const defaultPortName = 'lumina.widget';

  Future<WidgetStatus?> lastStatus() => _service.lastStatus();

  /// Whether any light was on, last time it was known. A toggle goes the
  /// other way.
  Future<bool?> lastOn() => _service.lastOn();

  Future<void> rememberOn(bool on) => _serial(() => _rememberOn(on));

  Future<void> _rememberOn(bool on) async {
    if (await _service.lastOn() != on) await _service.rememberOn(on);
  }

  /// Updates the widgets, unless they already show [status]. On and off
  /// are also remembered for the next toggle.
  ///
  /// Reads what the widgets show each time instead of caching it: the
  /// widget's background isolate draws them too.
  Future<void> show(WidgetStatus status) => _serial(() async {
    if (status == WidgetStatus.on || status == WidgetStatus.off) {
      await _rememberOn(status == WidgetStatus.on);
    }
    if (await _service.lastStatus() == status) return;
    await _service.show(status);
  });

  /// Whether the light at [addr] was on, last time it was known.
  Future<bool?> lastLightOn(int addr) => _service.lastLightOn(addr);

  /// Updates the One light widgets for [addr], unless they already show
  /// [status].
  Future<void> showLight(int addr, WidgetStatus status) => _serial(() => _showLight(addr, status));

  Future<void> _showLight(int addr, WidgetStatus status) async {
    if (await _service.lastLightStatus(addr) == status) return;
    await _service.showLight(addr, status);
  }

  List<(int, String)>? _lights;

  /// In the running app: the lights One light widgets can be set to, as
  /// (address, name, on), with on null while a light's state is unknown.
  Future<void> syncLights(List<(int, String, bool?)> lights) => _serial(() async {
    final names = [for (final (addr, name, _) in lights) (addr, name)];
    if (!listEquals(names, _lights)) {
      _lights = names;
      await _service.saveLights(names);
    }
    for (final (addr, _, on) in lights) {
      if (on != null) await _showLight(addr, on ? WidgetStatus.on : WidgetStatus.off);
    }
  });

  /// Runs widget updates one at a time, so a quick on then off can't
  /// finish in the wrong order.
  Future<void> _serial(Future<void> Function() update) {
    final next = _updates.then((_) => update());
    _updates = next.catchError((Object _) {});
    return next;
  }

  Future<void> _updates = Future<void>.value();

  // ---------- the running app ----------

  ReceivePort? _port;

  /// In the running app: widget taps from the background isolate.
  Stream<WidgetRequest> listen() {
    final port = _port = ReceivePort();
    IsolateNameServer.removePortNameMapping(portName);
    IsolateNameServer.registerPortWithName(port.sendPort, portName);
    return port
        .map((msg) {
          if (msg case [final String uri, final SendPort replyTo]) {
            final action = WidgetAction.fromUri(Uri.parse(uri));
            if (action != null) return WidgetRequest(action, (s) => replyTo.send(s.name));
          }
          return null;
        })
        .where((r) => r != null)
        .cast<WidgetRequest>();
  }

  void close() {
    if (_port == null) return;
    IsolateNameServer.removePortNameMapping(portName);
    _port?.close();
    _port = null;
  }

  // ---------- the widget's background isolate ----------

  /// Hands [action] to the running app, if there is one, and returns the
  /// status it answered with. Returns null if the app is not running.
  /// [timeout] defaults to [Timings.askApp].
  Future<WidgetStatus?> askApp(WidgetAction action, {Duration? timeout}) async {
    final app = IsolateNameServer.lookupPortByName(portName);
    if (app == null) return null;
    final answer = ReceivePort();
    try {
      app.send([action.toUri().toString(), answer.sendPort]);
      final name = await answer.first.timeout(timeout ?? timings.askApp);
      return WidgetStatus.values.where((s) => s.name == name).firstOrNull ??
          WidgetStatus.unavailable;
    } on TimeoutException {
      return WidgetStatus.unavailable;
    } finally {
      answer.close();
    }
  }
}
