import 'package:demo_ai_even/ble_manager.dart';
import 'package:demo_ai_even/services/proto.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DisplaySettingsPage extends StatefulWidget {
  const DisplaySettingsPage({super.key});

  @override
  _DisplaySettingsPageState createState() => _DisplaySettingsPageState();
}

class _DisplaySettingsPageState extends State<DisplaySettingsPage> {
  // Brightness Settings (0x00 to 0x2A = 0 to 42)
  double _brightness = 21.0; // Default to middle (21 = 0x15)
  bool _autoBrightness = false; // Default to manual
  
  // Head Up Angle Settings (0x00 to 0x42 = 0 to 66 degrees)
  double _headUpAngle = 30.0; // Default to 30 degrees
  
  // Display Settings (Height: 0-8, Depth: 1-9)
  double _displayHeight = 4.0; // Default to middle
  double _displayDepth = 5.0; // Default to middle
  
  // Display Type Settings (0x00=Full, 0x01=Dual, 0x02=Minimal)
  int _displayType = 0; // Default to Full (0x00)
  
  bool _isApplyingSettings = false;
  bool _isLoadingSettings = false;
  String? _lastStatusMessage;
  
  static const String _prefsKeyDisplayType = 'display_type';
  static const String _prefsKeyBrightness = 'brightness';
  static const String _prefsKeyAutoBrightness = 'auto_brightness';
  
