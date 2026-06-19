import 'package:flutter_test/flutter_test.dart';
import 'package:no_snooze/screens/ring_screen.dart';

// ENG-01 / ENG-02 (Plan 04-03): pure-testable parts of the two-stage handoff.
//
// The live audio handoff + camera mission are device-verified in Task 2 (no CLI
// substitute exists). What IS unit-testable here is the ringtone-source
// RESOLUTION branch (Pitfall 6): the app stores `ringtonePath` either as the
// full bundled-asset path ('assets/sounds/alarmN.mp3') OR a device-file path
// (custom ringtone picked via file_picker). The soft loop must build an
// AssetSource (with the 'assets/' prefix STRIPPED, because audioplayers
// re-prepends it) for the former and a DeviceFileSource for the latter.
void main() {
  group('resolveSoftLoopSource (Pitfall 6 — AssetSource vs DeviceFileSource)', () {
    test('an assets/ path resolves to an asset source with the prefix stripped', () {
      final r = resolveSoftLoopSource('assets/sounds/alarm1.mp3');
      expect(r.isAsset, isTrue);
      // audioplayers AssetSource re-prepends 'assets/', so the key must NOT
      // contain it (a double 'assets/assets/...' would 404 the asset).
      expect(r.value, 'sounds/alarm1.mp3');
    });

    test('a bundled asset with a different folder still strips only the leading assets/', () {
      final r = resolveSoftLoopSource('assets/foo/bar.mp3');
      expect(r.isAsset, isTrue);
      expect(r.value, 'foo/bar.mp3');
    });

    test('a device-file path resolves to a device-file source verbatim', () {
      final r = resolveSoftLoopSource('/storage/emulated/0/Music/custom.mp3');
      expect(r.isAsset, isFalse);
      expect(r.value, '/storage/emulated/0/Music/custom.mp3');
    });

    test('a Windows-style absolute device path is treated as a device file', () {
      final r = resolveSoftLoopSource(r'C:\Users\me\ring.mp3');
      expect(r.isAsset, isFalse);
      expect(r.value, r'C:\Users\me\ring.mp3');
    });

    test('an empty path is a device-file (non-asset) — never crashes the handoff', () {
      final r = resolveSoftLoopSource('');
      expect(r.isAsset, isFalse);
      expect(r.value, '');
    });
  });
}
