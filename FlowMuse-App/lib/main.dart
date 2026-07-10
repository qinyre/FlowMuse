import 'package:flutter/widgets.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/flow_muse_app.dart';
import 'app/view_models/theme_view_model.dart';
import 'features/whiteboard/editor_core/src/rendering/rough/pencil_shader.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(isOptional: true);

  // 铅笔纹理 shader（鸿蒙等不支持的平台会静默降级，不影响使用）
  await PencilShader.init();

  final initialThemePreset = await loadSavedThemePreset();
  runApp(
    ProviderScope(
      overrides: [
        initialThemePresetProvider.overrideWithValue(initialThemePreset),
      ],
      child: FlowMuseApp(),
    ),
  );
}
