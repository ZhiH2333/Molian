import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/image_upload_constants.dart';
import '../../../core/image/image_compression_service.dart';
import '../../../core/router/app_router.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/auto_leading_button.dart';
import '../../../shared/widgets/upload_confirm_sheet.dart';
import '../../files/data/files_repository.dart';
import '../../files/providers/files_providers.dart';
import '../data/models/post_model.dart';
import '../providers/posts_providers.dart';

/// 上传中单条：压缩后的字节与文件名，用于上传与重试。
class _UploadingEntry {
  _UploadingEntry({required this.id, this.bytes, this.filename});
  final String id;
  final Uint8List? bytes;
  final String? filename;
  String? error;
}

/// 发布帖子：正文 + 可选图片（先压缩再上传再发布）。[initialPost] 非空时为编辑模式。
class CreatePostScreen extends ConsumerStatefulWidget {
  const CreatePostScreen({super.key, this.initialPost, this.postId});

  final PostModel? initialPost;
  final String? postId;

  @override
  ConsumerState<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends ConsumerState<CreatePostScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _contentController = TextEditingController();
  final List<String> _imageUrls = [];
  final List<_UploadingEntry> _uploadingEntries = [];
  bool _isLoading = false;
  String? _error;
  static const _uuid = Uuid();
  bool _initialized = false;

  bool get _isEditMode =>
      widget.initialPost != null ||
      (widget.postId != null && widget.postId!.isNotEmpty);

  String? get _editingPostId {
    final id = widget.initialPost?.id ?? widget.postId;
    if (id == null || id.isEmpty) return null;
    return id;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    if (widget.initialPost != null) {
      _applyPostToForm(widget.initialPost!);
      return;
    }
    final id = widget.postId;
    if (id != null && id.isNotEmpty) {
      unawaited(_loadPostForEdit(id));
    }
  }

  void _applyPostToForm(PostModel post) {
    final content = post.content;
    if (content.isNotEmpty) {
      final lines = content.split('\n');
      if (lines.length >= 3) {
        _titleController.text = lines[0];
        _descriptionController.text = lines[1];
        _contentController.text = lines.sublist(2).join('\n');
      } else if (lines.length == 2) {
        _titleController.text = lines[0];
        _contentController.text = lines[1];
      } else {
        _contentController.text = content;
      }
    }
    _imageUrls
      ..clear()
      ..addAll(post.imageUrls ?? const <String>[]);
  }

  Future<void> _loadPostForEdit(String postId) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final repo = ref.read(postsRepositoryProvider);
      final post = await repo.getPost(postId);
      if (!mounted) return;
      if (post == null) {
        setState(() => _error = '帖子不存在或已删除');
        return;
      }
      _applyPostToForm(post);
      setState(() {});
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  int get _totalImageCount => _imageUrls.length + _uploadingEntries.length;

