import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_router.dart';
import 'app_theme.dart';
import 'view_models/theme_view_model.dart';

class FlowMuseApp extends ConsumerWidget {
  FlowMuseApp({super.key}) : _router = createAppRouter();

  final RouterConfig<Object> _router;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeColor = ref.watch(themeViewModelProvider);

    return MaterialApp.router(
      title: 'FlowMuse',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(themeColor),
      routerConfig: _router,
    );
  }
}
