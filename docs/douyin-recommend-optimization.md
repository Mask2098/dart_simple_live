# 抖音「推荐」实现分析与优化方案

> 分析对象：`D:\src\simple_live`（SimpleLive / GPL-3.0）
> 范围：`simple_live_core/lib/src/douyin_site.dart` 的推荐相关实现、签名依赖，以及 `simple_live_app` 首屏消费链路
> 说明：本文所有结论均来自源码阅读与线上接口实测（2026-10-25），不含猜测性描述

---

## 1. 现状：它到底怎么"推荐"

### 1.1 调用链

```
HomePage (TabBar: 虎牙/斗鱼/B站/抖音)
  └─ HomeListView(siteId)
       └─ HomeListController.getData(page, pageSize)      home_list_controller.dart:11
            └─ DouyinSite.getRecommendRooms(page: page)   douyin_site.dart:232
                 └─ _getPartitionRooms() × N              douyin_site.dart:141
                      └─ DouyinSign.getAbogusUrl()        douyin_sign.dart:10650+
                      └─ GET live.douyin.com/webcast/web/partition/detail/room/v2/
```

TV 端 `simple_live_tv_app/lib/modules/hot_live/hot_live_controller.dart:35` 复用同一个接口，**改动会同时影响两端**。

### 1.2 改造前（上游 master）

```dart
// 改造前 douyin_site.dart:184-236
"count": '15',
"offset": ((page - 1) * 15).toString(),
"partition": '720',        // 写死
"partition_type": '1',
```

- 本质是**"分区 720 的房间列表"**，不是推荐流；
- 单页 15 条，`hasMore = list.length >= 15`；
- 分区 720 是历史遗留 id。实测抖音直播首页当前分类表已不含 720：

| 一级分区 id | 名称 | 二级分类 |
|---|---|---|
| 101 | 聊天 | — |
| 102 | 音乐 | — |
| 103 | 游戏 | 三角洲行动 / 王者荣耀 / 无畏契约 / 英雄联盟 / 和平精英 / 火影忍者手游 / 绝地求生 / 金铲铲之战 |
| 104 | 二次元 | — |
| 105 | 舞蹈 | — |
| 106 | 文化 | — |
| 107 | 生活 | — |
| 108 | 运动 | — |

所以旧实现"只推荐几个"的根因是**数据源窄**：一个可能已半废弃的分区，翻两页见底就停。

### 1.3 改造后（当前工作副本）

`douyin_site.dart:121-279`：

- `kRecommendPartitions`：9 个分区（`720,1` + `101~108,4`）；
- `_getPartitionRooms()`：统一的请求 + 解析（`room/web_rid/cover/owner/room_view_stats`，缺字段不再抛异常）；
- `getRecommendRooms(page)`：
  - 每页取 **3 个分区**，按页码轮转；
  - 分区池轮完一圈（3 页）后 `offset += 15`；
  - 结果按分区 **round-robin 交错**并用 `web_rid` 去重；
  - `hasMore = 任一分区返回满 15 条`。
- `douyin_sign.dart:10652-10709`：QuickJS 运行时改为懒加载单例，否则每页 3 个并发签名会各付一次 641 KB 脚本 eval。

效果：单页从 15 条提升到最多 45 条，分区从 1 个扩展到 9 个。

---

## 2. 问题清单（按影响排序）

