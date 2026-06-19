package com.burakcam.uyan

import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    // FIX (lockscreen-mission-hidden): the alarm package's AlarmPlugin observer
    // calls activity.setShowWhenLocked(false) + setTurnScreenOn(false) the moment
    // Alarm.stop() flips AlarmRingingLiveData to false (AlarmService.stopAlarm).
    // That runtime call OVERRIDES the static manifest showWhenLocked=true, so the
    // Stage-2 mission surface drops behind the keyguard during the Stage-1 ->
    // Stage-2 handoff. We re-assert the lock-screen window flags here, invoked
    // from Dart right after Alarm.stop() inside _handoffToMission.
    //
    // CYCLE 2 (device-verified): requestDismissKeyguard was REMOVED. On a secure
    // lock it raised an unwanted PIN/auth prompt after the barcode (it asks to
    // UNLOCK, it does not show-over). Stage 1 was always shown OVER the keyguard
    // (setShowWhenLocked only, never dismissing it), so Stage 2 must do the same:
    // setShowWhenLocked(true) + setTurnScreenOn(true) ONLY, no keyguard dismiss.
    private val channelName = "com.burakcam.uyan/keyguard"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "showOverLockscreen" -> {
                        showOverLockscreen()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun showOverLockscreen() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O_MR1) return
        runOnUiThread {
            // Show OVER the keyguard, exactly like Stage 1 did — do NOT dismiss it
            // (requestDismissKeyguard triggers a PIN prompt on secure locks).
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        }
    }
}
