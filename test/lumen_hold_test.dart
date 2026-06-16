import 'package:flutter_test/flutter_test.dart';
import 'package:no_snooze/constants/app_constants.dart';
import 'package:no_snooze/l10n/app_strings.dart';

// MIS-01 / D-02 characterization: the pure sustained-hold helpers backing the
// Lümen mission. Hold is SUSTAINED, not cumulative — any below-threshold frame
// resets progress to 0. Also pins the calibratable constants and asserts TR/EN
// parity for every new mission string.
void main() {
  group('accumulateHold (D-02 sustained, not cumulative)', () {
    test('adds dtMs when avgY >= kLumenThreshold', () {
      expect(accumulateHold(0, kLumenThreshold, 100), 100);
      expect(accumulateHold(500, kLumenThreshold + 50, 100), 600);
    });

    test('avgY exactly at threshold counts (>=)', () {
      expect(accumulateHold(200, kLumenThreshold, 50), 250);
    });

    test('resets to 0 when avgY < kLumenThreshold (any drop)', () {
      expect(accumulateHold(2000, kLumenThreshold - 1, 100), 0);
      expect(accumulateHold(2400, 0, 100), 0);
    });
  });

  group('lumenComplete', () {
    test('true exactly at/after kLumenHoldMs', () {
      expect(lumenComplete(kLumenHoldMs), isTrue);
      expect(lumenComplete(kLumenHoldMs + 1), isTrue);
    });

    test('false below kLumenHoldMs', () {
      expect(lumenComplete(kLumenHoldMs - 1), isFalse);
      expect(lumenComplete(0), isFalse);
    });
  });

  group('simulated tick sequence', () {
    test('above-threshold ticks reach completion at/after kLumenHoldMs', () {
      const dt = 100;
      int held = 0;
      while (!lumenComplete(held)) {
        held = accumulateHold(held, kLumenThreshold + 10, dt);
      }
      expect(held >= kLumenHoldMs, isTrue);
    });

    test('a below-threshold tick mid-sequence resets progress to 0', () {
      int held = 0;
      held = accumulateHold(held, kLumenThreshold + 10, 1000); // 1000
      held = accumulateHold(held, kLumenThreshold + 10, 1000); // 2000
      expect(held, 2000);
      held = accumulateHold(held, kLumenThreshold - 50, 100); // drop => reset
      expect(held, 0);
      expect(lumenComplete(held), isFalse);
    });
  });

  group('constant values pinned (calibration regression guard)', () {
    test('kLumenThreshold is 140 (avg-Y 0..255, exposure-locked calibration)', () {
      expect(kLumenThreshold, 140);
    });
    test('kLumenHoldMs is 2500 (~2.5s sustained)', () {
      expect(kLumenHoldMs, 2500);
    });
  });

  group('TR/EN parity for new mission strings', () {
    const keys = [
      'mission_lumen_title',
      'mission_lumen_guide',
      'mission_lumen_brighter',
      'mission_lumen_hold',
      'mission_sound_lowered',
      'mission_menu_title',
      'mission_none',
      'mission_lumen_name',
      'mission_select_title',
    ];

    test('every new key returns non-empty for BOTH tr and en', () {
      for (final key in keys) {
        final tr = AppStrings.get(key, 'tr');
        final en = AppStrings.get(key, 'en');
        // get() returns the key itself as fallback when missing — so a present
        // key must differ from the bare key (or at minimum be non-empty).
        expect(tr.isNotEmpty, isTrue, reason: 'TR missing for $key');
        expect(en.isNotEmpty, isTrue, reason: 'EN missing for $key');
        expect(tr, isNot(key), reason: 'TR not defined for $key');
        expect(en, isNot(key), reason: 'EN not defined for $key');
      }
    });
  });
}
