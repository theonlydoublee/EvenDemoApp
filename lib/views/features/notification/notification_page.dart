// ignore_for_file: library_private_types_in_public_api

import 'package:demo_ai_even/g1_manager_wrapper.dart';
import 'package:demo_ai_even/views/features/notification/notify_model.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';

class NotificationPage extends StatefulWidget {
  const NotificationPage({super.key});

  @override
  _NotificationState createState() => _NotificationState();
}

class _NotificationState extends State<NotificationPage> {
  //
  final FocusNode identifierFn = FocusNode();
  late TextEditingController identifierCtl;
  //
  final FocusNode contentFn = FocusNode();
  late TextEditingController contentCtl;
  //  Whitelist
  String appWhitelist = "";
  bool isSetting = false;
  //  Content
  String notifyContent = "";
  int notifyId = 0;
  bool isSending = false;
  
  G1ManagerWrapper get _g1 => G1ManagerWrapper.instance;

  @override
  void initState() {
    //  1、Init app whitelist
    final evenModel = NotifyAppModel("com.even.test", "Even");
    final youToBeModel =
        NotifyAppModel("com.google.android.youtube", "YouToBe");
    appWhitelist = NotifyWhitelistModel([evenModel, youToBeModel]).toShowJson();
    identifierCtl = TextEditingController(text: appWhitelist);
    //  2、Init notify content
    final testNotify = NotifyModel(
      1234567890,
      evenModel.identifier,
      "Even Realities",
      "Notify",
      "This is a notification",
      DateTime.now().millisecondsSinceEpoch,
      "Even",
    );
    notifyContent = testNotify.toJson();
    contentCtl = TextEditingController(text: notifyContent);
    super.initState();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Notification'),
        ),
        body: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              //  App whitelist info
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.orange),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Note: Whitelist is managed locally. Use the main Notification Whitelist page to configure.',
                        style: TextStyle(color: Colors.orange, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              //  Notify edit
              Container(
                width: double.infinity,
                height: 150,
                margin: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(5),
                ),
                padding: const EdgeInsets.all(8),
                child: TextField(
                  decoration: const InputDecoration.collapsed(hintText: ""),
                  focusNode: contentFn,
                  controller: contentCtl,
                  onChanged: (newNotify) => notifyContent = newNotify,
                  maxLines: null,
                ),
              ),
              GestureDetector(
                onTap: !_g1.isConnected || isSending
                    ? null
                    : () async {
                        final newNotify = NotifyModel.fromJson(notifyContent);
                        if (newNotify == null) {
                          Fluttertoast.showToast(
                              msg:
                                  "Json conversion error, please check and retry");
                          return;
                        }
                        setState(() => isSending = true);
                        notifyId++;
                        if (notifyId > 255) {
                          notifyId = 0;
                        }
                        try {
                          // Send notification using library
                          await _g1.g1.notifications.sendSimple(
                            appName: newNotify.displayName,
                            title: newNotify.title,
                            message: newNotify.message,
                            subtitle: newNotify.subTitle,
                            appIdentifier: newNotify.appIdentifier,
                          );
                          Fluttertoast.showToast(msg: "Notification sent successfully");
                        } catch (e) {
                          Fluttertoast.showToast(msg: "Error sending notification: $e");
                        }
                        setState(() => isSending = false);
                      },
                child: Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    isSending ? "Sending" : "Send notify",
                    style: TextStyle(
                      color: _g1.isConnected
                          ? Colors.black
                          : Colors.grey,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}
