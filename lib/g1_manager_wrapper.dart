import 'dart:async';
import 'dart:convert';
import 'package:demo_ai_even/app.dart';
import 'package:demo_ai_even/services/evenai.dart';
import 'package:demo_ai_even/services/text_service.dart';
import 'package:demo_ai_even/services/pin_text_service.dart';
import 'package:demo_ai_even/controllers/pin_text_controller.dart';
import 'package:demo_ai_even/services/notification_service.dart';
import 'package:even_realities_g1/even_realities_g1.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

/// Wrapper around the even_realities_g1 library's G1Manager.
/// Provides app-specific functionality and maintains backward compatibility
/// with existing services.
class G1ManagerWrapper {
  G1ManagerWrapper._();

  static G1ManagerWrapper? _instance;
  static G1ManagerWrapper get instance {
    _instance ??= G1ManagerWrapper._();
    return _instance!;
  }

  /// The underlying G1Manager from the library
  final G1Manager g1 = G1Manager();

  /// Method channel for app-specific native calls (notification service, etc.)
  static const _channel = MethodChannel('method.bluetooth');

  /// Callbacks
  Function()? onStatusChanged;
  Function(String lr)? onTouchpadTap;

  /// Connection state
  bool get isConnected => g1.isConnected;
  bool get isScanning => g1.isScanning;
  String connectionStatus = 'Not connected';

  /// For backward compatibility with pairedGlasses list
  final List<Map<String, String>> pairedGlasses = [];

  /// App background state tracking
  bool _isAppInBackground = false;
  bool isAppInBackground() => _isAppInBackground;

  /// Heartbeat timer for app-level keep-alive
  Timer? _heartbeatTimer;
  int _heartbeatFailureCount = 0;
  static const int _maxHeartbeatFailures = 3;
  static const int _maxHeartbeatFailuresInBackground = 10;

  /// F6 message buffers for chunked JSON commands
  final Map<String, StringBuffer> _f6MessageBuffers = {};

  /// Initialize the wrapper
  Future<void> initialize() async {
    await g1.initialize();

    // Set up connection state listener
    g1.connectionState.listen(_handleConnectionEvent);

    // Set up data received callback
    g1.onDataReceived = _handleDataReceived;

    // Configure Even AI callbacks
    g1.configureEvenAI(
      onLeftTap: () => _handleTouchpadTap('L'),
      onRightTap: () => _handleTouchpadTap('R'),
      onDoubleTap: () => _handleDoubleTap(),
      onExitToDashboard: () => _handleExitToDashboard(),
      onAISessionStart: () => _handleAISessionStart(),
      onAISessionEnd: (audioData) => _handleAISessionEnd(audioData),
    );

    // Set up method call handler for native callbacks
    _channel.setMethodCallHandler(_methodCallHandler);
  }

  /// Start scanning for glasses
  Future<void> startScan() async {
    pairedGlasses.clear();
    connectionStatus = 'Scanning...';
    onStatusChanged?.call();

    try {
      await g1.startScan(
        onUpdate: (message) {
          print('Scan update: $message');
        },
        onGlassesFound: (left, right) {
          print('Found glasses: Left=$left, Right=$right');
          // Add to paired glasses list for compatibility
          final channelMatch = RegExp(r'_(\d+)_[LR]_').firstMatch(left);
          if (channelMatch != null) {
            final channel = channelMatch.group(1) ?? '';
            if (!pairedGlasses.any((g) => g['channelNumber'] == channel)) {
              pairedGlasses.add({
                'channelNumber': channel,
                'leftName': left,
                'rightName': right,
              });
              onStatusChanged?.call();
            }
          }
        },
        onConnected: () {
          _onConnected();
        },
        timeout: const Duration(seconds: 30),
      );
    } catch (e) {
      connectionStatus = 'Scan error: $e';
      onStatusChanged?.call();
    }
  }

  /// Stop scanning
  Future<void> stopScan() async {
    await g1.stopScan();
  }

