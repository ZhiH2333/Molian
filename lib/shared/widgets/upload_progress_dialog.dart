import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

/// 显示上传进度弹窗：正在上传、进度条、上传速度、取消上传。
///
/// [totalBytes] 为待上传总字节数。[uploadFn] 接收进度回调和取消 Token，返回上传结果。
/// 成功返回 [T]，用户取消返回 null，失败抛出异常。
Future<T?> showUploadProgressDialog<T>(
  BuildContext context, {
  required int totalBytes,
  required Future<T> Function(
    void Function(int sent, int total) onProgress,
    CancelToken cancelToken,
  ) uploadFn,
}) async {
  final completer = Completer<T?>();
  if (!context.mounted) {
    completer.complete(null);
    return completer.future;
  }
  showDialog<void>(
    barrierDismissible: false,
    context: context,
    builder: (BuildContext ctx) {
      return _UploadProgressDialogContent<T>(
        totalBytes: totalBytes,
        uploadFn: uploadFn,
        onDone: (T? result) {
          Navigator.of(ctx).pop();
          if (!completer.isCompleted) completer.complete(result);
        },
        onError: (Object e, StackTrace? st) {
          Navigator.of(ctx).pop();
          if (!completer.isCompleted) completer.completeError(e, st);
        },
      );
    },
  );
  return completer.future;
}

class _UploadProgressDialogContent<T> extends StatefulWidget {
  const _UploadProgressDialogContent({
    required this.totalBytes,
    required this.uploadFn,
    required this.onDone,
    required this.onError,
  });

  final int totalBytes;
  final Future<T> Function(
    void Function(int sent, int total) onProgress,
    CancelToken cancelToken,
  ) uploadFn;
  final void Function(T? result) onDone;
  final void Function(Object e, StackTrace? st) onError;

  @override
  State<_UploadProgressDialogContent<T>> createState() =>
      _UploadProgressDialogContentState<T>();
}

class _UploadProgressDialogContentState<T>
    extends State<_UploadProgressDialogContent<T>> {
  late final CancelToken _cancelToken;
  int _sent = 0;
  int _total = 0;
  double _speedBytesPerSecond = 0;
  DateTime? _startTime;

  @override
  void initState() {
    super.initState();
    _cancelToken = CancelToken();
    _total = widget.totalBytes;
    if (_total <= 0) _total = 1;
    _startUpload();
  }

  void _onProgress(int sent, int total) {
    final now = DateTime.now();
    if (!mounted) return;
    setState(() {
      _sent = sent;
      if (total > 0) _total = total;
      if (_startTime != null) {
        final elapsedSec = now.difference(_startTime!).inMilliseconds / 1000.0;
        if (elapsedSec > 0) {
          _speedBytesPerSecond = sent / elapsedSec;
          if (_speedBytesPerSecond < 0) _speedBytesPerSecond = 0;
        }
      }
    });
  }

  Future<void> _startUpload() async {
    _startTime = DateTime.now();
    try {
      final result = await widget.uploadFn(_onProgress, _cancelToken);
      if (mounted) widget.onDone(result);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        if (mounted) widget.onDone(null);
        return;
      }
      if (mounted) widget.onError(e, e.stackTrace);
    } catch (e, st) {
      if (mounted) widget.onError(e, st);
    }
  }

  void _cancelUpload() {
    _cancelToken.cancel('用户取消上传');
    widget.onDone(null);
  }

  String get _speedText {
    if (_speedBytesPerSecond <= 0) return '-- KB/s';
    if (_speedBytesPerSecond < 1024) return '${_speedBytesPerSecond.toStringAsFixed(0)} B/s';
    return '${(_speedBytesPerSecond / 1024).toStringAsFixed(1)} KB/s';
  }

  @override
  Widget build(BuildContext context) {
    final progress = _total > 0 ? (_sent / _total).clamp(0.0, 1.0) : 0.0;
    return AlertDialog(
      title: const Text('正在上传'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LinearProgressIndicator(value: progress),
          const SizedBox(height: 16),
          Text(
            _speedText,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
          ),
          const SizedBox(height: 24),
          TextButton(
            onPressed: _cancelUpload,
            child: const Text('取消上传'),
          ),
        ],
      ),
    );
  }
}
