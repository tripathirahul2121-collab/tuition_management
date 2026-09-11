import 'package:flutter/material.dart';
import 'core/config/app_branding.dart';
import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';

class TuitionApp extends StatelessWidget {
  const TuitionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: WhiteLabelConfig.current.instituteShortName,
      theme: AppTheme.lightTheme,

      // ✅ Start app from Splash Screen
      initialRoute: '/',

      routes: AppRouter.routes,
    );
  }
}
