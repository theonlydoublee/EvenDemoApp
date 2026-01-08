import 'dart:async';
import 'dart:convert';
import 'package:demo_ai_even/app.dart';
import 'package:demo_ai_even/services/ble.dart';
import 'package:demo_ai_even/services/evenai.dart';
import 'package:demo_ai_even/services/proto.dart';
import 'package:demo_ai_even/services/text_service.dart';
import 'package:demo_ai_even/services/pin_text_service.dart';
import 'package:demo_ai_even/controllers/pin_text_controller.dart';
import 'package:demo_ai_even/services/notification_service.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

typedef SendResultParse = bool Function(Uint8List value);

class BleManager {
  Function()? onStatusChanged;
  Function(String lr)? onTouchpadTap; // Callback for touchpad taps (L or R)
  BleManager._() {}

  static BleManager? _instance;
  static BleManager get() {
    if (_instance == null) {
      _instance ??= BleManager._();
      _instance!._init();
    }
    return _instance!;
  }

  static const methodSend = "send";
  static const _eventBleReceive = "eventBleReceive";
  static const _channel = MethodChannel('method.bluetooth');
  
  final eventBleReceive = const EventChannel(_eventBleReceive)
      .receiveBroadcastStream(_eventBleReceive)
      .map((ret) => BleReceive.fromMap(ret));

  Timer? beatHeartTimer;
  int _heartbeatFailureCount = 0;
  static const int _maxHeartbeatFailures = 3; // Max consecutive failures before considering connection lost
  static const int _maxHeartbeatFailuresInBackground = 10; // More lenient when in background
  
  final List<Map<String, String>> pairedGlasses = [];
  bool isConnected = false;
  String connectionStatus = 'Not connected';
  bool _isAppInBackground = false; // Track if app is in background
  final Map<String, StringBuffer> _f6MessageBuffers = {};

  void _init() {}

  /// Check if app is currently in background
  bool isAppInBackground() {
    return _isAppInBackground;
  }

  /// Set app background state (called from lifecycle observer)
  void setAppInBackground(bool inBackground) {
    _isAppInBackground = inBackground;
    if (inBackground) {
      print('${DateTime.now()} App moved to background - heartbeat will be more lenient');
      // Check actual connection status when going to background
      _checkActualConnectionStatus();
    } else {
      print('${DateTime.now()} App moved to foreground - resuming normal heartbeat');
      // Reset failure count when coming back to foreground
      _heartbeatFailureCount = 0;
      // Sync state with native service when coming to foreground
      _syncWithNativeService();
      // If we're connected, ensure heartbeat is running
      if (isConnected && beatHeartTimer == null) {
        startSendBeatHeart();
      }
      // Check actual connection status when coming to foreground
      _checkActualConnectionStatus();
    }
  }
  
  /// Sync Dart state with native service state
  Future<void> _syncWithNativeService() async {
    try {
      // Check if native service says we're connected
      final nativeConnected = await _channel.invokeMethod<bool>('checkBleConnectionStatus') ?? false;
      
      if (nativeConnected && !isConnected) {
        // Native says connected but Dart thinks disconnected - restore state
        print('${DateTime.now()} Syncing: Native service reports connected, updating Dart state');
        connectionStatus = 'Connected (restored)';
        isConnected = true;
        startSendBeatHeart();
        onStatusChanged?.call();
      } else if (!nativeConnected && isConnected) {
        // Native says disconnected but Dart thinks connected - update state
        print('${DateTime.now()} Syncing: Native service reports disconnected, updating Dart state');
        _onGlassesDisconnected();
      }
      
      // Check battery optimization status
      final batteryOptimized = await _channel.invokeMethod<bool>('checkBatteryOptimization') ?? false;
      if (!batteryOptimized) {
        print('${DateTime.now()} Warning: Battery optimization is not disabled - service may be killed');
      }
    } catch (e) {
      print('Error syncing with native service: $e');
    }
  }

  /// Check actual BLE connection status from native side
  Future<void> _checkActualConnectionStatus() async {
    try {
      final isActuallyConnected = await _channel.invokeMethod<bool>('checkBleConnectionStatus') ?? false;
      if (isActuallyConnected && !isConnected) {
        // Native says connected but Dart thinks disconnected - restore connection
        print('${DateTime.now()} Detected actual BLE connection - restoring Dart state');
        connectionStatus = 'Connected';
        isConnected = true;
        startSendBeatHeart();
        onStatusChanged?.call();
      } else if (!isActuallyConnected && isConnected) {
        // Native says disconnected but Dart thinks connected - disconnect
        print('${DateTime.now()} Detected actual BLE disconnection - updating Dart state');
        _onGlassesDisconnected();
      }
    } catch (e) {
      print('Error checking BLE connection status: $e');
    }
  }

