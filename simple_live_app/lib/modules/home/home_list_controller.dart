import 'dart:async';

import 'package:get/get.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/services/douyin_account_service.dart';
import 'package:simple_live_app/services/follow_service.dart';
import 'package:simple_live_core/simple_live_core.dart';

/// 首页单站点列表。
///
/// 抖音没有真正意义上的“推荐”接口，这里在客户端做一层编排：
/// - 第一页：先放「我的关注」，再用热门房间补满；
///   * 已登录抖音账号 → 关注来自账号关注流（webcast/web/feed/follow）；
///   * 未登录 → 回退到 App 内的关注列表；
/// - 后续页：只放热门房间（按在线人数排序）；
/// - 跨页去重，避免上拉加载出现重复卡片。
class HomeListController extends BasePageController<LiveRoomItem> {
  final Site site;

  HomeListController(this.site);

  /// 已经展示过的房间，用于跨页去重
  final Set<String> _seenRoomIds = {};

  bool get _isDouyin => site.id == Constant.kDouyin;

  @override
  Future<void> refreshData() async {
    _seenRoomIds.clear();
    await super.refreshData();
  }

  @override
  Future<List<LiveRoomItem>> getData(int page, int pageSize) async {
    if (!_isDouyin) {
      var result = await site.liveSite.getRecommendRooms(page: page);
      return result.items;
    }

    var hot = await _recommendRooms(page);

    // 非首页只展示热门，避免关注房间被重复塞进每一页
    if (page != 1) {
      return _takeUnique(_sortedByHot(hot), pageSize);
    }

    var followed = await _followedRooms();
    if (followed.isEmpty && !DouyinAccountService.instance.logined.value) {
      // 未登录时用的是本地关注，状态可能还没刷新过，后台补一次（最多 8 个）
      unawaited(FollowService.instance.refreshStatusForSite(Constant.kDouyin));
    }

    // 关注在前，热门补齐；_takeUnique 负责写去重集合并截断
    var items = <LiveRoomItem>[];
    items.addAll(_takeUnique(followed, pageSize));
    if (items.length < pageSize) {
      items.addAll(
        _takeUnique(_sortedByHot(hot), pageSize, skip: items.length),
      );
    }
    return items;
  }

  /// 「推荐」数据源：
  /// 优先用抖音登录态推荐流（webcast/feed，登录后带账号画像），
  /// 失败再回退到公开分区聚合（按人气排序）。
  Future<List<LiveRoomItem>> _recommendRooms(int page) async {
    if (site.liveSite is DouyinSite) {
      try {
        var feed = await (site.liveSite as DouyinSite).getRecommendFeed(page: page);
        if (feed.items.isNotEmpty) {
          return feed.items;
        }
      } catch (e) {
        // 忽略，走分区兜底
      }
    }
    var fallback = await site.liveSite.getRecommendRooms(page: page);
    return fallback.items;
  }

  /// 「我的关注」数据源：
  /// 已登录抖音账号时优先用账号关注流，失败或未登录则回退到本地关注列表。
  Future<List<LiveRoomItem>> _followedRooms() async {
    if (DouyinAccountService.instance.logined.value &&
        site.liveSite is DouyinSite) {
      try {
        var result = await (site.liveSite as DouyinSite).getFollowRooms();
        if (result.items.isNotEmpty) {
          return result.items;
        }
      } catch (e) {
        // 登录态失效/接口异常时静默回退
      }
    }
    return _liveFollowedRooms();
  }

  /// 取用户关注里正在直播的房间，按加入时间倒序（最近关注的在前）
  List<LiveRoomItem> _liveFollowedRooms() {
    if (!Get.isRegistered<FollowService>()) {
      return const [];
    }
    var list = FollowService.instance.followList
        .where((e) => e.siteId == site.id && e.liveStatus.value == 2)
        .toList();
    list.sort((a, b) => b.addTime.compareTo(a.addTime));
    return list
        .map(
          (e) => LiveRoomItem(
            roomId: e.roomId,
            title: e.userName,
            cover: e.face,
            userName: e.userName,
            isFollowed: true,
          ),
        )
        .toList();
  }

  /// 按在线人数降序（热门优先）
  List<LiveRoomItem> _sortedByHot(List<LiveRoomItem> items) {
    return [...items]..sort((a, b) => b.online.compareTo(a.online));
  }

  /// 依次取房间写入去重集合，直到凑满 [limit]；
  /// [skip] 表示前面已经占了几个名额（用于关注 + 热门拼接）。
  List<LiveRoomItem> _takeUnique(
    List<LiveRoomItem> items,
    int limit, {
    int skip = 0,
  }) {
    var out = <LiveRoomItem>[];
    for (var item in items) {
      if (skip + out.length >= limit) break;
      if (item.roomId.isEmpty) continue;
      if (_seenRoomIds.add(item.roomId)) {
        out.add(item);
      }
    }
    return out;
  }
}
