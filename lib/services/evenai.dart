import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:demo_ai_even/g1_manager_wrapper.dart';
import 'package:demo_ai_even/controllers/evenai_model_controller.dart';
import 'package:demo_ai_even/services/api_services_openrouter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

class EvenAI {
  static EvenAI? _instance;
  static EvenAI get get => _instance ??= EvenAI._();
  
  G1ManagerWrapper get _g1 => G1ManagerWrapper.instance;

  static bool _isRunning = false;
  static bool get isRunning => _isRunning;

  bool isReceivingAudio = false;
  List<int> audioDataBuffer = [];
  Uint8List? audioData;

  File? lc3File;
  File? pcmFile;
  int durationS = 0;

  static int maxRetry = 10;
  static int _currentLine = 0;
  static Timer? _timer; // Text sending timer
  static List<String> list = [];
  static List<String> sendReplys = [];

  Timer? _recordingTimer;
  final int maxRecordingDuration = 30;

  static bool _isManual = false; 

  static set isRunning(bool value) {
    _isRunning = value;
    isEvenAIOpen.value = value;
    isEvenAISyncing.value = value;
  }

  static RxBool isEvenAIOpen = false.obs;
  static RxBool isEvenAISyncing = false.obs;

  int _lastStartTime = 0;
  int _lastStopTime = 0;
  final int startTimeGap = 500;
  final int stopTimeGap = 500;

  static const _eventSpeechRecognize = "eventSpeechRecognize"; 
  final _eventSpeechRecognizeChannel =
      const EventChannel(_eventSpeechRecognize).receiveBroadcastStream(_eventSpeechRecognize);

  String combinedText = '';
  StreamSubscription? _speechSubscription;

  static final StreamController<String> _textStreamController = StreamController<String>.broadcast();
  static Stream<String> get textStream => _textStreamController.stream;

  static void updateDynamicText(String newText) {
    _textStreamController.add(newText);
  }

  EvenAI._(); 

  void startListening() {
    // Cancel previous subscription if exists
    _speechSubscription?.cancel();
    
    // Always clear combinedText when starting to listen for a new recording
    combinedText = '';
    print("${DateTime.now()} EvenAI: Starting to listen, cleared combinedText");
    
    _speechSubscription = _eventSpeechRecognizeChannel.listen((event) {
      var txt = event["script"] as String? ?? '';
      print("${DateTime.now()} EvenAI: Event received - script: '$txt' (isEmpty: ${txt.isEmpty})");
      if (txt.isNotEmpty && txt.trim().isNotEmpty) {
        combinedText = txt.trim();
        print("${DateTime.now()} EvenAI: Received transcription and set combinedText: '$combinedText'");
      } else {
        print("${DateTime.now()} EvenAI: Received empty or whitespace-only transcription");
      }
    }, onError: (error) {
      print("${DateTime.now()} EvenAI: Error in event: $error");
    });
    
    print("${DateTime.now()} EvenAI: Event listener set up, waiting for transcription...");
  }

  // receiving starting Even AI request from ble
  void toStartEvenAIByOS() async {
    // Clear combinedText before starting new recording
    combinedText = '';
    
    // Set up listener BEFORE starting recording
    startListening(); 
    
    // avoid duplicate ble command in short time
    int currentTime = DateTime.now().millisecondsSinceEpoch;
    if (currentTime - _lastStartTime < startTimeGap) {
      return;
    }

    _lastStartTime = currentTime;

    clear();
    isReceivingAudio = true;

    isRunning = true;
    _currentLine = 0;

    // Start native speech recognition
    await G1ManagerWrapper.invokeMethod("startEvenAI");
    
    // Enable microphone on glasses using library
    await openEvenAIMic();

    startRecordingTimer();
  }

  // Monitor the recording time to prevent unexpected exits
  void startRecordingTimer() {
    _recordingTimer = Timer(Duration(seconds: maxRecordingDuration), () {
      if (isReceivingAudio) {
        print("${DateTime.now()} Even AI startRecordingTimer-----exit-----");
        clear();
      } else {
        _recordingTimer?.cancel();
        _recordingTimer = null;
      }
    });
  }

