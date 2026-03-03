import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_providers.dart';
import '../../social/providers/social_providers.dart';

/// 全站用户搜索：输入关键词搜索，可对结果发送好友申请。
class UserSearchScreen extends ConsumerStatefulWidget {
  const UserSearchScreen({super.key});

  @override
  ConsumerState<UserSearchScreen> createState() => _UserSearchScreenState();
}

class _UserSearchScreenState extends ConsumerState<UserSearchScreen> {
  final TextEditingController _queryController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  List<Map<String, dynamic>> _results = [];
  bool _loading = false;
  String? _error;
  final Set<String> _sendingIds = <String>{};
  final Set<String> _sentIds = <String>{};
  /// 已是好友的用户 id 集合，搜索时与结果比对，不显示「发送好友申请」按钮。
  final Set<String> _friendIds = <String>{};

  @override
  void dispose() {
    _queryController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// 从用户或好友项中解析用户 id（兼容 id / user_id / user.id）。
  static String? _userIdFrom(Map<String, dynamic> map) {
    final id = map['id']?.toString();
    if (id != null && id.isNotEmpty) return id;
    final userId = map['user_id']?.toString();
    if (userId != null && userId.isNotEmpty) return userId;
    final user = map['user'];
    if (user is Map) return _userIdFrom(Map<String, dynamic>.from(user));
    return null;
  }

  Future<void> _loadFriendIds() async {
    try {
      final repo = ref.read(socialRepositoryProvider);
      final friends = await repo.getFriends();
      if (mounted) {
        setState(() {
          _friendIds.clear();
          for (final f in friends) {
            final id = _userIdFrom(f);
            if (id != null) _friendIds.add(id);
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _results = [];
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ref.read(socialRepositoryProvider);
      final list = await repo.searchUsers(query);
      await _loadFriendIds();
      if (mounted) {
        setState(() {
          _results = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  Future<void> _sendFriendRequest(String targetId) async {
    setState(() => _sendingIds.add(targetId));
    try {
      final repo = ref.read(socialRepositoryProvider);
      await repo.sendFriendRequest(targetId);
      if (mounted) {
        setState(() {
          _sendingIds.remove(targetId);
          _sentIds.add(targetId);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _sendingIds.remove(targetId));
        final msg = e.toString().replaceFirst('Exception: ', '');
        final is409 = msg.contains('409') || msg.contains('已发送') || msg.contains('已是好友');
        if (is409) {
          setState(() => _sentIds.add(targetId));
        } else {
          _showErrorDialog(e, targetId);
        }
      }
    }
  }

  void _showErrorDialog(Object error, String targetId) {
    if (!mounted) return;
    final details = _buildErrorDetails(error, targetId);
    showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('好友申请发送失败'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: SelectableText(details),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: details));
            },
            child: const Text('复制'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  String _buildErrorDetails(Object e, String targetId) {
    final buffer = StringBuffer()
      ..writeln('target_id: $targetId')
      ..writeln('time: ${DateTime.now().toIso8601String()}');
    if (e is DioException) {
      final req = e.requestOptions;
      buffer
        ..writeln('request: ${req.method} ${req.baseUrl}${req.path}')
        ..writeln('status: ${e.response?.statusCode ?? 'unknown'}')
        ..writeln('dio_type: ${e.type}');
      if (req.queryParameters.isNotEmpty) {
        buffer.writeln('query: ${jsonEncode(req.queryParameters)}');
      }
      final data = e.response?.data;
      if (data != null) {
        buffer.writeln('response: ${_stringify(data)}');
      }
    }
    buffer.writeln('error: ${e.toString()}');
    return buffer.toString().trim();
  }

  static String _stringify(Object data) {
    try {
      return jsonEncode(data);
    } catch (_) {
      return data.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final me = ref.watch(authStateProvider).valueOrNull;
    return Scaffold(
      appBar: AppBar(
        title: const Text('搜索用户'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _queryController,
              focusNode: _focusNode,
              decoration: InputDecoration(
                hintText: '输入用户名或显示名搜索',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                filled: true,
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: _search,
            ),
          ),
        ),
      ),
      body: me == null
          ? const Center(child: Text('请先登录'))
          : Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FilledButton.icon(
                        onPressed: _loading
                            ? null
                            : () => _search(_queryController.text),
                        icon: _loading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.search),
                        label: const Text('搜索全站用户'),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '发送申请后需对方在「好友申请」中接受，才能成为好友并私信',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                  ),
                Expanded(
                  child: _results.isEmpty && !_loading
                      ? Center(
                          child: Text(
                            _queryController.text.trim().isEmpty
                                ? '输入关键词后点击搜索'
                                : '未找到匹配用户',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      : _loading
                          ? const Center(child: CircularProgressIndicator())
                          : ListView.builder(
                              itemCount: _results.length,
                              itemBuilder: (_, int i) {
                                final u = _results[i];
                                final id = _userIdFrom(u) ?? '';
                                final rawUser = u['user'] is Map
                                    ? Map<String, dynamic>.from(u['user'] as Map)
                                    : u;
                                final username = (rawUser['username'] ?? u['username'])?.toString() ?? '';
                                final displayName = (rawUser['display_name'] ?? u['display_name'])?.toString() ?? '';
                                final avatarUrl = (rawUser['avatar_url'] ?? u['avatar_url'])?.toString();
                                final name = displayName.isNotEmpty ? displayName : username;
                                final isMe = id == me.id;
                                final isFriend = _friendIds.contains(id);
                                final isSent = _sentIds.contains(id);
                                final isSending = _sendingIds.contains(id);
                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: theme.colorScheme.primaryContainer,
                                    backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                                        ? NetworkImage(avatarUrl)
                                        : null,
                                    child: avatarUrl == null || avatarUrl.isEmpty
                                        ? Text(
                                            name.isNotEmpty ? name[0] : '?',
                                            style: TextStyle(
                                              color: theme.colorScheme.onPrimaryContainer,
                                            ),
                                          )
                                        : null,
                                  ),
                                  title: Text(name),
                                  subtitle: username.isNotEmpty ? Text('@$username') : null,
                                  trailing: isMe
                                      ? Text(
                                          '本人',
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            color: theme.colorScheme.outline,
                                          ),
                                        )
                                      : isFriend
                                          ? Text(
                                              '已是好友',
                                              style: theme.textTheme.bodySmall?.copyWith(
                                                color: theme.colorScheme.primary,
                                              ),
                                            )
                                          : isSent
                                              ? Text(
                                                  '已发送',
                                                  style: theme.textTheme.bodySmall?.copyWith(
                                                    color: theme.colorScheme.primary,
                                                  ),
                                                )
                                              : TextButton(
                                                  onPressed: isSending
                                                      ? null
                                                      : () => _sendFriendRequest(id),
                                                  child: isSending
                                                      ? const SizedBox(
                                                          width: 20,
                                                          height: 20,
                                                          child: CircularProgressIndicator(strokeWidth: 2),
                                                        )
                                                      : const Text('发送好友申请'),
                                                ),
                                );
                              },
                            ),
                ),
              ],
            ),
    );
  }
}
