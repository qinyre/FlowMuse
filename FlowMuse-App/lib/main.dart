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
}
