import 'dart:convert';
import 'dart:typed_data';

import 'package:demo_ai_even/ble_manager.dart';
import 'package:demo_ai_even/services/evenai_proto.dart';
import 'package:demo_ai_even/utils/utils.dart';

class Proto {
  static String lR() {
    // todo
    if (BleManager.isBothConnected()) return "R";
    //if (BleManager.isConnectedR()) return "R";
    return "L";
  }

  /// Returns the time consumed by the command and whether it is successful
  static Future<(int, bool)> micOn({
    String? lr,
  }) async {
    var begin = Utils.getTimestampMs();
    var data = Uint8List.fromList([0x0E, 0x01]);
    var receive = await BleManager.request(data, lr: lr);

    var end = Utils.getTimestampMs();
    var startMic = (begin + ((end - begin) ~/ 2));

    print("Proto---micOn---startMic---$startMic-------");
    return (startMic, (!receive.isTimeout && receive.data[1] == 0xc9));
  }

  /// Even AI
  static int _evenaiSeq = 0;
  // AI result transmission (also compatible with AI startup and Q&A status synchronization)
  static Future<bool> sendEvenAIData(String text,
      {int? timeoutMs,
      required int newScreen,
      required int pos,
      required int current_page_num,
      required int max_page_num}) async {
    var data = utf8.encode(text);
    var syncSeq = _evenaiSeq & 0xff;

    List<Uint8List> dataList = EvenaiProto.evenaiMultiPackListV2(0x4E,
        data: data,
        syncSeq: syncSeq,
        newScreen: newScreen,
        pos: pos,
        current_page_num: current_page_num,
        max_page_num: max_page_num);
    _evenaiSeq++;

    print(
        '${DateTime.now()} proto--sendEvenAIData---text---$text---_evenaiSeq----$_evenaiSeq---newScreen---$newScreen---pos---$pos---current_page_num--$current_page_num---max_page_num--$max_page_num--dataList----$dataList---');

    bool isSuccess = await BleManager.requestList(dataList,
        lr: "L", timeoutMs: timeoutMs ?? 2000);

    print(
        '${DateTime.now()} sendEvenAIData-----isSuccess-----$isSuccess-------');
    if (!isSuccess) {
      print("${DateTime.now()} sendEvenAIData failed  L ");
      return false;
    } else {
      isSuccess = await BleManager.requestList(dataList,
          lr: "R", timeoutMs: timeoutMs ?? 2000);

      if (!isSuccess) {
        print("${DateTime.now()} sendEvenAIData failed  R ");
        return false;
      }
      return true;
    }
  }

  static int _beatHeartSeq = 0;
  static Future<bool> sendHeartBeat() async {
    var length = 6;
    var data = Uint8List.fromList([
      0x25,                    // Command
      length & 0xff,           // Length low byte
      (length >> 8) & 0xff,   // Length high byte
      _beatHeartSeq % 0xff,    // HB Sequence (first occurrence)
      0x04,                    // Constant byte
      _beatHeartSeq % 0xff,     // HB Sequence (duplicate)
    ]);
    _beatHeartSeq++;

    print('${DateTime.now()} sendHeartBeat--------data---${data.hexString}--');
    var ret = await BleManager.request(data, lr: "L", timeoutMs: 1500);

    print('${DateTime.now()} sendHeartBeat----L----ret---${ret.data.hexString}--');
    if (ret.isTimeout) {
      print('${DateTime.now()} sendHeartBeat----L----time out--');
      return false;
    }
    
    // Validate response format
    if (ret.data.isEmpty || ret.data.length < 6) {
      print('${DateTime.now()} sendHeartBeat----L----invalid response length: ${ret.data.length}');
      return false;
    }
    
    // Check if response is valid (should start with 0x25 and have 0x04 at position 4)
    if (ret.data[0].toInt() == 0x25 &&
        ret.data.length > 5 &&
        ret.data[4].toInt() == 0x04) {
      var retR = await BleManager.request(data, lr: "R", timeoutMs: 1500);
      print('${DateTime.now()} sendHeartBeat----R----retR---${retR.data.hexString}--');
      
      if (retR.isTimeout) {
        print('${DateTime.now()} sendHeartBeat----R----time out--');
        return false;
      }
      
      // Validate right response format
      if (retR.data.isEmpty || retR.data.length < 6) {
        print('${DateTime.now()} sendHeartBeat----R----invalid response length: ${retR.data.length}');
        return false;
      }
      
      if (retR.data[0].toInt() == 0x25 &&
          retR.data.length > 5 &&
          retR.data[4].toInt() == 0x04) {
        return true;
      } else {
        print('${DateTime.now()} sendHeartBeat----R----invalid response format');
        return false;
      }
    } else {
      print('${DateTime.now()} sendHeartBeat----L----invalid response format');
      return false;
    }
  }

