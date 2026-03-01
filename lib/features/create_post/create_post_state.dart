/// 发布帖子页状态：标题、描述、内容、已选圈子、仅圈子可见、编辑用 postId、加载与错误。
class CreatePostState {
  const CreatePostState({
    this.title = '',
    this.description = '',
    this.content = '',
    this.selectedCommunityIds = const [],
    this.isCircleOnly = false,
    this.postId,
    this.isLoading = false,
    this.errorMessage,
  });

  final String title;
  final String description;
  final String content;
  final List<String> selectedCommunityIds;
  final bool isCircleOnly;
  final String? postId;
  final bool isLoading;
  final String? errorMessage;

  bool get hasCommunities => selectedCommunityIds.isNotEmpty;

  bool get canToggleCircleOnly => hasCommunities;

  bool get effectiveIsPublic => !isCircleOnly;

  bool get isEditMode => postId != null && postId!.isNotEmpty;

  CreatePostState copyWith({
    String? title,
    String? description,
    String? content,
    List<String>? selectedCommunityIds,
    bool? isCircleOnly,
    String? postId,
    bool? isLoading,
    String? errorMessage,
  }) {
    return CreatePostState(
      title: title ?? this.title,
      description: description ?? this.description,
      content: content ?? this.content,
      selectedCommunityIds: selectedCommunityIds ?? this.selectedCommunityIds,
      isCircleOnly: isCircleOnly ?? this.isCircleOnly,
      postId: postId ?? this.postId,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }
}
