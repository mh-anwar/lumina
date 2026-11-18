import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:lumina/data/repositories/connection_repository.dart';
import 'package:lumina/data/repositories/home_repository.dart';
import 'package:lumina/data/repositories/light_repository.dart';
import 'package:lumina/data/repositories/scene_repository.dart';
import 'package:lumina/data/repositories/widget_repository.dart';
import 'package:lumina/data/services/activity_log.dart';
import 'package:lumina/data/services/ble/ble_service.dart';
import 'package:lumina/data/services/provisioning_service.dart';
import 'package:lumina/domain/models/connection.dart';
import 'package:lumina/domain/models/home.dart';
import 'package:lumina/domain/models/light.dart';
import 'package:lumina/domain/models/light_state.dart';
import 'package:lumina/domain/models/nearby_bulb.dart';
import 'package:lumina/domain/models/preset.dart';
import 'package:lumina/domain/models/widget_action.dart';
import 'package:lumina/domain/use_cases/add_light_use_case.dart';
import 'package:lumina/domain/use_cases/connect_use_case.dart';

/// State and commands for the home screen: the connection, all lights,
/// each light, scenes, and backup.
class HomeViewModel extends ChangeNotifier {
  HomeViewModel({
    required this._home,
    required this._connection,
    required this._lights,
    required this._scenes,
    required this._connect,
    required this._addLight,
    required this._widgets,
    required this._log,
  }) {
    for (final l in [_home, _connection, _lights]) {
      l.addListener(notifyListeners);
    }
    _droppedSub = _connection.dropped.listen((_) => _reconnect());
    addListener(_syncWidgets);
  }

  final HomeRepository _home;
  final ConnectionRepository _connection;
  final LightRepository _lights;
  final SceneRepository _scenes;
  final ConnectUseCase _connect;
  final AddLightUseCase _addLight;
  final ActivityLog _log;
  final WidgetRepository _widgets;
  late final StreamSubscription<void> _droppedSub;
  StreamSubscription<WidgetRequest>? _widgetSub;

  // ---------- state ----------

  String _status = '';
  bool _statusIsError = false;
  bool _busy = false;

  /// The message under the title.
  String get status => _status;
  bool get statusIsError => _statusIsError;

  /// Connecting or adding a light.
  bool get busy => _busy;
  bool get loaded => _home.loaded;
  Connection get connection => _connection.state;
  bool get isConnected => _connection.isConnected;

  List<Light> get lights => _home.home.lights;
  List<Light> get ready => _home.home.ready;
  LightState stateOf(Light l) => _lights.stateOf(l.addr);

  Map<int, String> get scenes => _scenes.names;
  bool get showScenes => ready.any((l) => l.has('scene'));

  List<Light> get _on => [
    for (final l in ready)
      if (stateOf(l).on) l,
  ];

  /// How many configured lights are on.
  int get onCount => _on.length;

  /// The light the all-lights sliders show: the first one that is on.
  Light? get _reference => _on.firstOrNull ?? ready.firstOrNull;
  int get allLevel => _reference?.level ?? 70;
  int get allKelvin => _reference?.kelvin ?? 3000;

  String statusLine(Light l) {
    final s = stateOf(l);
    if (l.wasReset) return 'Was reset';
    if (!l.configured) return 'Needs one more setup step';
    if (!isConnected && !s.known) return 'Not connected';
    if (isConnected && !s.responding) return 'Not responding';
    if (!s.on) return 'Off';
    final look = switch (l.hue) {
      final h? when l.inColor => ' · ${colorName(h, l.saturation)}',
      _ when l.hasCtl => ' · ${warmth(l.kelvin)}',
      _ => '',
    };
    return '${l.level}%$look';
  }

  /// A color in words, from its hue in degrees and saturation in percent.
  static String colorName(int hue, int saturation) {
    if (saturation < 15) return 'White';
    final h = hue % 360;
    final name = switch (h) {
      < 15 => 'Red',
      < 40 => 'Orange',
      < 65 => 'Yellow',
      < 160 => 'Green',
      < 200 => 'Cyan',
      < 255 => 'Blue',
      < 290 => 'Purple',
      < 340 => 'Pink',
      _ => 'Red',
    };
    return saturation < 50 ? 'Pale ${name.toLowerCase()}' : name;
  }

