/// API 基础地址与路径常量。
class ApiConstants {
  ApiConstants._();

  static const String _baseUrlEnv = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://api.molian.app',
  );

  static const String _wsBaseUrlEnv = String.fromEnvironment(
    'WS_BASE_URL',
    defaultValue: 'wss://api.molian.app',
  );

  /// REST API 基地址。默认远端 Worker；本地调试时用 --dart-define=API_BASE_URL=http://127.0.0.1:8787 连本地。
  static String get baseUrl => _baseUrlEnv;

  /// WebSocket 基地址。默认与 API 同域（wss）；本地调试时用 --dart-define=WS_BASE_URL=ws://127.0.0.1:8787。
  static String get wsBaseUrl => _wsBaseUrlEnv;
  static const String authLogin = '/api/auth/login';
  static const String authRegister = '/api/auth/register';
  static const String authMe = '/api/auth/me';
  static const String authRefresh = '/api/auth/refresh';
  static const String usersMe = '/api/users/me';
  static const String posts = '/api/posts';
  static const String users = '/api/users';
  static const String follows = '/api/follows';
  static const String messages = '/api/messages';
  static const String upload = '/api/upload';
  static const String usersMeFollowing = '/api/users/me/following';
  static const String usersMeFollowers = '/api/users/me/followers';
  static const String usersMeFriends = '/api/users/me/friends';
  static const String usersSearch = '/api/users/search';
  static const String friendRequests = '/api/friend-requests';
  static const String feeds = '/api/feeds';
  static const String realms = '/api/realms';
  static const String files = '/api/files';
  static const String filesConfirm = '/api/files/confirm';
  static String realmById(String id) => '$realms/$id';
  static String realmPosts(String id) => '$realms/$id/posts';
  static String realmJoin(String id) => '$realms/$id/join';
  static String realmLeave(String id) => '$realms/$id/leave';
  static String assetUrl(String key) =>
      '$baseUrl/api/asset/${Uri.encodeComponent(key)}';
  static const String notificationsList = '/api/notifications';
  static const String notificationsRead = '/api/notifications/read';
  static const String notificationsSubscribe = '/api/notifications/subscribe';

  static const String messagerChat = '/messager/chat';

  static String messagerChatMessages(String roomId) =>
      '/messager/chat/$roomId/messages';

  static String messagerChatMessage(String roomId, String messageId) =>
      '/messager/chat/$roomId/messages/$messageId';

  static String messagerChatMessageReaction(
    String roomId,
    String messageId,
    String emoji,
  ) => '/messager/chat/$roomId/messages/$messageId/reactions/$emoji';

  static String messagerChatDirect(String peerId) =>
      '/messager/chat/direct/$peerId';
}
