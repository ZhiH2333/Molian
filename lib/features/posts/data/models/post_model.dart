import 'dart:convert' show jsonDecode;

/// 帖子模型，与 API 响应一致。
class PostModel {
  const PostModel({
    required this.id,
    required this.userId,
    required this.content,
    this.title = '',
    this.imageUrls,
    this.isPublic = true,
    this.communityIds,
    this.createdAt,
    this.updatedAt,
    this.likeCount = 0,
    this.liked = false,
    this.commentCount = 0,
    this.viewCount = 0,
    this.repostCount = 0,
    this.isReposted = false,
    this.isBookmarked = false,
    this.user,
  });

  final String id;
  final String userId;
  final String content;
  final String title;
  final List<String>? imageUrls;
  final bool isPublic;
  final List<String>? communityIds;
  final String? createdAt;
  final String? updatedAt;
  final int likeCount;
  final bool liked;
  final int commentCount;
  final int viewCount;
  final int repostCount;
  final bool isReposted;
  final bool isBookmarked;
  final PostUser? user;

  factory PostModel.fromJson(Map<String, dynamic> json) {
    List<String>? urls;
    if (json['image_urls'] != null) {
      if (json['image_urls'] is List) {
        urls = (json['image_urls'] as List).map((e) => e.toString()).toList();
      } else if (json['image_urls'] is String) {
        try {
          final decoded = jsonDecode(json['image_urls'] as String) as List<dynamic>?;
          urls = decoded?.map((e) => e.toString()).toList();
        } catch (_) {
          urls = null;
        }
      }
    }
    List<String>? communityIds;
    if (json['community_ids'] is List) {
      communityIds = (json['community_ids'] as List).map((e) => e.toString()).toList();
    }
    PostUser? u;
    if (json['user'] is Map<String, dynamic>) {
      u = PostUser.fromJson(json['user'] as Map<String, dynamic>);
    }
    final isPublicRaw = json['is_public'];
    final bool isPublic = isPublicRaw == true || isPublicRaw == 1;
    return PostModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      content: json['content'] as String,
      title: (json['title'] as String?)?.trim() ?? '',
      imageUrls: urls,
      isPublic: isPublic,
      communityIds: communityIds,
      createdAt: json['created_at'] as String?,
      updatedAt: json['updated_at'] as String?,
      likeCount: (json['like_count'] as num?)?.toInt() ?? 0,
      liked: json['liked'] as bool? ?? false,
      commentCount: (json['comment_count'] as num?)?.toInt() ?? 0,
      viewCount: (json['view_count'] as num?)?.toInt() ?? 0,
      repostCount: (json['repost_count'] as num?)?.toInt() ?? 0,
      isReposted: json['is_reposted'] as bool? ?? false,
      isBookmarked: json['is_bookmarked'] as bool? ?? false,
      user: u,
    );
  }
}

/// 帖子中的用户摘要。
class PostUser {
  const PostUser({
    this.username,
    this.displayName,
    this.avatarUrl,
  });

  final String? username;
  final String? displayName;
  final String? avatarUrl;

  factory PostUser.fromJson(Map<String, dynamic> json) {
    return PostUser(
      username: json['username'] as String?,
      displayName: json['display_name'] as String?,
      avatarUrl: json['avatar_url'] as String?,
    );
  }
}
