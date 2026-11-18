import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/domain/models/preset.dart';
import 'package:lumina/domain/models/widget_action.dart';

void main() {
  test('actions travel as luminar:// URIs', () {
    for (final a in [
      const ToggleAllAction(),
      for (final p in presets) ApplyPresetAction(p),
      const ToggleLightAction(0x10),
    ]) {
      final back = WidgetAction.fromUri(a.toUri());
      expect(back.runtimeType, a.runtimeType);
      if (a is ApplyPresetAction) expect((back! as ApplyPresetAction).preset, a.preset);
      if (a is ToggleLightAction) expect((back! as ToggleLightAction).addr, a.addr);
    }
    expect(const ToggleAllAction().toUri().toString(), 'luminar://toggle');
    expect(ApplyPresetAction(presets[1]).toUri().toString(), 'luminar://preset?name=Read');
    expect(const ToggleLightAction(0x10).toUri().toString(), 'luminar://light?addr=0x0010');
  });

  test('ignores URIs it does not know', () {
    for (final u in [
      'other://toggle',
      'luminar://nope',
      'luminar://preset?name=Disco',
      'luminar://light',
      'luminar://light?addr=lamp',
      'luminar://light?addr=0xC000', // a group, not one light
      null,
    ]) {
      expect(WidgetAction.fromUri(u == null ? null : Uri.parse(u)), isNull, reason: '$u');
    }
  });
}
