import 'package:intl/intl.dart';

String money(String raw) {
  final value = double.tryParse(raw.trim());
  if (value == null) return raw;
  return NumberFormat.currency(
    locale: 'en_KE',
    symbol: 'KES ',
    decimalDigits: 2,
  ).format(value);
}

String amountOnly(String raw) {
  final value = double.tryParse(raw.trim());
  if (value == null) return raw;
  return NumberFormat.currency(
    locale: 'en_KE',
    symbol: '',
    decimalDigits: 2,
  ).format(value).trim();
}

String maskedMoney() => 'KES ••••••';

String initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
  if (parts.isEmpty) return '?';
  return parts.take(2).map((p) => p.substring(0, 1).toUpperCase()).join();
}

String firstName(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return '';
  return trimmed.split(RegExp(r'\s+')).first;
}

String titleCase(String value) {
  final text = value.replaceAll('_', ' ').trim();
  if (text.isEmpty) return value;
  return text
      .split(' ')
      .map(
        (word) => word.isEmpty
            ? word
            : '${word.substring(0, 1).toUpperCase()}${word.substring(1).toLowerCase()}',
      )
      .join(' ');
}

String memberCount(int count) => count == 1 ? '1 member' : '$count members';

String compactMoney(String amount) {
  final value = double.tryParse(amount);
  if (value == null) return money(amount);
  return 'KES ${NumberFormat.decimalPattern('en_KE').format(value)}';
}

String frequencyUnit(String value) => switch (value) {
  'daily' => '/ day',
  'weekly' => '/ week',
  'monthly' => '/ month',
  'yearly' => '/ year',
  _ => '',
};

String frequencyLabel(String value) => switch (value) {
  'weekly' => 'Weekly',
  'biweekly' => 'Every two weeks',
  'quarterly' => 'Quarterly',
  _ => 'Monthly',
};

String shortDate(String? raw) {
  if (raw == null || raw.isEmpty) return '—';
  final date = DateTime.tryParse(raw);
  if (date == null) return raw;
  final local = date.toLocal();
  final now = DateTime.now();
  if (local.year == now.year &&
      local.month == now.month &&
      local.day == now.day) {
    return 'Today';
  }
  return DateFormat('d MMM').format(local);
}

String longDate(String? raw) {
  if (raw == null || raw.isEmpty) return '—';
  final date = DateTime.tryParse(raw);
  if (date == null) return raw;
  return DateFormat('EEE d MMM yyyy').format(date.toLocal());
}

String timeLabel(String? raw) {
  if (raw == null || raw.isEmpty) return '';
  final date = DateTime.tryParse(raw);
  if (date == null) return '';
  return DateFormat('HH:mm').format(date.toLocal());
}

String relativeTime(String? raw) {
  if (raw == null || raw.isEmpty) return '';
  final date = DateTime.tryParse(raw);
  if (date == null) return '';
  final diff = DateTime.now().difference(date.toLocal());
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return shortDate(raw);
}

String maskPhone(String phone) {
  final digits = phone.replaceAll(RegExp(r'\D'), '');
  if (digits.length < 5) return phone;
  final local = digits.startsWith('254')
      ? '0${digits.substring(3)}'
      : digits.startsWith('0')
      ? digits
      : '0$digits';
  if (local.length < 7) return local;
  return '${local.substring(0, 4)} ••• ${local.substring(local.length - 3)}';
}

String normalizedPhone(String raw) {
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.startsWith('254')) return '0${digits.substring(3)}';
  if (digits.startsWith('0')) return digits;
  return '0$digits';
}

String dueLabel(int contributionDay, String frequency) {
  final now = DateTime.now();
  if (frequency == 'weekly' || frequency == 'biweekly') {
    final day = DateTime(now.year, now.month, now.day);
    final next = day.add(Duration(days: 7 - (day.weekday % 7)));
    return DateFormat('EEE d MMM').format(next);
  }
  final day = contributionDay.clamp(1, 28).toInt();
  var due = DateTime(now.year, now.month, day);
  if (due.isBefore(DateTime(now.year, now.month, now.day))) {
    due = DateTime(now.year, now.month + 1, day);
  }
  return DateFormat('EEE d MMM').format(due);
}

bool isInflow(String type) => switch (type) {
  'contribution' ||
  'welfare_contribution' ||
  'loan_repayment' ||
  'fine' => true,
  _ => false,
};

String transactionTitle(String type) => switch (type) {
  'contribution' => 'Contribution',
  'welfare_contribution' => 'Welfare contribution',
  'loan_repayment' => 'Loan repayment',
  'loan_disbursement' => 'Loan disbursed',
  'welfare_payout' => 'Welfare payout',
  'rotation_payout' => 'Rotation payout',
  'fine' => 'Fine',
  'manual_adjustment' => 'Adjustment',
  _ => titleCase(type),
};

String transactionSignedAmount(String type, String amount) {
  final prefix = isInflow(type) ? '+' : '−';
  return '$prefix ${money(amount)}';
}