  static Future<String> getLegSn(String lr) async {
    var cmd = Uint8List.fromList([0x34]);
    var resp = await BleManager.request(cmd, lr: lr);
    var sn = String.fromCharCodes(resp.data.sublist(2, 18).toList());
    return sn;
  }

  // tell the glasses to exit function to dashboard
  static Future<bool> exit() async {
    print("send exit all func");
    var data = Uint8List.fromList([0x18]);

    var retL = await BleManager.request(data, lr: "L", timeoutMs: 1500);
    print('${DateTime.now()} exit----L----ret---${retL.data}--');
    if (retL.isTimeout) {
      return false;
    } else if (retL.data.isNotEmpty && retL.data[1].toInt() == 0xc9) {
      var retR = await BleManager.request(data, lr: "R", timeoutMs: 1500);
      print('${DateTime.now()} exit----R----retR---${retR.data}--');
      if (retR.isTimeout) {
        return false;
      } else if (retR.data.isNotEmpty && retR.data[1].toInt() == 0xc9) {
        return true;
      } else {
        return false;
      }
    } else {
      return false;
    }
  }

  static List<Uint8List> _getPackList(int cmd, Uint8List data,
      {int count = 20}) {
    final realCount = count - 3;
    List<Uint8List> send = [];
    int maxSeq = data.length ~/ realCount;
    if (data.length % realCount > 0) {
      maxSeq++;
    }
    for (var seq = 0; seq < maxSeq; seq++) {
      var start = seq * realCount;
      var end = start + realCount;
      if (end > data.length) {
        end = data.length;
      }
      var itemData = data.sublist(start, end);
      var pack = Utils.addPrefixToUint8List([cmd, maxSeq, seq], itemData);
      send.add(pack);
    }
    return send;
  }

  static Future<void> sendNewAppWhiteListJson(String whitelistJson) async {
    print("proto -> sendNewAppWhiteListJson: whitelist = $whitelistJson");
    final whitelistData = utf8.encode(whitelistJson);
    //  2、转换为接口格式
    final dataList = _getPackList(0x04, whitelistData, count: 180);
    print(
        "proto -> sendNewAppWhiteListJson: length = ${dataList.length}, dataList = $dataList");
    for (var i = 0; i < 3; i++) {
      final isSuccess =
          await BleManager.requestList(dataList, timeoutMs: 300, lr: "L");
      if (isSuccess) {
        return;
      }
    }
  }

  /// 发送通知
  ///
  /// - app [Map] 通知消息数据
  static Future<bool> sendNotify(Map appData, int notifyId,
      {int retry = 6}) async {
    final notifyJson = jsonEncode({
      "ncs_notification": appData,
    });
    final dataList =
        _getNotifyPackList(0x4B, notifyId, utf8.encode(notifyJson));
    print(
        "proto -> sendNotify: notifyId = $notifyId, data length = ${dataList.length}, data = $dataList, app = $notifyJson");
    
    // Check connection state before attempting to send
    if (!BleManager.get().isConnected) {
      print("proto -> sendNotify: Not connected, cannot send notification");
      print("proto -> sendNotify: Connection status: ${BleManager.get().getConnectionStatus()}");
      return false;
    }
    
    for (var i = 0; i < retry; i++) {
      print("proto -> sendNotify: Attempt ${i + 1}/$retry");
      try {
        bool isSuccess =
            await BleManager.requestList(dataList, timeoutMs: 1000);

        if (!isSuccess) {
          print(
              "proto -> sendNotify: Both-arm send failed on attempt ${i + 1}, falling back to left arm only");
          isSuccess = await BleManager.requestList(dataList,
              timeoutMs: 1000, lr: "L");
        }

        if (isSuccess) {
          print("proto -> sendNotify: Success on attempt ${i + 1}");
          return true;
        } else {
          print("proto -> sendNotify: Failed on attempt ${i + 1}, retrying...");
        }
      } catch (e, stackTrace) {
        print("proto -> sendNotify: Error on attempt ${i + 1}: $e");
        print("Stack trace: $stackTrace");
      }
      
      // Small delay before retry
      if (i < retry - 1) {
        await Future.delayed(Duration(milliseconds: 200));
      }
    }
    
    print("proto -> sendNotify: All $retry attempts failed");
    return false;
  }

