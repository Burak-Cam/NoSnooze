import 'dart:async';
import 'dart:convert';
import 'package:alarm/alarm.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart'; 
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Alarm.init();

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  runApp(const NoSnoozeApp());
}

class NoSnoozeApp extends StatefulWidget {
  const NoSnoozeApp({super.key});

  @override
  State<NoSnoozeApp> createState() => _NoSnoozeAppState();
}

class _NoSnoozeAppState extends State<NoSnoozeApp> {
  Locale _locale = const Locale('en'); 

  void setLanguage(String langCode) {
    setState(() {
      _locale = Locale(langCode);
    });
  }

  @override
  void initState() {
    super.initState();
    _loadSavedLanguage();
  }

  Future<void> _loadSavedLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    String? savedLang = prefs.getString('app_lang');
    if (savedLang != null) {
      setState(() {
        _locale = Locale(savedLang);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'NoSnooze',
      locale: _locale, 
      supportedLocales: const [Locale('en'), Locale('tr')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
        primaryColor: Colors.red,
        colorScheme: const ColorScheme.dark(
          primary: Colors.red,
          secondary: Colors.redAccent,
          surface: Colors.black,
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: Colors.red,
          foregroundColor: Colors.white,
        ),
      ),
      home: HomeScreen(onLanguageChanged: setLanguage),
    );
  }
}

// ALARM SCHEDULING (v5.1.5 Compatible)
Future<void> scheduleAlarmFn(int id, DateTime dateTime, bool vibrate, String lang) async {
  final alarmSettings = AlarmSettings(
    id: id,
    dateTime: dateTime,
    assetAudioPath: 'assets/alarm.mp3',
    loopAudio: true,
    vibrate: vibrate,
    volumeSettings: VolumeSettings.fade(
      volume: 1.0,
      fadeDuration: const Duration(seconds: 3),
      volumeEnforced: true,
    ),
    notificationSettings: NotificationSettings(
      title: 'NoSnooze',
      body: AppStrings.get('notification_body', lang),
      stopButton: null,
      icon: 'notification_icon',
    ),
    warningNotificationOnKill: true, 
    androidFullScreenIntent: true,
  );
  await Alarm.set(alarmSettings: alarmSettings);
}

class HomeScreen extends StatefulWidget {
  final Function(String) onLanguageChanged;

  const HomeScreen({super.key, required this.onLanguageChanged});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<AlarmEntity> alarms = [];
  List<String> savedBarcodes = [];
  String get currentLang => Localizations.localeOf(context).languageCode;
  