  void startListening() {
    eventBleReceive.listen((res) {
      _handleReceivedData(res);
    });
  }

  Future<void> startScan() async {
    try {
      await _channel.invokeMethod('startScan');
    } catch (e, stackTrace) {
      print('Error starting scan: $e');
      print('Stack trace: $stackTrace');
    }
  }

  Future<void> stopScan() async {
    try {
      await _channel.invokeMethod('stopScan');
    } catch (e) {
      print('Error stopping scan: $e');
    }
  }

  Future<void> connectToGlasses(String deviceName) async {
    try {
      // Cancel any existing connection timeout
      _connectionTimeoutTimer?.cancel();
      _connectionTimeoutTimer = null;
      
      // Set initial connecting state
      connectionStatus = 'Connecting...';
      isConnected = false;
      onStatusChanged?.call();
      
      await _channel.invokeMethod('connectToGlasses', {'deviceName': deviceName});
      
      // Start connection timeout (in case native code doesn't send callbacks)
      // This is a safety timeout - native code should handle its own timeouts
      _connectionTimeoutTimer?.cancel();
      _connectionTimeoutTimer = Timer(Duration(seconds: 30), () {
        if (connectionStatus == 'Connecting...' && !isConnected) {
          connectionStatus = 'Connection timeout. Please try again.';
          isConnected = false;
          onStatusChanged?.call();
          _connectionTimeoutTimer?.cancel();
          _connectionTimeoutTimer = null;
        }
      });
    } on PlatformException catch (e) {
      // Handle platform-specific errors (like device not found)
      _connectionTimeoutTimer?.cancel();
      _connectionTimeoutTimer = null;
      connectionStatus = 'Connection failed: ${e.message ?? "Unknown error"}';
      isConnected = false;
      onStatusChanged?.call();
      print('Error connecting to device: $e');
    } catch (e) {
      _connectionTimeoutTimer?.cancel();
      _connectionTimeoutTimer = null;
      connectionStatus = 'Connection error: $e';
      isConnected = false;
      onStatusChanged?.call();
      print('Error connecting to device: $e');
    }
  }

  void setMethodCallHandler() {
    _channel.setMethodCallHandler(_methodCallHandler);
  }

  Timer? _connectionTimeoutTimer;

  Future<void> _methodCallHandler(MethodCall call) async {
    switch (call.method) {
      case 'glassesConnected':
        _connectionTimeoutTimer?.cancel();
        _connectionTimeoutTimer = null;
        _onGlassesConnected(call.arguments);
        break;
      case 'glassesConnecting':
        _onGlassesConnecting();
        break;
      case 'glassesDisconnected':
        _connectionTimeoutTimer?.cancel();
        _connectionTimeoutTimer = null;
        _onGlassesDisconnected();
        break;
      case 'glassesConnectionFailed':
        _connectionTimeoutTimer?.cancel();
        _connectionTimeoutTimer = null;
        _onGlassesConnectionFailed(call.arguments);
        break;
      case 'foundPairedGlasses':
        _onPairedGlassesFound(Map<String, String>.from(call.arguments));
        break;
      default:
        print('Unknown method: ${call.method}');
    }
  }

  void _onGlassesConnected(dynamic arguments) {
    print("_onGlassesConnected----arguments----$arguments------");
    connectionStatus = 'Connected: \n${arguments['leftDeviceName']} \n${arguments['rightDeviceName']}';
    isConnected = true;

    onStatusChanged?.call();
    startSendBeatHeart();
    
    // Start foreground service to keep connection alive in background
    _startForegroundService();
    
    // Note: Speech recognition for Pin Text is started when 0xF5 0x1E is received
    // (Start Pin Text recording command per protocol)
  }

  /// Start foreground service to maintain BLE connection in background
  Future<void> _startForegroundService() async {
    try {
      await _channel.invokeMethod('startForegroundService');
      print('${DateTime.now()} Started foreground service to maintain BLE connection');
      
      // Request battery optimization exception to prevent Android from killing the service
      // This is a reminder in case user didn't grant it on app startup
      try {
        await _channel.invokeMethod('requestBatteryOptimization');
        print('${DateTime.now()} Requested battery optimization exception');
      } catch (e) {
        print('Error requesting battery optimization: $e');
      }
    } catch (e) {
      print('Error starting foreground service: $e');
    }
  }

