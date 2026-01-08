import 'package:demo_ai_even/ble_manager.dart';
import 'package:demo_ai_even/controllers/evenai_model_controller.dart';
import 'package:demo_ai_even/controllers/pin_text_controller.dart';
import 'package:demo_ai_even/controllers/weather_controller.dart';
import 'package:demo_ai_even/services/notification_service.dart';
import 'package:demo_ai_even/services/pin_text_voice_service.dart';
import 'package:demo_ai_even/views/home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:get/get.dart';

const MethodChannel _methodChannel = MethodChannel('method.bluetooth');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Load environment variables from .env file
  await dotenv.load(fileName: ".env");
  
  BleManager.get();
  Get.put(EvenaiModelController());
  Get.put(PinTextController());
  Get.put(WeatherController());
  
  // Initialize Google Cloud credentials from .env
  await _initializeGoogleCloudCredentials();
  
  // Initialize notification service
  await _initializeNotificationService();
  
  // Start listening for Pin Text voice recordings
  PinTextVoiceService.instance.startListening();
  
  runApp(MyApp());
}

Future<void> _initializeGoogleCloudCredentials() async {
  try {
    final credentialsJson = dotenv.env['GOOGLE_CLOUD_CREDENTIALS_JSON'] ?? '';
    
    if (credentialsJson.isEmpty) {
      print('GoogleCloud: No credentials in .env, will use file from assets if available');
      return;
    }
    
    // Send credentials to native Android code
    final result = await _methodChannel.invokeMethod('setGoogleCloudCredentials', {
      'credentialsJson': credentialsJson,
    });
    
    if (result == true) {
      print('GoogleCloud: Credentials set from .env file');
    } else {
      print('GoogleCloud: Failed to set credentials, will use file from assets if available');
    }
  } catch (e) {
    print('GoogleCloud: Error initializing credentials: $e');
  }
}

Future<void> _initializeNotificationService() async {
  try {
    final notificationService = NotificationService.instance;
    
    // Check if notification access is enabled
    final hasPermission = await notificationService.checkNotificationPermission();
    
    if (hasPermission) {
      // Start listening for notifications
      await notificationService.startListening();
      print('NotificationService: Initialized and listening');
    } else {
      print('NotificationService: Permission not granted, will not start listening');
    }
  } catch (e) {
    print('Error initializing notification service: $e');
  }
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    final bleManager = BleManager.get();
    
    switch (state) {
      case AppLifecycleState.resumed:
        // App is in foreground
        bleManager.setAppInBackground(false);
        // Ensure weather auto-update is running if it was enabled
        try {
          final weatherController = Get.find<WeatherController>();
          if (weatherController.isAutoUpdateEnabled.value && 
              !weatherController.isAutoUpdateActive()) {
            weatherController.startAutoUpdate();
          }
        } catch (e) {
          // Controller might not be initialized yet
        }
        break;
      case AppLifecycleState.paused:
        // App is in background
        bleManager.setAppInBackground(true);
        // Weather auto-update timer will continue running in background
        break;
      case AppLifecycleState.inactive:
        // App is transitioning (e.g., phone call, notification drawer)
        // Don't change state here, wait for paused or resumed
        break;
      case AppLifecycleState.detached:
        // App is being terminated
        bleManager.setAppInBackground(true);
        break;
      case AppLifecycleState.hidden:
        // App is hidden (Android 14+)
        bleManager.setAppInBackground(true);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Even AI Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: HomePage(), 
    );
  }
}
