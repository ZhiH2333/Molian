/// 圈子模型，与 API 响应一致。
class RealmModel {
  const RealmModel({
    required this.id,
    required this.name,
    required this.slug,
    this.description,
    this.avatarUrl,
    this.createdAt,
    this.joined = false,
    this.isCreator = false,
  });

  final String id;
  final String name;
  final String slug;
  final String? description;
  final String? avatarUrl;
  final String? createdAt;
  final bool joined;
  final bool isCreator;

  factory RealmModel.fromJson(Map<String, dynamic> json) {
    return RealmModel(
      id: json['id'] as String,
      name: json['name'] as String,
      slug: json['slug'] as String,
      description: json['description'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      createdAt: json['created_at'] as String?,
      joined: json['joined'] as bool? ?? false,
      isCreator: json['is_creator'] as bool? ?? false,
    );
  }
}