  int streakCount = 0;
  int snoozeTokens = 0;
  bool cheatDetected = false; 
  StreamSubscription? alarmSubscription;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
    _checkPermissions();
    _startAlarmListener();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkBatteryOptimization();
      _checkCheatStatus(); 
    });
  }

  @override
  void dispose() {
    alarmSubscription?.cancel();
    super.dispose();
  }

  Future<void> _checkCheatStatus() async {
    final prefs = await SharedPreferences.getInstance();
    bool wasRinging = prefs.getBool('is_ringing') ?? false;

    if (wasRinging) {
      await prefs.setBool('is_ringing', false); 
      await prefs.setInt('user_streak', 0); 
      await prefs.setInt('snooze_tokens', 0);
      
      if (!mounted) return;

      setState(() {
        streakCount = 0;
        snoozeTokens = 0;
        cheatDetected = true;
      });

      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            backgroundColor: Colors.red[900],
            title: Text(
              AppStrings.get('cheat_title', currentLang), 
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)
            ),
            content: Text(AppStrings.get('cheat_msg', currentLang), style: const TextStyle(color: Colors.white)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("OK", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              )
            ],
          ),
        );
      }
    }
  }

  void _startAlarmListener() {
    // ignore: deprecated_member_use
    alarmSubscription = Alarm.ringStream.stream.listen((alarmSettings) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_ringing', true);

      final index = alarms.indexWhere((element) => element.id == alarmSettings.id);
      if (index != -1) {
        if (mounted) {
          setState(() {
            alarms[index].isActive = false;
          });
        }
        _saveAlarms();
      }

      if (!mounted) return;

      if (savedBarcodes.isNotEmpty) {
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => RingScreen(
              targetBarcodes: savedBarcodes,
              startWithoutVibration: !alarmSettings.vibrate,
              language: currentLang,
              alarmId: alarmSettings.id,
            ),
          ),
        );

        if (!mounted) return;

        if (result == 'RESTART') {
           await Alarm.stop(alarmSettings.id);
           await Future.delayed(const Duration(milliseconds: 500));
           await scheduleAlarmFn(alarmSettings.id, DateTime.now().add(const Duration(milliseconds: 100)), false, currentLang);
        } else if (result == 'SUCCESS') {
           _loadPreferences(); 
        }
      }
    });
  }

  Future<void> _checkBatteryOptimization() async {
    if (await Permission.ignoreBatteryOptimizations.isGranted) return;
    final prefs = await SharedPreferences.getInstance();
    bool hasSeenWarning = prefs.getBool('battery_dialog_seen') ?? false;
    if (hasSeenWarning) return;

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(AppStrings.get('battery_title', currentLang)),
        content: Text(AppStrings.get('battery_desc', currentLang)),
        actions: [
          TextButton(
            onPressed: () async {
              await prefs.setBool('battery_dialog_seen', true);
              if (context.mounted) Navigator.pop(context);
            },
            child: Text(AppStrings.get('btn_close', currentLang), style: const TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () async {
              await prefs.setBool('battery_dialog_seen', true);
              if (context.mounted) Navigator.pop(context);
              await openAppSettings();
            },
            child: const Text("OK", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _checkPermissions() async {
    if (await Permission.notification.isDenied) await Permission.notification.request();
    await Permission.camera.request();
    await Permission.scheduleExactAlarm.request();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      savedBarcodes = prefs.getStringList('target_barcodes') ?? [];
      streakCount = prefs.getInt('user_streak') ?? 0;
      snoozeTokens = prefs.getInt('snooze_tokens') ?? 0;
      
      final String? alarmsJson = prefs.getString('alarms_data');
      if (alarmsJson != null) {
        List<dynamic> decoded = jsonDecode(alarmsJson);
        alarms = decoded.map((e) => AlarmEntity.fromJson(e)).toList();
      }
    });
  }

  Future<void> _saveAlarms() async {
    final prefs = await SharedPreferences.getInstance();
    String encoded = jsonEncode(alarms.map((e) => e.toJson()).toList());
    await prefs.setString('alarms_data', encoded);
  }

  Future<void> _toggleLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    String newLang = (currentLang == 'tr') ? 'en' : 'tr';
    widget.onLanguageChanged(newLang);
    await prefs.setString('app_lang', newLang);
  }

  Future<void> _testAlarm() async {
    if (savedBarcodes.isEmpty) {
      _showSnack(AppStrings.get('add_item_first', currentLang));
      return;
    }
    final now = DateTime.now();
    await scheduleAlarmFn(
      now.millisecondsSinceEpoch % 10000, 
      now.add(const Duration(seconds: 5)), 
      true, 
      currentLang
    );
    _showSnack(AppStrings.get('test_start', currentLang));
  }

  void _showStatInfo(String type) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: Row(
          children: [
            Icon(
              type == 'streak' ? Icons.local_fire_department : Icons.timelapse,
              color: type == 'streak' ? Colors.orange : Colors.cyanAccent,
            ),
            const SizedBox(width: 10),
            Text(
              type == 'streak' ? AppStrings.get('streak_title', currentLang) : AppStrings.get('token_title', currentLang),
              style: const TextStyle(color: Colors.white, fontSize: 18),
            ),
          ],
        ),
        content: Text(
          type == 'streak' ? AppStrings.get('streak_desc', currentLang) : AppStrings.get('token_desc', currentLang),
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Got it!", style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );
  }

  Future<void> _addAlarm() async {
    if (savedBarcodes.isEmpty) {
      _showSnack(AppStrings.get('add_item_first', currentLang));
      return;
    }

    DateTime? selectedDateTime;
    
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext builder) {
        DateTime tempDateTime = DateTime.now().add(const Duration(minutes: 1));
        return SizedBox(
          height: 300,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
                    ),
                    TextButton(
                      onPressed: () {
                        selectedDateTime = tempDateTime;
                        Navigator.pop(context);
                      },
                      child: const Text("OK", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 18)),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: CupertinoTheme(
                  data: const CupertinoThemeData(
                    brightness: Brightness.dark,
                    textTheme: CupertinoTextThemeData(
                      dateTimePickerTextStyle: TextStyle(color: Colors.white, fontSize: 20),
                    ),
                  ),
                  child: CupertinoDatePicker(
                    mode: CupertinoDatePickerMode.dateAndTime,
                    use24hFormat: true,
                    minimumDate: DateTime.now(),
                    initialDateTime: DateTime.now().add(const Duration(minutes: 5)),
                    onDateTimeChanged: (DateTime newDateTime) {
                      tempDateTime = newDateTime;
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted || selectedDateTime == null) return;

    final dateTime = selectedDateTime!;
    
    final newAlarm = AlarmEntity(
      id: DateTime.now().millisecondsSinceEpoch % 100000, 
      time: TimeOfDay(hour: dateTime.hour, minute: dateTime.minute),
      isActive: true, 
    );

    await scheduleAlarmFn(newAlarm.id, dateTime, true, currentLang);

    setState(() {
      alarms.add(newAlarm);
      alarms.sort((a, b) => (a.time.hour * 60 + a.time.minute).compareTo(b.time.hour * 60 + b.time.minute));
    });
    _saveAlarms();
    
    if (mounted) _showRemainingTime(dateTime);
  }

  Future<void> _toggleAlarm(int index, bool value) async {
    setState(() {
      alarms[index].isActive = value;
    });

    if (value) {
       if (savedBarcodes.isEmpty) {
        _showSnack(AppStrings.get('add_item_first', currentLang));
        setState(() => alarms[index].isActive = false);
        return;
      }
      
      final now = DateTime.now();
      DateTime dateTime = DateTime(now.year, now.month, now.day, alarms[index].time.hour, alarms[index].time.minute);
      if (dateTime.isBefore(now)) {
        dateTime = dateTime.add(const Duration(days: 1));
      }
      
      await scheduleAlarmFn(alarms[index].id, dateTime, true, currentLang);
      
      if (mounted) _showRemainingTime(dateTime);
    } else {
      await Alarm.stop(alarms[index].id);
      if (mounted) _showSnack(AppStrings.get('alarm_cancelled', currentLang));
    }
    _saveAlarms();
  }

  Future<void> _deleteAlarm(int index) async {
    await Alarm.stop(alarms[index].id);
    setState(() {
      alarms.removeAt(index);
    });
    _saveAlarms();
  }

  void _showRemainingTime(DateTime target) {
    final now = DateTime.now();
    final difference = target.difference(now);
    final hours = difference.inHours;
    final minutes = difference.inMinutes % 60;
    
    String msg = currentLang == 'tr' 
      ? "Alarm $hours saat $minutes dakika sonra çalacak." 
      : "Alarm set for $hours hours and $minutes minutes.";

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
      )
    );
  }

  Future<void> _scanAndAddBarcode() async {
    if (savedBarcodes.length >= 3) {
      _showSnack(AppStrings.get('max_items', currentLang));
      return;
    }
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => ScannerScreen(language: currentLang))
    );

    if (!mounted) return;

    if (result != null) {
      if (savedBarcodes.contains(result)) {
        _showSnack(AppStrings.get('item_exists', currentLang));
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      setState(() => savedBarcodes.add(result));
      await prefs.setStringList('target_barcodes', savedBarcodes);
      
      if (mounted) _showSnack(AppStrings.get('item_added', currentLang));
    }
  }

  Future<void> _removeBarcode(int index) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => savedBarcodes.removeAt(index));
    await prefs.setStringList('target_barcodes', savedBarcodes);
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("NoSnooze", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2)),
        centerTitle: true,
        backgroundColor: Colors.black,
        leading: TextButton(
          onPressed: _toggleLanguage,
          child: Text(currentLang.toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
        actions: [
          IconButton(
            onPressed: _testAlarm, 
            icon: const Icon(Icons.play_circle_filled, color: Colors.greenAccent),
            tooltip: "Test Alarm (5s)",
          ),
          
          GestureDetector(
            onTap: () => _showStatInfo('streak'),
            child: Container(
              margin: const EdgeInsets.only(left: 10),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: streakCount > 0 ? Colors.orange : Colors.grey)
              ),
              child: Row(
                children: [
                  const Icon(Icons.local_fire_department, color: Colors.orange, size: 20),
                  const SizedBox(width: 4),
                  Text("$streakCount", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),

          GestureDetector(
            onTap: () => _showStatInfo('token'),
            child: Container(
              margin: const EdgeInsets.only(right: 15, left: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: snoozeTokens > 0 ? Colors.cyanAccent : Colors.grey)
              ),
              child: Row(
                children: [
                  const Icon(Icons.timelapse, color: Colors.cyanAccent, size: 20),
                  const SizedBox(width: 4),
                  Text("$snoozeTokens", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addAlarm,
        child: const Icon(Icons.add, size: 30),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("${AppStrings.get('saved_items', currentLang)} (${savedBarcodes.length}/3)", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white70)),
                    if (savedBarcodes.length < 3)
                      IconButton(onPressed: _scanAndAddBarcode, icon: const Icon(Icons.qr_code_scanner, color: Colors.white, size: 24))
                  ],
                ),
                if (savedBarcodes.isEmpty)
                   Padding(
                     padding: const EdgeInsets.all(8.0),
                     child: Text(AppStrings.get('list_empty', currentLang), style: const TextStyle(color: Colors.grey, fontSize: 12), textAlign: TextAlign.center),
                   )
                else
                  Wrap(
                    spacing: 8.0,
                    children: List.generate(savedBarcodes.length, (index) {
                      return Chip(
                        label: Text("${AppStrings.get('item', currentLang)} ${index + 1}"),
                        avatar: const Icon(Icons.qr_code, size: 14),
                        deleteIcon: const Icon(Icons.close, size: 14, color: Colors.redAccent),
                        onDeleted: () => _removeBarcode(index),
                        backgroundColor: Colors.grey[800],
                      );
                    }),
                  ),
              ],
            ),
          ),
          
          const Divider(color: Colors.grey),

          Expanded(
            child: alarms.isEmpty 
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.alarm_off, size: 80, color: Colors.grey[800]),
                      const SizedBox(height: 10),
                      const Text("No Alarms Set", style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: alarms.length,
                  itemBuilder: (context, index) {
                    final alarm = alarms[index];
                    return Dismissible(
                      key: Key(alarm.id.toString()),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        color: Colors.red,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      onDismissed: (direction) => _deleteAlarm(index),
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.grey[900],
                          borderRadius: BorderRadius.circular(15),
                          // v5 uses withValues
                          border: Border.all(color: alarm.isActive ? Colors.red.withValues(alpha: 0.5) : Colors.transparent)
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          title: Text(
                            "${alarm.time.hour.toString().padLeft(2, '0')}:${alarm.time.minute.toString().padLeft(2, '0')}",
                            style: TextStyle(
                              fontSize: 40, 
                              fontWeight: FontWeight.bold,
                              color: alarm.isActive ? Colors.white : Colors.grey
                            ),
                          ),
                          subtitle: Text(alarm.isActive ? "Active" : "Inactive", style: const TextStyle(color: Colors.grey)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.white54),
                                onPressed: () => _deleteAlarm(index),
                              ),
                              Switch(
                                value: alarm.isActive,
                                activeTrackColor: Colors.red, 
                                onChanged: (value) => _toggleAlarm(index, value),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
          ),
        ],
      ),
    );
  }
}