  /// Connect to glasses using channel number (for backward compatibility)
  Future<void> connectToGlasses(String channelNumber) async {
    connectionStatus = 'Connecting...';
    onStatusChanged?.call();

    // Find the glasses in the paired list
    final glasses = pairedGlasses.firstWhereOrNull(
      (g) => g['channelNumber'] == channelNumber,
    );

    if (glasses == null) {
      // Start a new scan to find and connect
      await startScan();
      return;
    }

    // The library handles connection during scan, so we just wait
    // If not connected, try scanning again
    if (!g1.isConnected) {
      await startScan();
    }
  }

  /// Disconnect from glasses
  Future<void> disconnect() async {
    _stopHeartbeat();
    await g1.disconnect();
    await _stopForegroundService();
    connectionStatus = 'Not connected';
    onStatusChanged?.call();
  }

  void _onConnected() {
    connectionStatus = 'Connected: ${g1.leftGlass?.name ?? "Left"}, ${g1.rightGlass?.name ?? "Right"}';
    onStatusChanged?.call();
    _startHeartbeat();
    _startForegroundService();
  }

  void _handleConnectionEvent(G1ConnectionEvent event) {
    switch (event.state) {
      case G1ConnectionState.scanning:
        connectionStatus = 'Scanning...';
        break;
      case G1ConnectionState.connecting:
        connectionStatus = 'Connecting...';
        break;
      case G1ConnectionState.connected:
        _onConnected();
        return; // Already handled
      case G1ConnectionState.disconnected:
        _stopHeartbeat();
        connectionStatus = 'Not connected';
        break;
      case G1ConnectionState.error:
        _stopHeartbeat();
        connectionStatus = event.errorMessage ?? 'Connection error';
        break;
    }
    onStatusChanged?.call();
  }

  /// Handle data received from glasses
  Future<void> _handleDataReceived(GlassSide side, List<int> data) async {
    if (data.isEmpty) return;

    final lr = side == GlassSide.left ? 'L' : 'R';
    final cmd = data[0];

    // Log non-voice data commands
    if (cmd != 0xF1) {
      print('${DateTime.now()} G1Manager receive cmd: 0x${cmd.toRadixString(16)}, len: ${data.length}');
    }

    // Handle F6 chunked commands
    if (cmd == 0xF6) {
      _handleF6Command(lr, data);
      return;
    }

    // Handle F5 event commands (touchpad, AI control, etc.)
    if (cmd == 0xF5 && data.length >= 2) {
      _handleF5Command(lr, data[1]);
      return;
    }

    // Handle note-related commands
    if (cmd == 0x21 || cmd == 0x22) {
      print('${DateTime.now()} PinText: Received command 0x${cmd.toRadixString(16)} (len=${data.length})');
      return;
    }
  }

  void _handleF5Command(String lr, int subCmd) {
    switch (subCmd) {
      case 0x00: // Exit to dashboard
        App.get.exitAll();
        try {
          final pinTextController = Get.find<PinTextController>();
          pinTextController.isDashboardMode.value = true;
        } catch (_) {}
        break;

      case 0x01: // Single tap
        _handleTouchpadTap(lr);
        break;

      case 23: // 0x17 - Start Even AI
        try {
          final pinTextController = Get.find<PinTextController>();
          pinTextController.isDashboardMode.value = false;
        } catch (_) {}
        EvenAI.get.toStartEvenAIByOS();
        break;

      case 24: // 0x18 - Even AI record over
        EvenAI.get.recordOverByOS();
        break;

      case 10: // 0x0A - Dashboard event
        try {
          final pinTextController = Get.find<PinTextController>();
          pinTextController.isDashboardMode.value = true;
        } catch (_) {}
        break;

      case 30: // 0x1E - Start Pin Text recording
        if (!EvenAI.isRunning) {
          _channel.invokeMethod("startEvenAI").catchError((e) {
            print('Error starting Pin Text recognition: $e');
          });
        }
        break;

      case 31: // 0x1F - End Pin Text recording
        if (!EvenAI.isRunning) {
          _channel.invokeMethod("stopEvenAI").then((_) {
            Future.delayed(const Duration(milliseconds: 1000), () {
              _channel.invokeMethod("startEvenAI").catchError((_) {});
            });
          }).catchError((_) {});
        }
        break;

      default:
        print('Unknown F5 subcommand: 0x${subCmd.toRadixString(16)}');
    }
  }