  static List<Uint8List> _getNotifyPackList(
      int cmd, int msgId, Uint8List data) {
    List<Uint8List> send = [];
    int maxSeq = data.length ~/ 176;
    if (data.length % 176 > 0) {
      maxSeq++;
    }
    for (var seq = 0; seq < maxSeq; seq++) {
      var start = seq * 176;
      var end = start + 176;
      if (end > data.length) {
        end = data.length;
      }
      var itemData = data.sublist(start, end);
      var pack =
          Utils.addPrefixToUint8List([cmd, msgId, maxSeq, seq], itemData);
      send.add(pack);
    }
    return send;
  }

  /// Set Head Up Angle Settings
  /// Sets the angle at which the display turns on when looking up
  /// 
  /// - [angle]: Angle value from 0x00 to 0x42 (0 to 66 degrees)
  /// - [level]: Optional level parameter (default 0x01)
  /// 
  /// Returns true if successful (response contains 0xC9)
  /// Note: This command should be sent to the RIGHT arm only
  static Future<bool> setHeadUpAngleSettings({
    required int angle,
    int level = 0x01,
  }) async {
    // Validate angle range (0x00 to 0x42 = 0 to 66)
    // Updated to match GET command range
    if (angle < 0 || angle > 0x42) {
      print("setHeadUpAngleSettings: Invalid angle value $angle (must be 0x00-0x42, i.e., 0-66)");
      return false;
    }

    var data = Uint8List.fromList([
      0x0B,
      angle & 0xFF,
      level & 0xFF,
    ]);

    print('${DateTime.now()} setHeadUpAngleSettings: angle=$angle, level=$level');
    
    // Send to RIGHT arm only as per documentation
    var ret = await BleManager.request(data, lr: "R", timeoutMs: 1500);
    
    print('${DateTime.now()} setHeadUpAngleSettings response: ${ret.data.hexString}');
    
    if (ret.isTimeout) {
      print('setHeadUpAngleSettings: Timeout');
      return false;
    }
    
    // Check response: [0x0B, C9/CA]
    if (ret.data.isNotEmpty && 
        ret.data[0].toInt() == 0x0B && 
        ret.data.length >= 2) {
      bool success = ret.data[1].toInt() == 0xC9;
      print('setHeadUpAngleSettings: ${success ? "Success" : "Failed"}');
      return success;
    }
    
    return false;
  }

  static int _displaySettingsSeq = 0;

  /// Set Display Settings (Height and Depth)
  /// Controls the display's height and depth positioning
  /// 
  /// - [height]: Display height value from 0x00 to 0x08 (0 to 8)
  /// - [depth]: Display depth value from 0x01 to 0x09 (1 to 9)
  /// - [preview]: If true, sends preview command (must be called first)
  ///              If false, applies the settings (must be called after preview)
  /// - [seq]: Optional sequence number (auto-incremented if not provided)
  /// 
  /// IMPORTANT: This command MUST be called twice:
  /// 1. First with preview=true
  /// 2. Then with preview=false (a few seconds later)
  /// 
  /// If preview=true is not sent first, the glasses will reject the setting.
  /// The display will stay on permanently until preview=false is sent.
  /// 
  /// Returns true if successful (response contains 0xC9)
  static Future<bool> setDisplaySettings({
    required int height,
    required int depth,
    required bool preview,
    int? seq,
  }) async {
    // Validate height range (0x00 to 0x08 = 0 to 8)
    if (height < 0 || height > 0x08) {
      print("setDisplaySettings: Invalid height value $height (must be 0x00-0x08)");
      return false;
    }
    
    // Validate depth range (0x01 to 0x09 = 1 to 9)
    if (depth < 0x01 || depth > 0x09) {
      print("setDisplaySettings: Invalid depth value $depth (must be 0x01-0x09)");
      return false;
    }

    // Use provided seq or auto-increment
    int sequenceNum = seq ?? (_displaySettingsSeq++ & 0xFF);
    
    var data = Uint8List.fromList([
      0x26,           // Command header
      0x08,           // Packet size
      0x00,           // Pad
      sequenceNum,    // Sequence number (0x00-0xFF)
      0x02,           // Unknown byte (sub-command?)
      preview ? 0x01 : 0x00,  // Preview flag (0x01 for preview, 0x00 for final)
      height & 0xFF,  // Height (0x00-0x08)
      depth & 0xFF,   // Depth (0x01-0x09)
    ]);

    print('${DateTime.now()} setDisplaySettings: height=$height, depth=$depth, preview=$preview, seq=$sequenceNum');
    
    // Send to both arms and validate responses
    // Response format: [0x26, 0x06, 0x00, seq, 0x02, C9/CA]
    var retL = await BleManager.request(data, lr: "L", timeoutMs: 1500);
    
    print('${DateTime.now()} setDisplaySettings L response: ${retL.data.hexString}');
    
    if (retL.isTimeout) {
      print('setDisplaySettings: Timeout on L');
      return false;
    }
    
    // Validate left response
    bool leftSuccess = retL.data.length >= 6 &&
        retL.data[0].toInt() == 0x26 &&
        retL.data[1].toInt() == 0x06 &&
        retL.data[3].toInt() == sequenceNum &&
        retL.data[5].toInt() == 0xC9;
    
    if (!leftSuccess) {
      print('setDisplaySettings: Left arm failed');
      return false;
    }
    
    // Send to right arm
    var retR = await BleManager.request(data, lr: "R", timeoutMs: 1500);
    
    print('${DateTime.now()} setDisplaySettings R response: ${retR.data.hexString}');
    
    if (retR.isTimeout) {
      print('setDisplaySettings: Timeout on R');
      return false;
    }
    
    // Validate right response
    bool rightSuccess = retR.data.length >= 6 &&
        retR.data[0].toInt() == 0x26 &&
        retR.data[1].toInt() == 0x06 &&
        retR.data[3].toInt() == sequenceNum &&
        retR.data[5].toInt() == 0xC9;
    
    if (rightSuccess) {
      print('setDisplaySettings: Success on both arms');
      return true;
    } else {
      print('setDisplaySettings: Right arm failed');
      return false;
    }
  }

