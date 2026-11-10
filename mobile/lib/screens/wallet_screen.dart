import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import 'details.dart';
import 'sheets.dart';

class WalletScreen extends StatelessWidget {
  const WalletScreen({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final group = controller.active;
        final dashboard = controller.dashboard;
        if (group == null || !group.isActive) {
          return const SafeArea(
            child: EmptyState(
              icon: Icons.account_balance_wallet_outlined,
              title: 'No chama yet.',
              body: 'Join a chama to see its balances.',
            ),
          );
        }
        return SafeArea(
          bottom: false,
          child: RefreshIndicator(
            color: ChamaColors.purple,
            onRefresh: controller.refreshHome,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Wallet',
                            style: TextStyle(
                              color: ChamaColors.ink,
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.7,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            group.name,
                            style: const TextStyle(
                              color: ChamaColors.muted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    CircleIconButton(
                      icon: Icons.receipt_long_outlined,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => LedgerScreen(
                            controller: controller,
                            group: group,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                if (dashboard == null)
                  const SkeletonCard(height: 160)
                else
                  GradientPanel(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Chama savings',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          money(dashboard.kpis.savings),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 29,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(height: 15),
                        FilledButton.icon(
                          onPressed: () =>
                              showContributeSheet(context, controller, group),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: ChamaColors.deep,
                            minimumSize: const Size(0, 44),
                          ),
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('Contribute'),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 22),
                const SectionHeading(title: 'Chama balances'),
                const SizedBox(height: 10),
                if (dashboard == null)
                  const SkeletonCard(height: 88)
                else
                  Row(
                    children: [
                      Expanded(
                        child: _BalanceTile(
                          label: 'Fines',
                          value: money(dashboard.kpis.unpaidFines),
                          color: ChamaColors.danger,
                          icon: Icons.receipt_long_outlined,
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: _BalanceTile(
                          label: 'Loans',
                          value: money(dashboard.kpis.outstandingLoans),
                          color: ChamaColors.purple,
                          icon: Icons.account_balance_outlined,
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 24),
                SectionHeading(
                  title: 'Recent activity',
                  action: 'See all',
                  onAction: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => LedgerScreen(
                        controller: controller,
                        group: group,
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
                  child: controller.recent.isEmpty
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
                            for (final entry in controller.recent.take(6))
                              TransactionTile(entry: entry),
                          ],
                        ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Contributions go directly to your chama’s M-Pesa shortcode.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: ChamaColors.muted, fontSize: 11),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BalanceTile extends StatelessWidget {
  const _BalanceTile({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  final String label;
  final String value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 19),
          const SizedBox(height: 13),
          Text(
            label,
            style: const TextStyle(
              color: ChamaColors.muted,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 15,
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