| # | 问题 | 证据 | 影响 |
|---|---|---|---|
| P1 | **语义错位**：本质是"多分区轮播"，没有任何个性化（用户兴趣、历史、关注）参与 | `douyin_site.dart:232-279` | 与"推荐"预期不符；每个用户看到同一批房间 |
| P2 | **分区池硬编码**：抖音改版/分区下线后静默失效，720 已是例子 | `douyin_site.dart:123-133` | 失效无告警，只能等用户反馈"没内容" |
| P3 | **页大小与客户端不匹配**：站点一页最多 45 条，客户端 `pageSize=24` 只作为形参传递，实际未被站点使用 | `base_controller.dart:60`、`home_list_controller.dart:11` | 首屏一次渲染 45 个卡片，弱机滚动压力大；分页节奏不可控 |
| P4 | **`hasMore` 从未被消费**：全仓仅 3 处定义、0 处读取，客户端靠"返回空列表"判断结束 | `live_category_result.dart:7`；`base_controller.dart:85-95` | 各站点终止条件不一致（B站30/斗鱼6/抖音15~45），行为不可预期 |
| P5 | **offset 分页天然重复**：直播列表实时变化，翻页插入新房间会导致错位；去重只在单页内做 | `douyin_site.dart:246-272` | 跨页重复卡片、漏内容 |
| P6 | **无失败降级**：某分区异常时该批为空，整页只剩 2 个分区的量；没有健康度记忆 | `douyin_site.dart:242-252` | 页大小腰斩且持续到下次重启 |
| P7 | **无排序权重**：交错顺序 = 分区数组顺序，固定不变；人气字段 `online` 只展示不参与排序 | `douyin_site.dart:256-273` | "热门"房间可能被排在小分区之后 |
| P8 | **无缓存/无预取**：每次翻页 3 个 RTT；下拉刷新必打满 | `douyin_site.dart:232-252` | 弱网首屏慢，快速切 tab 会产生重复请求 |
| P9 | **无并发/重入保护**（客户端侧）：`loadData` 无锁，快速下拉可能叠请求 | `base_controller.dart:66-101` | 重复请求、列表重复追加 |
| P10 | **无观测**：没有分区级成功/耗时/条数统计 | — | 出问题只能靠猜 |

---

## 3. 优化方案

### 3.1 A 档：低风险、当天可做

**A1 分区池外置 + 自愈**
- 从 `getCategores()`（`douyin_site.dart:67-119`）动态取一级分区，失败时回退到现有硬编码；
- 启动后异步探测一次各分区首屏条数，连续返回 0 的分区打入黑名单（如 720），10 分钟后重试；
- 收益：抖音改版不再静默失效。改动量：中（约 80 行）。

**A2 页大小对齐**
- 方案一：每页 2 个分区（30 条），贴近客户端 `pageSize=24` 的观感；
- 方案二：把 `pageSize` 透传进 `getRecommendRooms`，站点按 `min(pageSize, 15×N)` 决定拉几个分区；
- 推荐方案二——接口签名改为 `getRecommendRooms({int page = 1, int pageSize = 24})`，其它站点可忽略参数，向后兼容。

**A3 分区健康度**
- 内存表 `partitionHealth: {id: {ok, fail, lastFailAt}}`；
- 连续失败 3 次 → 跳过 10 分钟；成功后清零；
- 收益：P6 消除，单分区故障不再影响整页。

**A4 请求去重 + 短 TTL 缓存**
- key = `douyin:recommend:{page}`，TTL 5 秒；下拉刷新传 `force: true` 绕过；
- 收益：切 tab / 误触刷新不再打网络。改动量：小（约 30 行）。

**A5 排序与多样性**
- 组内按 `online` 降序，再按"每分区最多连续 2 条"做交错（而不是纯轮转）；
- 保留 1 条"低人气长尾"位置，避免首屏全是十万+大主播；
- 收益：P7 消除，观感更像推荐。

### 3.2 B 档：需要产品判断（0.5–2 天）

**B1 游标分页替代 offset**
- 游标 = `(partitionId, offset, seenRoomIds)`；请求前带上已见集合，返回后过滤；
- 或改用接口返回的 `cursor`/`has_more` 字段（需抓包确认字段名）；
- 收益：P5 消除；改动涉及接口签名与客户端状态，需回归。

**B2 兴趣加权**
- 数据源：`DBService.historyBox`（观看历史，`live_room_controller.dart:516-536` 写入）；
- 统计用户在各分区的观看次数 → 生成权重表（如 游戏 3.0、音乐 1.0）；
- 按权重分配每页的分区配额与排序；
- 收益：从"轮播"变成"弱个性化"；无隐私外传，纯本地计算。

**B3 预取与增量加载**
- 首屏渲染完成后，空闲时预取第 2 页；
- 列表滚动到 70% 时提前触发下一页（当前是触底才加载）；
- 收益：翻页等待感消失；代价是流量增加约 1 页。

**B4 探索真正的推荐源**
- 候选：`/webcast/web/feed/`（关注/推荐流）、热门榜、`/webcast/web/partition/detail/room/v2/` 的 `req_from` 变体；
- 做法：抓包验证后在 `DouyinSite` 内加开关，默认走分区聚合，命中率高时再切；
- 风险：需要签名参数配合，且随时可能被风控；必须保留现有路径作为 fallback。

