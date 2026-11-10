import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api.dart';
import '../core/app_state.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../core/widgets.dart';

enum _AuthStep { phone, otp, register }

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _phone = TextEditingController();
  final _otp = TextEditingController();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _pin = TextEditingController();

  _AuthStep _step = _AuthStep.phone;
  String _normalizedPhone = '';
  String? _devCode;
  String? _registrationToken;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _phone.dispose();
    _otp.dispose();
    _firstName.dispose();
    _lastName.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final raw = _phone.text.trim();
    if (raw.replaceAll(RegExp(r'\D'), '').length < 9) {
      setState(() => _error = 'Enter a 9-digit phone number.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      _normalizedPhone = normalizedPhone(raw);
      final result = await widget.controller.sendOtp(_normalizedPhone);
      if (!mounted) return;
      setState(() {
        _devCode = result.devCode;
        if (_devCode != null) _otp.text = _devCode!;
        _step = _AuthStep.otp;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _friendly(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifyCode() async {
    final code = _otp.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Enter the 6-digit code.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.controller.verifyOtp(_normalizedPhone, code);
      if (!mounted) return;
      if (result.newUser) {
        setState(() {
          _registrationToken = result.registrationToken;
          _step = _AuthStep.register;
        });
      } else if (result.session != null) {
        await widget.controller.finishSignIn(result.session!);
      } else {
        setState(() => _error = 'We could not finish signing you in.');
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _friendly(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _register() async {
    final first = _firstName.text.trim();
    final last = _lastName.text.trim();
    final pin = _pin.text.trim();
    if (first.isEmpty || last.isEmpty) {
      setState(() => _error = 'Enter your first and last name.');
      return;
    }
    if (!RegExp(r'^\d{4}$').hasMatch(pin)) {
      setState(() => _error = 'Your PIN must be 4 digits.');
      return;
    }
    if (_registrationToken == null) {
      setState(() => _error = 'Verify your phone again to continue.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.controller.finishRegistration(
        registrationToken: _registrationToken!,
        firstName: first,
        lastName: last,
        pin: pin,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _friendly(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.controller.sendOtp(_normalizedPhone);
      if (!mounted) return;
      setState(() {
        _devCode = result.devCode;
        _otp.clear();
        if (_devCode != null) _otp.text = _devCode!;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _friendly(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _changeNumber() {
    setState(() {
      _step = _AuthStep.phone;
      _otp.clear();
      _error = null;
      _devCode = null;
    });
  }

  String _friendly(Object error) {
    if (error is ApiException) {
      return switch (error.code) {
        'rate_limited' => 'Too many attempts. Wait a minute, then try again.',
        'validation_failed' =>
          error.fields.values.firstOrNull ?? 'Check the details and try again.',
        'phone_taken' => 'That phone number already has an account.',
        _ => error.message,
      };
    }
    return 'We could not reach the server. Try again.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ChamaColors.canvas,
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(
            children: [
              _AuthHero(step: _step),
              Transform.translate(
                offset: const Offset(0, -24),
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding: const EdgeInsets.fromLTRB(22, 24, 22, 26),
                  decoration: BoxDecoration(
                    color: ChamaColors.surface,
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(color: ChamaColors.line),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x0D2E0A5E),
                        blurRadius: 30,
                        offset: Offset(0, 14),
                      ),
                    ],
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    switchInCurve: Curves.easeOut,
                    child: switch (_step) {
                      _AuthStep.phone => _phoneForm(),
                      _AuthStep.otp => _otpForm(),
                      _AuthStep.register => _registerForm(),
                    },
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 4, 24, 28),
                child: Text(
                  'Your chama. In one place.',
                  style: TextStyle(
                    color: ChamaColors.muted,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _phoneForm() {
    return Column(
      key: const ValueKey('phone'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Welcome',
          style: TextStyle(
            color: ChamaColors.ink,
            fontSize: 28,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
          ),
        ),
        const SizedBox(height: 5),
        const Text(
          'Sign in or create your account.',
          style: TextStyle(color: ChamaColors.muted, fontSize: 13.5),
        ),
        const SizedBox(height: 23),
        const Text(
          'Phone number',
          style: TextStyle(
            color: ChamaColors.ink,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 7),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.telephoneNumberNational],
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(10),
          ],
          onSubmitted: (_) => _busy ? null : _sendCode(),
          decoration: const InputDecoration(
            prefixIcon: Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 11, 0),
              child: Text(
                '+254',
                style: TextStyle(
                  color: ChamaColors.ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            prefixIconConstraints: BoxConstraints(minWidth: 0, minHeight: 0),
            hintText: '712 345 678',
          ),
        ),
        if (_error != null) _ErrorNote(_error!),
        const SizedBox(height: 20),
        _PrimaryButton(label: 'Continue', busy: _busy, onTap: _sendCode),
      ],
    );
  }

  Widget _otpForm() {
    return Column(
      key: const ValueKey('otp'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Enter the code',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            TextButton(
              onPressed: _busy ? null : _changeNumber,
              child: const Text('Change'),
            ),
          ],
        ),
        Text(
          'Sent to ${maskPhone(_normalizedPhone)}',
          style: const TextStyle(color: ChamaColors.muted, fontSize: 13.5),
        ),
        const SizedBox(height: 23),
        TextField(
          controller: _otp,
          autofocus: true,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: ChamaColors.ink,
            fontSize: 27,
            fontWeight: FontWeight.w800,
            letterSpacing: 11,
          ),
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          onSubmitted: (_) => _busy ? null : _verifyCode(),
          decoration: const InputDecoration(
            hintText: '000000',
            hintStyle: TextStyle(
              color: ChamaColors.line,
              fontSize: 27,
              letterSpacing: 11,
            ),
          ),
        ),
        if (_devCode != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: ChamaColors.soft,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Development code: $_devCode',
                style: const TextStyle(
                  color: ChamaColors.purple,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        if (_error != null) _ErrorNote(_error!),
        const SizedBox(height: 19),
        _PrimaryButton(label: 'Verify', busy: _busy, onTap: _verifyCode),
        const SizedBox(height: 9),
        Center(
          child: TextButton(
            onPressed: _busy ? null : _resend,
            child: const Text('Resend code'),
          ),
        ),
      ],
    );
  }

  Widget _registerForm() {
    return Column(
      key: const ValueKey('register'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Create your account',
          style: TextStyle(
            color: ChamaColors.ink,
            fontSize: 26,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.7,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          maskPhone(_normalizedPhone),
          style: const TextStyle(color: ChamaColors.muted, fontSize: 13.5),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _firstName,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.givenName],
          decoration: const InputDecoration(labelText: 'First name'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _lastName,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.familyName],
          decoration: const InputDecoration(labelText: 'Last name'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _pin,
          keyboardType: TextInputType.number,
          obscureText: true,
          textInputAction: TextInputAction.done,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(4),
          ],
          onSubmitted: (_) => _busy ? null : _register(),
          decoration: const InputDecoration(
            labelText: '4-digit PIN',
            helperText: 'You will use this PIN to approve payments.',
          ),
        ),
        if (_error != null) _ErrorNote(_error!),
        const SizedBox(height: 20),
        _PrimaryButton(label: 'Create account', busy: _busy, onTap: _register),
      ],
    );
  }
}

class _AuthHero extends StatelessWidget {
  const _AuthHero({required this.step});

  final _AuthStep step;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 272),
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 52),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [ChamaColors.deep, ChamaColors.purple],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -55,
            top: -75,
            child: Container(
              width: 190,
              height: 190,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.08),
                  width: 30,
                ),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const BrandLockup(onDark: true, markSize: 34),
              const SizedBox(height: 38),
              Text(
                step == _AuthStep.phone
                    ? 'Your chama,\ntogether.'
                    : step == _AuthStep.otp
                    ? 'One code.\nThen you are in.'
                    : 'Make it\nyours.',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.9,
                  height: 1.08,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Save, plan, grow.',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.busy,
    required this.onTap,
  });

  final String label;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: busy ? null : onTap,
        child: busy
            ? const SizedBox(
                width: 21,
                height: 21,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(label),
      ),
    );
  }
}

class _ErrorNote extends StatelessWidget {
  const _ErrorNote(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 17,
            color: ChamaColors.danger,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: ChamaColors.danger,
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

extension _FirstOrNullValue on Iterable<String> {
  String? get firstOrNull => isEmpty ? null : first;
}
