import 'package:flutter/widgets.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/flow_muse_app.dart';
import 'app/view_models/theme_view_model.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(isOptional: true);
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
