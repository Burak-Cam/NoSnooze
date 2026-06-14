import 'package:alarm/alarm.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:no_snooze/models/alarm_entity.dart';
import 'package:no_snooze/services/alarm_service.dart';

// TST-02: reschedule date math is unit-testable via the injectable
// [AlarmGateway] seam. We assert (a) calculateAlarmDateTime invariants survive
// the move, and (b) scheduleAlarmFn funnels through the gateway exactly once
// with a DateTime equal to calculateAlarmDateTime's next occurrence.

class MockAlarmGateway extends Mock implements AlarmGateway {}

class _FakeAlarmSettings extends Fake implements AlarmSettings {}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeAlarmSettings());
  });

  group('calculateAlarmDateTime — one-time (repeatDays empty)', () {
    test('result matches requested hour/minute', () {
      final result =
          calculateAlarmDateTime(const TimeOfDay(hour: 9, minute: 15), const []);
      expect(result.hour, 9);
      expect(result.minute, 15);
      expect(result.second, 0);
    });

    test('result is now-or-future and within the next 24 hours', () {
      final now = DateTime.now();
      final result = calculateAlarmDateTime(
        TimeOfDay(hour: now.hour, minute: now.minute),
        const [],
      );
      expect(result.isBefore(now.subtract(const Duration(seconds: 1))), isFalse);
      expect(result.difference(now).inHours.abs() <= 24, isTrue);
    });

    test('a time already passed today rolls to tomorrow', () {
      final now = DateTime.now();
      final past = now.subtract(const Duration(hours: 1));
      final result = calculateAlarmDateTime(
        TimeOfDay(hour: past.hour, minute: past.minute),
        const [],
      );
      expect(result.isAfter(now), isTrue);
    });
  });

  group('calculateAlarmDateTime — repeating', () {
    test('returns a day whose weekday is in repeatDays', () {
      const repeat = [1, 2, 3, 4, 5];
      final result =
          calculateAlarmDateTime(const TimeOfDay(hour: 6, minute: 0), repeat);
      expect(repeat.contains(result.weekday), isTrue);
    });
  });

  group('incrementId', () {
    test('increments by one', () {
      expect(incrementId(0), 1);
      expect(incrementId(41), 42);
    });
  });

  group('scheduleAlarmFn via injectable AlarmGateway (TST-02)', () {
    late MockAlarmGateway gateway;

    setUp(() {
      gateway = MockAlarmGateway();
      when(() => gateway.set(any())).thenAnswer((_) async {});
      when(() => gateway.stop(any())).thenAnswer((_) async {});
    });

    test('calls gateway.set exactly once', () async {
      await scheduleAlarmFn(
        7,
        DateTime(2030, 1, 1, 6, 0),
        true,
        'en',
        'assets/sounds/alarm1.mp3',
        'Wake',
        AlarmKind.real,
        gateway: gateway,
      );
      verify(() => gateway.set(any())).called(1);
    });

    test('schedules the DateTime returned by calculateAlarmDateTime', () async {
      final scheduled = calculateAlarmDateTime(
        const TimeOfDay(hour: 6, minute: 30),
        const [1, 2, 3, 4, 5],
      );
      await scheduleAlarmFn(
        7,
        scheduled,
        true,
        'en',
        'assets/sounds/alarm1.mp3',
        'Wake',
        AlarmKind.real,
        gateway: gateway,
      );
      final captured = verify(() => gateway.set(captureAny())).captured.single
          as AlarmSettings;
      expect(captured.dateTime, scheduled);
      expect(captured.id, 7);
    });

    test('encodes the AlarmKind in the payload', () async {
      await scheduleAlarmFn(
        9,
        DateTime(2030, 1, 1, 6, 0),
        false,
        'tr',
        'assets/sounds/alarm1.mp3',
        'Test',
        AlarmKind.test,
        gateway: gateway,
      );
      final captured = verify(() => gateway.set(captureAny())).captured.single
          as AlarmSettings;
      expect(captured.payload, contains('test'));
      expect(captured.loopAudio, isTrue);
    });
  });
}