  @override
  void initState() {
    super.initState();
    _loadDisplayType();
    _loadBrightnessSettings();
    // Load settings if already connected
    if (BleManager.get().isConnected) {
      // Small delay to ensure connection is fully established
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          _loadCurrentSettings();
        }
      });
    }
  }
  
  @override
  void dispose() {
    super.dispose();
  }
  
  Future<void> _loadDisplayType() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _displayType = prefs.getInt(_prefsKeyDisplayType) ?? 0; // Default to Full
      });
    } catch (e) {
      print('Error loading display type: $e');
    }
  }

  Future<void> _loadBrightnessSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _brightness = prefs.getDouble(_prefsKeyBrightness) ?? 21.0; // Default to middle
        _autoBrightness = prefs.getBool(_prefsKeyAutoBrightness) ?? false; // Default to manual
      });
    } catch (e) {
      print('Error loading brightness settings: $e');
    }
  }

  Future<void> _saveBrightnessSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_prefsKeyBrightness, _brightness);
      await prefs.setBool(_prefsKeyAutoBrightness, _autoBrightness);
    } catch (e) {
      print('Error saving brightness settings: $e');
    }
  }

  Future<void> _applyBrightnessSettings() async {
    setState(() {
      _isApplyingSettings = true;
      _lastStatusMessage = 'Applying brightness settings...';
    });
    
    bool success = await Proto.setBrightnessSettings(
      brightness: _brightness.toInt(),
      autoBrightness: _autoBrightness,
    );
    
    setState(() {
      _isApplyingSettings = false;
      _lastStatusMessage = success
          ? 'Success: Brightness ${_autoBrightness ? "set to auto" : "set to ${_brightness.toInt()}"}'
          : 'Failed: Could not set brightness. Please try again.';
    });
  }

  /// Load current display settings from glasses
  Future<void> _loadCurrentSettings() async {
    // Only fetch if connected
    if (!BleManager.get().isConnected) {
      print('_loadCurrentSettings: Not connected, skipping');
      return;
    }

    setState(() {
      _isLoadingSettings = true;
      _lastStatusMessage = 'Loading current settings...';
    });

    try {
      List<String> loadedSettings = [];
      
      // Get head up angle settings from right arm
      final headUpAngle = await Proto.getHeadUpAngleSettings();
      if (headUpAngle != null) {
        setState(() {
          _headUpAngle = headUpAngle.toDouble();
        });
        loadedSettings.add('Head Up Angle: ${headUpAngle}°');
        print('_loadCurrentSettings: Successfully loaded head up angle=$headUpAngle');
      } else {
        print('_loadCurrentSettings: Failed to get head up angle settings');
      }
      
      // Get display settings (height and depth) from right arm
      final displaySettings = await Proto.getDisplaySettings();
      if (displaySettings != null) {
        setState(() {
          _displayHeight = displaySettings['height']!.toDouble();
          _displayDepth = displaySettings['depth']!.toDouble();
        });
        loadedSettings.add('Height: ${displaySettings['height']}, Depth: ${displaySettings['depth']}');
        print('_loadCurrentSettings: Successfully loaded height=${displaySettings['height']}, depth=${displaySettings['depth']}');
      } else {
        print('_loadCurrentSettings: Failed to get display settings');
      }
      
      // Update status message
      if (loadedSettings.isNotEmpty) {
        setState(() {
          _lastStatusMessage = 'Success: Loaded settings (${loadedSettings.join(', ')})';
        });
      } else {
        setState(() {
          _lastStatusMessage = 'Failed: Could not load settings from glasses';
        });
      }
    } catch (e) {
      print('_loadCurrentSettings: Error - $e');
      setState(() {
        _lastStatusMessage = 'Error: Failed to load settings - $e';
      });
    } finally {
      setState(() {
        _isLoadingSettings = false;
      });
    }
  }
  
  Future<void> _saveDisplayType(int displayType) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefsKeyDisplayType, displayType);
    } catch (e) {
      print('Error saving display type: $e');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Display Settings'),
    ),
    body: SingleChildScrollView(
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
              child: Row(
                children: [
                  const Icon(Icons.warning, color: Colors.orange),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Please connect to glasses first',
                      style: TextStyle(color: Colors.orange),
                    ),
                  ),
                ],
              ),
            ),
          
          // Status message
          if (_lastStatusMessage != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: _lastStatusMessage!.contains('Success') || _lastStatusMessage!.contains('Loaded')
                    ? Colors.green.withOpacity(0.1)
                    : _lastStatusMessage!.contains('Loading')
                        ? Colors.blue.withOpacity(0.1)
                        : Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(
                  color: _lastStatusMessage!.contains('Success') || _lastStatusMessage!.contains('Loaded')
                      ? Colors.green
                      : _lastStatusMessage!.contains('Loading')
                          ? Colors.blue
                          : Colors.red,
                ),
              ),
              child: Row(
                children: [
                  if (_isLoadingSettings)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Icon(
                      _lastStatusMessage!.contains('Success') || _lastStatusMessage!.contains('Loaded')
                          ? Icons.check_circle
                          : Icons.error,
                      size: 16,
                      color: _lastStatusMessage!.contains('Success') || _lastStatusMessage!.contains('Loaded')
                          ? Colors.green.shade700
                          : Colors.red.shade700,
                    ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _lastStatusMessage!,
                      style: TextStyle(
                        color: _lastStatusMessage!.contains('Success') || _lastStatusMessage!.contains('Loaded')
                            ? Colors.green.shade700
                            : _lastStatusMessage!.contains('Loading')
                                ? Colors.blue.shade700
                                : Colors.red.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          
          // Refresh button to reload settings
          if (BleManager.get().isConnected && !_isLoadingSettings)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 16),
              child: ElevatedButton.icon(
                onPressed: _isApplyingSettings ? null : _loadCurrentSettings,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh Settings from Glasses'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),

          // Brightness Settings Section
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
                  'Brightness Settings',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Adjust the brightness level or enable/disable auto brightness.',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 20),
                
                // Auto Brightness Switch
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Auto Brightness:',
                      style: TextStyle(fontSize: 16),
                    ),
                    Switch(
                      value: _autoBrightness,
                      onChanged: (value) {
                        setState(() {
                          _autoBrightness = value;
                        });
                        // Save settings
                        _saveBrightnessSettings();
                        // Apply immediately if connected
                        if (BleManager.get().isConnected) {
                          _applyBrightnessSettings();
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                
                // Manual Brightness Slider (only when auto is off)
                if (!_autoBrightness) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Brightness:',
                        style: TextStyle(fontSize: 16),
                      ),
                      Text(
                        _brightness.toInt().toString(),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: _brightness,
                    min: 0,
                    max: 42, // Maximum based on command range (0x2A = 42)
                    divisions: 42,
                    label: _brightness.toInt().toString(),
                    onChanged: (value) {
                      setState(() {
                        _brightness = value;
                      });
                    },
                    onChangeEnd: (value) {
                      // Save settings when user finishes dragging
                      _saveBrightnessSettings();
                      // Apply immediately if connected
                      if (BleManager.get().isConnected) {
                        _applyBrightnessSettings();
                      }
                    },
                  ),
                ],
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: (!BleManager.get().isConnected || _isApplyingSettings)
                        ? null
                        : _applyBrightnessSettings,
                    child: _isApplyingSettings
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Apply Brightness Settings'),
                  ),
                ),
              ],
            ),
          ),

          // Head Up Angle Settings Section
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
                  'Head Up Angle Settings',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Set the angle at which the display turns on when looking up.',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Angle:',
                      style: TextStyle(fontSize: 16),
                    ),
                    Text(
                      '${_headUpAngle.toInt()}°',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: _headUpAngle,
                  min: 0,
                  max: 66, // Maximum based on GET command range (0x42 = 66)
                  divisions: 66,
                  label: '${_headUpAngle.toInt()}°',
                  onChanged: (value) {
                    setState(() {
                      _headUpAngle = value;
                    });
                  },
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: (!BleManager.get().isConnected || _isApplyingSettings)
                        ? null
                        : () async {
                            setState(() {
                              _isApplyingSettings = true;
                              _lastStatusMessage = 'Applying head up angle settings...';
                            });
                            
                            bool success = await Proto.setHeadUpAngleSettings(
                              angle: _headUpAngle.toInt(),
                            );
                            
                            setState(() {
                              _isApplyingSettings = false;
                              _lastStatusMessage = success
                                  ? 'Success: Head up angle set to ${_headUpAngle.toInt()}°'
                                  : 'Failed: Could not set head up angle. Please try again.';
                            });
                          },
                    child: _isApplyingSettings
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Apply Head Up Angle'),
                  ),
                ),
              ],
            ),
          ),

          // Display Type Settings Section
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
                  'Display Type Settings',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Set the dashboard display mode. Changes will be applied immediately.',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 16),
                RadioListTile<int>(
                  title: const Text('Full'),
                  subtitle: const Text('Full display mode'),
                  value: 0,
                  groupValue: _displayType,
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _displayType = value;
                      });
                    }
                  },
                ),
                RadioListTile<int>(
                  title: const Text('Dual'),
                  subtitle: const Text('Dual pane display mode'),
                  value: 1,
                  groupValue: _displayType,
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _displayType = value;
                      });
                    }
                  },
                ),
                RadioListTile<int>(
                  title: const Text('Minimal'),
                  subtitle: const Text('Minimal display mode'),
                  value: 2,
                  groupValue: _displayType,
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _displayType = value;
                      });
                    }
                  },
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: (!BleManager.get().isConnected || _isApplyingSettings)
                        ? null
                        : () async {
                            setState(() {
                              _isApplyingSettings = true;
                              _lastStatusMessage = 'Applying display type settings...';
                            });
                            
                            // Save to preferences
                            await _saveDisplayType(_displayType);
                            
                            // Apply to glasses
                            bool success = await Proto.setDashboardMode(
                              modeId: _displayType,
                            );
                            
                            setState(() {
                              _isApplyingSettings = false;
                              final modeNames = ['Full', 'Dual', 'Minimal'];
                              _lastStatusMessage = success
                                  ? 'Success: Display type set to ${modeNames[_displayType]}'
                                  : 'Failed: Could not set display type. Please try again.';
                            });
                          },
                    child: _isApplyingSettings
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Apply Display Type'),
                  ),
                ),
              ],
            ),
          ),

          // Display Settings Section
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Display Position Settings',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Adjust the height and depth of the display. Changes will be previewed before applying.',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 24),
                
                // Height Slider
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Height:',
                      style: TextStyle(fontSize: 16),
                    ),
                    Text(
                      _displayHeight.toInt().toString(),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: _displayHeight,
                  min: 0,
                  max: 8,
                  divisions: 8,
                  label: _displayHeight.toInt().toString(),
                  onChanged: (value) {
                    setState(() {
                      _displayHeight = value;
                    });
                  },
                ),
                const SizedBox(height: 20),
                
                // Depth Slider
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Depth:',
                      style: TextStyle(fontSize: 16),
                    ),
                    Text(
                      _displayDepth.toInt().toString(),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: _displayDepth,
                  min: 1,
                  max: 9,
                  divisions: 8,
                  label: _displayDepth.toInt().toString(),
                  onChanged: (value) {
                    setState(() {
                      _displayDepth = value;
                    });
                  },
                ),
                const SizedBox(height: 20),
                
                // Apply Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: (!BleManager.get().isConnected || _isApplyingSettings)
                        ? null
                        : () async {
                            setState(() {
                              _isApplyingSettings = true;
                              _lastStatusMessage = 'Applying display settings (this will take a few seconds)...';
                            });
                            
                            bool success = await Proto.setDisplaySettingsWithPreview(
                              height: _displayHeight.toInt(),
                              depth: _displayDepth.toInt(),
                              previewDelaySeconds: 3,
                            );
                            
                            setState(() {
                              _isApplyingSettings = false;
                              _lastStatusMessage = success
                                  ? 'Success: Display settings applied (Height: ${_displayHeight.toInt()}, Depth: ${_displayDepth.toInt()})'
                                  : 'Failed: Could not apply display settings. Please try again.';
                            });
                          },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _isApplyingSettings
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text(
                            'Apply Display Settings',
                            style: TextStyle(fontSize: 16),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