  void _handleF6Command(String lr, List<int> data) {
    if (data.length < 3) return;

    final subCmd = data[1];
    final chunkIndex = data[2];
    final chunkData = data.length > 3 ? data.sublist(3) : <int>[];
    final bufferKey = '$lr-$subCmd';
    final buffer = _f6MessageBuffers.putIfAbsent(bufferKey, () => StringBuffer());

    if (chunkIndex == 0) {
      buffer.clear();
    }

    if (chunkData.isNotEmpty) {
      try {
        buffer.write(utf8.decode(chunkData, allowMalformed: true));
      } catch (e) {
        print('Error decoding F6 chunk: $e');
        return;
      }
    }

    final payload = buffer.toString();
    try {
      final decoded = jsonDecode(payload);
      _processDeviceJsonCommand(subCmd, decoded);
      _f6MessageBuffers.remove(bufferKey);
    } catch (_) {
      // JSON not complete yet; wait for more chunks
    }
  }

  void _processDeviceJsonCommand(int subCmd, dynamic payload) {
    if (subCmd == 0x06 && payload is Map) {
      final data = payload['whitelist_add'];
      if (data is Map) {
        final appIdentifier = data['app_identifier'] as String?;
        final displayName = (data['display_name'] as String?)?.trim();
        if (appIdentifier != null && appIdentifier.isNotEmpty) {
          unawaited(
            NotificationService.instance.handleDeviceWhitelistAdd(
              appIdentifier,
              displayName?.isNotEmpty == true ? displayName! : appIdentifier,
            ),
          );
        }
      }
    }
  }

  void _handleTouchpadTap(String lr) {
    if (onTouchpadTap != null) {
      onTouchpadTap!(lr);
      return;
    }

    try {
      final pinTextController = Get.find<PinTextController>();

      if (pinTextController.isDashboardMode.value &&
          !EvenAI.isRunning &&
          !TextService.isRunning) {
        // Dashboard mode - navigate Pin Text
        if (lr == 'R') {
          pinTextController.nextNote();
          final currentNote = pinTextController.getCurrentNote();
          if (currentNote != null) {
            PinTextService.instance.sendPinText(currentNote.content);
          }
        } else {
          pinTextController.previousNote();
          final currentNote = pinTextController.getCurrentNote();
          if (currentNote != null) {
            PinTextService.instance.sendPinText(currentNote.content);
          }
        }
      } else {
        // Feature mode - page navigation
        if (lr == 'L') {
          EvenAI.get.lastPageByTouchpad();
        } else {
          EvenAI.get.nextPageByTouchpad();
        }
      }
    } catch (_) {
      // Default behavior
      if (lr == 'L') {
        EvenAI.get.lastPageByTouchpad();
      } else {
        EvenAI.get.nextPageByTouchpad();
      }
    }
  }

  void _handleDoubleTap() {
    App.get.exitAll();
    try {
      final pinTextController = Get.find<PinTextController>();
      pinTextController.isDashboardMode.value = true;
    } catch (_) {}
  }

  void _handleExitToDashboard() {
    _handleDoubleTap();
  }

  void _handleAISessionStart() {
    try {
      final pinTextController = Get.find<PinTextController>();
      pinTextController.isDashboardMode.value = false;
    } catch (_) {}
    EvenAI.get.toStartEvenAIByOS();
  }