  /// Stop foreground service when disconnected
  Future<void> _stopForegroundService() async {
    try {
      await _channel.invokeMethod('stopForegroundService');
      print('${DateTime.now()} Stopped foreground service');
    } catch (e) {
      print('Error stopping foreground service: $e');
    }
  }

  int tryTime = 0;
  
  /// Start the heartbeat timer that sends periodic keep-alive messages to the glasses
  void startSendBeatHeart() {
    // Stop any existing heartbeat timer first
    stopSendBeatHeart();
    
    // If foreground service is running (which handles native heartbeat),
    // we don't need Dart heartbeat - native one is more reliable in background
    // Check if native heartbeat is running by checking if foreground service is active
    // For now, we'll still run Dart heartbeat but at a different interval to avoid conflicts
    // In production, consider disabling Dart heartbeat when native service is active
    
    // Reset failure count when starting
    _heartbeatFailureCount = 0;

    beatHeartTimer = Timer.periodic(Duration(seconds: 25), (timer) async {
      // Only send heartbeat if we think we're connected
      if (!isConnected) {
        print('${DateTime.now()} Heartbeat: Skipping - not connected');
        stopSendBeatHeart();
        return;
      }

      bool isSuccess = await Proto.sendHeartBeat();
      
      if (!isSuccess) {
        // Try once more if first attempt failed
        if (tryTime < 1) {
          tryTime++;
          print('${DateTime.now()} Heartbeat: Retrying after failure (attempt $tryTime)');
          isSuccess = await Proto.sendHeartBeat();
        }
        
        if (!isSuccess) {
          _heartbeatFailureCount++;
          final maxFailures = _isAppInBackground ? _maxHeartbeatFailuresInBackground : _maxHeartbeatFailures;
          print('${DateTime.now()} Heartbeat: Failed (consecutive failures: $_heartbeatFailureCount/$maxFailures) [Background: $_isAppInBackground]');
          
          // If we've failed too many times consecutively, check actual connection status
          if (_heartbeatFailureCount >= maxFailures) {
            print('${DateTime.now()} Heartbeat: Too many failures, checking actual connection status');
            
            // Check if we're actually still connected via native BLE
            await _checkActualConnectionStatus();
            
            // Only mark as disconnected if native confirms disconnection
            if (isConnected) {
              // Still connected according to native, but heartbeat failing
              // This might be a temporary issue, so reset counter and continue
              if (!_isAppInBackground) {
                // In foreground, be more strict - reset and try again
                _heartbeatFailureCount = 0;
                print('${DateTime.now()} Heartbeat: Native confirms connection, resetting failure count');
              } else {
                // In background, be more lenient - just reduce the counter
                _heartbeatFailureCount = maxFailures - 2;
                print('${DateTime.now()} Heartbeat: In background, reducing failure count');
              }
            } else {
              // Native confirms disconnection
              stopSendBeatHeart();
              connectionStatus = 'Connection lost (heartbeat failed)';
              onStatusChanged?.call();
              return;
            }
          }
        } else {
          // Success on retry - reset counters
          _heartbeatFailureCount = 0;
          tryTime = 0;
        }
      } else {
        // Success - reset all failure counters
        _heartbeatFailureCount = 0;
        tryTime = 0;
      }
    });
  }

  /// Stop the heartbeat timer
  void stopSendBeatHeart() {
    beatHeartTimer?.cancel();
    beatHeartTimer = null;
    tryTime = 0;
    _heartbeatFailureCount = 0;
    print('${DateTime.now()} Heartbeat: Stopped');
  }

  void _onGlassesConnecting() {
    connectionStatus = 'Connecting...';
    isConnected = false;
    
    // Start connection timeout
    _connectionTimeoutTimer?.cancel();
    _connectionTimeoutTimer = Timer(Duration(seconds: 20), () {
      if (connectionStatus == 'Connecting...' && !isConnected) {
        connectionStatus = 'Connection timeout. Please try again.';
        isConnected = false;
        onStatusChanged?.call();
        _connectionTimeoutTimer?.cancel();
        _connectionTimeoutTimer = null;
      }
    });
    
    onStatusChanged?.call();
  }

