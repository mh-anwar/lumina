import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:lumina/data/repositories/provisioning_repository.dart';
import 'package:lumina/domain/models/nearby_bulb.dart';

/// Scans for bulbs that are ready to add.
class AddLightViewModel extends ChangeNotifier {
  AddLightViewModel({required this._provisioning, this.rescanPause = const Duration(seconds: 1)});

  final ProvisioningRepository _provisioning;

  /// Pause before scanning again after a scan ends, so a scan that ends at
  /// once (no Bluetooth, or a fake in tests) doesn't restart in a tight loop.
  final Duration rescanPause;
  Timer? _rescan;
  StreamSubscription<List<NearbyBulb>>? _sub;

  List<NearbyBulb> _found = const [];
  bool _scanning = false;
  String? _error;

  // Signal readings jump by 10 dB or more between adverts. Keep bulbs in the
  // order they were first found, so rows never move under the user's
  // finger, and smooth each bulb's signal so its label does not flicker.
  final _order = <String>[];
  final _names = <String, String>{};
  final _replaces = <String, String?>{};
  final _rssi = <String, double>{};
  static const _smoothing = 0.3;

  /// In the order they were first found, with smoothed signal strength.
  List<NearbyBulb> get found => _found;
  bool get scanning => _scanning;
  String? get error => _error;

  bool _stopped = false;

  /// Looks for bulbs until [stop], starting a new scan whenever one ends, so
  /// a bulb reset while the sheet is open shows up without a Scan again tap.
  void scan() {
    _stopped = false;
    unawaited(_sub?.cancel());
    _scanning = true;
    _error = null;
    _order.clear();
    _names.clear();
    _replaces.clear();
    _rssi.clear();
    _found = const [];
    notifyListeners();
    _listen();
  }

  void _listen() {
    _sub = _provisioning.scan().listen(
      (list) {
        _update(list);
        notifyListeners();
      },
      onError: (Object e) {
        _error = e.toString();
        _scanning = false;
        notifyListeners();
      },
      onDone: () {
        if (!_stopped && _error == null) {
          _rescan = Timer(rescanPause, () {
            if (!_stopped) _listen();
          });
          return;
        }
        _scanning = false;
        notifyListeners();
      },
    );
  }

  void _update(List<NearbyBulb> list) {
    for (final b in list) {
      final prev = _rssi[b.id];
      if (prev == null) _order.add(b.id);
      _rssi[b.id] = prev == null ? b.rssi.toDouble() : prev + _smoothing * (b.rssi - prev);
      _names[b.id] = b.name;
      _replaces[b.id] = b.replaces;
    }
    _found = [
      for (final id in _order)
        NearbyBulb(id: id, name: _names[id]!, rssi: _rssi[id]!.round(), replaces: _replaces[id]),
    ];
  }

  Future<void> stop() async {
    _stopped = true;
    _rescan?.cancel();
    await _sub?.cancel();
    _sub = null;
    await _provisioning.stopScan();
  }

  /// The row title: the light's name for a bulb that was one of ours.
  static String title(NearbyBulb b) => b.replaces ?? b.name;

  /// The row subtitle: signal strength, and whether it replaces a light.
  static String subtitle(NearbyBulb b) =>
      b.replaces == null ? signal(b.rssi) : 'Was reset, sets it up again · ${signal(b.rssi)}';

  static String signal(int rssi) => rssi > -60
      ? 'Very close'
      : rssi > -75
      ? 'Nearby'
      : 'Far away, move closer';

  @override
  void dispose() {
    _stopped = true;
    _rescan?.cancel();
    unawaited(_sub?.cancel());
    super.dispose();
  }
}