  /// A light that needs the user before it can be controlled.
  bool needsAction(Light l) => l.wasReset || !l.configured;

  /// What tapping a light that needs the user does.
  String? actionLabel(Light l) => l.wasReset
      ? 'Set up again'
      : !l.configured
      ? 'Finish setup'
      : null;

  /// The all-lights tile's status.
  String get allStatus {
    final n = onCount, total = ready.length;
    if (n == 0) return 'All off';
    final which = n == total ? 'All on' : '$n of $total on';
    return '$which · $allLevel%';
  }

  /// A color temperature in words.
  static String warmth(int kelvin) => switch (kelvin) {
    < 3300 => 'Warm',
    < 4500 => 'Neutral',
    < 5500 => 'Cool',
    _ => 'Daylight',
  };

  /// Connection, in a few words for the header.
  String get connectionLabel => switch (connection) {
    Connection.on => 'Connected',
    Connection.connecting => 'Connecting…',
    Connection.off => 'Not connected',
  };

  void _say(String msg, {bool error = false}) {
    _status = msg;
    _statusIsError = error;
    if (msg.isNotEmpty) _log.add(error ? 'ERROR $msg' : msg);
    notifyListeners();
  }

  // ---------- lifecycle and connection ----------

  /// Loads the home, starts answering widget taps, and connects if there
  /// are lights.
  Future<void> start() async {
    if (!loaded) await _home.load();
    _widgetSub ??= _widgets.listen().listen((r) async => r.reply(await runWidgetAction(r.action)));
    _syncWidgets();
    if (lights.isNotEmpty) {
      _say('');
      await connect();
    }
  }

  bool _away = false;

  /// Reconnects when the app comes back from the background. Android also
  /// reports resumed while the app launches; [start] connects then.
  Future<void> lifecycleChanged(AppLifecycleState state) async {
    switch (state) {
      case AppLifecycleState.hidden || AppLifecycleState.paused:
        _away = true;
      case AppLifecycleState.resumed when _away:
        _away = false;
        if (loaded && lights.isNotEmpty && connection == Connection.off && !_busy) await connect();
      default:
    }
  }

