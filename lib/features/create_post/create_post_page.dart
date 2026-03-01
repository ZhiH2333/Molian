import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/layout_constants.dart';
import '../../core/router/app_router.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/auto_leading_button.dart';
import '../realms/data/models/realm_model.dart';
import '../realms/providers/realms_providers.dart';
import 'create_post_controller.dart';

/// 发布帖子页：标题、内容、圈子选择、仅圈子可见、发布。Material 3 风格。
class CreatePostPage extends ConsumerStatefulWidget {
  const CreatePostPage({super.key});

  @override
  ConsumerState<CreatePostPage> createState() => _CreatePostPageState();
}

class _CreatePostPageState extends ConsumerState<CreatePostPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleFocus = FocusNode();
  final _contentFocus = FocusNode();
  late final TextEditingController _titleController;
  late final TextEditingController _contentController;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _contentController = TextEditingController();
  }

  @override
  void dispose() {
    _titleFocus.dispose();
    _contentFocus.dispose();
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('发布成功'),
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
        title: const Text('发布'),
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
                if ((v ?? '').trim().isEmpty) return '请填写内容';
                return null;
              },
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
                  : const Text('发布'),
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
    final async = ref.watch(realmsListProvider);
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
                      child: Text(
                        '暂无圈子',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
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
                          onPressed: () => ref.invalidate(realmsListProvider),
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
