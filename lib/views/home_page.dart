// ignore_for_file: library_private_types_in_public_api

import 'dart:async';

import 'package:demo_ai_even/ble_manager.dart';
import 'package:demo_ai_even/services/evenai.dart';
import 'package:demo_ai_even/services/notification_service.dart';
import 'package:demo_ai_even/services/proto.dart';
import 'package:demo_ai_even/controllers/pin_text_controller.dart';
import 'package:demo_ai_even/views/even_list_page.dart';
import 'package:demo_ai_even/views/features_page.dart';
import 'package:demo_ai_even/views/notification_whitelist_page.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Timer? scanTimer;
  bool isScanning = false;
  bool _notificationAccessEnabled = false;

  @override
  void initState() {
    super.initState();
    BleManager.get().setMethodCallHandler();
    BleManager.get().startListening();
    
    // Sync with native service state on init
    _syncWithNativeService();
    
    BleManager.get().onStatusChanged = () {
      _refreshPage();
      _checkNotificationPermission();
      // Start notification service when glasses connect
      if (BleManager.get().isConnected) {
        NotificationService.instance.startListening();
        // Enable dashboard mode when connected
        try {
          final pinTextController = Get.find<PinTextController>();
          pinTextController.isDashboardMode.value = true;
          // Pinned note is just a UI marker - do NOT auto-send
        } catch (e) {
          print('PinTextController not found: $e');
        }
        
        // Apply saved display type settings
        _applySavedDisplaySettings();
      }
    };
    _checkNotificationPermission();
  }
  
  /// Sync Dart state with native service state
  Future<void> _syncWithNativeService() async {
    try {
      // This will be called by BleManager internally, but we can also trigger it here
      // The sync happens automatically when app comes to foreground
    } catch (e) {
      print('Error in sync: $e');
    }
  }

  void _refreshPage() => setState(() {});

  Future<void> _checkNotificationPermission() async {
    final hasPermission = await NotificationService.instance.checkNotificationPermission();
    if (mounted) {
      setState(() {
        _notificationAccessEnabled = hasPermission;
      });
    }
  }

  /// Apply saved display type settings when glasses connect
  Future<void> _applySavedDisplaySettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final displayType = prefs.getInt('display_type');
      
      // Only apply if a display type is saved (not null)
      if (displayType != null && displayType >= 0 && displayType <= 2) {
        // Wait a short delay to ensure connection is fully established
        await Future.delayed(const Duration(milliseconds: 500));
        
        print('Applying saved display type: $displayType');
        final success = await Proto.setDashboardMode(modeId: displayType);
        if (success) {
          final modeNames = ['Full', 'Dual', 'Minimal'];
          print('Successfully applied display type: ${modeNames[displayType]}');
        } else {
          print('Failed to apply saved display type: $displayType');
        }
      }
    } catch (e) {
      print('Error applying saved display settings: $e');
    }
  }

  Future<void> _requestNotificationPermission() async {
    // First request POST_NOTIFICATIONS permission (Android 13+)
    await NotificationService.instance.requestNotificationPermission();
    
    // Then open notification listener settings (for reading notifications from other apps)
    await NotificationService.instance.openNotificationSettings();
    
    // Check again after a delay to see if user enabled it
    Future.delayed(const Duration(seconds: 2), () {
      _checkNotificationPermission();
    });
  }

  Future<void> _startScan() async {
    setState(() => isScanning = true);
    try {
      await BleManager.get().startScan();
      scanTimer?.cancel();
      scanTimer = Timer(15.seconds, () {
        _stopScan();
      });
    } catch (e) {
      setState(() => isScanning = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error starting scan: $e')),
        );
      }
    }
  }

  Future<void> _stopScan() async {
    if (isScanning) {
      await BleManager.get().stopScan();
      setState(() => isScanning = false);
    }
  }

  Widget blePairedList() => Expanded(
        child: ListView.separated(
          separatorBuilder: (context, index) => const SizedBox(height: 5),
          itemCount: BleManager.get().getPairedGlasses().length,
          itemBuilder: (context, index) {
            final glasses = BleManager.get().getPairedGlasses()[index];
            return GestureDetector(
              onTap: () async {
                String channelNumber = glasses['channelNumber']!;
                await BleManager.get().connectToGlasses("Pair_$channelNumber");
                _refreshPage();
              },
              child: Container(
                height: 72,
                padding: const EdgeInsets.only(left: 16, right: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Pair: ${glasses['channelNumber']}'),
                        Text(
                            'Left: ${glasses['leftDeviceName']} \nRight: ${glasses['rightDeviceName']}'),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Even AI Demo'),
          actions: [
            InkWell(
              onTap: () {
                print("To Features Page...");
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const FeaturesPage()),
                );
              },
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
              child: const Padding(
                padding:
                    EdgeInsets.only(left: 16, top: 12, bottom: 14, right: 16),
                child: Icon(Icons.menu),
              ),
            ),
          ],
        ),
        body: Padding(
          padding:
              const EdgeInsets.only(left: 16, right: 16, top: 12, bottom: 44),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
                  InkWell(
                    onTap: () async {
                      final status = BleManager.get().getConnectionStatus();
                      final isConnecting = status.contains('Connecting');
                      final hasFailed = status.contains('failed') || status.contains('timeout');
                      
                      if (hasFailed || (isConnecting && !isScanning)) {
                        // Reset connection state to allow retry
                        BleManager.get().resetConnectionState();
                        _refreshPage();
                        // Start scan again
                        if (!isScanning) {
                          _startScan();
                        }
                      } else if (status == 'Not connected' && !isScanning) {
                        _startScan();
                      } else if (isScanning) {
                        _stopScan();
                      }
                    },
                borderRadius: BorderRadius.circular(5),
                child: Container(
                  height: 100,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  alignment: Alignment.center,
                  child: () {
                    final status = BleManager.get().getConnectionStatus();
                    final isConnecting = status.contains('Connecting');
                    final hasFailed = status.contains('failed') || status.contains('timeout');
                    
                    if (isScanning) {
                      return const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Scanning for glasses...',
                            style: TextStyle(fontSize: 16),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Tap to stop',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      );
                    } else if (isConnecting) {
                      return const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Connecting...',
                            style: TextStyle(fontSize: 16),
                          ),
                        ],
                      );
                    } else if (hasFailed) {
                      return Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            status,
                            style: TextStyle(fontSize: 14, color: Colors.red.shade700),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Tap to retry',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      );
                    } else {
                      return Text(
                        status,
                        style: const TextStyle(fontSize: 16),
                        textAlign: TextAlign.center,
                      );
                    }
                  }(),
                ),
              ),
              const SizedBox(height: 16),
              // Notification permission status
              InkWell(
                onTap: _requestNotificationPermission,
                borderRadius: BorderRadius.circular(5),
                child: Container(
                  height: 50,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: _notificationAccessEnabled ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: [
                      Icon(
                        _notificationAccessEnabled ? Icons.notifications_active : Icons.notifications_off,
                        color: _notificationAccessEnabled ? Colors.green : Colors.orange,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _notificationAccessEnabled 
                              ? 'Notifications: Enabled' 
                              : 'Tap to enable notification forwarding',
                          style: TextStyle(
                            fontSize: 14,
                            color: _notificationAccessEnabled ? Colors.green.shade700 : Colors.orange.shade700,
                          ),
                        ),
                      ),
                      if (!_notificationAccessEnabled)
                        const Icon(Icons.arrow_forward_ios, size: 16),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Notification whitelist management
              InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const NotificationWhitelistPage(),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(5),
                child: Container(
                  height: 50,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: [
                      const Icon(
                        Icons.filter_list,
                        color: Colors.blue,
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Manage notification whitelist',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.blue,
                          ),
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios, size: 16),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (BleManager.get().getConnectionStatus() == 'Not connected')
                blePairedList(),
              if (BleManager.get().isConnected)
                Expanded(
                  child: GestureDetector(
                    onTap: () async {
                      // todo
                      print("To AI History List...");
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const EvenAIListPage(),
                        ),
                      );
                    },
                    child: Container(
                      color: Colors.white,
                      padding: const EdgeInsets.all(16),
                      alignment: Alignment.topCenter,
                      child: SingleChildScrollView(
                        child: StreamBuilder<String>(
                          stream: EvenAI.textStream,
                          initialData:
                              "Press and hold left TouchBar to engage Even AI.",
                          builder: (context, snapshot) => Obx(
                            () => EvenAI.isEvenAISyncing.value
                                ? const SizedBox(
                                    width: 50,
                                    height: 50,
                                    child: CircularProgressIndicator(),
                                  ) // Color(0xFFFEF991)
                                : Text(
                                    snapshot.data ?? "Loading...",
                                    style: TextStyle(
                                        fontSize: 14,
                                        color: BleManager.get().isConnected
                                            ? Colors.black
                                            : Colors.grey.withOpacity(0.5)),
                                    textAlign: TextAlign.center,
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );

  @override
  void dispose() {
    scanTimer?.cancel();
    isScanning = false;
    BleManager.get().onStatusChanged = null;
    super.dispose();
  }
}
