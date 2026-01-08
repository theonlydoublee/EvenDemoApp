import 'package:demo_ai_even/ble_manager.dart';
import 'package:demo_ai_even/services/text_service.dart';
import 'package:demo_ai_even/services/evenai.dart';
import 'package:demo_ai_even/services/proto.dart';
import 'package:demo_ai_even/app.dart';

class PinTextService {
  static PinTextService? _instance;
  static PinTextService get instance => _instance ??= PinTextService._();
  
  PinTextService._();

  bool _isActive = false;

  /// Send a PinText to the glasses using TextService
  /// This sends the note as text (same as Text feature)
  /// Note: Need to ensure we're in dashboard mode first (exit other features)
  Future<bool> sendPinText(String content) async {
    if (!BleManager.isBothConnected()) {
      print('PinTextService: Not connected to glasses');
      return false;
    }

    // First, ensure we're in dashboard mode by exiting any active features
    try {
      if (EvenAI.isRunning || TextService.isRunning) {
        print('PinTextService: Exiting active features to enter dashboard mode');
        App.get.exitAll(); // This returns void, not Future
        // Also send exit command to glasses explicitly
        await Proto.exit();
        await Future.delayed(const Duration(milliseconds: 800)); // Wait for exit to complete
      }
    } catch (e) {
      print('PinTextService: Error exiting features: $e');
    }

    // Add delay to avoid BLE command conflicts (prior command might still be in progress)
    // This prevents "writeCharacteristic() - prior command is not finished" errors
    await Future.delayed(const Duration(milliseconds: 200));

    _isActive = true;

    print('${DateTime.now()} PinTextService: Sending PinText as text, content=$content');
    
    // Use TextService to send the PinText as text
    await TextService.get.startSendText(content);

    _isActive = false;
    print('${DateTime.now()} PinTextService: PinText sent successfully as text');
    return true;
  }

  /// Send all PinText to glasses (for initial sync)
  Future<void> syncPinText(List<String> notes) async {
    if (notes.isEmpty) return;
    
    // Send first note
    await sendPinText(notes[0]);
  }

  bool get isActive => _isActive;
}

