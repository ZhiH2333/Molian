import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/layout_constants.dart';
import '../../../core/responsive.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/auto_leading_button.dart';
import '../../posts/data/models/post_model.dart';
import '../../posts/presentation/widgets/post_card.dart';
import '../data/models/realm_model.dart';
import '../data/realms_repository.dart';
import '../providers/realms_providers.dart';

/// 加入/退出/编辑/删除圈子后，使「已加入」「我创建的」「全部」三个 tab 的列表都刷新。
void _invalidateAllRealmLists(WidgetRef ref) {
  ref.invalidate(realmsListProvider);
}

/// 圈子详情：展示信息、加入/退出、该圈子帖子列表；创建者可编辑/删除。
class RealmDetailScreen extends ConsumerStatefulWidget {
  const RealmDetailScreen({super.key, required this.realmId, this.initialRealm});

  final String realmId;
  final RealmModel? initialRealm;

  @override
  ConsumerState<RealmDetailScreen> createState() => _RealmDetailScreenState();
}

class _RealmDetailScreenState extends ConsumerState<RealmDetailScreen> {
  bool _joined = false;
  bool _isLoading = false;

  /// 用接口返回的 joined 同步本地状态（在 build 后用 postFrameCallback 避免在 build 中 setState）。
  void _syncJoinedFromRealm(RealmModel? realm) {
    if (realm == null || _joined == realm.joined) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _joined != realm.joined) setState(() => _joined = realm.joined);
    });
  }

  Future<void> _confirmDeleteRealm(BuildContext context, RealmModel realm) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('删除圈子'),
        content: Text('确定要删除「${realm.name}」吗？删除后无法恢复。'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _isLoading = true);
    try {
      await ref.read(realmsRepositoryProvider).deleteRealm(widget.realmId);
      if (mounted) {
        _invalidateAllRealmLists(ref);
        context.pop();
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('圈子已删除')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('删除失败: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = isWideScreen(context);
    final async = ref.watch(realmDetailProvider(widget.realmId));
    final realm = async.valueOrNull ?? widget.initialRealm;
    if (realm != null) _syncJoinedFromRealm(realm);
    final bool displayJoined = async.hasValue && realm != null ? realm.joined : _joined;
    return AppScaffold(
      isNoBackground: wide,
      isWideScreen: wide,
      appBar: AppBar(
        leading: const AutoLeadingButton(),
        title: Text(realm?.name ?? '圈子'),
        actions: <Widget>[
          if (realm != null && realm.isCreator) ...[
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: _isLoading ? null : () => _openEditRealm(context, realm),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _isLoading ? null : () => _confirmDeleteRealm(context, realm),
            ),
          ],
        ],
      ),
      body: realm == null
          ? async.when(
              data: (_) => const Center(child: Text('圈子不存在')),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (Object e, _) => Center(child: Text('加载失败: $e')),
            )
          : CustomScrollView(
              slivers: <Widget>[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(LayoutConstants.kSpacingXLarge),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Center(
                          child: CircleAvatar(
                            radius: 48,
                            backgroundImage: realm.avatarUrl != null && realm.avatarUrl!.isNotEmpty
                                ? CachedNetworkImageProvider(realm.avatarUrl!)
                                : null,
                            child: realm.avatarUrl == null || realm.avatarUrl!.isEmpty
                                ? Text(realm.name.isNotEmpty ? realm.name[0] : '?', style: const TextStyle(fontSize: 36))
                                : null,
                          ),
                        ),
                        const SizedBox(height: LayoutConstants.kSpacingLarge),
                        Text(
                          realm.name,
                          style: Theme.of(context).textTheme.headlineSmall,
                          textAlign: TextAlign.center,
                        ),
                        if (realm.slug.isNotEmpty) ...[
                          const SizedBox(height: LayoutConstants.kSpacingSmall),
                          Text(
                            '@${realm.slug}',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: Theme.of(context).colorScheme.outline,
                                ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                        if (realm.description != null && realm.description!.isNotEmpty) ...[
                          const SizedBox(height: LayoutConstants.kSpacingLarge),
                          Text(realm.description!, style: Theme.of(context).textTheme.bodyLarge),
                        ],
                        const SizedBox(height: LayoutConstants.kSpacingXLarge),
                        FilledButton(
                          onPressed: _isLoading
                              ? null
                              : () async {
                                  final currentlyJoined = async.hasValue ? realm.joined : _joined;
                                  setState(() => _isLoading = true);
                                  try {
                                    final repo = ref.read(realmsRepositoryProvider);
                                    if (currentlyJoined) {
                                      await repo.leaveRealm(widget.realmId);
                                      if (mounted) setState(() => _joined = false);
                                    } else {
                                      await repo.joinRealm(widget.realmId);
                                      if (mounted) setState(() => _joined = true);
                                    }
                                    if (mounted) ref.invalidate(realmDetailProvider(widget.realmId));
                                    if (mounted) _invalidateAllRealmLists(ref);
                                  } catch (e) {
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('操作失败: $e')),
                                      );
                                    }
                                  } finally {
                                    if (mounted) setState(() => _isLoading = false);
                                  }
                                },
                          child: _isLoading
                              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                              : Text(displayJoined ? '退出圈子' : '加入圈子'),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: LayoutConstants.kSpacingXLarge),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '圈子帖子',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                        ),
                        if (!displayJoined)
                          Padding(
                            padding: const EdgeInsets.only(top: LayoutConstants.kSpacingSmall),
                            child: Text(
                              '加入圈子后可查看「仅圈子可见」的帖子',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context).colorScheme.outline,
                                  ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.only(bottom: LayoutConstants.kSpacingXLarge),
                  sliver: _RealmPostsList(realmId: widget.realmId),
                ),
              ],
            ),
    );
  }

  void _openEditRealm(BuildContext context, RealmModel realm) {
    final repo = ref.read(realmsRepositoryProvider);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (BuildContext ctx) => _EditRealmSheet(
        realm: realm,
        repo: repo,
        onSaved: (RealmModel updated) {
          ref.invalidate(realmDetailProvider(widget.realmId));
          _invalidateAllRealmLists(ref);
          if (ctx.mounted) Navigator.pop(ctx);
        },
        onError: (String msg) {
          if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(msg)));
        },
      ),
    );
  }
}