**B5 客户端体验修复**
- `hasMore` 接入分页判断（P4）：`canLoadMore = result.hasMore`；
- `loadData` 加重入锁（P9）；
- tab 切换保留列表与滚动位置（现在是重建）；
- 空页与错误页区分展示。

### 3.3 C 档：架构级（可选）

- **C1 本地推荐服务化**：把"聚合 + 去重 + 排序 + 兴趣"收敛到 app 内的 shelf 服务（项目已有 `shelf` 依赖），客户端只取最终列表，便于 A/B 与缓存；
- **C2 埋点**：曝光/点击/停留时长，用于调分区权重；
- **C3 房间元数据缓存**：`roomId → detail` 加 TTL 缓存，减少重复请求。

---

## 4. 风险与合规

- 抖音 webcast 接口无公开文档，分区 id 与签名算法（`a_bogus`）随时可能变；任何改动都必须保留"单分区旧路径"作为兜底。
- 并发 3 个请求已接近常见风控阈值，**不建议再提高**；A4 缓存与 A3 降级反而应减少请求。
- 本项目 README 明确"仅用于学习交流"，避免高频抓取与批量分发。

---

## 5. 验收指标

| 指标 | 当前 | 目标 |
|---|---|---|
| 首屏可见房间数 | 15（旧）/ ≤45（新） | ≥30 |
| 翻页重复率 | 未统计 | <5% |
| 单页 P95 耗时 | 3 个 RTT（签名已缓存） | <1.5s |
| 单分区故障影响 | 整页腰斩 | 0（自动降级） |
| 分区失效发现时间 | 用户反馈 | 自动探测（1 次启动内） |

---

## 6. 建议执行顺序

1. **A3 + A4 + A2**（半天，风险最低，先止血）
2. **A1 + A5**（一天，解决"分区失效"与"排序固定"）
3. **B5 + B3**（一天，客户端体验）
4. **B2**（两天，需要观看历史数据积累）
5. **B1 / B4**（按需，需抓包与回归）

---

## 7. 实施记录（2026-10-25）

本轮先落地了"关注优先 + 热门兜底"，对应上文 A5 / P7 / P1 的一部分：

| 文件 | 改动 |
|---|---|
| `simple_live_core/lib/src/model/live_room_item.dart` | 新增 `isFollowed` 字段（默认 false），供卡片打"关注"角标 |
| `simple_live_core/lib/src/douyin_site.dart:123-137` | 分区池重排：游戏/音乐/聊天/二次元/舞蹈/文化/生活/运动，720 降为最后兜底 |
| `simple_live_core/lib/src/douyin_site.dart:275` | 聚合结果按 `online` 降序，保证是"热门"而不是"分区顺序" |
| `simple_live_app/lib/modules/home/home_list_controller.dart` | 抖音首页：先放"已关注且直播中"的房间（按关注时间倒序），再用热门补满 `pageSize`；跨页 `_seenRoomIds` 去重；非抖音站点行为不变 |
| `simple_live_app/lib/services/follow_service.dart:225-270` | 抽出 `_refreshItem()`，新增 `refreshStatusForSite(siteId, limit: 8)`：首页发现没有可用关注时后台补一次抖音关注状态，且不打乱整体轮询计数 |
| `simple_live_app/lib/widgets/live_room_card.dart:39-63` | 关注来源的卡片左上角显示"关注"角标 |

验证：`flutter analyze lib`（app）= No issues found；`dart analyze lib`（core）= 13 条既有告警（全部在 `model/tars/*` 生成代码），本次改动 0 告警。

**尚未实现**：基于观看历史的兴趣加权（B2）、游标分页（B1）、预取（B3）。当前"历史关联"仅在"关注列表"这一层间接体现。

---

## 8. 客户端消费链路的深层问题（补充审查）

首页链路是「`TabBarView` 懒构建 → `HomeListView` → `KeepAliveWrapper` → `PageGridView(firstRefresh: true)` → `EasyRefresh.callRefresh` → `BasePageController.refreshData → loadData → getData`」。控制器在 `HomeController.onInit` 里一次性 `Get.put` 四个站点（`home_controller.dart:32-34`），切 tab 不重建、不刷新。在此基础上还有几处比"条数少"更值得修的问题：