  void _handleAISessionEnd(List<int> audioData) {
    EvenAI.get.recordOverByOS();
    // Audio data can be processed by EvenAI service
  }

  /// Set app background state
  void setAppInBackground(bool inBackground) {
    _isAppInBackground = inBackground;
    if (inBackground) {
      print('${DateTime.now()} App moved to background');
    } else {
      print('${DateTime.now()} App moved to foreground');
      _heartbeatFailureCount = 0;
      if (isConnected && _heartbeatTimer == null) {
        _startHeartbeat();
      }
    }
  }

  void _startHeartbeat() {
    _stopHeartbeat();
    _heartbeatFailureCount = 0;

    _heartbeatTimer = Timer.periodic(const Duration(seconds: 25), (timer) async {
      if (!isConnected) {
        _stopHeartbeat();
        return;
      }

      try {
        await g1.settings.heartbeat();
        _heartbeatFailureCount = 0;
      } catch (e) {
        _heartbeatFailureCount++;
        final maxFailures = _isAppInBackground
            ? _maxHeartbeatFailuresInBackground
            : _maxHeartbeatFailures;

        if (_heartbeatFailureCount >= maxFailures) {
          print('Too many heartbeat failures, marking as disconnected');
          connectionStatus = 'Connection lost (heartbeat failed)';
          onStatusChanged?.call();
        }
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _heartbeatFailureCount = 0;
  }

  /// Start foreground service for background BLE connection
  Future<void> _startForegroundService() async {
    try {
      await _channel.invokeMethod('startForegroundService');
      print('Started foreground service');
    } catch (e) {
      print('Error starting foreground service: $e');
    }
  }

  /// Stop foreground service
  Future<void> _stopForegroundService() async {
    try {
      await _channel.invokeMethod('stopForegroundService');
      print('Stopped foreground service');
    } catch (e) {
      print('Error stopping foreground service: $e');
    }
  }

  /// Method call handler for native callbacks
  Future<void> _methodCallHandler(MethodCall call) async {
    switch (call.method) {
      case 'glassesConnected':
        // Handled by library's connection stream
        break;
      case 'glassesDisconnected':
        // Handled by library's connection stream
        break;
      case 'foundPairedGlasses':
        final deviceInfo = Map<String, String>.from(call.arguments);
        final channelNumber = deviceInfo['channelNumber']!;
        if (!pairedGlasses.any((g) => g['channelNumber'] == channelNumber)) {
          pairedGlasses.add(deviceInfo);
          onStatusChanged?.call();
        }
        break;
    }
  }

  /// Get connection status string
  String getConnectionStatus() => connectionStatus;

  /// Get paired glasses list
  List<Map<String, String>> getPairedGlasses() => pairedGlasses;

  /// Reset connection state
  void resetConnectionState() {
    _stopHeartbeat();
    connectionStatus = 'Not connected';
  }

  // ============= Backward Compatibility Static Methods =============
  // These are provided for gradual migration from BleManager

  static bool isBothConnected() {
    return instance.isConnected;
  }

  static Future<T?> invokeMethod<T>(String method, [dynamic params]) {
    return _channel.invokeMethod(method, params);
  }

  /// Send data to glasses (backward compatible)
  static Future<void> sendData(Uint8List data, {String? lr}) async {
    final wrapper = instance;
    if (!wrapper.isConnected) return;

    if (lr == 'L' || lr == null) {
      await wrapper.g1.leftGlass?.sendData(data);
    }
    if (lr == 'R' || lr == null) {
      await wrapper.g1.rightGlass?.sendData(data);
    }
  }

  /// Send command to both glasses with ACK
  static Future<bool> sendBoth(
    Uint8List data, {
    int timeoutMs = 250,
    int? retry,
  }) async {
    final wrapper = instance;
    if (!wrapper.isConnected) return false;

    try {
      await wrapper.g1.sendCommand(data.toList());
      return true;
    } catch (e) {
      print('sendBoth error: $e');
      return false;
    }
  }
}

