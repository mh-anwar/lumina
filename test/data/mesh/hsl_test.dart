// Light HSL messages and Composition Data, checked against the Bluetooth
// Mesh specifications and Nordic's nRF Mesh Library for Android:
// - Mesh Model 1.0, 6.3.3.5 Light HSL Set: opcode 0x82 0x76 (Set
//   Unacknowledged 0x82 0x77), then HSL Lightness, HSL Hue and HSL
//   Saturation as little-endian uint16, TID, and optional Transition Time
//   and Delay. nRF Mesh's LightHslSetUnacknowledged.java writes the same
//   fields in the same order (putShort lightness, hue, saturation, put tId).
// - Mesh Profile 1.0.1, 4.2.1.1 Composition Data Page 0: CID, PID, VID,
//   CRPL, Features (uint16 each), then elements of Loc (uint16), NumS,
//   NumV, NumS SIG model ids (uint16) and NumV vendor model ids (CID and
//   model id, uint16 each).
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/data/mesh/bytes.dart';
import 'package:lumina/data/mesh/messages.dart';

void main() {
  group('Light HSL Set', () {
    test('unacknowledged, without a transition', () {
      expect(Msg.hslSet(0x1234, 0x5678, 0x9abc, 7), hex('827734127856bc9a07'));
    });

    test('acknowledged', () {
      // The TID is one byte.
      expect(Msg.hslSet(0xffff, 0, 0x8000, 0x1ff, ack: true), hex('8276ffff00000080ff'));
    });
  });

  group('Composition Data Status', () {
    // Page 0 of a bulb with two elements: element 0 has Configuration
    // Server, Generic OnOff Server, Light HSL Server and one vendor model;
    // element 1 has Light HSL Hue Server.
    List<int> status(int page) => [
      0x02, page,
      0x71, 0x01, 0x08, 0x00, 0x03, 0x00, 0x69, 0x00, 0x07, 0x00, // CID PID VID CRPL Features
      0x00, 0x00, 3, 1, 0x00, 0x00, 0x00, 0x10, 0x07, 0x13, 0x71, 0x01, 0x00, 0xfe,
      0x00, 0x00, 1, 0, 0x0a, 0x13,
    ];

    test('reads page 0', () {
      final c = Composition.parse(status(0))!;
      expect([c.cid, c.pid, c.vid, c.crpl, c.features], [0x0171, 8, 3, 0x69, 7]);
      expect(c.elements.map((e) => e.sigModels), [
        [0x0000, 0x1000, 0x1307],
        [0x130a],
      ]);
      expect(c.elements.first.vendorModels, [0x0171fe00]);
    });

    test(
      'reads page 0 data sent under another page number, as some Sengled color firmware does',
      () {
        expect(Composition.parse(status(0xee))!.sigModels, {0x0000, 0x1000, 0x1307, 0x130a});
      },
    );

    test('rejects an element that runs past the end', () {
      expect(Composition.parse(status(0).sublist(0, 20)), isNull);
    });
  });
}
