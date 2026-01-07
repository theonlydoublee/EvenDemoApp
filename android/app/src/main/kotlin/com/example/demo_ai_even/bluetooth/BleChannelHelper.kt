package com.example.demo_ai_even.bluetooth

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import com.example.demo_ai_even.MainActivity
import com.example.demo_ai_even.model.BlePairDevice
import com.example.demo_ai_even.speech.SpeechRecognitionManager
import com.example.demo_ai_even.call.CallStateListener
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.EventChannel.EventSink
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

object BleChannelHelper {
    private const val TAG = "BleChannelHelper"

    /// METHOD TAG
    private const val METHOD_CHANNEL_BLE_TAG = "method.bluetooth"

    /// EVENT TAG
    private const val EVENT_BLE_STATUS = "eventBleStatus"
    private const val EVENT_BLE_RECEIVE = "eventBleReceive"
    private const val EVENT_BLE_SPEECH_RECOGNIZE = "eventSpeechRecognize"
    private const val EVENT_NOTIFICATION_RECEIVED = "eventNotificationReceived"
    private const val EVENT_NOTIFICATION_LISTENER_STATUS = "eventNotificationListenerStatus"

    /// Save EventSink
    private val eventSinks: MutableMap<String, EventSink> = mutableMapOf()
    ///
    private lateinit var bleMethodChannel: BleMethodChannel
    val bleMC: BleMethodChannel
        get() = bleMethodChannel


    //*================ Method - Public ================*//

    /**
     *
     */
    fun initChannel(context: MainActivity, flutterEngine: FlutterEngine) {
        val binaryMessenger = flutterEngine.dartExecutor.binaryMessenger
        //  Method
        bleMethodChannel = BleMethodChannel(MethodChannel(binaryMessenger, METHOD_CHANNEL_BLE_TAG), context)
        //  Event - Create StreamHandler with channel name identifier
        EventChannel(binaryMessenger, EVENT_BLE_STATUS).setStreamHandler(ChannelStreamHandler(EVENT_BLE_STATUS))
        EventChannel(binaryMessenger, EVENT_BLE_RECEIVE).setStreamHandler(ChannelStreamHandler(EVENT_BLE_RECEIVE))
        EventChannel(binaryMessenger, EVENT_BLE_SPEECH_RECOGNIZE).setStreamHandler(ChannelStreamHandler(EVENT_BLE_SPEECH_RECOGNIZE))
        EventChannel(binaryMessenger, EVENT_NOTIFICATION_RECEIVED).setStreamHandler(ChannelStreamHandler(EVENT_NOTIFICATION_RECEIVED))
        EventChannel(binaryMessenger, EVENT_NOTIFICATION_LISTENER_STATUS).setStreamHandler(ChannelStreamHandler(EVENT_NOTIFICATION_LISTENER_STATUS))
    }

    /**
     *
     */
    fun addEventSink(eventTag: String?, eventSink: EventSink?) {
        if (eventTag == null || eventSink == null) {
            return
        }
        eventSinks[eventTag] = eventSink
    }

    /**
     *
     */
    fun removeEventSink(eventTag: String?) {
        eventTag?.let {
            eventSinks.remove(it)
        }
    }

    //*================ Method - Event Channel ================*//

    fun bleStatus(data: Any) = eventSinks[EVENT_BLE_STATUS]?.success(data)

    fun bleReceive(data: Any) = eventSinks[EVENT_BLE_RECEIVE]?.success(data)

    fun bleSpeechRecognize(data: Any) {
        val eventSink = eventSinks[EVENT_BLE_SPEECH_RECOGNIZE]
        if (eventSink != null) {
            try {
                eventSink.success(data)
                Log.d(TAG, "Sent speech recognition event to Flutter: $data")
            } catch (e: Exception) {
                Log.e(TAG, "Error sending speech recognition event: ${e.message}", e)
            }
        } else {
            Log.e(TAG, "Event sink for $EVENT_BLE_SPEECH_RECOGNIZE is null - Flutter listener may not be set up")
        }
    }
    