class RingScreen extends StatefulWidget {
  final List<String> targetBarcodes;
  final bool startWithoutVibration;
  final String language;
  final int alarmId; 

  const RingScreen({
    super.key, 
    required this.targetBarcodes, 
    this.startWithoutVibration = false, 
    required this.language,
    required this.alarmId,
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

    // POCO C40 & YÜKSEK PERFORMANS FIX
    // Gecikmeyi kaldırdık, sadece UI hazır olunca başlatıyoruz.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _initController();
        setState(() => isCameraReady = true);
      }
    });
  }

  void _initController() {
    // EN KALİTELİ MOD + GÜVENLİ BAŞLATMA
    controller = MobileScannerController(
      // noDuplicates = En iyi okuma kalitesi
      detectionSpeed: DetectionSpeed.noDuplicates, 
      returnImage: false,
      torchEnabled: false,
      autoStart: true, 
    );
  }

  void _requestRestart() {
    Navigator.pop(context, 'RESTART');
  }

  void _handleEmergencyStop() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_ringing', false); 

    setState(() => isLocked = true);
    Alarm.stop(widget.alarmId); 
    HapticFeedback.lightImpact();
    if (!mounted) return;
    Navigator.pop(context);
    
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("⚠️ ${AppStrings.get('alarm_cancelled', widget.language)}")),
    );
  }

  bool isLocked = false;
  Future<void> _onScanSuccess() async {
    if (isLocked) return;
    setState(() => isLocked = true);

    // Kritik: Alarmı önce durdur, CPU rahatlasın
    await Alarm.stop(widget.alarmId); 
    HapticFeedback.heavyImpact();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_ringing', false);

    String today = DateTime.now().toString().split(' ')[0];
    String? lastScan = prefs.getString('last_scan_date');
    int currentStreak = prefs.getInt('user_streak') ?? 0;
    int currentTokens = prefs.getInt('snooze_tokens') ?? 0;

    if (lastScan != today) {
        currentStreak++;
        await prefs.setInt('user_streak', currentStreak);
        await prefs.setString('last_scan_date', today);

        bool tokenEarned = false;
        if (currentStreak % 3 == 0 && currentTokens < 3) {
           currentTokens++;
           await prefs.setInt('snooze_tokens', currentTokens);
           tokenEarned = true;
        }

        if(mounted) {
          String msg = "🔥 $currentStreak ${AppStrings.get('streak_day', widget.language)}";
          if (tokenEarned) {
             msg += "\n🎁 +1 ${AppStrings.get('token_name', widget.language)}!";
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
      Navigator.pop(context, 'SUCCESS');
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
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 20),
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(20)),
                    child: Text(AppStrings.get('scan_instructions', widget.language), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
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

class AlarmEntity {
  final int id;         
  TimeOfDay time;       
  bool isActive;
  
  AlarmEntity({
    required this.id,
    required this.time,
    this.isActive = true,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'hour': time.hour,
    'minute': time.minute,
    'isActive': isActive,
  };

  factory AlarmEntity.fromJson(Map<String, dynamic> json) {
    return AlarmEntity(
      id: json['id'],
      time: TimeOfDay(hour: json['hour'], minute: json['minute']),
      isActive: json['isActive'],
    );
  }
}

class AppStrings {
  static const Map<String, Map<String, String>> _localizedValues = {
    'notification_body': {'tr': 'Susmak için barkodu okut!', 'en': 'Scan barcode to stop alarm!'},
    'saved_items': {'tr': 'Kayıtlı Ürünler', 'en': 'Saved Items'},
    'list_empty': {'tr': 'Barkod eklemek için tarama ikonuna bas.', 'en': 'Tap scanner icon to add barcodes.'},
    'item': {'tr': 'Ürün', 'en': 'Item'},
    'alarm_cancelled': {'tr': 'Alarm İptal Edildi 🔕', 'en': 'Alarm Cancelled 🔕'},
    'scan_instructions': {'tr': 'SUSMAK İÇİN\nTANIMLI ÜRÜNÜ\nOKUT!', 'en': 'SCAN ITEM\nTO STOP!'},
    'morning_msg': {'tr': 'GÜNAYDIN ŞAMPİYON! ☀️', 'en': 'GOOD MORNING CHAMPION! ☀️'},
    'camera_fix_btn': {'tr': 'KAMERA ODAKLAMIYOR MU?\nTİTREŞİMİ KES', 'en': 'CAMERA BLURRY?\nCUT VIBRATION'},
    'scan_title': {'tr': 'Ürün Tara', 'en': 'Scan Item'},
    'flash_hint': {'tr': 'Karanlıktaysa flaşı aç 👆', 'en': 'Turn on flash if dark 👆'},
    'item_exists': {'tr': 'Bu ürün zaten ekli!', 'en': 'Item already exists!'},
    'item_added': {'tr': 'Ürün Eklendi! ✅', 'en': 'Item Added! ✅'},
    'add_item_first': {'tr': 'Önce barkod ekle!', 'en': 'Add an item first!'},
    'test_start': {'tr': '5 saniye sonra çalacak...', 'en': 'Ringing in 5 seconds...'},
    'battery_title': {'tr': '⚠️ Önemli Uyarı', 'en': '⚠️ Important'},
    'battery_desc': {
      'tr': 'Alarmın garanti çalması ve uygulamanın kapanmaması için açılan ekranda şunları yapmalısınız:\n\n'
            '1. PİL/BATARYA: "Kısıtlama Yok" veya "Sınırsız" seçeneğini seçin.\n'
            '2. BAŞLATMA: Varsa "Otomatik Başlatma" veya "Arka Planda Çalışma" iznini açın.',
      'en': 'To ensure the alarm rings reliably, please adjust these settings in the next screen:\n\n'
            '1. BATTERY: Select "Unrestricted" or "No Restrictions".\n'
            '2. LAUNCH: Enable "Autostart" or "Run in Background" if available.'
    },
    'btn_close': {'tr': 'Kapat', 'en': 'Close'},
    'emergency_btn': {'tr': 'ACİL DURUM KAPAT', 'en': 'EMERGENCY STOP'},
    'cheat_title': {'tr': '🚨 HİLE TESPİT EDİLDİ! 🚨', 'en': '🚨 CHEAT DETECTED! 🚨'},
    'cheat_msg': {
      'tr': 'Dün alarm çalarken uygulamayı zorla kapatıp kaçtığını tespit ettik.\n\nBu davranış "NoSnooze" ruhuna aykırı!\n\nCEZA: Seri (Streak) sıfırlandı.',
      'en': 'We detected that you forced closed the app while the alarm was ringing.\n\nThis is against the "NoSnooze" spirit!\n\nPENALTY: Streak reset.'
    },
    'max_items': {'tr': 'En fazla 3 ürün eklenebilir.', 'en': 'Max 3 items allowed.'},
    'streak_title': {'tr': 'Ateş Serisi (Streak)', 'en': 'Fire Streak'},
    'streak_desc': {'tr': 'Her gün zamanında uyanarak seriyi koru. Ateşin sönmesin!', 'en': 'Wake up on time daily to keep the fire burning!'},
    'token_title': {'tr': 'Erteleme Jetonu', 'en': 'Snooze Token'},
    'token_desc': {'tr': 'Her 3 günlük seride 1 jeton kazanırsın. En fazla 3 jeton birikebilir.', 'en': 'Earn 1 token every 3-day streak. Max 3 tokens allowed.'},
    'streak_day': {'tr': '. Gün', 'en': '. Day'},
    'token_name': {'tr': 'Jeton', 'en': 'Token'},
  };
  
  static const Map<String, List<String>> _sleepFacts = {
    'tr': [
      "Biliyor muydun? Ortalama bir uyku döngüsü yaklaşık 90 dakikadır.",
      "Uyku sırasında beynin gün içinde öğrendiklerini pekiştirir.",
      "Yetişkinlerin %40'ı günde 7 saatten az uyuyor. Hedefin 7-9 saat olsun!",
      "Uyku eksikliği iştahını artırabilir. Kilo kontrolü için uykuna dikkat et.",
      "Uyanır uyanmaz yatağını toplamak, güne küçük bir başarı ile başlamanı sağlar.",
    ],
    'en': [
      "Did you know? An average sleep cycle is about 90 minutes.",
      "During sleep, your brain consolidates what you learned during the day.",
      "40% of adults sleep less than 7 hours a day. Aim for 7-9 hours!",
      "Lack of sleep increases hunger hormones. Watch your sleep for weight control.",
      "Making your bed right after waking up is a great way to start the day.",
    ],
  };

  static String get(String key, String lang) {
    return _localizedValues[key]?[lang] ?? key;
  }

  static String getRandomFact(String lang) {
    final facts = _sleepFacts[lang] ?? _sleepFacts['tr']!; 
    final randomIndex = DateTime.now().millisecondsSinceEpoch % facts.length; 
    return facts[randomIndex];
  }
}