import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../core/widgets.dart';

Future<void> showLedgerReceipt(BuildContext context, LedgerEntry entry) {
  return showDialog<void>(
    context: context,
    useSafeArea: true,
    builder: (context) => _ReceiptDialog(
      icon: isInflow(entry.type)
          ? Icons.south_west_rounded
          : Icons.north_east_rounded,
      iconColor: isInflow(entry.type) ? ChamaColors.green : ChamaColors.purple,
      iconBackground: isInflow(entry.type)
          ? ChamaColors.greenSoft
          : ChamaColors.soft,
      title: 'Transaction receipt',
      subtitle: transactionTitle(entry.type),
      amount: money(entry.amount),
      details: [
        _ReceiptRow(label: 'Status', status: entry.status),
        _ReceiptRow(label: 'Member', value: entry.member),
        _ReceiptRow(
          label: 'Date',
          value: '${longDate(entry.createdAt)} · ${timeLabel(entry.createdAt)}',
        ),
        if (entry.channel != null && entry.channel!.isNotEmpty)
          _ReceiptRow(label: 'Channel', value: titleCase(entry.channel!)),
        if (entry.referenceCode != null && entry.referenceCode!.isNotEmpty)
          _ReceiptRow(label: 'Reference', value: entry.referenceCode!),
        if (entry.periodLabel != null && entry.periodLabel!.isNotEmpty)
          _ReceiptRow(label: 'Period', value: entry.periodLabel!),
        if (entry.narration.isNotEmpty)
          _ReceiptRow(label: 'Details', value: entry.narration),
      ],
      action: 'Close',
    ),
  );
}

Future<void> showPaymentReceipt(
  BuildContext context, {
  required Chama group,
  required StkResult result,
  String? phone,
}) {
  final pending = result.status != 'completed';
  return showDialog<void>(
    context: context,
    useSafeArea: true,
    builder: (context) => _ReceiptDialog(
      icon: pending ? Icons.phone_iphone_rounded : Icons.check_rounded,
      iconColor: pending ? ChamaColors.purple : ChamaColors.green,
      iconBackground: pending ? ChamaColors.soft : ChamaColors.greenSoft,
      title: pending ? 'Payment request sent' : 'Payment received',
      subtitle: pending
          ? 'Check your phone for the M-Pesa prompt.'
          : 'Your payment has been received.',
      amount: money(result.amount),
      details: [
        _ReceiptRow(label: 'Chama', value: group.name),
        _ReceiptRow(label: 'Purpose', value: titleCase(result.purpose)),
        _ReceiptRow(label: 'Status', status: result.status),
        if (phone != null && phone.isNotEmpty)
          _ReceiptRow(label: 'M-Pesa', value: maskPhone(phone)),
        _ReceiptRow(
          label: 'Reference',
          value: result.paymentRequestId.isEmpty
              ? 'Awaiting M-Pesa'
              : result.paymentRequestId,
        ),
      ],
      note: pending
          ? 'Enter your M-Pesa PIN on your phone to complete this payment.'
          : null,
      action: 'Done',
    ),
  );
}

class _ReceiptDialog extends StatelessWidget {
  const _ReceiptDialog({
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.details,
    required this.action,
    this.note,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final String title;
  final String subtitle;
  final String amount;
  final List<Widget> details;
  final String action;
  final String? note;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 384),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  color: iconBackground,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor, size: 31),
              ),
              const SizedBox(height: 15),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: ChamaColors.ink,
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: ChamaColors.muted,
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 19),
              Text(
                amount,
                style: const TextStyle(
                  color: ChamaColors.ink,
                  fontSize: 29,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.8,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 19),
              const Divider(),
              const SizedBox(height: 7),
              ...details,
              if (note != null) ...[
                const SizedBox(height: 7),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: ChamaColors.soft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    note!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: ChamaColors.purple,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(action),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReceiptRow extends StatelessWidget {
  const _ReceiptRow({required this.label, this.value, this.status});

  final String label;
  final String? value;
  final String? status;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 91,
            child: Text(
              label,
              style: const TextStyle(color: ChamaColors.muted, fontSize: 11),
            ),
          ),
          Expanded(
            child: status != null
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: StatusPill(status: status!),
                  )
                : Text(
                    value ?? '—',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: ChamaColors.ink,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
