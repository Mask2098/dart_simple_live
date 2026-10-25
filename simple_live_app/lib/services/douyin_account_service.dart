import 'package:get/get.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/services/local_storage_service.dart';
import 'package:simple_live_core/simple_live_core.dart';

class DouyinAccountService extends GetxService {
  static DouyinAccountService get instance =>
      Get.find<DouyinAccountService>();

  var cookie = "";

  /// 是否配置了自定义 cookie（ttwid 或完整登录 cookie）
  var hasCookie = false.obs;

  /// 是否带登录态（含 sessionid），只有登录后才拿得到"账号关注流"
  var logined = false.obs;

  @override
  void onInit() {
    cookie = LocalStorageService.instance
        .getValue(LocalStorageService.kDouyinCookie, "");
    hasCookie.value = cookie.isNotEmpty;
    logined.value = _hasSession(cookie);
    setSite();
    super.onInit();
  }

  bool _hasSession(String value) {
    var text = value.toLowerCase();
    return text.contains("sessionid=") || text.contains("sessionid_ss=");
  }

  void setSite() {
    var site = (Sites.allSites[Constant.kDouyin]!.liveSite as DouyinSite);
    site.cookie = cookie;
  }

  void setCookie(String cookie) {
    this.cookie = cookie;
    LocalStorageService.instance
        .setValue(LocalStorageService.kDouyinCookie, cookie);
    hasCookie.value = cookie.isNotEmpty;
    logined.value = _hasSession(cookie);
    setSite();
  }

  void clearCookie() {
    cookie = "";
    LocalStorageService.instance
        .setValue(LocalStorageService.kDouyinCookie, "");
    hasCookie.value = false;
    logined.value = false;
    setSite();
  }
}
