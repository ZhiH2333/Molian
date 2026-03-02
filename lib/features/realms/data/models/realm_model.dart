/// 圈子模型，与 API 响应一致。
class RealmModel {
  const RealmModel({
    required this.id,
    required this.name,
    required this.slug,
    this.description,
    this.avatarUrl,
    this.bannerUrl,
    this.createdAt,
    this.joined = false,
    this.isCreator = false,
  });

  final String id;
  final String name;
  final String slug;
  final String? description;
  final String? avatarUrl;
  final String? bannerUrl;
  final String? createdAt;
  final bool joined;
  final bool isCreator;

  factory RealmModel.fromJson(Map<String, dynamic> json) {
    return RealmModel(
      id: json['id'] as String,
      name: json['name'] as String,
      slug: json['slug'] as String,
      description: _readNullableString(json, <String>['description']),
      avatarUrl: _readNullableString(json, <String>['avatar_url', 'avatarUrl']),
      bannerUrl: _readNullableString(json, <String>['banner_url', 'bannerUrl']),
      createdAt: _readNullableString(json, <String>['created_at', 'createdAt']),
      joined: json['joined'] as bool? ?? false,
      isCreator: json['is_creator'] as bool? ?? false,
    );
  }

  static String? _readNullableString(
    Map<String, dynamic> json,
    List<String> keys,
  ) {
    for (final String key in keys) {
      final dynamic raw = json[key];
      if (raw == null) continue;
      final String value = raw.toString().trim();
      if (value.isEmpty) return null;
      if (value.toLowerCase() == 'null') return null;
      return value;
    }
    return null;
  }
}