  Future<void> connect() async {
    if (_busy || isConnected) return;
    _busy = true;
    _say(lights.isEmpty ? '' : 'Looking for your lights…');
    try {
      switch (await _connect()) {
        case Connected():
          final reset = [
            for (final l in lights)
              if (l.wasReset) l.name,
          ];
          // The header already says Connected; only reset lights need a message.
          _log.add('Connected.');
          _say(_resetMessage(reset), error: reset.isNotEmpty);
        case NoLights():
          _say('Add a light first.');
        case NoneFound():
          _say('No lights found nearby. Make sure they are powered on and close by.', error: true);
        case OldSetup():
          _say(
            'The bulbs nearby are still on their old setup. Reset a bulb with five quick off/on cycles, then use Add a light.',
            error: true,
          );
        case ConnectFailed(:final detail):
          _say(
            detail == null
                ? 'Could not connect. Close nRF Mesh or other light apps, then try again.'
                : 'Could not connect: $detail',
            error: true,
          );
        case LightsWereReset(:final names):
          _say(_resetMessage(names), error: true);
        case BluetoothOff(:final message):
          _say(message, error: true);
      }
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  static String _resetMessage(List<String> names) => switch (names) {
    [] => '',
    [final one] => '$one was reset. Tap it to set it up again.',
    [...final rest, final last] =>
      '${rest.join(', ')} and $last were reset. Tap each one to set it up again.',
  };

  Future<void> disconnect() => _connection.disconnect();

  /// After an unexpected disconnect: reconnects at once while the app is in
  /// front, otherwise when it comes back ([lifecycleChanged]).
  Future<void> _reconnect() async {
    if (_away || _busy) {
      _say('Disconnected.');
      return;
    }
    _log.add('Disconnected. Reconnecting.');
    await connect();
  }

  /// Connect, or disconnect when connected.
  Future<void> toggleConnection() => isConnected ? disconnect() : connect();

  // ---------- home-screen widgets ----------

  void _syncWidgets() {
    if (!loaded || ready.isEmpty) return;
    unawaited(_widgets.show(onCount > 0 ? WidgetStatus.on : WidgetStatus.off));
  }

  /// Runs a widget tap through this (running) app's connection.
  Future<WidgetStatus> runWidgetAction(WidgetAction action) async {
    if (!await _connected()) return WidgetStatus.unavailable;
    switch (action) {
      case ToggleAllAction():
        await toggleAll();
      case ApplyPresetAction(:final preset):
        await applyPreset(preset);
    }
    return onCount > 0 ? WidgetStatus.on : WidgetStatus.off;
  }

  // ---------- adding a light ----------

  /// Provisions and configures [bulb]. Returns true if it joined the network
  /// (even if its setup is unfinished).
  Future<bool> addLight(NearbyBulb bulb) async {
    await _whileBusy();
    if (_busy) return false;
    _busy = true;
    _say('Connecting to ${bulb.name}…');
    try {
      final r = await _addLight(
        bulb,
        onStep: (s) => _say('Setting up ${bulb.name} (${s.index + 1} of 3)…'),
      );
      switch (r) {
        case LightAdded(:final light):
          _say('${light.name} is ready.');
        case LightNeedsSetup(:final light):
          _say(
            '${light.name} was added but needs one more step. Tap it to finish setup.',
            error: true,
          );
      }
      return true;
    } on ProvisioningException catch (e) {
      _say(_provisioningMessage(e), error: true);
      return false;
    } on BluetoothUnavailable catch (e) {
      _say(e.message, error: true);
      return false;
    } catch (e) {
      final s = '$e';
      _say(s.startsWith('Exception: ') ? s.substring(11) : s, error: true);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Sets up a light that was reset outside the app again, keeping its
  /// place and name.
  Future<bool> setUpAgain(Light l) async {
    final id = l.bleId;
    if (id == null) {
      _say('Reset ${l.name} (five quick off/on cycles), then use Add a light.', error: true);
      return false;
    }
    return addLight(NearbyBulb(id: id, name: l.name, rssi: 0, replaces: l.name));
  }

  static String _provisioningMessage(ProvisioningException e) => switch (e.error) {
    ProvisioningError.disconnected => 'The bulb disconnected during setup. Reset it and try again.',
    ProvisioningError.noAnswer =>
      'The bulb stopped answering. Move closer, reset it, and try again.',
    ProvisioningError.failed =>
      'The bulb stopped setup (error ${e.code ?? '?'}). Reset it and try again.',
    ProvisioningError.unexpected => 'The bulb sent an unexpected reply. Reset it and try again.',
    ProvisioningError.unsupported => 'This bulb uses a setup method Lumina does not support.',
    ProvisioningError.securityCheck =>
      'The bulb failed its security check. Reset it and try again.',
  };

  /// Finish setup for a light from its row.
  Future<void> finishSetup(Light l) async {
    if (!isConnected) {
      await connect(); // connecting configures unfinished lights
      return;
    }
    _say('Finishing setup for ${l.name}…');
    switch (await _lights.configure(l.addr)) {
      case ConfigureResult.ready:
        _say('${l.name} is ready.');
        await _lights.queryState(l.addr);
      case ConfigureResult.noAnswer:
        _say('${l.name} did not respond. Move closer and tap Finish setup again.', error: true);
      case ConfigureResult.onOffRejected:
        _say(
          '${l.name} did not accept its on/off setup. Tap Finish setup to try again.',
          error: true,
        );
    }
  }

  // ---------- control ----------

  /// Connects first when needed, so no command waits on a Connect button.
  /// Returns false if the lights can't be reached.
  Future<bool> _connected() async {
    if (isConnected) return true;
    await _whileBusy();
    if (!isConnected) await connect();
    return isConnected;
  }

  /// Waits for a connect or setup in progress (such as a reconnect) to end.
  Future<void> _whileBusy() async {
    for (var i = 0; i < 300 && _busy; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  Future<void> toggleAll() async {
    if (await _connected()) await _lights.toggleAll();
  }

  /// All-lights sliders.
  void setAll({int? level, int? kelvin}) {
    if (isConnected) {
      _lights.setAll(level: level, kelvin: kelvin);
    } else {
      unawaited(
        _connected().then((ok) {
          if (ok) _lights.setAll(level: level, kelvin: kelvin);
        }),
      );
    }
  }

  Future<void> applyPreset(Preset p) async {
    if (await _connected()) await _lights.applyPreset(p);
  }

  Future<void> setPower(Light l, bool on) async {
    if (await _connected()) await _lights.setPower(l.addr, on);
  }

  /// One light's sliders: brightness, white temperature, or color.
  void setLight(Light l, {int? level, int? kelvin, int? hue, int? saturation}) {
    void send() => _lights.setLevel(
      l.addr,
      level: level,
      kelvin: kelvin,
      hue: hue,
      saturation: saturation,
    );
    if (isConnected) {
      send();
    } else {
      unawaited(
        _connected().then((ok) {
          if (ok) send();
        }),
      );
    }
  }

  Future<void> rename(Light l, String name) => _lights.rename(l.addr, name);

  Future<void> remove(Light l) async {
    await _lights.remove(l.addr);
    _say('${l.name} was removed.');
  }

  /// Makes the light's current level and temperature its power-on default.
  Future<void> useAsDefault(Light l) async {
    final r = await _lights.setCtlDefault(l.addr, l.level, l.kelvin);
    _say(
      r != null
          ? '${l.name} will use ${l.level}% and ${l.kelvin} K as its default.'
          : '${l.name} did not answer. Try again.',
      error: r == null,
    );
  }

  // ---------- scenes ----------

  Future<void> saveScene(String name) async {
    final n = await _scenes.save(name);
    _say(
      n > 0
          ? 'Saved on $n light${n == 1 ? '' : 's'}. Tap it to bring it back.'
          : 'The lights did not save the scene. Try again closer to them.',
      error: n == 0,
    );
  }

  Future<void> recallScene(int scene) async {
    if (!await _connected()) return;
    final addrs = await _scenes.recall(scene);
    _lights.assumeOn(addrs);
    // The recalled state is unknown until the lights report it.
    for (final a in addrs) {
      await _lights.queryState(a);
    }
  }

  Future<void> forgetScene(int scene) => _scenes.forget(scene);

  // ---------- the user's presets ----------

  /// Presets the user made. The built-in ones are [presets].
  List<Preset> get customPresets => _home.home.presets;

  /// Shows a brightness and warmth on every light while a preset is being
  /// made, without asking to connect.
  void preview({int? level, int? kelvin}) {
    if (isConnected) _lights.setAll(level: level, kelvin: kelvin);
  }

  /// Saves a preset that sets every light to [level] and [kelvin]. Returns
  /// false if the name can't be used.
  Future<bool> savePreset(String name, {required int level, required int kelvin}) async {
    final n = name.trim();
    if (n.isEmpty) {
      _say('Give the scene a name.', error: true);
      return false;
    }
    if (presets.any((p) => p.name.toLowerCase() == n.toLowerCase())) {
      _say('$n is already a built-in scene. Pick another name.', error: true);
      return false;
    }
    await _home.savePreset(Preset(n, level, kelvin));
    _say('Saved $n. Tap it to use it.');
    return true;
  }

  Future<void> deletePreset(Preset p) => _home.removePreset(p.name);

  // ---------- backup ----------

  String backupCode() => _home.backupCode();

  void backupCopied() => _say('Backup code copied.');

  /// Replaces the lights with a backup. Returns false if the code is not
  /// valid.
  Future<bool> restore(String code) async {
    try {
      Home.fromBackupCode(code);
    } on FormatException {
      _say(
        'That backup code is not valid. Paste the full code, starting with LAMPLIGHT1.',
        error: true,
      );
      return false;
    }
    await _connection.disconnect();
    await _home.restore(code);
    _lights.resetStates();
    final n = lights.length;
    // Connect straight away; if that fails, its message says why.
    await connect();
    if (isConnected) _say('Restored $n light${n == 1 ? '' : 's'}.');
    return true;
  }

  Future<void> startOver() async {
    await _connection.disconnect();
    await _home.startOver();
    _lights.resetStates();
    _say('Starting fresh. Tap Add a light.');
  }

  @override
  void dispose() {
    _widgetSub?.cancel();
    _widgets.close();
    removeListener(_syncWidgets);
    _droppedSub.cancel();
    for (final l in [_home, _connection, _lights]) {
      l.removeListener(notifyListeners);
    }
    super.dispose();
  }
}
