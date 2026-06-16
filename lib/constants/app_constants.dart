/// FIX-04 / D-07: the camera/vibration restart cooldown after a RESTART
/// dismiss. Safe-side 2.5s value (RLS-05) — pinned by cooldown_value_test.dart.
const int kCameraRestartCooldownMs = 2500;

/// D-01: the maximum number of dismissal barcodes a user may register
/// (CLAUDE.md "barcode CRUD max 3"). Both `_HomeScreenState` barcode guards
/// (length >= [kMaxBarcodes] / length < [kMaxBarcodes]) reference this.
const int kMaxBarcodes = 3;

/// MIS-01 / D-03: the average-luminance threshold (avg-Y on a 0..255 scale)
/// a camera frame must reach to count as "bright enough" for the Lümen
/// mission. Device-calibrated on the Redmi Note 9S (Plan 03 checkpoint): with
/// AUTO-exposure the frame average is pinned to ~mid-gray (~110) no matter how
/// bright the scene, so LumenMission now LOCKS exposure (see lumen_mission.dart)
/// to make the average track real brightness. With exposure locked, 140 sits
/// above the locked ambient baseline so the user must point at a genuinely
/// bright light. Pinned by lumen_hold_test.dart so a regression is caught.
const double kLumenThreshold = 140;

/// MIS-01 / D-02: how long (ms) average luminance must be SUSTAINED at/above
/// [kLumenThreshold] to complete the Lümen mission (~2-3s sustained, NOT
/// cumulative — any drop resets). [ASSUMED] starting value, device-calibrated
/// in Plan 03. Pinned by lumen_hold_test.dart.
const int kLumenHoldMs = 2500;

/// MIS-01 / D-02: pure sustained-hold accumulator. Adds [dtMs] to [heldMs] when
/// the frame's [avgY] is at/above [kLumenThreshold]; otherwise RESETS to 0 (a
/// single below-threshold frame wipes progress — sustained, not cumulative).
int accumulateHold(int heldMs, double avgY, int dtMs) =>
    avgY >= kLumenThreshold ? heldMs + dtMs : 0;

/// MIS-01 / D-02: the Lümen mission is complete once accumulated [heldMs]
/// reaches [kLumenHoldMs].
bool lumenComplete(int heldMs) => heldMs >= kLumenHoldMs;
