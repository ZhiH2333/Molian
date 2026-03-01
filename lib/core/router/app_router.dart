import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/chat/presentation/chat_rooms_list_screen.dart';
import '../../features/chat/presentation/chat_room_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/register_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/create_post/create_post_page.dart';
import '../../features/posts/data/models/post_model.dart';
import '../../features/posts/presentation/post_comments_screen.dart';
import '../../features/posts/presentation/post_detail_screen.dart';
import '../../features/direct/presentation/direct_to_chat_redirect_screen.dart';
import '../../features/direct/presentation/friend_requests_screen.dart';
import '../../features/direct/presentation/user_search_screen.dart';
import '../../features/discovery/presentation/explore_screen.dart';
import '../../features/files/presentation/files_screen.dart';
import '../../features/notifications/presentation/notifications_screen.dart';
import '../../features/main_shell/presentation/main_shell_screen.dart';
import '../../features/social/presentation/social_screen.dart';
import '../../features/realms/data/models/realm_model.dart';
import '../../features/realms/presentation/create_realm_screen.dart';
import '../../features/realms/presentation/realm_detail_screen.dart';
import '../../features/realms/presentation/realms_screen.dart';
import '../../features/realms/presentation/realms_search_screen.dart';
import '../../features/settings/presentation/account_privacy_screen.dart';
import '../../features/settings/presentation/push_settings_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';

/// 路由路径常量。
class AppRoutes {
  AppRoutes._();

  static const String home = '/';
  static const String login = '/login';
  static const String register = '/register';
  static const String profile = '/profile';
  static const String createPost = '/posts/create';
  static const String settings = '/settings';
  static const String userSearch = '/users/search';
  static const String friendRequests = '/friend-requests';
  static const String explore = '/explore';
  static const String realms = '/realms';
  static const String realmsCreate = '/realms/create';
  static const String realmsSearch = '/realms/search';
  static String realmDetail(String id) => '/realms/$id';
  static const String files = '/files';
  static const String notifications = '/notifications';
  static const String social = '/social';
  static const String settingsAccount = '/settings/account';
  static const String settingsPush = '/settings/push';
  static const String direct = '/direct';
  static String directConversation(String peerId) => '/direct/$peerId';
  static const String chatRooms = '/chat';
  static String chatRoom(String roomId) => '/chat/$roomId';
}

/// 配置 go_router，含底部导航壳（浏览、聊天、个人）。
GoRouter createAppRouter() {
  return GoRouter(
    initialLocation: AppRoutes.home,
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.home,
        builder: (BuildContext context, GoRouterState state) =>
            const MainShellScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (BuildContext context, GoRouterState state) =>
            const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.register,
        builder: (BuildContext context, GoRouterState state) =>
            const RegisterScreen(),
      ),
      GoRoute(
        path: AppRoutes.profile,
        builder: (BuildContext context, GoRouterState state) =>
            const ProfileScreen(),
      ),
      GoRoute(
        path: AppRoutes.createPost,
        builder: (BuildContext context, GoRouterState state) =>
            const CreatePostPage(),
      ),
      GoRoute(
        path: '/posts/:id',
        builder: (BuildContext context, GoRouterState state) {
          final String id = state.pathParameters['id'] ?? '';
          final PostModel? initialPost = state.extra as PostModel?;
          return PostDetailScreen(postId: id, initialPost: initialPost);
        },
      ),
      GoRoute(
        path: '/posts/:id/edit',
        builder: (BuildContext context, GoRouterState state) {
          final String id = state.pathParameters['id'] ?? '';
          final PostModel? post = state.extra as PostModel?;
          return CreatePostPage(postId: id, initialPost: post);
        },
      ),
      GoRoute(
        path: '/posts/:id/comments',
        builder: (BuildContext context, GoRouterState state) {
          final String id = state.pathParameters['id'] ?? '';
          return PostCommentsScreen(postId: id);
        },
      ),
      GoRoute(
        path: AppRoutes.userSearch,
        builder: (BuildContext context, GoRouterState state) =>
            const UserSearchScreen(),
      ),
      GoRoute(
        path: AppRoutes.friendRequests,
        builder: (BuildContext context, GoRouterState state) =>
            const FriendRequestsScreen(),
      ),
      GoRoute(
        path: AppRoutes.settings,
        builder: (BuildContext context, GoRouterState state) =>
            const SettingsScreen(),
      ),
      GoRoute(
        path: AppRoutes.settingsAccount,
        builder: (BuildContext context, GoRouterState state) =>
            const AccountPrivacyScreen(),
      ),
      GoRoute(
        path: AppRoutes.settingsPush,
        builder: (BuildContext context, GoRouterState state) =>
            const PushSettingsScreen(),
      ),
      GoRoute(
        path: AppRoutes.explore,
        builder: (BuildContext context, GoRouterState state) =>
            const ExploreScreen(),
      ),
      GoRoute(
        path: AppRoutes.realms,
        builder: (BuildContext context, GoRouterState state) =>
            const RealmsScreen(),
        routes: <RouteBase>[
          GoRoute(
            path: 'create',
            builder: (BuildContext context, GoRouterState state) =>
                const CreateRealmScreen(),
          ),
          GoRoute(
            path: 'search',
            builder: (BuildContext context, GoRouterState state) =>
                const RealmsSearchScreen(),
          ),
          GoRoute(
            path: ':id',
            builder: (BuildContext context, GoRouterState state) {
              final id = state.pathParameters['id'] ?? '';
              final realm = state.extra as RealmModel?;
              return RealmDetailScreen(realmId: id, initialRealm: realm);
            },
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.files,
        builder: (BuildContext context, GoRouterState state) =>
            const FilesScreen(),
      ),
      GoRoute(
        path: AppRoutes.notifications,
        builder: (BuildContext context, GoRouterState state) =>
            const NotificationsScreen(),
      ),
      GoRoute(
        path: AppRoutes.social,
        builder: (BuildContext context, GoRouterState state) =>
            const SocialScreen(),
      ),
      GoRoute(
        path: '${AppRoutes.direct}/:peerId',
        builder: (BuildContext context, GoRouterState state) {
          final peerId = state.pathParameters['peerId'] ?? '';
          final peerName = state.uri.queryParameters['peerName'];
          return DirectToChatRedirectScreen(
            peerId: peerId,
            peerDisplayName: peerName,
          );
        },
      ),
      GoRoute(
        path: AppRoutes.chatRooms,
        builder: (BuildContext context, GoRouterState state) =>
            const ChatRoomsListScreen(),
      ),
      GoRoute(
        path: '/chat/:roomId',
        builder: (BuildContext context, GoRouterState state) {
          final roomId = state.pathParameters['roomId'] ?? '';
          final extra = state.extra is Map<String, String>
              ? state.extra as Map<String, String>
              : null;
          final title = extra?['title'];
          return ChatRoomScreen(roomId: roomId, roomTitle: title);
        },
      ),
    ],
  );
}
