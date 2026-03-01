import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/layout_constants.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/auto_leading_button.dart';
import '../data/realms_repository.dart';
import '../providers/realms_providers.dart';

/// 创建圈子页：名称（必填）、slug（选填）、描述（选填）。
class CreateRealmScreen extends ConsumerStatefulWidget {
  const CreateRealmScreen({super.key});

  @override
  ConsumerState<CreateRealmScreen> createState() => _CreateRealmScreenState();
}

class _CreateRealmScreenState extends ConsumerState<CreateRealmScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _slugController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _slugController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _isLoading = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final repo = ref.read(realmsRepositoryProvider);
      await repo.createRealm(
        name: _nameController.text.trim(),
        slug: _slugController.text.trim().isEmpty ? null : _slugController.text.trim(),
        description: _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
      );
      if (!mounted) return;
      ref.invalidate(realmsListProvider(const RealmsListKey(scope: RealmsScope.mine)));
      ref.invalidate(realmsListProvider(const RealmsListKey(scope: RealmsScope.all)));
      ref.invalidate(realmsListProvider(const RealmsListKey(scope: RealmsScope.joined)));
      context.pop();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('圈子已创建'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      final message = e is Exception
          ? e.toString().replaceFirst('Exception: ', '')
          : e.toString();
      if (mounted) {
        setState(() => _isLoading = false);
        messenger.showSnackBar(
          SnackBar(
            content: Text(message.isEmpty ? '创建失败' : message),
            backgroundColor: Theme.of(context).colorScheme.errorContainer,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AppScaffold(
      appBar: AppBar(
        leading: const AutoLeadingButton(),
        title: const Text('创建圈子'),
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
              controller: _nameController,
              decoration: InputDecoration(
                labelText: '名称',
                hintText: '必填',
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
              enabled: !_isLoading,
              validator: (String? v) {
                if ((v ?? '').trim().isEmpty) return '请输入圈子名称';
                return null;
              },
            ),
            const SizedBox(height: LayoutConstants.kSpacingLarge),
            TextFormField(
              controller: _slugController,
              decoration: InputDecoration(
                labelText: '短链接名',
                hintText: '选填，用于 URL',
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
              enabled: !_isLoading,
            ),
            const SizedBox(height: LayoutConstants.kSpacingLarge),
            TextFormField(
              controller: _descriptionController,
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
              maxLines: 3,
              enabled: !_isLoading,
            ),
            const SizedBox(height: LayoutConstants.kSpacingXLarge),
            FilledButton(
              onPressed: _isLoading ? null : _submit,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: LayoutConstants.kRadiusMediumBR,
                ),
              ),
              child: _isLoading
                  ? SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colorScheme.onPrimary,
                      ),
                    )
                  : const Text('创建'),
            ),
          ],
        ),
      ),
    );
  }
}
