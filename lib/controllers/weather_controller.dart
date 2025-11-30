import 'dart:async';
import 'package:get/get.dart';
import 'package:demo_ai_even/services/weather_service.dart';
import 'package:demo_ai_even/services/proto.dart';
import 'package:demo_ai_even/ble_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/services.dart';

class WeatherController extends GetxController {
  final WeatherService _weatherService = WeatherService();
  static const MethodChannel _methodChannel = MethodChannel('method.bluetooth');

  // Observable state
  var isLoading = false.obs;
  var weatherData = Rxn<WeatherData>();
  var errorMessage = Rxn<String>();
  var lastUpdateTime = Rxn<DateTime>();
  var useFahrenheit = false.obs;
  var use12HourFormat = true.obs;
  var updateIntervalMinutes = 1.obs; // Default: 1 minute
  var isAutoUpdateEnabled = false.obs;
  var locationAccuracy = LocationAccuracyPreference.high.obs; // Default to high for sub-area precision
  
  Timer? _autoUpdateTimer;
  
  // Cache last known location to avoid repeated location requests in background
  double? _lastKnownLatitude;
  double? _lastKnownLongitude;
  DateTime? _lastLocationTimestamp;
  static const String _prefKeyUpdateInterval = 'weather_update_interval_minutes';
  static const String _prefKeyAutoUpdateEnabled = 'weather_auto_update_enabled';
  static const String _prefKeyUseFahrenheit = 'weather_use_fahrenheit';
  static const String _prefKeyUse12HourFormat = 'weather_use_12hour_format';
  static const String _prefKeyLastLatitude = 'weather_last_latitude';
  static const String _prefKeyLastLongitude = 'weather_last_longitude';
  static const String _prefKeyLastLocationTimestamp = 'weather_last_location_timestamp';
  static const String _prefKeyLocationAccuracy = 'weather_location_accuracy';

  @override
  void onInit() {
    super.onInit();
    // Load preferences asynchronously, then start auto-update if needed
    _loadPreferences().then((_) {
      // Apply location accuracy to weather service
      _weatherService.setLocationAccuracy(locationAccuracy.value);
      // Start auto-update if enabled after preferences are loaded
      if (isAutoUpdateEnabled.value) {
        startAutoUpdate();
      }
    });
  }

  @override
  void onClose() {
    stopAutoUpdate();
    super.onClose();
  }

  /// Load saved preferences
  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedInterval = prefs.getInt(_prefKeyUpdateInterval);
      final savedAutoUpdate = prefs.getBool(_prefKeyAutoUpdateEnabled);
      final savedFahrenheit = prefs.getBool(_prefKeyUseFahrenheit);
      final saved12Hour = prefs.getBool(_prefKeyUse12HourFormat);
      final savedAccuracy = prefs.getString(_prefKeyLocationAccuracy);
      
      if (savedInterval != null) {
        updateIntervalMinutes.value = savedInterval;
        print('Loaded update interval: $savedInterval minutes');
      }
      if (savedAutoUpdate != null) {
        isAutoUpdateEnabled.value = savedAutoUpdate;
        print('Loaded auto-update enabled: $savedAutoUpdate');
      }
      if (savedFahrenheit != null) {
        useFahrenheit.value = savedFahrenheit;
        print('Loaded use Fahrenheit: $savedFahrenheit');
      }
      if (saved12Hour != null) {
        use12HourFormat.value = saved12Hour;
        print('Loaded use 12-hour format: $saved12Hour');
      }
      if (savedAccuracy != null) {
        try {
          locationAccuracy.value = LocationAccuracyPreference.values.firstWhere(
            (e) => e.name == savedAccuracy,
            orElse: () => LocationAccuracyPreference.high,
          );
          print('Loaded location accuracy: ${locationAccuracy.value.name}');
        } catch (e) {
          print('Error loading location accuracy: $e, using default (high)');
          locationAccuracy.value = LocationAccuracyPreference.high;
        }
      }

      final cachedLat = prefs.getDouble(_prefKeyLastLatitude);
      final cachedLon = prefs.getDouble(_prefKeyLastLongitude);
      final cachedTimestamp = prefs.getString(_prefKeyLastLocationTimestamp);