/// 圈子内帖子列表。
class _RealmPostsList extends ConsumerWidget {
  const _RealmPostsList({required this.realmId});
  final String realmId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(realmPostsProvider(realmId));
    return async.when(
      data: (List<PostModel> posts) {
        if (posts.isEmpty) {
          return SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(LayoutConstants.kSpacingXLarge),
              child: Center(
                child: Text(
                  '暂无帖子',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
            ),
          );
        }
        return SliverList(
          delegate: SliverChildBuilderDelegate(
            (BuildContext context, int index) => PostCard(post: posts[index]),
            childCount: posts.length,
          ),
        );
      },
      loading: () => const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (Object e, _) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(LayoutConstants.kSpacingXLarge),
          child: Center(child: Text('加载帖子失败: $e')),
        ),
      ),
    );
  }
}

/// 编辑圈子 BottomSheet：名称、slug、描述。
class _EditRealmSheet extends StatefulWidget {
  const _EditRealmSheet({
    required this.realm,
    required this.repo,
    required this.onSaved,
    required this.onError,
  });
  final RealmModel realm;
  final RealmsRepository repo;
  final void Function(RealmModel updated) onSaved;
  final void Function(String msg) onError;

  @override
  State<_EditRealmSheet> createState() => _EditRealmSheetState();
}

class _EditRealmSheetState extends State<_EditRealmSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _slugController;
  late final TextEditingController _descController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.realm.name);
    _slugController = TextEditingController(text: widget.realm.slug);
    _descController = TextEditingController(text: widget.realm.description ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _slugController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      widget.onError('圈子名称不能为空');
      return;
    }
    setState(() => _saving = true);
    try {
      final updated = await widget.repo.updateRealm(
        widget.realm.id,
        name: name,
        slug: _slugController.text.trim().isEmpty ? null : _slugController.text.trim(),
        description: _descController.text.trim().isEmpty ? null : _descController.text.trim(),
      );
      widget.onSaved(updated);
    } catch (e) {
      widget.onError(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(LayoutConstants.kSpacingXLarge),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text('编辑圈子', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: LayoutConstants.kSpacingLarge),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: '名称'),
              enabled: !_saving,
            ),
            const SizedBox(height: LayoutConstants.kSpacingMedium),
            TextField(
              controller: _slugController,
              decoration: const InputDecoration(labelText: 'Slug（选填）'),
              enabled: !_saving,
            ),
            const SizedBox(height: LayoutConstants.kSpacingMedium),
            TextField(
              controller: _descController,
              decoration: const InputDecoration(labelText: '描述（选填）'),
              maxLines: 2,
              enabled: !_saving,
            ),
            const SizedBox(height: LayoutConstants.kSpacingXLarge),
            FilledButton(
              onPressed: _saving ? null : () => _save(),
              child: _saving ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }
}