  Future<void> _pickImage() async {
    if (_totalImageCount >= ImageUploadConstants.maxPostImages) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('最多添加 9 张图片')));
      }
      return;
    }
    final picker = ImagePicker();
    final xFile = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (xFile == null || !mounted) return;
    setState(() => _error = null);
    Uint8List previewBytes;
    try {
      previewBytes = await xFile.readAsBytes();
    } catch (e) {
      if (mounted)
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
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
    final repo = ref.read(postsRepositoryProvider);
    Uint8List compressedBytes;
    try {
      compressedBytes = await ImageCompressionService.compressToBytes(
        previewBytes,
        maxBytesKb: ImageUploadConstants.postImageMaxKb,
        maxWidth: ImageUploadConstants.postImageMaxDimension,
        maxHeight: ImageUploadConstants.postImageMaxDimension,
      );
    } catch (e) {
      if (mounted)
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
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
      final url = await repo.uploadImageFromBytes(
        compressedBytes,
        filename: name,
        mimeType: 'image/jpeg',
      );
      if (!mounted) return;
      setState(() {
        _uploadingEntries.removeWhere((e) => e.id == entry.id);
        _imageUrls.add(url);
      });
      _confirmImageToFiles(url, name: name, size: compressedBytes.length);
    } catch (e) {
      if (mounted) {
        setState(() {
          final idx = _uploadingEntries.indexWhere((e) => e.id == entry.id);
          if (idx >= 0)
            _uploadingEntries[idx].error = e.toString().replaceFirst(
              'Exception: ',
              '',
            );
        });
      }
    }
  }

  /// 将上传后的图片登记到「文件」列表，便于在文件界面查看；失败静默忽略。
  Future<void> _confirmImageToFiles(
    String url, {
    required String name,
    int size = 0,
  }) async {
    try {
      final filesRepo = ref.read(filesRepositoryProvider);
      final key = FilesRepository.keyFromAssetUrl(url);
      await filesRepo.confirmUpload(
        key: key,
        name: name,
        size: size,
        mimeType: 'image/jpeg',
      );
      ref.invalidate(filesListProvider);
    } catch (_) {}
  }

  void _removeUploading(_UploadingEntry entry) {
    setState(() => _uploadingEntries.removeWhere((e) => e.id == entry.id));
  }

  Future<void> _retryUploading(_UploadingEntry entry) async {
    if (entry.bytes == null || entry.filename == null) return;
    setState(() => entry.error = null);
    final repo = ref.read(postsRepositoryProvider);
    try {
      final url = await repo.uploadImageFromBytes(
        entry.bytes!,
        filename: entry.filename!,
        mimeType: 'image/jpeg',
      );
      if (!mounted) return;
      setState(() {
        _uploadingEntries.removeWhere((e) => e.id == entry.id);
        _imageUrls.add(url);
      });
      final name = entry.filename ?? 'image.jpg';
      final size = entry.bytes?.length ?? 0;
      _confirmImageToFiles(url, name: name, size: size);
    } catch (e) {
      if (mounted) {
        setState(
          () => entry.error = e.toString().replaceFirst('Exception: ', ''),
        );
      }
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final title = _titleController.text.trim();
      final description = _descriptionController.text.trim();
      final body = _contentController.text.trim();
      final content = [title, description, body].join('\n');
      final repo = ref.read(postsRepositoryProvider);
      final postId = _editingPostId;
      if (postId != null) {
        await repo.updatePost(
          postId,
          content: content,
          imageUrls: _imageUrls.isEmpty ? null : _imageUrls,
        );
        ref.invalidate(postsListProvider(const PostsListKey()));
        ref.invalidate(feedsListProvider(const PostsListKey()));
        ref.invalidate(postDetailProvider(postId));
        if (!mounted) return;
        context.pop();
      } else {
        final firstLine = content.split('\n').firstOrNull ?? content;
        await repo.createPost(
          title: firstLine,
          content: content,
          imageUrls: _imageUrls.isEmpty ? null : _imageUrls,
        );
        ref.invalidate(postsListProvider(const PostsListKey()));
        ref.invalidate(feedsListProvider(const PostsListKey()));
        if (!mounted) return;
        context.go(AppRoutes.home);
      }
    } catch (e) {
      if (mounted)
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      isNoBackground: false,
      appBar: AppBar(
        leading: const AutoLeadingButton(),
        title: Text(_isEditMode ? '编辑' : '发布'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: <Widget>[
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: '标题',
                border: OutlineInputBorder(),
                hintText: '选填',
                alignLabelWithHint: true,
              ),
              maxLines: 1,
              enabled: !_isLoading,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: '描述',
                border: OutlineInputBorder(),
                hintText: '选填',
                alignLabelWithHint: true,
              ),
              maxLines: 2,
              enabled: !_isLoading,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _contentController,
              decoration: const InputDecoration(
                labelText: '内容',
                border: OutlineInputBorder(),
                hintText: '写点什么...',
                alignLabelWithHint: true,
              ),
              maxLines: 5,
              enabled: !_isLoading,
              validator: (String? v) {
                final title = _titleController.text.trim();
                final description = _descriptionController.text.trim();
                final content = (v ?? '').trim();
                if (title.isEmpty && description.isEmpty && content.isEmpty)
                  return '请至少填写标题、描述或内容之一';
                return null;
              },
            ),
            const SizedBox(height: 16),
            if (_imageUrls.isNotEmpty) ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _imageUrls.map((url) {
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
                          icon: const Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 20,
                          ),
                          onPressed: () =>
                              setState(() => _imageUrls.remove(url)),
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
                children: _uploadingEntries.map((entry) {
                  return SizedBox(
                    width: 80,
                    height: 80,
                    child: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
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
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.error,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: <Widget>[
                                          IconButton(
                                            icon: const Icon(
                                              Icons.refresh,
                                              size: 18,
                                            ),
                                            onPressed: () =>
                                                _retryUploading(entry),
                                          ),
                                          IconButton(
                                            icon: const Icon(
                                              Icons.close,
                                              size: 18,
                                            ),
                                            onPressed: () =>
                                                _removeUploading(entry),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                )
                              : const Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
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
              onPressed:
                  _isLoading ||
                      _totalImageCount >= ImageUploadConstants.maxPostImages
                  ? null
                  : _pickImage,
              icon: const Icon(Icons.add_photo_alternate),
              label: const Text('添加图片'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _isLoading ? null : _submit,
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_isEditMode ? '保存' : '发布'),
            ),
          ],
        ),
      ),
    );
  }
}
