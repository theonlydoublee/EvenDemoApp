import 'dart:async';
import 'package:flutter/services.dart';
import 'package:demo_ai_even/services/evenai.dart';
import 'package:demo_ai_even/ble_manager.dart';
import 'package:demo_ai_even/controllers/pin_text_controller.dart';
import 'package:get/get.dart';

/// Service to handle voice recording for PinText
/// When voice recording is not for EvenAI, create PinText from speech recognition
class PinTextVoiceService {
  static PinTextVoiceService? _instance;
  static PinTextVoiceService get instance => _instance ??= PinTextVoiceService._();
  
  PinTextVoiceService._();

  static const _eventSpeechRecognize = "eventSpeechRecognize";
  final _eventSpeechRecognizeChannel =
      const EventChannel(_eventSpeechRecognize).receiveBroadcastStream(_eventSpeechRecognize);
  
  StreamSubscription<dynamic>? _speechSubscription;
  String _currentRecordingText = '';
  bool _isRecording = false;

  Timer? _debounceTimer;
  String _lastText = '';

  /// Start listening for speech recognition results to create PinText
  void startListening() {
    if (_speechSubscription != null) {
      // Cancel existing subscription and create a new one
      _speechSubscription?.cancel();
      _speechSubscription = null;
    }

    _speechSubscription = _eventSpeechRecognizeChannel.listen(
      (event) {
        try {
          final txt = event["script"] as String? ?? '';
          print('${DateTime.now()} PinTextVoiceService: Received speech recognition: "$txt" (EvenAI running: ${EvenAI.isRunning})');
          
          // Only create note if EvenAI is NOT running
          // If EvenAI is running, let it handle the speech recognition
          if (!EvenAI.isRunning && txt.isNotEmpty && txt.trim().isNotEmpty) {
            _lastText = txt;
            _isRecording = true;
            
            // Cancel previous timer if exists
            _debounceTimer?.cancel();
            
            // Wait a bit to see if more text comes (partial results)
            // If no more updates come, create the note
            _debounceTimer = Timer(const Duration(milliseconds: 2000), () {
              if (_isRecording && _lastText.isNotEmpty && _lastText.trim().isNotEmpty) {
                // No more updates, create the note
                print('${DateTime.now()} PinTextVoiceService: Creating note from final text: "$_lastText"');
                _createNoteFromSpeech(_lastText.trim());
                _isRecording = false;
                _lastText = '';
                
                // Stop speech recognition after creating note
                try {
                  BleManager.invokeMethod("stopEvenAI");
                  print('${DateTime.now()} PinTextVoiceService: Stopped speech recognition after note creation');
                } catch (e) {
                  print('${DateTime.now()} PinTextVoiceService: Error stopping speech recognition: $e');
                }
              }
            });
          }
        } catch (e) {
          print('${DateTime.now()} PinTextVoiceService: Error processing speech recognition: $e');
        }
      },
      onError: (error) {
        print('${DateTime.now()} PinTextVoiceService: Error in speech recognition channel: $error');
      },
    );
    
    print('${DateTime.now()} PinTextVoiceService: Started listening for voice recordings');
  }

  void _createNoteFromSpeech(String text) {
    if (text.trim().isEmpty) {
      print('${DateTime.now()} PinTextVoiceService: Empty text, not creating note');
      return;
    }

    try {
      final pinTextController = Get.find<PinTextController>();
      pinTextController.addNote(text.trim());
      print('${DateTime.now()} PinTextVoiceService: Created PinText from voice: "$text"');
    } catch (e) {
      print('${DateTime.now()} PinTextVoiceService: Error creating note: $e');
    }
  }

  /// Stop listening for speech recognition
  void stopListening() {
    _speechSubscription?.cancel();
    _speechSubscription = null;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _isRecording = false;
    _lastText = '';
    _currentRecordingText = '';
    print('${DateTime.now()} PinTextVoiceService: Stopped listening');
  }

  void dispose() {
    stopListening();
  }
}


