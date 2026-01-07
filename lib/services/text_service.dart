import 'dart:async';
import 'dart:math';
import 'package:demo_ai_even/g1_manager_wrapper.dart';
import 'package:demo_ai_even/services/evenai.dart';

class TextService {
  static TextService? _instance;
  static TextService get get => _instance ??= TextService._();
  static bool isRunning = false;
  static int maxRetry = 5;
  static int _currentLine = 0;
  static Timer? _timer;
  static List<String> list = [];
  static List<String> sendReplys = [];

  TextService._();
  
  G1ManagerWrapper get _g1 => G1ManagerWrapper.instance;

  Future startSendText(String text) async {
    isRunning = true;

    _currentLine = 0;
    list = EvenAIDataMethod.measureStringList(text);
    
    if (!_g1.isConnected) {
      print('TextService: Not connected to glasses');
      clear();
      return;
    }
    
    try {
      // Use library's display API for text display
      await _g1.g1.display.showText(text);
      
      // If text is long, set up auto-paging timer
      if (list.length > 5) {
        _currentLine = 0;
        await _startAutoPaging();
      }
    } catch (e) {
      print('TextService: Error sending text: $e');
      clear();
    }
  }

  int retryCount = 0;
  Future<bool> doSendText(String text, int type, int status, int pos) async {
    print('${DateTime.now()} doSendText--currentPage---${getCurrentPage()}-----text----$text-----type---$type---status---$status----pos---$pos-');
    if (!isRunning || !_g1.isConnected) {
      return false;
    }

    try {
      // Use library's display API
      await _g1.g1.display.showText(text);
      retryCount = 0;
      return true;
    } catch (e) {
      print('TextService: Error in doSendText: $e');
      if (retryCount < maxRetry) {
        retryCount++;
        return await doSendText(text, type, status, pos);
      } else {
        retryCount = 0;
        return false;
      }
    }
  }

  Future _startAutoPaging() async {
    if (!isRunning) return;
    int interval = 8; // The paging interval can be customized
   
    _timer?.cancel();
    _timer = Timer.periodic(Duration(seconds: interval), (timer) async {
      if (!isRunning || !_g1.isConnected) {
        _timer?.cancel();
        _timer = null;
        return;
      }

      _currentLine = min(_currentLine + 5, list.length - 1);
      sendReplys = list.sublist(_currentLine);

      if (_currentLine > list.length - 1) {
        _timer?.cancel();
        _timer = null;
        clear();
      } else {
        int endIdx = min(5, sendReplys.length);
        var mergedStr = sendReplys
            .sublist(0, endIdx)
            .map((str) => '$str\n')
            .join();

        try {
          await _g1.g1.display.showText(mergedStr);
          
          if (_currentLine >= list.length - 5) {
            _timer?.cancel();
            _timer = null;
          }
        } catch (e) {
          print('TextService: Error during auto-paging: $e');
          _timer?.cancel();
          _timer = null;
        }
      }
    });
  }

  @Deprecated('Use _startAutoPaging instead')
  Future updateReplyToOSByTimer() async {
    await _startAutoPaging();
  }

  int getTotalPages() {
    if (list.isEmpty) {
      return 0;
    }
    if (list.length < 6) {
      return 1;
    }
    int pages = 0;
    int div = list.length ~/ 5;
    int rest = list.length % 5;
    pages = div;
    if (rest != 0) {
      pages++;
    }
    return pages;
  }

  int getCurrentPage() {
    if (_currentLine == 0) {
      return 1;
    }
    int currentPage = 1;
    int div = _currentLine ~/ 5;
    int rest = _currentLine % 5;
    currentPage = 1 + div;
    if (rest != 0) {
      currentPage++;
    }
    return currentPage;
  }

  Future stopTextSendingByOS() async {
    print("stopTextSendingByOS---------------");
    isRunning = false;
    clear();
  }

  void clear() {
    isRunning = false;
    _currentLine = 0;
    _timer?.cancel();
    _timer = null;
    list = [];
    sendReplys = [];
    retryCount = 0;
  }
}
