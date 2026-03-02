import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/image_upload_constants.dart';
import '../../../core/constants/layout_constants.dart';
import '../../../core/image/image_compression_service.dart';
import '../../../core/responsive.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/auto_leading_button.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/image_lightbox.dart';
import '../../../shared/widgets/upload_confirm_sheet.dart';
import '../../../shared/widgets/upload_progress_dialog.dart';
import '../data/files_repository.dart';
import '../data/models/file_model.dart';
import '../providers/files_providers.dart';

/// 文件列表，接入 /api/files；支持上传后登记。
class FilesScreen extends ConsumerStatefulWidget {
  const FilesScreen({super.key});

  @override
  ConsumerState<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends ConsumerState<FilesScreen> {
  bool _isUploading = false;

  Future<void> _pickAndUpload() async {
    final picker = ImagePicker();
    final xFile = await picker.pickImage(source: ImageSource.gallery);
    if (xFile == null || !mounted) return;
    final bytes = await xFile.readAsBytes();
    if (!mounted) return;
    final fileName = xFile.name.isNotEmpty ? xFile.name : 'image.jpg';
    final confirmed = await showUploadConfirmSheet(
      context,
      fileName: fileName,
      imageBytes: bytes,
    );
    if (!confirmed || !mounted) return;
    setState(() => _isUploading = true);
    try {
      final compressedBytes = await ImageCompressionService.compressToBytes(
        bytes,
        maxBytesKb: ImageUploadConstants.imageMaxKb,
        maxWidth: ImageUploadConstants.postImageMaxDimension,
        maxHeight: ImageUploadConstants.postImageMaxDimension,
      );
      if (!mounted) return;
      final repo = ref.read(filesRepositoryProvider);
      final result = await showUploadProgressDialog<FileModel>(
        context,
        totalBytes: compressedBytes.length,
        uploadFn: (onProgress, cancelToken) => repo.uploadAndConfirm(
          compressedBytes,
          filename: fileName,
          mimeType: 'image/jpeg',
          onSendProgress: onProgress,
          cancelToken: cancelToken,
        ),
      );
      if (!mounted) return;
      if (result != null) {
        ref.invalidate(filesListProvider);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已上传并登记')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('上传失败: $e')));
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = isWideScreen(context);
    return AppScaffold(
      isNoBackground: wide,
      isWideScreen: wide,
      appBar: AppBar(
        leading: const AutoLeadingButton(),
        title: const Text('文件'),
        actions: <Widget>[
          IconButton(
            icon: _isUploading ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.upload_file),
            onPressed: _isUploading ? null : _pickAndUpload,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Consumer(
        builder: (BuildContext context, WidgetRef ref, _) {
          final async = ref.watch(filesListProvider);
          return async.when(
            data: (List<FileModel> files) {
              if (files.isEmpty) {
                return EmptyState(
                  title: '暂无文件',
                  description: '上传图片或文件后将显示在这里',
                  icon: Icons.folder_outlined,
                  action: FilledButton.icon(
                    onPressed: _isUploading ? null : _pickAndUpload,
                    icon: const Icon(Icons.upload_file),
                    label: const Text('上传'),
                  ),
                );
              }
              return RefreshIndicator(
                onRefresh: () async => ref.invalidate(filesListProvider),
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: LayoutConstants.kSpacingXLarge),
                  itemCount: files.length,
                  itemBuilder: (BuildContext context, int index) {
                    final file = files[index];
                    return _FileTile(file: file);
                  },
                ),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (Object err, StackTrace? st) => EmptyState(
              title: '加载失败',
              description: err.toString(),
              action: TextButton(
                onPressed: () => ref.invalidate(filesListProvider),
                child: const Text('重试'),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FileTile extends StatelessWidget {
  const _FileTile({required this.file});

  final FileModel file;

  @override
  Widget build(BuildContext context) {
    final url = FilesRepository.getAssetUrl(file.key);
    final isImage = file.mimeType != null && (file.mimeType!.startsWith('image/'));
    return ListTile(
      minLeadingWidth: LayoutConstants.kListTileMinLeadingWidth,
      contentPadding: LayoutConstants.kListTileContentPadding,
      leading: isImage
          ? Image.network(url, width: 48, height: 48, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.insert_drive_file))
          : const Icon(Icons.insert_drive_file),
      title: Text(file.name, overflow: TextOverflow.ellipsis),
      subtitle: Text(_formatSize(file.size)),
      onTap: () {
        if (isImage) {
          showImageLightbox(
          context,
          imageUrls: <String>[url],
          initialIndex: 0,
          heroTagPrefix: 'file-${file.id}',
        );
        }
      },
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
