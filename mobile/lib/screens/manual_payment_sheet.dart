import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api.dart';
import '../core/app_state.dart';
import '../core/models.dart';
import '../core/theme.dart';
import 'sheets.dart' show UpperCaseTextFormatter, showPinSheet;

/// Records a contribution the treasurer already received, with the M-Pesa code as reference.
Future<bool?> showManualContributionSheet(
  BuildContext context,
  AppController controller,
  Chama group,
  List<Member> members,
) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ManualContributionSheet(
      controller: controller,
      group: group,
      members: members,
    ),
  );
}

class _ManualContributionSheet extends StatefulWidget {
  const _ManualContributionSheet({
    required this.controller,
    required this.group,
    required this.members,
  });

  final AppController controller;
  final Chama group;
  final List<Member> members;

  @override
  State<_ManualContributionSheet> createState() =>
      _ManualContributionSheetState();
}

class _ManualContributionSheetState extends State<_ManualContributionSheet> {
  late final TextEditingController _amount = TextEditingController(
    text: widget.group.contributionAmount,
  );
  final _reference = TextEditingController();
  final _narration = TextEditingController();
  String? _memberId;
  String? _error;
  Map<String, String> _fields = const {};
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    _narration.dispose();
    super.dispose();
  }

  Future<void> _record() async {
    final memberId = _memberId;
    if (memberId == null) {
      setState(() => _error = 'Choose the member who paid.');
      return;
    }
    final value = double.tryParse(_amount.text.replaceAll(',', ''));
    if (value == null || value < 1) {
      setState(() => _error = 'Enter an amount of at least KES 1.');
      return;
    }
    final reference = _reference.text.trim().toUpperCase();
    if (reference.length < 6) {
      setState(() => _error = 'Enter the M-Pesa code from the SMS.');
      return;
    }
    final pin = await showPinSheet(context);
    if (pin == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
      _fields = const {};
    });
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final result = await widget.controller.recordManualContribution(
        group: widget.group,
        pin: pin,
        memberId: memberId,
        amount: value.toStringAsFixed(2),
        reference: reference,
        narration: _narration.text.trim(),
      );
      if (!mounted) return;
      navigator.pop(true);
      messenger.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Contribution recorded · ${result.reference}'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        if (error is ApiException) {
          _fields = error.fields;
          _error = error.fields.isEmpty ? error.message : null;
        } else {
          _error = 'Could not record the payment. Try again.';
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _fieldError(String key) => _fields[key];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        8,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 24,
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
            'Record a payment',
            style: TextStyle(
              color: ChamaColors.ink,
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Money ${widget.group.name} already received',
            style: const TextStyle(color: ChamaColors.muted, fontSize: 12.5),
          ),
          const SizedBox(height: 20),
          const _FieldLabel('Member'),
          const SizedBox(height: 8),
          InputDecorator(
            decoration: const InputDecoration(
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _memberId,
                isExpanded: true,
                hint: const Text('Choose a member'),
                items: [
                  for (final member in widget.members)
                    DropdownMenuItem(
                      value: member.id,
                      child: Text(
                        member.displayName.isEmpty
                            ? member.firstName
                            : member.displayName,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) => setState(() => _memberId = value),
              ),
            ),
          ),
          if (_fieldError('member_id') != null)
            _FieldError(_fieldError('member_id')!),
          const SizedBox(height: 14),
          const _FieldLabel('Amount'),
          const SizedBox(height: 8),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            style: const TextStyle(
              color: ChamaColors.ink,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
            decoration: const InputDecoration(
              prefixText: 'KES  ',
              hintText: '0.00',
            ),
          ),
          if (_fieldError('amount') != null)
            _FieldError(_fieldError('amount')!),
          const SizedBox(height: 14),
          const _FieldLabel('M-Pesa code'),
          const SizedBox(height: 8),
          TextField(
            controller: _reference,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
              UpperCaseTextFormatter(),
              LengthLimitingTextInputFormatter(24),
            ],
            style: const TextStyle(
              color: ChamaColors.ink,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
            decoration: const InputDecoration(hintText: 'SLK7XQ2P9D'),
          ),
          if (_fieldError('reference') != null)
            _FieldError(_fieldError('reference')!),
          const SizedBox(height: 14),
          const _FieldLabel('Note (optional)'),
          const SizedBox(height: 8),
          TextField(
            controller: _narration,
            maxLength: 120,
            decoration: const InputDecoration(
              hintText: 'For example January contribution',
            ),
          ),
          if (_error != null) _FieldError(_error!),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: ChamaColors.soft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.playlist_add_check_rounded,
                  color: ChamaColors.purple,
                  size: 19,
                ),
                SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'This writes a completed contribution to the chama ledger. '
                    'Use it for members who pay the paybill or hand cash to the treasurer.',
                    style: TextStyle(
                      color: ChamaColors.muted,
                      fontSize: 11,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _busy ? null : _record,
              child: _busy
                  ? const SizedBox(
                      width: 21,
                      height: 21,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Record contribution'),
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: ChamaColors.ink,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _FieldError extends StatelessWidget {
  const _FieldError(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        message,
        style: const TextStyle(color: ChamaColors.danger, fontSize: 11.5),
      ),
    );
  }
}
