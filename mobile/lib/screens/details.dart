import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import 'member_features.dart';
import 'receipt_dialog.dart';

class MembersScreen extends StatefulWidget {
  const MembersScreen({
    super.key,
    required this.controller,
    required this.group,
    this.initial,
  });

  final AppController controller;
  final Chama group;
  final List<Member>? initial;

  @override
  State<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends State<MembersScreen> {
  late Future<List<Member>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.initial == null
        ? widget.controller.api.members(widget.group.id)
        : Future.value(widget.initial);
  }

  Future<void> _reload() async {
    final future = widget.controller.api.members(widget.group.id);
    setState(() => _future = future);
    await future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Members')),
      body: FutureBuilder<List<Member>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LoadingList();
          }
          if (snapshot.hasError) {
            return ErrorState(
              message: snapshot.error.toString(),
              onRetry: _reload,
            );
          }
          final members = snapshot.data ?? const <Member>[];
          if (members.isEmpty) {
            return const EmptyState(
              icon: Icons.people_outline_rounded,
              title: 'No members yet.',
            );
          }
          return RefreshIndicator(
            color: ChamaColors.purple,
            onRefresh: _reload,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              itemCount: members.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final member = members[index];
                return SurfaceCard(
                  padding: const EdgeInsets.all(13),
                  child: Row(
                    children: [
                      Avatar(name: member.displayName, size: 43),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              member.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: ChamaColors.ink,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              titleCase(member.role),
                              style: const TextStyle(
                                color: ChamaColors.muted,
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      StatusPill(status: member.status),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class LedgerScreen extends StatefulWidget {
  const LedgerScreen({
    super.key,
    required this.controller,
    required this.group,
    this.initial,
  });

  final AppController controller;
  final Chama group;
  final List<LedgerEntry>? initial;

  @override
  State<LedgerScreen> createState() => _LedgerScreenState();
}

class _LedgerScreenState extends State<LedgerScreen> {
  late Future<List<LedgerEntry>> _future;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _future = widget.initial == null
        ? widget.controller.api.transactions(widget.group.id)
        : Future.value(widget.initial);
  }

  Future<void> _reload() async {
    final future = widget.controller.api.transactions(widget.group.id);
    setState(() => _future = future);
    await future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ledger')),
      body: FutureBuilder<List<LedgerEntry>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LoadingList();
          }
          if (snapshot.hasError) {
            return ErrorState(
              message: snapshot.error.toString(),
              onRetry: _reload,
            );
          }
          final all = snapshot.data ?? const <LedgerEntry>[];
          final entries = all.where((entry) {
            if (_filter == 'all') return true;
            if (_filter == 'contribution') {
              return entry.type == 'contribution' ||
                  entry.type == 'welfare_contribution';
            }
            if (_filter == 'loans') {
              return entry.type == 'loan_repayment' ||
                  entry.type == 'loan_disbursement';
            }
            return entry.type == 'fine';
          }).toList();
          return RefreshIndicator(
            color: ChamaColors.purple,
            onRefresh: _reload,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _FilterChip(
                        label: 'All',
                        selected: _filter == 'all',
                        onTap: () => setState(() => _filter = 'all'),
                      ),
                      _FilterChip(
                        label: 'Contributions',
                        selected: _filter == 'contribution',
                        onTap: () => setState(() => _filter = 'contribution'),
                      ),
                      _FilterChip(
                        label: 'Loans',
                        selected: _filter == 'loans',
                        onTap: () => setState(() => _filter = 'loans'),
                      ),
                      _FilterChip(
                        label: 'Fines',
                        selected: _filter == 'fine',
                        onTap: () => setState(() => _filter = 'fine'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                if (entries.isEmpty)
                  const EmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: 'No entries yet.',
                  )
                else
                  SurfaceCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 15,
                      vertical: 6,
                    ),
                    child: Column(
                      children: [
                        for (final entry in entries)
                          TransactionTile(
                            entry: entry,
                            onTap: () => _showEntry(context, entry),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showEntry(BuildContext context, LedgerEntry entry) {
    showLedgerReceipt(context, entry);
  }
}

class LoansScreen extends StatefulWidget {
  const LoansScreen({
    super.key,
    required this.controller,
    required this.group,
    this.initial,
  });

  final AppController controller;
  final Chama group;
  final List<Loan>? initial;

  @override
  State<LoansScreen> createState() => _LoansScreenState();
}

class _LoanOverview {
  const _LoanOverview({
    required this.loans,
    required this.settings,
    required this.members,
  });

  final List<Loan> loans;
  final LoanSettings settings;
  final List<Member> members;
}

class _LoansScreenState extends State<LoansScreen> {
  late Future<_LoanOverview> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_LoanOverview> _load() async {
    final results = await Future.wait<Object?>([
      widget.initial == null
          ? widget.controller.api.loans(widget.group.id)
          : Future.value(widget.initial),
      widget.controller.api.loanSettings(widget.group.id),
      widget.controller.api.members(widget.group.id),
    ]);
    return _LoanOverview(
      loans: results[0] as List<Loan>,
      settings: results[1] as LoanSettings,
      members: results[2] as List<Member>,
    );
  }

  Future<void> _reload() async {
    final future = _load();
    setState(() => _future = future);
    await future;
  }

  Future<void> _requestLoan(_LoanOverview data) async {
    final loan = await showLoanRequestSheet(
      context,
      widget.controller,
      widget.group,
      data.settings,
      data.members,
    );
    if (loan == null || !mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Loan request sent.')));
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Loans')),
      body: FutureBuilder<_LoanOverview>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LoadingList();
          }
          if (snapshot.hasError) {
            return ErrorState(
              message: snapshot.error.toString(),
              onRetry: _reload,
            );
          }
          final data = snapshot.data!;
          final loans = data.loans;
          final outstanding = loans.fold<double>(
            0,
            (sum, loan) => sum + (double.tryParse(loan.outstanding) ?? 0),
          );
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
                        'Outstanding',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        money(outstanding.toStringAsFixed(2)),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                if (!data.settings.allowLoans)
                  Container(
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      color: ChamaColors.warningSoft,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.pause_circle_outline_rounded,
                          size: 18,
                          color: ChamaColors.warning,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'This chama is not accepting loan applications.',
                            style: TextStyle(
                              color: ChamaColors.ink,
                              fontSize: 11.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => _requestLoan(data),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Request a loan'),
                    ),
                  ),
                const SizedBox(height: 20),
                SectionHeading(
                  title: widget.group.canManage ? 'All loans' : 'My loans',
                ),
                const SizedBox(height: 8),
                if (loans.isEmpty)
                  const EmptyState(
                    icon: Icons.account_balance_outlined,
                    title: 'No loans yet.',
                  )
                else
                  for (final loan in loans) ...[
                    _LoanCard(
                      loan: loan,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => LoanDetailScreen(
                            controller: widget.controller,
                            group: widget.group,
                            loan: loan,
                          ),
                        ),
                      ),
                    ),
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

class _LoanCard extends StatelessWidget {
  const _LoanCard({required this.loan, required this.onTap});

  final Loan loan;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.all(15),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  money(loan.principal),
                  style: const TextStyle(
                    color: ChamaColors.ink,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              StatusPill(status: loan.status),
              const SizedBox(width: 2),
              const Icon(
                Icons.chevron_right_rounded,
                color: ChamaColors.muted,
                size: 19,
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            '${loan.termMonths} months · ${money(loan.outstanding)} left',
            style: const TextStyle(color: ChamaColors.muted, fontSize: 11.5),
          ),
          const SizedBox(height: 13),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: loan.progress,
              minHeight: 6,
              backgroundColor: ChamaColors.soft,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            '${(loan.progress * 100).round()}% repaid',
            style: const TextStyle(
              color: ChamaColors.muted,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class WelfareScreen extends StatefulWidget {
  const WelfareScreen({
    super.key,
    required this.controller,
    required this.group,
    this.initialFund,
    this.initialClaims,
  });

  final AppController controller;
  final Chama group;
  final WelfareFund? initialFund;
  final List<WelfareClaim>? initialClaims;

  @override
  State<WelfareScreen> createState() => _WelfareScreenState();
}

class _WelfareScreenState extends State<WelfareScreen> {
  late Future<(WelfareFund?, List<WelfareClaim>)> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.initialFund == null
        ? _load()
        : Future.value((widget.initialFund, widget.initialClaims ?? const []));
  }

  Future<(WelfareFund?, List<WelfareClaim>)> _load() async {
    final fund = await widget.controller.api.welfare(widget.group.id);
    final claims = await widget.controller.api.welfareClaims(widget.group.id);
    return (fund, claims);
  }

  Future<void> _reload() async {
    final future = _load();
    setState(() => _future = future);
    await future;
  }

  Future<void> _requestHelp() async {
    final submitted = await showWelfareClaimSheet(
      context,
      widget.controller,
      widget.group,
    );
    if (submitted != true || !mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Welfare claim sent.')));
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Welfare')),
      body: FutureBuilder<(WelfareFund?, List<WelfareClaim>)>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LoadingList();
          }
          if (snapshot.hasError) {
            return ErrorState(
              message: snapshot.error.toString(),
              onRetry: _reload,
            );
          }
          final (fund, claims) = snapshot.data ?? (null, <WelfareClaim>[]);
          return RefreshIndicator(
            color: ChamaColors.purple,
            onRefresh: _reload,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              children: [
                if (fund == null || !fund.configured)
                  const EmptyState(
                    icon: Icons.favorite_outline_rounded,
                    title: 'No welfare fund yet.',
                  )
                else ...[
                  GradientPanel(
                    padding: const EdgeInsets.all(19),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fund.name,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          money(fund.balance),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '${money(fund.monthlyAmount)} monthly',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (fund.isActive)
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _requestHelp,
                        icon: const Icon(
                          Icons.volunteer_activism_outlined,
                          size: 18,
                        ),
                        label: const Text('Request help'),
                      ),
                    ),
                  if (fund.isActive) const SizedBox(height: 20),
                  const SectionHeading(title: 'Claims'),
                  const SizedBox(height: 8),
                  if (claims.isEmpty)
                    const EmptyState(
                      icon: Icons.inbox_outlined,
                      title: 'No claims yet.',
                    )
                  else
                    for (final claim in claims) ...[
                      SurfaceCard(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.volunteer_activism_outlined,
                              color: ChamaColors.purple,
                              size: 21,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    claim.member,
                                    style: const TextStyle(
                                      color: ChamaColors.ink,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    claim.reason,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: ChamaColors.muted,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  money(claim.amount),
                                  style: const TextStyle(
                                    color: ChamaColors.ink,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                StatusPill(status: claim.status),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 7),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        showCheckmark: false,
        labelStyle: TextStyle(
          color: selected ? Colors.white : ChamaColors.muted,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
        selectedColor: ChamaColors.purple,
        backgroundColor: ChamaColors.surface,
        side: BorderSide(
          color: selected ? ChamaColors.purple : ChamaColors.line,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
    );
  }
}
