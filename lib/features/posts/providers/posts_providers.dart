import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_provider.dart';
import '../data/models/post_model.dart';
import '../data/posts_repository.dart';

final postsRepositoryProvider = Provider<PostsRepository>((ref) {
  final dio = ref.watch(dioProvider);
  return PostsRepository(dio: dio);
});

/// 时间线帖子列表（分页）；refresh 与 loadMore 由调用方触发。
final postsListProvider = FutureProvider.family<PostsPageResult, PostsListKey>((ref, key) async {
  final repo = ref.watch(postsRepositoryProvider);
  return repo.fetchPosts(limit: key.limit, cursor: key.cursor);
});

/// 发现流帖子列表（分页）。
final feedsListProvider = FutureProvider.family<PostsPageResult, PostsListKey>((ref, key) async {
  final repo = ref.watch(postsRepositoryProvider);
  return repo.fetchFeeds(limit: key.limit, cursor: key.cursor);
});

/// 单条帖子详情 provider。
final postDetailProvider = FutureProvider.family<PostModel?, String>((ref, id) async {
  final repo = ref.watch(postsRepositoryProvider);
  return repo.getPost(id);
});

/// 本会话内已上报过浏览的帖子 id 集合，用于避免重复上报并用于本地展示 +1。
final recordedViewPostIdsProvider =
    StateProvider<Set<String>>((ref) => <String>{});

class PostsListKey {
  const PostsListKey({this.limit = 20, this.cursor});
  final int limit;
  final String? cursor;
  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is PostsListKey && limit == other.limit && cursor == other.cursor;
  @override
  int get hashCode => Object.hash(limit, cursor);
}
