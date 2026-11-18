import 'package:lumina/config/dependencies.dart';
import 'package:lumina/data/services/home_store.dart';
import 'package:lumina/data/services/home_widget_service.dart';
import 'package:lumina/data/services/timings.dart';
import 'package:lumina/domain/models/light.dart';
import 'package:lumina/domain/models/nearby_bulb.dart';
import 'package:lumina/ui/features/home/view_models/home_view_model.dart';

import 'mock_bulb.dart';

const fast = Timings(
  scan: Duration(milliseconds: 10),
  addLightScan: Duration(milliseconds: 10),
  defaultScan: Duration(milliseconds: 10),
  bleStatus: Duration(milliseconds: 10),
  bleConnect: Duration(milliseconds: 100),
  bleConnectGuard: Duration(milliseconds: 200),
  notifySettle: Duration(milliseconds: 1),
  beacon: Duration(milliseconds: 100),
  provReply: Duration(seconds: 2),
  configReply: Duration(milliseconds: 300),
  nodeReset: Duration(milliseconds: 100),
  reconnectBase: Duration(milliseconds: 10),
  reconnectStep: Duration(milliseconds: 10),
  throttle: Duration(milliseconds: 20),
  askApp: Duration(milliseconds: 500),
  writeFlush: Duration(milliseconds: 1),
);

Future<void> settle([int ms = 50]) => Future<void>.delayed(Duration(milliseconds: ms));

NearbyBulb nearby(MockBulb b) => NearbyBulb(id: b.id, name: b.name, rssi: b.rssi);

/// The app's object graph over simulated bulbs.
class Harness extends Dependencies {
  Harness(FakeBle ble, [MemoryHomeStore? store, Timings timings = fast])
    : super(
        ble: ble,
        store: store ?? MemoryHomeStore(),
        timings: timings,
        widgetService: MemoryHomeWidgetService(),
        widgetPort: 'lumina.test.${_harnesses++}',
      );

  static var _harnesses = 0;

  @override
  MemoryHomeWidgetService get widgetService => super.widgetService as MemoryHomeWidgetService;

  @override
  FakeBle get ble => super.ble as FakeBle;

  @override
  MemoryHomeStore get store => super.store as MemoryHomeStore;

  HomeViewModel get vm => homeViewModel;

  /// A loaded harness.
  static Future<Harness> start(FakeBle ble, [MemoryHomeStore? store]) async {
    final h = Harness(ble, store);
    await h.home.load();
    return h;
  }

  /// Adds [b] through the home screen's flow.
  Future<bool> add(MockBulb b) => vm.addLight(nearby(b));

  List<Light> get all => home.home.lights;
  Light get single => all.single;
}