  // Received Even AI recording end command from glasses
  Future<void> recordOverByOS() async {
    print('${DateTime.now()} EvenAI -------recordOverByOS-------');

    int currentTime = DateTime.now().millisecondsSinceEpoch;
    if (currentTime - _lastStopTime < stopTimeGap) {
      return;
    }
    _lastStopTime = currentTime;

    // Stop receiving audio but keep listener active
    isReceivingAudio = false;
    _recordingTimer?.cancel();
    _recordingTimer = null;

    // Make sure listener is still active
    if (_speechSubscription == null) {
      print("recordOverByOS----WARNING: Speech listener is null, setting it up now");
      startListening();
    }
    
    // Stop native speech recognition
    await G1ManagerWrapper.invokeMethod("stopEvenAI");
    
    // Disable microphone on glasses
    try {
      await _g1.g1.microphone.disable();
    } catch (e) {
      print("recordOverByOS----Error disabling mic: $e");
    }
    
    // Wait for transcription result
    print("recordOverByOS----Waiting for transcription result... (current combinedText: '$combinedText')");
    int waitAttempts = 0;
    const maxWaitAttempts = 60;
    while (combinedText.isEmpty && waitAttempts < maxWaitAttempts) {
      await Future.delayed(Duration(milliseconds: 100));
      waitAttempts++;
      if (waitAttempts % 10 == 0) {
        print("recordOverByOS----Still waiting... (attempt $waitAttempts/$maxWaitAttempts, combinedText: '$combinedText')");
      }
    }

    print("recordOverByOS----startSendReply---pre------combinedText-------*$combinedText*--- (waited ${waitAttempts * 100}ms)");

    _speechSubscription?.cancel();
    _speechSubscription = null;

    if (combinedText.isEmpty) {
      print("recordOverByOS----No transcription received after waiting");
      updateDynamicText("No Speech Recognized");
      isEvenAISyncing.value = false;
      await startSendReply("No Speech Recognized");
      return;
    }

    // We have transcription - now process it
    try {
      print("recordOverByOS----Sending transcribed text to glasses: '$combinedText'");
      await startSendReply(combinedText);
      updateDynamicText(combinedText);
      
      await Future.delayed(Duration(milliseconds: 500));

      // Send to AI and wait for response
      print("recordOverByOS----Sending to AI for response: '$combinedText'");
      final apiService = ApiOpenRouterService();
      String answer = '';
      
      try {
        answer = await apiService.sendChatRequest(combinedText);
        print("recordOverByOS----AI response received: '$answer'");
      } catch (e) {
        print("recordOverByOS----Error getting AI response: $e");
        answer = "Error getting AI response: $e";
      }
  
      print("recordOverByOS----Complete flow - transcription: '$combinedText' - AI answer: '$answer'");

      _timer?.cancel();
      _timer = null;
      
      print("recordOverByOS----Sending AI response to glasses: '$answer'");
      try {
        await startSendReply(answer);
        print("recordOverByOS----AI response sent to glasses successfully");
      } catch (e) {
        print("recordOverByOS----Error sending AI response to glasses: $e");
      }
      
      updateDynamicText("$combinedText\n\n$answer");
      saveQuestionItem(combinedText, answer);
    } catch (e) {
      print("recordOverByOS----Error in processing flow: $e");
    } finally {
      isEvenAISyncing.value = false;
    }
  }