  void _onGlassesDisconnected() {
    // Stop heartbeat timer when disconnected
    stopSendBeatHeart();
    
    connectionStatus = 'Not connected';
    isConnected = false;

    // Note: We don't stop the foreground service here because it might be reconnecting
    // The service will handle its own lifecycle based on connection state
    // Only stop if this is an explicit user disconnection

    onStatusChanged?.call();
  }
  
  /// Explicitly disconnect and stop service (user-initiated)
  Future<void> disconnectAndStopService() async {
    try {
      await _channel.invokeMethod('disconnectFromGlasses');
      _onGlassesDisconnected();
      // Now stop the service since user explicitly disconnected
      await _stopForegroundService();
    } catch (e) {
      print('Error disconnecting: $e');
    }
  }

  void _onGlassesConnectionFailed(dynamic status) {
    print("_onGlassesConnectionFailed----status----$status------");
    
    // Stop heartbeat timer when connection fails
    stopSendBeatHeart();
    
    // Get a more descriptive error message
    String errorMsg = 'Connection failed.';
    if (status is int) {
      if (status == -1) {
        errorMsg = 'Device not found. Please scan again.';
      } else {
        errorMsg = 'Connection failed (error: $status). Please try again.';
      }
    }
    
    connectionStatus = errorMsg;
    isConnected = false;
    
    // Clean up timeout timer
    _connectionTimeoutTimer?.cancel();
    _connectionTimeoutTimer = null;
    
    onStatusChanged?.call();
  }

  void _onPairedGlassesFound(Map<String, String> deviceInfo) {
    final String channelNumber = deviceInfo['channelNumber']!;
    final isAlreadyPaired = pairedGlasses.any((glasses) => glasses['channelNumber'] == channelNumber);

    if (!isAlreadyPaired) {
      pairedGlasses.add(deviceInfo);
    }

    onStatusChanged?.call();
  }

