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

/// A slider change: brightness, white temperature, or color.
typedef _Look = ({int? level, int? kelvin, int? hue, int? saturation});

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
    this.infoLinger = const Duration(seconds: 4),
  }) {
    for (final l in [_home, _connection, _lights]) {
      l.addListener(notifyListeners);
    }
    _droppedSub = _connection.dropped.listen((_) => _reconnect());
    // Bluetooth turned on or allowed: connect without a tap.
    _readySub = _connection.bluetoothReady.listen((_) {
      if (loaded && lights.isNotEmpty && !_away && !isConnected) unawaited(connect());
    });
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
  late final StreamSubscription<void> _readySub;
  StreamSubscription<WidgetRequest>? _widgetSub;

  /// How long a message that is not an error stays under the title. A
  /// reading time for people, not a radio timeout, so it is not in Timings.
  final Duration infoLinger;

  // ---------- state ----------

  String _status = '';
  bool _statusIsError = false;
  Timer? _statusTimer;

  /// The connect under way, which commands and adds wait for.
  Future<void>? _connecting;

  /// The light being added, which connects and other adds wait for.
  Future<bool>? _adding;

  /// The last connect ended without a connection, and trying again may help.
  bool _connectFailed = false;

  /// Lights whose setup is being finished.
  final _finishing = <int>{};

  /// The message under the title.
  String get status => _status;
  bool get statusIsError => _statusIsError;

  /// Connecting or adding a light.
  bool get busy => _connecting != null || _adding != null;

  /// Something is under way that the message describes.
  bool get working => busy || _finishing.isNotEmpty;
  bool get loaded => _home.loaded;
  Connection get connection => _connection.state;
  bool get isConnected => _connection.isConnected;

  /// Whether the header offers Try again: only after a connect failed.
  bool get showRetry =>
      _connectFailed && !busy && connection == Connection.off && lights.isNotEmpty;

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
    if (_finishing.contains(l.addr)) return 'Finishing setup…';
    if (!l.configured) return 'Setup not finished';
    if (!isConnected && !s.known) return 'Not connected';
    if (isConnected && !s.responding) return 'Not responding';
    if (!isConnected) return 'Last seen ${s.on ? _looks(l) : 'off'}';
    return s.on ? _looks(l) : 'Off';
  }

  /// Brightness and color or white, such as "70% · Warm".
  static String _looks(Light l) {
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
  bool needsAction(Light l) => l.wasReset || (!l.configured && !_finishing.contains(l.addr));

  /// What tapping a light that needs the user does.
  String? actionLabel(Light l) => l.wasReset
      ? 'Set up again'
      : !l.configured && !_finishing.contains(l.addr)
      ? 'Finish setup'
      : null;

  List<Light> get _resetLights => [
    for (final l in lights)
      if (l.wasReset) l,
  ];

  /// Several lights were reset: one button sets them all up again.
  bool get canSetUpAllAgain => _resetLights.length > 1;

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

  /// Shows [msg] under the title. Errors stay until the next message, and
  /// so does progress (a message ending in …); anything else clears itself
  /// after [infoLinger].
  void _say(String msg, {bool error = false}) {
    _status = msg;
    _statusIsError = error;
    _statusTimer?.cancel();
    _statusTimer = null;
    if (msg.isNotEmpty && !error && !msg.endsWith('…')) {
      _statusTimer = Timer(infoLinger, () => _say(''));
    }
    if (msg.isNotEmpty) _log.add(error ? 'ERROR $msg' : msg);
    notifyListeners();
  }

  static const _noAnswer = "The bulb didn't answer. Move closer and try again.";

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
        if (loaded && lights.isNotEmpty && connection == Connection.off && !busy) await connect();
      default:
    }
  }

  /// Connects. If a connect is already under way, or a light is being
  /// added, waits for it instead of starting another.
  Future<void> connect() async {
    final adding = _adding;
    if (adding != null) await adding;
    if (isConnected) return;
    final running = _connecting;
    if (running != null) {
      await running;
      return;
    }
    final done = Completer<void>();
    _connecting = done.future;
    try {
      await _connectNow();
    } finally {
      _connecting = null;
      done.complete();
      notifyListeners();
    }
  }

  Future<void> _connectNow() async {
    _connectFailed = false;
    _say(lights.isEmpty ? '' : 'Looking for your lights…');
    final ConnectResult result;
    try {
      result = await _connect();
    } catch (e) {
      _log.add('Connect failed: $e');
      _connectFailed = true;
      _say(_noAnswer, error: true);
      return;
    }
    switch (result) {
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
        _connectFailed = true;
        _say('No lights found nearby. Make sure they are powered on and close by.', error: true);
      case OldSetup():
        _connectFailed = true;
        _say(
          "These bulbs belong to another app's network. Reset one (switch it off and on five times), then add it.",
          error: true,
        );
      case ConnectFailed(:final detail):
        _connectFailed = true;
        if (detail != null) _log.add('Connect failed: $detail');
        _say('Could not connect. Close nRF Mesh or other light apps, then try again.', error: true);
      case LightsWereReset(:final names):
        _say(_resetMessage(names), error: true);
      case BluetoothOff(:final message):
        _connectFailed = true;
        _say(message, error: true);
      case ConnectBusy():
        // An Add a light scan is running; connecting would stop it.
        _say('');
    }
  }

  static String _resetMessage(List<String> names) => switch (names) {
    [] => '',
    [final one] => '$one was reset. Tap it to set it up again.',
    [...final rest, final last] => '${rest.join(', ')} and $last were reset.',
  };

  Future<void> disconnect() => _connection.disconnect();

  /// After an unexpected disconnect: reconnects at once while the app is in
  /// front, otherwise when it comes back ([lifecycleChanged]).
  Future<void> _reconnect() async {
    if (busy) {
      // A connect or setup under way handles its own links.
      _log.add('Disconnected.');
      return;
    }
    if (_away) {
      _say('Disconnected.');
      return;
    }
    _log.add('Disconnected. Reconnecting.');
    await connect();
  }

  // ---------- home-screen widgets ----------

  void _syncWidgets() {
    if (!loaded) return;
    final states = [for (final l in ready) (l.addr, l.name, stateOf(l))];
    unawaited(_widgets.syncLights([for (final (a, n, s) in states) (a, n, s.known ? s.on : null)]));
    if (ready.isEmpty) return;
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
      case ToggleLightAction(:final addr):
        final l = ready.where((x) => x.addr == addr).firstOrNull;
        if (l == null) return WidgetStatus.unavailable;
        await setPower(l, !stateOf(l).on);
        return stateOf(l).on ? WidgetStatus.on : WidgetStatus.off;
    }
    return onCount > 0 ? WidgetStatus.on : WidgetStatus.off;
  }

  // ---------- adding a light ----------

  /// Provisions and configures [bulb]. Returns true if it joined the network
  /// (even if its setup is unfinished). Waits for a connect or another add
  /// under way first.
  Future<bool> addLight(NearbyBulb bulb) async {
    final connecting = _connecting;
    if (connecting != null) {
      _say('Waiting for the connection…');
      await connecting;
    }
    for (var other = _adding; other != null; other = _adding) {
      await other;
    }
    final done = Completer<bool>();
    _adding = done.future; // _add's first message notifies
    AddLightResult? result;
    try {
      result = await _add(bulb);
    } finally {
      _adding = null;
      done.complete(result != null);
      notifyListeners();
    }
    if (result case LightNeedsSetup(:final light)) unawaited(_finishInBackground(light));
    return result != null;
  }

  /// Adds [bulb] and says how it went. Null if it did not join.
  Future<AddLightResult?> _add(NearbyBulb bulb) async {
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
          _finishing.add(light.addr);
          _say('${light.name} was added. Finishing its setup…');
      }
      return r;
    } on ProvisioningException catch (e) {
      _log.add('Setup failed: $e');
      _say(_provisioningMessage(e), error: true);
    } on BluetoothUnavailable catch (e) {
      _say(e.message, error: true);
    } on ServiceNotFound catch (e) {
      _log.add('Setup failed: $e');
      _say(
        "The bulb isn't ready to be set up. Reset it (switch it off and on five times) and try again.",
        error: true,
      );
    } catch (e) {
      // Timeouts and anything else: the detail is for the activity log.
      _log.add('Setup failed: $e');
      _say(_noAnswer, error: true);
    }
    return null;
  }

  /// Tries twice more to finish a new light's setup before asking the user.
  Future<void> _finishInBackground(Light light) async {
    final addr = light.addr;
    try {
      for (var i = 0; i < 2; i++) {
        if (!await _connected()) break;
        final l = _home.home.lightAt(addr);
        if (l == null) return; // removed meanwhile
        if (l.configured || await _lights.configure(addr) == ConfigureResult.ready) {
          _finishing.remove(addr);
          _say('${light.name} is ready.');
          await _lights.queryState(addr);
          return;
        }
      }
    } catch (e) {
      _log.add('Finishing setup for ${light.name} failed: $e');
    } finally {
      _finishing.remove(addr);
    }
    if (_home.home.lightAt(addr) == null) return;
    _say('${light.name} was added but needs one more step. Tap it to finish setup.', error: true);
  }

  /// Sets up a light that was reset outside the app again, keeping its
  /// place and name.
  Future<bool> setUpAgain(Light l) async {
    final id = l.bleId;
    if (id == null) {
      _say('Reset ${l.name} (switch it off and on five times), then use Add a light.', error: true);
      return false;
    }
    return addLight(NearbyBulb(id: id, name: l.name, rssi: 0, replaces: l.name));
  }

  /// Sets up every reset light again, one after another.
  Future<void> setUpAllAgain() async {
    final failed = <String>[];
    for (final l in _resetLights) {
      if (!await setUpAgain(l)) failed.add(l.name);
    }
    if (failed.isEmpty) return;
    _say(
      '${_names(failed)} could not be set up again. Move closer and tap each one to try again.',
      error: true,
    );
  }

  static String _names(List<String> names) => switch (names) {
    [] => '',
    [final one] => one,
    [...final rest, final last] => '${rest.join(', ')} and $last',
  };

  static String _provisioningMessage(ProvisioningException e) => switch (e.error) {
    ProvisioningError.disconnected => 'The bulb disconnected during setup. Reset it and try again.',
    ProvisioningError.noAnswer =>
      'The bulb stopped answering. Move closer, reset it, and try again.',
    ProvisioningError.failed => 'The bulb stopped setup. Reset it and try again.',
    ProvisioningError.unexpected => 'The bulb sent an unexpected reply. Reset it and try again.',
    ProvisioningError.unsupported => 'This bulb uses a setup method Lumina does not support.',
    ProvisioningError.securityCheck =>
      'The bulb failed its security check. Reset it and try again.',
  };

  /// Finish setup for a light from its row. Connects first if needed;
  /// connecting finishes unfinished setups by itself.
  Future<void> finishSetup(Light l) async {
    if (_finishing.contains(l.addr)) return;
    if (!await _connected()) return;
    final now = _home.home.lightAt(l.addr);
    if (now == null) return;
    if (now.configured) {
      _say('${l.name} is ready.');
      return;
    }
    _finishing.add(l.addr);
    _say('Finishing setup for ${l.name}…');
    final ConfigureResult result;
    try {
      result = await _lights.configure(l.addr);
    } finally {
      _finishing.remove(l.addr);
    }
    switch (result) {
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

  /// Connects first when needed (or waits for the connect under way), so
  /// no command waits on a Connect button. Returns false, with a message,
  /// if the lights can't be reached.
  Future<bool> _connected() async {
    if (isConnected) return true;
    await connect();
    if (isConnected) return true;
    // A failed connect has said why; say something if it did not.
    if (!_statusIsError) {
      _say('Could not reach your lights. Move closer and try again.', error: true);
    }
    return false;
  }

  Future<void> toggleAll() async {
    if (await _connected()) await _lights.toggleAll();
  }

  /// Slider values set while disconnected, by light address (null for all
  /// lights). Each is sent once, with its latest value, when connected. Kept
  /// here because the states read on connecting would overwrite them.
  final _pending = <int?, _Look>{};

  void _sendLater(int? addr, _Look look) {
    final old = _pending[addr];
    _pending[addr] = old == null
        ? look
        : (
            level: look.level ?? old.level,
            // A temperature switches to white, a hue to color.
            kelvin: look.kelvin ?? (look.hue != null ? null : old.kelvin),
            hue: look.hue ?? (look.kelvin != null ? null : old.hue),
            saturation: look.saturation ?? old.saturation,
          );
    if (old == null) unawaited(_sendOnceConnected(addr));
  }

  Future<void> _sendOnceConnected(int? addr) async {
    final ok = await _connected();
    final look = _pending.remove(addr);
    if (!ok || look == null) return;
    if (addr == null) {
      _lights.setAll(level: look.level, kelvin: look.kelvin);
    } else {
      _lights.setLevel(
        addr,
        level: look.level,
        kelvin: look.kelvin,
        hue: look.hue,
        saturation: look.saturation,
      );
    }
  }

  /// All-lights sliders. The lights show the new value at once; while
  /// disconnected it is sent once connected.
  void setAll({int? level, int? kelvin}) {
    final now = isConnected;
    _lights.setAll(level: level, kelvin: kelvin, send: now);
    if (!now) _sendLater(null, (level: level, kelvin: kelvin, hue: null, saturation: null));
  }

  Future<void> applyPreset(Preset p) async {
    if (await _connected()) await _lights.applyPreset(p);
  }

  Future<void> setPower(Light l, bool on) async {
    if (await _connected()) await _lights.setPower(l.addr, on);
  }

  /// One light's sliders: brightness, white temperature, or color. Like
  /// [setAll], waits for a connection to send.
  void setLight(Light l, {int? level, int? kelvin, int? hue, int? saturation}) {
    final now = isConnected;
    _lights.setLevel(
      l.addr,
      level: level,
      kelvin: kelvin,
      hue: hue,
      saturation: saturation,
      send: now,
    );
    if (!now) {
      _sendLater(l.addr, (level: level, kelvin: kelvin, hue: hue, saturation: saturation));
    }
  }

  Future<void> rename(Light l, String name) => _lights.rename(l.addr, name);

  /// Resets the bulb and forgets [l]. Returns false, keeping the light, if
  /// the bulb could not be reached or did not answer; ask with
  /// [removeUnanswered], then [removeAnyway].
  Future<bool> remove(Light l) async {
    if (l.wasReset) {
      // The bulb already left the network.
      await _lights.forget(l.addr);
    } else if (!await _connected() || !await _lights.remove(l.addr)) {
      return false;
    }
    _say('${l.name} was removed.');
    return true;
  }

  /// The question when [remove] got no answer from the bulb.
  String removeUnanswered(Light l) =>
      "${l.name} didn't answer. Remove it anyway? You'll need to reset the bulb by switching it off and on five times.";

  /// Forgets [l] without resetting the bulb.
  Future<void> removeAnyway(Light l) async {
    await _lights.forget(l.addr);
    _say('${l.name} was removed.');
  }

  /// Makes the light's current level and temperature its power-on default.
  Future<void> useAsDefault(Light l) async {
    if (!await _connected()) return;
    final r = await _lights.setCtlDefault(l.addr, l.level, l.kelvin);
    _say(
      r != null
          ? '${l.name} will come on at ${l.level}%, ${warmth(l.kelvin).toLowerCase()} white.'
          : '${l.name} did not answer. Try again.',
      error: r == null,
    );
  }

  // ---------- scenes ----------

  /// The name the Save each light dialog suggests: the lowest unused
  /// "Scene N".
  String get nextSceneName => _lowestUnused('Scene', scenes.values);

  Future<void> saveScene(String name) async {
    if (!await _connected()) return;
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

  Future<void> forgetScene(int scene) async {
    if (!await _connected()) return;
    await _scenes.forget(scene);
  }

  // ---------- the user's presets ----------

  /// Presets the user made. The built-in ones are [presets].
  List<Preset> get customPresets => _home.home.presets;

  /// The name the New scene sheet suggests: the lowest unused "My scene N".
  String get nextPresetName => _lowestUnused('My scene', [for (final p in customPresets) p.name]);

  static String _lowestUnused(String stem, Iterable<String> taken) {
    final used = {for (final t in taken) t.trim().toLowerCase()};
    var n = 1;
    while (used.contains('${stem.toLowerCase()} $n')) {
      n++;
    }
    return '$stem $n';
  }

  /// Each ready light, and whether it was on, when the New scene sheet
  /// opened. Null when the sheet is closed.
  List<(Light, bool)>? _beforeNewScene;

  /// Whether the New scene sheet changed the lights.
  bool _previewed = false;

  /// Remembers how the lights look, so [endNewScene] can put them back.
  void beginNewScene() {
    _beforeNewScene = [for (final l in ready) (l, stateOf(l).on)];
    _previewed = false;
  }

  /// Shows a brightness and warmth on every light while a preset is being
  /// made, without asking to connect.
  void preview({int? level, int? kelvin}) {
    if (!isConnected) return;
    _previewed = true;
    _lights.setAll(level: level, kelvin: kelvin);
  }

  /// When the New scene sheet closes: unless a preset was [saved], puts
  /// every light back as it was when the sheet opened.
  Future<void> endNewScene({required bool saved}) async {
    final before = _beforeNewScene;
    final previewed = _previewed;
    _beforeNewScene = null;
    _previewed = false;
    if (saved || before == null || !previewed || !isConnected) return;
    // Let the last preview message go out first, so it can't undo this.
    await Future<void>.delayed(_lights.timings.throttle * 2);
    for (final (l, on) in before) {
      if (_home.home.lightAt(l.addr) == null) continue;
      // A light that was off only needs switching off again.
      _lights.setLevel(
        l.addr,
        level: l.level,
        kelvin: l.kelvin,
        hue: l.hue,
        saturation: l.saturation,
        send: on,
      );
      if (!on) await _lights.setPower(l.addr, false);
    }
  }

  /// Saves a preset that sets every light to [level] and [kelvin]. Returns
  /// why the name can't be used, or null once saved.
  Future<String?> savePreset(String name, {required int level, required int kelvin}) async {
    final n = name.trim();
    if (n.isEmpty) return 'Give the scene a name.';
    bool taken(List<Preset> list) => list.any((p) => p.name.toLowerCase() == n.toLowerCase());
    if (taken(presets)) return '$n is already a built-in scene. Pick another name.';
    if (taken(customPresets)) return 'You already have a scene called $n. Pick another name.';
    await _home.savePreset(Preset(n, level, kelvin));
    _say('Saved $n. Tap it to use it.');
    return null;
  }

  Future<void> deletePreset(Preset p) => _home.removePreset(p.name);

  // ---------- backup ----------

  String backupCode() => _home.backupCode();

  /// Shown once the backup code is on the clipboard.
  static const backupCopied = 'Backup code copied.';

  /// Whether clipboard [text] looks like a backup code worth pre-filling.
  static bool looksLikeBackupCode(String? text) =>
      text != null && text.trim().startsWith(Home.backupPrefix);

  /// Why [code] can't be restored, or null if it can.
  static String? checkBackupCode(String code) {
    if (code.trim().isEmpty) return 'Paste your backup code.';
    try {
      Home.fromBackupCode(code);
      return null;
    } catch (_) {
      return 'That backup code is not valid. Paste the full code, starting with LAMPLIGHT1.';
    }
  }

  /// Replaces the lights with a backup. Returns false if the code is not
  /// valid.
  Future<bool> restore(String code) async {
    final invalid = checkBackupCode(code);
    if (invalid != null) {
      _say(invalid, error: true);
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

  Future<void> forgetAll() async {
    await _connection.disconnect();
    await _home.forgetAll();
    _lights.resetStates();
    _say('All lights forgotten.');
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _widgetSub?.cancel();
    _widgets.close();
    removeListener(_syncWidgets);
    _droppedSub.cancel();
    _readySub.cancel();
    for (final l in [_home, _connection, _lights]) {
      l.removeListener(notifyListeners);
    }
    super.dispose();
  }
}
