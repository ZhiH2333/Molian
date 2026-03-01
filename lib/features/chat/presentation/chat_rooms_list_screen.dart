import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../auth/providers/auth_providers.dart';
import '../../direct/providers/chat_providers.dart' as ws_providers;
import '../../social/providers/social_providers.dart';
import '../data/models/chat_room_model.dart';
import '../providers/chat_providers.dart';

/// 聊天 Tab 页：会话列表 + 好友列表；点击进入 ChatRoomScreen（flutter_chat_ui v2）。
class ChatRoomsListScreen extends ConsumerStatefulWidget {
  const ChatRoomsListScreen({super.key});

  @override
  ConsumerState<ChatRoomsListScreen> createState() =>
      _ChatRoomsListScreenState();
}

class _ChatRoomsListScreenState extends ConsumerState<ChatRoomsListScreen>
    with SingleTickerProviderStateMixin {
  bool _didConnectWs = false;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(authStateProvider).valueOrNull;
    if (me == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('聊天')),
        body: const Center(child: Text('请先登录')),
      );
    }
    if (!_didConnectWs) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _didConnectWs) return;
        ref.read(ws_providers.webSocketServiceProvider).connect();
        if (mounted) setState(() => _didConnectWs = true);
      });
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('聊天'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const <Tab>[
            Tab(text: '会话'),
            Tab(text: '好友'),
          ],
        ),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.mail_outline),
            tooltip: '好友申请',
            onPressed: () => context.push(AppRoutes.friendRequests),
          ),
          IconButton(
            icon: const Icon(Icons.person_add),
            tooltip: '搜索添加好友',
            onPressed: () => context.push(AppRoutes.userSearch),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(chatRoomListProvider);
              setState(() {});
            },
            tooltip: '刷新',
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: const <Widget>[
          _ConversationsTab(),
          _FriendsTab(),
        ],
      ),
    );
  }
}

class _ConversationsTab extends ConsumerWidget {
  const _ConversationsTab();

  /// 私聊时显示对方名称与头像，群聊用 room 的 name/avatarUrl。
  static String _roomDisplayTitle(ChatRoom room, String? myUserId) {
    if (room.isDirect && room.members.isNotEmpty && myUserId != null) {
      final other = room.members
          .where((ChatRoomMember m) => m.userId != myUserId)
          .firstOrNull;
      if (other != null) {
        final dn = other.displayName?.trim();
        if (dn != null && dn.isNotEmpty) return dn;
      }
    }
    return room.name.isNotEmpty ? room.name : room.id;
  }

  static String? _roomDisplayAvatarUrl(ChatRoom room, String? myUserId) {
    if (room.avatarUrl != null && room.avatarUrl!.isNotEmpty) return room.avatarUrl;
    if (room.isDirect && room.members.isNotEmpty && myUserId != null) {
      final other = room.members
          .where((ChatRoomMember m) => m.userId != myUserId)
          .firstOrNull;
      if (other?.avatarUrl != null && other!.avatarUrl!.isNotEmpty) return other.avatarUrl;
    }
    return null;
  }

  static String? _formatLastMessageTime(String isoString) {
    try {
      final dt = DateTime.parse(isoString);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = today.subtract(const Duration(days: 1));
      final date = DateTime(dt.year, dt.month, dt.day);
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      if (date == today) return '今天 $h:$m';
      if (date == yesterday) return '昨天 $h:$m';
      if (dt.year == now.year) return '${dt.month}月${dt.day}日';
      return '${dt.year}年${dt.month}月${dt.day}日';
    } catch (_) {
      return null;
    }
  }

