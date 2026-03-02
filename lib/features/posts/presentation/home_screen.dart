import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/layout_constants.dart';
import '../../../core/responsive.dart';
import '../../../core/router/app_router.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../auth/data/models/user_model.dart';
import '../../auth/providers/auth_providers.dart';
import '../../notifications/data/models/notification_model.dart';
import '../../notifications/data/notifications_repository.dart';
import '../../notifications/providers/notifications_providers.dart';
import '../data/posts_repository.dart';
import '../providers/posts_providers.dart';
import 'widgets/post_card.dart';

/// 壳内已登录时 FAB 在 body 的 Stack 中绘制（避免被底部导航挡住），此时不使用 Scaffold 的 floatingActionButton。
bool _shouldShowFabInShell(UserModel? user, bool inShell) =>
    inShell && user != null;

/// 首页：已登录显示发现流与发布 FAB，未登录显示登录/注册入口。
/// 壳内时以 Tab 展示：发现、通知（圈子、文件已移至左侧菜单）。
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key, this.inShell = false});

  /// 是否嵌入底部导航壳；为 true 时以 Tab 展示发现/通知。
  final bool inShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final wide = isWideScreen(context);
    return AppScaffold(
      isNoBackground: wide,
      isWideScreen: wide,
      appBar: inShell
          ? AppBar(title: const Text('浏览'))
          : AppBar(
              title: const Text('Molian'),
              actions: <Widget>[
                if (authState.valueOrNull != null) ...[
                  IconButton(
                    icon: const Icon(Icons.chat),
                    onPressed: () => context.push(AppRoutes.chatRooms),
                  ),
                  IconButton(
                    icon: const Icon(Icons.person),
                    onPressed: () => context.push(AppRoutes.profile),
                  ),
                ],
              ],
            ),
      body: authState.when(
        data: (UserModel? user) {
          if (user == null) {
            return _buildGuestBody(context);
          }
          if (inShell) {
            final bottomInset = MediaQuery.paddingOf(context).bottom;
            final fabBottom =
                bottomInset + LayoutConstants.kFabMarginAboveBottomNav;
            return Stack(
              children: <Widget>[
                DefaultTabController(
                  length: 2,
                  child: Column(
                    children: <Widget>[
                      TabBar(
                        tabs: <Widget>[
                          Tab(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: const <Widget>[
                                Icon(Icons.explore_outlined, size: 20),
                                SizedBox(width: 8),
                                Text('发现'),
                              ],
                            ),
                          ),
                          Tab(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: const <Widget>[
                                Icon(Icons.notifications_none_outlined, size: 20),
                                SizedBox(width: 8),
                                Text('通知'),
                              ],
                            ),
                          ),
                        ],
                      ),
                      Expanded(
                        child: TabBarView(
                          physics: const NeverScrollableScrollPhysics(),
                          children: <Widget>[
                            _FeedsTabContent(),
                            _NotificationsTabContent(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  right: LayoutConstants.kSpacingLarge,
                  bottom: fabBottom,
                  child: FloatingActionButton(
                    onPressed: () => context.push(AppRoutes.createPost),
                    child: const Icon(Icons.add),
                  ),
                ),
              ],
            );
          }
          return _FeedsTabContent();
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object err, StackTrace? stack) => EmptyState(
          title: '加载失败',
          description: err.toString(),
          action: TextButton(
            onPressed: () => context.push(AppRoutes.login),
            child: const Text('去登录'),
          ),
        ),
      ),
      floatingActionButton:
          _shouldShowFabInShell(authState.valueOrNull, inShell)
          ? null
          : (authState.valueOrNull != null
                ? FloatingActionButton(
                    onPressed: () => context.push(AppRoutes.createPost),
                    child: const Icon(Icons.add),
                  )
                : null),
    );
  }

  Widget _buildGuestBody(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const Text('首页（时间线占位）'),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => context.push(AppRoutes.login),
            child: const Text('登录'),
          ),
          TextButton(
            onPressed: () => context.push(AppRoutes.register),
            child: const Text('注册'),
          ),
        ],
      ),
    );
  }
}

