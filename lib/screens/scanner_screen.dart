import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../l10n/app_strings.dart';

class ScannerScreen extends StatefulWidget {
  final String language;
  const ScannerScreen({super.key, required this.language});
  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final MobileScannerController controller = MobileScannerController(
    torchEnabled: false,
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool isScanCompleted = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppStrings.get('scan_title', widget.language)), backgroundColor: Colors.black, actions: [
        ValueListenableBuilder(
          valueListenable: controller,
          builder: (context, state, child) => IconButton(
            icon: Icon(state.torchState == TorchState.on ? Icons.flash_on : Icons.flash_off, color: state.torchState == TorchState.on ? Colors.yellow : Colors.grey),
            onPressed: () => controller.toggleTorch(),
          ),
        ),
      ]),
      body: Stack(
        children: [
          MobileScanner(
            controller: controller,
            onDetect: (capture) {
              if (isScanCompleted) return;
              final List<Barcode> barcodes = capture.barcodes;
              if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
                HapticFeedback.mediumImpact();
                setState(() => isScanCompleted = true);
                Navigator.pop(context, barcodes.first.rawValue);
              }
            },
          ),
          Positioned(
            bottom: 50, left: 0, right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                child: Text(AppStrings.get('flash_hint', widget.language), style: const TextStyle(color: Colors.white)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
