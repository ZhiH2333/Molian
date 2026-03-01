/// 聊天房间类型。
enum ChatRoomType {
  direct,
  group,
}

/// 聊天房间成员。
class ChatRoomMember {
  const ChatRoomMember({
    required this.id,
    required this.roomId,
    required this.userId,
    required this.role,
    this.joinedAt,
    this.displayName,
    this.avatarUrl,
  });

  final String id;
  final String roomId;
  final String userId;
  final String role;
  final String? joinedAt;
  final String? displayName;
  final String? avatarUrl;

  factory ChatRoomMember.fromJson(Map<String, dynamic> json) =>
      ChatRoomMember(
        id: (json['id'] as Object?)?.toString() ?? '',
        roomId: (json['room_id'] as Object?)?.toString() ?? '',
        userId: (json['user_id'] as Object?)?.toString() ?? '',
        role: (json['role'] as Object?)?.toString() ?? 'member',
        joinedAt: json['joined_at'] as String?,
        displayName: json['display_name'] as String?,
        avatarUrl: json['avatar_url'] as String?,
      );
}

/// 聊天房间。
class ChatRoom {
  const ChatRoom({
    required this.id,
    required this.name,
    required this.type,
    this.description,
    this.avatarUrl,
    this.memberCount = 0,
    this.lastMessageAt,
    this.lastMessageText,
    this.createdAt,
    this.members = const [],
  });

  final String id;
  final String name;
  final ChatRoomType type;
  final String? description;
  final String? avatarUrl;
  final int memberCount;
  final String? lastMessageAt;
  /// 最新一条消息的文本预览（若 API 返回）。
  final String? lastMessageText;
  final String? createdAt;
  final List<ChatRoomMember> members;

  bool get isDirect => type == ChatRoomType.direct;

  static String? _parseLastMessageText(Map<String, dynamic> json) {
    final direct = json['last_message_text'] as String?;
    if (direct != null && direct.trim().isNotEmpty) return direct.trim();
    final obj = json['last_message'];
    if (obj is Map<String, dynamic>) {
      final text = (obj['text'] as String?) ?? (obj['content'] as String?);
      if (text != null && text.trim().isNotEmpty) return text.trim();
    }
    return null;
  }

  factory ChatRoom.fromJson(Map<String, dynamic> json) {
    final typeStr = (json['type'] as String?) ?? 'direct';
    List<ChatRoomMember> membersList = (json['members'] as List?)
            ?.map((dynamic e) =>
                ChatRoomMember.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    if (membersList.isEmpty) {
      final peerId = (json['peer_id'] as Object?)?.toString();
      if (peerId != null && peerId.isNotEmpty) {
        membersList = [
          ChatRoomMember.fromJson(<String, dynamic>{'user_id': peerId}),
        ];
      }
    }
    return ChatRoom(
      id: (json['id'] as Object?)?.toString() ?? '',
      name: (json['name'] as Object?)?.toString() ?? '',
      type: typeStr == 'group' ? ChatRoomType.group : ChatRoomType.direct,
      description: json['description'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      memberCount: (json['member_count'] as int?) ?? 0,
      lastMessageAt: json['last_message_at'] as String?,
      lastMessageText: _parseLastMessageText(json),
      createdAt: json['created_at'] as String?,
      members: membersList,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'type': type.name,
        'description': description,
        'avatar_url': avatarUrl,
        'member_count': memberCount,
        'last_message_at': lastMessageAt,
        'last_message_text': lastMessageText,
        'created_at': createdAt,
      };
}
