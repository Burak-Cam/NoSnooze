import '../models/alarm_entity.dart';

/// Anti-cheat / streak pure logic (TST-01). Relocated verbatim from `main.dart`
/// so it has a real service-layer destination before 02-04 rewrites the test
/// imports. Kept PURE — no SharedPreferences, no BuildContext — so
/// cheat_logic_test / streak_logic_test stay valid unit oracles.

/// Anti-cheat decision outcome on cold start (D-01/FIX-02).
enum CheatVerdict { reset, preserve, none }

/// FIX-02 / D-01: decide whether a leftover ringing flag means the user
/// genuinely escaped (reset streak) or the app was OEM-killed/crashed/rebooted
/// (preserve streak). If the app was not ringing, there is nothing to judge.
///
/// - !wasRinging                  => [CheatVerdict.none]
/// - wasRinging && escapeDetected => [CheatVerdict.reset]
/// - wasRinging && !escapeDetected => [CheatVerdict.preserve]
CheatVerdict decideCheat(
    {required bool wasRinging, required bool escapeDetected}) {
  if (!wasRinging) return CheatVerdict.none;
  return escapeDetected ? CheatVerdict.reset : CheatVerdict.preserve;
}

/// FIX-04 / D-02/D-03/D-04: a day counts toward the streak only when a REAL
/// wake alarm is dismissed and the day has not already been counted. Test and
/// snooze alarms never count; a second scan the same day is neutral.
bool streakEligible(AlarmKind kind, String? lastScanDate, String today) =>
    kind == AlarmKind.real && lastScanDate != today;