class _FeedsTabContent extends ConsumerWidget {
  const _FeedsTabContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pageAsync = ref.watch(feedsListProvider(const PostsListKey()));
    return pageAsync.when(
      data: (PostsPageResult result) {
        if (result.posts.isEmpty) {
          return EmptyState(
            title: '发现',
            description: '暂无推荐内容',
            icon: Icons.explore_outlined,
            action: FilledButton.icon(
              onPressed: () => context.push(AppRoutes.createPost),
              icon: const Icon(Icons.add),
              label: const Text('发一条'),
            ),
          );
        }
        final bottomPadding = MediaQuery.paddingOf(context).bottom + 64;
        return RefreshIndicator(
          onRefresh: () async =>
              ref.invalidate(feedsListProvider(const PostsListKey())),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: LayoutConstants.kContentMaxWidthWide,
              ),
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                padding: EdgeInsets.only(bottom: bottomPadding),
                itemCount: result.posts.length,
                itemBuilder: (BuildContext context, int index) =>
                    PostCard(post: result.posts[index]),
              ),
            ),
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object err, StackTrace? st) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text('加载失败: $err'),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () =>
                  ref.invalidate(feedsListProvider(const PostsListKey())),
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationsTabContent extends ConsumerWidget {
  const _NotificationsTabContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(
      notificationsListProvider(const NotificationsListKey()),
    );
    return async.when(
      data: (NotificationsPageResult result) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () async {
                    final repo = ref.read(notificationsRepositoryProvider);
                    await repo.markRead();
                    ref.invalidate(
                      notificationsListProvider(const NotificationsListKey()),
                    );
                  },
                  child: const Text('全部已读'),
                ),
              ),
            ),
            Expanded(
              child: result.notifications.isEmpty
                  ? const EmptyState(
                      title: '暂无通知',
                      description: '新的点赞、评论、关注等会出现在这里',
                      icon: Icons.notifications_none_outlined,
                    )
                  : RefreshIndicator(
                      onRefresh: () async => ref.invalidate(
                        notificationsListProvider(const NotificationsListKey()),
                      ),
                      child: ListView.builder(
                        padding: const EdgeInsets.only(
                          bottom: LayoutConstants.kSpacingXLarge,
                        ),
                        itemCount: result.notifications.length,
                        itemBuilder: (BuildContext context, int index) {
                          final n = result.notifications[index];
                          return _HomeNotificationTile(
                            notification: n,
                            onMarkRead: () async {
                              final repo = ref.read(
                                notificationsRepositoryProvider,
                              );
                              await repo.markRead(id: n.id);
                              ref.invalidate(
                                notificationsListProvider(
                                  const NotificationsListKey(),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object err, StackTrace? st) => EmptyState(
        title: '加载失败',
        description: err.toString(),
        action: TextButton(
          onPressed: () => ref.invalidate(
            notificationsListProvider(const NotificationsListKey()),
          ),
          child: const Text('重试'),
        ),
      ),
    );
  }
}

class _HomeNotificationTile extends StatelessWidget {
  const _HomeNotificationTile({
    required this.notification,
    required this.onMarkRead,
  });

  final NotificationModel notification;
  final VoidCallback onMarkRead;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUnread = !notification.read;
    return ListTile(
      minLeadingWidth: LayoutConstants.kListTileMinLeadingWidth,
      contentPadding: LayoutConstants.kListTileContentPadding,
      leading: CircleAvatar(
        backgroundColor: isUnread ? theme.colorScheme.primaryContainer : null,
        child: Icon(
          _iconForType(notification.type),
          color: isUnread
              ? theme.colorScheme.onPrimaryContainer
              : theme.colorScheme.outline,
        ),
      ),
      title: Text(
        notification.title ?? notification.type,
        style: TextStyle(
          fontWeight: isUnread ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      subtitle: notification.body != null && notification.body!.isNotEmpty
          ? Text(
              notification.body!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            )
          : null,
      trailing: isUnread
          ? TextButton(onPressed: onMarkRead, child: const Text('标为已读'))
          : null,
    );
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'like':
        return Icons.favorite_outline;
      case 'comment':
        return Icons.chat_bubble_outline;
      case 'follow':
        return Icons.person_add_outlined;
      case 'friend_request':
        return Icons.mail_outline;
      default:
        return Icons.notifications_outlined;
    }
  }
}
