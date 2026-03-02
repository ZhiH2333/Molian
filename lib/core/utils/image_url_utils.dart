import '../constants/api_constants.dart';

/// 将可能为相对路径或不同域名的图片 URL 转为应用配置的 API 完整地址，确保 CachedNetworkImage 能加载。
/// 凡包含 /api/asset/ 的地址一律用 [ApiConstants.baseUrl] 拼出，避免服务端返回的 origin 与客户端不一致导致无法显示。
String fullImageUrl(String? url) {
  final raw = url?.trim();
  if (raw == null || raw.isEmpty || raw.toLowerCase() == 'null') return '';

  final base = ApiConstants.baseUrl;
  final String pathAndQuery;
  if (raw.startsWith('http://') || raw.startsWith('https://')) {
    try {
      final uri = Uri.parse(raw);
      pathAndQuery = uri.path + (uri.query.isEmpty ? '' : '?${uri.query}');
    } catch (_) {
      return raw;
    }
  } else {
    pathAndQuery = raw.startsWith('/') ? raw : '/$raw';
  }

  final normalizedPath = pathAndQuery.startsWith('/')
      ? pathAndQuery
      : '/$pathAndQuery';

  if (normalizedPath.startsWith('/api/asset/')) {
    String keyPart = normalizedPath.replaceFirst('/api/asset/', '');
    final int queryIndex = keyPart.indexOf('?');
    if (queryIndex >= 0) {
      keyPart = keyPart.substring(0, queryIndex);
    }
    if (keyPart.isEmpty) {
      return raw.startsWith('http')
          ? raw
          : (base.endsWith('/') ? '${base}api/asset/' : '$base/api/asset/');
    }
    // 历史数据里可能出现重复编码（%252F），这里做有限次 decode 以还原真实 key。
    for (int i = 0; i < 3; i++) {
      final String decoded = Uri.decodeComponent(keyPart);
      if (decoded == keyPart) break;
      keyPart = decoded;
    }
    final encodedKey = Uri.encodeComponent(keyPart);
    return base.endsWith('/')
        ? '${base}api/asset/$encodedKey'
        : '$base/api/asset/$encodedKey';
  }

  if (raw.startsWith('http')) return raw;

  final noLeadingSlash = normalizedPath.startsWith('/')
      ? normalizedPath.replaceFirst('/', '')
      : normalizedPath;
  if (noLeadingSlash.startsWith('assets/')) {
    final encodedKey = Uri.encodeComponent(noLeadingSlash);
    return base.endsWith('/')
        ? '${base}api/asset/$encodedKey'
        : '$base/api/asset/$encodedKey';
  }

  return base.endsWith('/') ? '$base$noLeadingSlash' : '$base$normalizedPath';
}
