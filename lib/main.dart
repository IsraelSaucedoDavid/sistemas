import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';

import 'app_theme.dart';
import 'dashboard_page.dart';
import 'login_page.dart';
import 'notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();
  
  await Supabase.initialize(
    url: 'https://smnaclfbrefnzrjblfhp.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNtbmFjbGZicmVmbnpyamJsZmhwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY2MzYwMTEsImV4cCI6MjA5MjIxMjAxMX0.bo2-iClOuQQUzvNAR9UUAsbljwdcflY-vcWvsW_Y8Po',
  );

  runApp(const MainApp());
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  final _themeModeController = ThemeModeController();
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    // Initialize notifications and set navigator key
    final notifService = NotificationService();
    notifService.setNavigatorKey(_navigatorKey);
    notifService.init();
  }

  @override
  void dispose() {
    _themeModeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ThemeModeScope(
      controller: _themeModeController,
      child: ValueListenableBuilder<ThemeMode>(
        valueListenable: _themeModeController,
        builder: (context, mode, _) {
          return MaterialApp(
            title: 'TELECRAFT',
            navigatorKey: _navigatorKey,
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: mode,
            home: Supabase.instance.client.auth.currentSession == null
                ? const LoginPage()
                : const DashboardPage(),
          );
        },
      ),
    );
  }
}
