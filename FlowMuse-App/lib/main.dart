import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter/widgets.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'app/flow_muse_app.dart';
import 'app/view_models/theme_view_model.dart';

Future<void> main() async {
  // 房间密钥保留在 fragment；SDK 在非 Web 平台自动使用 no-op。
  setUrlStrategy(PathUrlStrategy(BrowserPlatformLocation(), true));
  WidgetsFlutterBinding.ensureInitialized();

  // 并行初始化，减少 runApp 前的等待时间，缩小 OnPreDrawListener 触发窗口
  final (_, initialThemePreset) = await (
    dotenv.load(fileName: 'assets/config/app.env', isOptional: true),
    loadSavedThemePreset(),
  ).wait;
  runApp(
    ProviderScope(
      overrides: [
        initialThemePresetProvider.overrideWithValue(initialThemePreset),
      ],
      child: FlowMuseApp(),
    ),
  );
  if (kIsWeb) unawaited(_loadDeferredUiFonts());
}

Future<void> _loadDeferredUiFonts() async {
  await WidgetsBinding.instance.waitUntilFirstFrameRasterized;
  try {
    final manifest =
        jsonDecode(await rootBundle.loadString('FontManifest.json'))
            as List<dynamic>;
    final family = manifest.cast<Map<String, dynamic>>().firstWhere(
      (entry) => entry['family'] == 'FlowMuseSans',
    );
    final fonts = family['fonts'] as List<dynamic>;
    if (fonts.length != 1 || fonts.single['weight'] != 400) return;

    await (FontLoader('FlowMuseSans')
          ..addFont(
            rootBundle.load('assets/fonts/ui/FlowMuseSans-SemiBold.ttf'),
          )
          ..addFont(rootBundle.load('assets/fonts/ui/FlowMuseSans-Bold.ttf')))
        .load();
  } catch (_) {
    debugPrint('Web 界面字体补载失败，使用已加载的常规字重');
  }
}