  static String? _roomSubtitle(ChatRoom room) {
    final text = room.lastMessageText?.trim();
    if (text != null && text.isNotEmpty) {
      const int maxLen = 40;
      return text.length <= maxLen ? text : '${text.substring(0, maxLen)}…';
    }
    if (room.lastMessageAt != null) {
      return _formatLastMessageTime(room.lastMessageAt!);
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(authStateProvider).valueOrNull;
    final myUserId = me?.id;
    final roomsAsync = ref.watch(chatRoomListProvider);
    return roomsAsync.when(
      data: (List<ChatRoom> rooms) {
        if (rooms.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text('暂无会话'),
                SizedBox(height: 8),
                Text(
                  '在「好友」中选择好友发起私信',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          );
        }
        return ListView.builder(
          itemCount: rooms.length,
          itemBuilder: (BuildContext context, int index) {
            final room = rooms[index];
            final title = _roomDisplayTitle(room, myUserId);
            final avatarUrl = _roomDisplayAvatarUrl(room, myUserId);
            final subtitle = _roomSubtitle(room);
            return ListTile(
              leading: CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
                backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
                child: avatarUrl == null
                    ? Text(
                        title.isNotEmpty ? title[0].toUpperCase() : '?',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSecondaryContainer,
                        ),
                      )
                    : null,
              ),
              title: Text(title),
              subtitle: subtitle != null ? Text(subtitle) : null,
              onTap: () => context.push(
                AppRoutes.chatRoom(room.id),
                extra: <String, String>{'title': title},
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object err, StackTrace _) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(err.toString()),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => ref.invalidate(chatRoomListProvider),
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FriendsTab extends ConsumerStatefulWidget {
  const _FriendsTab();

  @override
  ConsumerState<_FriendsTab> createState() => _FriendsTabState();
}

class _FriendsTabState extends ConsumerState<_FriendsTab> {
  List<Map<String, dynamic>> _friends = <Map<String, dynamic>>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  Future<void> _loadFriends() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ref.read(socialRepositoryProvider);
      final list = await repo.getFriends();
      if (mounted) {
        setState(() {
          _friends = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  Future<void> _confirmRemoveFriend(String friendId, String friendName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('删除好友'),
        content: Text('确定删除好友「$friendName」吗？删除后需重新发送好友申请才能恢复。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final repo = ref.read(socialRepositoryProvider);
      await repo.removeFriend(friendId);
      if (mounted) {
        ref.invalidate(chatRoomListProvider);
        final messenger = ScaffoldMessenger.of(context);
        messenger.clearSnackBars();
        messenger.showSnackBar(
          SnackBar(
            key: const ValueKey<String>('chat_friend_removed'),
            content: Text('已删除好友（${friendName.trim().isNotEmpty ? friendName : friendId}）'),
          ),
        );
        _loadFriends();
      }
    } catch (e) {
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        messenger.clearSnackBars();
        messenger.showSnackBar(
          SnackBar(
            key: const ValueKey<String>('chat_friend_remove_fail'),
            content: Text('删除失败：${e.toString().replaceFirst('Exception: ', '')}'),
          ),
        );
      }
    }
  }

  Future<void> _openChatWithFriend(String friendId, String friendName) async {
    if (friendId.isEmpty) return;
    try {
      final room = await ref.read(chatRoomListProvider.notifier).fetchOrCreateDirectRoom(friendId);
      if (!mounted) return;
      final title = room.name.isNotEmpty ? room.name : friendName;
      context.push(AppRoutes.chatRoom(room.id), extra: <String, String>{'title': title});
    } catch (e) {
      if (!mounted) return;
      final errorMessage = e.toString().replaceFirst('Exception: ', '');
      await showDialog<void>(
        context: context,
        builder: (BuildContext ctx) => AlertDialog(
          title: const Text('无法发起会话'),
          content: Text(errorMessage),
          actions: <Widget>[
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('确定'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text('加载失败：$_error', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            TextButton(
              onPressed: _loadFriends,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    if (_friends.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text('暂无好友'),
            const SizedBox(height: 8),
            Text(
              '发送好友申请后，对方接受才会成为好友，才能发起私信',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => context.push(AppRoutes.userSearch),
              icon: const Icon(Icons.person_search),
              label: const Text('搜索添加好友'),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadFriends,
      child: ListView.builder(
        itemCount: _friends.length,
        itemBuilder: (BuildContext context, int i) {
          final f = _friends[i];
          final id = f['id']?.toString() ?? '';
          final displayName = (f['display_name']?.toString() ?? '').trim();
          final username = f['username']?.toString() ?? '';
          final title = displayName.isNotEmpty ? displayName : username;
          final avatarUrl = f['avatar_url']?.toString();
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
              backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                  ? NetworkImage(avatarUrl)
                  : null,
              child: avatarUrl == null || avatarUrl.isEmpty
                  ? Text(
                      title.isNotEmpty ? title[0].toUpperCase() : '?',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSecondaryContainer,
                      ),
                    )
                  : null,
            ),
            title: Text(title),
            subtitle: username.isNotEmpty ? Text('@$username') : null,
            trailing: PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (String value) {
                if (value == 'delete') _confirmRemoveFriend(id, title);
              },
              itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                const PopupMenuItem<String>(
                  value: 'delete',
                  child: Row(
                    children: <Widget>[
                      Icon(Icons.person_remove, size: 20),
                      SizedBox(width: 12),
                      Text('删除好友'),
                    ],
                  ),
                ),
              ],
            ),
            onTap: () => _openChatWithFriend(id, title),
          );
        },
      ),
    );
  }
}
