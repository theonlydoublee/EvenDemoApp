import 'dart:async';
import 'package:dio/dio.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

/// Location accuracy preference enum
enum LocationAccuracyPreference {
  low,      // LocationAccuracy.low - fastest, least accurate (~100m)
  medium,   // LocationAccuracy.medium - balanced (default, ~10-100m)
  high,     // LocationAccuracy.high - more accurate (~10m)
  best,     // LocationAccuracy.best - most accurate (~5m), uses more battery
}

class WeatherData {
  final String cityName;
  final double temperature;
  final int weatherIconId;
  final String condition;
  final double latitude;
  final double longitude;

  WeatherData({
    required this.cityName,
    required this.temperature,
    required this.weatherIconId,
    required this.condition,
    required this.latitude,
    required this.longitude,
  });
}

class WeatherService {
  late Dio _dio;
  
  // TODO: Replace with your OpenWeatherMap API key
  // Get a free API key from: https://openweathermap.org/api
  static const String _apiKey = 'API KEY HERE';
  static const String _baseUrl = 'https://api.openweathermap.org/data/3.0';

  // Location accuracy preference (default to high for better sub-area precision)
  LocationAccuracyPreference _locationAccuracy = LocationAccuracyPreference.high;

  WeatherService() {
    _dio = Dio(
      BaseOptions(
        baseUrl: _baseUrl,
        headers: {
          'Content-Type': 'application/json',
        },
      ),
    );
  }

  /// Set location accuracy preference
  void setLocationAccuracy(LocationAccuracyPreference accuracy) {
    _locationAccuracy = accuracy;
    print('WeatherService: Location accuracy set to ${accuracy.name}');
  }

  /// Get current location accuracy preference
  LocationAccuracyPreference get locationAccuracy => _locationAccuracy;

  /// Convert LocationAccuracyPreference to Geolocator LocationAccuracy
  LocationAccuracy _getLocationAccuracy() {
    switch (_locationAccuracy) {
      case LocationAccuracyPreference.low:
        return LocationAccuracy.low;
      case LocationAccuracyPreference.medium:
        return LocationAccuracy.medium;
      case LocationAccuracyPreference.high:
        return LocationAccuracy.high;
      case LocationAccuracyPreference.best:
        return LocationAccuracy.best;
    }
  }

  /// Get current location of the device
  /// [useLastKnown]: If true, use last known position if getting current position fails (useful in background)
  Future<Position> getCurrentLocation({bool useLastKnown = false}) async {
    try {
      bool serviceEnabled;
      LocationPermission permission;

      // Check if location services are enabled
      serviceEnabled = await Geolocator.isLocationServiceEnabled().timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          print('WeatherService: Location service check timed out');
          return false;
        },
      );
      
      if (!serviceEnabled) {
        if (useLastKnown) {
          print('WeatherService: Location services disabled, trying last known position');
          try {
            final lastKnown = await Geolocator.getLastKnownPosition();
            if (lastKnown != null) {
              return lastKnown;
            }
            throw Exception('Location services are disabled and no last known position available.');
          } catch (e) {
            throw Exception('Location services are disabled. Please enable location services.');
          }
        }
        throw Exception('Location services are disabled. Please enable location services.');
      }

