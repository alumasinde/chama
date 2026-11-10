import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api.dart';
import '../core/app_state.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../core/theme.dart';

Future<void> showContributeSheet(
  BuildContext context,
  AppController controller,
  Chama group, {
  String purpose = 'contribution',
  String? initialAmount,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ContributeSheet(
      controller: controller,
      group: group,
      purpose: purpose,
      initialAmount: initialAmount,
    ),
  );
}

class _ContributeSheet extends StatefulWidget {
  const _ContributeSheet({
    required this.controller,
    required this.group,
    required this.purpose,
    this.initialAmount,
  });

  final AppController controller;
  final Chama group;
  final String purpose;
  final String? initialAmount;

  @override
  State<_ContributeSheet> createState() => _ContributeSheetState();
}

class _ContributeSheetState extends State<_ContributeSheet> {
  late final TextEditingController _amount = TextEditingController(
    text: _clean(widget.initialAmount ?? widget.group.contributionAmount),
  );
  String? _error;
  bool _busy = false;
  bool _done = false;
  StkResult? _result;

  String get _title => switch (widget.purpose) {
    'fine' => 'Pay fine',
    'loan_repayment' => 'Repay loan',
    'welfare_contribution' => 'Welfare',
    _ => 'Contribute',
  };

  List<String> get _presets {
    final values = <String>{
      '500',
      '1000',
      '2000',
      widget.group.contributionAmount,
    };
    return values.toList();
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _pay() async {
    final value = double.tryParse(_amount.text.replaceAll(',', ''));
    if (value == null || value < 1) {
      setState(() => _error = 'Enter an amount of at least KES 1.');
      return;
    }
    final pin = await showPinSheet(context);
    if (pin == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.controller.pay(
        group: widget.group,
        pin: pin,
        amount: value.toStringAsFixed(2),
        purpose: widget.purpose,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _done = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _paymentMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        8,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        child: _done ? _success() : _form(),
      ),
    );
  }

  Widget _form() {
    final phone = widget.controller.user?.phoneNumber ?? '';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: ChamaColors.line,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          _title,
          style: const TextStyle(
            color: ChamaColors.ink,
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          widget.group.name,
          style: const TextStyle(color: ChamaColors.muted, fontSize: 12.5),
        ),
        const SizedBox(height: 22),
        const Text(
          'Amount',
          style: TextStyle(
            color: ChamaColors.ink,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _amount,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          style: const TextStyle(
            color: ChamaColors.ink,
            fontSize: 24,
            fontWeight: FontWeight.w800,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
          decoration: const InputDecoration(
            prefixText: 'KES  ',
            prefixStyle: TextStyle(
              color: ChamaColors.muted,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
            hintText: '0.00',
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final preset in _presets)
              _AmountChip(
                label: 'KES ${_clean(preset)}',
                selected: _amount.text == preset,
                onTap: () => setState(() => _amount.text = preset),
              ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          _PaymentError(message: _error!),
        ],
        const SizedBox(height: 22),
        Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: ChamaColors.soft,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.phone_iphone_rounded,
                color: ChamaColors.purple,
                size: 20,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'M-Pesa',
                      style: TextStyle(
                        color: ChamaColors.ink,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      phone.isEmpty
                          ? 'A prompt will open on your phone.'
                          : maskPhone(phone),
                      style: const TextStyle(
                        color: ChamaColors.muted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.lock_outline_rounded,
                color: ChamaColors.muted,
                size: 17,
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _busy ? null : _pay,
            child: _busy
                ? const SizedBox(
                    width: 21,
                    height: 21,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text('Pay via M-Pesa'),
          ),
        ),
        const SizedBox(height: 10),
        const Center(
          child: Text(
            'Secure & encrypted',
            style: TextStyle(
              color: ChamaColors.muted,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _success() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 18),
        Container(
          width: 66,
          height: 66,
          decoration: const BoxDecoration(
            color: ChamaColors.greenSoft,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check_rounded,
            color: ChamaColors.green,
            size: 34,
          ),
        ),
        const SizedBox(height: 17),
        const Text(
          'Check your phone',
          style: TextStyle(
            color: ChamaColors.ink,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Enter your M-Pesa PIN to complete the payment.',
          textAlign: TextAlign.center,
          style: TextStyle(color: ChamaColors.muted, fontSize: 13.5),
        ),
        if (_result != null) ...[
          const SizedBox(height: 16),
          Text(
            money(_result!.amount),
            style: const TextStyle(
              color: ChamaColors.ink,
              fontSize: 26,
              fontWeight: FontWeight.w800,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
        const SizedBox(height: 22),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ),
      ],
    );
  }
}

class _AmountChip extends StatelessWidget {
  const _AmountChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? ChamaColors.purple : ChamaColors.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? ChamaColors.purple : ChamaColors.line,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : ChamaColors.ink,
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _PaymentError extends StatelessWidget {
  const _PaymentError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4F3),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        message,
        style: const TextStyle(color: ChamaColors.danger, fontSize: 12),
      ),
    );
  }
}

Future<String?> showPinSheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const _PinSheet(),
  );
}

class _PinSheet extends StatefulWidget {
  const _PinSheet();

  @override
  State<_PinSheet> createState() => _PinSheetState();
}

class _PinSheetState extends State<_PinSheet> {
  final _pin = TextEditingController();

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ready = _pin.text.length == 4;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        22,
        10,
        22,
        MediaQuery.viewInsetsOf(context).bottom + 26,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: ChamaColors.line,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          const SizedBox(height: 22),
          const Text(
            'Enter your PIN',
            style: TextStyle(
              color: ChamaColors.ink,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Approve this payment.',
            style: TextStyle(color: ChamaColors.muted, fontSize: 13),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _pin,
            autofocus: true,
            obscureText: true,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            maxLength: 4,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(4),
            ],
            onChanged: (_) => setState(() {}),
            onSubmitted: (value) {
              if (value.length == 4) Navigator.of(context).pop(value);
            },
            style: const TextStyle(
              color: ChamaColors.ink,
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: 12,
            ),
            decoration: const InputDecoration(
              counterText: '',
              hintText: '••••',
              hintStyle: TextStyle(
                color: ChamaColors.line,
                fontSize: 26,
                letterSpacing: 12,
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: ready
                  ? () => Navigator.of(context).pop(_pin.text)
                  : null,
              child: const Text('Confirm'),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> showJoinChamaSheet(
  BuildContext context,
  AppController controller,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _JoinChamaSheet(controller: controller),
  );
}

class _JoinChamaSheet extends StatefulWidget {
  const _JoinChamaSheet({required this.controller});

  final AppController controller;

  @override
  State<_JoinChamaSheet> createState() => _JoinChamaSheetState();
}

class _JoinChamaSheetState extends State<_JoinChamaSheet> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    if (RegExp(r'^[A-Z0-9]{8}$').hasMatch(_code.text) == false) {
      setState(() => _error = 'Enter the 8-character invite code.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.controller.joinChama(_code.text);
      if (!mounted) return;
      Navigator.of(context).pop();
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            result.status == 'active' ? 'Chama joined' : 'Request sent',
          ),
          content: Text(
            result.status == 'active'
                ? result.groupName
                : '${result.groupName} will appear after an admin approves you.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _error = error is ApiException ? error.message : 'Try again.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        22,
        10,
        22,
        MediaQuery.viewInsetsOf(context).bottom + 26,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: ChamaColors.line,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Join a chama',
            style: TextStyle(
              color: ChamaColors.ink,
              fontSize: 23,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'Enter the invite code from an admin.',
            style: TextStyle(color: ChamaColors.muted, fontSize: 13),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _code,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            maxLength: 8,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
              UpperCaseTextFormatter(),
            ],
            style: const TextStyle(
              color: ChamaColors.ink,
              fontSize: 21,
              fontWeight: FontWeight.w800,
              letterSpacing: 4,
            ),
            textAlign: TextAlign.center,
            decoration: const InputDecoration(
              counterText: '',
              hintText: 'ABCD1234',
              hintStyle: TextStyle(
                color: ChamaColors.line,
                fontSize: 20,
                letterSpacing: 4,
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: const TextStyle(color: ChamaColors.danger, fontSize: 12),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _busy ? null : _join,
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Join'),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> showCreateChamaSheet(
  BuildContext context,
  AppController controller,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _CreateChamaSheet(controller: controller),
  );
}

class _CreateChamaSheet extends StatefulWidget {
  const _CreateChamaSheet({required this.controller});

  final AppController controller;

  @override
  State<_CreateChamaSheet> createState() => _CreateChamaSheetState();
}

class _CreateChamaSheetState extends State<_CreateChamaSheet> {
  final _name = TextEditingController();
  final _amount = TextEditingController(text: '1000');
  String _frequency = 'monthly';
  int _day = DateTime.now().day.clamp(1, 28);
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_name.text.trim().length < 2) {
      setState(() => _error = 'Enter a chama name.');
      return;
    }
    if ((double.tryParse(_amount.text) ?? 0) < 1) {
      setState(() => _error = 'Enter a contribution amount.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.controller.createChama(
        name: _name.text,
        amount: _amount.text,
        frequency: _frequency,
        contributionDay: _day,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Chama created.')));
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _error = error is ApiException ? error.message : 'Try again.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        22,
        10,
        22,
        MediaQuery.viewInsetsOf(context).bottom + 26,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: ChamaColors.line,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Start a chama',
              style: TextStyle(
                color: ChamaColors.ink,
                fontSize: 23,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Chama name'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _amount,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Contribution amount',
                prefixText: 'KES  ',
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _frequency,
              decoration: const InputDecoration(labelText: 'Frequency'),
              items: const [
                DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                DropdownMenuItem(
                  value: 'biweekly',
                  child: Text('Every two weeks'),
                ),
                DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _frequency = value);
              },
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<int>(
              initialValue: _day,
              decoration: const InputDecoration(labelText: 'Contribution day'),
              items: [
                for (final day in [1, 5, 10, 15, 20, 25])
                  DropdownMenuItem(value: day, child: Text('Day $day')),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _day = value);
              },
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: const TextStyle(color: ChamaColors.danger, fontSize: 12),
              ),
            ],
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy ? null : _create,
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Create chama'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}

String _clean(String raw) {
  if (raw.endsWith('.00')) return raw.substring(0, raw.length - 3);
  return raw;
}

String _paymentMessage(Object error) {
  if (error is ApiException) {
    return switch (error.code) {
      'payment_settings_missing' => 'This chama has not connected M-Pesa yet.',
      'pin_incorrect' => 'That PIN is not correct.',
      'pin_locked' => 'Your PIN is locked. Try again later.',
      'amount_not_whole_shillings' => 'Use whole shillings only.',
      'step_up_required' => 'Enter your PIN again.',
      'provider_error' => 'M-Pesa did not accept the request. Try again.',
      'idempotency_conflict' => 'That request was already used. Try again.',
      _ => error.message,
    };
  }
  return 'We could not start the payment. Try again.';
}
