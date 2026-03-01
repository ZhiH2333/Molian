import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/layout_constants.dart';
import '../../core/router/app_router.dart';

/// 未登录占位视图（图1样式）：图标、请先登录、页面对应提示、去登录按钮。
class LoginPromptView extends StatelessWidget {
  const LoginPromptView({
    super.key,
    required this.hint,
    this.onLoginPressed,
  });

  /// 对应页面的提示文案，如「登录后查看与编辑个人资料」。
  final String hint;

  /// 点击「去登录」的回调；为空时使用 [context.go(AppRoutes.login)]。
  final VoidCallback? onLoginPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(LayoutConstants.kSpacingXLarge),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.article_outlined,
              size: 80,
              color: colorScheme.outline,
            ),
            const SizedBox(height: LayoutConstants.kSpacingXLarge),
            Text(
              '请先登录',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: LayoutConstants.kSpacingSmall),
            Text(
              hint,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: LayoutConstants.kSpacingXLarge * 2),
            FilledButton(
              onPressed: () {
                if (onLoginPressed != null) {
                  onLoginPressed!();
                } else {
                  context.go(AppRoutes.login);
                }
              },
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: LayoutConstants.kSpacingXLarge * 2,
                  vertical: LayoutConstants.kSpacingMedium,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              child: const Text('去登录'),
            ),
          ],
        ),
      ),
    );
  }
}