      // Check location permissions
      permission = await Geolocator.checkPermission().timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          print('WeatherService: Permission check timed out');
          return LocationPermission.denied;
        },
      );
      
      if (permission == LocationPermission.denied) {
        print('WeatherService: Location permission denied, requesting permission...');
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (useLastKnown) {
            print('WeatherService: Location permission denied after request, trying last known position');
            try {
              final lastKnown = await Geolocator.getLastKnownPosition();
              if (lastKnown != null) {
                return lastKnown;
              }
              throw Exception('Location permissions are denied and no last known position available.');
            } catch (e) {
              throw Exception('Location permissions are denied.');
            }
          }
          throw Exception('Location permissions are denied.');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (useLastKnown) {
          print('WeatherService: Location permission denied forever, trying last known position');
          try {
            final lastKnown = await Geolocator.getLastKnownPosition();
            if (lastKnown != null) {
              return lastKnown;
            }
            throw Exception('Location permissions are permanently denied and no last known position available.');
          } catch (e) {
            throw Exception('Location permissions are permanently denied. Please enable them in app settings.');
          }
        }
        throw Exception('Location permissions are permanently denied. Please enable them in app settings.');
      }
      
      // Check background location permission for Android 10+ (API 29+)
      // Note: This is a runtime check, the permission is declared in manifest
      if (permission == LocationPermission.whileInUse) {
        print('WeatherService: Only while-in-use permission granted. Background location may not work.');
        // Continue anyway - the system will handle it
      }

      // Get current position with timeout
      // Force fresh location by checking timestamp and retrying if stale
      final accuracy = _getLocationAccuracy();
      print('WeatherService: Requesting current position with accuracy: ${_locationAccuracy.name} (${accuracy.name})...');
      
      // Configure location settings for background location updates
      // This ensures the geolocator service can get location even in background
      final locationSettings = LocationSettings(
        accuracy: accuracy,
        distanceFilter: 0, // Get any location update, don't filter by distance
        timeLimit: const Duration(seconds: 30), // Time limit for getting location
      );
      
      // Request current position with location settings and increased timeout
      // This is especially important when foreground service is active in background
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: locationSettings,
        desiredAccuracy: accuracy,
        timeLimit: const Duration(seconds: 30), // Increased timeout for GPS fix in background
      ).timeout(
        const Duration(seconds: 35), // Overall 35 second timeout
        onTimeout: () {
          print('WeatherService: getCurrentPosition timed out, trying last known position');
          if (useLastKnown) {
            throw TimeoutException('Getting current position timed out');
          }
          throw Exception('Getting current location timed out. Please try again.');
        },
      );
      
      // Verify the position is fresh (not cached) - check if timestamp is recent (within last 60 seconds)
      final positionAge = DateTime.now().difference(position.timestamp ?? DateTime.now());
      print('WeatherService: Position timestamp age: ${positionAge.inSeconds}s');
      
      // If position is stale and we don't want last known, try to get a fresh one
      if (positionAge.inSeconds > 60 && !useLastKnown) {
        print('WeatherService: WARNING - Position is ${positionAge.inSeconds}s old (may be cached), retrying for fresh location...');
        try {
          // Retry to get a fresh location with location settings
          final retryLocationSettings = LocationSettings(
            accuracy: accuracy,
            distanceFilter: 0,
            timeLimit: const Duration(seconds: 20),
          );
          final freshPosition = await Geolocator.getCurrentPosition(
            locationSettings: retryLocationSettings,
            desiredAccuracy: accuracy,
            timeLimit: const Duration(seconds: 20),
          ).timeout(
            const Duration(seconds: 25),
            onTimeout: () {
              print('WeatherService: Retry for fresh location timed out');
              throw TimeoutException('Getting fresh location timed out');
            },
          );
          
          final freshAge = DateTime.now().difference(freshPosition.timestamp ?? DateTime.now());
          if (freshAge.inSeconds <= 60) {
            print('WeatherService: Got fresh position on retry: ${freshPosition.latitude}, ${freshPosition.longitude} (${freshAge.inSeconds}s old)');
            return freshPosition;
          } else {
            print('WeatherService: Retry also returned stale position (${freshAge.inSeconds}s old), using original');
            return position;
          }
        } catch (e) {
          print('WeatherService: Retry failed: $e, using original position');
          return position;
        }
      } else if (positionAge.inSeconds <= 60) {
        print('WeatherService: Position is fresh (${positionAge.inSeconds}s old): ${position.latitude}, ${position.longitude}');
      } else {
        print('WeatherService: Position is ${positionAge.inSeconds}s old but useLastKnown=true, using it');
      }
      
      return position;
    } on TimeoutException {
      if (useLastKnown) {
        print('WeatherService: Timeout getting current position, using last known position');
        try {
          final lastKnown = await Geolocator.getLastKnownPosition();
          if (lastKnown != null) {
            print('WeatherService: Using last known position: ${lastKnown.latitude}, ${lastKnown.longitude}');
            return lastKnown;
          }
        } catch (e) {
          print('WeatherService: Failed to get last known position: $e');
        }
      }
      rethrow;
    } catch (e) {
      print('WeatherService: Error getting location: $e');
      if (useLastKnown) {
        print('WeatherService: Trying last known position as fallback');
        try {
          final lastKnown = await Geolocator.getLastKnownPosition();
          if (lastKnown != null) {
            print('WeatherService: Using last known position as fallback: ${lastKnown.latitude}, ${lastKnown.longitude}');
            return lastKnown;
          }
        } catch (e2) {
          print('WeatherService: Failed to get last known position: $e2');
        }
      }
      rethrow;
    }
  }

  /// Get city name from coordinates using reverse geocoding
  Future<String> getCityNameFromLocation(double latitude, double longitude) async {
    try {
      print('WeatherService: Getting city name for $latitude, $longitude');
      List<Placemark> placemarks = await placemarkFromCoordinates(latitude, longitude).timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          print('WeatherService: Geocoding request timed out');
          return <Placemark>[];
        },
      );
      
      if (placemarks.isNotEmpty) {
        final place = placemarks[0];
        // Try to get city name, fallback to locality or administrative area
        final cityName = place.locality ?? 
               place.subAdministrativeArea ?? 
               place.administrativeArea ?? 
               'Unknown Location';
        print('WeatherService: Got city name: $cityName');
        return cityName;
      }
      print('WeatherService: No placemarks found, using Unknown Location');
      return 'Unknown Location';
    } catch (e) {
      print('WeatherService: Error getting city name: $e');
      return 'Unknown Location';
    }
  }

  /// Fetch weather data from OpenWeatherMap One Call API 3.0
  /// Documentation: https://openweathermap.org/api/one-call-3
  Future<WeatherData> fetchWeather(double latitude, double longitude) async {
    if (_apiKey == 'YOUR_OPENWEATHERMAP_API_KEY_HERE') {
      throw Exception('OpenWeatherMap API key not configured. Please set your API key in weather_service.dart');
    }

    try {
      print('WeatherService: Starting API request to /onecall for lat=$latitude, lon=$longitude');
      
      // Use One Call API 3.0 endpoint with timeout
      // Exclude minutely, hourly, daily, and alerts to get only current weather
      final response = await _dio.get(
        '/onecall',
        queryParameters: {
          'lat': latitude,
          'lon': longitude,
          'appid': _apiKey,
          'units': 'metric', // Use Celsius
          'exclude': 'minutely,hourly,daily,alerts', // Only get current weather
        },
        options: Options(
          receiveTimeout: const Duration(seconds: 15),
          sendTimeout: const Duration(seconds: 10),
        ),
      ).timeout(
        const Duration(seconds: 20),
        onTimeout: () {
          print('WeatherService: API request timed out after 20 seconds');
          throw TimeoutException('Weather API request timed out');
        },
      );
      
      print('WeatherService: API request completed with status ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = response.data;
        
        // Parse current weather data from One Call API 3.0 response
        final current = data['current'];
        if (current == null) {
          throw Exception('Invalid API response: missing current weather data');
        }

        final temp = (current['temp'] as num?)?.toDouble() ?? 0.0;
        final weatherArray = current['weather'] as List?;
        
        if (weatherArray == null || weatherArray.isEmpty) {
          throw Exception('Invalid API response: missing weather condition');
        }

        final weatherMain = weatherArray[0]?['main'] as String? ?? 'Unknown';
        final weatherId = weatherArray[0]?['id'] as int? ?? 0;
        
        // One Call API 3.0 doesn't return city name, so get it via geocoding
        // Use timeout to prevent hanging
        String cityName;
        try {
          cityName = await getCityNameFromLocation(latitude, longitude).timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              print('WeatherService: Geocoding timed out, using default city name');
              return 'Unknown Location';
            },
          );
        } catch (e) {
          print('WeatherService: Geocoding failed: $e, using default city name');
          cityName = 'Unknown Location';
        }
        
        // Determine if it's night time (for icon selection)
        final now = DateTime.now();
        final sunrise = current['sunrise'] != null 
            ? DateTime.fromMillisecondsSinceEpoch((current['sunrise'] as int) * 1000)
            : null;
        final sunset = current['sunset'] != null
            ? DateTime.fromMillisecondsSinceEpoch((current['sunset'] as int) * 1000)
            : null;
        
        bool isNight = false;
        if (sunrise != null && sunset != null) {
          isNight = now.isBefore(sunrise) || now.isAfter(sunset);
        } else {
          // Fallback: assume night if current hour is between 6 PM and 6 AM
          isNight = now.hour >= 18 || now.hour < 6;
        }

        final iconId = mapWeatherConditionToIconId(weatherMain, weatherId, isNight);
        
        return WeatherData(
          cityName: cityName,
          temperature: temp,
          weatherIconId: iconId,
          condition: weatherMain,
          latitude: latitude,
          longitude: longitude,
        );
      } else {
        throw Exception('Weather API returned status code: ${response.statusCode}');
      }
    } on DioException catch (e) {
      if (e.response != null) {
        final statusCode = e.response?.statusCode;
        final errorData = e.response?.data;
        
        // Parse error message from One Call API 3.0 error response
        String errorMessage = 'Weather API error: $statusCode';
        if (errorData is Map && errorData['message'] != null) {
          errorMessage = 'Weather API error: ${errorData['message']}';
        } else if (errorData != null) {
          errorMessage = 'Weather API error: $statusCode, $errorData';
        }
        
        throw Exception(errorMessage);
      } else {
        throw Exception('Weather API error: ${e.message ?? "Unknown error"}');
      }
    } catch (e) {
      throw Exception('Error fetching weather: $e');
    }
  }

  /// Map weather condition from API to protocol icon ID
  /// Based on OpenWeatherMap weather codes and protocol icon IDs (0x00-0x10)
  int mapWeatherConditionToIconId(String condition, int weatherCode, bool isNight) {
    // OpenWeatherMap weather code ranges:
    // 200-232: Thunderstorm
    // 300-321: Drizzle
    // 500-531: Rain
    // 600-622: Snow
    // 701-781: Atmosphere (Mist, Fog, etc.)
    // 800: Clear
    // 801-804: Clouds

    // Thunderstorms
    if (weatherCode >= 200 && weatherCode < 230) {
      return 0x07; // Thunder
    } else if (weatherCode >= 230 && weatherCode <= 232) {
      return 0x08; // Thunder Storm
    }
    // Drizzle
    else if (weatherCode >= 300 && weatherCode < 310) {
      return 0x03; // Drizzle
    } else if (weatherCode >= 310 && weatherCode <= 321) {
      return 0x04; // Heavy Drizzle
    }
    // Rain
    else if (weatherCode >= 500 && weatherCode < 520) {
      return 0x05; // Rain
    } else if (weatherCode >= 520 && weatherCode <= 531) {
      return 0x06; // Heavy Rain
    }
    // Freezing/Sleet conditions (check before snow, as these codes are in 600-622 range)
    else if (weatherCode == 611 || weatherCode == 612 || weatherCode == 613) {
      return 0x0F; // Freezing (Sleet)
    }
    // Snow
    else if (weatherCode >= 600 && weatherCode <= 622) {
      return 0x09; // Snow
    }
    // Atmosphere conditions
    else if (weatherCode == 701) {
      return 0x0A; // Mist
    } else if (weatherCode == 711) {
      return 0x0C; // Sand (Smoke)
    } else if (weatherCode == 721) {
      return 0x0A; // Haze (similar to Mist)
    } else if (weatherCode == 731 || weatherCode == 761) {
      return 0x0C; // Sand/Dust
    } else if (weatherCode == 741) {
      return 0x0B; // Fog
    } else if (weatherCode == 751 || weatherCode == 762) {
      return 0x0C; // Sand
    } else if (weatherCode == 771) {
      return 0x0D; // Squalls
    } else if (weatherCode == 781) {
      return 0x0E; // Tornado
    }
    // Clear sky
    else if (weatherCode == 800) {
      return isNight ? 0x01 : 0x10; // Night or Sunny
    }
    // Clouds
    else if (weatherCode == 801) {
      return 0x02; // Clouds (few clouds)
    } else if (weatherCode == 802) {
      return 0x02; // Clouds (scattered clouds)
    } else if (weatherCode == 803 || weatherCode == 804) {
      return 0x02; // Clouds (broken/overcast clouds)
    }

    // Fallback based on condition string if weather code doesn't match
    switch (condition.toUpperCase()) {
      case 'THUNDERSTORM':
        return 0x08; // Thunder Storm
      case 'DRIZZLE':
        return 0x04; // Heavy Drizzle
      case 'RAIN':
        return 0x05; // Rain
      case 'SNOW':
        return 0x09; // Snow
      case 'MIST':
        return 0x0A; // Mist
      case 'FOG':
        return 0x0B; // Fog
      case 'CLEAR':
        return isNight ? 0x01 : 0x10; // Night or Sunny
      case 'CLOUDS':
      case 'CLOUDY':
        return 0x02; // Clouds
      default:
        return 0x00; // None
    }
  }

  /// Fetch weather for current location
  /// [useLastKnownLocation]: If true, try last known position first (for background updates)
  /// [cachedLatitude]: Optional cached latitude to use directly
  /// [cachedLongitude]: Optional cached longitude to use directly
  Future<WeatherData> fetchWeatherForCurrentLocation({
    bool useLastKnownLocation = true,
    double? cachedLatitude,
    double? cachedLongitude,
  }) async {
    try {
      print('WeatherService: fetchWeatherForCurrentLocation - useLastKnownLocation=$useLastKnownLocation, cached=$cachedLatitude,$cachedLongitude');
      
      Position position;
      
      // If cached coordinates provided, use them directly (fastest path for background updates)
      if (cachedLatitude != null && cachedLongitude != null) {
        print('WeatherService: Using provided cached coordinates: $cachedLatitude, $cachedLongitude');
        // Create a Position object from cached coordinates
        position = Position(
          latitude: cachedLatitude,
          longitude: cachedLongitude,
          timestamp: DateTime.now(),
          accuracy: 0,
          altitude: 0,
          heading: 0,
          speed: 0,
          speedAccuracy: 0,
          altitudeAccuracy: 0,
          headingAccuracy: 0,
        );
      } else if (useLastKnownLocation) {
        // Try last known position first (fast and works in background)
        // This is the preferred method for background updates
        print('WeatherService: Trying last known position first (background-safe method)...');
        Position? lastKnown;
        
        try {
          // Try to get last known position - this works even when app is in background
          lastKnown = await Geolocator.getLastKnownPosition().timeout(
            const Duration(seconds: 3),
            onTimeout: () {
              print('WeatherService: Getting last known position timed out after 3 seconds');
              return null;
            },
          );
        } catch (e) {
          print('WeatherService: Exception getting last known position: $e');
          lastKnown = null;
        }
        
        if (lastKnown != null) {
          final age = DateTime.now().difference(lastKnown.timestamp);
          print('WeatherService: Successfully got last known position: ${lastKnown.latitude}, ${lastKnown.longitude}');
          print('WeatherService: Last known position timestamp: ${lastKnown.timestamp} (${age.inMinutes} minutes ago)');
          print('WeatherService: Last known position accuracy: ${lastKnown.accuracy}m');
          
          // When foreground service is active, always try to get fresh location first
          // Only use last known if it's very recent (< 5 minutes) or if fresh location fails
          if (age.inMinutes < 5) {
            print('WeatherService: Last known position is very recent (${age.inMinutes} minutes old), but foreground service is active - trying fresh location first...');
            // Still try to get fresh location even if last known is recent
            try {
              position = await getCurrentLocation(useLastKnown: false).timeout(
                const Duration(seconds: 30), // Give time for GPS fix with foreground service
                onTimeout: () {
                  print('WeatherService: Getting fresh position timed out, using recent last known position');
                  throw TimeoutException('Getting current position timed out');
                },
              );
              print('WeatherService: Successfully got fresh current position: ${position.latitude}, ${position.longitude}');
            } on TimeoutException {
              // Timeout occurred, use recent last known position
              print('WeatherService: Using recent last known position due to timeout');
              position = lastKnown!; // Safe because we checked != null above
            } catch (e) {
              print('WeatherService: Failed to get current position: $e, using recent last known position');
              // Fall back to last known position
              position = lastKnown!; // Safe because we checked != null above
            }
          } else {
            print('WeatherService: Last known position is old (${age.inMinutes} minutes old), attempting to get fresh location...');
            // Try to get current position with longer timeout when foreground service is active
            try {
              position = await getCurrentLocation(useLastKnown: false).timeout(
                const Duration(seconds: 35), // Longer timeout for GPS fix with foreground service
                onTimeout: () {
                  print('WeatherService: Getting current position timed out, will use old last known position');
                  throw TimeoutException('Getting current position timed out');
                },
              );
              print('WeatherService: Successfully got fresh current position: ${position.latitude}, ${position.longitude}');
            } on TimeoutException {
              // Timeout occurred, use old last known position
              print('WeatherService: Using old last known position due to timeout');
              position = lastKnown!; // Safe because we checked != null above
            } catch (e) {
              print('WeatherService: Failed to get current position: $e, using last known position');
              // Fall back to last known position even if it's old
              position = lastKnown!; // Safe because we checked != null above
            }
          }
        } else {
          // No last known position available at all
          print('WeatherService: No last known position available in system');
          // Try to get current position with longer timeout when foreground service is active
          print('WeatherService: Attempting to get current position (foreground service should enable this in background)...');
          try {
            // Use longer timeout since foreground service is active
            position = await getCurrentLocation(useLastKnown: false).timeout(
              const Duration(seconds: 35), // Longer timeout to allow GPS fix with foreground service
              onTimeout: () {
                print('WeatherService: Getting current position timed out after 35s (foreground service may not be sufficient)');
                throw TimeoutException('Cannot get location in background. Please ensure location services are enabled and GPS has a fix.');
              },
            );
            print('WeatherService: Successfully got current position: ${position.latitude}, ${position.longitude}');
          } catch (e) {
            print('WeatherService: Failed to get any location: $e');
            // If we can't get any location, throw an error with helpful message
            throw Exception('Cannot get location data in background. Please ensure location services are enabled and GPS has a fix. Error: $e');
          }
        }
      } else {
        // Try to get current location first (user wants fresh location)
        // When foreground service is active, we should be able to get fresh location even in background
        print('WeatherService: Getting current location (fresh location requested, foreground service should be active)...');
        try {
          // Request fresh location with longer timeout to allow GPS to get a fix
          position = await getCurrentLocation(useLastKnown: false).timeout(
            const Duration(seconds: 25), // Increased timeout to allow GPS fix in background
            onTimeout: () {
              print('WeatherService: Getting current location timed out after 25 seconds');
              throw TimeoutException('Getting current location timed out');
            },
          );
          
          // Verify position is fresh (within last 60 seconds for background)
          final positionAge = DateTime.now().difference(position.timestamp ?? DateTime.now());
          if (positionAge.inSeconds > 60) {
            print('WeatherService: WARNING - Position is ${positionAge.inSeconds}s old, may be cached. Requesting again...');
            // Try one more time to get a fresh location
            try {
              final freshPosition = await getCurrentLocation(useLastKnown: false).timeout(
                const Duration(seconds: 15),
                onTimeout: () {
                  print('WeatherService: Second attempt to get fresh location timed out');
                  throw TimeoutException('Getting fresh location timed out');
                },
              );
              final freshAge = DateTime.now().difference(freshPosition.timestamp ?? DateTime.now());
              if (freshAge.inSeconds <= 60) {
                print('WeatherService: Got fresh position on second attempt: ${freshPosition.latitude}, ${freshPosition.longitude} (${freshAge.inSeconds}s old)');
                position = freshPosition;
              } else {
                print('WeatherService: Second attempt also returned stale position (${freshAge.inSeconds}s old), using it anyway');
                position = freshPosition;
              }
            } catch (e2) {
              print('WeatherService: Second attempt failed: $e2, using first position');
              // Use the first position even if it's stale
            }
          } else {
            print('WeatherService: Successfully got fresh current position: ${position.latitude}, ${position.longitude} (${positionAge.inSeconds}s old)');
          }
        } catch (e) {
          print('WeatherService: Failed to get current location: $e');
          // If getting current location fails, try last known position as fallback
          print('WeatherService: Trying last known position as fallback...');
          try {
            final lastKnown = await Geolocator.getLastKnownPosition().timeout(
              const Duration(seconds: 2),
              onTimeout: () {
                print('WeatherService: Getting last known position timed out');
                return null;
              },
            );
            
            if (lastKnown != null) {
              print('WeatherService: Using last known position as fallback: ${lastKnown.latitude}, ${lastKnown.longitude}');
              position = lastKnown;
            } else {
              print('WeatherService: No last known position available either');
              rethrow; // Re-throw the original error
            }
          } catch (e2) {
            print('WeatherService: All location methods failed: $e2');
            rethrow;
          }
        }
      }
      
      // Fetch weather using coordinates (more accurate than city name)
      print('WeatherService: Fetching weather for ${position.latitude}, ${position.longitude}');
      return await fetchWeather(position.latitude, position.longitude);
    } catch (e) {
      print('WeatherService: Error in fetchWeatherForCurrentLocation: $e');
      rethrow;
    }
  }
}

