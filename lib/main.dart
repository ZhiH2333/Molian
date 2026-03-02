import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'core/network/storage_providers.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_mode_provider.dart';
import 'core/theme/theme_settings_provider.dart';
import 'features/direct/providers/chat_providers.dart';
import 'features/notifications/providers/notifications_providers.dart';

void main() {
  runZonedGuarded(
    () {
      WidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.getInstance().then((SharedPreferences prefs) {
        runApp(
          ProviderScope(
            overrides: [sharedPreferencesProvider.overrideWith((ref) => prefs)],
            child: const MolianApp(),
          ),
        );
      });
    },
    (Object error, StackTrace stack) {
      if (error is WebSocketChannelException) {
        return;
      }
      if (error.toString().contains('Connection refused') &&
          error.toString().contains('61199')) {
        return;
      }
      final msg = error.toString();
      if (msg.contains('connection errored') &&
          msg.contains('XMLHttpRequest onError')) {
        return;
      }
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'runZonedGuarded',
        ),
      );
    },
  );
}

class MolianApp extends ConsumerStatefulWidget {
  const MolianApp({super.key});

  @override
  ConsumerState<MolianApp> createState() => _MolianAppState();
}

class _MolianAppState extends ConsumerState<MolianApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _releaseStuckKeys());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive) {
      _releaseStuckKeys();
    }
  }

  /// macOS 在焦点切换/热重载后偶发重复 KeyDown（如 Meta Left），这里主动释放
  /// Flutter 内部记录的按下状态，避免断言失败。
  void _releaseStuckKeys() {
    final HardwareKeyboard keyboard = HardwareKeyboard.instance;
    final List<PhysicalKeyboardKey> pressed = keyboard.physicalKeysPressed
        .toList(growable: false);
    if (pressed.isEmpty) return;
    final Duration ts = Duration(
      milliseconds: DateTime.now().millisecondsSinceEpoch,
    );
    for (final PhysicalKeyboardKey physical in pressed) {
      final LogicalKeyboardKey? logical = keyboard.lookUpLayout(physical);
      if (logical == null) continue;
      keyboard.handleKeyEvent(
        KeyUpEvent(
          physicalKey: physical,
          logicalKey: logical,
          synthesized: true,
          timeStamp: ts,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(wsLifecycleProvider);
    ref.watch(pushSubscribeOnAuthProvider);
    final themeMode = ref.watch(themeModeProvider);
    final themeSettings = ref.watch(themeSettingsProvider);
    return HeroControllerScope.none(
      child: MaterialApp.router(
        title: 'Molian V1',
        theme: AppTheme.light(themeSettings),
        darkTheme: AppTheme.dark(themeSettings),
        themeMode: themeMode,
        routerConfig: createAppRouter(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
