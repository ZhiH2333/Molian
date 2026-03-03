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

  void setDescription(String value) {
    state = state.copyWith(description: value, errorMessage: null);
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

  void setImageUrls(List<String> urls) {
    state = state.copyWith(imageUrls: urls, errorMessage: null);
  }

  void addImageUrl(String url) {
    state = state.copyWith(
      imageUrls: [...state.imageUrls, url],
      errorMessage: null,
    );
  }

  void removeImageUrl(String url) {
    state = state.copyWith(
      imageUrls: state.imageUrls.where((String u) => u != url).toList(),
      errorMessage: null,
    );
  }

  /// 进入编辑模式并预填帖子数据。
  void setEditPost(
    String postId,
    String title,
    String description,
    String content,
    List<String> communityIds,
    bool isCircleOnly,
  ) {
    state = state.copyWith(
      postId: postId,
      title: title,
      description: description,
      content: content,
      selectedCommunityIds: communityIds,
      isCircleOnly: isCircleOnly,
      errorMessage: null,
    );
  }

  /// 清除编辑模式，回到发布新帖。
  void clearEditMode() {
    state = state.copyWith(
      postId: null,
      imageUrls: const [],
      errorMessage: null,
    );
  }

  Future<bool> submit() async {
    final title = state.title.trim();
    final description = state.description.trim();
    final body = state.content.trim();
    final content = description.isEmpty
        ? body
        : (body.isEmpty ? description : '$description\n$body');
    if (content.isEmpty) {
      state = state.copyWith(errorMessage: '请填写内容或描述');
      return false;
    }
    final ids = state.selectedCommunityIds;
    final isCircleOnly = ids.isNotEmpty && state.isCircleOnly;
    final isPublic = ids.isEmpty || !isCircleOnly;
    final effectiveTitle = title.isEmpty
        ? (content.split('\n').firstOrNull ?? content)
        : title;
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final repo = ref.read(postsRepositoryProvider);
      if (state.isEditMode && state.postId != null) {
        await repo.updatePost(
          state.postId!,
          title: effectiveTitle,
          content: content,
          isPublic: isPublic,
          communityIds: ids.isEmpty ? <String>[] : ids,
          imageUrls: state.imageUrls.isEmpty ? null : state.imageUrls,
        );
        // 失效整个 family，确保所有分页 key 都会重拉，避免 Web 返回后仍命中旧缓存。
        ref.invalidate(postsListProvider);
        ref.invalidate(feedsListProvider);
        ref.invalidate(postDetailProvider(state.postId!));
      } else {
        await repo.createPost(
          title: effectiveTitle,
          content: content,
          isPublic: isPublic,
          communityIds: ids.isEmpty ? null : ids,
          imageUrls: state.imageUrls.isEmpty ? null : state.imageUrls,
        );
        ref.invalidate(postsListProvider);
        ref.invalidate(feedsListProvider);
      }
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
