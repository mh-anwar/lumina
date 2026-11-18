import 'dart:convert';

import 'package:home_widget/home_widget.dart';

import 'package:lumina/domain/models/widget_action.dart';

/// Draws Lumina's home-screen widgets.
abstract interface class HomeWidgetService {
  /// What the all-lights widgets show.
  Future<WidgetStatus?> lastStatus();
  Future<void> show(WidgetStatus status);

  /// Whether any light was on, last time the app or a widget knew. Unlike
  /// [lastStatus] it is never busy or unavailable.
  Future<bool?> lastOn();
  Future<void> rememberOn(bool on);

  /// What the One light widgets for the light at [addr] show.
  Future<WidgetStatus?> lastLightStatus(int addr);

  /// Shows [status] on the light's widgets, and remembers on or off.
  Future<void> showLight(int addr, WidgetStatus status);

  /// Whether the light at [addr] was on, last time it was known.
  Future<bool?> lastLightOn(int addr);

  /// The lights a One light widget can be set to, as (address, name).
  Future<void> saveLights(List<(int, String)> lights);
}

/// [HomeWidgetService] backed by the home_widget plugin. The Android
/// providers (LuminarWidgets.kt) read these keys from the plugin's shared
/// preferences.
class PluginHomeWidgetService implements HomeWidgetService {
  static const _status = 'status';
  static const _on = 'lastOn';
  static const _lights = 'lights';
  static String _lightStatus(int addr) => 'light_${addr}_status';
  static String _lightOn(int addr) => 'light_${addr}_on';

  static const _providers = [
    'app.luminar.luminar.LightsToggleWidget',
    'app.luminar.luminar.LightsPresetsWidget',
  ];
  static const _lightProvider = 'app.luminar.luminar.OneLightWidget';

  static WidgetStatus? _parse(String? name) =>
      WidgetStatus.values.where((s) => s.name == name).firstOrNull;

  @override
  Future<WidgetStatus?> lastStatus() async =>
      _parse(await HomeWidget.getWidgetData<String>(_status));

  @override
  Future<void> show(WidgetStatus status) async {
    await HomeWidget.saveWidgetData<String>(_status, status.name);
    for (final p in _providers) {
      await HomeWidget.updateWidget(qualifiedAndroidName: p);
    }
  }

  @override
  Future<bool?> lastOn() => HomeWidget.getWidgetData<bool>(_on);

  @override
  Future<void> rememberOn(bool on) async {
    await HomeWidget.saveWidgetData<bool>(_on, on);
  }

  @override
  Future<WidgetStatus?> lastLightStatus(int addr) async =>
      _parse(await HomeWidget.getWidgetData<String>(_lightStatus(addr)));

  @override
  Future<void> showLight(int addr, WidgetStatus status) async {
    await HomeWidget.saveWidgetData<String>(_lightStatus(addr), status.name);
    if (status == WidgetStatus.on || status == WidgetStatus.off) {
      await HomeWidget.saveWidgetData<bool>(_lightOn(addr), status == WidgetStatus.on);
    }
    await HomeWidget.updateWidget(qualifiedAndroidName: _lightProvider);
  }

  @override
  Future<bool?> lastLightOn(int addr) => HomeWidget.getWidgetData<bool>(_lightOn(addr));

  @override
  Future<void> saveLights(List<(int, String)> lights) async {
    final json = jsonEncode([
      for (final (addr, name) in lights) {'addr': addr, 'name': name},
    ]);
    await HomeWidget.saveWidgetData<String>(_lights, json);
    await HomeWidget.updateWidget(qualifiedAndroidName: _lightProvider);
  }
}

/// Keeps everything in memory, for tests. Two repositories over one of
/// these act like the app and a widget's background isolate sharing the
/// plugin's storage.
class MemoryHomeWidgetService implements HomeWidgetService {
  final shown = <WidgetStatus>[];
  bool? on;
  final lightShown = <int, List<WidgetStatus>>{};
  final lightOn = <int, bool>{};
  List<(int, String)> lights = const [];

  @override
  Future<WidgetStatus?> lastStatus() async => shown.lastOrNull;

  @override
  Future<void> show(WidgetStatus status) async => shown.add(status);

  @override
  Future<bool?> lastOn() async => on;

  @override
  Future<void> rememberOn(bool on) async {
    this.on = on;
  }

  @override
  Future<WidgetStatus?> lastLightStatus(int addr) async => lightShown[addr]?.lastOrNull;

  @override
  Future<void> showLight(int addr, WidgetStatus status) async {
    (lightShown[addr] ??= []).add(status);
    if (status == WidgetStatus.on || status == WidgetStatus.off) {
      lightOn[addr] = status == WidgetStatus.on;
    }
  }

  @override
  Future<bool?> lastLightOn(int addr) async => lightOn[addr];

  @override
  Future<void> saveLights(List<(int, String)> lights) async {
    this.lights = lights;
  }
}
