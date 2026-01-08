// ignore_for_file: library_private_types_in_public_api

import 'dart:io';
import 'dart:typed_data';
import 'package:demo_ai_even/ble_manager.dart';
import 'package:demo_ai_even/services/features_services.dart';
import 'package:demo_ai_even/utils/utils.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:fluttertoast/fluttertoast.dart';

class UploadImagePage extends StatefulWidget {
  const UploadImagePage({super.key});

  @override
  _UploadImageState createState() => _UploadImageState();
}

class _UploadImageState extends State<UploadImagePage> {
  XFile? _pickedImage;
  Uint8List? _fullImageBmp; // Full height image BMP
  Uint8List? _currentWindowBmp; // Current 136-pixel window BMP
  bool _isConverting = false;
  bool _isSending = false;
  double _threshold = 0.5;
  int _scrollPosition = 0; // Vertical scroll position in pixels
  int _fullImageHeight = 0; // Full image height after scaling to 576 width
  String _sizeStatus = '';
  bool _waitingForTouchpad = false;
  String _touchpadInstructions = '';

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _setupTouchpadListener();
  }

  void _setupTouchpadListener() {
    // Touchpad callback will be set when waiting for input
    // Don't set it here to avoid intercepting other touchpad events
  }

  @override
  void dispose() {
    // Clear touchpad callback when page is disposed
    BleManager.get().onTouchpadTap = null;
    super.dispose();
  }

  void _enableTouchpadMode() {
    if (_fullImageHeight <= 136) {
      _showToast('Image fits in one screen, no scrolling needed');
      return;
    }
    
    setState(() {
      _waitingForTouchpad = true;
      _touchpadInstructions = 'Touchpad scrolling enabled!\n'
          'Tap LEFT touchpad: Scroll up (view higher parts)\n'
          'Tap RIGHT touchpad: Scroll down (view lower parts)\n'
          'Position: $_scrollPosition / ${_fullImageHeight - 136}px';
    });
    // Set touchpad callback
    BleManager.get().onTouchpadTap = _handleTouchpadTap;
  }

  void _disableTouchpadMode() {
    setState(() {
      _waitingForTouchpad = false;
      _touchpadInstructions = '';
    });
    // Clear touchpad callback
    BleManager.get().onTouchpadTap = null;
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 100,
      );

      if (image != null) {
        setState(() {
          _pickedImage = image;
          _fullImageBmp = null;
          _currentWindowBmp = null;
          _scrollPosition = 0;
          _fullImageHeight = 0;
          _sizeStatus = '';
          _waitingForTouchpad = false;
          _touchpadInstructions = '';
        });
        await _convertImage();
      }
    } catch (e) {
      _showToast('Error picking image: $e');
    }
  }

  Future<void> _takePhoto() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 100,
      );

      if (image != null) {
        setState(() {
          _pickedImage = image;
          _fullImageBmp = null;
          _currentWindowBmp = null;
          _scrollPosition = 0;
          _fullImageHeight = 0;
          _sizeStatus = '';
          _waitingForTouchpad = false;
          _touchpadInstructions = '';
        });
        await _convertImage();
      }
    } catch (e) {
      _showToast('Error taking photo: $e');
    }
  }

  Future<void> _convertImage() async {
    if (_pickedImage == null) return;

    setState(() {
      _isConverting = true;
      _sizeStatus = '';
    });

    try {
      // Read image file
      final imageBytes = await _pickedImage!.readAsBytes();
      
      // Convert to full-height BMP (576 width, maintain aspect ratio)
      final result = await Utils.convertImageBytesToFullHeightBmp(
        imageBytes,
        targetWidth: 576,
        threshold: _threshold,
      );

      if (result != null) {
        setState(() {
          _fullImageBmp = result['bmp'];
          _fullImageHeight = result['height'];
          _scrollPosition = 0; // Reset scroll to top
          _isConverting = false;
          _sizeStatus = 'Image converted to 576x$_fullImageHeight (1-bit BMP)\nScroll to view different parts';
        });
        _updateCurrentWindow();
      } else {
        setState(() {
          _isConverting = false;
          _sizeStatus = 'Error: Failed to convert image';
        });
        _showToast('Failed to convert image to BMP format');
      }
    } catch (e) {
      setState(() {
        _isConverting = false;
        _sizeStatus = 'Error: $e';
      });
      _showToast('Error converting image: $e');
    }
  }

  void _updateCurrentWindow() {
    if (_fullImageBmp == null || _fullImageHeight == 0) return;

    // Extract a 136-pixel-high window from the full image
    // Clamp scroll position to valid range
    final maxScroll = (_fullImageHeight - 136).clamp(0, _fullImageHeight);
    _scrollPosition = _scrollPosition.clamp(0, maxScroll);

    // Extract the window from the full BMP
    _currentWindowBmp = Utils.extractBmpWindow(
      _fullImageBmp!,
      _fullImageHeight,
      576,
      _scrollPosition,
      136,
    );

    setState(() {
      // Update status
      if (_fullImageHeight > 136) {
        _sizeStatus = 'Image: 576x$_fullImageHeight | Viewing: ${_scrollPosition}-${_scrollPosition + 136}px';
      } else {
        _sizeStatus = 'Image: 576x$_fullImageHeight (1-bit BMP)';
      }
    });
  }

  Future<void> _adjustThreshold() async {
    if (_pickedImage == null) return;

    // Show dialog with threshold slider
    _showThresholdDialog();
  }

  void _showThresholdDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Adjust Image Threshold'),
        content: StatefulBuilder(
          builder: (context, setDialogState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Threshold: ${(_threshold * 100).toStringAsFixed(0)}%'),
              Slider(
                value: _threshold,
                min: 0.0,
                max: 1.0,
                divisions: 100,
                onChanged: (value) {
                  setDialogState(() {
                    _threshold = value;
                  });
                },
              ),
              const Text(
                'Lower values = more black\nHigher values = more white',
                style: TextStyle(fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _waitingForTouchpad = false;
                _touchpadInstructions = '';
              });
            },
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _convertImage();
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  Future<void> _sendToGlasses() async {
    if (_currentWindowBmp == null) {
      _showToast('Please convert an image first');
      return;
    }

    if (!BleManager.get().isConnected) {
      _showToast('Not connected to glasses');
      return;
    }

    // Disable touchpad mode when sending
    _disableTouchpadMode();

    setState(() {
      _isSending = true;
    });

    try {
      // Send the current window (576x136) to glasses
      await FeaturesServices().sendBmpFromBytes(_currentWindowBmp!);
      _showToast('Image sent to glasses');
    } catch (e) {
      _showToast('Error sending image: $e');
    } finally {
      setState(() {
        _isSending = false;
      });
    }
  }

  void _showToast(String message) {
    Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
    );
  }

  void _handleTouchpadTap(String lr) {
    if (!_waitingForTouchpad || _fullImageBmp == null || _fullImageHeight <= 136) {
      // If not waiting for touchpad or image doesn't need scrolling, ignore
      return;
    }

    setState(() {
      const scrollStep = 20; // Pixels to scroll per tap
      
      if (lr == 'L') {
        // Scroll up (decrease scroll position)
        _scrollPosition = (_scrollPosition - scrollStep).clamp(0, _fullImageHeight - 136);
      } else if (lr == 'R') {
        // Scroll down (increase scroll position)
        _scrollPosition = (_scrollPosition + scrollStep).clamp(0, _fullImageHeight - 136);
      }
      
      _touchpadInstructions = 'Scrolling...\n'
          'Position: $_scrollPosition / ${_fullImageHeight - 136}px\n'
          'LEFT: Up | RIGHT: Down';
    });

    // Update the current window after scrolling
    _updateCurrentWindow();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Upload Image'),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Image picker buttons
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _pickImage,
                      icon: const Icon(Icons.photo_library),
                      label: const Text('From Gallery'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _takePhoto,
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('Take Photo'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Picked image preview
              if (_pickedImage != null) ...[
                Container(
                  height: 200,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      File(_pickedImage!.path),
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Conversion status
              if (_isConverting)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: CircularProgressIndicator(),
                  ),
                ),

              if (_sizeStatus.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _sizeStatus.contains('Error')
                        ? Colors.red.withOpacity(0.1)
                        : Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _sizeStatus,
                    style: TextStyle(
                      color: _sizeStatus.contains('Error')
                          ? Colors.red
                          : Colors.green,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Threshold adjustment
              if (_pickedImage != null && !_isConverting) ...[
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Grayscale Threshold: ${(_threshold * 100).toStringAsFixed(0)}%'),
                          const Text(
                            'Adjust the threshold for better contrast',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      onPressed: _adjustThreshold,
                      child: const Text('Adjust Threshold'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],

              // Scroll controls (only if image is taller than 136px)
              if (_pickedImage != null && _fullImageHeight > 136 && !_isConverting) ...[
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Scroll Position: $_scrollPosition / ${_fullImageHeight - 136}px'),
                          const Text(
                            'Use touchpads to scroll through the image',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      onPressed: _enableTouchpadMode,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _waitingForTouchpad ? Colors.green : null,
                      ),
                      child: Text(_waitingForTouchpad ? 'Scrolling Active' : 'Enable Scrolling'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],

              // Touchpad instructions
              if (_waitingForTouchpad && _touchpadInstructions.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      Text(
                        _touchpadInstructions,
                        style: const TextStyle(color: Colors.blue),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _disableTouchpadMode,
                        child: const Text('Disable Scrolling'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Current window preview (if available)
              if (_currentWindowBmp != null) ...[
                const Text(
                  'Current View (576x136, 1-bit BMP)',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Container(
                  height: 136,
                  width: double.infinity,
                  constraints: const BoxConstraints(maxWidth: 576),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.black,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(
                      _currentWindowBmp!,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                if (_fullImageHeight > 136) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Showing ${_scrollPosition}-${(_scrollPosition + 136).clamp(0, _fullImageHeight)}px of ${_fullImageHeight}px total',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 16),
              ],

              // Send button
              if (_currentWindowBmp != null && !_isSending) ...[
                ElevatedButton.icon(
                  onPressed: _sendToGlasses,
                  icon: const Icon(Icons.send),
                  label: const Text('Send Current View to Glasses'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ],

              if (_isSending) ...[
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 8),
                        Text('Sending to glasses...'),
                      ],
                    ),
                  ),
                ),
              ],

              // Instructions
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Instructions:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 8),
                    Text(
                      '1. Pick an image from gallery or take a photo\n'
                      '2. Image will be scaled to 576px width (maintains aspect ratio)\n'
                      '3. Adjust grayscale threshold using the slider for better contrast\n'
                      '4. If image is taller than 136px, enable scrolling:\n'
                      '   - LEFT touchpad: Scroll up (view higher parts)\n'
                      '   - RIGHT touchpad: Scroll down (view lower parts)\n'
                      '5. Tap "Send to Glasses" to transmit the current view',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}