    fun bleNotificationReceived(data: Any) = eventSinks[EVENT_NOTIFICATION_RECEIVED]?.success(data)
    
    fun bleNotificationListenerStatus(enabled: Boolean) = eventSinks[EVENT_NOTIFICATION_LISTENER_STATUS]?.success(enabled)

    /**
     * StreamHandler that identifies itself by channel name
     */
    private class ChannelStreamHandler(private val channelName: String) : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
            Log.d("BleChannelHelper", "EventChannel $channelName - OnListen: events = $events")
            addEventSink(channelName, events)
        }

        override fun onCancel(arguments: Any?) {
            Log.d("BleChannelHelper", "EventChannel $channelName - OnCancel")
            removeEventSink(channelName)
        }
    }

}

///
class BleMethodChannel(
   private val methodChannel: MethodChannel,
   private val context: MainActivity
) {
    private val TAG = "BleMethodChannel"

    init {
        methodChannel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "startScan" -> startScan(call, result)
                    "stopScan" -> stopScan(call, result)
                    "connectToGlasses" -> connectToGlasses(call, result)
                    "disconnectFromGlasses" -> disconnectFromGlasses(call, result)
                    "send" -> send(call, result)
                    "startEvenAI" -> startEvenAI(call, result)
                    "stopEvenAI" -> stopEvenAI(call, result)
                    "checkNotificationPermission" -> checkNotificationPermission(call, result)
                    "openNotificationSettings" -> openNotificationSettings(call, result)
                    "getInstalledApps" -> getInstalledApps(call, result)
                    "startForegroundService" -> startForegroundService(call, result)
                    "stopForegroundService" -> stopForegroundService(call, result)
                    "checkBleConnectionStatus" -> checkBleConnectionStatus(call, result)
                    "requestNotificationPermission" -> requestNotificationPermission(call, result)
                    "requestBatteryOptimization" -> requestBatteryOptimization(call, result)
                    "checkBatteryOptimization" -> checkBatteryOptimization(call, result)
                    "showWeatherNotification" -> showWeatherNotification(call, result)
                    "resolveCallerName" -> resolveCallerName(call, result)
                    "setGoogleCloudCredentials" -> setGoogleCloudCredentials(call, result)
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error handling method call ${call.method}: ${e.message}", e)
                result.error("EXCEPTION", "Error calling ${call.method}: ${e.message}", null)
            }
        }
    }

    //* =================== Native Call Flutter =================== *//

    fun startScan(call: MethodCall, result: MethodChannel.Result) = BleManager.instance.startScan(result)

    fun stopScan(call: MethodCall, result: MethodChannel.Result) = BleManager.instance.stopScan(result)

    fun connectToGlasses(call: MethodCall, result: MethodChannel.Result) {
        val deviceChannel: String = (call.arguments as? Map<*, *>)?.get("deviceName") as? String ?: ""
        if (deviceChannel.isEmpty()) {
            result.error("InvalidArguments", "Invalid arguments", null)
            return
        }
        BleManager.instance.connectToGlass(deviceChannel.replace("Pair_", ""), result)
    }

    fun disconnectFromGlasses(call: MethodCall, result: MethodChannel.Result) = BleManager.instance.disconnectFromGlasses(result)

    fun send(call: MethodCall, result: MethodChannel.Result) {
        BleManager.instance.senData(call.arguments as? Map<*, *>)
        result.success(null)
    }

    fun startEvenAI(call: MethodCall, result: MethodChannel.Result) {
        // Start speech recognition with default language (EN)
        // This will use Google Cloud Speech-to-Text if credentials are available,
        // otherwise falls back to Android SpeechRecognizer (phone mic)
        SpeechRecognitionManager.instance.startRecognition("EN")
        result.success(null)
    }

    fun stopEvenAI(call: MethodCall, result: MethodChannel.Result) {
        // Stop speech recognition (works for both Google Cloud and Android SpeechRecognizer)
        SpeechRecognitionManager.instance.stopRecognition()
        result.success(null)
    }

    //* =================== Flutter Call Native =================== *//

    fun flutterFoundPairedGlasses(device: BlePairDevice) = methodChannel.invokeMethod("foundPairedGlasses", device.toInfoJson())

    fun flutterGlassesConnected(deviceInfo: Map<String, Any>) = methodChannel.invokeMethod("glassesConnected", deviceInfo)

    fun flutterGlassesConnecting(deviceInfo: Map<String, Any>) = methodChannel.invokeMethod("glassesConnecting", deviceInfo)

    fun flutterGlassesDisconnected(deviceInfo: Map<String, Any>) = methodChannel.invokeMethod("glassesDisconnected", deviceInfo)

    fun flutterGlassesConnectionFailed(status: Int) = methodChannel.invokeMethod("glassesConnectionFailed", status)

    fun checkNotificationPermission(call: MethodCall, result: MethodChannel.Result) {
        val service = com.example.demo_ai_even.notification.AppNotificationListenerService.instance
        val isEnabled = if (service != null) {
            service.isNotificationAccessEnabled()
        } else {
            // Check permission even if service isn't running
            val componentName = android.content.ComponentName(
                context,
                com.example.demo_ai_even.notification.AppNotificationListenerService::class.java
            )
            val componentNameFlat = componentName.flattenToString()
            val flat = android.provider.Settings.Secure.getString(
                context.contentResolver,
                "enabled_notification_listeners"
            )
            if (flat != null && !flat.isEmpty()) {
                val names = flat.split(":")
                names.any { it.contains(componentNameFlat) }
            } else {
                false
            }
        }
        result.success(isEnabled)
    }

    fun openNotificationSettings(call: MethodCall, result: MethodChannel.Result) {
        val service = com.example.demo_ai_even.notification.AppNotificationListenerService.instance
        if (service != null) {
            service.openNotificationAccessSettings()
        } else {
            // If service is not available, open settings directly
            val intent = android.content.Intent("android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS")
            intent.flags = android.content.Intent.FLAG_ACTIVITY_NEW_TASK
            context.startActivity(intent)
        }
        result.success(null)
    }

    fun getInstalledApps(call: MethodCall, result: MethodChannel.Result) {
        try {
            val pm = context.packageManager
            
            // Determine the appropriate flags based on Android version
            val flags = when {
                android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU -> {
                    // Android 13+ - use MATCH_ALL or MATCH_KNOWN_PACKAGES
                    // MATCH_ALL requires QUERY_ALL_PACKAGES permission
                    android.content.pm.PackageManager.MATCH_ALL or
                    android.content.pm.PackageManager.GET_META_DATA
                }
                android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.N -> {
                    // Android 7.0+ - use MATCH_UNINSTALLED_PACKAGES to get all apps
                    android.content.pm.PackageManager.MATCH_UNINSTALLED_PACKAGES or
                    android.content.pm.PackageManager.GET_META_DATA
                }
                else -> {
                    // Older Android versions
                    android.content.pm.PackageManager.GET_META_DATA
                }
            }
            
            val packages = pm.getInstalledPackages(flags)
            val appList = mutableListOf<Map<String, String>>()
            
            Log.d(TAG, "Querying installed apps with flags: $flags (Android ${android.os.Build.VERSION.SDK_INT})")
            
            for (packageInfo in packages) {
                val appInfo = packageInfo.applicationInfo
                
                if (appInfo == null) {
                    continue
                }
                
                try {
                    val packageName = packageInfo.packageName
                    
                    // Skip the app itself
                    if (packageName == context.packageName) {
                        continue
                    }
                    
                    // Try to get app label
                    val appName = try {
                        pm.getApplicationLabel(appInfo).toString()
                    } catch (e: Exception) {
                        // Fallback to package name if label can't be retrieved
                        packageName
                    }
                    
                    // Skip if app name or package name is invalid
                    if (appName.isBlank() || packageName.isBlank()) {
                        continue
                    }
                    
                    appList.add(mapOf(
                        "packageName" to packageName,
                        "appName" to appName
                    ))
                } catch (e: Exception) {
                    // Skip apps that can't be read (permissions, uninstalled, etc.)
                    Log.w(TAG, "Skipping app ${packageInfo.packageName}: ${e.message}")
                    continue
                }
            }
            
            // Sort by app name (case-insensitive)
            appList.sortBy { it["appName"]?.lowercase() ?: "" }
            
            Log.d(TAG, "Found ${appList.size} installed apps")
            result.success(appList)
        } catch (e: Exception) {
            Log.e(TAG, "Error getting installed apps: ${e.message}", e)
            result.error("ERROR", "Failed to get installed apps: ${e.message}", null)
        }
    }

    fun startForegroundService(call: MethodCall, result: MethodChannel.Result) {
        try {
            com.example.demo_ai_even.notification.NotificationForwardingService.startService(context)
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "Error starting foreground service", e)
            result.error("EXCEPTION", "Error starting foreground service: ${e.message}", null)
        }
    }

    fun stopForegroundService(call: MethodCall, result: MethodChannel.Result) {
        try {
            com.example.demo_ai_even.notification.NotificationForwardingService.stopService(context)
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping foreground service", e)
            result.error("EXCEPTION", "Error stopping foreground service: ${e.message}", null)
        }
    }

    fun checkBleConnectionStatus(call: MethodCall, result: MethodChannel.Result) {
        try {
            val isConnected = BleManager.instance.isBleConnected()
            result.success(isConnected)
        } catch (e: Exception) {
            Log.e(TAG, "Error checking BLE connection status", e)
            result.error("EXCEPTION", "Error checking BLE connection status: ${e.message}", null)
        }
    }

    fun requestNotificationPermission(call: MethodCall, result: MethodChannel.Result) {
        try {
            val granted = BlePermissionUtil.checkNotificationPermission(context)
            result.success(granted)
        } catch (e: Exception) {
            Log.e(TAG, "Error requesting notification permission", e)
            result.error("EXCEPTION", "Error requesting notification permission: ${e.message}", null)
        }
    }

    fun requestBatteryOptimization(call: MethodCall, result: MethodChannel.Result) {
        try {
            if (context is MainActivity) {
                (context as MainActivity).requestBatteryOptimization()
                result.success(true)
            } else {
                Log.w(TAG, "Context is not MainActivity, cannot request battery optimization")
                result.success(false)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error requesting battery optimization", e)
            result.error("EXCEPTION", "Error requesting battery optimization: ${e.message}", null)
        }
    }
    
    fun checkBatteryOptimization(call: MethodCall, result: MethodChannel.Result) {
        try {
            if (context is MainActivity) {
                val isDisabled = (context as MainActivity).isBatteryOptimizationDisabled()
                result.success(isDisabled)
            } else {
                Log.w(TAG, "Context is not MainActivity, cannot check battery optimization")
                result.success(false)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error checking battery optimization", e)
            result.error("EXCEPTION", "Error checking battery optimization: ${e.message}", null)
        }
    }

    fun showWeatherNotification(call: MethodCall, result: MethodChannel.Result) {
        try {
            val arguments = call.arguments as? Map<*, *>
            val message = arguments?.get("message") as? String ?: "Weather Updated"
            
            Log.d(TAG, "showWeatherNotification called with message: $message")
            
            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val channelId = "weather_updates_channel"
            val notificationId = 1001 // Unique ID for weather notifications
            
            // Create notification channel for Android O and above
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                try {
                    // Check if channel already exists
                    val existingChannel = notificationManager.getNotificationChannel(channelId)
                    if (existingChannel == null) {
                        Log.d(TAG, "Creating weather notification channel")
                        val channel = NotificationChannel(
                            channelId,
                            "Weather Updates",
                            NotificationManager.IMPORTANCE_HIGH // Use HIGH importance to ensure visibility
                        ).apply {
                            description = "Weather update notifications"
                            enableVibration(true)
                            enableLights(true)
                            setShowBadge(true)
                            setSound(null, null) // No sound, but still high importance
                        }
                        notificationManager.createNotificationChannel(channel)
                        Log.d(TAG, "Weather notification channel created")
                    } else {
                        Log.d(TAG, "Weather notification channel already exists")
                        // Update importance if needed
                        if (existingChannel.importance < NotificationManager.IMPORTANCE_HIGH) {
                            val updatedChannel = NotificationChannel(
                                channelId,
                                "Weather Updates",
                                NotificationManager.IMPORTANCE_HIGH
                            ).apply {
                                description = "Weather update notifications"
                                enableVibration(true)
                                enableLights(true)
                                setShowBadge(true)
                                setSound(null, null)
                            }
                            notificationManager.createNotificationChannel(updatedChannel)
                            Log.d(TAG, "Weather notification channel updated to HIGH importance")
                        }
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Error creating/checking notification channel", e)
                }
            }
            
            // Create intent to open app when notification is tapped
            val intent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
            }
            val pendingIntentFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
            val pendingIntent = PendingIntent.getActivity(
                context,
                0,
                intent,
                pendingIntentFlags
            )
            
            // Build notification with higher priority
            val notification = NotificationCompat.Builder(context, channelId)
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentTitle("Weather Updated")
                .setContentText(message)
                .setStyle(NotificationCompat.BigTextStyle().bigText(message))
                .setPriority(NotificationCompat.PRIORITY_HIGH) // High priority
                .setContentIntent(pendingIntent)
                .setAutoCancel(true)
                .setWhen(System.currentTimeMillis())
                .setShowWhen(true)
                .build()
            
            // Show notification
            try {
                notificationManager.notify(notificationId, notification)
                Log.d(TAG, "Weather notification shown successfully: $message (ID: $notificationId)")
                result.success(true)
            } catch (e: Exception) {
                Log.e(TAG, "Error displaying notification", e)
                result.error("NOTIFICATION_ERROR", "Failed to display notification: ${e.message}", null)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error showing weather notification", e)
            result.error("EXCEPTION", "Error showing weather notification: ${e.message}", null)
        }
    }

    private fun resolveCallerName(call: MethodCall, result: MethodChannel.Result) {
        try {
            val arguments = call.arguments as? Map<*, *>
            val phoneNumber = arguments?.get("phoneNumber") as? String

            if (phoneNumber.isNullOrEmpty()) {
                result.error("INVALID_ARGS", "phoneNumber is required", null)
                return
            }

            val name = CallStateListener.getInstance(context).getCallerDisplayName(phoneNumber)
            result.success(name)
        } catch (e: Exception) {
            Log.e(TAG, "Error resolving caller name: ${e.message}", e)
            result.error("EXCEPTION", "Error resolving caller name: ${e.message}", null)
        }
    }

    private fun setGoogleCloudCredentials(call: MethodCall, result: MethodChannel.Result) {
        try {
            val arguments = call.arguments as? Map<*, *>
            val credentialsJson = arguments?.get("credentialsJson") as? String

            if (credentialsJson.isNullOrEmpty()) {
                Log.d(TAG, "No Google Cloud credentials provided - will use file from assets if available")
                result.success(false)
                return
            }

            // Initialize Google Cloud Speech Service with credentials from Flutter
            com.example.demo_ai_even.speech.GoogleCloudSpeechService.instance.initialize(context, credentialsJson)
            Log.d(TAG, "Google Cloud credentials set from Flutter environment")
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "Error setting Google Cloud credentials: ${e.message}", e)
            result.error("EXCEPTION", "Error setting Google Cloud credentials: ${e.message}", null)
        }
    }
}