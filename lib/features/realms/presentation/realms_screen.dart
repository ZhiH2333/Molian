import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/layout_constants.dart';
import '../../../core/responsive.dart';
import '../../../core/router/app_router.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/auto_leading_button.dart';
import '../../../shared/widgets/empty_state.dart';
import '../data/models/realm_model.dart';
import '../providers/realms_providers.dart';

/// 圈子列表，接入 /api/realms；点击进入详情并可加入/退出。
class RealmsScreen extends ConsumerWidget {
  const RealmsScreen({super.key, this.inShell = false});

  /// 是否嵌入主壳；为 true 时不显示左上角返回按钮。
  final bool inShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wide = isWideScreen(context);
    return AppScaffold(
      isNoBackground: wide,
      isWideScreen: wide,
      appBar: AppBar(
        leading: inShell ? null : const AutoLeadingButton(),
        title: const Text('圈子'),
      ),
      body: Consumer(
        builder: (BuildContext context, WidgetRef ref, _) {
          final async = ref.watch(realmsListProvider);
          return async.when(
            data: (List<RealmModel> realms) {
              if (realms.isEmpty) {
                return const EmptyState(
                  title: '暂无圈子',
                  description: '圈子功能即将开放',
                  icon: Icons.people_outline,
                );
              }
              return RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(realmsListProvider);
                },
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: LayoutConstants.kSpacingXLarge),
                  itemCount: realms.length,
                  itemBuilder: (BuildContext context, int index) {
                    final realm = realms[index];
                    return ListTile(
                      minLeadingWidth: LayoutConstants.kListTileMinLeadingWidth,
                      contentPadding: LayoutConstants.kListTileContentPadding,
                      leading: CircleAvatar(
                        backgroundImage: realm.avatarUrl != null && realm.avatarUrl!.isNotEmpty
                            ? CachedNetworkImageProvider(realm.avatarUrl!)
                            : null,
                        child: realm.avatarUrl == null || realm.avatarUrl!.isEmpty
                            ? Text(realm.name.isNotEmpty ? realm.name[0] : '?')
                            : null,
                      ),
                      title: Text(realm.name),
                      subtitle: realm.description != null && realm.description!.isNotEmpty
                          ? Text(realm.description!, maxLines: 2, overflow: TextOverflow.ellipsis)
                          : null,
                      onTap: () => context.push(AppRoutes.realmDetail(realm.id), extra: realm),
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
                onPressed: () => ref.invalidate(realmsListProvider),
                child: const Text('重试'),
              ),
            ),
          );
        },
      ),
    );
  }
}