| # | 问题 | 证据 | 影响 |
|---|---|---|---|
| C1 | **刷新与加载更多有竞态**：`refreshData` 先清空 `list`、置 `currentPage=1` 再请求；`loadData` 遇到 `loadding` 直接 return，不排队不取消；响应回来用"当前"的 `currentPage` 决定覆盖还是追加 | `base_controller.dart:64-96` | 第 2 页加载中途点刷新 → 第 1 页丢失、只剩第 2 页，或直接空白 |
| C2 | **`hasMore` 全链路被丢弃**：`LiveCategoryResult.hasMore` 在四个站点都算好了，但 `HomeListController`/`CategoryDetailController` 只返回 `items`，`loadData` 用"本页非空"判断 | `home_list_controller.dart:11`、`base_controller.dart:81-90`、各 site 的 hasMore 赋值 | 斗鱼按 `type!=1` 过滤后可能整页空但仍有更多 → 提前终止且无法恢复 |
| C3 | **`canLoadMore=false` 不阻止请求**：`loadData` 只检查 `loadding`，不检查 `canLoadMore`；也没有 `finishLoad(noMore: true)` | `base_controller.dart:70-72`、`page_grid_view.dart:51` | 列表到底后每次越界都重复请求同一页 |
| C4 | **`pageSize=24` 是死契约**：core 接口只有 `page`，没有 `pageSize` | `live_site.dart:41-52`、`base_controller.dart:60` | 实际每页 15/30/45 条由站点决定；不能拿"少于 24 条"当最后一页 |
| C5 | **整树 Obx 重建**：`PageGridView.build` 用一个 `Obx` 包住 `Stack`，读取 `list/canLoadMore/pageLoadding/pageEmpty/pageError/errorMsg` 六个状态，每次 load 都重建整个 `MasonryGridView`，且每次 build 都新建 header/footer | `page_grid_view.dart:38-125`、`:41-47` | 45 条批次下滚动/刷新更容易掉帧 |
| C6 | **跨页无去重、列表无 key**：`list.addAll` 直接追加，`LiveRoomItem` 没有 `==`，itemBuilder 没有 `ValueKey(roomId)` | `base_controller.dart:95`、`home_list_view.dart:28-31` | 榜单变化时跨页重复；复用错位导致图片重载 |

> C1–C3 是同一组基础问题，收益最高；C4 需要改 core 接口（与 3.1 的 A2 合并做最省事）；C5/C6 可独立进行。

---

## 9. 运行验证记录（2026-10-25）

Windows 构建打通后做了两轮实测。

### 9.1 核心接口（命令行）

```
page 1 -> 45 rooms, hasMore=true, 1392ms, top online=[27277, 12894, 10178]
page 2 -> 44 rooms, hasMore=true,  356ms, top online=[46140035, 82031, 80311]
```

- 单页从 15 条提升到 45/44 条；
- 严格按 `online` 降序，第二页头部是 4614 万的周年庆；
- 第二次 356ms vs 首次 1392ms，QuickJS 运行时复用生效。

### 9.2 客户端联调时发现并修复的 Bug

首次在 App 里打开抖音 tab 时列表为空（"这里什么都没有"），而命令行同样代码返回 45 条。加临时日志后定位到：接口返回正常（`status_code=0`、每个分区 15 条），问题出在 `HomeListController` 自身的去重逻辑——

原实现 `_pickHot()` 在筛选时就把 `roomId` 写进了 `_seenRoomIds`，外层拼接循环再检查一次时全部命中"已存在"，45 条被自己过滤成 0 条。

修复（`home_list_controller.dart`）：拆成 `_sortedByHot()`（只排序）和 `_takeUnique()`（唯一负责写去重集合并截断），关注与热门两条来源都走同一个 `_takeUnique`，用 `skip` 参数拼接。

修复后 App 内实测：抖音 tab 正常渲染 24 张卡片（`pageSize` 生效），人气从 2.6 万递减，符合"热门优先"预期。

### 9.3 验证方法备忘

