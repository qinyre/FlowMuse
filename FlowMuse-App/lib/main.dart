import 'package:flutter/widgets.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/flow_muse_app.dart';
import 'app/view_models/theme_view_model.dart';
import 'features/whiteboard/editor_core/src/rendering/rough/pencil_shader.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 并行初始化，减少 runApp 前的等待时间，缩小 OnPreDrawListener 触发窗口
  final (_, initialThemePreset) = await (
    Future.wait([
      dotenv.load(isOptional: true),
      PencilShader.init(), // 铅笔纹理 shader（不支持的平台静默降级）
    ]),
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
