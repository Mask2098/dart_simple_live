import 'dart:io';

import 'package:flutter/material.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';
import 'package:simple_live_app/widgets/status/app_empty_widget.dart';
import 'package:simple_live_app/widgets/status/app_error_widget.dart';
import 'package:simple_live_app/widgets/status/app_loadding_widget.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:flutter_easyrefresh/easy_refresh.dart';
import 'package:get/get.dart';

class PageGridView extends StatelessWidget {
  final BasePageController pageController;
  final IndexedWidgetBuilder itemBuilder;
  final EdgeInsets? padding;
  final bool firstRefresh;
  final Function()? onLoginSuccess;
  final bool showPageLoadding;
  final double crossAxisSpacing, mainAxisSpacing;
  final int crossAxisCount;
  final bool showPCRefreshButton;

  /// 可选：按条目返回分区标题，传入后会以「分组 + 标题」的方式渲染。
  /// 目前只有抖音首页用它把「我的关注」和「热门直播」分开。
  final String? Function(dynamic item)? sectionOf;

  const PageGridView({
    required this.itemBuilder,
    required this.pageController,
    this.padding,
    this.firstRefresh = false,
    this.showPageLoadding = false,
    this.onLoginSuccess,
    this.crossAxisSpacing = 0.0,
    this.mainAxisSpacing = 0.0,
    this.showPCRefreshButton = true,
    this.sectionOf,
    required this.crossAxisCount,
    Key? key,
  }) : super(key: key);

  /// 把 [pageController.list] 按 [sectionOf] 切成有序分组，生成带标题的 sliver。
  ///
  /// 分组保持原列表顺序，itemBuilder 仍然接收全局下标，
  /// 因此「关注在前、热门在后」这种连续分段可以安全映射。
  List<Widget> _buildSectionSlivers(BuildContext context) {
    var groups = <String, List<dynamic>>{};
    for (var item in pageController.list) {
      var title = sectionOf!(item) ?? "";
      groups.putIfAbsent(title, () => []).add(item);
    }

    var slivers = <Widget>[];
    groups.forEach((title, items) {
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
            child: Row(
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  "${items.length} 个直播间",
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).hintColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      slivers.add(
        SliverPadding(
          padding: padding ?? EdgeInsets.zero,
          sliver: SliverMasonryGrid.count(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: crossAxisSpacing,
            mainAxisSpacing: mainAxisSpacing,
            childCount: items.length,
            itemBuilder: (context, index) {
              // 用对象身份回查全局下标，避免分组下标与列表下标错位
              var item = items[index];
              var globalIndex =
                  pageController.list.indexWhere((e) => identical(e, item));
              return itemBuilder(
                context,
                globalIndex < 0 ? index : globalIndex,
              );
            },
          ),
        ),
      );
    });
    return slivers;
  }

  Widget _buildContent(BuildContext context) {
    if (sectionOf == null) {
      return MasonryGridView.count(
        padding: padding,
        itemCount: pageController.list.length,
        itemBuilder: itemBuilder,
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: crossAxisSpacing,
        mainAxisSpacing: mainAxisSpacing,
      );
    }
    return CustomScrollView(
      slivers: _buildSectionSlivers(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => Stack(
        children: [
          EasyRefresh(
            header: MaterialHeader(
              completeDuration: const Duration(milliseconds: 400),
            ),
            footer: MaterialFooter(
              completeDuration: const Duration(milliseconds: 400),
            ),
            scrollController: pageController.scrollController,
            controller: pageController.easyRefreshController,
            firstRefresh: firstRefresh,
            onLoad: pageController.loadData,
            onRefresh: pageController.refreshData,
            child: _buildContent(context),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: // 加载更多按钮
                Visibility(
              visible: (Platform.isWindows ||
                      Platform.isLinux ||
                      Platform.isMacOS) &&
                  pageController.canLoadMore.value &&
                  !pageController.pageLoadding.value &&
                  !pageController.pageEmpty.value,
              child: Center(
                child: TextButton(
                  onPressed: pageController.loadData,
                  child: const Text("加载更多"),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 12,
            right: 12,
            child: // 加载更多按钮
                Visibility(
              visible: (Platform.isWindows ||
                      Platform.isLinux ||
                      Platform.isMacOS) &&
                  pageController.canLoadMore.value &&
                  !pageController.pageLoadding.value &&
                  !pageController.pageEmpty.value &&
                  showPCRefreshButton,
              child: Center(
                child: IconButton(
                  style: IconButton.styleFrom(
                    backgroundColor: Get.theme.cardColor.withAlpha(200),
                    elevation: 4,
                  ),
                  onPressed: () {
                    pageController.refreshData();
                  },
                  icon: const Icon(Icons.refresh),
                ),
              ),
            ),
          ),
          Offstage(
            offstage: !pageController.pageEmpty.value,
            child: AppEmptyWidget(
              onRefresh: () => pageController.refreshData(),
            ),
          ),
          Offstage(
            offstage: !(showPageLoadding && pageController.pageLoadding.value),
            child: const AppLoaddingWidget(),
          ),
          Offstage(
            offstage: !pageController.pageError.value,
            child: AppErrorWidget(
              errorMsg: pageController.errorMsg.value,
              onRefresh: () => pageController.refreshData(),
            ),
          ),
        ],
      ),
    );
  }
}