      if (cachedLat != null && cachedLon != null) {
        _lastKnownLatitude = cachedLat;
        _lastKnownLongitude = cachedLon;
        _lastLocationTimestamp = cachedTimestamp != null ? DateTime.tryParse(cachedTimestamp) : null;

        final age = _lastLocationTimestamp != null
            ? DateTime.now().difference(_lastLocationTimestamp!)
            : null;
        print(
          'Loaded cached location: '
          '$_lastKnownLatitude,$_lastKnownLongitude'
          '${age != null ? ' (age: ${age.inMinutes} minutes)' : ''}',
        );
      }
    } catch (e) {
      print('Error loading weather preferences: $e');
    }
  }

  /// Save preferences
  Future<void> _savePreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Save all preferences
      await prefs.setInt(_prefKeyUpdateInterval, updateIntervalMinutes.value);
      await prefs.setBool(_prefKeyAutoUpdateEnabled, isAutoUpdateEnabled.value);
      await prefs.setBool(_prefKeyUseFahrenheit, useFahrenheit.value);
      await prefs.setBool(_prefKeyUse12HourFormat, use12HourFormat.value);
      await prefs.setString(_prefKeyLocationAccuracy, locationAccuracy.value.name);
      
      // Verify the save by reading back (optional, for debugging)
      final savedInterval = prefs.getInt(_prefKeyUpdateInterval);
      final savedAutoUpdate = prefs.getBool(_prefKeyAutoUpdateEnabled);
      final savedFahrenheit = prefs.getBool(_prefKeyUseFahrenheit);
      final saved12Hour = prefs.getBool(_prefKeyUse12HourFormat);
      
      print('Weather preferences saved: interval=$savedInterval, autoUpdate=$savedAutoUpdate, fahrenheit=$savedFahrenheit, 12hour=$saved12Hour');
      
      // Verify all values match what we tried to save
      if (savedInterval != updateIntervalMinutes.value ||
          savedAutoUpdate != isAutoUpdateEnabled.value ||
          savedFahrenheit != useFahrenheit.value ||
          saved12Hour != use12HourFormat.value) {
        print('WARNING: Saved preferences do not match current values!');
        print('  Expected: interval=${updateIntervalMinutes.value}, autoUpdate=$isAutoUpdateEnabled, fahrenheit=$useFahrenheit, 12hour=$use12HourFormat');
        print('  Actual: interval=$savedInterval, autoUpdate=$savedAutoUpdate, fahrenheit=$savedFahrenheit, 12hour=$saved12Hour');
      }
    } catch (e, stackTrace) {
      print('Error saving weather preferences: $e');
      print('Stack trace: $stackTrace');
      rethrow; // Re-throw so callers can handle if needed
    }
  }

  bool get _hasCachedLocation =>
      _lastKnownLatitude != null && _lastKnownLongitude != null;

  Duration? get _cachedLocationAge =>
      _lastLocationTimestamp != null ? DateTime.now().difference(_lastLocationTimestamp!) : null;

  Future<void> _saveLastKnownLocation(
    double latitude,
    double longitude, {
    DateTime? timestamp,
  }) async {
    _lastKnownLatitude = latitude;
    _lastKnownLongitude = longitude;
    _lastLocationTimestamp = timestamp ?? DateTime.now();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_prefKeyLastLatitude, latitude);
      await prefs.setDouble(_prefKeyLastLongitude, longitude);
      await prefs.setString(
        _prefKeyLastLocationTimestamp,
        _lastLocationTimestamp!.toIso8601String(),
      );
      print(
        'Saved cached location: '
        '$_lastKnownLatitude,$_lastKnownLongitude at $_lastLocationTimestamp',
      );
    } catch (e, stackTrace) {
      print('Error saving cached location: $e');
      print('Stack trace: $stackTrace');
    }
  }

  Future<Position?> _getSystemLastKnownPosition({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    try {
      final position = await Geolocator.getLastKnownPosition().timeout(
        timeout,
        onTimeout: () {
          print(
            'fetchAndSendWeather: getLastKnownPosition timed out after '
            '${timeout.inSeconds}s',
          );
          return null;
        },
      );

      if (position != null) {
        final age = position.timestamp != null
            ? DateTime.now().difference(position.timestamp!)
            : null;
        print(
          'fetchAndSendWeather: System last known position: '
          '${position.latitude},${position.longitude}'
          '${age != null ? ' (age: ${age.inMinutes} minutes)' : ''}',
        );
      } else {
        print('fetchAndSendWeather: System last known position is null');
      }

      return position;
    } catch (e) {
      print('fetchAndSendWeather: Error retrieving system last known position: $e');
      return null;
    }
  }

  /// Start foreground service to enable location updates in background
  Future<void> _startForegroundService() async {
    try {
      await _methodChannel.invokeMethod('startForegroundService');
      print('WeatherController: Foreground service started for location updates');
    } catch (e) {
      print('WeatherController: Error starting foreground service: $e');
    }
  }

  /// Show notification when location is updated in background
  Future<void> _showLocationUpdateNotification(String message, bool usedCached) async {
    try {
      await _methodChannel.invokeMethod('showWeatherNotification', {
        'message': message,
        'usedCached': usedCached,
      });
      print('WeatherController: Location update notification sent: $message (cached=$usedCached)');
    } catch (e) {
      print('WeatherController: Error showing location update notification: $e');
    }
  }

  /// Fetch weather for current location and send to glasses
  /// [silent]: If true, don't set error messages (for auto-updates)
  Future<void> fetchAndSendWeather({bool silent = false}) async {
    print('fetchAndSendWeather called: silent=$silent, isConnected=${BleManager.get().isConnected}');
    
    if (!BleManager.get().isConnected) {
      print('fetchAndSendWeather: Glasses not connected, returning');
      if (!silent) {
        errorMessage.value = 'Glasses are not connected. Please connect to glasses first.';
      }
      return;
    }

    isLoading.value = true;
    if (!silent) {
      errorMessage.value = null;
    }

    try {
      print('fetchAndSendWeather: Starting weather update process...');
      final isInBackground = BleManager.get().isAppInBackground();
      
      // Always start foreground service during weather updates to ensure location can be obtained
      // This is especially important in background, but also helps in foreground
      print('fetchAndSendWeather: Starting foreground service for location access (background=$isInBackground)');
      await _startForegroundService();
      // Give the service a moment to start
      await Future.delayed(const Duration(milliseconds: 500));

      WeatherData? weather;
      var locationUpdated = false;
      var usedCachedLocation = false; // Track if we used cached location

      // Always try to get fresh location first when updating weather
      // The foreground service ensures we can get location even in background
      // Give enough time for GPS to get a fix (up to 40 seconds total)
      print('fetchAndSendWeather: Requesting fresh current location (foreground service active)...');
      try {
        // Get fresh location - foreground service allows this even in background
        // Increased timeout to allow GPS time to get a fix in background
        weather = await _weatherService.fetchWeatherForCurrentLocation(
          useLastKnownLocation: false, // Always try fresh location first
        ).timeout(
          const Duration(seconds: 40), // Increased timeout to match weather service (35s) + buffer
          onTimeout: () {
            print('fetchAndSendWeather: Fresh location request timed out after 40s, trying last known');
            throw TimeoutException('Location request timed out');
          },
        );
        await _saveLastKnownLocation(weather.latitude, weather.longitude);
        locationUpdated = true;
        usedCachedLocation = false; // Successfully got fresh location
        print('fetchAndSendWeather: Successfully got fresh location: ${weather.latitude}, ${weather.longitude}');
      } on TimeoutException catch (timeoutError) {
        print('fetchAndSendWeather: Fresh location timed out: $timeoutError, trying last known position');
        // Fallback to last known position if fresh location times out
        try {
          weather = await _weatherService.fetchWeatherForCurrentLocation(
            useLastKnownLocation: true, // Fallback to last known
          ).timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              print('fetchAndSendWeather: Last known location request also timed out');
              throw TimeoutException('Location request timed out');
            },
          );
          await _saveLastKnownLocation(weather.latitude, weather.longitude);
          locationUpdated = true;
          usedCachedLocation = false; // Last known is still from system, not our cache
          print('fetchAndSendWeather: Using last known location: ${weather.latitude}, ${weather.longitude}');
        } catch (fallbackError) {
          print('fetchAndSendWeather: Failed to get location (fresh and fallback): $fallbackError');
          // Try cached coordinates as last resort
          if (_hasCachedLocation) {
            print('fetchAndSendWeather: Using cached coordinates as last resort');
            try {
              weather = await _weatherService
                  .fetchWeather(_lastKnownLatitude!, _lastKnownLongitude!)
                  .timeout(
                const Duration(seconds: 20),
                onTimeout: () {
                  print('fetchAndSendWeather: Weather fetch with cached coords timed out');
                  throw TimeoutException('Weather fetch timed out.');
                },
              );
              usedCachedLocation = true; // Used our cached coordinates
            } catch (cachedError) {
              print('fetchAndSendWeather: All location methods failed: $cachedError');
              if (!silent) {
                errorMessage.value = _formatErrorMessage(fallbackError);
              }
              return;
            }
          } else {
            print('fetchAndSendWeather: No cached location available, cannot update weather');
            if (!silent) {
              errorMessage.value = 'Cannot get location. Please ensure location services are enabled.';
            }
            return;
          }
        }
      } catch (locationError) {
        print('fetchAndSendWeather: Error getting location: $locationError');
        // Try cached coordinates as last resort
        if (_hasCachedLocation) {
          print('fetchAndSendWeather: Using cached coordinates due to error');
          try {
            weather = await _weatherService
                .fetchWeather(_lastKnownLatitude!, _lastKnownLongitude!)
                .timeout(
              const Duration(seconds: 20),
              onTimeout: () {
                print('fetchAndSendWeather: Weather fetch with cached coords timed out');
                throw TimeoutException('Weather fetch timed out.');
              },
            );
            usedCachedLocation = true; // Used our cached coordinates
          } catch (cachedError) {
            print('fetchAndSendWeather: Cached weather fetch also failed: $cachedError');
            if (!silent) {
              errorMessage.value = _formatErrorMessage(locationError);
            }
            return;
          }
        } else {
          if (!silent) {
            errorMessage.value = _formatErrorMessage(locationError);
          }
          return;
        }
      }

      if (weather == null) {
        print('fetchAndSendWeather: Weather data unavailable after location handling, aborting update');
        return;
      }

      final resolvedWeather = weather;

      if (locationUpdated) {
        print(
          'fetchAndSendWeather: Cached location updated to '
          '${resolvedWeather.latitude},${resolvedWeather.longitude}',
        );
      }

      print('fetchAndSendWeather: Weather data fetched: ${resolvedWeather.cityName}, ${resolvedWeather.temperature}°C, ${resolvedWeather.condition}');
      weatherData.value = resolvedWeather;
      lastUpdateTime.value = DateTime.now();

        // Weather update notifications disabled per user request
      // if (isInBackground && (locationUpdated || usedCachedLocation)) {
      //   final locationSource = usedCachedLocation 
      //       ? 'cached location' 
      //       : 'current location';
      //   final notificationMessage = 
      //       'Weather updated using $locationSource: ${resolvedWeather.cityName}, '
      //       '${resolvedWeather.temperature.round()}°C, ${resolvedWeather.condition}';
      //   await _showLocationUpdateNotification(notificationMessage, usedCachedLocation);
      // }

      // Convert temperature to integer (round to nearest)
      // IMPORTANT: Always send temperature in Celsius. The useFahrenheit flag only tells
      // the glasses how to DISPLAY the temperature, not what unit we're sending.
      int tempCelsius = resolvedWeather.temperature.round();

      // Validate temperature range (-128 to 127)
      if (tempCelsius < -128 || tempCelsius > 127) {
        if (!silent) {
          errorMessage.value = 'Temperature out of range: $tempCelsius°C. Must be between -128 and 127.';
        }
        isLoading.value = false;
        return;
      }

      // Send to glasses (temperature is always in Celsius, flag controls display)
      final success = await Proto.setTimeAndWeather(
        weatherIconId: resolvedWeather.weatherIconId,
        temperature: tempCelsius,
        useFahrenheit: useFahrenheit.value,
        use12HourFormat: use12HourFormat.value,
      );

      if (!success) {
        if (!silent) {
          errorMessage.value = 'Failed to send weather data to glasses. Please try again.';
        } else {
          print('Weather auto-update: Failed to send to glasses');
        }
      } else {
        if (!silent) {
          errorMessage.value = null;
        }
        print('Weather auto-update: Successfully updated weather at ${DateTime.now()}');
        // Notifications removed per user request
      }
    } catch (e, stackTrace) {
      if (!silent) {
        errorMessage.value = _formatErrorMessage(e);
      }
      print('Error fetching/sending weather: $e');
      print('Stack trace: $stackTrace');
    } finally {
      isLoading.value = false;
    }
  }

  /// Get current weather without sending to glasses
  Future<WeatherData?> getCurrentWeather() async {
    isLoading.value = true;
    errorMessage.value = null;

    try {
      final weather = await _weatherService.fetchWeatherForCurrentLocation();
      weatherData.value = weather;
      lastUpdateTime.value = DateTime.now();
      return weather;
    } catch (e) {
      errorMessage.value = _formatErrorMessage(e);
      print('Error fetching weather: $e');
      return null;
    } finally {
      isLoading.value = false;
    }
  }

  /// Send current weather data to glasses (without fetching new data)
  Future<bool> sendCurrentWeatherToGlasses() async {
    if (weatherData.value == null) {
      errorMessage.value = 'No weather data available. Please fetch weather first.';
      return false;
    }

    if (!BleManager.get().isConnected) {
      errorMessage.value = 'Glasses are not connected. Please connect to glasses first.';
      return false;
    }

    try {
      final weather = weatherData.value!;
      // IMPORTANT: Always send temperature in Celsius. The useFahrenheit flag only tells
      // the glasses how to DISPLAY the temperature, not what unit we're sending.
      int tempCelsius = weather.temperature.round();

      // Validate temperature range
      if (tempCelsius < -128 || tempCelsius > 127) {
        errorMessage.value = 'Temperature out of range: $tempCelsius°C. Must be between -128 and 127.';
        return false;
      }

      final success = await Proto.setTimeAndWeather(
        weatherIconId: weather.weatherIconId,
        temperature: tempCelsius,
        useFahrenheit: useFahrenheit.value,
        use12HourFormat: use12HourFormat.value,
      );

      if (!success) {
        errorMessage.value = 'Failed to send weather data to glasses.';
      } else {
        errorMessage.value = null;
      }

      return success;
    } catch (e) {
      errorMessage.value = 'Error sending weather: $e';
      print('Error sending weather: $e');
      return false;
    }
  }

  /// Format error message for user display
  String _formatErrorMessage(dynamic error) {
    final errorString = error.toString();
    
    if (errorString.contains('Location services are disabled')) {
      return 'Location services are disabled. Please enable location services in device settings.';
    } else if (errorString.contains('Location permissions')) {
      return 'Location permission denied. Please grant location permission in app settings.';
    } else if (errorString.contains('API key not configured')) {
      return 'Weather API key not configured. Please set your OpenWeatherMap API key in weather_service.dart';
    } else if (errorString.contains('Weather API')) {
      return 'Failed to fetch weather data. Please check your internet connection and API key.';
    } else if (errorString.contains('network') || errorString.contains('connection')) {
      return 'Network error. Please check your internet connection.';
    } else {
      return 'Error: ${errorString.replaceAll('Exception: ', '')}';
    }
  }

  /// Toggle temperature unit
  void toggleTemperatureUnit() {
    useFahrenheit.value = !useFahrenheit.value;
    _savePreferences().catchError((e) {
      print('Error saving temperature unit preference: $e');
    });
  }

  /// Toggle time format
  void toggleTimeFormat() {
    use12HourFormat.value = !use12HourFormat.value;
    _savePreferences().catchError((e) {
      print('Error saving time format preference: $e');
    });
  }

  /// Set location accuracy preference
  Future<void> setLocationAccuracy(LocationAccuracyPreference accuracy) async {
    locationAccuracy.value = accuracy;
    _weatherService.setLocationAccuracy(accuracy);
    try {
      await _savePreferences();
      print('Location accuracy set to: ${accuracy.name}');
    } catch (e) {
      print('Error saving location accuracy preference: $e');
    }
  }

  /// Set update interval in minutes
  Future<void> setUpdateInterval(int minutes) async {
    if (minutes < 1) {
      minutes = 1; // Minimum 1 minute
    }
    
    final oldInterval = updateIntervalMinutes.value;
    updateIntervalMinutes.value = minutes;
    
    try {
      await _savePreferences();
      print('Update interval changed from $oldInterval to $minutes minutes');
    } catch (e) {
      print('Error saving update interval preference: $e');
    }
    
    // Restart timer if auto-update is enabled and interval actually changed
    if (isAutoUpdateEnabled.value && oldInterval != minutes) {
      print('Restarting auto-update timer with new interval: $minutes minutes');
      final wasActive = isAutoUpdateActive();
      if (wasActive) {
        _autoUpdateTimer?.cancel();
        _autoUpdateTimer = null;
      }
      
      // Restart with new interval
      final duration = Duration(minutes: minutes);
      print('Starting periodic timer with interval: ${duration.inMinutes} minutes');
      
      // Immediately fetch once if timer was already running
      if (wasActive) {
        fetchAndSendWeather(silent: true);
      }
      
      // Set up periodic timer
      _autoUpdateTimer = Timer.periodic(duration, (timer) {
        print('Auto-update timer fired at ${DateTime.now()}');
        if (BleManager.get().isConnected) {
          fetchAndSendWeather(silent: true);
        } else {
          print('Weather auto-update: Skipping update - glasses not connected');
        }
      });
      
      print('Auto-update timer restarted successfully. Active: ${isAutoUpdateActive()}');
    }
  }

  /// Check if auto-update is currently active
  bool isAutoUpdateActive() {
    return _autoUpdateTimer != null && _autoUpdateTimer!.isActive;
  }

  /// Start automatic weather updates
  void startAutoUpdate() {
    // Cancel any existing timer first
    if (isAutoUpdateActive()) {
      print('Weather auto-update: Stopping existing timer before restarting');
      _autoUpdateTimer?.cancel();
      _autoUpdateTimer = null;
    }

    isAutoUpdateEnabled.value = true;
    _savePreferences().catchError((e) {
      print('Error saving auto-update enabled preference: $e');
    });

    final duration = Duration(minutes: updateIntervalMinutes.value);
    print('Weather auto-update: Starting with interval ${updateIntervalMinutes.value} minute(s) (${duration.inSeconds} seconds)');

    // Immediately fetch once
    fetchAndSendWeather(silent: true);

    // Then set up periodic timer
    _autoUpdateTimer = Timer.periodic(duration, (timer) async {
      print('Auto-update timer fired at ${DateTime.now()} (interval: ${updateIntervalMinutes.value} minutes)');
      print('Weather auto-update: Checking connection and background state...');
      print('Weather auto-update: isConnected=${BleManager.get().isConnected}, isBackground=${BleManager.get().isAppInBackground()}');
      
      if (BleManager.get().isConnected) {
        try {
          print('Weather auto-update: Starting fetchAndSendWeather...');
          await fetchAndSendWeather(silent: true);
          print('Weather auto-update: fetchAndSendWeather completed');
        } catch (e, stackTrace) {
          print('Weather auto-update: Error in fetchAndSendWeather: $e');
          print('Weather auto-update: Stack trace: $stackTrace');
        }
      } else {
        print('Weather auto-update: Skipping update - glasses not connected');
      }
    });
    
    print('Weather auto-update: Timer started successfully. Active: ${isAutoUpdateActive()}, Next update in ${duration.inMinutes} minutes');
  }

  /// Stop automatic weather updates
  void stopAutoUpdate() {
    _autoUpdateTimer?.cancel();
    _autoUpdateTimer = null;
    isAutoUpdateEnabled.value = false;
    _savePreferences().catchError((e) {
      print('Error saving auto-update disabled preference: $e');
    });
    print('Weather auto-update: Stopped');
  }

  /// Toggle auto-update on/off
  void toggleAutoUpdate() {
    if (isAutoUpdateEnabled.value) {
      stopAutoUpdate();
    } else {
      startAutoUpdate();
    }
  }

  /// Clear error message
  void clearError() {
    errorMessage.value = null;
  }

}

