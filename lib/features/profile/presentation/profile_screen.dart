import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/image_upload_constants.dart';
import '../../../core/constants/layout_constants.dart';
import '../../../core/image/image_compression_service.dart';
import '../../../core/responsive.dart';
import '../../../core/router/app_router.dart';
import '../../../core/utils/image_url_utils.dart';
import '../../../shared/widgets/app_background.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/login_prompt_view.dart';
import '../../../shared/widgets/upload_confirm_sheet.dart';
import '../../auth/data/models/user_model.dart';
import '../../auth/providers/auth_providers.dart';
import '../../posts/providers/posts_providers.dart';
import '../providers/profile_providers.dart';

/// 个人资料：展示与编辑 display_name、bio、头像；登出。
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key, this.inShell = false});

  /// 是否嵌入底部导航壳。
  final bool inShell;

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final TextEditingController _displayNameController = TextEditingController();
  final TextEditingController _bioController = TextEditingController();
  bool _isLoading = false;
  String? _error;
  bool _initialized = false;

  @override
  void dispose() {
    _displayNameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  void _initFromUser(UserModel user) {
    if (_initialized) return;
    _initialized = true;
    _displayNameController.text = user.displayName ?? user.username;
    _bioController.text = user.bio ?? '';
  }

  Future<void> _pickAvatar() async {
    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) return;
    final picker = ImagePicker();
    final xFile = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (xFile == null || !mounted) return;
    final previewBytes = await xFile.readAsBytes();
    if (!mounted) return;
    final fileName = xFile.name.isNotEmpty ? xFile.name : 'avatar.jpg';
    final confirmed = await showUploadConfirmSheet(
      context,
      fileName: fileName,
      imageBytes: previewBytes,
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _error = null;
      _isLoading = true;
    });
    try {
      final postsRepo = ref.read(postsRepositoryProvider);
      final profileRepo = ref.read(profileRepositoryProvider);
      String url;
      if (kIsWeb) {
        final compressedBytes = await ImageCompressionService.compressToBytes(
          previewBytes,
          maxBytesKb: ImageUploadConstants.avatarMaxKb,
          maxWidth: ImageUploadConstants.avatarMaxDimension,
          maxHeight: ImageUploadConstants.avatarMaxDimension,
        );
        url = await postsRepo.uploadImageFromBytes(
          compressedBytes,
          filename: fileName,
          mimeType: 'image/jpeg',
        );
      } else {
        final compressedPath = await ImageCompressionService.compressToFile(
          xFile.path,
          maxBytesKb: ImageUploadConstants.avatarMaxKb,
          maxWidth: ImageUploadConstants.avatarMaxDimension,
          maxHeight: ImageUploadConstants.avatarMaxDimension,
        );
        url = await postsRepo.uploadImage(
          compressedPath,
          mimeType: 'image/jpeg',
        );
      }
      await profileRepo.updateMe(avatarUrl: url);
      ref.invalidate(authStateProvider);
      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _save({required String displayName, required String bio}) async {
    if (displayName.trim().isEmpty) {
      if (mounted) {
        setState(() => _error = '请输入显示名');
      }
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final profileRepo = ref.read(profileRepositoryProvider);
      await profileRepo.updateMe(
        displayName: displayName.trim(),
        bio: bio.trim(),
      );
      _displayNameController.text = displayName.trim();
      _bioController.text = bio.trim();
      ref.invalidate(authStateProvider);
      if (!mounted) return;
      setState(() => _isLoading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  void _openEditSheet(BuildContext context) {
    final TextEditingController nameController = TextEditingController(
      text: _displayNameController.text,
    );
    final TextEditingController bioController = TextEditingController(
      text: _bioController.text,
    );
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (BuildContext ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: LayoutConstants.kSpacingXLarge,
            right: LayoutConstants.kSpacingXLarge,
            top: LayoutConstants.kSpacingXLarge,
            bottom:
                MediaQuery.of(ctx).viewInsets.bottom +
                LayoutConstants.kSpacingXLarge,
          ),
          child: Consumer(
            builder: (BuildContext ctx, WidgetRef ref, _) {
              final user = ref.watch(authStateProvider).valueOrNull;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    '编辑资料',
                    style: Theme.of(ctx).textTheme.titleLarge,
                  ),
                  const SizedBox(height: LayoutConstants.kSpacingLarge),
                  Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        CircleAvatar(
                          radius: 40,
                          backgroundImage:
                              user != null &&
                                  user.avatarUrl != null &&
                                  user.avatarUrl!.isNotEmpty
                              ? NetworkImage(
                                  fullImageUrl(user.avatarUrl),
                                )
                              : null,
                          child:
                              user == null ||
                                  user.avatarUrl == null ||
                                  user.avatarUrl!.isEmpty
                              ? Text(
                                  user != null
                                      ? ((_displayNameController.text.isNotEmpty
                                              ? _displayNameController.text
                                              : user.username)[0])
                                      : '?',
                                  style: Theme.of(ctx)
                                      .textTheme
                                      .headlineMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                )
                              : null,
                        ),
                        const SizedBox(width: LayoutConstants.kSpacingLarge),
                        FilledButton.tonalIcon(
                          onPressed: _isLoading ? null : _pickAvatar,
                          icon: const Icon(
                            Icons.camera_alt_outlined,
                            size: LayoutConstants.kIconSizeSmall,
                          ),
                          label: const Text('更换头像'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: LayoutConstants.kSpacingMedium,
                              vertical: LayoutConstants.kSpacingSmall,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: LayoutConstants.kSpacingLarge),
                  TextField(
                    controller: nameController,
                    decoration: InputDecoration(
                      labelText: '显示名',
                      hintText: '请输入显示名',
                      filled: true,
                      border: OutlineInputBorder(
                        borderRadius: LayoutConstants.kRadiusMediumBR,
                      ),
                    ),
                    textCapitalization: TextCapitalization.none,
                  ),
                  const SizedBox(height: LayoutConstants.kSpacingMedium),
                  TextField(
                    controller: bioController,
                    decoration: InputDecoration(
                      labelText: '个人简介',
                      hintText: '选填',
                      filled: true,
                      border: OutlineInputBorder(
                        borderRadius: LayoutConstants.kRadiusMediumBR,
                      ),
                    ),
                    maxLines: 3,
                    textCapitalization: TextCapitalization.sentences,
                  ),
                  const SizedBox(height: LayoutConstants.kSpacingXLarge),
                  FilledButton(
                    onPressed: _isLoading
                        ? null
                        : () async {
                            await _save(
                              displayName: nameController.text,
                              bio: bioController.text,
                            );
                            if (ctx.mounted && _error == null) Navigator.pop(ctx);
                          },
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        vertical: LayoutConstants.kSpacingMedium,
                      ),
                    ),
                    child: _isLoading
                        ? SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Theme.of(ctx).colorScheme.onPrimary,
                            ),
                          )
                        : const Text('保存'),
                  ),
            ],
          );
            },
          ),
        );
      },
    ).whenComplete(() {
      nameController.dispose();
      bioController.dispose();
    });
  }

  Future<void> _logout(BuildContext context) async {
    await ref.read(authStateProvider.notifier).logout();
    if (context.mounted) context.go(AppRoutes.home);
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final wide = isWideScreen(context);
    return AppBackground(
      isRoot: true,
      child: authState.when(
        data: (UserModel? user) {
          if (user == null) {
            return AppScaffold(
              isNoBackground: wide,
              isWideScreen: wide,
              appBar: AppBar(title: const Text('个人资料')),
              body: const LoginPromptView(hint: '登录后查看与编辑个人资料'),
            );
          }
          _initFromUser(user);
          return AppScaffold(
            isNoBackground: wide,
            isWideScreen: wide,
            appBar: AppBar(
              automaticallyImplyLeading: !widget.inShell,
              title: const Text('个人资料'),
              centerTitle: true,
              actions: <Widget>[
                IconButton(
                  icon: const Icon(Icons.logout_outlined),
                  onPressed: () => _logout(context),
                ),
              ],
            ),
            body: ListView(
              padding: const EdgeInsets.symmetric(
                horizontal: LayoutConstants.kSpacingXLarge,
                vertical: LayoutConstants.kSpacingLarge,
              ),
              children: <Widget>[
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(LayoutConstants.kSpacingXLarge),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        CircleAvatar(
                          radius: 40,
                          backgroundImage:
                              user.avatarUrl != null &&
                                  user.avatarUrl!.isNotEmpty
                              ? NetworkImage(
                                  fullImageUrl(user.avatarUrl),
                                )
                              : null,
                          child:
                              user.avatarUrl == null ||
                                  user.avatarUrl!.isEmpty
                              ? Text(
                                  (_displayNameController.text.isNotEmpty
                                      ? _displayNameController.text
                                      : user.username)[0],
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                )
                              : null,
                        ),
                        const SizedBox(width: LayoutConstants.kSpacingXLarge),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                _displayNameController.text,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                              const SizedBox(height: LayoutConstants.kSpacingSmall),
                              Text(
                                _bioController.text.isNotEmpty
                                    ? _bioController.text
                                    : '添加个人简介',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                              ),
                              const SizedBox(height: LayoutConstants.kSpacingLarge),
                              FilledButton.tonalIcon(
                                onPressed: _isLoading
                                    ? null
                                    : () => _openEditSheet(context),
                                icon: const Icon(
                                  Icons.edit_outlined,
                                  size: LayoutConstants.kIconSizeSmall,
                                ),
                                label: const Text('编辑资料'),
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: LayoutConstants.kSpacingLarge,
                                    vertical: LayoutConstants.kSpacingSmall,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: LayoutConstants.kSpacingLarge),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: Theme.of(context).textTheme.bodyMedium?.fontSize,
                    ),
                  ),
                ],
                const SizedBox(height: LayoutConstants.kSpacingLarge),
                Card(
                  margin: EdgeInsets.zero,
                  child: Column(
                    children: <Widget>[
                      _ProfileEntry(
                        icon: Icons.notifications_outlined,
                        title: '消息',
                        onTap: () => context.push(AppRoutes.notifications),
                      ),
                      const Divider(height: 1),
                      _ProfileEntry(
                        icon: Icons.people_outline,
                        title: '关注和粉丝',
                        onTap: () => context.push(AppRoutes.social),
                      ),
                      const Divider(height: 1),
                      _ProfileEntry(
                        icon: Icons.folder_outlined,
                        title: '文件',
                        onTap: () => context.push(AppRoutes.files),
                      ),
                      const Divider(height: 1),
                      _ProfileEntry(
                        icon: Icons.article_outlined,
                        title: '帖子',
                        onTap: () => context.go(AppRoutes.home),
                      ),
                      const Divider(height: 1),
                      _ProfileEntry(
                        icon: Icons.settings_outlined,
                        title: '设置',
                        onTap: () => context.push(AppRoutes.settings),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
        loading: () => AppScaffold(
          isNoBackground: wide,
          isWideScreen: wide,
          appBar: AppBar(title: const Text('个人资料')),
          body: const Center(child: CircularProgressIndicator()),
        ),
        error: (Object err, StackTrace? stack) => AppScaffold(
          isNoBackground: wide,
          isWideScreen: wide,
          appBar: AppBar(title: const Text('个人资料')),
          body: EmptyState(
            title: '加载失败',
            description: err.toString(),
            action: TextButton(
              onPressed: () => context.go(AppRoutes.login),
              child: const Text('去登录'),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileEntry extends StatelessWidget {
  const _ProfileEntry({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      minLeadingWidth: LayoutConstants.kListTileMinLeadingWidth,
      contentPadding: LayoutConstants.kListTileContentPadding,
      leading: Icon(icon, size: LayoutConstants.kIconSizeMedium),
      title: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium,
      ),
      trailing: Icon(
        Icons.chevron_right,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      onTap: onTap,
    );
  }
}
