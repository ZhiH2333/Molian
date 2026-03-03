import 'package:dio/dio.dart';

import '../../../core/constants/api_constants.dart';

/// 点赞、评论、关注、私信接口。
class SocialRepository {
  SocialRepository({required Dio dio}) : _dio = dio;
  final Dio _dio;

  Future<void> likePost(String postId) async {
    await _dio.post<Map<String, dynamic>>('${ApiConstants.posts}/$postId/like');
  }

  Future<void> unlikePost(String postId) async {
    await _dio.delete<Map<String, dynamic>>('${ApiConstants.posts}/$postId/like');
  }

  Future<void> follow(String followingId) async {
    await _dio.post<Map<String, dynamic>>(ApiConstants.follows, data: <String, dynamic>{'following_id': followingId});
  }

  Future<void> unfollow(String followingId) async {
    await _dio.delete<Map<String, dynamic>>('${ApiConstants.follows}/$followingId');
  }

  Future<List<Map<String, dynamic>>> getComments(String postId) async {
    final response = await _dio.get<Map<String, dynamic>>('${ApiConstants.posts}/$postId/comments');
    final data = response.data;
    if (data == null || data['comments'] is! List) return [];
    return List<Map<String, dynamic>>.from(data['comments'] as List);
  }

  Future<Map<String, dynamic>> addComment(String postId, String content, {String? parentCommentId}) async {
    final payload = <String, dynamic>{'content': content};
    if (parentCommentId != null) payload['parent_comment_id'] = parentCommentId;
    final response = await _dio.post<Map<String, dynamic>>(
      '${ApiConstants.posts}/$postId/comments',
      data: payload,
    );
    final data = response.data;
    if (data == null || data['comment'] == null) throw Exception('评论失败');
    return data['comment'] as Map<String, dynamic>;
  }

  /// 删除评论，仅评论作者可删。
  Future<void> deleteComment(String postId, String commentId) async {
    await _dio.delete<Map<String, dynamic>>('${ApiConstants.posts}/$postId/comments/$commentId');
  }

  /// 编辑评论，仅评论作者可编辑。
  Future<Map<String, dynamic>> updateComment(String postId, String commentId, String content) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '${ApiConstants.posts}/$postId/comments/$commentId',
      data: <String, dynamic>{'content': content},
    );
    final data = response.data;
    if (data == null || data['comment'] == null) throw Exception('编辑失败');
    return data['comment'] as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> getConversations() async {
    final response = await _dio.get<Map<String, dynamic>>(ApiConstants.messages);
    final data = response.data;
    if (data == null || data['conversations'] is! List) return [];
    return List<Map<String, dynamic>>.from(data['conversations'] as List);
  }

  Future<List<Map<String, dynamic>>> getMessages(String withUserId, {String? cursor, int? limit}) async {
    final queryParams = <String, String>{'with_user': withUserId};
    if (cursor != null) queryParams['cursor'] = cursor;
    if (limit != null) queryParams['limit'] = limit.toString();
    final uri = Uri.parse(ApiConstants.messages).replace(queryParameters: queryParams);
    final response = await _dio.get<Map<String, dynamic>>(uri.toString());
    final data = response.data;
    if (data == null || data['messages'] is! List) return [];
    return List<Map<String, dynamic>>.from(data['messages'] as List);
  }

  /// 将与某用户的会话标记为已读（对方发来的未读消息全部标已读）。
  Future<void> markConversationRead(String withUserId) async {
    await _dio.post<Map<String, dynamic>>(
      '${ApiConstants.messages}/mark-read',
      data: <String, dynamic>{'with_user': withUserId},
    );
  }

  Future<Map<String, dynamic>> sendMessage(String receiverId, String content) async {
    final response = await _dio.post<Map<String, dynamic>>(
      ApiConstants.messages,
      data: <String, dynamic>{'receiver_id': receiverId, 'content': content},
    );
    final data = response.data;
    if (data == null || data['message'] == null) throw Exception('发送失败');
    return data['message'] as Map<String, dynamic>;
  }

  /// 搜索全站用户（username / display_name 模糊匹配）。
  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    if (query.trim().isEmpty) return [];
    final uri = Uri.parse(ApiConstants.usersSearch).replace(
      queryParameters: <String, String>{'q': query.trim()},
    );
    final response = await _dio.get<Map<String, dynamic>>(uri.toString());
    final data = response.data;
    if (data == null) return [];
    final raw = data['users'] as List? ?? data['data'] as List? ?? [];
    return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// 发送好友申请。连接类错误时最多重试 2 次（共 3 次请求），应对冷启动或瞬时网络问题。
  Future<void> sendFriendRequest(String targetUserId) async {
    Future<void> doPost() => _dio.post<Map<String, dynamic>>(
          ApiConstants.friendRequests,
          data: <String, dynamic>{'target_id': targetUserId},
        );
    const retryableTypes = [
      DioExceptionType.connectionError,
      DioExceptionType.connectionTimeout,
      DioExceptionType.receiveTimeout,
      DioExceptionType.sendTimeout,
    ];
    int attempt = 0;
    while (true) {
      try {
        attempt++;
        await doPost();
        return;
      } on DioException catch (e) {
        final isRetryable = retryableTypes.contains(e.type);
        if (isRetryable && attempt < 3) {
          await Future<void>.delayed(const Duration(milliseconds: 1500));
        } else {
          rethrow;
        }
      }
    }
  }

  /// 获取收到的好友申请列表（仅 pending）。
  Future<List<Map<String, dynamic>>> getFriendRequestsReceived() async {
    final response = await _dio.get<Map<String, dynamic>>(ApiConstants.friendRequests);
    final data = response.data;
    if (data == null || data['friend_requests'] is! List) return [];
    return List<Map<String, dynamic>>.from(data['friend_requests'] as List);
  }

  /// 接受好友申请；成功后双方互相关注。
  Future<void> acceptFriendRequest(String requestId) async {
    await _dio.post<Map<String, dynamic>>(
      '${ApiConstants.friendRequests}/$requestId/accept',
    );
  }

  /// 拒绝好友申请。
  Future<void> rejectFriendRequest(String requestId) async {
    await _dio.post<Map<String, dynamic>>(
      '${ApiConstants.friendRequests}/$requestId/reject',
    );
  }

  /// 获取当前用户的好友列表（已接受的好友关系）。
  Future<List<Map<String, dynamic>>> getFriends() async {
    final response = await _dio.get<Map<String, dynamic>>(ApiConstants.usersMeFriends);
    final data = response.data;
    if (data == null) return [];
    final raw = data['friends'] as List? ?? data['data'] as List? ?? [];
    return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// 获取当前用户关注的用户列表。
  Future<List<Map<String, dynamic>>> getFollowing() async {
    final response = await _dio.get<Map<String, dynamic>>(ApiConstants.usersMeFollowing);
    final data = response.data;
    if (data == null || data['users'] is! List) return [];
    return List<Map<String, dynamic>>.from(data['users'] as List);
  }

  /// 获取当前用户的粉丝列表。
  Future<List<Map<String, dynamic>>> getFollowers() async {
    final response = await _dio.get<Map<String, dynamic>>(ApiConstants.usersMeFollowers);
    final data = response.data;
    if (data == null || data['users'] is! List) return [];
    return List<Map<String, dynamic>>.from(data['users'] as List);
  }

  /// 删除好友（解除好友关系）。
  Future<void> removeFriend(String friendUserId) async {
    await _dio.delete<Map<String, dynamic>>('${ApiConstants.usersMeFriends}/$friendUserId');
  }
}
