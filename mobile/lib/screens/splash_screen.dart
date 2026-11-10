import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/widgets.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ChamaColors.deep,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [ChamaColors.deep, ChamaColors.purple],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(),
              const BrandLockup(
                onDark: true,
                markSize: 64,
                showTagline: false,
              ),
              const SizedBox(height: 18),
              const Text(
                'Together · Save · Grow',
                style: TextStyle(
                  color: Colors.white60,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              const SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 46),
            ],
          ),
        ),
      ),
    );
  }
}
