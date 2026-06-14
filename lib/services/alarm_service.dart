import 'dart:convert';

import 'package:alarm/alarm.dart';
import 'package:flutter/material.dart' show TimeOfDay;

import '../l10n/app_strings.dart';
import '../models/alarm_entity.dart';
import 'prefs_service.dart';

/// TST-02 / RESEARCH A2: a thin injectable seam over the static `Alarm` API.
/// This is the ONLY place that touches `Alarm.set` / `Alarm.stop`, so the
/// reschedule/date logic in [scheduleAlarmFn] becomes unit-testable: tests pass
/// a `MockAlarmGateway` and assert `verify(() => gateway.set(...)).called(1)`.
/// The production default delegates verbatim to the static API (behavior
/// preserved).
class AlarmGateway {
  const AlarmGateway();

  Future<void> set(AlarmSettings alarmSettings) =>
      Alarm.set(alarmSettings: alarmSettings);

  Future<void> stop(int id) => Alarm.stop(id);
}

/// Default production gateway. Reused so every non-test call site keeps the
/// exact prior behavior without allocating a fresh instance.
const AlarmGateway defaultAlarmGateway = AlarmGateway();

/// The single funnel for ALL alarm scheduling (re-arm correctness underpins
/// FIX-01). Builds the [AlarmSettings] (payload jsonEncode {'kind': ...},
/// looping audio, fade volume, full-screen intent) and routes through the
/// injectable [gateway] so reschedule date math is unit-testable. Behavior is
/// byte-for-byte preserved from the prior in-`main.dart` implementation.
///
/// FIX-04 / D-03: the alarm TYPE is carried out-of-band via the payload so the
/// RingScreen can gate the streak (real vs test vs snooze). Legacy alarms with
/// a null payload decode to [AlarmKind.real] (Pitfall 2).
Future<void> scheduleAlarmFn(
  int id,
  DateTime dateTime,
  bool vibrate,
  String lang,
  String audioPath,
  String label,
  AlarmKind alarmType, {
  AlarmGateway gateway = defaultAlarmGateway,
}) async {
  final alarmSettings = AlarmSettings(
    id: id,
    dateTime: dateTime,
    assetAudioPath: audioPath,
    loopAudio: true,
    vibrate: vibrate,
    payload: jsonEncode({'kind': alarmType.name}),
    volumeSettings: VolumeSettings.fade(
      volume: 1.0,
      fadeDuration: const Duration(seconds: 3),
      volumeEnforced: true,
    ),
    notificationSettings: NotificationSettings(
      title: label.isEmpty ? 'NoSnooze' : label,
      body: AppStrings.get('notification_body', lang),
      stopButton: null,
      icon: 'notification_icon',
    ),
    warningNotificationOnKill: true,
    androidFullScreenIntent: true,
  );
  await gateway.set(alarmSettings);
}

/// FIX-05: monotonic id step. Pure helper backing the SharedPreferences
/// `alarm_id_counter` so unit tests can assert it never collides.
int incrementId(int prior) => prior + 1;

/// FIX-05 (RESEARCH Q1): mint the next unique alarm id from the persisted
/// monotonic counter `alarm_id_counter`. Used for ALL ids — entity, snooze and
/// test alarms — so two alarms minted in the same millisecond never collide
/// (the old `% N` of millisecondsSinceEpoch could). Persists before returning.
Future<int> nextAlarmId(PrefsService prefs) async {
  final next = incrementId(prefs.alarmIdCounter);
  await prefs.setAlarmIdCounter(next);
  return next;
}

/// Next occurrence for an alarm. Top-level so `date_calc_test.dart` /
/// `alarm_service_test.dart` can characterize FIX-01 behavior. Behavior is
/// preserved EXACTLY from the prior implementation.
DateTime calculateAlarmDateTime(TimeOfDay time, List<int> repeatDays) {
  DateTime now = DateTime.now();
  DateTime target =
      DateTime(now.year, now.month, now.day, time.hour, time.minute);

  if (repeatDays.isEmpty) {
    if (target.isBefore(now)) {
      return target.add(const Duration(days: 1));
    }
    return target;
  }

  while (true) {
    if (target.isBefore(now) || !repeatDays.contains(target.weekday)) {
      target = target.add(const Duration(days: 1));
    } else {
      return target;
    }
  }
}