- 默认 tab 是哔哩哔哩，脚本点击 tab 在这台机器上不生效（合成鼠标事件被忽略），临时把 `HomeController` 的 `TabController.initialIndex` 指向抖音验证，验证后已还原；
- 应用内网络日志会打印每个 `[HTTP Request]`/`[HTTP Response]`，排查空列表时最有效：先确认请求发出、状态码、响应体结构，再怀疑自己的解析/去重代码。

---

## 10. 抖音账号关注流接入（2026-10-25）

### 10.1 接口

网页版「关注」tab 实际请求的是 **`https://live.douyin.com/webcast/feed/follow_top/`**，
不是 `/webcast/web/feed/follow/`（后者恒返回 `10011 Request params error`）。

必带参数（缺任一项都可能 10011）：

```
enter_source=homepage_pc_followtop
source_key=web_homepage_follow_top
follow_session_id=0
need_pinned_info=0
need_map=1
webcast_version_code=170400
version_code=170400
```

其余为常规 webcast 参数（aid / app_name / live_id / device_platform / screen_* / browser_* / os_*）+ `count`、`offset`。

### 10.2 三个坑

1. **路径**：`/webcast/web/feed/follow/` 存在但恒 10011；正确路径是 `/webcast/feed/follow_top/`。
2. **UA 必须与参数里的 `browser_name` / `browser_version` 一致**：参数写 Chrome、实际用默认 QQBrowser UA 时，
   接口返回 `status_code=0` 但列表为空——不报错，最难查。
3. **响应结构不稳定**：有时 `{"data": [...]}`，有时 `{"data": {"data": [...]}}`，解析要两种都兼容。

### 10.3 字段映射

`data[].data` 里是房间对象：

| 字段 | 用途 |
|---|---|
| `id_str` | 房间号（19 位，可直接给 `getRoomDetail`） |
| `title` | 标题 |
| `cover.url_list[0]` | 封面 |
| `owner.nickname` | 主播名 |
| `room_view_stats.display_value` | 在线人数（回退 `user_count`） |

### 10.4 登录态

`DouyinAccountService` 只负责存 cookie；新增「网页登录」页（WebView2 打开 `www.douyin.com`），
登录成功后从 `live.douyin.com` 域读取全部 cookie，只要含 `sessionid` / `sessionid_ss` 即视为已登录。

首页逻辑：已登录优先用账号关注流，拉空或失败再回退到 App 内关注列表；未登录行为不变。

### 10.5 验证结果

- `status_code=0`，首屏返回 **15 个关注直播间**（`count=15`），卡片左上角带「关注」角标；
- 抖音 tab 分区为 `我的关注 15 个直播间` + `推荐直播 21 个直播间`（关注在前，推荐补齐并自动续页）。

---

## 11. 「热门」的真实逻辑与替换（2026-10-25）

### 11.1 之前为什么会"和账号无关"

原来的「热门直播」是：

```
getRecommendRooms() → 并发拉 3 个公开分区（游戏/音乐/聊天/二次元…）
                    → 合并去重 → 按 online 人数降序
```

这是**全站公共分区 + 人气排序**，完全没有任何账号因素，所以和抖音账号的推荐必然无关。
它只是"全站热门"，不是"给你的推荐"。

### 11.2 换成真正的推荐流

抖音首页推荐 tab 用的是 **`https://live.douyin.com/webcast/feed/`**：

- 未登录也能拿到一份公共推荐；
- 登录后会带上 cookie 画像，返回内容明显更贴近该账号（实测首条就是该账号关注的主播）；
- 响应结构与 `follow_top` 一致：`data[].data`，字段同 10.3。

现在 `HomeListController` 的取值顺序是：

```
1. 我的关注：账号关注流（follow_top）→ 失败回退 App 内关注
2. 推荐直播：webcast/feed（个性化）→ 失败回退分区聚合（按人气）
```

分区聚合降级为兜底，界面标题也从「热门直播」改成「推荐直播」。

### 11.3 仍然和手机 App 有差距的原因

- 我们只取 web 端推荐流的第 1~2 页，没有"曝光 → 点击/停留 → 换一批"的闭环；
- 没有"不感兴趣"、观看时长等反馈信号，个性化只来自 cookie 画像；
- 所以它比原来的"分区热门"贴近很多，但仍不等于抖音 App 的完整推荐算法。

---
