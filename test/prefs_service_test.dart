import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:no_snooze/services/prefs_service.dart';

// ARC-02 / D-02: the PrefsService facade must route all 13 keys with the EXACT
// original null-fallback defaults (a missed/mistyped key is a silent break,
// Pitfall 6). Uses SharedPreferences.setMockInitialValues for a clean fake
// store per test (RESEARCH §"Don't Hand-Roll").
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<PrefsService> svc() async =>
      PrefsService(await SharedPreferences.getInstance());

  group('PrefsService defaults when unset', () {
    test('appLang defaults to null', () async {
      expect((await svc()).appLang, isNull);
    });
    test('isDarkMode defaults to true', () async {
      expect((await svc()).isDarkMode, isTrue);
    });
    test('ringtonePath defaults to assets/sounds/alarm1.mp3', () async {
      expect((await svc()).ringtonePath, 'assets/sounds/alarm1.mp3');
    });
    test('alarmIdCounter defaults to 0', () async {
      expect((await svc()).alarmIdCounter, 0);
    });
    test('escapeDetected defaults to false', () async {
      expect((await svc()).escapeDetected, isFalse);
    });
    test('isRinging defaults to false', () async {
      expect((await svc()).isRinging, isFalse);
    });
    test('isRingingSetAt defaults to null', () async {
      expect((await svc()).isRingingSetAt, isNull);
    });
    test('snoozeTokens defaults to 0', () async {
      expect((await svc()).snoozeTokens, 0);
    });
    test('userStreak defaults to 0', () async {
      expect((await svc()).userStreak, 0);
    });
    test('batteryDialogSeen defaults to false', () async {
      expect((await svc()).batteryDialogSeen, isFalse);
    });
    test('alarmsData defaults to null', () async {
      expect((await svc()).alarmsData, isNull);
    });
    test('targetBarcodes defaults to empty list', () async {
      expect((await svc()).targetBarcodes, isEmpty);
    });
    test('lastScanDate defaults to null', () async {
      expect((await svc()).lastScanDate, isNull);
    });
  });

  group('PrefsService set -> get round-trip', () {
    test('appLang', () async {
      final s = await svc();
      await s.setAppLang('en');
      expect(s.appLang, 'en');
    });
    test('isDarkMode', () async {
      final s = await svc();
      await s.setDarkMode(false);
      expect(s.isDarkMode, isFalse);
    });
    test('ringtonePath', () async {
      final s = await svc();
      await s.setRingtonePath('assets/sounds/alarm9.mp3');
      expect(s.ringtonePath, 'assets/sounds/alarm9.mp3');
    });
    test('alarmIdCounter', () async {
      final s = await svc();
      await s.setAlarmIdCounter(42);
      expect(s.alarmIdCounter, 42);
    });
    test('escapeDetected', () async {
      final s = await svc();
      await s.setEscapeDetected(true);
      expect(s.escapeDetected, isTrue);
    });
    test('isRinging', () async {
      final s = await svc();
      await s.setRinging(true);
      expect(s.isRinging, isTrue);
    });
    test('isRingingSetAt', () async {
      final s = await svc();
      await s.setRingingSetAt(1700000000000);
      expect(s.isRingingSetAt, 1700000000000);
    });
    test('snoozeTokens', () async {
      final s = await svc();
      await s.setSnoozeTokens(3);
      expect(s.snoozeTokens, 3);
    });
    test('userStreak', () async {
      final s = await svc();
      await s.setUserStreak(7);
      expect(s.userStreak, 7);
    });
    test('batteryDialogSeen', () async {
      final s = await svc();
      await s.setBatteryDialogSeen(true);
      expect(s.batteryDialogSeen, isTrue);
    });
    test('alarmsData', () async {
      final s = await svc();
      await s.setAlarmsData('[]');
      expect(s.alarmsData, '[]');
    });
    test('targetBarcodes', () async {
      final s = await svc();
      await s.setTargetBarcodes(['123', '456']);
      expect(s.targetBarcodes, ['123', '456']);
    });
    test('lastScanDate', () async {
      final s = await svc();
      await s.setLastScanDate('2026-06-14');
      expect(s.lastScanDate, '2026-06-14');
    });
  });
}
