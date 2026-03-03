import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/constants/api_constants.dart';
import 'models/post_model.dart';

/// 帖子列表分页结果。
class PostsPageResult {
  const PostsPageResult({required this.posts, this.nextCursor});
  final List<PostModel> posts;
  final String? nextCursor;
}

/// 帖子接口：列表、发布、单条、上传图片。
class PostsRepository {
  PostsRepository({required Dio dio}) : _dio = dio;
  final Dio _dio;

  Future<PostsPageResult> fetchPosts({int limit = 20, String? cursor}) async {
    final query = <String, String>{'limit': limit.toString()};
    if (cursor != null && cursor.isNotEmpty) query['cursor'] = cursor;
    final uri = Uri.parse(ApiConstants.posts).replace(queryParameters: query);
    final response = await _dio.get<Map<String, dynamic>>(uri.toString());
    final data = response.data;
    if (data == null || data['posts'] is! List)
      return const PostsPageResult(posts: []);
    final list = (data['posts'] as List)
        .map((e) => PostModel.fromJson(e as Map<String, dynamic>))
        .toList();
    final nextCursor = data['nextCursor'] as String?;
    return PostsPageResult(posts: list, nextCursor: nextCursor);
  }

  /// 发现流（与帖子列表结构一致，使用 /api/feeds）。
  Future<PostsPageResult> fetchFeeds({int limit = 20, String? cursor}) async {
    final query = <String, String>{'limit': limit.toString()};
    if (cursor != null && cursor.isNotEmpty) query['cursor'] = cursor;
    final uri = Uri.parse(ApiConstants.feeds).replace(queryParameters: query);
    final response = await _dio.get<Map<String, dynamic>>(uri.toString());
    final data = response.data;
    if (data == null || data['posts'] is! List)
      return const PostsPageResult(posts: []);
    final list = (data['posts'] as List)
        .map((e) => PostModel.fromJson(e as Map<String, dynamic>))
        .toList();
    final nextCursor = data['nextCursor'] as String?;
    return PostsPageResult(posts: list, nextCursor: nextCursor);
  }

  Future<PostModel> createPost({
    required String title,
    required String content,
    List<String>? imageUrls,
    bool isPublic = true,
    List<String>? communityIds,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        ApiConstants.posts,
        data: <String, dynamic>{
          'title': title,
          'content': content,
          'is_public': isPublic,
          if (imageUrls != null && imageUrls.isNotEmpty)
            'image_urls': imageUrls,
          if (communityIds != null && communityIds.isNotEmpty)
            'community_ids': communityIds,
        },
      );
      final data = response.data;
      if (data == null || data['post'] == null) throw Exception('发布响应异常');
      return PostModel.fromJson(data['post'] as Map<String, dynamic>);
    } on DioException catch (e) {
      final msg = _messageFromDioException(e);
      final code = e.response?.statusCode;
      final detail = code != null ? '$msg ($code)' : msg;
      throw Exception(detail);
    }
  }

  Future<PostModel?> getPost(String id) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '${ApiConstants.posts}/$id',
      );
      final data = response.data;
      if (data == null || data['post'] == null) return null;
      return PostModel.fromJson(data['post'] as Map<String, dynamic>);
    } on DioException catch (_) {
      return null;
    }
  }

  /// 记录帖子被浏览一次（用户刷到即上报，后端需实现 POST /api/posts/:id/view）。
  Future<void> recordPostView(String postId) async {
    try {
      await _dio.post<dynamic>(ApiConstants.postView(postId));
    } on DioException catch (_) {
      // 后端未实现或网络失败时静默忽略，不影响列表展示。
    }
  }

  /// 更新帖子，仅发布者有权编辑。支持 title、content、is_public、community_ids、image_urls。
  Future<PostModel> updatePost(
    String id, {
    String? title,
    String? content,
    bool? isPublic,
    List<String>? communityIds,
    List<String>? imageUrls,
  }) async {
    final data = <String, dynamic>{};
    if (title != null) data['title'] = title;
    if (content != null) data['content'] = content;
    if (isPublic != null) data['is_public'] = isPublic;
    if (communityIds != null) data['community_ids'] = communityIds;
    if (imageUrls != null) data['image_urls'] = imageUrls;
    if (data.isEmpty) throw Exception('无有效更新字段');
    try {
      final response = await _dio.patch<Map<String, dynamic>>(
        '${ApiConstants.posts}/$id',
        data: data,
      );
      final responseData = response.data;
      if (responseData == null || responseData['post'] == null)
        throw Exception('更新响应异常');
      return PostModel.fromJson(responseData['post'] as Map<String, dynamic>);
    } on DioException catch (e) {
      final msg = _messageFromDioException(e);
      final code = e.response?.statusCode;
      final detail = code != null ? '$msg ($code)' : msg;
      throw Exception(detail);
    }
  }

  /// 从 Dio 错误中解析可读信息：优先使用服务端 error/message，404 时给出友好提示。
  static String _messageFromDioException(DioException e) {
    final code = e.response?.statusCode;
    final body = e.response?.data;
    if (body is Map<String, dynamic>) {
      final err = body['error'] as String? ?? body['message'] as String?;
      if (err != null && err.isNotEmpty) return err;
    }
    if (code == 404) return '接口不存在(404)，请检查 API 地址或稍后重试';
    if (code == 401) return '未登录或登录已过期，请重新登录';
    if (code != null && code >= 400) return '请求失败($code)';
    return e.message ?? '网络错误';
  }

  /// 删除帖子，仅发布者有权删除。
  Future<void> deletePost(String id) async {
    await _dio.delete<Map<String, dynamic>>('${ApiConstants.posts}/$id');
  }

  /// 上传单张图片（本地路径），仅非 Web 平台。Web 请用 [uploadImageFromBytes]。
  Future<String> uploadImage(String path, {required String mimeType}) async {
    if (kIsWeb) {
      throw UnsupportedError('Web 端请使用 uploadImageFromBytes');
    }
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        path,
        filename: path.split('/').last,
      ),
    });
    return _uploadFormData(formData);
  }

  /// 上传单张图片（字节），Web 与各平台通用。
  /// 可选 [onSendProgress] 与 [cancelToken] 用于进度与取消。
  Future<String> uploadImageFromBytes(
    Uint8List bytes, {
    required String filename,
    required String mimeType,
    ProgressCallback? onSendProgress,
    CancelToken? cancelToken,
  }) async {
    final parts = mimeType.split('/');
    final contentType = parts.length >= 2
        ? DioMediaType(parts[0], parts[1])
        : null;
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        bytes,
        filename: filename,
        contentType: contentType,
      ),
    });
    return _uploadFormData(
      formData,
      onSendProgress: onSendProgress,
      cancelToken: cancelToken,
    );
  }

  Future<String> _uploadFormData(
    FormData formData, {
    ProgressCallback? onSendProgress,
    CancelToken? cancelToken,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        ApiConstants.upload,
        data: formData,
        options: Options(
          contentType: 'multipart/form-data',
          sendTimeout: const Duration(seconds: 60),
        ),
        onSendProgress: onSendProgress,
        cancelToken: cancelToken,
      );
      final data = response.data;
      if (data == null || data['url'] is! String) throw Exception('上传响应异常');
      final url = data['url'] as String;
      if (url.startsWith('http')) return url;
      return '${ApiConstants.baseUrl}$url';
    } on DioException catch (e) {
      final msg = _messageFromDioException(e);
      throw Exception(msg);
    }
  }
}