  /// Set Display Settings with automatic preview flow
  /// This helper method handles the two-step process automatically:
  /// 1. Sends preview=true command
  /// 2. Waits a few seconds
  /// 3. Sends preview=false command to apply
  /// 
  /// - [height]: Display height value (0x00-0x08)
  /// - [depth]: Display depth value (0x01-0x09)
  /// - [previewDelay]: Delay in seconds between preview and final command (default 3)
  static Future<bool> setDisplaySettingsWithPreview({
    required int height,
    required int depth,
    int previewDelaySeconds = 3,
  }) async {
    // Step 1: Send preview command
    print('setDisplaySettingsWithPreview: Sending preview command...');
    bool previewSuccess = await setDisplaySettings(
      height: height,
      depth: depth,
      preview: true,
    );
    
    if (!previewSuccess) {
      print('setDisplaySettingsWithPreview: Preview command failed');
      return false;
    }
    
    // Step 2: Wait before applying
    print('setDisplaySettingsWithPreview: Waiting ${previewDelaySeconds}s before applying...');
    await Future.delayed(Duration(seconds: previewDelaySeconds));
    
    // Step 3: Send final command to apply settings
    print('setDisplaySettingsWithPreview: Applying final settings...');
    return await setDisplaySettings(
      height: height,
      depth: depth,
      preview: false,
    );
  }

  static int _timeWeatherSeq = 0;

