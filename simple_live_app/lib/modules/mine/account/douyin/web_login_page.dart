import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/modules/mine/account/douyin/web_login_controller.dart';

class DouyinWebLoginPage extends GetView<DouyinWebLoginController> {
  const DouyinWebLoginPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("抖音账号登录"),
        actions: [
          TextButton(
            onPressed: () => controller.trySaveCookies(),
            child: const Text("完成登录"),
          ),
        ],
      ),
      body: InAppWebView(
        onWebViewCreated: controller.onWebViewCreated,
        onLoadStop: controller.onLoadStop,
        initialSettings: InAppWebViewSettings(
          userAgent:
              "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36 Edg/125.0.0.0",
          useShouldOverrideUrlLoading: false,
          thirdPartyCookiesEnabled: true,
          domStorageEnabled: true,
        ),
      ),
    );
  }
}
