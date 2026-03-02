import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/image_upload_constants.dart';
import '../../core/constants/layout_constants.dart';
import '../../core/image/image_compression_service.dart';
import '../../core/router/app_router.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/auto_leading_button.dart';
import '../../shared/widgets/upload_confirm_sheet.dart';
import '../files/data/files_repository.dart';
import '../files/providers/files_providers.dart';
import '../posts/data/models/post_model.dart';
import '../posts/providers/posts_providers.dart';
import '../realms/data/models/realm_model.dart';
import '../realms/data/realms_repository.dart';
import '../realms/providers/realms_providers.dart';
import 'create_post_controller.dart';
import 'create_post_state.dart';

/// 上传中单条：压缩后的字节与文件名。
class _UploadingEntry {
  _UploadingEntry({required this.id, this.bytes, this.filename});
  final String id;
  final Uint8List? bytes;
  final String? filename;
  String? error;
}

/// 发布帖子页：标题、内容、图片、圈子选择、仅圈子可见、发布；支持编辑模式（与创建界面一致）。
class CreatePostPage extends ConsumerStatefulWidget {
  const CreatePostPage({super.key, this.postId, this.initialPost});

  final String? postId;
  final PostModel? initialPost;

  @override
  ConsumerState<CreatePostPage> createState() => _CreatePostPageState();
}