  void _handleReceivedData(BleReceive res) {
    if (res.type == "VoiceChunk") {
      return;
    }

    String cmd = "${res.lr}${res.getCmd().toRadixString(16).padLeft(2, '0')}";
    if (res.getCmd() != 0xf1) {
      print(
        "${DateTime.now()} BleManager receive cmd: $cmd, len: ${res.data.length}, data = ${res.data.hexString}",
      );
    }

    // Command 0x21 - might be audio data or other note-related data
    // Command 0x22 - might be note status/data (seen in logs)
    // These are handled but not processed for text extraction
    // Speech recognition is handled via 0xF5 0x1E (start) and 0xF5 0x1F (end)
    if (res.data.isNotEmpty && (res.data[0].toInt() == 0x21 || res.data[0].toInt() == 0x22)) {
      print('${DateTime.now()} PinText: Received command 0x${res.data[0].toRadixString(16)} (len=${res.data.length}), might be note data');
      // Log but don't process - these are likely binary data or status
      return; // Don't process further
    }

    if (res.data.isNotEmpty && res.data[0].toInt() == 0xF6) {
      _handleF6Command(res);
      return;
    }

    // Handle other unknown commands
    if (res.data.isNotEmpty && 
        res.data[0].toInt() != 0xF5 && 
        res.data[0].toInt() != 0xF1 &&
        res.data[0].toInt() != 0x25 && // Heartbeat
        res.data[0].toInt() != 0x4E && // Response to our command
        res.data[0].toInt() != 0x21) { // Voice recording/note data (handled above)
      // Log unrecognized commands for debugging
      print('${DateTime.now()} PinText: Received unknown command 0x${res.data[0].toRadixString(16)}, might be note data');
    }

    if (res.data[0].toInt() == 0xF5) {
      final notifyIndex = res.data[1].toInt();
      
      switch (notifyIndex) {
        case 0:
          App.get.exitAll();
          // Exit all features, return to dashboard
          try {
            final pinTextController = Get.find<PinTextController>();
            pinTextController.isDashboardMode.value = true;
            // Pinned note is just a UI marker - do NOT auto-send
          } catch (e) {
            print('PinTextController not found: $e');
          }
          break;
        case 1: 
          // Check if there's a custom touchpad callback (e.g., from upload image page)
          if (onTouchpadTap != null) {
            onTouchpadTap!(res.lr ?? 'L');
            break;
          }
          
          // Check if we're in dashboard mode or feature mode
          try {
            final pinTextController = Get.find<PinTextController>();
            
            if (pinTextController.isDashboardMode.value && 
                !EvenAI.isRunning && 
                !TextService.isRunning) {
              // Dashboard mode - navigate Pin Text
              if (res.lr == 'R') {
                // Right tap - next Pin Text
                pinTextController.nextNote();
                final currentNote = pinTextController.getCurrentNote();
                if (currentNote != null) {
                  PinTextService.instance.sendPinText(currentNote.content);
                }
              } else if (res.lr == 'L') {
                // Left tap - previous Pin Text
                pinTextController.previousNote();
                final currentNote = pinTextController.getCurrentNote();
                if (currentNote != null) {
                  PinTextService.instance.sendPinText(currentNote.content);
                }
              }
            } else {
              // Feature mode - normal page navigation
              if (res.lr == 'L') {
                EvenAI.get.lastPageByTouchpad();
              } else {
                EvenAI.get.nextPageByTouchpad();
              }
            }
          } catch (e) {
            // PinTextController not found, use default behavior
          if (res.lr == 'L') {
            EvenAI.get.lastPageByTouchpad();
          } else {
            EvenAI.get.nextPageByTouchpad();
            }
          }
          break;
        case 23: //BleEvent.evenaiStart:
          // Start Even AI - exit dashboard mode
          try {
            final pinTextController = Get.find<PinTextController>();
            pinTextController.isDashboardMode.value = false;
          } catch (e) {
            print('PinTextController not found: $e');
          }
          EvenAI.get.toStartEvenAIByOS();
          break;
        case 24: //BleEvent.evenaiRecordOver:
          EvenAI.get.recordOverByOS();
          break;
        case 10: // 0x0A - Dashboard/Pin Text related event (from logs)
          print("${DateTime.now()} Received 0xF5 0x0A - Dashboard event");
          // This is just a dashboard event - do NOT start recognition here
          // Speech recognition should only start when 0xF5 0x1E is received (Pin Text recording start)
          try {
            final pinTextController = Get.find<PinTextController>();
            pinTextController.isDashboardMode.value = true;
            print("${DateTime.now()} Dashboard mode enabled via 0xF5 0x0A");
          } catch (e) {
            print('PinTextController not found: $e');
          }
          break;
        case 30: // 0x1E - Start Pin Text recording (per Google Docs protocol)
          print("${DateTime.now()} Received 0xF5 0x1E - Start Pin Text recording");
          if (!EvenAI.isRunning) {
            try {
              print('${DateTime.now()} PinText: Starting speech recognition for Pin Text recording');
              // Start speech recognition when Pin Text recording starts
              // This uses phone microphone - user must speak into phone
              BleManager.invokeMethod("startEvenAI").then((_) {
                print('${DateTime.now()} PinText: Speech recognition started (phone microphone)');
              }).catchError((e) {
                print('${DateTime.now()} PinText: Error starting recognition: $e');
              });
            } catch (e) {
              print('${DateTime.now()} PinText: Error handling 0xF5 0x1E: $e');
            }
          }
          break;
        case 31: // 0x1F - End Pin Text recording (per Google Docs protocol)
          print("${DateTime.now()} Received 0xF5 0x1F - End Pin Text recording");
          if (!EvenAI.isRunning) {
            try {
              print('${DateTime.now()} PinText: Stopping recognition to get final results');
              // Stop recognition to get final results
              BleManager.invokeMethod("stopEvenAI").then((_) {
                print('${DateTime.now()} PinText: Recognition stopped, waiting for results');
                // Start fresh recognition after a delay for next recording
                Future.delayed(const Duration(milliseconds: 1000), () {
                  print('${DateTime.now()} PinText: Starting fresh recognition for next recording');
                  BleManager.invokeMethod("startEvenAI").catchError((e) {
                    print('${DateTime.now()} PinText: Error starting fresh recognition: $e');
                  });
                });
              }).catchError((e) {
                print('${DateTime.now()} PinText: Error stopping recognition: $e');
              });
            } catch (e) {
              print('${DateTime.now()} PinText: Error handling 0xF5 0x1F: $e');
            }
          }
          break;
        default:
          print("${DateTime.now()} Unknown Ble Event: $notifyIndex (0x${notifyIndex.toRadixString(16).padLeft(2, '0')})");
          // Log full command data for debugging Pin Text recording trigger
          if (notifyIndex >= 20 && notifyIndex <= 40) {
            print("${DateTime.now()} Potential Pin Text command? Full data: ${res.data.hexString}");
          }
      }
      return;
    }
      _reqListen.remove(cmd)?.complete(res);
      _reqTimeout.remove(cmd)?.cancel();
      if (_nextReceive != null) {
        _nextReceive?.complete(res);
        _nextReceive = null;
      }

  }

