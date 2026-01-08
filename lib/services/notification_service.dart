import 'dart:async';
import 'dart:convert';
import 'package:demo_ai_even/ble_manager.dart';
import 'package:demo_ai_even/services/proto.dart';
import 'package:demo_ai_even/services/evenai.dart';
import 'package:demo_ai_even/views/features/notification/notify_model.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationService {
  static NotificationService? _instance;
  static NotificationService get instance => _instance ??= NotificationService._();

  NotificationService._();

  static const MethodChannel _methodChannel = MethodChannel('method.bluetooth');
  static const EventChannel _notificationReceivedChannel = 
      EventChannel('eventNotificationReceived');
  static const EventChannel _notificationListenerStatusChannel = 
      EventChannel('eventNotificationListenerStatus');

  StreamSubscription? _notificationSubscription;
  StreamSubscription? _statusSubscription;
  bool _isListening = false;
  bool _isNotificationAccessEnabled = false;
  int _notificationId = 0;
  
  static const _whitelistPrefsKey = 'notification_whitelist';
  static const _whitelistNamesPrefsKey = 'notification_whitelist_names';

  // Whitelist of apps to forward notifications from
  // Empty list means forward all notifications
  Set<String> _whitelistedApps = {};
  final Map<String, String> _whitelistedAppNames = {};
  
  // Track recently sent call notifications to prevent duplicates
  // Key: combination of msg_id, caller info, and timestamp
  // Value: timestamp when it was sent
  final Map<String, int> _recentCallNotifications = {};
  static const int _callDeduplicationWindowSeconds = 30; // Don't resend same call within 30 seconds

  /// Check if notification access is enabled
  Future<bool> checkNotificationPermission() async {
    try {
      final bool enabled = await _methodChannel.invokeMethod('checkNotificationPermission') ?? false;
      _isNotificationAccessEnabled = enabled;
      return enabled;
    } catch (e) {
      print('Error checking notification permission: $e');
      return false;
    }
  }

  /// Open system settings to enable notification access
  Future<void> openNotificationSettings() async {
    try {
      await _methodChannel.invokeMethod('openNotificationSettings');
    } catch (e) {
      print('Error opening notification settings: $e');
    }
  }

  /// Request notification permission (Android 13+)
  /// Returns true if permission is granted, false otherwise
  Future<bool> requestNotificationPermission() async {
    try {
      final bool granted = await _methodChannel.invokeMethod('requestNotificationPermission') ?? false;
      return granted;
    } catch (e) {
      print('Error requesting notification permission: $e');
      return false;
    }
  }

  /// Set whitelist of apps to forward notifications from
  /// Empty set means forward all notifications
  void setWhitelistedApps(Set<String> appIdentifiers) {
    _whitelistedApps = Set.from(appIdentifiers);
    for (final id in _whitelistedApps) {
      _whitelistedAppNames.putIfAbsent(id, () => id);
    }
    unawaited(_persistWhitelist());
    unawaited(_sendWhitelistToGlasses());
  }

  /// Add app to whitelist
  void addWhitelistedApp(String appIdentifier, {String? displayName}) {
    if (appIdentifier.isEmpty) {
      return;
    }
    _whitelistedApps.add(appIdentifier);
    if (displayName != null && displayName.trim().isNotEmpty) {
      _whitelistedAppNames[appIdentifier] = displayName.trim();
    } else {
      _whitelistedAppNames.putIfAbsent(appIdentifier, () => appIdentifier);
    }
    unawaited(_persistWhitelist());
    unawaited(_sendWhitelistToGlasses());
  }

  /// Remove app from whitelist
  void removeWhitelistedApp(String appIdentifier) {
    _whitelistedApps.remove(appIdentifier);
    _whitelistedAppNames.remove(appIdentifier);
    unawaited(_persistWhitelist());
    unawaited(_sendWhitelistToGlasses());
  }

  /// Check if app is whitelisted (or if whitelist is empty)
  bool _isAppWhitelisted(String appIdentifier) {
    if (_whitelistedApps.isEmpty) {
      return true; // If whitelist is empty, forward all
    }
    return _whitelistedApps.contains(appIdentifier);
  }

  /// Start listening for notifications
  Future<void> startListening() async {
    if (_isListening) {
      print('NotificationService: Already listening');
      return;
    }

    // Load whitelist from storage
    await _loadWhitelistFromStorage();

    // Check permission first
    final hasPermission = await checkNotificationPermission();
    if (!hasPermission) {
      print('NotificationService: Notification access not enabled');
      return;
    }

    await _sendWhitelistToGlasses();

    try {
      // Listen for notification listener status changes
      _statusSubscription = _notificationListenerStatusChannel
          .receiveBroadcastStream()
          .listen((status) {
        _isNotificationAccessEnabled = status as bool? ?? false;
        print('NotificationService: Listener status changed: $_isNotificationAccessEnabled');
        
        if (!_isNotificationAccessEnabled && _isListening) {
          // Service disconnected, stop listening
          stopListening();
        } else if (_isNotificationAccessEnabled && !_isListening) {
          // Service connected, start listening
          _startNotificationStream();
        }
      });

      // Start listening for notifications if access is enabled
      if (_isNotificationAccessEnabled) {
        await _startNotificationStream();
      }

      // Start foreground service to keep app running in background
      await _startForegroundService();

      _isListening = true;
      print('NotificationService: Started listening for notifications');
    } catch (e) {
      print('Error starting notification listener: $e');
    }
  }

  Future<void> _startNotificationStream() async {
    try {
      _notificationSubscription?.cancel();
      _notificationSubscription = _notificationReceivedChannel
          .receiveBroadcastStream()
          .listen((notificationData) {
        unawaited(_handleNotification(notificationData));
      });
    } catch (e) {
      print('Error starting notification stream: $e');
    }
  }

  /// Stop listening for notifications
  void stopListening() {
    _notificationSubscription?.cancel();
    _notificationSubscription = null;
    _statusSubscription?.cancel();
    _statusSubscription = null;
    _isListening = false;
    
    // Stop foreground service
    _stopForegroundService();
    
    print('NotificationService: Stopped listening for notifications');
  }

  /// Start foreground service to keep app running in background
  Future<void> _startForegroundService() async {
    try {
      await _methodChannel.invokeMethod('startForegroundService');
      print('NotificationService: Foreground service started');
    } catch (e) {
      print('Error starting foreground service: $e');
    }
  }

  /// Stop foreground service
  Future<void> _stopForegroundService() async {
    try {
      await _methodChannel.invokeMethod('stopForegroundService');
      print('NotificationService: Foreground service stopped');
    } catch (e) {
      print('Error stopping foreground service: $e');
    }
  }

  /// Handle incoming notification from native
  Future<void> _handleNotification(dynamic notificationData) async {
    try {
      print('NotificationService: Received notification data: $notificationData');
      
      // Parse notification data
      String jsonString;
      if (notificationData is String) {
        jsonString = notificationData;
      } else {
        jsonString = jsonEncode(notificationData);
      }

      final Map<String, dynamic> data = jsonDecode(jsonString);
      print('NotificationService: Parsed data: $data');
      
      // Extract app identifier
      final String? appIdentifier = data['app_identifier'] as String?;
      print('NotificationService: App identifier: $appIdentifier');
      print('NotificationService: Whitelisted apps: $_whitelistedApps');
      
      // Create NotifyModel first to check if it's a call
      var notify = NotifyModel(
        data['msg_id'] as int? ?? 0,
        appIdentifier ?? '',
        data['title'] as String? ?? '',
        data['subtitle'] as String? ?? '',
        data['message'] as String? ?? '',
        data['time_s'] as int? ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
        data['display_name'] as String? ?? '',
      );

      // Check if this is a call notification (calls should always be forwarded)
      final isCall = _isCallNotification(notify, data);
      data['is_call'] = isCall;
      
      // For call notifications, check for duplicates EARLY using phone number or contact name
      if (isCall) {
        // Extract phone number or contact name for deduplication
        final callKey = _getCallDeduplicationKey(notify, data);
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final lastSentTime = _recentCallNotifications[callKey];
        
        if (lastSentTime != null && (now - lastSentTime) < _callDeduplicationWindowSeconds) {
          print('NotificationService: Duplicate call notification detected (key: $callKey, sent ${now - lastSentTime}s ago), skipping');
          return;
        }
        
        // Mark this call as sent IMMEDIATELY to prevent duplicate processing
        _recentCallNotifications[callKey] = now;
        print('NotificationService: Call notification key: $callKey, will process and send to glasses');
        
        // Clean up old entries (older than deduplication window)
        _cleanupOldCallNotifications(now);
      }
      
      if (isCall && appIdentifier != null && !_isAppWhitelisted(appIdentifier)) {
        final callerLines = _extractCallerInfoLines(notify);
        final displayLabel = callerLines.isNotEmpty
            ? callerLines.first
            : (notify.displayName.isNotEmpty
                ? notify.displayName
                : (notify.subTitle.isNotEmpty ? notify.subTitle : appIdentifier));
        addWhitelistedApp(appIdentifier, displayName: displayLabel);
        data['caller_name_whitelisted'] = displayLabel;
      }

      // For call notifications, try to enrich with caller name lookup
      // But don't block - if enrichment fails or takes too long, use original data
      if (isCall) {
        try {
          // Use a shorter timeout to avoid delaying the notification
          notify = await _enrichCallNotificationData(notify, data)
              .timeout(const Duration(milliseconds: 300), onTimeout: () {
            print('NotificationService: Call enrichment timeout, using original data');
            return notify; // Return original if timeout
          });
        } catch (e) {
          print('NotificationService: Error enriching call notification: $e');
          // Continue with original notify if enrichment fails
        }
      }
      
      // Check whitelist (but always allow call notifications)
      if (!isCall && appIdentifier != null && !_isAppWhitelisted(appIdentifier)) {
        print('NotificationService: App $appIdentifier not in whitelist, skipping');
        return;
      }
      
      if (isCall) {
        print('NotificationService: Call notification detected - bypassing whitelist');
      }

      print('NotificationService: Created NotifyModel - title: "${notify.title}", message: "${notify.message}", subtitle: "${notify.subTitle}", displayName: "${notify.displayName}", category: "${data['category']}", isCall: $isCall');
      if (isCall) {
        print('NotificationService: Call notification - caller ID will be: "${notify.message.isNotEmpty ? notify.message : notify.displayName}"');
      }

      // Send to glasses (will also update UI)
      // Pass raw data for call detection
      await _sendNotificationToGlasses(notify, data);
    } catch (e, stackTrace) {
      print('Error handling notification: $e');
      print('Stack trace: $stackTrace');
    }
  }

  /// Send notification to glasses
  Future<void> _sendNotificationToGlasses(NotifyModel notify, [Map<String, dynamic>? rawData]) async {
    final bool isCall = rawData?['is_call'] == true;

    // Format notification for display
    final displayText = _formatNotificationForDisplay(notify, rawData);
    
    // Always update UI to show notification (same place as AI responses)
    EvenAI.updateDynamicText(displayText);
    
    if (!BleManager.get().isConnected) {
      print('NotificationService: Cannot send notification to glasses - glasses not connected');
      print('NotificationService: Notification displayed in UI: $displayText');
      return;
    }

    try {
      // Double-check connection state
      if (!BleManager.get().isConnected) {
        print('NotificationService: Connection check failed - isConnected = false');
        print('NotificationService: Connection status: ${BleManager.get().getConnectionStatus()}');
        EvenAI.updateDynamicText('$displayText\n\n⚠️ Cannot send - glasses not connected');
        return;
      }

      // Increment notification ID (wrap around at 255)
      _notificationId = (_notificationId + 1) % 256;

      final notifyMap = Map<String, dynamic>.from(notify.toMap());
      if (rawData != null) {
        if (rawData['category'] != null) {
          notifyMap['category'] = rawData['category'];
        }
        if (rawData['call_notification'] == true) {
          notifyMap['call_notification'] = true;
        }
        if (rawData['is_call'] == true) {
          notifyMap['is_call'] = true;
        }
        if (rawData['caller_name_lookup'] != null) {
          notifyMap['caller_name_lookup'] = rawData['caller_name_lookup'];
        }
      }
      if (isCall) {
        // For call notifications, the enriched notify should already have the correct structure
        // The notify.toMap() above already populated all fields correctly from the enriched notify
        // Just ensure title is "Incoming Call" and add call-specific flags
        notifyMap['title'] = 'Incoming Call';
        
        // Ensure message and display_name are set (they should be from enrichment, but double-check)
        if (notifyMap['message'] == null || (notifyMap['message'] as String).isEmpty) {
          notifyMap['message'] = notifyMap['display_name'] ?? 'Unknown Caller';
        }
        if (notifyMap['display_name'] == null || (notifyMap['display_name'] as String).isEmpty) {
          notifyMap['display_name'] = notifyMap['message'] ?? 'Incoming Call';
        }
        
        print('NotificationService: Call notification payload - title: "${notifyMap['title']}", message: "${notifyMap['message']}", display_name: "${notifyMap['display_name']}", subtitle: "${notifyMap['subtitle']}"');
      }
      print('NotificationService: Sending notification to glasses');
      print('NotificationService: Notification ID: $_notificationId');
      print('NotificationService: Notification data: $notifyMap');
      print('NotificationService: Display text: $displayText');
      print('NotificationService: Connection status: ${BleManager.get().getConnectionStatus()}');
      
      // Send to glasses (now returns bool)
      bool success = await Proto.sendNotify(notifyMap, _notificationId);
      
      if (success) {
        print('NotificationService: ✅ Notification sent successfully to glasses');
        // Update UI to confirm it was sent
        if (isCall) {
          EvenAI.updateDynamicText('$displayText\n\n✅ Call sent to glasses');
        } else {
          EvenAI.updateDynamicText('$displayText\n\n✅ Sent to glasses');
        }
      } else {
        print('NotificationService: ❌ Failed to send notification after retries');
        final failureSuffix = isCall
            ? '\n\n❌ Failed to send call to glasses (check connection)'
            : '\n\n❌ Failed to send to glasses (check connection)';
        EvenAI.updateDynamicText('$displayText$failureSuffix');
      }
    } catch (e, stackTrace) {
      print('NotificationService: ❌ Error sending notification to glasses: $e');
      print('Stack trace: $stackTrace');
      // Still update UI with error message
      final errorSuffix = isCall
          ? '\n\n❌ Call send error: $e'
          : '\n\n❌ Error: $e';
      EvenAI.updateDynamicText('$displayText$errorSuffix');
    }
  }

  /// Check if notification is a call notification
  bool _isCallNotification(NotifyModel notify, Map<String, dynamic>? rawData) {
    // Hardcode to false for testing
    return false;

    // Check notification category (if available)
    final category = rawData?['category'] as String?;
    if (category == 'call') {
      return true;
    }
    
    // Check app identifier for common phone/dialer packages
    final appId = notify.appIdentifier.toLowerCase();
    final phonePackagePatterns = [
      'phone',
      'dialer',
      'telecom',
      'incallui',
      'call',
    ];
    
    if (phonePackagePatterns.any((pattern) => appId.contains(pattern))) {
      return true;
    }
    
    // Check title/text for call-related keywords
    final titleLower = notify.title.toLowerCase();
    final messageLower = notify.message.toLowerCase();
    final subTitleLower = notify.subTitle.toLowerCase();
    final displayNameLower = notify.displayName.toLowerCase();
    
    final callKeywords = [
      'incoming call',
      'call',
      'calling',
      'phone call',
      'ringing',
    ];
    
    if (callKeywords.any((keyword) => 
        titleLower.contains(keyword) || 
        messageLower.contains(keyword) || 
        subTitleLower.contains(keyword) ||
        displayNameLower.contains(keyword))) {
      return true;
    }
    
    return false;
  }

  /// Extract caller info lines (name/number) from a call notification
  List<String> _extractCallerInfoLines(NotifyModel notify) {
    final lines = <String>[];

    String cleaned(String value) => value.trim();

    final subTitle = cleaned(notify.subTitle);
    final message = cleaned(notify.message);
    final title = cleaned(notify.title);
    final display = cleaned(notify.displayName);

    bool isGenericCallLabel(String value) {
      if (value.isEmpty) return true;
      final lower = value.toLowerCase();
      return lower.contains('incoming call') ||
          lower.contains('phone call') ||
          lower.contains('calling');
    }

    // Subtitle often holds the contact name
    if (subTitle.isNotEmpty) {
      lines.add(subTitle);
    }

    // Message may contain the phone number or contact info
    if (message.isNotEmpty && !lines.contains(message)) {
      lines.add(message);
    }

    // If both subtitle and message missing, fall back to title if it isn't generic
    if (lines.isEmpty && title.isNotEmpty && !isGenericCallLabel(title)) {
      lines.add(title);
    }

    // Finally fall back to display name if it looks meaningful
    if (lines.isEmpty && display.isNotEmpty && !isGenericCallLabel(display)) {
      lines.add(display);
    }

    if (lines.isEmpty) {
      lines.add('Unknown Caller');
    }

    return lines;
  }

  Future<NotifyModel> _enrichCallNotificationData(NotifyModel notify, Map<String, dynamic> rawData) async {
    // Get the caller ID from existing fields (message or subtitle usually contains caller name/number)
    // Priority: message > subtitle > title
    final originalCallerId = _firstNonEmpty([
      notify.message,
      notify.subTitle,
      notify.title,
    ]);
    
    print('NotificationService: Enriching call - original caller ID: "$originalCallerId"');
    
    // Determine the final caller ID to use
    String finalCallerId;
    String finalSubtitle = notify.subTitle;
    
    // If we already have a meaningful caller ID (name, not just a number or generic label)
    if (originalCallerId.isNotEmpty && 
        !_isGenericCallLabel(originalCallerId) && 
        !_looksLikeJustPhoneNumber(originalCallerId)) {
      // We already have a name, use it as-is
      finalCallerId = originalCallerId;
      print('NotificationService: Using existing caller ID: "$finalCallerId"');
    } else {
      // Try to extract phone number and resolve to name
      final phoneNumber = _extractPhoneNumber(notify);
      String? resolvedName;
      
      if (phoneNumber != null && phoneNumber.isNotEmpty) {
        print('NotificationService: Extracted phone number: "$phoneNumber", attempting name resolution...');
        // Try to resolve the phone number to a name (with short timeout)
        try {
          resolvedName = await _resolveCallerName(phoneNumber)
              .timeout(const Duration(milliseconds: 400));
          if (resolvedName != null && resolvedName.isNotEmpty && resolvedName != phoneNumber) {
            rawData['caller_name_lookup'] = resolvedName;
            print('NotificationService: Resolved name: "$resolvedName"');
          } else {
            print('NotificationService: Name resolution returned same as phone number or empty');
          }
        } catch (e) {
          print('NotificationService: Name resolution timeout or error: $e');
          // Continue without resolved name
        }
      }
      
      // Use resolved name if available, otherwise use original caller ID or phone number
      if (resolvedName != null && resolvedName.isNotEmpty && resolvedName != phoneNumber) {
        finalCallerId = resolvedName;
        // If we resolved a name, keep the phone number as subtitle if available
        if (phoneNumber != null && finalSubtitle.isEmpty) {
          finalSubtitle = phoneNumber;
        }
      } else {
        finalCallerId = originalCallerId.isNotEmpty 
            ? originalCallerId 
            : (phoneNumber ?? 'Unknown Caller');
      }
    }

    // Create enriched notification with proper structure
    final enriched = NotifyModel(
      notify.msgId,
      notify.appIdentifier,
      'Incoming Call', // Always set title to "Incoming Call" for calls
      finalSubtitle,   // subtitle can be empty or contain phone number
      finalCallerId,   // message = caller ID (name or number)
      notify.timestamp,
      finalCallerId,   // display_name = caller ID
    );
    
    print('NotificationService: Enriched call notification - title: "${enriched.title}", message: "${enriched.message}", displayName: "${enriched.displayName}", subtitle: "${enriched.subTitle}"');
    
    return enriched;
  }
  
  bool _looksLikeJustPhoneNumber(String value) {
    if (value.isEmpty) return false;
    // Remove all non-digit characters and check length
    final digits = value.replaceAll(RegExp(r'[^0-9+]'), '');
    // If it's mostly digits (70%+) and has 7+ digits, it's probably just a phone number
    final totalChars = value.replaceAll(RegExp(r'\s'), '').length;
    return digits.length >= 7 && totalChars > 0 && (digits.length / totalChars) > 0.7;
  }
  
  bool _isGenericCallLabel(String value) {
    if (value.isEmpty) return true;
    final lower = value.toLowerCase();
    return lower.contains('incoming call') ||
        lower.contains('phone call') ||
        lower.contains('calling') ||
        lower == 'phone';
  }

  String? _extractPhoneNumber(NotifyModel notify) {
    // Try to find a phone number in the notification fields
    // Check subtitle first (often contains phone number), then message, then title
    final candidates = [notify.subTitle, notify.message, notify.title];
    for (final candidate in candidates) {
      if (candidate.isEmpty) continue;
      // Extract digits and check if it looks like a phone number
      final digits = candidate.replaceAll(RegExp(r'[^0-9+]'), '');
      if (digits.length >= 7 && digits.length <= 15) {
        // Return the normalized digits for lookup
        return digits;
      }
    }
    return null;
  }


  Future<String?> _resolveCallerName(String phoneNumber) async {
    try {
      final name = await _methodChannel.invokeMethod<String>('resolveCallerName', {
        'phoneNumber': phoneNumber,
      });
      return name;
    } catch (e) {
      print('NotificationService: Error resolving caller name: $e');
      return null;
    }
  }
 
  /// Format notification for display in UI
  String _formatNotificationForDisplay(NotifyModel notify, [Map<String, dynamic>? rawData]) {
    // Special formatting for incoming calls
    if (_isCallNotification(notify, rawData)) {
      final buffer = StringBuffer();
      buffer.writeln('Incoming Call');
      if (notify.message.isNotEmpty) {
        buffer.writeln('');
        buffer.writeln(notify.message);
      }
      if (notify.subTitle.isNotEmpty && notify.subTitle != notify.message) {
        buffer.writeln(notify.subTitle);
      }
      return buffer.toString().trim();
    }
    
    // Standard notification formatting
    final buffer = StringBuffer();
    buffer.writeln('📱 Notification from ${notify.displayName}');
    buffer.writeln('');
    if (notify.title.isNotEmpty) {
      buffer.writeln(notify.title);
    }
    if (notify.subTitle.isNotEmpty) {
      buffer.writeln(notify.subTitle);
    }
    if (notify.message.isNotEmpty) {
      buffer.writeln(notify.message);
    }
    if (notify.title.isEmpty && notify.subTitle.isEmpty && notify.message.isEmpty) {
      buffer.writeln('(No content)');
    }
    return buffer.toString().trim();
  }

  String _firstNonEmpty(List<String?> values) {
    for (final value in values) {
      if (value != null && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return '';
  }

  /// Generate a deduplication key for a call notification based on phone number or contact name
  String _getCallDeduplicationKey(NotifyModel notify, Map<String, dynamic>? rawData) {
    // First, try to extract phone number (most reliable identifier)
    final phoneNumber = _extractPhoneNumber(notify);
    if (phoneNumber != null && phoneNumber.isNotEmpty) {
      // Normalize phone number: remove all non-digits except +
      final normalizedPhone = phoneNumber.replaceAll(RegExp(r'[^0-9+]'), '');
      if (normalizedPhone.length >= 7) {
        return 'call_phone_${normalizedPhone}';
      }
    }
    
    // If no phone number, use contact name (normalized)
    String contactName = '';
    if (notify.message.isNotEmpty && !_isGenericCallLabel(notify.message)) {
      contactName = notify.message.trim();
    } else if (notify.displayName.isNotEmpty && !_isGenericCallLabel(notify.displayName)) {
      contactName = notify.displayName.trim();
    } else if (notify.subTitle.isNotEmpty && !_isGenericCallLabel(notify.subTitle)) {
      contactName = notify.subTitle.trim();
    }
    
    // Normalize contact name: lowercase, remove extra spaces, remove special chars for comparison
    if (contactName.isNotEmpty) {
      final normalizedName = contactName
          .toLowerCase()
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      return 'call_name_${normalizedName}';
    }
    
    // Fallback: use timestamp + app identifier if we can't identify the caller
    return 'call_unknown_${notify.timestamp}_${notify.appIdentifier}';
  }
  
  /// Clean up old call notification entries
  void _cleanupOldCallNotifications(int currentTime) {
    final keysToRemove = <String>[];
    for (final entry in _recentCallNotifications.entries) {
      if ((currentTime - entry.value) > _callDeduplicationWindowSeconds) {
        keysToRemove.add(entry.key);
      }
    }
    for (final key in keysToRemove) {
      _recentCallNotifications.remove(key);
    }
    if (keysToRemove.isNotEmpty) {
      print('NotificationService: Cleaned up ${keysToRemove.length} old call notification entries');
    }
  }

  /// Dispose resources
  void dispose() {
    stopListening();
  }

  /// Get current notification access status
  bool get isNotificationAccessEnabled => _isNotificationAccessEnabled;
  
  /// Check if currently listening
  bool get isListening => _isListening;
  
  /// Get current whitelist
  Set<String> get whitelistedApps => Set.from(_whitelistedApps);

  Future<void> handleDeviceWhitelistAdd(String appIdentifier, String displayName) async {
    print('NotificationService: Device requested whitelist add for $appIdentifier ($displayName)');
    addWhitelistedApp(appIdentifier, displayName: displayName);
  }

  Future<void> syncWhitelistToGlasses() async {
    await _sendWhitelistToGlasses();
  }

  Future<void> _persistWhitelist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_whitelistedApps.isEmpty) {
        await prefs.remove(_whitelistPrefsKey);
        await prefs.remove(_whitelistNamesPrefsKey);
      } else {
        await prefs.setString(_whitelistPrefsKey, _whitelistedApps.join(','));
        final namesMap = <String, String>{};
        for (final id in _whitelistedApps) {
          namesMap[id] = _whitelistedAppNames[id] ?? id;
        }
        await prefs.setString(_whitelistNamesPrefsKey, jsonEncode(namesMap));
      }
    } catch (e) {
      print('Error saving whitelist to storage: $e');
    }
  }

  Future<void> _sendWhitelistToGlasses() async {
    if (!BleManager.get().isConnected) {
      return;
    }

    try {
      final apps = _whitelistedApps.map((id) => {
            'id': id,
            'name': _whitelistedAppNames[id] ?? id,
          }).toList();

      final payload = {
        'calendar_enable': false,
        'call_enable': true,
        'msg_enable': true,
        'ios_mail_enable': false,
        'app': {
          'list': apps,
          'enable': apps.isNotEmpty,
        },
      };

      final whitelistJson = jsonEncode(payload);
      await Proto.sendNewAppWhiteListJson(whitelistJson);
      print('NotificationService: Synced whitelist to glasses (${apps.length} apps, call_enable=true)');
    } catch (e) {
      print('NotificationService: Error sending whitelist to glasses: $e');
    }
  }

  /// Load whitelist from shared preferences
  Future<void> _loadWhitelistFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final whitelistString = prefs.getString(_whitelistPrefsKey) ?? '';
      
      if (whitelistString.isEmpty) {
        _whitelistedApps = {};
      } else {
        _whitelistedApps = whitelistString
            .split(',')
            .map((id) => id.trim())
            .where((id) => id.isNotEmpty)
            .toSet();
      }

      _whitelistedAppNames.clear();
      final namesJson = prefs.getString(_whitelistNamesPrefsKey);
      if (namesJson != null && namesJson.isNotEmpty) {
        try {
          final Map<String, dynamic> namesMap = jsonDecode(namesJson);
          namesMap.forEach((key, value) {
            if (key is String && value is String) {
              _whitelistedAppNames[key] = value;
            }
          });
        } catch (e) {
          print('Error decoding whitelist names: $e');
        }
      }

      for (final id in _whitelistedApps) {
        _whitelistedAppNames.putIfAbsent(id, () => id);
      }
    } catch (e) {
      print('Error loading whitelist from storage: $e');
      _whitelistedApps = {};
      _whitelistedAppNames.clear();
    }
  }
}