  /// Set Time and Weather
  /// Sets the current time and weather information on the glasses
  /// Based on Gadgetbridge implementation: DASHBOARD_CONFIG command (0x06) with SET_TIME_AND_WEATHER subcommand
  /// 
  /// - [weatherIconId]: Weather icon ID (0x00-0x10)
  /// - [temperature]: Temperature in Celsius (signed byte, -128 to 127)
  /// - [useFahrenheit]: If true, temperature is in Fahrenheit (0x01), else Celsius (0x00)
  /// - [use12HourFormat]: If true, use 12-hour time format (0x01), else 24-hour (0x00)
  /// - [epochTimeSeconds]: Optional epoch time in seconds (defaults to current time)
  /// 
  /// Returns true if successful (response contains 0xC9)
  /// Command: 0x06 (DASHBOARD_CONFIG), Length: 0x15 (21 bytes), Subcommand: SET_TIME_AND_WEATHER
  /// Packet format: [0x06, 0x15, 0x00, sequence, subcommand, time32(4 bytes), time64(8 bytes), icon, temp, c/f, 12h/24h]
  /// Sends to both L and R arms
  static Future<bool> setTimeAndWeather({
    required int weatherIconId,
    required int temperature,
    bool useFahrenheit = false,
    bool use12HourFormat = false,
    int? epochTimeSeconds,
  }) async {
    // Validate weather icon ID (0x00-0x10)
    if (weatherIconId < 0 || weatherIconId > 0x10) {
      print("setTimeAndWeather: Invalid weather icon ID $weatherIconId (must be 0x00-0x10)");
      return false;
    }

    // Validate temperature range (signed byte: -128 to 127)
    if (temperature < -128 || temperature > 127) {
      print("setTimeAndWeather: Invalid temperature $temperature (must be -128 to 127)");
      return false;
    }

    // Get current time
    // Send local time as if it were UTC so glasses display the correct local time
    // This is necessary because glasses may not handle timezone conversion properly
    int timeSeconds;
    int timeMilliseconds;
    
    if (epochTimeSeconds != null) {
      // Use provided epoch time (in seconds)
      timeSeconds = epochTimeSeconds;
      timeMilliseconds = epochTimeSeconds * 1000;
    } else {
      // Get current local time and convert it to epoch as if it were UTC
      // This ensures glasses display the correct local time
      final localNow = DateTime.now();
      // Create a UTC DateTime with the same components as local time
      final utcEquivalent = DateTime.utc(
        localNow.year,
        localNow.month,
        localNow.day,
        localNow.hour,
        localNow.minute,
        localNow.second,
        localNow.millisecond,
      );
      timeMilliseconds = utcEquivalent.millisecondsSinceEpoch;
      timeSeconds = timeMilliseconds ~/ 1000;
    }

    // Get sequence number
    final sequence = _timeWeatherSeq++ & 0xFF;

    // Build the command packet according to Gadgetbridge format
    // Format: [0x06, 0x15, 0x00, sequence, subcommand, time32(4), time64(8), icon, temp, c/f, 12h/24h]
    // Total: 21 bytes (0x15)
    var data = Uint8List(21);
    data[0] = 0x06;                              // Command: DASHBOARD_CONFIG
    data[1] = 0x15;                              // Length: 21 bytes
    data[2] = 0x00;                              // Padding
    data[3] = sequence;                          // Sequence number
    data[4] = 0x01;                              // Subcommand: SET_TIME_AND_WEATHER
    
    // Write 32-bit time (seconds) at index 5-8 (little-endian)
    data[5] = timeSeconds & 0xFF;
    data[6] = (timeSeconds >> 8) & 0xFF;
    data[7] = (timeSeconds >> 16) & 0xFF;
    data[8] = (timeSeconds >> 24) & 0xFF;
    
    // Write 64-bit time (milliseconds) at index 9-16 (little-endian)
    data[9] = timeMilliseconds & 0xFF;
    data[10] = (timeMilliseconds >> 8) & 0xFF;
    data[11] = (timeMilliseconds >> 16) & 0xFF;
    data[12] = (timeMilliseconds >> 24) & 0xFF;
    data[13] = (timeMilliseconds >> 32) & 0xFF;
    data[14] = (timeMilliseconds >> 40) & 0xFF;
    data[15] = (timeMilliseconds >> 48) & 0xFF;
    data[16] = (timeMilliseconds >> 56) & 0xFF;
    
    // Weather information
    data[17] = weatherIconId & 0xFF;             // Weather Icon ID
    data[18] = temperature & 0xFF;               // Temperature (signed byte)
    data[19] = useFahrenheit ? 0x01 : 0x00;      // C/F flag (0x00=Celsius, 0x01=Fahrenheit)
    data[20] = use12HourFormat ? 0x01 : 0x00;    // 24H/12H flag (0x00=24H, 0x01=12H)

    // Debug: Log the time being sent
    final sentTimeUtc = DateTime.fromMillisecondsSinceEpoch(timeMilliseconds, isUtc: true);
    final localTime = DateTime.now();
    print('${DateTime.now()} setTimeAndWeather: icon=$weatherIconId, temp=$temperature, fahrenheit=$useFahrenheit, 12h=$use12HourFormat');
    print('  Time: Local=${localTime.toIso8601String()}, SentAsUTC=${sentTimeUtc.toIso8601String()}, timeSeconds=$timeSeconds, timeMs=$timeMilliseconds, seq=$sequence');
    
    // Send to left arm first
    var retL = await BleManager.request(data, lr: "L", timeoutMs: 1500);
    
    print('${DateTime.now()} setTimeAndWeather L response: ${retL.data.hexString}');
    
    if (retL.isTimeout) {
      print('setTimeAndWeather: Timeout on L');
      return false;
    }
    
    // Validate left response: [0x06, 0x15, 0x00, sequence, subcommand, status]
    // Response format echoes the command header, with status at index 5
    // Status: 0x00 = success, 0xCA or other = failure
    bool leftSuccess = retL.data.length >= 6 &&
        retL.data[0].toInt() == 0x06 &&
        retL.data[1].toInt() == 0x15 &&
        retL.data[3].toInt() == sequence &&
        retL.data[4].toInt() == 0x01 &&
        retL.data[5].toInt() == 0x00;  // Status code at index 5 (0x00 = success)
    
    if (!leftSuccess) {
      print('setTimeAndWeather: Left arm failed - response: ${retL.data.hexString}, expected seq=$sequence');
      return false;
    }
    
    // Send to right arm
    var retR = await BleManager.request(data, lr: "R", timeoutMs: 1500);
    
    print('${DateTime.now()} setTimeAndWeather R response: ${retR.data.hexString}');
    
    if (retR.isTimeout) {
      print('setTimeAndWeather: Timeout on R');
      return false;
    }
    
    // Validate right response
    bool rightSuccess = retR.data.length >= 6 &&
        retR.data[0].toInt() == 0x06 &&
        retR.data[1].toInt() == 0x15 &&
        retR.data[3].toInt() == sequence &&
        retR.data[4].toInt() == 0x01 &&
        retR.data[5].toInt() == 0x00;  // Status code at index 5 (0x00 = success)
    
    if (rightSuccess) {
      print('setTimeAndWeather: Success on both arms');
      return true;
    } else {
      print('setTimeAndWeather: Right arm failed - response: ${retR.data.hexString}, expected seq=$sequence');
      return false;
    }
  }