  void _handleF6Command(BleReceive res) {
    if (res.data.length < 3) {
      return;
    }

    final subCmd = res.data[1].toInt();
    final chunkIndex = res.data[2].toInt();
    final chunkData = res.data.length > 3 ? res.data.sublist(3) : <int>[];
    final bufferKey = '${res.lr ?? ''}-$subCmd';
    final buffer = _f6MessageBuffers.putIfAbsent(bufferKey, () => StringBuffer());

    if (chunkIndex == 0) {
      buffer.clear();
    }

    if (chunkData.isNotEmpty) {
      try {
        buffer.write(utf8.decode(chunkData, allowMalformed: true));
      } catch (e) {
        print('BleManager: Error decoding 0xF6 chunk: $e');
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

  String getConnectionStatus() {
    return connectionStatus;
  }

  /// Reset connection state (for retry after failure)
  void resetConnectionState() {
    // Stop heartbeat when resetting connection
    stopSendBeatHeart();
    _connectionTimeoutTimer?.cancel();
    _connectionTimeoutTimer = null;
    connectionStatus = 'Not connected';
    isConnected = false;
  }

  List<Map<String, String>> getPairedGlasses() {
    return pairedGlasses;
  }


  static final _reqListen = <String, Completer<BleReceive>>{};
  static final _reqTimeout = <String, Timer>{};
  static Completer<BleReceive>? _nextReceive;

  static _checkTimeout(String cmd, int timeoutMs, Uint8List data, String lr) {
    _reqTimeout.remove(cmd);
    var cb = _reqListen.remove(cmd);
    print('${DateTime.now()} _checkTimeout-----timeoutMs----$timeoutMs-----cb----$cb-----');
    if (cb != null) {
      var res = BleReceive();
      res.isTimeout = true;
      //var showData = data.length > 50 ? data.sublist(0, 50) : data;
      print(
          "send Timeout $cmd of $timeoutMs");
      cb.complete(res);
    }

    _reqTimeout[cmd]?.cancel();
    _reqTimeout.remove(cmd);
  }

  static Future<T?> invokeMethod<T>(String method, [dynamic params]) {
    return _channel.invokeMethod(method, params);
  }

  static Future<BleReceive> requestRetry(
    Uint8List data, {
    String? lr,
    Map<String, dynamic>? other,
    int timeoutMs = 200,
    bool useNext = false,
    int retry = 3,
  }) async {
    BleReceive ret;
    for (var i = 0; i <= retry; i++) {
      ret = await request(data,
          lr: lr, other: other, timeoutMs: timeoutMs, useNext: useNext);
      if (!ret.isTimeout) {
        return ret;
      }
      if (!BleManager.isBothConnected()) {
        break;
      }
    }
    ret = BleReceive();
    ret.isTimeout = true;
    print(
        "requestRetry $lr timeout of $timeoutMs");
    return ret;
  }

  static Future<bool> sendBoth(
    data, {
    int timeoutMs = 250,
    SendResultParse? isSuccess,
    int? retry,
  }) async {

    var ret = await BleManager.requestRetry(data,
        lr: "L", timeoutMs: timeoutMs, retry: retry ?? 0);
    if (ret.isTimeout) {
      print("sendBoth L timeout");

      return false;
    } else if (isSuccess != null) {
      final success = isSuccess.call(ret.data);
      if (!success) return false;
      var retR = await BleManager.requestRetry(data,
          lr: "R", timeoutMs: timeoutMs, retry: retry ?? 0);
      if (retR.isTimeout) return false;
      return isSuccess.call(retR.data);
    } else if (ret.data[1].toInt() == 0xc9) {
      var ret = await BleManager.requestRetry(data,
          lr: "R", timeoutMs: timeoutMs, retry: retry ?? 0);
      if (ret.isTimeout) return false;
    }
    return true;
  }

  static Future sendData(Uint8List data,
      {String? lr, Map<String, dynamic>? other, int secondDelay = 100}) async {

    var params = <String, dynamic>{
      'data': data,
    };
    if (other != null) {
      params.addAll(other);
    }
    dynamic ret;
    if (lr != null) {
      params["lr"] = lr;
      ret = await BleManager.invokeMethod(methodSend, params);
      return ret;
    } else {
      params["lr"] = "L"; // get().slave; 
      var ret = await _channel
          .invokeMethod(methodSend, params); //ret is true or false or null
      if (ret == true) {
        params["lr"] = "R"; // get().master;
        ret = await BleManager.invokeMethod(methodSend, params);
        return ret;
      }
      if (secondDelay > 0) {
        await Future.delayed(Duration(milliseconds: secondDelay));
      }
      params["lr"] = "R"; // get().master;
      ret = await BleManager.invokeMethod(methodSend, params);
      return ret;
    }
  }

  static Future<BleReceive> request(Uint8List data,
      {String? lr,
      Map<String, dynamic>? other,
      int timeoutMs = 1000, //500,
      bool useNext = false}) async {

    var lr0 = lr ?? Proto.lR();
    var completer = Completer<BleReceive>();
    String cmd = "$lr0${data[0].toRadixString(16).padLeft(2, '0')}";

    if (useNext) {
      _nextReceive = completer;
    } else {
      if (_reqListen.containsKey(cmd)) {
        var res = BleReceive();
        res.isTimeout = true;
        _reqListen[cmd]?.complete(res);
        print("already exist key: $cmd");

        _reqTimeout[cmd]?.cancel();
      }
      _reqListen[cmd] = completer;
    }
    print("request key: $cmd, ");

    if (timeoutMs > 0) {
      _reqTimeout[cmd] = Timer(Duration(milliseconds: timeoutMs), () {
        _checkTimeout(cmd, timeoutMs, data, lr0);
      });
    }

    completer.future.then((result) {
      _reqTimeout.remove(cmd)?.cancel();
    });

    await sendData(data, lr: lr, other: other).timeout(
      Duration(seconds: 2),
      onTimeout: () {
        _reqTimeout.remove(cmd)?.cancel();
        var ret = BleReceive();
        ret.isTimeout = true;
        _reqListen.remove(cmd)?.complete(ret);
      },
    );

    return completer.future;
  }

  static bool isBothConnected() {
    //return isConnectedL() && isConnectedR();

    // todo
    return true;
  }

  static Future<bool> requestList(
    List<Uint8List> sendList, {
    String? lr,
    int? timeoutMs,
  }) async {
    print("requestList---sendList---${sendList.first}----lr---$lr----timeoutMs----$timeoutMs-");

    if (lr != null) {
      return await _requestList(sendList, lr, timeoutMs: timeoutMs);
    } else {
      var rets = await Future.wait([
        _requestList(sendList, "L", keepLast: true, timeoutMs: timeoutMs),
        _requestList(sendList, "R", keepLast: true, timeoutMs: timeoutMs),
      ]);
      if (rets.length == 2 && rets[0] && rets[1]) {
        var lastPack = sendList[sendList.length - 1];
        return await sendBoth(lastPack, timeoutMs: timeoutMs ?? 250);
      } else {
        print("error request lr leg");
      }
    }
    return false;
  }

  static Future<bool> _requestList(List sendList, String lr,
      {bool keepLast = false, int? timeoutMs}) async {
    int len = sendList.length;
    if (keepLast) len = sendList.length - 1;
    for (var i = 0; i < len; i++) {
      var pack = sendList[i];
      var resp = await request(pack, lr: lr, timeoutMs: timeoutMs ?? 350);
      if (resp.isTimeout) {
        print("_requestList: Timeout on packet $i/$len for $lr");
        return false;
      }
      
      // Validate response data
      if (resp.data.isEmpty) {
        print("_requestList: Empty response on packet $i/$len for $lr");
        return false;
      }
      
      // Check response status (0xc9 = success, 0xCB = success alternative)
      if (resp.data.length > 1) {
        int status = resp.data[1].toInt();
        if (status != 0xc9 && status != 0xcB) {
          print("_requestList: Invalid status 0x${status.toRadixString(16)} on packet $i/$len for $lr");
          return false;
        }
      } else {
        print("_requestList: Response too short (length ${resp.data.length}) on packet $i/$len for $lr");
        return false;
      }
    }
    return true;
  }

}

extension Uint8ListEx on Uint8List {
  String get hexString {
    return map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ');
  }
}
