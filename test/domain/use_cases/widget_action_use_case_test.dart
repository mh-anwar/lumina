import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/domain/models/preset.dart';
import 'package:lumina/domain/models/widget_action.dart';

import '../../support/harness.dart';
import '../../support/mock_bulb.dart';

void main() {
  late List<MockBulb> bulbs;
  late FakeBle ble;
  late Harness background;

  // Two lights added by the app, then a fresh process (the widget's
  // background isolate) on the same store.
  setUp(() async {
    bulbs = [MockBulb('AA:01', 'BLE Bulb_A9CB'), MockBulb('AA:02', 'BLE Bulb_A9CC')];
    ble = FakeBle(bulbs);
    final app = await Harness.start(ble);
    for (final b in bulbs) {
      await app.add(b);
    }
    await app.connection.disconnect();
    background = await Harness.start(ble, app.store);
  });

  test('connects and toggles from the state the widget showed', () async {
    for (final b in bulbs) {
      b.on = true;
    }
    final before = bulbs.fold(0, (n, b) => n + b.fromPhone);
    expect(await background.widgetAction(const ToggleAllAction(), wasOn: true), WidgetStatus.off);
    await settle();
    expect(bulbs.map((b) => b.on), everyElement(isFalse));
    // One group message, no state queries: the widget knew the state.
    expect(bulbs.fold(0, (n, b) => n + b.fromPhone) - before, 1);

    expect(await background.widgetAction(const ToggleAllAction(), wasOn: false), WidgetStatus.on);
    await settle();
    expect(bulbs.map((b) => b.on), everyElement(isTrue));
  });

  test('applies a preset', () async {
    final daylight = presets.firstWhere((p) => p.name == 'Daylight');
    expect(
      await background.widgetAction(ApplyPresetAction(daylight), wasOn: false),
      WidgetStatus.on,
    );
    await settle();
    expect(bulbs.map((b) => b.kelvin), everyElement(6500));
  });

  test('switches one light from its last known state', () async {
    expect(
      await background.widgetAction(const ToggleLightAction(0x10), wasOn: false),
      WidgetStatus.on,
    );
    await settle();
    expect(bulbs.map((b) => b.on), [true, false]);

    expect(
      await background.widgetAction(const ToggleLightAction(0x10), wasOn: true),
      WidgetStatus.off,
    );
    await settle();
    expect(bulbs[0].on, isFalse);
  });

  test('reports unavailable for a light that is gone', () async {
    expect(
      await background.widgetAction(const ToggleLightAction(0x20), wasOn: false),
      WidgetStatus.unavailable,
    );
  });

  test('reports unavailable when no light is in range', () async {
    ble.bulbs.clear();
    expect(
      await background.widgetAction(const ToggleAllAction(), wasOn: false),
      WidgetStatus.unavailable,
    );
  });
}