class _CreatePostPageState extends ConsumerState<CreatePostPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleFocus = FocusNode();
  final _descriptionFocus = FocusNode();
  final _contentFocus = FocusNode();
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _contentController;
  bool _prefillDone = false;
  final List<_UploadingEntry> _uploadingEntries = [];
  static const _uuid = Uuid();

  void _removeUploadingEntry(_UploadingEntry entry) {
    setState(() => _uploadingEntries.removeWhere((e) => e.id == entry.id));
  }

  Future<void> _retryUploadingEntry(_UploadingEntry entry) async {
    if (entry.bytes == null || entry.filename == null) return;
    setState(() => entry.error = null);
    try {
      final repo = ref.read(postsRepositoryProvider);
      final url = await repo.uploadImageFromBytes(
        entry.bytes!,
        filename: entry.filename!,
        mimeType: 'image/jpeg',
      );
      if (!mounted) return;
      ref.read(createPostControllerProvider.notifier).addImageUrl(url);
      setState(() => _uploadingEntries.removeWhere((e) => e.id == entry.id));
    } catch (e) {
      if (mounted) {
        setState(() {
          entry.error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _descriptionController = TextEditingController();
    _contentController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initEditOrCreate());
  }

  void _initEditOrCreate() {
    if (!mounted) return;
    final notifier = ref.read(createPostControllerProvider.notifier);
    if (widget.postId == null) {
      notifier.clearEditMode();
      return;
    }
    if (widget.initialPost != null) {
      _prefillFromPost(widget.initialPost!, overwrite: false);
    }
    _loadAndPrefillPost(widget.postId!);
  }

  /// [overwrite] 为 true 时用服务端完整数据（含 community_ids）覆盖，用于编辑时拉取单帖后回填。
  void _prefillFromPost(PostModel post, {bool overwrite = false}) {
    if (!overwrite && _prefillDone) return;
    if (!mounted) return;
    if (overwrite) _prefillDone = true;
    final ids = post.communityIds ?? <String>[];
    final isCircleOnly = ids.isNotEmpty && !post.isPublic;
    ref.read(createPostControllerProvider.notifier).setEditPost(
      post.id,
      post.title,
      '',
      post.content,
      ids,
      isCircleOnly,
    );
    ref.read(createPostControllerProvider.notifier).setImageUrls(
      post.imageUrls ?? const <String>[],
    );
    _titleController.text = post.title;
    _descriptionController.text = '';
    _contentController.text = post.content;
  }

  Future<void> _loadAndPrefillPost(String postId) async {
    if (!mounted) return;
    final post = await ref.read(postsRepositoryProvider).getPost(postId);
    if (post != null && mounted) _prefillFromPost(post, overwrite: true);
  }

  @override
  void dispose() {
    _titleFocus.dispose();
    _descriptionFocus.dispose();
    _contentFocus.dispose();
    _titleController.dispose();
    _descriptionController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  int _totalImageCount(CreatePostState state) =>
      state.imageUrls.length + _uploadingEntries.length;

  Future<void> _pickImage() async {
    final state = ref.read(createPostControllerProvider);
    if (_totalImageCount(state) >= ImageUploadConstants.maxPostImages) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('最多添加 9 张图片')),
        );
      }
      return;
    }
    final xFile = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (xFile == null || !mounted) return;
    Uint8List previewBytes;
    try {
      previewBytes = await xFile.readAsBytes();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('读取图片失败: ${e.toString()}')),
        );
      }
      return;
    }
    if (!mounted) return;
    final fileName = xFile.name.isNotEmpty ? xFile.name : 'image.jpg';
    final confirmed = await showUploadConfirmSheet(
      context,
      fileName: fileName,
      imageBytes: previewBytes,
    );
    if (!confirmed || !mounted) return;
    Uint8List compressedBytes;
    try {
      compressedBytes = await ImageCompressionService.compressToBytes(
        previewBytes,
        maxBytesKb: ImageUploadConstants.postImageMaxKb,
        maxWidth: ImageUploadConstants.postImageMaxDimension,
        maxHeight: ImageUploadConstants.postImageMaxDimension,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('压缩失败: ${e.toString()}')),
        );
      }
      return;
    }
    if (!mounted) return;
    final name = fileName;
    final entry = _UploadingEntry(
      id: _uuid.v4(),
      bytes: compressedBytes,
      filename: name,
    );
    setState(() => _uploadingEntries.add(entry));
    try {
      final repo = ref.read(postsRepositoryProvider);
      final url = await repo.uploadImageFromBytes(
        compressedBytes,
        filename: name,
        mimeType: 'image/jpeg',
      );
      if (!mounted) return;
      ref.read(createPostControllerProvider.notifier).addImageUrl(url);
      setState(() => _uploadingEntries.removeWhere((e) => e.id == entry.id));
      try {
        final filesRepo = ref.read(filesRepositoryProvider);
        final key = FilesRepository.keyFromAssetUrl(url);
        await filesRepo.confirmUpload(
          key: key,
          name: name,
          size: compressedBytes.length,
          mimeType: 'image/jpeg',
        );
        ref.invalidate(filesListProvider);
      } catch (_) {}
    } catch (e) {
      if (mounted) {
        setState(() {
          final idx = _uploadingEntries.indexWhere((e) => e.id == entry.id);
          if (idx >= 0) {
            _uploadingEntries[idx].error = e.toString().replaceFirst('Exception: ', '');
          }
        });
      }
    }
  }

  void _openCirclePicker() {
    final state = ref.read(createPostControllerProvider);
    final selected = List<String>.from(state.selectedCommunityIds);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (BuildContext sheetContext) {
        return _CirclePickerSheet(
          selectedIds: selected,
          onConfirm: (List<String> ids) {
            ref.read(createPostControllerProvider.notifier).setSelectedCommunityIds(ids);
            if (!context.mounted) return;
            Navigator.of(sheetContext).pop();
          },
        );
      },
    );
  }

  Future<void> _submit() async {
    ref.read(createPostControllerProvider.notifier).clearError();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final notifier = ref.read(createPostControllerProvider.notifier);
    final success = await notifier.submit();
    if (!mounted) return;
    if (success) {
      context.go(AppRoutes.home);
      final isEdit = ref.read(createPostControllerProvider).isEditMode;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isEdit ? '已保存' : '发布成功'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      final message = ref.read(createPostControllerProvider).errorMessage ?? '发布失败';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Theme.of(context).colorScheme.errorContainer,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(createPostControllerProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AppScaffold(
      appBar: AppBar(
        leading: const AutoLeadingButton(),
        title: Text(state.isEditMode ? '编辑' : '发布'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.symmetric(
            horizontal: LayoutConstants.kSpacingXLarge,
            vertical: LayoutConstants.kSpacingLarge,
          ),
          children: <Widget>[
            TextFormField(
              controller: _titleController,
              onChanged: ref.read(createPostControllerProvider.notifier).setTitle,
              focusNode: _titleFocus,
              decoration: InputDecoration(
                labelText: '标题',
                hintText: '选填',
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: LayoutConstants.kRadiusMediumBR,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: LayoutConstants.kRadiusMediumBR,
                  borderSide: BorderSide(color: colorScheme.outlineVariant),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: LayoutConstants.kRadiusMediumBR,
                  borderSide: BorderSide(color: colorScheme.primary, width: 2),
                ),
              ),
              style: theme.textTheme.headlineSmall,
              maxLines: 1,
              enabled: !state.isLoading,
              textInputAction: TextInputAction.next,
              onFieldSubmitted: (_) => FocusScope.of(context).requestFocus(_descriptionFocus),
            ),
            const SizedBox(height: LayoutConstants.kSpacingLarge),
            TextFormField(
              controller: _descriptionController,
              onChanged: ref.read(createPostControllerProvider.notifier).setDescription,
              focusNode: _descriptionFocus,
              decoration: InputDecoration(
                labelText: '描述',
                hintText: '选填',
                alignLabelWithHint: true,
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: LayoutConstants.kRadiusMediumBR,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: LayoutConstants.kRadiusMediumBR,
                  borderSide: BorderSide(color: colorScheme.outlineVariant),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: LayoutConstants.kRadiusMediumBR,
                  borderSide: BorderSide(color: colorScheme.primary, width: 2),
                ),
              ),
              style: theme.textTheme.bodyLarge,
              maxLines: 2,
              enabled: !state.isLoading,
              textInputAction: TextInputAction.next,
              onFieldSubmitted: (_) => FocusScope.of(context).requestFocus(_contentFocus),
            ),
            const SizedBox(height: LayoutConstants.kSpacingLarge),
            TextFormField(
              controller: _contentController,
              onChanged: ref.read(createPostControllerProvider.notifier).setContent,
              focusNode: _contentFocus,
              decoration: InputDecoration(
                labelText: '内容',
                hintText: '写点什么...',
                alignLabelWithHint: true,
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: LayoutConstants.kRadiusMediumBR,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: LayoutConstants.kRadiusMediumBR,
                  borderSide: BorderSide(color: colorScheme.outlineVariant),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: LayoutConstants.kRadiusMediumBR,
                  borderSide: BorderSide(color: colorScheme.primary, width: 2),
                ),
              ),
              style: theme.textTheme.bodyLarge,
              maxLines: 6,
              minLines: 3,
              enabled: !state.isLoading,
              validator: (String? v) {
                final body = (v ?? '').trim();
                final desc = ref.read(createPostControllerProvider).description.trim();
                if (body.isEmpty && desc.isEmpty) return '请填写描述或内容';
                return null;
              },
            ),
            const SizedBox(height: LayoutConstants.kSpacingLarge),
            if (state.imageUrls.isNotEmpty) ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: state.imageUrls.map((String url) {
                  return Stack(
                    children: <Widget>[
                      SizedBox(
                        width: 80,
                        height: 80,
                        child: Image.network(url, fit: BoxFit.cover),
                      ),
                      Positioned(
                        top: 0,
                        right: 0,
                        child: IconButton(
                          icon: const Icon(Icons.close, color: Colors.white, size: 20),
                          onPressed: state.isLoading
                              ? null
                              : () => ref.read(createPostControllerProvider.notifier).removeImageUrl(url),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
            ],
            if (_uploadingEntries.isNotEmpty) ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _uploadingEntries.map((_UploadingEntry entry) {
                  return SizedBox(
                    width: 80,
                    height: 80,
                    child: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: entry.error != null
                              ? Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: <Widget>[
                                      Text(
                                        entry.error!,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(fontSize: 10, color: colorScheme.error),
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: <Widget>[
                                          IconButton(
                                            icon: const Icon(Icons.refresh, size: 18),
                                            onPressed: () => _retryUploadingEntry(entry),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.close, size: 18),
                                            onPressed: () => _removeUploadingEntry(entry),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                )
                              : const Center(
                                  child: SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
            ],
            OutlinedButton.icon(
              onPressed: state.isLoading ||
                      _totalImageCount(state) >= ImageUploadConstants.maxPostImages
                  ? null
                  : _pickImage,
              icon: const Icon(Icons.add_photo_alternate),
              label: const Text('添加图片'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: LayoutConstants.kRadiusMediumBR,
                ),
              ),
            ),
            const SizedBox(height: LayoutConstants.kSpacingLarge),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: LayoutConstants.kRadiusMediumBR,
                side: BorderSide(color: colorScheme.outlineVariant),
              ),
              child: Column(
                children: <Widget>[
                  ListTile(
                    leading: Icon(Icons.people_outline, color: colorScheme.primary),
                    title: const Text('链接到圈子'),
                    subtitle: state.hasCommunities
                        ? Text('已选 ${state.selectedCommunityIds.length} 个圈子')
                        : const Text('可选，发布后全站可见'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: state.isLoading ? null : _openCirclePicker,
                  ),
                  if (state.hasCommunities)
                    SwitchListTile(
                      secondary: Icon(Icons.visibility, color: colorScheme.primary),
                      title: const Text('仅圈子可见'),
                      subtitle: const Text('关闭则全站与圈子均可见'),
                      value: state.isCircleOnly,
                      onChanged: state.canToggleCircleOnly
                          ? (bool value) {
                              ref.read(createPostControllerProvider.notifier).setCircleOnly(value);
                            }
                          : null,
                    ),
                ],
              ),
            ),
            const SizedBox(height: LayoutConstants.kSpacingXLarge),
            FilledButton(
              onPressed: state.isLoading ? null : _submit,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: LayoutConstants.kRadiusMediumBR,
                ),
              ),
              child: state.isLoading
                  ? SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colorScheme.onPrimary,
                      ),
                    )
                  : Text(state.isEditMode ? '保存' : '发布'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 圈子多选 BottomSheet，内部使用 Consumer 获取圈子列表。
class _CirclePickerSheet extends ConsumerStatefulWidget {
  const _CirclePickerSheet({
    required this.selectedIds,
    required this.onConfirm,
  });

  final List<String> selectedIds;
  final void Function(List<String> ids) onConfirm;

  @override
  ConsumerState<_CirclePickerSheet> createState() => _CirclePickerSheetState();
}

class _CirclePickerSheetState extends ConsumerState<_CirclePickerSheet> {
  late List<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = List<String>.from(widget.selectedIds);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(realmsListProvider(const RealmsListKey(scope: RealmsScope.joined)));
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (BuildContext context, ScrollController scrollController) {
        return Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: LayoutConstants.kSpacingLarge,
                vertical: LayoutConstants.kSpacingMedium,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Text(
                    '选择圈子',
                    style: theme.textTheme.titleLarge,
                  ),
                  TextButton(
                    onPressed: () {
                      widget.onConfirm(_selected);
                    },
                    child: const Text('确定'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: async.when(
                data: (List<RealmModel> realms) {
                  if (realms.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(LayoutConstants.kSpacingLarge),
                        child: Text(
                          '暂无已加入的圈子，请先加入圈子后再选择',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    );
                  }
                  return ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.only(bottom: LayoutConstants.kSpacingXLarge),
                    itemCount: realms.length,
                    itemBuilder: (BuildContext context, int index) {
                      final realm = realms[index];
                      final isSelected = _selected.contains(realm.id);
                      return CheckboxListTile(
                        value: isSelected,
                        onChanged: (bool? value) {
                          setState(() {
                            if (value == true) {
                              _selected.add(realm.id);
                            } else {
                              _selected.remove(realm.id);
                            }
                          });
                        },
                        title: Text(realm.name),
                        subtitle: realm.description != null && realm.description!.isNotEmpty
                            ? Text(
                                realm.description!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall,
                              )
                            : null,
                      );
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (Object err, StackTrace? _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(LayoutConstants.kSpacingLarge),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(err.toString(), textAlign: TextAlign.center),
                        const SizedBox(height: LayoutConstants.kSpacingMedium),
                        TextButton(
                          onPressed: () => ref.invalidate(realmsListProvider(const RealmsListKey(scope: RealmsScope.joined))),
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
