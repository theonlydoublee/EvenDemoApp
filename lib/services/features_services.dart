import 'dart:typed_data';
import 'package:demo_ai_even/g1_manager_wrapper.dart';
import 'package:demo_ai_even/utils/utils.dart';

class FeaturesServices {
  G1ManagerWrapper get _g1 => G1ManagerWrapper.instance;
  
  Future<void> sendBmp(String imageUrl) async {
    Uint8List bmpData = await Utils.loadBmpImage(imageUrl);
    await sendBmpFromBytes(bmpData);
  }

  Future<void> sendBmpFromBytes(Uint8List bmpData) async {
    if (!_g1.isConnected) {
      print('FeaturesServices: Not connected to glasses');
      return;
    }
    
    print("${DateTime.now()} sendBmpFromBytes: Starting BMP send using library");
    
    try {
      // Use library's bitmap API to send image
      await _g1.g1.bitmap.send(bmpData);
      print("${DateTime.now()} sendBmpFromBytes: BMP sent successfully");
    } catch (e) {
      print("${DateTime.now()} sendBmpFromBytes: Error sending BMP: $e");
    }
  }

  Future<void> exitBmp() async {
    if (!_g1.isConnected) {
      print('FeaturesServices: Not connected to glasses');
      return;
    }
    
    try {
      await _g1.g1.display.clear();
      print("exitBmp: Successfully cleared display");
    } catch (e) {
      print("exitBmp: Error clearing display: $e");
    }
  }
}
