import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../core/constants/api_constants.dart';
import 'models/file_model.dart';

/// 文件接口：列表、上传后确认登记。
class FilesRepository {
  FilesRepository({required Dio dio}) : _dio = dio;
  final Dio _dio;

  /// 从上传返回的 url 中解析 R2 key（/api/asset/ 后的部分 decode 后即为 key）。
  static String keyFromAssetUrl(String url) {
    final uri = Uri.parse(url);
    if (uri.pathSegments.length >= 3 && uri.pathSegments[0] == 'api' && uri.pathSegments[1] == 'asset') {
      return Uri.decodeComponent(uri.pathSegments.sublist(2).join('/'));
    }
    return uri.path.replaceFirst('/api/asset/', '');
  }

  /// 上传文件（字节）并登记到文件列表；返回登记后的 FileModel。
  /// 可选 [onSendProgress] 与 [cancelToken] 用于进度与取消。
  Future<FileModel> uploadAndConfirm(
    Uint8List bytes, {
    required String filename,
    required String mimeType,
    ProgressCallback? onSendProgress,
    CancelToken? cancelToken,
  }) async {
    final parts = mimeType.split('/');
    final contentType = parts.length >= 2 ? DioMediaType(parts[0], parts[1]) : DioMediaType('application', 'octet-stream');
    final formData = FormData.fromMap(<String, dynamic>{
      'file': MultipartFile.fromBytes(bytes, filename: filename, contentType: contentType),
    });
    final response = await _dio.post<Map<String, dynamic>>(
      ApiConstants.upload,
      data: formData,
      options: Options(contentType: 'multipart/form-data'),
      onSendProgress: onSendProgress,
      cancelToken: cancelToken,
    );
    final data = response.data;
    if (data == null || data['url'] is! String) throw Exception('上传失败');
    final url = data['url'] as String;
    final key = keyFromAssetUrl(url);
    return confirmUpload(key: key, name: filename, size: bytes.length, mimeType: mimeType);
  }

  Future<List<FileModel>> fetchFiles() async {
    final response = await _dio.get<Map<String, dynamic>>(ApiConstants.files);
    final data = response.data;
    if (data == null || data['files'] is! List) return [];
    return (data['files'] as List)
        .map((e) => FileModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 上传完成后调用，将 R2 中的文件登记到数据库。
  Future<FileModel> confirmUpload({
    required String key,
    String? name,
    int size = 0,
    String? mimeType,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      ApiConstants.filesConfirm,
      data: <String, dynamic>{
        'key': key,
        if (name != null && name.isNotEmpty) 'name': name,
        if (size > 0) 'size': size,
        if (mimeType != null) 'mime_type': mimeType,
      },
    );
    final data = response.data;
    if (data == null || data['file'] == null) throw Exception('登记失败');
    return FileModel.fromJson(data['file'] as Map<String, dynamic>);
  }

  /// 获取文件访问 URL（R2 通过 /api/asset/:key 提供）。
  static String getAssetUrl(String key) => ApiConstants.assetUrl(key);
}
