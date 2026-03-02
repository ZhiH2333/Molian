import 'dart:typed_data';

import 'package:flutter/material.dart';

/// 上传确认底部弹窗的统一入口。
///
/// 当用户在任何界面上传附件时，先弹出此窗口确认后再执行实际上传。
/// [imageBytes] 用于图片预览；为空时显示占位图标。
Future<bool> showUploadConfirmSheet(
  BuildContext context, {
  required String fileName,
  Uint8List? imageBytes,
}) async {
  final bool? result = await showModalBottomSheet<bool>(
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    context: context,
    builder: (BuildContext context) {
      return _UploadConfirmSheet(
        fileName: fileName,
        imageBytes: imageBytes,
      );
    },
  );
  return result ?? false;
}

class _UploadConfirmSheet extends StatelessWidget {
  const _UploadConfirmSheet({
    required this.fileName,
    this.imageBytes,
  });

  final String fileName;
  final Uint8List? imageBytes;

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * (3 / 4);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20.0),
          topRight: Radius.circular(20.0),
        ),
      ),
      height: height,
      child: Column(
        children: [
          SizedBox(
            height: 50,
            child: Stack(
              textDirection: TextDirection.rtl,
              children: [
                const Center(
                  child: Text(
                    '上传确认',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16.0,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(false),
                ),
              ],
            ),
          ),
          const Divider(height: 1.0),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 16),
                  Text(
                    '将要把附件 $fileName 上传到「文件」，是否继续？',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: Center(
                      child: _buildPreview(context),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '您的附件将会被压缩',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontStyle: FontStyle.italic,
                          color: Colors.grey,
                        ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text('取消'),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          child: const Text('上传'),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(
                    height: MediaQuery.of(context).padding.bottom + 16,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview(BuildContext context) {
    if (imageBytes != null && imageBytes!.isNotEmpty) {
      return _PreviewImage(
        child: Image.memory(
          imageBytes!,
          fit: BoxFit.contain,
        ),
      );
    }
    return _PreviewImage(
      child: Icon(
        Icons.insert_drive_file,
        size: 80,
        color: Colors.grey.shade400,
      ),
    );
  }
}

class _PreviewImage extends StatelessWidget {
  const _PreviewImage({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(
        maxWidth: 400,
        maxHeight: 320,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: child,
      ),
    );
  }
}
