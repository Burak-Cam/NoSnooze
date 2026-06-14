/// FIX-04 / D-07: the camera/vibration restart cooldown after a RESTART
/// dismiss. Safe-side 2.5s value (RLS-05) — pinned by cooldown_value_test.dart.
const int kCameraRestartCooldownMs = 2500;

/// D-01: the maximum number of dismissal barcodes a user may register
/// (CLAUDE.md "barcode CRUD max 3"). Both `_HomeScreenState` barcode guards
/// (length >= [kMaxBarcodes] / length < [kMaxBarcodes]) reference this.
const int kMaxBarcodes = 3;
