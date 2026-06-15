import 'dart:async';
import 'package:alarm/alarm.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_strings.dart';
import '../models/alarm_entity.dart';
import '../models/enums.dart';
import '../services/prefs_service.dart';
import '../services/streak_service.dart';

class RingScreen extends StatefulWidget {
  final List<String> targetBarcodes;
  final bool startWithoutVibration;
  final String language;
  final int alarmId;
  final int availableTokens;
  final String label;
  final AlarmKind alarmKind; // FIX-04: type carried from payload to gate streak.

  const RingScreen({
    super.key,
    required this.targetBarcodes,
    this.startWithoutVibration = false,
    required this.language,
    required this.alarmId,
    required this.availableTokens,
    required this.label,
    required this.alarmKind,
  });

  @override
  State<RingScreen> createState() => _RingScreenState();
}

class _RingScreenState extends State<RingScreen> {
  MobileScannerController? controller;
  bool isVibrationStopped = false;
  bool isCameraReady = false;
  late String randomFact;
  bool _showEmergencyButton = false;
  Timer? _emergencyTimer;

  @override
  void initState() {
    super.initState();
    isVibrationStopped = widget.startWithoutVibration;
    randomFact = AppStrings.getRandomFact(widget.language);

    _emergencyTimer = Timer(const Duration(seconds: 60), () {
      if (mounted) setState(() => _showEmergencyButton = true);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _initController();
        setState(() => isCameraReady = true);
      }
    });
  }

  void _initController() {
    // Detection-reliability config tuned for dense real-product EAN-13 codes on
    // low-end / MIUI devices, where ML Kit can take many seconds to land its
    // first decode (Redmi Note 9S field report):
    // - DetectionSpeed.normal + a short detectionTimeoutMs (100ms) lets ML Kit
    //   retry decoding ~10x/sec instead of suppressing repeated attempts as
    //   DetectionSpeed.noDuplicates does. The isLocked guard in _onScanSuccess
    //   makes any repeated emission of the same barcode harmless.
    // - cameraResolution 1920x1080 (vs the 640x480 Android default) gives ML Kit
    //   far more pixels-per-bar, which dense 1D barcodes need to decode quickly.
    // NOTE: formats are intentionally left at the default (all formats). The
    // add-barcode flow (ScannerScreen) stores ANY scanned format verbatim, so
    // restricting formats here could permanently trap a user who saved a non
    // EAN-13 code — a core-value ("must be able to dismiss") violation.
    controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      detectionTimeoutMs: 100,
      cameraResolution: const Size(1920, 1080),
      returnImage: false,
      torchEnabled: false,
      autoStart: true,
    );
  }

  void _requestRestart() {
    Navigator.pop(context, RingResult.restart);
  }

  void _useSnoozeToken() {
    if (widget.availableTokens > 0) {
      Navigator.pop(context, RingResult.snooze);
    }
  }

  void _handleEmergencyStop() async {
    final prefs = PrefsService(await SharedPreferences.getInstance());
    await prefs.setRinging(false);

    setState(() => isLocked = true);
    await Alarm.stop(widget.alarmId);
    HapticFeedback.lightImpact();
    if (!mounted) return;
    // FIX-01: return RingResult.emergency (was an arg-less pop) so the dismiss
    // chain in _startAlarmListener can re-arm a repeating alarm to its next
    // occurrence. The user-facing cancelled-snackbar is shown there/here.
    Navigator.pop(context, RingResult.emergency);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("⚠️ ${AppStrings.get('alarm_cancelled', widget.language)}")),
    );
  }

  bool isLocked = false;
  Future<void> _onScanSuccess() async {
    if (isLocked) return;
    setState(() => isLocked = true);

    await Alarm.stop(widget.alarmId); 
    HapticFeedback.heavyImpact();

    final prefs = PrefsService(await SharedPreferences.getInstance());
    await prefs.setRinging(false);

    String today = DateTime.now().toString().split(' ')[0];
    String? lastScan = prefs.lastScanDate;
    int currentStreak = prefs.userStreak;
    int currentTokens = prefs.snoozeTokens;

    // FIX-04 / D-02,D-03,D-04: a day counts only for a REAL wake alarm not yet
    // counted today. Test and snooze re-arms never earn streak; a second scan
    // the same day is neutral (streakEligible folds in the lastScan != today
    // guard). Snooze stays streak-neutral here AND on its re-arm path.
    if (streakEligible(widget.alarmKind, lastScan, today)) {
        currentStreak++;
        await prefs.setUserStreak(currentStreak);
        await prefs.setLastScanDate(today);

        bool tokenEarned = false;
        if (currentStreak % 3 == 0 && currentTokens < 3) {
           currentTokens++;
           await prefs.setSnoozeTokens(currentTokens);
           tokenEarned = true;
        }

        if(mounted) {
          String msg = "🔥 $currentStreak ${AppStrings.get('streak_day', widget.language)}";
          if (tokenEarned) {
             msg += "\n🎁 +1 ${AppStrings.get('token_name', widget.language)}!";
          }
          if (currentStreak % 7 == 0) {
             msg += "\n\n🎉 ${AppStrings.get('weekly_msg', widget.language)} 🎉";
          }

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                "$msg\n\n${AppStrings.get('morning_msg', widget.language)} \n$randomFact",
                textAlign: TextAlign.center,
              ),
              duration: const Duration(seconds: 8),
              backgroundColor: tokenEarned ? Colors.blueAccent : Colors.green,
            ),
          );
        }
    } else {
       if(mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                "${AppStrings.get('morning_msg', widget.language)}\n\n$randomFact",
                textAlign: TextAlign.center
              ), 
              backgroundColor: Colors.green
            ),
          );
       }
    }

    await Future.delayed(const Duration(seconds: 2));

    if(mounted) {
      Navigator.pop(context, RingResult.success);
    }
  }

  @override
  void dispose() {
    _emergencyTimer?.cancel();
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.red,
        body: Stack(
          children: [
            if (isCameraReady && controller != null)
              MobileScanner(
                controller: controller!,
                // If the camera pipeline fails, show a clear message and a torch
                // hint instead of a silent black screen — the user still has the
                // 60s emergency-stop fallback, but should know scanning is down.
                errorBuilder: (context, error, child) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        AppStrings.get('scan_instructions', widget.language),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 20),
                      ),
                    ),
                  );
                },
                onDetect: (capture) {
                  final List<Barcode> barcodes = capture.barcodes;
                  for (final barcode in barcodes) {
                    if (barcode.rawValue != null && widget.targetBarcodes.contains(barcode.rawValue)) {
                      _onScanSuccess();
                      break;
                    }
                  }
                },
              )
            else
              const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 20),
                    Text("Starting Camera...", style: TextStyle(color: Colors.white))
                  ],
                ),
              ),

            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (widget.label.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: Text(
                        widget.label.toUpperCase(),
                        style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.bold, letterSpacing: 2)
                      ),
                    ),

                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 20),
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(20)),
                    child: Text(AppStrings.get('scan_instructions', widget.language), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                  ),
                  
                  if (widget.availableTokens > 0 && !isLocked)
                    Padding(
                      padding: const EdgeInsets.only(top: 20),
                      child: ElevatedButton.icon(
                        onPressed: _useSnoozeToken,
                        icon: const Icon(Icons.timelapse),
                        label: Text("${AppStrings.get('snooze_btn', widget.language)} (-1 ${AppStrings.get('token_name', widget.language)})"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.cyanAccent, 
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15)
                        ),
                      ),
                    ),

                  const SizedBox(height: 300),
                ],
              ),
            ),

            if (!isVibrationStopped)
              Positioned(
                bottom: 120, left: 0, right: 0,
                child: Center(
                  child: ElevatedButton.icon(
                    onPressed: _requestRestart,
                    icon: const Icon(Icons.vibration, color: Colors.white),
                    label: Text(AppStrings.get('camera_fix_btn', widget.language), textAlign: TextAlign.center),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15)),
                  ),
                ),
              ),

            if (isCameraReady && controller != null)
              Positioned(
                top: 50, right: 20,
                child: ValueListenableBuilder(
                  valueListenable: controller!,
                  builder: (context, state, child) {
                    final isFlashOn = state.torchState == TorchState.on;
                    return IconButton(
                      iconSize: 40,
                      icon: Icon(isFlashOn ? Icons.flash_on : Icons.flash_off, color: isFlashOn ? Colors.yellow : Colors.white),
                      onPressed: () => controller?.toggleTorch(),
                    );
                  },
                ),
              ),

            if (_showEmergencyButton)
              Positioned(
                top: 50, left: 20,
                child: GestureDetector(
                  onTap: _handleEmergencyStop,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: Colors.redAccent, width: 2)
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 20),
                        const SizedBox(width: 5),
                        Text(
                          AppStrings.get('emergency_btn', widget.language),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
