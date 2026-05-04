import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'app_theme.dart';
import 'dashboard_page.dart';
import 'login_page.dart';
import 'notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();
  
  await Supabase.initialize(
    url: 'https://smnaclfbrefnzrjblfhp.supabase.co',
    anonKey: 'sb_publishable_NkiA1_tDkTF4AVJ21NTBcA_s1QuChk5',
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

  @override
  void initState() {
    super.initState();
    // Initialize notifications in the background
    NotificationService().init();
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
