import 'package:demo_ai_even/g1_manager_wrapper.dart';
import 'package:demo_ai_even/services/text_service.dart';
import 'package:demo_ai_even/services/evenai.dart';
import 'package:demo_ai_even/app.dart';

class PinTextService {
  static PinTextService? _instance;
  static PinTextService get instance => _instance ??= PinTextService._();
  
  PinTextService._();

  bool _isActive = false;
  
  G1ManagerWrapper get _g1 => G1ManagerWrapper.instance;

  /// Send a PinText to the glasses using library notes API
  /// Note: Need to ensure we're in dashboard mode first (exit other features)
  Future<bool> sendPinText(String content) async {
    if (!_g1.isConnected) {
      print('PinTextService: Not connected to glasses');
      return false;
    }

    // First, ensure we're in dashboard mode by exiting any active features
    try {
      if (EvenAI.isRunning || TextService.isRunning) {
        print('PinTextService: Exiting active features to enter dashboard mode');
        App.get.exitAll();
        // Clear display using library
        await _g1.g1.display.clear();
        await Future.delayed(const Duration(milliseconds: 800)); // Wait for exit to complete
      }
    } catch (e) {
      print('PinTextService: Error exiting features: $e');
    }

    // Add delay to avoid BLE command conflicts
    await Future.delayed(const Duration(milliseconds: 200));

    _isActive = true;

    print('${DateTime.now()} PinTextService: Sending PinText using notes API, content=$content');
    
    try {
      // Use library's notes API to add a quick note
      await _g1.g1.notes.add(
        noteNumber: 1,
        name: 'Quick Note',
        text: content,
      );
      
      _isActive = false;
      print('${DateTime.now()} PinTextService: PinText sent successfully');
      return true;
    } catch (e) {
      _isActive = false;
      print('${DateTime.now()} PinTextService: Error sending PinText: $e');
      return false;
    }
  }

  /// Send all PinText to glasses (for initial sync)
  Future<void> syncPinText(List<String> notes) async {
    if (notes.isEmpty) return;
    
    // Send first note
    await sendPinText(notes[0]);
  }

  bool get isActive => _isActive;
}
