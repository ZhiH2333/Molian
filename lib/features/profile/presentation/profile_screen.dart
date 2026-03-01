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
import '../../../shared/widgets/app_background.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/login_prompt_view.dart';
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
  final _formKey = GlobalKey<FormState>();
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
    final xFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (xFile == null || !mounted) return;
    setState(() {
      _error = null;
      _isLoading = true;
    });
    try {
      final postsRepo = ref.read(postsRepositoryProvider);
      final profileRepo = ref.read(profileRepositoryProvider);
      String url;
      if (kIsWeb) {
        final rawBytes = await xFile.readAsBytes();
        final compressedBytes = await ImageCompressionService.compressToBytes(
          rawBytes,
          maxBytesKb: ImageUploadConstants.avatarMaxKb,
          maxWidth: ImageUploadConstants.avatarMaxDimension,
          maxHeight: ImageUploadConstants.avatarMaxDimension,
        );
        final name = xFile.name.isNotEmpty ? xFile.name : 'avatar.jpg';
        url = await postsRepo.uploadImageFromBytes(
          compressedBytes,
          filename: name,
          mimeType: 'image/jpeg',
        );
      } else {
        final compressedPath = await ImageCompressionService.compressToFile(
          xFile.path,
          maxBytesKb: ImageUploadConstants.avatarMaxKb,
          maxWidth: ImageUploadConstants.avatarMaxDimension,
          maxHeight: ImageUploadConstants.avatarMaxDimension,
        );
        url = await postsRepo.uploadImage(compressedPath, mimeType: 'image/jpeg');
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

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final profileRepo = ref.read(profileRepositoryProvider);
      await profileRepo.updateMe(
        displayName: _displayNameController.text.trim(),
        bio: _bioController.text.trim(),
      );
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
              title: const Text('个人资料'),
              actions: <Widget>[
                IconButton(
                  icon: const Icon(Icons.settings),
                  onPressed: () => context.push(AppRoutes.settings),
                ),
                IconButton(
                  icon: const Icon(Icons.logout),
                  onPressed: () async {
                    await ref.read(authStateProvider.notifier).logout();
                    if (context.mounted) context.go(AppRoutes.home);
                  },
                ),
              ],
            ),
            body: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(LayoutConstants.kSpacingXLarge),
                children: <Widget>[
                  Center(
                    child: GestureDetector(
                      onTap: _isLoading ? null : _pickAvatar,
                      child: Stack(
                        children: <Widget>[
                          CircleAvatar(
                            radius: 48,
                            backgroundImage: user.avatarUrl != null && user.avatarUrl!.isNotEmpty
                                ? NetworkImage(user.avatarUrl!)
                                : null,
                            child: user.avatarUrl == null || user.avatarUrl!.isEmpty
                                ? Text((user.displayName ?? user.username).isNotEmpty ? (user.displayName ?? user.username)[0] : '?')
                                : null,
                          ),
                          if (_isLoading)
                            const Positioned.fill(
                              child: DecoratedBox(
                                decoration: BoxDecoration(color: Colors.black26),
                                child: Center(child: CircularProgressIndicator()),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: LayoutConstants.kSpacingSmall),
                  Center(child: Text(_isLoading ? '上传中...' : '点击头像更换')),
                  const SizedBox(height: LayoutConstants.kSpacingXLarge),
                  TextFormField(
                    controller: _displayNameController,
                    decoration: const InputDecoration(labelText: '显示名', border: OutlineInputBorder()),
                    enabled: !_isLoading,
                    validator: (String? v) => (v?.trim() ?? '').isEmpty ? '请输入显示名' : null,
                  ),
                  const SizedBox(height: LayoutConstants.kSpacingLarge),
                  TextFormField(
                    controller: _bioController,
                    decoration: const InputDecoration(labelText: '简介', border: OutlineInputBorder(), alignLabelWithHint: true),
                    maxLines: 3,
                    enabled: !_isLoading,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: LayoutConstants.kSpacingMedium),
                    Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                  const SizedBox(height: LayoutConstants.kSpacingLarge),
                  ListTile(
                    contentPadding: LayoutConstants.kListTileContentPadding,
                    minLeadingWidth: LayoutConstants.kListTileMinLeadingWidth,
                    leading: const Icon(Icons.mail_outline),
                    title: const Text('好友申请'),
                    subtitle: const Text('查看、接受或拒绝好友申请'),
                    onTap: () => context.push(AppRoutes.friendRequests),
                    shape: RoundedRectangleBorder(borderRadius: LayoutConstants.kRadiusSmallBR),
                  ),
                  ListTile(
                    contentPadding: LayoutConstants.kListTileContentPadding,
                    minLeadingWidth: LayoutConstants.kListTileMinLeadingWidth,
                    leading: const Icon(Icons.people_outline),
                    title: const Text('关注与粉丝'),
                    subtitle: const Text('查看我关注的人与粉丝列表'),
                    onTap: () => context.push(AppRoutes.social),
                    shape: RoundedRectangleBorder(borderRadius: LayoutConstants.kRadiusSmallBR),
                  ),
                  ListTile(
                    contentPadding: LayoutConstants.kListTileContentPadding,
                    minLeadingWidth: LayoutConstants.kListTileMinLeadingWidth,
                    leading: const Icon(Icons.notifications_outlined),
                    title: const Text('通知中心'),
                    subtitle: const Text('点赞、评论、关注等通知'),
                    onTap: () => context.push(AppRoutes.notifications),
                    shape: RoundedRectangleBorder(borderRadius: LayoutConstants.kRadiusSmallBR),
                  ),
                  ListTile(
                    contentPadding: LayoutConstants.kListTileContentPadding,
                    minLeadingWidth: LayoutConstants.kListTileMinLeadingWidth,
                    leading: const Icon(Icons.people_outline),
                    title: const Text('圈子'),
                    subtitle: const Text('加入或浏览圈子'),
                    onTap: () => context.push(AppRoutes.realms),
                    shape: RoundedRectangleBorder(borderRadius: LayoutConstants.kRadiusSmallBR),
                  ),
                  ListTile(
                    contentPadding: LayoutConstants.kListTileContentPadding,
                    minLeadingWidth: LayoutConstants.kListTileMinLeadingWidth,
                    leading: const Icon(Icons.folder_outlined),
                    title: const Text('我的文件'),
                    subtitle: const Text('上传与查看文件'),
                    onTap: () => context.push(AppRoutes.files),
                    shape: RoundedRectangleBorder(borderRadius: LayoutConstants.kRadiusSmallBR),
                  ),
                  const SizedBox(height: LayoutConstants.kSpacingXLarge),
                  FilledButton(
                    onPressed: _isLoading ? null : _save,
                    child: _isLoading ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('保存'),
                  ),
                ],
              ),
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
