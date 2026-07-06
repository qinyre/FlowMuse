import 'package:flutter/material.dart';

import 'app_router.dart';
import 'app_theme.dart';

class FlowMuseApp extends StatelessWidget {
  const FlowMuseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'FlowMuse',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      routerConfig: appRouter,
    );
  }
}
