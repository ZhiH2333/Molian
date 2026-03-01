import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../posts/providers/posts_providers.dart';
import 'create_post_state.dart';

final createPostControllerProvider =
    NotifierProvider<CreatePostController, CreatePostState>(
  CreatePostController.new,
);

class CreatePostController extends Notifier<CreatePostState> {
  @override
  CreatePostState build() => const CreatePostState();

  void setTitle(String value) {
    state = state.copyWith(title: value, errorMessage: null);
  }

  void setContent(String value) {
    state = state.copyWith(content: value, errorMessage: null);
  }

  void setSelectedCommunityIds(List<String> ids) {
    bool isCircleOnly = state.isCircleOnly;
    if (ids.isEmpty) isCircleOnly = false;
    state = state.copyWith(
      selectedCommunityIds: ids,
      isCircleOnly: isCircleOnly,
      errorMessage: null,
    );
  }

  void setCircleOnly(bool value) {
    if (!state.canToggleCircleOnly) return;
    state = state.copyWith(isCircleOnly: value, errorMessage: null);
  }

  Future<bool> submit() async {
    final title = state.title.trim();
    final content = state.content.trim();
    if (content.isEmpty) {
      state = state.copyWith(errorMessage: '请填写内容');
      return false;
    }
    final ids = state.selectedCommunityIds;
    final isCircleOnly = ids.isNotEmpty && state.isCircleOnly;
    final isPublic = ids.isEmpty || !isCircleOnly;
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final repo = ref.read(postsRepositoryProvider);
      await repo.createPost(
        title: title.isEmpty ? content.split('\n').firstOrNull ?? content : title,
        content: content,
        isPublic: isPublic,
        communityIds: ids.isEmpty ? null : ids,
      );
      ref.invalidate(postsListProvider(const PostsListKey()));
      ref.invalidate(feedsListProvider(const PostsListKey()));
      state = state.copyWith(isLoading: false);
      return true;
    } catch (e) {
      final message = e.toString().replaceFirst('Exception: ', '');
      state = state.copyWith(isLoading: false, errorMessage: message);
      return false;
    }
  }

  void clearError() {
    state = state.copyWith(errorMessage: null);
  }
}
