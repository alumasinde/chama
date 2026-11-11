import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BiometricService {
  BiometricService({LocalAuthentication? auth})
    : _auth = auth ?? LocalAuthentication();

  static const _enabledKey = 'chama.biometric_enabled';
  final LocalAuthentication _auth;

  Future<bool> isAvailable() async {
    if (kIsWeb) return false;
    try {
      if (!await _auth.canCheckBiometrics) return false;
      final enrolled = await _auth.getAvailableBiometrics();
      return enrolled.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<bool> isEnabled() async {
    if (kIsWeb) return false;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? false;
  }

  Future<void> setEnabled(bool enabled) async {
    if (kIsWeb) return;
    final prefs = await SharedPreferences.getInstance();
    if (enabled) {
      await prefs.setBool(_enabledKey, true);
    } else {
      await prefs.remove(_enabledKey);
    }
  }

  Future<bool> authenticate({required String reason}) async {
    if (kIsWeb) return false;
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }
}
