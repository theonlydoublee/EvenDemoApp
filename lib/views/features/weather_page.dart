import 'package:demo_ai_even/ble_manager.dart';
import 'package:demo_ai_even/controllers/weather_controller.dart';
import 'package:demo_ai_even/services/weather_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class WeatherPage extends StatefulWidget {
  const WeatherPage({super.key});

  @override
  _WeatherPageState createState() => _WeatherPageState();
}

class _WeatherPageState extends State<WeatherPage> {
  late WeatherController _controller;
  double _sliderValue = 1.0; // Local state for slider to avoid triggering updates during drag
  bool _isDraggingSlider = false; // Track if user is currently dragging the slider

  @override
  void initState() {
    super.initState();
    // Get or create controller
    try {
      _controller = Get.find<WeatherController>();
    } catch (e) {
      _controller = Get.put(WeatherController());
    }
    // Initialize slider value from controller
    _sliderValue = _controller.updateIntervalMinutes.value.toDouble();
  }

  String _getWeatherIconName(int iconId) {
    switch (iconId) {
      case 0x00:
        return 'None';
      case 0x01:
        return 'Night';
      case 0x02:
        return 'Clouds';
      case 0x03:
        return 'Drizzle';
      case 0x04:
        return 'Heavy Drizzle';
      case 0x05:
        return 'Rain';
      case 0x06:
        return 'Heavy Rain';
      case 0x07:
        return 'Thunder';
      case 0x08:
        return 'Thunder Storm';
      case 0x09:
        return 'Snow';
      case 0x0A:
        return 'Mist';
      case 0x0B:
        return 'Fog';
      case 0x0C:
        return 'Sand';
      case 0x0D:
        return 'Squalls';
      case 0x0E:
        return 'Tornado';
      case 0x0F:
        return 'Freezing';
      case 0x10:
        return 'Sunny';
      default:
        return 'Unknown';
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Weather'),
        ),
        body: Obx(() => SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Connection status warning
                  if (!BleManager.get().isConnected)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: Colors.orange),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.warning, color: Colors.orange),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Please connect to glasses first to send weather data',
                              style: TextStyle(color: Colors.orange),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Error message
                  if (_controller.errorMessage.value != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: Colors.red),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error, color: Colors.red),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _controller.errorMessage.value ?? '',
                              style: const TextStyle(color: Colors.red),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.red, size: 20),
                            onPressed: () => _controller.clearError(),
                          ),
                        ],
                      ),
                    ),

                  // Current Weather Display
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    margin: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Current Weather',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 20),
                        if (_controller.weatherData.value != null)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // City Name
                              Row(
                                children: [
                                  const Icon(Icons.location_on, color: Colors.blue),
                                  const SizedBox(width: 8),
                                  Text(
                                    _controller.weatherData.value!.cityName,
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              // Temperature
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _controller.useFahrenheit.value
                                        ? '${((_controller.weatherData.value!.temperature * 9 / 5) + 32).round()}°F'
                                        : '${_controller.weatherData.value!.temperature.round()}°C',
                                    style: const TextStyle(
                                      fontSize: 48,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _getWeatherIconName(_controller.weatherData.value!.weatherIconId),
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          _controller.weatherData.value!.condition,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              // Icon ID and Coordinates
                              Row(
                                children: [
                                  Text(
                                    'Icon ID: 0x${_controller.weatherData.value!.weatherIconId.toRadixString(16).padLeft(2, '0').toUpperCase()}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Text(
                                    'Lat: ${_controller.weatherData.value!.latitude.toStringAsFixed(2)}, '
                                    'Lon: ${_controller.weatherData.value!.longitude.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          )
                        else
                          const Text(
                            'No weather data available. Tap "Update Weather" to fetch current weather.',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey,
                            ),
                          ),
                      ],
                    ),
                  ),

                  // Settings Section
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    margin: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Settings',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Temperature Unit Toggle
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Temperature Unit:',
                              style: TextStyle(fontSize: 16),
                            ),
                            Switch(
                              value: _controller.useFahrenheit.value,
                              onChanged: (value) {
                                _controller.toggleTemperatureUnit();
                              },
                            ),
                          ],
                        ),
                        Text(
                          _controller.useFahrenheit.value ? 'Fahrenheit (°F)' : 'Celsius (°C)',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Time Format Toggle
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Time Format:',
                              style: TextStyle(fontSize: 16),
                            ),
                            Switch(
                              value: _controller.use12HourFormat.value,
                              onChanged: (value) {
                                _controller.toggleTimeFormat();
                              },
                            ),
                          ],
                        ),
                        Text(
                          _controller.use12HourFormat.value ? '12-hour format' : '24-hour format',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 24),
                        // Location Accuracy Setting
                        const Text(
                          'Location Accuracy:',
                          style: TextStyle(fontSize: 16),
                        ),
                        const SizedBox(height: 8),
                        Obx(() => DropdownButton<LocationAccuracyPreference>(
                          value: _controller.locationAccuracy.value,
                          isExpanded: true,
                          items: [
                            DropdownMenuItem(
                              value: LocationAccuracyPreference.low,
                              child: Row(
                                children: [
                                  const Icon(Icons.battery_1_bar, size: 20, color: Colors.green),
                                  const SizedBox(width: 8),
                                  const Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Low (~100m)', style: TextStyle(fontSize: 14)),
                                        Text('Fastest, saves battery', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            DropdownMenuItem(
                              value: LocationAccuracyPreference.medium,
                              child: Row(
                                children: [
                                  const Icon(Icons.battery_3_bar, size: 20, color: Colors.orange),
                                  const SizedBox(width: 8),
                                  const Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Medium (~10-100m)', style: TextStyle(fontSize: 14)),
                                        Text('Balanced accuracy', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            DropdownMenuItem(
                              value: LocationAccuracyPreference.high,
                              child: Row(
                                children: [
                                  const Icon(Icons.battery_5_bar, size: 20, color: Colors.blue),
                                  const SizedBox(width: 8),
                                  const Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('High (~10m)', style: TextStyle(fontSize: 14)),
                                        Text('Better for sub-areas', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            DropdownMenuItem(
                              value: LocationAccuracyPreference.best,
                              child: Row(
                                children: [
                                  const Icon(Icons.battery_full, size: 20, color: Colors.red),
                                  const SizedBox(width: 8),
                                  const Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Best (~5m)', style: TextStyle(fontSize: 14)),
                                        Text('Most accurate, uses more battery', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              _controller.setLocationAccuracy(value);
                            }
                          },
                        )),
                        const SizedBox(height: 8),
                        Obx(() => Text(
                          _getAccuracyDescription(_controller.locationAccuracy.value),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                            fontStyle: FontStyle.italic,
                          ),
                        )),
                        const SizedBox(height: 24),
                        // Auto-Update Toggle
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Expanded(
                              child: Text(
                                'Auto-Update Weather:',
                                style: TextStyle(fontSize: 16),
                              ),
                            ),
                            Switch(
                              value: _controller.isAutoUpdateEnabled.value,
                              onChanged: (value) {
                                _controller.toggleAutoUpdate();
                              },
                            ),
                          ],
                        ),
                        Text(
                          _controller.isAutoUpdateEnabled.value
                              ? 'Weather updates every ${_controller.updateIntervalMinutes.value} minute(s)'
                              : 'Auto-update is disabled',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                        ),
                        // Update Interval Configuration (only show if auto-update is enabled)
                        Obx(() {
                          if (!_controller.isAutoUpdateEnabled.value) {
                            return const SizedBox.shrink();
                          }
                          
                          // Only sync slider value with controller when NOT dragging
                          // This prevents the slider from jumping back during drag
                          if (!_isDraggingSlider) {
                            final controllerValue = _controller.updateIntervalMinutes.value.toDouble();
                            // Only sync if values differ (means external change, not user drag)
                            if ((_sliderValue - controllerValue).abs() >= 1.0) {
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (mounted && !_isDraggingSlider) {
                                  setState(() {
                                    _sliderValue = controllerValue;
                                  });
                                }
                              });
                            }
                          }
                          
                          return Column(
                            children: [
                              const SizedBox(height: 16),
                              const Text(
                                'Update Interval:',
                                style: TextStyle(fontSize: 16),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: Slider(
                                      value: _sliderValue,
                                      min: 1,
                                      max: 60,
                                      divisions: 59,
                                      label: '${_sliderValue.toInt()} minute(s)',
                                      onChanged: (value) {
                                        // Mark that we're dragging and update local slider value
                                        _isDraggingSlider = true;
                                        setState(() {
                                          _sliderValue = value;
                                        });
                                      },
                                      onChangeStart: (value) {
                                        // Mark dragging started
                                        _isDraggingSlider = true;
                                      },
                                      onChangeEnd: (value) {
                                        // Mark dragging ended and update controller
                                        _isDraggingSlider = false;
                                        print('Slider onChangeEnd: Setting interval to $value minutes');
                                        _controller.setUpdateInterval(value.toInt());
                                        // Ensure slider matches the final value after controller update
                                        Future.delayed(const Duration(milliseconds: 100), () {
                                          if (mounted) {
                                            setState(() {
                                              _sliderValue = _controller.updateIntervalMinutes.value.toDouble();
                                            });
                                          }
                                        });
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    width: 60,
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      border: Border.all(color: Colors.grey),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '${_sliderValue.toInt()}m',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          );
                        }),
                      ],
                    ),
                  ),

                  // Last Update Time
                  if (_controller.lastUpdateTime.value != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        'Last updated: ${_formatDateTime(_controller.lastUpdateTime.value!)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ),

                  // Update Weather Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _controller.isLoading.value
                          ? null
                          : () async {
                              await _controller.fetchAndSendWeather();
                            },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: _controller.isLoading.value
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text(
                              'Update Weather',
                              style: TextStyle(fontSize: 16),
                            ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Send Current Weather Button (only if weather data exists)
                  if (_controller.weatherData.value != null &&
                      BleManager.get().isConnected)
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: _controller.isLoading.value
                            ? null
                            : () async {
                                await _controller.sendCurrentWeatherToGlasses();
                              },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const Text(
                          'Send Weather to Glasses',
                          style: TextStyle(fontSize: 16),
                        ),
                      ),
                    ),
                ],
              ),
            )),
      );

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} '
        '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}';
  }

  String _getAccuracyDescription(LocationAccuracyPreference accuracy) {
    switch (accuracy) {
      case LocationAccuracyPreference.low:
        return 'Recommended for general city-level weather. Fastest response time.';
      case LocationAccuracyPreference.medium:
        return 'Good balance between accuracy and battery usage.';
      case LocationAccuracyPreference.high:
        return 'Recommended for sub-area precision. Better weather accuracy for specific neighborhoods.';
      case LocationAccuracyPreference.best:
        return 'Maximum precision for very specific locations. May use more battery.';
    }
  }
}