  void saveQuestionItem(String title, String content) {
    print("saveQuestionItem----title----$title----content---$content-");
    final controller = Get.find<EvenaiModelController>();
    controller.addItem(title, content);
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

  Future sendNetworkErrorReply(String text) async {
    _currentLine = 0;
    list = EvenAIDataMethod.measureStringList(text);

    String ryplyWords =
        list.sublist(0, min(3, list.length)).map((str) => '$str\n').join();
    String headString = '\n\n';
    ryplyWords = headString + ryplyWords;

    await sendEvenAIReply(ryplyWords, 0x01, 0x60, 0);
    clear();
  }

  Future startSendReply(String text) async {
    _currentLine = 0;
    list = EvenAIDataMethod.measureStringList(text);
    
    if (!_g1.isConnected) {
      print('EvenAI: Not connected to glasses');
      return;
    }
   
    if (list.length < 4) {
      String startScreenWords =
          list.sublist(0, min(3, list.length)).map((str) => '$str\n').join();
      String headString = '\n\n';
      startScreenWords = headString + startScreenWords;

      await sendEvenAIReply(startScreenWords, 0x01, 0x30, 0);
      
      await Future.delayed(Duration(seconds: 3));
      if (_isManual) {
        return;
      }
      await sendEvenAIReply(startScreenWords, 0x01, 0x40, 0);
      return;
    }
    if (list.length == 4) {
      String startScreenWords =
          list.sublist(0, 4).map((str) => '$str\n').join();
      String headString = '\n';
      startScreenWords = headString + startScreenWords;

      await sendEvenAIReply(startScreenWords, 0x01, 0x30, 0);
      await Future.delayed(Duration(seconds: 3));
      if (_isManual) {
        return;
      }
      await sendEvenAIReply(startScreenWords, 0x01, 0x40, 0);
      return;
    }

    if (list.length == 5) {
      String startScreenWords =
          list.sublist(0, 5).map((str) => '$str\n').join();
      await sendEvenAIReply(startScreenWords, 0x01, 0x30, 0);
      await Future.delayed(Duration(seconds: 3));
      if (_isManual) {
        return;
      }
      await sendEvenAIReply(startScreenWords, 0x01, 0x40, 0);
      return;
    }

    String startScreenWords = list.sublist(0, 5).map((str) => '$str\n').join();
    bool isSuccess = await sendEvenAIReply(startScreenWords, 0x01, 0x30, 0);

    if (isSuccess) {
      _currentLine = 0;
      await updateReplyToOSByTimer();
    } else {
      clear(); 
    }
  }

  Future updateReplyToOSByTimer() async {
    int interval = 5;
   
    _timer?.cancel();
    _timer = Timer.periodic(Duration(seconds: interval), (timer) async {
      if (_isManual) {
        _timer?.cancel();
        _timer = null;
        return;
      }

      int nextLine = _currentLine + 5;
      
      if (nextLine >= list.length) {
        _timer?.cancel();
        _timer = null;
        return;
      }
      
      _currentLine = nextLine;
      sendReplys = list.sublist(_currentLine);

      bool isLastPage = (_currentLine + 5 >= list.length) || sendReplys.length <= 5;
        
      if (sendReplys.length < 4) {
        var mergedStr = sendReplys
            .sublist(0, sendReplys.length)
            .map((str) => '$str\n')
            .join();

        if (isLastPage) {
          await sendEvenAIReply(mergedStr, 0x01, 0x40, 0);
          _timer?.cancel();
          _timer = null;
        } else {
          await sendEvenAIReply(mergedStr, 0x01, 0x30, 0);
        }
      } else {
        var mergedStr = sendReplys
            .sublist(0, min(5, sendReplys.length))
            .map((str) => '$str\n')
            .join();

        if (isLastPage) {
          await sendEvenAIReply(mergedStr, 0x01, 0x40, 0);
          _timer?.cancel();
          _timer = null;
        } else {
          await sendEvenAIReply(mergedStr, 0x01, 0x30, 0);
        }
      }
    });
  }

  // Click the TouchBar on the right to turn the page down
  void nextPageByTouchpad() {
    if (!isRunning) return;
    _isManual = true;
    _timer?.cancel();
    _timer = null;

    if (getTotalPages() < 2) {
      manualForJustOnePage();
      return;
    }

    if (_currentLine + 5 > list.length - 1) {
      return;
    } else {
      _currentLine += 5;
    }
    updateReplyToOSByManual();
  }

  // Click the TouchBar on the left to turn the page up
  void lastPageByTouchpad() {
    if (!isRunning) return;
    _isManual = true;
    _timer?.cancel();
    _timer = null;

    if (getTotalPages() < 2) {
      manualForJustOnePage();
      return;
    }

    if (_currentLine - 5 < 0) {
      _currentLine = 0;
    } else {
      _currentLine -= 5;
    }
    updateReplyToOSByManual();
  }

  Future updateReplyToOSByManual() async {
    if (_currentLine < 0 || _currentLine > list.length - 1) {
      return;
    }

    sendReplys = list.sublist(_currentLine);
    if (sendReplys.length < 4) {
      var mergedStr = sendReplys
          .sublist(0, sendReplys.length)
          .map((str) => '$str\n')
          .join();
      await sendEvenAIReply(mergedStr, 0x01, 0x50, 0);
    } else {
      var mergedStr = sendReplys
          .sublist(0, min(5, sendReplys.length))
          .map((str) => '$str\n')
          .join();
      await sendEvenAIReply(mergedStr, 0x01, 0x50, 0);
    }
  }

  // When there is only one page of text
  Future manualForJustOnePage() async {
    if (list.length < 4) {
      String screenWords =
          list.sublist(0, min(3, list.length)).map((str) => '$str\n').join();
      String headString = '\n\n';
      screenWords = headString + screenWords;

      await sendEvenAIReply(screenWords, 0x01, 0x50, 0);
      return;
    }

    if (list.length == 4) {
      String screenWords = list.sublist(0, 4).map((str) => '$str\n').join();
      String headString = '\n';
      screenWords = headString + screenWords;

      await sendEvenAIReply(screenWords, 0x01, 0x50, 0);
      return;
    }

    if (list.length == 5) {
      String screenWords = list.sublist(0, 5).map((str) => '$str\n').join();

      await sendEvenAIReply(screenWords, 0x01, 0x50, 0);
      return;
    }
  }

  Future stopEvenAIByOS() async {
    isRunning = false;
    clear();

    await G1ManagerWrapper.invokeMethod("stopEvenAI");
    
    // Clear display using library
    try {
      await _g1.g1.display.clear();
    } catch (e) {
      print("stopEvenAIByOS: Error clearing display: $e");
    }
  }

  void clear() {
    isReceivingAudio = false;
    isRunning = false;
    _isManual = false;
    _currentLine = 0;
    _recordingTimer?.cancel();
    _recordingTimer = null;
    _timer?.cancel();
    _timer = null;
    _speechSubscription?.cancel();
    _speechSubscription = null;
    audioDataBuffer.clear();
    audioDataBuffer = [];
    audioData = null;
    list = [];
    sendReplys = [];
    durationS = 0;
    retryCount = 0;
  }

  Future openEvenAIMic() async {
    try {
      // Enable microphone using library
      await _g1.g1.microphone.enable();
      print('${DateTime.now()} openEvenAIMic---mic enabled via library');
    } catch (e) {
      print('${DateTime.now()} openEvenAIMic---error: $e');
      if (isReceivingAudio && isRunning) {
        await Future.delayed(Duration(seconds: 1));
        await openEvenAIMic();
      }
    }
  }

  // Send text data to the glasses
  int retryCount = 0;
  Future<bool> sendEvenAIReply(
      String text, int type, int status, int pos) async {
    print('${DateTime.now()} sendEvenAIReply---text----$text-----type---$type---status---$status----pos---$pos-');
    if (!isRunning || !_g1.isConnected) {
      return false;
    }

    try {
      // Use library's display API for AI response
      // The status codes: 0x30 = in progress, 0x40 = complete, 0x50 = manual, 0x60 = error
      bool isComplete = (status == 0x40 || status == 0x60);
      
      await _g1.g1.display.showAIResponse(
        text,
        isComplete: isComplete,
      );
      
      retryCount = 0;
      return true;
    } catch (e) {
      print('sendEvenAIReply error: $e');
      if (retryCount < maxRetry) {
        retryCount++;
        return await sendEvenAIReply(text, type, status, pos);
      } else {
        retryCount = 0;
        return false;
      }
    }
  }

  static void dispose() {
    _textStreamController.close();
  }
}

extension EvenAIDataMethod on EvenAI {
  static int transferToNewScreen(int type, int status) {
    int newScreen = status | type;
    return newScreen;
  }

  static List<String> measureStringList(String text, [double? maxW]) {
    final double maxWidth = maxW ?? 488; 
    const double fontSize = 21;

    List<String> paragraphs = text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    List<String> ret = [];

    TextStyle ts = TextStyle(fontSize: fontSize);

    for (String paragraph in paragraphs) {
      final textSpan = TextSpan(text: paragraph, style: ts);
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
        maxLines: null,
      );

      textPainter.layout(maxWidth: maxWidth);

      final lineCount = textPainter.computeLineMetrics().length;

      var start = 0;
      for (var i = 0; i < lineCount; i++) {
        final line = textPainter.getLineBoundary(TextPosition(offset: start));
        ret.add(paragraph.substring(line.start, line.end).trim());
        start = line.end;
      }
    }
    return ret;
  }
}
