import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/theme.dart';
import '../core/widgets.dart';

class BiometricLockScreen extends StatefulWidget {
  const BiometricLockScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<BiometricLockScreen> createState() => _BiometricLockScreenState();
}

class _BiometricLockScreenState extends State<BiometricLockScreen> {
  bool _busy = false;
  bool _prompted = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_prompted) {
        _prompted = true;
        _unlock();
      }
    });
  }

  Future<void> _unlock() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final unlocked = await widget.controller.unlockWithBiometrics();
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!unlocked) {
        _error = 'Fingerprint was not recognised. Try again or use your phone number.';
      }
    });
  }

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
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const BrandLockup(
                  onDark: true,
                  markSize: 38,
                  showTagline: false,
                ),
                const Spacer(),
                Center(
                  child: Container(
                    width: 94,
                    height: 94,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.13),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.2),
                        width: 1.5,
                      ),
                    ),
                    child: const Icon(
                      Icons.fingerprint_rounded,
                      color: Colors.white,
                      size: 50,
                    ),
                  ),
                ),
                const SizedBox(height: 26),
                const Center(
                  child: Text(
                    'Welcome back',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 29,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.9,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Center(
                  child: Text(
                    'Unlock Chama with your fingerprint.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 13.5),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Center(
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFFFFD5D0),
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _busy ? null : _unlock,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: ChamaColors.deep,
                    ),
                    child: _busy
                        ? const SizedBox(
                            width: 21,
                            height: 21,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: ChamaColors.deep,
                            ),
                          )
                        : const Text('Unlock with fingerprint'),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: TextButton(
                    onPressed: _busy
                        ? null
                        : () => widget.controller.useOtpInstead(),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white70,
                    ),
                    child: const Text('Use phone number instead'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class StartupErrorScreen extends StatelessWidget {
  const StartupErrorScreen({
    super.key,
    required this.controller,
    required this.message,
  });

  final AppController controller;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 34, 24, 30),
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: BrandLockup(markSize: 36),
            ),
            const SizedBox(height: 55),
            const Icon(
              Icons.cloud_off_rounded,
              size: 56,
              color: ChamaColors.purple,
            ),
            const SizedBox(height: 18),
            const Text(
              'We could not open your chama.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: ChamaColors.ink,
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.6,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: ChamaColors.muted,
                fontSize: 13.5,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 26),
            FilledButton(
              onPressed: () => controller.boot(),
              child: const Text('Try again'),
            ),
            const SizedBox(height: 9),
            OutlinedButton(
              onPressed: () => controller.logout(),
              child: const Text('Sign out'),
            ),
          ],
        ),
      ),
    );
  }
}