  static int _dashboardModeSeq = 0;

  /// Set Dashboard Mode
  /// Sets the dashboard display mode (Full, Dual, or Minimal)
  /// 
  /// Based on protocol: Command 0x06 (DASHBOARD_CONFIG) with subcommand 0x06 (SET_DASHBOARD_MODE)
  /// - [modeId]: Mode ID (0x00=Full, 0x01=Dual, 0x02=Minimal)
  /// - [secondaryPaneId]: Optional secondary pane ID (0x00-0x05, default 0x00)
  /// 
  /// Packet format: [0x06, 0x07, 0x00, sequence, 0x06, modeId, secondaryPaneId]
  /// Total length: 7 bytes
  /// 
  /// Returns true if successful (response contains 0xC9 or 0x00 success status)
  /// Sends to both L and R arms
  static Future<bool> setDashboardMode({
    required int modeId,
    int secondaryPaneId = 0x00,
  }) async {
    // Validate mode ID range (0x00 to 0x02)
    if (modeId < 0 || modeId > 0x02) {
      print("setDashboardMode: Invalid mode ID $modeId (must be 0x00-0x02)");
      return false;
    }

    // Validate secondary pane ID range (0x00 to 0x05)
    if (secondaryPaneId < 0 || secondaryPaneId > 0x05) {
      print("setDashboardMode: Invalid secondary pane ID $secondaryPaneId (must be 0x00-0x05)");
      return false;
    }

    // Get sequence number
    final sequence = _dashboardModeSeq++ & 0xFF;

    // Build the command packet
    // Format: [0x06, 0x07, 0x00, sequence, 0x06, modeId, secondaryPaneId]
    // Total: 7 bytes (0x07)
    var data = Uint8List(7);
    data[0] = 0x06;                              // Command: DASHBOARD_CONFIG
    data[1] = 0x07;                              // Length: 7 bytes
    data[2] = 0x00;                              // Padding
    data[3] = sequence;                          // Sequence number
    data[4] = 0x06;                              // Subcommand: SET_DASHBOARD_MODE
    data[5] = modeId & 0xFF;                     // Mode ID (0x00=Full, 0x01=Dual, 0x02=Minimal)
    data[6] = secondaryPaneId & 0xFF;            // Secondary Pane ID (0x00-0x05)

    final modeNames = ['Full', 'Dual', 'Minimal'];
    print('${DateTime.now()} setDashboardMode: mode=${modeNames[modeId]} (0x${modeId.toRadixString(16)}), secondaryPaneId=0x${secondaryPaneId.toRadixString(16)}, seq=$sequence');
    
    // Send to left arm first
    var retL = await BleManager.request(data, lr: "L", timeoutMs: 1500);
    
    print('${DateTime.now()} setDashboardMode L response: ${retL.data.hexString}');
    
    if (retL.isTimeout) {
      print('setDashboardMode: Timeout on L');
      return false;
    }
    
    // Validate left response: [0x06, 0x07, 0x00, sequence, 0x06, status]
    // Status: 0x00 or 0xC9 = success, 0xCA or other = failure
    bool leftSuccess = retL.data.length >= 6 &&
        retL.data[0].toInt() == 0x06 &&
        retL.data[1].toInt() == 0x07 &&
        retL.data[3].toInt() == sequence &&
        retL.data[4].toInt() == 0x06 &&
        (retL.data[5].toInt() == 0x00 || retL.data[5].toInt() == 0xC9);  // Success status
    
    if (!leftSuccess) {
      print('setDashboardMode: Left arm failed - response: ${retL.data.hexString}, expected seq=$sequence');
      return false;
    }
    
    // Send to right arm
    var retR = await BleManager.request(data, lr: "R", timeoutMs: 1500);
    
    print('${DateTime.now()} setDashboardMode R response: ${retR.data.hexString}');
    
    if (retR.isTimeout) {
      print('setDashboardMode: Timeout on R');
      return false;
    }
    
    // Validate right response
    bool rightSuccess = retR.data.length >= 6 &&
        retR.data[0].toInt() == 0x06 &&
        retR.data[1].toInt() == 0x07 &&
        retR.data[3].toInt() == sequence &&
        retR.data[4].toInt() == 0x06 &&
        (retR.data[5].toInt() == 0x00 || retR.data[5].toInt() == 0xC9);  // Success status
    
    if (rightSuccess) {
      print('setDashboardMode: Success on both arms');
      return true;
    } else {
      print('setDashboardMode: Right arm failed - response: ${retR.data.hexString}, expected seq=$sequence');
      return false;
    }
  }

