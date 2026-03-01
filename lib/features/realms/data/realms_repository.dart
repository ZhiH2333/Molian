import 'package:dio/dio.dart';

import '../../../core/constants/api_constants.dart';
import '../../posts/data/models/post_model.dart';
import 'models/realm_model.dart';

/// 圈子列表 scope：已加入、我创建的、全部。
enum RealmsScope {
  joined,
  mine,
  all,
}

/// 圈子接口：列表（按 scope/搜索）、详情、加入、退出、创建。
class RealmsRepository {
  RealmsRepository({required Dio dio}) : _dio = dio;
  final Dio _dio;

  Future<List<RealmModel>> fetchRealms({
    RealmsScope scope = RealmsScope.all,
    String? query,
  }) async {
    final queryParams = <String, String>{
      'scope': switch (scope) {
        RealmsScope.joined => 'joined',
        RealmsScope.mine => 'mine',
        RealmsScope.all => 'all',
      },
    };
    if (query != null && query.trim().isNotEmpty) {
      queryParams['q'] = query.trim();
    }
    final uri = Uri.parse(ApiConstants.realms).replace(queryParameters: queryParams);
    final response = await _dio.get<Map<String, dynamic>>(uri.toString());
    final data = response.data;
    if (data == null || data['realms'] is! List) return [];
    return (data['realms'] as List)
        .map((e) => RealmModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<RealmModel> createRealm({
    required String name,
    String? slug,
    String? description,
  }) async {
    final body = <String, dynamic>{
      'name': name,
      if (slug != null && slug.trim().isNotEmpty) 'slug': slug.trim(),
      if (description != null && description.trim().isNotEmpty) 'description': description.trim(),
    };
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        ApiConstants.realms,
        data: body,
      );
      final data = response.data;
      if (data == null || data['realm'] == null) throw Exception('创建圈子响应异常');
      return RealmModel.fromJson(data['realm'] as Map<String, dynamic>);
    } on DioException catch (e) {
      String? msg;
      if (e.response?.data is Map<String, dynamic>) {
        final data = e.response!.data!;
        msg = data['error'] as String? ?? data['message'] as String?;
      }
      final statusCode = e.response?.statusCode;
      if (msg == null && statusCode != null) {
        if (statusCode == 401) msg = '未登录，请先登录';
        else if (statusCode == 404) msg = '接口未就绪，请确认已部署最新版 Worker';
        else if (statusCode >= 500) msg = '服务器错误，请稍后重试';
      }
      throw Exception(msg ?? e.message ?? '创建失败');
    }
  }

  Future<RealmModel?> getRealm(String id) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(ApiConstants.realmById(id));
      final data = response.data;
      if (data == null || data['realm'] == null) return null;
      return RealmModel.fromJson(data['realm'] as Map<String, dynamic>);
    } on DioException catch (_) {
      return null;
    }
  }

  Future<void> joinRealm(String realmId) async {
    await _dio.post<Map<String, dynamic>>(ApiConstants.realmJoin(realmId));
  }

  Future<void> leaveRealm(String realmId) async {
    await _dio.post<Map<String, dynamic>>(ApiConstants.realmLeave(realmId));
  }

  /// 获取某圈子下的帖子列表。
  Future<List<PostModel>> fetchRealmPosts(String realmId, {int limit = 20, String? cursor}) async {
    final query = <String, String>{'limit': limit.toString()};
    if (cursor != null && cursor.isNotEmpty) query['cursor'] = cursor;
    final uri = Uri.parse(ApiConstants.realmPosts(realmId)).replace(queryParameters: query);
    final response = await _dio.get<Map<String, dynamic>>(uri.toString());
    final data = response.data;
    if (data == null || data['posts'] is! List) return <PostModel>[];
    return (data['posts'] as List)
        .map((e) => PostModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 更新圈子（仅创建者）。可选 name、slug、description。
  Future<RealmModel> updateRealm(String id, {String? name, String? slug, String? description}) async {
    final body = <String, dynamic>{};
    if (name != null && name.trim().isNotEmpty) body['name'] = name.trim();
    if (slug != null && slug.trim().isNotEmpty) body['slug'] = slug.trim();
    if (description != null) body['description'] = description.trim().isEmpty ? null : description.trim();
    if (body.isEmpty) throw Exception('无有效更新字段');
    final response = await _dio.patch<Map<String, dynamic>>(ApiConstants.realmById(id), data: body);
    final data = response.data;
    if (data == null || data['realm'] == null) throw Exception('更新圈子响应异常');
    return RealmModel.fromJson(data['realm'] as Map<String, dynamic>);
  }

  /// 删除圈子（仅创建者）。
  Future<void> deleteRealm(String id) async {
    await _dio.delete<Map<String, dynamic>>(ApiConstants.realmById(id));
  }
}
