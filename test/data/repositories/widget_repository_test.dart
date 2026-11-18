import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/data/repositories/widget_repository.dart';
import 'package:lumina/data/services/home_widget_service.dart';
import 'package:lumina/domain/models/widget_action.dart';

void main() {
  test('redraws what the background isolate changed', () async {
    // One storage, as the app and the widget's isolate share the plugin's.
    final service = MemoryHomeWidgetService();
    final app = WidgetRepository(service: service, portName: 'lumina.test.redraw');
    final isolate = WidgetRepository(service: service, portName: 'lumina.test.redraw');
    await app.show(WidgetStatus.on);
    await app.show(WidgetStatus.on);
    expect(service.shown, [WidgetStatus.on], reason: 'no redraw when nothing changed');

    await isolate.show(WidgetStatus.unavailable);
    await app.show(WidgetStatus.on);
    expect(service.shown.last, WidgetStatus.on);
  });

  test('remembers on or off apart from what the widget shows', () async {
    final r = WidgetRepository(service: MemoryHomeWidgetService(), portName: 'lumina.test.on');
    expect(await r.lastOn(), isNull);
    await r.show(WidgetStatus.on);
    await r.show(WidgetStatus.busy);
    await r.show(WidgetStatus.unavailable);
    expect(await r.lastOn(), isTrue, reason: 'a tap now turns the lights off');

    await r.showLight(0x10, WidgetStatus.off);
    await r.showLight(0x10, WidgetStatus.busy);
    expect(await r.lastLightOn(0x10), isFalse);
    expect(await r.lastLightOn(0x11), isNull);
  });

  test('hands a tap to the running app and returns its answer', () async {
    final app = WidgetRepository(service: MemoryHomeWidgetService(), portName: 'lumina.test.app');
    final widget = WidgetRepository(
      service: MemoryHomeWidgetService(),
      portName: 'lumina.test.app',
    );
    expect(await widget.askApp(const ToggleAllAction()), isNull, reason: 'app not running');

    final seen = <WidgetAction>[];
    app.listen().listen((r) {
      seen.add(r.action);
      r.reply(WidgetStatus.off);
    });
    expect(await widget.askApp(const ToggleAllAction()), WidgetStatus.off);
    expect(seen.single, isA<ToggleAllAction>());

    app.close();
    expect(await widget.askApp(const ToggleAllAction()), isNull, reason: 'app closed');
  });

  test('gives up on an app that does not answer', () async {
    final app = WidgetRepository(service: MemoryHomeWidgetService(), portName: 'lumina.test.mute');
    app.listen().listen((_) {});
    final widget = WidgetRepository(
      service: MemoryHomeWidgetService(),
      portName: 'lumina.test.mute',
    );
    expect(
      await widget.askApp(const ToggleAllAction(), timeout: const Duration(milliseconds: 50)),
      WidgetStatus.unavailable,
    );
    app.close();
  });
}