  /// Get Display Settings (0x3B)
  /// Fetches the current screen height and depth values from the glasses
  /// 
  /// This command should be sent to the RIGHT arm only.
  /// Response format: [0x3B, 0xC9, height, depth]
  /// - height: Display height value from 0x00 to 0x08 (0 to 8)
  /// - depth: Display depth value from 0x01 to 0x09 (1 to 9)
  /// 
  /// Returns a map with 'height' and 'depth' keys, or null if failed
  static Future<Map<String, int>?> getDisplaySettings() async {
    var cmd = Uint8List.fromList([0x3B]);
    
    print('${DateTime.now()} getDisplaySettings: Sending 0x3B to right arm...');
    
    // Send to RIGHT arm only as per documentation
    var ret = await BleManager.request(cmd, lr: "R", timeoutMs: 1500);
    
    print('${DateTime.now()} getDisplaySettings response: ${ret.data.hexString}');
    
    if (ret.isTimeout) {
      print('getDisplaySettings: Timeout');
      return null;
    }
    
    // Validate response format: [0x3B, 0xC9, height, depth]
    if (ret.data.length >= 4 &&
        ret.data[0].toInt() == 0x3B &&
        ret.data[1].toInt() == 0xC9) {
      int height = ret.data[2].toInt();
      int depth = ret.data[3].toInt();
      
      // Validate ranges
      if (height >= 0 && height <= 0x08 && depth >= 0x01 && depth <= 0x09) {
        print('getDisplaySettings: Success - height=$height, depth=$depth');
        return {
          'height': height,
          'depth': depth,
        };
      } else {
        print('getDisplaySettings: Invalid values - height=$height (0-8), depth=$depth (1-9)');
        return null;
      }
    } else {
      print('getDisplaySettings: Invalid response format - expected [0x3B, 0xC9, height, depth]');
      return null;
    }
  }

  /// Get Message Stay Time Settings (0x3C)
  /// Fetches the current message enabled status and timeout duration
  /// 
  /// This command should be sent to the LEFT arm only.
  /// Response format: [0x3C, 0xC9, enabled, timeout]
  /// - enabled: Message enabled status (0x00 = disabled, 0x01 = enabled)
  /// - timeout: Timeout duration from 0x00 to 0xFF (0 to 255)
  /// 
  /// Returns a map with 'enabled' (bool) and 'timeout' (int) keys, or null if failed
  static Future<Map<String, dynamic>?> getMessageStayTimeSettings() async {
    var cmd = Uint8List.fromList([0x3C]);
    
    print('${DateTime.now()} getMessageStayTimeSettings: Sending 0x3C to left arm...');
    
    // Send to LEFT arm only as per documentation
    var ret = await BleManager.request(cmd, lr: "L", timeoutMs: 1500);
    
    print('${DateTime.now()} getMessageStayTimeSettings response: ${ret.data.hexString}');
    
    if (ret.isTimeout) {
      print('getMessageStayTimeSettings: Timeout');
      return null;
    }
    
    // Validate response format: [0x3C, 0xC9, enabled, timeout]
    if (ret.data.length >= 4 &&
        ret.data[0].toInt() == 0x3C &&
        ret.data[1].toInt() == 0xC9) {
      int enabledValue = ret.data[2].toInt();
      int timeout = ret.data[3].toInt();
      
      // Validate enabled value (should be 0x00 or 0x01)
      if (enabledValue != 0x00 && enabledValue != 0x01) {
        print('getMessageStayTimeSettings: Invalid enabled value $enabledValue (expected 0x00 or 0x01)');
        return null;
      }
      
      // Validate timeout range (0x00 to 0xFF)
      if (timeout < 0x00 || timeout > 0xFF) {
        print('getMessageStayTimeSettings: Invalid timeout value $timeout (expected 0x00-0xFF)');
        return null;
      }
      
      bool enabled = enabledValue == 0x01;
      print('getMessageStayTimeSettings: Success - enabled=$enabled, timeout=$timeout');
      return {
        'enabled': enabled,
        'timeout': timeout,
      };
    } else {
      print('getMessageStayTimeSettings: Invalid response format - expected [0x3C, 0xC9, enabled, timeout]');
      return null;
    }
  }

