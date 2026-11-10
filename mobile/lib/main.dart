import 'package:flutter/material.dart';

import 'core/app_state.dart';
import 'core/theme.dart';
import 'screens/app_shell.dart';
import 'screens/auth_screen.dart';
import 'screens/splash_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ChamaApp());
}

class ChamaApp extends StatefulWidget {
  const ChamaApp({super.key});

  @override
  State<ChamaApp> createState() => _ChamaAppState();
}

class _ChamaAppState extends State<ChamaApp> {
  late final AppController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AppController();
    _controller.boot();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chama',
      debugShowCheckedModeBanner: false,
      theme: buildChamaTheme(),
      home: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          if (_controller.booting) {
            return const SplashScreen();
          }
          if (_controller.user == null) {
            return AuthScreen(controller: _controller);
          }
          return AppShell(controller: _controller);
        },
      ),
    );
  }
}
