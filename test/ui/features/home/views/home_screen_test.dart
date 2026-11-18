import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lumina/config/dependencies.dart';
import 'package:lumina/data/services/home_store.dart';
import 'package:lumina/data/services/home_widget_service.dart';
import 'package:lumina/main.dart';
import 'package:lumina/ui/features/home/view_models/home_view_model.dart';
import 'package:provider/provider.dart';

import '../../../../support/harness.dart';
import '../../../../support/mock_bulb.dart';

/// Pumps the app with the real dependency graph over [ble]. Returns the
/// home screen's view model.
Future<HomeViewModel> pumpApp(WidgetTester tester, FakeBle ble, Brightness b) async {
  tester.view.physicalSize = const Size(390 * 2, 1400 * 2);
  tester.view.devicePixelRatio = 2;
  tester.platformDispatcher.platformBrightnessTestValue = b;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  // Build the graph in the real zone, so its stream listeners and saves
  // do not wait on the fake clock.
  final deps = (await tester.runAsync(() async {
    final d = Dependencies(
      ble: ble,
      store: MemoryHomeStore(),
      timings: fast,
      widgetService: MemoryHomeWidgetService(),
      widgetPort: 'lumina.test.screen.${b.name}',
    );
    d.providers; // creates every object
    return d;
  }))!;
  await tester.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('app'),
      child: MultiProvider(providers: deps.providers, child: const LuminaApp()),
    ),
  );
  // Let the home load in the real zone.
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
  await tester.pumpAndSettle();
  return deps.homeViewModel;
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;
  debugPrint = debugPrintSynchronously;

  // Light mode only: CI renders both themes in tool/screenshots.
  const b = Brightness.light;
  testWidgets('empty state, add a light, control it', (tester) async {
    final bulbA = MockBulb('AA:01', 'BLE Bulb_7B2E');
    final bulbB = MockBulb('AA:02', 'BLE Bulb_A9CB', rssi: -80);
    final vm = await pumpApp(tester, FakeBle([bulbA, bulbB]), b);

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('No lights yet'), findsOneWidget);

    // The add sheet lists both unprovisioned bulbs.
    await tester.tap(find.text('Add a light'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.text('BLE Bulb_7B2E'), findsOneWidget);
    expect(find.text('BLE Bulb_A9CB'), findsOneWidget);
    await tester.tapAt(const Offset(20, 20)); // dismiss the sheet
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      expect(await vm.addLight(nearby(bulbA)), isTrue);
      await vm.setPower(vm.lights.single, true);
      await vm.saveScene('Evening');
    });
    await tester.pumpAndSettle();
    expect(find.text('Evening'), findsOneWidget);
    expect(find.text('Connected'), findsOneWidget);
    expect(find.text('All lights'), findsNothing, reason: 'one light needs no all-lights tile');

    // Tapping the tile switches the light.
    await tester.tap(find.text('BLE Bulb_7B2E'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(bulbA.on, isFalse);
    expect(find.text('Off'), findsOneWidget);

    // Dragging sideways across the tile turns it on and dims it.
    await tester.drag(find.text('BLE Bulb_7B2E'), const Offset(60, 0));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(vm.stateOf(vm.lights.single).on, isTrue);

    // New makes a scene from a brightness and white for every light.
    await tester.tap(find.text('New'));
    await tester.pumpAndSettle();
    expect(find.text('New scene'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Cozy');
    await tester.tap(find.text('Warm'));
    await tester.tap(find.text('Save scene'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.text('New scene'), findsNothing);
    expect(find.text('Cozy'), findsOneWidget);
    expect(vm.customPresets.single.kelvin, 2700);

    // The tune button opens the light's own controls.
    await tester.tap(find.byTooltip('More for BLE Bulb_7B2E'));
    await tester.pumpAndSettle();
    expect(find.text('Brightness'), findsOneWidget);
    expect(find.text('Remove light'), findsOneWidget);
    expect(find.text('When the switch turns it on'), findsOneWidget);
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    // Settings holds backups and the activity log.
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Back up lights'), findsOneWidget);
    await tester.tap(find.text('Activity log'));
    await tester.pumpAndSettle();
    expect(find.textContaining('BLE Bulb_7B2E is ready.'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.runAsync(vm.disconnect);
  }, timeout: const Timeout(Duration(seconds: 40)));
}
