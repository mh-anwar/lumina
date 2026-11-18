import 'package:lumina/data/repositories/connection_repository.dart';
import 'package:lumina/data/repositories/home_repository.dart';
import 'package:lumina/data/repositories/light_repository.dart';
import 'package:lumina/domain/models/widget_action.dart';

/// Runs a widget tap while the app is not running: connect, send one
/// command, report what the widget should show.
class WidgetActionUseCase {
  WidgetActionUseCase({required this._connection, required this._lights, required this._home});

  final ConnectionRepository _connection;
  final LightRepository _lights;
  final HomeRepository _home;

  /// [wasOn] is the last known state of the lights the action switches
  /// (all of them, or the one light), since a fresh connection has not
  /// heard from them yet.
  Future<WidgetStatus> call(WidgetAction action, {required bool wasOn}) async {
    // A light that was removed, reset or not set up can't be switched.
    final ready = {for (final l in _home.home.ready) l.addr};
    if (action is ToggleLightAction && !ready.contains(action.addr)) {
      return WidgetStatus.unavailable;
    }
    if (!_connection.isConnected && await _connection.connect() is! Connected) {
      return WidgetStatus.unavailable;
    }
    switch (action) {
      case ToggleAllAction():
        await _lights.setAllPower(!wasOn);
        return wasOn ? WidgetStatus.off : WidgetStatus.on;
      case ApplyPresetAction(:final preset):
        await _lights.applyPreset(preset);
        return WidgetStatus.on;
      case ToggleLightAction(:final addr):
        await _lights.setPower(addr, !wasOn);
        return wasOn ? WidgetStatus.off : WidgetStatus.on;
    }
  }
}
