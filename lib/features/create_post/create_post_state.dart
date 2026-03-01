/// 发布帖子页状态：标题、内容、已选圈子、仅圈子可见、加载与错误。
class CreatePostState {
  const CreatePostState({
    this.title = '',
    this.content = '',
    this.selectedCommunityIds = const [],
    this.isCircleOnly = false,
    this.isLoading = false,
    this.errorMessage,
  });

  final String title;
  final String content;
  final List<String> selectedCommunityIds;
  final bool isCircleOnly;
  final bool isLoading;
  final String? errorMessage;

  bool get hasCommunities => selectedCommunityIds.isNotEmpty;

  bool get canToggleCircleOnly => hasCommunities;

  bool get effectiveIsPublic => !isCircleOnly;

  CreatePostState copyWith({
    String? title,
    String? content,
    List<String>? selectedCommunityIds,
    bool? isCircleOnly,
    bool? isLoading,
    String? errorMessage,
  }) {
    return CreatePostState(
      title: title ?? this.title,
      content: content ?? this.content,
      selectedCommunityIds: selectedCommunityIds ?? this.selectedCommunityIds,
      isCircleOnly: isCircleOnly ?? this.isCircleOnly,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }
}
