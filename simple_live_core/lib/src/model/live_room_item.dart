import 'dart:convert';

class LiveRoomItem {
  /// 房间ID
  final String roomId;

  /// 标题
  final String title;

  /// 封面
  final String cover;

  /// 用户名
  final String userName;

  /// 人气/在线人数
  final int online;

  /// 是否来自用户关注列表（首页推荐里用来置顶展示）
  final bool isFollowed;

  LiveRoomItem({
    required this.roomId,
    required this.title,
    required this.cover,
    required this.userName,
    this.online = 0,
    this.isFollowed = false,
  });

  @override
  String toString() {
    return json.encode({
      "roomId": roomId,
      "title": title,
      "cover": cover,
      "userName": userName,
      "online": online,
      "isFollowed": isFollowed,
    });
  }
}
