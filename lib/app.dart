import 'package:flutter/material.dart';
import 'core/routing/app_router.dart';

class TuitionApp extends StatelessWidget {
  const TuitionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Tuition',
      theme: ThemeData(useMaterial3: true),

      // ✅ Start app from Splash Screen
      initialRoute: '/',

      routes: AppRouter.routes,
    );
  }
}
