import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/layout_constants.dart';
import '../../../core/responsive.dart';
import '../../../core/utils/image_url_utils.dart';
import '../../../core/router/app_router.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/auto_leading_button.dart';
import '../../../shared/widgets/empty_state.dart';
import '../data/models/realm_model.dart';
import '../data/realms_repository.dart';
import '../providers/realms_providers.dart';

/// 圈子列表：顶部 Tab「已加入｜我创建的｜全部圈子」，右上角搜索与创建。
class RealmsScreen extends ConsumerStatefulWidget {
  const RealmsScreen({super.key, this.inShell = false});

  final bool inShell;

  @override
  ConsumerState<RealmsScreen> createState() => _RealmsScreenState();
}

class _RealmsScreenState extends ConsumerState<RealmsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  static const List<_TabItem> _tabs = <_TabItem>[
    _TabItem(label: '已加入', scope: RealmsScope.joined),
    _TabItem(label: '我创建的', scope: RealmsScope.mine),
    _TabItem(label: '全部圈子', scope: RealmsScope.all),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wide = isWideScreen(context);
    return AppScaffold(
      isNoBackground: wide,
      isWideScreen: wide,
      appBar: AppBar(
        leading: widget.inShell ? null : const AutoLeadingButton(),
        title: const Text('圈子'),
        bottom: TabBar(
          controller: _tabController,
          tabs: _tabs.map((e) => Tab(text: e.label)).toList(),
        ),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => context.push(AppRoutes.realmsSearch),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => context.push(AppRoutes.realmsCreate),
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: _tabs.map((e) => _RealmsListTab(scope: e.scope)).toList(),
      ),
    );
  }
}

class _TabItem {
  const _TabItem({required this.label, required this.scope});
  final String label;
  final RealmsScope scope;
}

class _RealmsListTab extends ConsumerWidget {
  const _RealmsListTab({required this.scope});

  final RealmsScope scope;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = RealmsListKey(scope: scope);
    final async = ref.watch(realmsListProvider(key));

    return async.when(
      data: (List<RealmModel> realms) {
        if (realms.isEmpty) {
          return EmptyState(
            title: _emptyTitle(scope),
            description: _emptyDescription(scope),
            icon: Icons.people_outline,
            action: scope == RealmsScope.all
                ? TextButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('创建圈子'),
                    onPressed: () => context.push(AppRoutes.realmsCreate),
                  )
                : null,
          );
        }
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(realmsListProvider(key));
          },
          child: ListView.builder(
            padding: const EdgeInsets.only(
              bottom: LayoutConstants.kSpacingXLarge,
            ),
            itemCount: realms.length,
            itemBuilder: (BuildContext context, int index) {
              final realm = realms[index];
              return ListTile(
                minLeadingWidth: LayoutConstants.kListTileMinLeadingWidth,
                contentPadding: LayoutConstants.kListTileContentPadding,
                leading: CircleAvatar(
                  backgroundImage:
                      realm.avatarUrl != null && realm.avatarUrl!.isNotEmpty
                      ? CachedNetworkImageProvider(
                          fullImageUrl(realm.avatarUrl),
                        )
                      : null,
                  child: realm.avatarUrl == null || realm.avatarUrl!.isEmpty
                      ? Text(realm.name.isNotEmpty ? realm.name[0] : '?')
                      : null,
                ),
                title: Text(realm.name),
                subtitle:
                    realm.description != null && realm.description!.isNotEmpty
                    ? Text(
                        realm.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      )
                    : null,
                onTap: () =>
                    context.push(AppRoutes.realmDetail(realm.id), extra: realm),
              );
            },
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object err, StackTrace? st) => EmptyState(
        title: '加载失败',
        description: err.toString(),
        action: TextButton(
          onPressed: () => ref.invalidate(realmsListProvider(key)),
          child: const Text('重试'),
        ),
      ),
    );
  }

  String _emptyTitle(RealmsScope scope) {
    switch (scope) {
      case RealmsScope.joined:
        return '暂无加入的圈子';
      case RealmsScope.mine:
        return '暂无创建的圈子';
      case RealmsScope.all:
        return '暂无圈子';
    }
  }

  String _emptyDescription(RealmsScope scope) {
    switch (scope) {
      case RealmsScope.joined:
        return '去全部圈子中探索并加入';
      case RealmsScope.mine:
        return '点击右上角 + 创建你的第一个圈子';
      case RealmsScope.all:
        return '点击右上角 + 创建圈子';
    }
  }
}
