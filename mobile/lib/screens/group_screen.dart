import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import 'details.dart';
import 'member_features.dart';
import 'sheets.dart';

class GroupScreen extends StatefulWidget {
  const GroupScreen({super.key, required this.controller, required this.group});

  final AppController controller;
  final Chama group;

  @override
  State<GroupScreen> createState() => _GroupScreenState();
}

class _GroupScreenState extends State<GroupScreen> {
  late Future<GroupBundle> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.controller.loadGroupBundle(widget.group.id);
  }

  void _reload() {
    setState(() {
      _future = widget.controller.loadGroupBundle(widget.group.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ChamaColors.canvas,
      appBar: AppBar(
        backgroundColor: ChamaColors.deep,
        foregroundColor: Colors.white,
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 19,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.4,
        ),
        title: Text(
          widget.group.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: FutureBuilder<GroupBundle>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const _GroupLoading();
          }
          if (snapshot.hasError) {
            return ErrorState(
              message: snapshot.error.toString(),
              onRetry: _reload,
            );
          }
          final bundle = snapshot.data!;
          return RefreshIndicator(
            color: ChamaColors.purple,
            onRefresh: () async {
              _reload();
              await _future;
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
              children: [
                _GroupHero(group: widget.group),
                const SizedBox(height: 12),
                _GroupStats(bundle: bundle),
                const SizedBox(height: 18),
                const SectionHeading(title: 'View'),
                const SizedBox(height: 10),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.7,
                  children: [
                    QuickAction(
                      icon: Icons.people_alt_outlined,
                      label: 'Members',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => MembersScreen(
                            controller: widget.controller,
                            group: widget.group,
                            initial: bundle.members,
                          ),
                        ),
                      ),
                    ),
                    QuickAction(
                      icon: Icons.receipt_long_outlined,
                      label: 'Ledger',
                      color: ChamaColors.greenSoft,
                      iconColor: ChamaColors.green,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => LedgerScreen(
                            controller: widget.controller,
                            group: widget.group,
                            initial: bundle.transactions,
                          ),
                        ),
                      ),
                    ),
                    QuickAction(
                      icon: Icons.account_balance_outlined,
                      label: 'Loans',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => LoansScreen(
                            controller: widget.controller,
                            group: widget.group,
                            initial: bundle.loans,
                          ),
                        ),
                      ),
                    ),
                    QuickAction(
                      icon: Icons.favorite_outline_rounded,
                      label: 'Welfare',
                      color: ChamaColors.greenSoft,
                      iconColor: ChamaColors.green,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => WelfareScreen(
                            controller: widget.controller,
                            group: widget.group,
                            initialFund: bundle.welfare,
                            initialClaims: bundle.claims,
                          ),
                        ),
                      ),
                    ),
                    QuickAction(
                      icon: Icons.receipt_long_rounded,
                      label: 'Fines',
                      color: ChamaColors.warningSoft,
                      iconColor: ChamaColors.warning,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => FinesScreen(
                            controller: widget.controller,
                            group: widget.group,
                          ),
                        ),
                      ),
                    ),
                    QuickAction(
                      icon: Icons.sync_rounded,
                      label: 'Rotation',
                      color: ChamaColors.greenSoft,
                      iconColor: ChamaColors.green,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => RotationScreen(
                            controller: widget.controller,
                            group: widget.group,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _ContributionCard(group: widget.group),
                const SizedBox(height: 20),
                SectionHeading(
                  title: 'Recent activity',
                  action: 'See all',
                  onAction: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => LedgerScreen(
                        controller: widget.controller,
                        group: widget.group,
                        initial: bundle.transactions,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SurfaceCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 15,
                    vertical: 6,
                  ),
                  child: bundle.transactions.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 18),
                          child: Center(
                            child: Text(
                              'No activity yet.',
                              style: TextStyle(
                                color: ChamaColors.muted,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        )
                      : Column(
                          children: [
                            for (final entry in bundle.transactions.take(5))
                              TransactionTile(entry: entry),
                          ],
                        ),
                ),
                const SizedBox(height: 18),
                OutlinedButton.icon(
                  onPressed: () => showContributeSheet(
                    context,
                    widget.controller,
                    widget.group,
                  ),
                  icon: const Icon(Icons.add_card_rounded, size: 18),
                  label: const Text('Make a contribution'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _GroupHero extends StatelessWidget {
  const _GroupHero({required this.group});

  final Chama group;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
      decoration: BoxDecoration(
        color: ChamaColors.deep,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StatusPill(status: group.status),
              const Spacer(),
              Text(
                titleCase(group.role),
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            group.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.7,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            memberCount(group.activeMembers),
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupStats extends StatelessWidget {
  const _GroupStats({required this.bundle});

  final GroupBundle bundle;

  @override
  Widget build(BuildContext context) {
    final kpis = bundle.dashboard.kpis;
    return Row(
      children: [
        Expanded(
          child: _Metric(
            label: 'Collected',
            value: money(kpis.collected),
            icon: Icons.trending_up_rounded,
            color: ChamaColors.green,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _Metric(
            label: 'Loans out',
            value: money(kpis.outstandingLoans),
            icon: Icons.account_balance_outlined,
            color: ChamaColors.purple,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _Metric(
            label: 'Fines',
            value: money(kpis.unpaidFines),
            icon: Icons.receipt_long_outlined,
            color: ChamaColors.warning,
          ),
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: ChamaColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ChamaColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(height: 10),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: ChamaColors.muted,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: ChamaColors.ink,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _ContributionCard extends StatelessWidget {
  const _ContributionCard({required this.group});

  final Chama group;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.all(15),
      child: Row(
        children: [
          const Icon(
            Icons.event_repeat_rounded,
            color: ChamaColors.purple,
            size: 22,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${frequencyLabel(group.contributionFrequency)} contribution',
                  style: const TextStyle(
                    color: ChamaColors.ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${money(group.contributionAmount)} · ${dueLabel(group.contributionDay, group.contributionFrequency)}',
                  style: const TextStyle(
                    color: ChamaColors.muted,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupLoading extends StatelessWidget {
  const _GroupLoading();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        SkeletonCard(height: 150),
        SizedBox(height: 12),
        SkeletonCard(height: 85),
        SizedBox(height: 12),
        SkeletonCard(height: 220),
      ],
    );
  }
}
