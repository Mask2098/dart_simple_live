import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/services/douyin_account_service.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

/// 抖音网页登录：在 WebView 里扫码/密码登录后，
/// 读取 douyin.com 域的 cookie（含 sessionid）保存到本地，
/// 之后就能调用「账号关注流」接口。
class DouyinWebLoginController extends BaseController {
  InAppWebViewController? webViewController;
  final CookieManager cookieManager = CookieManager.instance();

  static const String loginUrl = "https://www.douyin.com/";

  void onWebViewCreated(InAppWebViewController controller) {
    webViewController = controller;
    webViewController!.loadUrl(
      urlRequest: URLRequest(url: WebUri(loginUrl)),
    );
  }

  void onLoadStop(InAppWebViewController controller, Uri? uri) async {
    if (uri == null) return;
    await trySaveCookies(silent: true);
  }

  /// 读取并保存 cookie；[silent] 为 true 时扫码未完成不提示。
  Future<bool> trySaveCookies({bool silent = false}) async {
    try {
      var cookies = await cookieManager.getCookies(
        url: WebUri("https://live.douyin.com"),
      );
      var names = cookies.map((e) => e.name).toSet();
      if (!names.contains("sessionid") && !names.contains("sessionid_ss")) {
        if (!silent) {
          SmartDialog.showToast("还没登录成功，请先在页面里完成登录");
        }
        return false;
      }
      var cookieStr = cookies.map((e) => "${e.name}=${e.value}").join("; ");
      Log.i("抖音登录 cookie 长度：${cookieStr.length}");
      DouyinAccountService.instance.setCookie(cookieStr);
      SmartDialog.showToast("抖音账号登录成功");
      Get.back();
      return true;
    } catch (e) {
      Log.logPrint(e);
      if (!silent) {
        SmartDialog.showToast("读取登录状态失败");
      }
      return false;
    }
  }
}
