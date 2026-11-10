import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api.dart';
import '../core/app_state.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import 'sheets.dart';

String _message(Object error) =>
    error is ApiException ? error.message : 'Something went wrong. Try again.';

class FinesScreen extends StatefulWidget {
  const FinesScreen({super.key, required this.controller, required this.group});

  final AppController controller;
  final Chama group;

  @override
  State<FinesScreen> createState() => _FinesScreenState();
}

class _FinesScreenState extends State<FinesScreen> {
  late Future<List<Fine>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.controller.api.fines(widget.group.id);
  }

  Future<void> _reload() async {
    final future = widget.controller.api.fines(widget.group.id);
    setState(() => _future = future);
    await future;
  }

  Future<void> _pay(Fine fine) async {
    await showContributeSheet(
      context,
      widget.controller,
      widget.group,
      purpose: 'fine',
      initialAmount: fine.amount,
    );
    if (mounted) await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Fines')),
      body: FutureBuilder<List<Fine>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const _LoadingList();
          }
          if (snapshot.hasError) {
            return ErrorState(
              message: snapshot.error.toString(),
              onRetry: _reload,
            );
          }
          final fines = snapshot.data ?? const <Fine>[];
          final unpaid = fines.where((fine) => fine.isUnpaid).toList();
          final total = unpaid.fold<double>(
            0,
            (sum, fine) => sum + (double.tryParse(fine.amount) ?? 0),
          );
          if (fines.isEmpty) {
            return const EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'No fines.',
            );
          }
          return RefreshIndicator(
            color: ChamaColors.purple,
            onRefresh: _reload,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              children: [
                GradientPanel(
                  padding: const EdgeInsets.all(19),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Outstanding fines',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        money(total.toStringAsFixed(2)),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        unpaid.length == 1
                            ? '1 fine to clear'
                            : '${unpaid.length} fines to clear',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const SectionHeading(title: 'My fines'),
                const SizedBox(height: 8),
                for (final fine in fines) ...[
                  _FineCard(fine: fine, onPay: () => _pay(fine)),
                  const SizedBox(height: 9),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _FineCard extends StatelessWidget {
  const _FineCard({required this.fine, required this.onPay});

  final Fine fine;
  final VoidCallback onPay;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: fine.isUnpaid
                      ? ChamaColors.warningSoft
                      : ChamaColors.greenSoft,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  fine.isUnpaid
                      ? Icons.gavel_rounded
                      : Icons.check_circle_outline_rounded,
                  color: fine.isUnpaid
                      ? ChamaColors.warning
                      : ChamaColors.green,
                  size: 20,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titleCase(fine.fineType),
                      style: const TextStyle(
                        color: ChamaColors.ink,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      fine.reason,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: ChamaColors.muted,
                        fontSize: 11.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    money(fine.amount),
                    style: const TextStyle(
                      color: ChamaColors.ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 4),
                  StatusPill(status: fine.status),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                fine.periodLabel == null || fine.periodLabel!.isEmpty
                    ? 'Assessed ${shortDate(fine.assessedOn)}'
                    : '${fine.periodLabel} · ${shortDate(fine.assessedOn)}',
                style: const TextStyle(
                  color: ChamaColors.muted,
                  fontSize: 10.5,
                ),
              ),
              const Spacer(),
              if (fine.isUnpaid)
                FilledButton(
                  onPressed: onPay,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 34),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    backgroundColor: ChamaColors.green,
                    textStyle: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: const Text('Pay via M-Pesa'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class LoanDetailScreen extends StatefulWidget {
  const LoanDetailScreen({
    super.key,
    required this.controller,
    required this.group,
    required this.loan,
  });

  final AppController controller;
  final Chama group;
  final Loan loan;

  @override
  State<LoanDetailScreen> createState() => _LoanDetailScreenState();
}

class _LoanDetailScreenState extends State<LoanDetailScreen> {
  late Future<_LoanDetailData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_LoanDetailData> _load() async {
    final loan = await widget.controller.api.loanDetail(
      widget.group.id,
      widget.loan.id,
    );
    var schedule = const <Installment>[];
    try {
      schedule = await widget.controller.api.loanSchedule(
        widget.group.id,
        widget.loan.id,
      );
    } catch (_) {
      // A loan can exist before its schedule is generated.
    }
    return _LoanDetailData(loan: loan, schedule: schedule);
  }

  Future<void> _reload() async {
    final future = _load();
    setState(() => _future = future);
    await future;
  }

  Future<void> _respond(Guarantor guarantee, String decision) async {
    setState(() {});
    try {
      await widget.controller.respondToGuarantee(
        group: widget.group,
        loanId: widget.loan.id,
        decision: decision,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Guarantee ${decision.toLowerCase()}.')),
      );
      await _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_message(error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Loan')),
      body: FutureBuilder<_LoanDetailData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const _LoadingList();
          }
          if (snapshot.hasError) {
            return ErrorState(
              message: snapshot.error.toString(),
              onRetry: _reload,
            );
          }
          final data = snapshot.data!;
          final loan = data.loan;
          final me = widget.controller.user?.id;
          Guarantor? mine;
          for (final guarantee in loan.guarantors) {
            if (guarantee.userId == me) {
              mine = guarantee;
              break;
            }
          }
          return RefreshIndicator(
            color: ChamaColors.purple,
            onRefresh: _reload,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              children: [
                GradientPanel(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Loan amount',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          StatusPill(status: loan.status),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        money(loan.principal),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(height: 13),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: loan.progress,
                          minHeight: 6,
                          backgroundColor: Colors.white24,
                          color: ChamaColors.green,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text(
                            '${money(loan.paidToDate)} repaid',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${money(loan.outstanding)} left',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                SurfaceCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _DetailRow(label: 'Borrower', value: loan.borrower),
                      _DetailRow(label: 'Purpose', value: loan.purpose),
                      _DetailRow(
                        label: 'Term',
                        value:
                            '${loan.termMonths} ${loan.termMonths == 1 ? 'month' : 'months'}',
                      ),
                      _DetailRow(
                        label: 'Interest',
                        value:
                            '${loan.interestRate}% ${titleCase(loan.interestMethod)}',
                      ),
                      _DetailRow(
                        label: 'Total payable',
                        value: money(loan.totalPayable),
                      ),
                      _DetailRow(
                        label: 'Requested',
                        value: longDate(loan.requestedAt),
                        last: true,
                      ),
                    ],
                  ),
                ),
                if (mine != null &&
                    mine.status == 'pending' &&
                    loan.status == 'pending_guarantors') ...[
                  const SizedBox(height: 18),
                  SurfaceCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Your guarantee is requested',
                          style: TextStyle(
                            color: ChamaColors.ink,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '${money(mine.amount)} for ${loan.borrower}.',
                          style: const TextStyle(
                            color: ChamaColors.muted,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 13),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => _respond(mine!, 'declined'),
                                child: const Text('Decline'),
                              ),
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: FilledButton(
                                onPressed: () => _respond(mine!, 'accepted'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: ChamaColors.green,
                                ),
                                child: const Text('Accept'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
                if (loan.guarantors.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const SectionHeading(title: 'Guarantors'),
                  const SizedBox(height: 8),
                  SurfaceCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 15,
                      vertical: 5,
                    ),
                    child: Column(
                      children: [
                        for (final guarantee in loan.guarantors)
                          _GuarantorRow(guarantee: guarantee),
                      ],
                    ),
                  ),
                ],
                if (loan.approvals.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const SectionHeading(title: 'Approvals'),
                  const SizedBox(height: 8),
                  SurfaceCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 15,
                      vertical: 5,
                    ),
                    child: Column(
                      children: [
                        for (final approval in loan.approvals)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    approval.displayName,
                                    style: const TextStyle(
                                      color: ChamaColors.ink,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                StatusPill(status: approval.decision),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                const SectionHeading(title: 'Repayment schedule'),
                const SizedBox(height: 8),
                if (data.schedule.isEmpty)
                  const EmptyState(
                    icon: Icons.event_note_outlined,
                    title: 'No schedule yet.',
                  )
                else
                  for (final installment in data.schedule) ...[
                    _InstallmentCard(installment: installment),
                    const SizedBox(height: 8),
                  ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _GuarantorRow extends StatelessWidget {
  const _GuarantorRow({required this.guarantee});

  final Guarantor guarantee;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Avatar(name: guarantee.displayName, size: 34),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  guarantee.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: ChamaColors.ink,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  money(guarantee.amount),
                  style: const TextStyle(
                    color: ChamaColors.muted,
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),
          StatusPill(status: guarantee.status),
        ],
      ),
    );
  }
}

class _InstallmentCard extends StatelessWidget {
  const _InstallmentCard({required this.installment});

  final Installment installment;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: installment.isPaid
                  ? ChamaColors.greenSoft
                  : ChamaColors.soft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${installment.number}',
              style: TextStyle(
                color: installment.isPaid
                    ? ChamaColors.green
                    : ChamaColors.purple,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  money(installment.total),
                  style: const TextStyle(
                    color: ChamaColors.ink,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  installment.isPaid
                      ? 'Paid ${shortDate(installment.paidAt)}'
                      : 'Due ${shortDate(installment.dueDate)}',
                  style: const TextStyle(
                    color: ChamaColors.muted,
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),
          StatusPill(status: installment.isPaid ? 'paid' : 'due'),
        ],
      ),
    );
  }
}

class _LoanDetailData {
  const _LoanDetailData({required this.loan, required this.schedule});

  final Loan loan;
  final List<Installment> schedule;
}

class RotationScreen extends StatefulWidget {
  const RotationScreen({
    super.key,
    required this.controller,
    required this.group,
  });

  final AppController controller;
  final Chama group;

  @override
  State<RotationScreen> createState() => _RotationScreenState();
}

class _RotationScreenState extends State<RotationScreen> {
  late Future<List<RotationCycle>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.controller.api.rotationCycles(widget.group.id);
  }

  Future<void> _reload() async {
    final future = widget.controller.api.rotationCycles(widget.group.id);
    setState(() => _future = future);
    await future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rotation')),
      body: FutureBuilder<List<RotationCycle>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const _LoadingList();
          }
          if (snapshot.hasError) {
            return ErrorState(
              message: snapshot.error.toString(),
              onRetry: _reload,
            );
          }
          final cycles = snapshot.data ?? const <RotationCycle>[];
          if (cycles.isEmpty) {
            return const EmptyState(
              icon: Icons.sync_rounded,
              title: 'No rotation yet.',
            );
          }
          RotationCycle? current;
          for (final cycle in cycles) {
            if (cycle.status == 'active') {
              current = cycle;
              break;
            }
          }
          current ??= cycles.first;
          final me = widget.controller.user?.id;
          RotationSlot? mine;
          for (final slot in current.slots) {
            if (slot.userId == me) {
              mine = slot;
              break;
            }
          }
          return RefreshIndicator(
            color: ChamaColors.purple,
            onRefresh: _reload,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              children: [
                GradientPanel(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              current.name,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          StatusPill(status: current.status),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        money(current.contribution),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 29,
                          fontWeight: FontWeight.w800,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${titleCase(current.orderingMode)} order · ${memberCount(current.memberCount)}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11.5,
                        ),
                      ),
                      if (mine != null) ...[
                        const SizedBox(height: 15),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.event_available_outlined,
                                color: ChamaColors.green,
                                size: 19,
                              ),
                              const SizedBox(width: 9),
                              Expanded(
                                child: Text(
                                  mine.paid
                                      ? 'You received this payout.'
                                      : 'Your turn: ${shortDate(mine.payoutDate)}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Text(
                                '#${mine.position}',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 15),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: current.progress,
                          minHeight: 6,
                          backgroundColor: Colors.white24,
                          color: ChamaColors.green,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        '${current.paidCount} of ${current.slotCount} payouts made',
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                SectionHeading(
                  title: 'Payout order',
                  action: current.slots.isEmpty
                      ? null
                      : '${current.slots.length}',
                ),
                const SizedBox(height: 8),
                if (current.slots.isEmpty)
                  const EmptyState(
                    icon: Icons.shuffle_rounded,
                    title: 'Order not drawn yet.',
                  )
                else
                  for (final slot in current.slots) ...[
                    _RotationSlotCard(slot: slot, isMine: slot.userId == me),
                    const SizedBox(height: 8),
                  ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _RotationSlotCard extends StatelessWidget {
  const _RotationSlotCard({required this.slot, required this.isMine});

  final RotationSlot slot;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      color: isMine ? ChamaColors.soft : ChamaColors.surface,
      padding: const EdgeInsets.all(13),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: slot.paid
                  ? ChamaColors.greenSoft
                  : isMine
                  ? ChamaColors.purple
                  : ChamaColors.soft,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Text(
              '${slot.position}',
              style: TextStyle(
                color: slot.paid
                    ? ChamaColors.green
                    : isMine
                    ? Colors.white
                    : ChamaColors.purple,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isMine ? '${slot.member} (you)' : slot.member,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: ChamaColors.ink,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  shortDate(slot.payoutDate),
                  style: const TextStyle(
                    color: ChamaColors.muted,
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),
          StatusPill(status: slot.paid ? 'paid' : 'upcoming'),
        ],
      ),
    );
  }
}

Future<Loan?> showLoanRequestSheet(
  BuildContext context,
  AppController controller,
  Chama group,
  LoanSettings settings,
  List<Member> members,
) {
  return showModalBottomSheet<Loan>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _LoanRequestSheet(
      controller: controller,
      group: group,
      settings: settings,
      members: members,
    ),
  );
}

class _LoanRequestSheet extends StatefulWidget {
  const _LoanRequestSheet({
    required this.controller,
    required this.group,
    required this.settings,
    required this.members,
  });

  final AppController controller;
  final Chama group;
  final LoanSettings settings;
  final List<Member> members;

  @override
  State<_LoanRequestSheet> createState() => _LoanRequestSheetState();
}

class _LoanRequestSheetState extends State<_LoanRequestSheet> {
  final _amount = TextEditingController();
  final _purpose = TextEditingController();
  final _selected = <String>{};
  late final List<int> _terms;
  late int _term;
  bool _busy = false;
  String? _error;

  List<Member> get _candidates {
    final me = widget.controller.user?.id;
    return widget.members
        .where((member) => member.id != me && member.status == 'active')
        .toList();
  }

  @override
  void initState() {
    super.initState();
    final max = widget.settings.maxTermMonths < 1
        ? 1
        : widget.settings.maxTermMonths;
    _terms = <int>{1, 2, 3, 6, 12, max}.where((term) => term <= max).toList()
      ..sort();
    _term = _terms.contains(3) ? 3 : _terms.first;
  }

  @override
  void dispose() {
    _amount.dispose();
    _purpose.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amount = double.tryParse(_amount.text.replaceAll(',', ''));
    final purpose = _purpose.text.trim();
    if (amount == null || amount < 1) {
      setState(() => _error = 'Enter an amount of at least KES 1.');
      return;
    }
    if (purpose.isEmpty || purpose.length > 200) {
      setState(() => _error = 'Describe the purpose in 1 to 200 characters.');
      return;
    }
    if (_selected.length != widget.settings.guarantorsRequired) {
      setState(
        () => _error =
            'Choose ${widget.settings.guarantorsRequired} guarantor(s).',
      );
      return;
    }
    final pin = await showPinSheet(context);
    if (pin == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final share = _selected.isEmpty
          ? '0.00'
          : (amount / _selected.length).toStringAsFixed(2);
      final loan = await widget.controller.applyLoan(
        group: widget.group,
        pin: pin,
        amount: amount.toStringAsFixed(2),
        termMonths: _term,
        purpose: purpose,
        guarantors: [
          for (final userId in _selected) (userId: userId, amount: share),
        ],
      );
      if (!mounted) return;
      Navigator.of(context).pop(loan);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final required = widget.settings.guarantorsRequired;
    final candidates = _candidates;
    return SingleChildScrollView(
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
            'Request a loan',
            style: TextStyle(
              color: ChamaColors.ink,
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Up to ${widget.settings.maxMultiple}× your savings · ${widget.settings.interestRate}% ${titleCase(widget.settings.interestMethod)}',
            style: const TextStyle(color: ChamaColors.muted, fontSize: 11.5),
          ),
          const SizedBox(height: 20),
          const _FieldLabel('Amount'),
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
              fontSize: 23,
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
          const SizedBox(height: 18),
          const _FieldLabel('Term'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final term in _terms)
                ChoiceChip(
                  label: Text('$term ${term == 1 ? 'month' : 'months'}'),
                  selected: _term == term,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _term = term),
                  selectedColor: ChamaColors.purple,
                  labelStyle: TextStyle(
                    color: _term == term ? Colors.white : ChamaColors.muted,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                  side: BorderSide(
                    color: _term == term
                        ? ChamaColors.purple
                        : ChamaColors.line,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          const _FieldLabel('Purpose'),
          const SizedBox(height: 8),
          TextField(
            controller: _purpose,
            maxLength: 200,
            maxLines: 2,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'What is the loan for?',
              counterText: '',
            ),
          ),
          if (required > 0) ...[
            const SizedBox(height: 15),
            _FieldLabel('Guarantors (${_selected.length}/$required)'),
            const SizedBox(height: 4),
            Text(
              'Choose $required member${required == 1 ? '' : 's'} to back this loan.',
              style: const TextStyle(color: ChamaColors.muted, fontSize: 11),
            ),
            const SizedBox(height: 8),
            if (candidates.length < required)
              const Text(
                'There are not enough other active members to guarantee this loan.',
                style: TextStyle(color: ChamaColors.danger, fontSize: 11.5),
              )
            else
              for (final member in candidates) ...[
                _GuarantorChoice(
                  member: member,
                  selected: _selected.contains(member.id),
                  enabled:
                      _selected.contains(member.id) ||
                      _selected.length < required,
                  onTap: () {
                    setState(() {
                      if (!_selected.remove(member.id)) {
                        _selected.add(member.id);
                      }
                      _error = null;
                    });
                  },
                ),
                const SizedBox(height: 7),
              ],
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            _ErrorBox(message: _error!),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      width: 21,
                      height: 21,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Submit request'),
            ),
          ),
          const SizedBox(height: 10),
          const Center(
            child: Text(
              'Your request goes to the guarantors and chama admins.',
              textAlign: TextAlign.center,
              style: TextStyle(color: ChamaColors.muted, fontSize: 10.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _GuarantorChoice extends StatelessWidget {
  const _GuarantorChoice({
    required this.member,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final Member member;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: SurfaceCard(
        color: selected ? ChamaColors.soft : ChamaColors.surface,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        onTap: enabled ? onTap : null,
        child: Row(
          children: [
            Avatar(name: member.displayName, size: 34),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                member.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: ChamaColors.ink,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: selected ? ChamaColors.purple : ChamaColors.muted,
              size: 21,
            ),
          ],
        ),
      ),
    );
  }
}

Future<bool?> showWelfareClaimSheet(
  BuildContext context,
  AppController controller,
  Chama group,
) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _WelfareClaimSheet(controller: controller, group: group),
  );
}

class _WelfareClaimSheet extends StatefulWidget {
  const _WelfareClaimSheet({required this.controller, required this.group});

  final AppController controller;
  final Chama group;

  @override
  State<_WelfareClaimSheet> createState() => _WelfareClaimSheetState();
}

class _WelfareClaimSheetState extends State<_WelfareClaimSheet> {
  final _amount = TextEditingController();
  final _reason = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amount = double.tryParse(_amount.text.replaceAll(',', ''));
    final reason = _reason.text.trim();
    if (amount == null || amount < 1) {
      setState(() => _error = 'Enter an amount of at least KES 1.');
      return;
    }
    if (reason.length < 3) {
      setState(() => _error = 'Tell the chama what the claim is for.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.controller.requestWelfareClaim(
        group: widget.group,
        amount: amount.toStringAsFixed(2),
        reason: reason,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
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
            'Request welfare help',
            style: TextStyle(
              color: ChamaColors.ink,
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.group.name,
            style: const TextStyle(color: ChamaColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 20),
          const _FieldLabel('Amount'),
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
              fontSize: 23,
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
          const SizedBox(height: 18),
          const _FieldLabel('Reason'),
          const SizedBox(height: 8),
          TextField(
            controller: _reason,
            maxLength: 300,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'What happened?',
              counterText: '',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            _ErrorBox(message: _error!),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      width: 21,
                      height: 21,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Send request'),
            ),
          ),
          const SizedBox(height: 10),
          const Center(
            child: Text(
              'A chama admin will review your claim.',
              style: TextStyle(color: ChamaColors.muted, fontSize: 10.5),
            ),
          ),
        ],
      ),
    );
  }
}

Future<bool?> showEditProfileSheet(
  BuildContext context,
  AppController controller,
) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _EditProfileSheet(controller: controller),
  );
}

class _EditProfileSheet extends StatefulWidget {
  const _EditProfileSheet({required this.controller});

  final AppController controller;

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  late final _first = TextEditingController(
    text: widget.controller.user?.firstName,
  );
  late final _last = TextEditingController(
    text: widget.controller.user?.lastName,
  );
  late final _email = TextEditingController(
    text: widget.controller.user?.email,
  );
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final first = _first.text.trim();
    final last = _last.text.trim();
    if (first.isEmpty || last.isEmpty) {
      setState(() => _error = 'Enter your first and last name.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.controller.updateProfile(
        firstName: first,
        lastName: last,
        email: _email.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
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
            'Edit profile',
            style: TextStyle(
              color: ChamaColors.ink,
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(height: 18),
          const _FieldLabel('First name'),
          const SizedBox(height: 7),
          TextField(
            controller: _first,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(hintText: 'First name'),
          ),
          const SizedBox(height: 14),
          const _FieldLabel('Last name'),
          const SizedBox(height: 7),
          TextField(
            controller: _last,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(hintText: 'Last name'),
          ),
          const SizedBox(height: 14),
          const _FieldLabel('Email (optional)'),
          const SizedBox(height: 7),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: const InputDecoration(hintText: 'you@example.com'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            _ErrorBox(message: _error!),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(
                      width: 21,
                      height: 21,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Save changes'),
            ),
          ),
        ],
      ),
    );
  }
}

Future<bool?> showChangePinSheet(
  BuildContext context,
  AppController controller,
) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ChangePinSheet(controller: controller),
  );
}

class _ChangePinSheet extends StatefulWidget {
  const _ChangePinSheet({required this.controller});

  final AppController controller;

  @override
  State<_ChangePinSheet> createState() => _ChangePinSheetState();
}

class _ChangePinSheetState extends State<_ChangePinSheet> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_current.text.length < 4 ||
        _next.text.length < 4 ||
        _next.text != _confirm.text) {
      setState(() => _error = 'Enter your current PIN and a matching new PIN.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.controller.changePin(
        currentPin: _current.text,
        newPin: _next.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _pinField(TextEditingController controller, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        obscureText: true,
        keyboardType: TextInputType.number,
        maxLength: 6,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(6),
        ],
        decoration: InputDecoration(labelText: label, counterText: ''),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
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
            'Change PIN',
            style: TextStyle(
              color: ChamaColors.ink,
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'Your PIN protects payments and loan requests.',
            style: TextStyle(color: ChamaColors.muted, fontSize: 11.5),
          ),
          const SizedBox(height: 18),
          _pinField(_current, 'Current PIN'),
          _pinField(_next, 'New PIN'),
          _pinField(_confirm, 'Confirm new PIN'),
          if (_error != null) _ErrorBox(message: _error!),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(
                      width: 21,
                      height: 21,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Update PIN'),
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

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4F3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFBD5D2)),
      ),
      child: Text(
        message,
        style: const TextStyle(color: ChamaColors.danger, fontSize: 11.5),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.last = false,
  });

  final String label;
  final String value;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 102,
            child: Text(
              label,
              style: const TextStyle(color: ChamaColors.muted, fontSize: 11.5),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: ChamaColors.ink,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingList extends StatelessWidget {
  const _LoadingList();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        SkeletonCard(height: 120),
        SizedBox(height: 12),
        SkeletonCard(height: 76),
        SizedBox(height: 8),
        SkeletonCard(height: 76),
      ],
    );
  }
}