  /// Get Head Up Activation Angle Settings (0x32)
  /// Fetches the current head-up activation angle from the glasses
  /// 
  /// This command should be sent to the RIGHT arm only.
  /// Response format: [0x32, 0xC9, angle]
  /// - angle: Head-up activation angle value from 0x00 to 0x42 (0 to 66 degrees)
  /// 
  /// Returns the angle value (0-66), or null if failed
  static Future<int?> getHeadUpAngleSettings() async {
    var cmd = Uint8List.fromList([0x32]);
    
    print('${DateTime.now()} getHeadUpAngleSettings: Sending 0x32 to right arm...');
    
    // Send to RIGHT arm only as per documentation
    var ret = await BleManager.request(cmd, lr: "R", timeoutMs: 1500);
    
    print('${DateTime.now()} getHeadUpAngleSettings response: ${ret.data.hexString}');
    
    if (ret.isTimeout) {
      print('getHeadUpAngleSettings: Timeout');
      return null;
    }
    
    // Validate response format: [0x32, 0xC9, angle]
    if (ret.data.length >= 3 &&
        ret.data[0].toInt() == 0x32 &&
        ret.data[1].toInt() == 0xC9) {
      int angle = ret.data[2].toInt();
      
      // Validate angle range (0x00 to 0x42 = 0 to 66)
      if (angle >= 0 && angle <= 0x42) {
        print('getHeadUpAngleSettings: Success - angle=$angle');
        return angle;
      } else {
        print('getHeadUpAngleSettings: Invalid angle value $angle (expected 0x00-0x42, i.e., 0-66)');
        return null;
      }
    } else {
      print('getHeadUpAngleSettings: Invalid response format - expected [0x32, 0xC9, angle]');
      return null;
    }
  }

  /// Set Brightness Settings (0x01)
  /// Adjust the brightness level or enable/disable auto brightness
  /// 
  /// - [brightness]: Brightness value from 0x00 to 0x2A (0 to 42)
  /// - [autoBrightness]: If true, enable auto brightness (0x01), else manual (0x00)
  /// 
  /// Returns true if successful
  /// Note: This command should be sent to the RIGHT arm only
  static Future<bool> setBrightnessSettings({
    required int brightness,
    required bool autoBrightness,
  }) async {
    // Validate brightness range (0x00 to 0x2A = 0 to 42)
    if (brightness < 0 || brightness > 0x2A) {
      print("setBrightnessSettings: Invalid brightness value $brightness (must be 0x00-0x2A, i.e., 0-42)");
      return false;
    }

    var data = Uint8List.fromList([
      0x01,                              // Command: SET_BRIGHTNESS
      brightness & 0xFF,                 // Brightness value (0x00-0x2A)
      autoBrightness ? 0x01 : 0x00,      // Auto brightness flag (0x00=off, 0x01=on)
    ]);

    print('${DateTime.now()} setBrightnessSettings: brightness=$brightness (0x${brightness.toRadixString(16)}), auto=$autoBrightness');
    
    // Send to RIGHT arm only as per documentation
    var ret = await BleManager.request(data, lr: "R", timeoutMs: 1500);
    
    print('${DateTime.now()} setBrightnessSettings response: ${ret.data.hexString}');
    
    if (ret.isTimeout) {
      print('setBrightnessSettings: Timeout');
      return false;
    }
    
    // Response is generic, so we consider it successful if we get a response
    // Typically responses start with the command byte (0x01)
    if (ret.data.isNotEmpty && ret.data[0].toInt() == 0x01) {
      print('setBrightnessSettings: Success');
      return true;
    }
    
    print('setBrightnessSettings: Unexpected response format');
    return false;
  }
}
