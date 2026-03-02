import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/layout_constants.dart';
import '../../../core/responsive.dart';
import '../../../core/router/app_router.dart';
import '../../../shared/widgets/login_prompt_view.dart';
import '../../auth/data/models/user_model.dart';
import '../../auth/providers/auth_providers.dart';
import '../../chat/presentation/chat_rooms_list_screen.dart';
import '../../posts/presentation/home_screen.dart';
import '../../profile/presentation/profile_screen.dart';
import '../../realms/presentation/realms_screen.dart';

/// 宽屏左侧导航栏样式常量
class _RailStyle {
  _RailStyle._();
  static const double railWidth = 250;
  static const double pillRadius = 24;
  static const double itemPaddingH = 16;
  static const double itemPaddingV = 12;
  static const double itemSpacing = 8;
  static const double groupSpacing = 24;
  /// Molian 标题左侧留白
  static const double titlePaddingLeft = 24;
}

/// 主壳：窄屏底部 NavigationBar，宽屏（≥768）左侧 NavigationRail；「浏览、圈子、聊天、个人」。
class MainShellScreen extends ConsumerStatefulWidget {
  const MainShellScreen({super.key});

  @override
  ConsumerState<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends ConsumerState<MainShellScreen> {
  int _currentIndex = 0;

  static const List<_NavItem> _navItems = <_NavItem>[
    _NavItem(
      label: '浏览',
      icon: Icons.explore_outlined,
      selectedIcon: Icons.explore,
    ),
    _NavItem(
      label: '圈子',
      icon: Icons.people_outline,
      selectedIcon: Icons.people,
    ),
    _NavItem(
      label: '聊天',
      icon: Icons.chat_bubble_outline,
      selectedIcon: Icons.chat_bubble,
    ),
    _NavItem(
      label: '个人',
      icon: Icons.person_outline,
      selectedIcon: Icons.person,
    ),
  ];

  /// 未登录时各 tab 的提示文案（与导航顺序一致：浏览、圈子、聊天、个人）。
  static const List<String> _guestHints = <String>[
    '登录后查看发现与通知',
    '登录后查看与加入圈子',
    '登录后查看会话与好友',
    '登录后查看与编辑个人资料',
  ];

  void _onDestinationSelected(int index, UserModel? user) {
    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final width = screenWidth(context);
    final useRail = useNavigationRail(width);
    return authState.when(
      data: (UserModel? user) {
        final Widget body = user == null
            ? LoginPromptView(hint: _guestHints[_currentIndex])
            : IndexedStack(
                index: _currentIndex,
                children: const <Widget>[
                  HomeScreen(inShell: true),
                  RealmsScreen(inShell: true),
                  ChatRoomsListScreen(),
                  ProfileScreen(inShell: true),
                ],
              );
        if (useRail) {
          final padding = MediaQuery.viewPaddingOf(context);
          final isDesktop =
              defaultTargetPlatform == TargetPlatform.macOS ||
              defaultTargetPlatform == TargetPlatform.windows ||
              defaultTargetPlatform == TargetPlatform.linux;
          final topPadding = padding.top > 0
              ? padding.top
              : (isDesktop ? 28.0 : 0.0);
          final railBg = Theme.of(context).colorScheme.surface;
          return Container(
            color: railBg,
            child: Padding(
              padding: EdgeInsets.only(
                top: topPadding,
                left: padding.left,
                right: padding.right,
                bottom: padding.bottom,
              ),
              child: Row(
                children: <Widget>[
                  _StyledNavigationRail(
                    currentIndex: _currentIndex,
                    onDestinationSelected: (int index) =>
                        _onDestinationSelected(index, user),
                    navItems: _navItems,
                  ),
                  Expanded(
                      child: Container(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      child: body,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        return Scaffold(
          backgroundColor: Colors.transparent,
          extendBody: true,
          body: body,
          bottomNavigationBar: _ConditionalBottomNav(
            currentIndex: _currentIndex,
            onDestinationSelected: (int index) =>
                _onDestinationSelected(index, user),
            navItems: _navItems,
          ),
        );
      },
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, __) => Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Text('加载失败'),
              TextButton(
                onPressed: () => context.push(AppRoutes.login),
                child: const Text('去登录'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// 宽屏左侧导航栏
class _StyledNavigationRail extends StatelessWidget {
  const _StyledNavigationRail({
    required this.currentIndex,
    required this.onDestinationSelected,
    required this.navItems,
  });

  final int currentIndex;
  final void Function(int index) onDestinationSelected;
  final List<_NavItem> navItems;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textColor = colorScheme.onSurface;
    final iconColor = colorScheme.onSurface;
    final selectedPillColor = colorScheme.surfaceContainerHighest;
    return SizedBox(
      width: _RailStyle.railWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              _RailStyle.titlePaddingLeft,
              _RailStyle.groupSpacing,
              _RailStyle.itemPaddingH,
              _RailStyle.itemSpacing,
            ),
            child: Text(
              'Molian',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: textColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: _RailStyle.groupSpacing),
          ...navItems.asMap().entries.map((MapEntry<int, _NavItem> entry) {
            final index = entry.key;
            final item = entry.value;
            final selected = index == currentIndex;
            return Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: _RailStyle.itemPaddingH,
                vertical: _RailStyle.itemSpacing / 2,
              ),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(_RailStyle.pillRadius),
                child: InkWell(
                  onTap: () => onDestinationSelected(index),
                  borderRadius: BorderRadius.circular(_RailStyle.pillRadius),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: _RailStyle.itemPaddingH,
                      vertical: _RailStyle.itemPaddingV,
                    ),
                    decoration: BoxDecoration(
                      color: selected ? selectedPillColor : Colors.transparent,
                      borderRadius: BorderRadius.circular(
                        _RailStyle.pillRadius,
                      ),
                    ),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          selected ? item.selectedIcon : item.icon,
                          size: LayoutConstants.kIconSizeMedium,
                          color: iconColor,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          item.label,
                          style: Theme.of(
                            context,
                          ).textTheme.labelLarge?.copyWith(color: textColor),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

/// 窄屏底部导航：毛玻璃、圆角、透明底、弱阴影。
class _ConditionalBottomNav extends StatelessWidget {
  const _ConditionalBottomNav({
    required this.currentIndex,
    required this.onDestinationSelected,
    required this.navItems,
  });

  final int currentIndex;
  final void Function(int index) onDestinationSelected;
  final List<_NavItem> navItems;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return ClipRRect(
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surface.withOpacity(0.8),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: NavigationBar(
              height: LayoutConstants.kBottomNavHeight,
              labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
              backgroundColor: Colors.transparent,
              indicatorColor: colorScheme.primary.withOpacity(0.2),
              selectedIndex: currentIndex,
              onDestinationSelected: onDestinationSelected,
              destinations: navItems
                  .map(
                    (_NavItem item) => NavigationDestination(
                      icon: Icon(item.icon),
                      selectedIcon: Icon(item.selectedIcon),
                      label: item.label,
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      ),
    );
  }
}
