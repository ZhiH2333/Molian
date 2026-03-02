import 'package:dio/dio.dart';

import '../../../core/constants/api_constants.dart';
import 'models/chat_message_dto.dart';

/// 将可能为相对路径的图片 URL 转为绝对 URL。
String toAbsoluteImageUrl(String url) {
  if (url.isEmpty) return url;
  final u = url.trim();
  if (u.startsWith('http://') || u.startsWith('https://')) return u;
  final base = ApiConstants.baseUrl;
  final path = u.startsWith('/') ? u : '/$u';
  return base.endsWith('/') ? '$base${path.substring(1)}' : '$base$path';
}

/// 聊天消息与房间的 REST 接口封装。
class ChatRepository {
  /// 供 UI 使用的图片 URL 规范化。
  static String imageUrl(String url) => toAbsoluteImageUrl(url);
  const ChatRepository(this._dio);

  final Dio _dio;

  /// 分页拉取房间消息，按时间正序（旧在前）返回。
  Future<List<ChatMessageDto>> fetchMessages(
    String roomId, {
    int offset = 0,
    int take = 50,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      ApiConstants.messagerChatMessages(roomId),
      queryParameters: <String, dynamic>{'offset': offset, 'take': take},
    );
    final data = res.data;
    if (data == null) return [];
    final raw = data['messages'] as List? ?? data['data'] as List? ?? [];
    final list = raw
        .map((dynamic e) => ChatMessageDto.fromJson(e as Map<String, dynamic>))
        .toList();
    list.sort((ChatMessageDto a, ChatMessageDto b) {
      final ta = _parseTime(a.createdAt);
      final tb = _parseTime(b.createdAt);
      return ta.compareTo(tb);
    });
    return list;
  }

  int _parseTime(String? s) {
    if (s == null || s.isEmpty) return 0;
    final dt = DateTime.tryParse(s.trim());
    return dt?.millisecondsSinceEpoch ?? 0;
  }

  /// 发送文本消息。[localId] 客户端唯一 id，用于乐观更新与 WebSocket 去重。
  /// 后端为 nonce 时同时传 nonce 以兼容。
  Future<ChatMessageDto?> sendText(
    String roomId, {
    required String content,
    required String localId,
    String? replyId,
  }) async {
    final body = <String, dynamic>{
      'content': content,
      'nonce': localId,
      'local_id': localId,
      if (replyId != null && replyId.isNotEmpty) 'reply_id': replyId,
    };
    final res = await _dio.post<Map<String, dynamic>>(
      ApiConstants.messagerChatMessages(roomId),
      data: body,
    );
    final msgJson = res.data?['message'] as Map<String, dynamic>?;
    if (msgJson == null) return null;
    return ChatMessageDto.fromJson(msgJson);
  }

  /// 发送图片消息：先上传得到 url，再发带 attachments 的消息。
  Future<ChatMessageDto?> sendImage(
    String roomId, {
    required String imagePath,
    required String localId,
    String? caption,
  }) async {
    final url = await uploadFile(imagePath);
    if (url.isEmpty) return null;
    final attachments = <Map<String, dynamic>>[
      <String, dynamic>{
        'id': '',
        'name': 'image',
        'url': url,
        'mime_type': 'image/jpeg',
      },
    ];
    final body = <String, dynamic>{
      'content': caption ?? '',
      'nonce': localId,
      'local_id': localId,
      'attachments': attachments,
    };
    final res = await _dio.post<Map<String, dynamic>>(
      ApiConstants.messagerChatMessages(roomId),
      data: body,
    );
    final msgJson = res.data?['message'] as Map<String, dynamic>?;
    if (msgJson == null) return null;
    return ChatMessageDto.fromJson(msgJson);
  }

  Future<String> uploadFile(String path) async {
    try {
      final formData = FormData.fromMap(<String, dynamic>{
        'file': await MultipartFile.fromFile(path, filename: 'image.jpg'),
      });
      final res = await _dio.post<Map<String, dynamic>>(
        ApiConstants.upload,
        data: formData,
        options: Options(contentType: 'multipart/form-data'),
      );
      final url =
          (res.data?['url'] as String? ?? res.data?['path'] as String? ?? '')
              .trim();
      if (url.isEmpty) return '';
      if (url.startsWith('http://') || url.startsWith('https://')) return url;
      return toAbsoluteImageUrl(url);
    } catch (_) {
      return '';
    }
  }

  /// 撤回/删除消息。
  Future<void> deleteMessage(String roomId, String messageId) async {
    await _dio.delete<void>(
      ApiConstants.messagerChatMessage(roomId, messageId),
    );
  }
}
