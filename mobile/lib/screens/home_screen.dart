import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import 'details.dart';
import 'member_features.dart';
import 'notifications_screen.dart';
import 'receipt_dialog.dart';
import 'sheets.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.controller,
    required this.onOpenChamas,
  });

  final AppController controller;
  final VoidCallback onOpenChamas;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _hideAmounts = false;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final group = widget.controller.active;
        if (group == null) {
          return _NoChama(controller: widget.controller);
        }
        if (group.isPending) {
          return _PendingChama(group: group, onOpenChamas: widget.onOpenChamas);
        }
        if (widget.controller.dashboard == null &&
            widget.controller.homeLoading) {
          return const _HomeLoading();
        }
        return SafeArea(
          bottom: false,
          child: RefreshIndicator(
            color: ChamaColors.purple,
            onRefresh: widget.controller.refreshHome,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 26),
              children: [
                _Header(
                  controller: widget.controller,
                  group: group,
                  onNotifications: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          NotificationsScreen(controller: widget.controller),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                _BalanceCard(
                  dashboard: widget.controller.dashboard,
                  loading: widget.controller.homeLoading,
                  hidden: _hideAmounts,
                  onToggle: () => setState(() => _hideAmounts = !_hideAmounts),
                ),
                const SizedBox(height: 12),
                _PeriodStrip(
                  dashboard: widget.controller.dashboard,
                  group: group,
                ),
                const SizedBox(height: 22),
                const SectionHeading(title: 'Quick actions'),
                const SizedBox(height: 11),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.65,
                  children: [
                    QuickAction(
                      icon: Icons.add_card_rounded,
                      label: 'Contribute',
                      onTap: () => showContributeSheet(
                        context,
                        widget.controller,
                        group,
                      ),
                    ),
                    QuickAction(
                      icon: Icons.receipt_long_rounded,
                      label: 'Pay a fine',
                      color: ChamaColors.greenSoft,
                      iconColor: ChamaColors.green,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => FinesScreen(
                            controller: widget.controller,
                            group: group,
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
                            group: group,
                          ),
                        ),
                      ),
                    ),
                    QuickAction(
                      icon: Icons.people_alt_outlined,
                      label: 'Members',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => MembersScreen(
                            controller: widget.controller,
                            group: group,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 13),
                _NextContributionCard(group: group),
                const SizedBox(height: 24),
                SectionHeading(
                  title: 'Recent activity',
                  action: 'See all',
                  onAction: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => LedgerScreen(
                        controller: widget.controller,
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
                  child: widget.controller.recent.isEmpty
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
                            for (final entry in widget.controller.recent.take(
                              4,
                            ))
                              TransactionTile(
                                entry: entry,
                                onTap: () => showLedgerReceipt(context, entry),
                              ),
                          ],
                        ),
                ),
                if (widget.controller.homeError != null) ...[
                  const SizedBox(height: 12),
                  _InlineError(
                    message: widget.controller.homeError!,
                    onRetry: widget.controller.refreshHome,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HomeLoading extends StatelessWidget {
  const _HomeLoading();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 26),
        children: const [
          Row(
            children: [
              SkeletonBox(height: 45, width: 45, radius: 99),
              SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(height: 16, width: 150),
                    SizedBox(height: 8),
                    SkeletonBox(height: 11, width: 100),
                  ],
                ),
              ),
              SkeletonBox(height: 42, width: 42, radius: 99),
            ],
          ),
          SizedBox(height: 20),
          SkeletonCard(height: 188),
          SizedBox(height: 12),
          SkeletonBox(height: 15, width: 190),
          SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: SkeletonCard(height: 82)),
              SizedBox(width: 10),
              Expanded(child: SkeletonCard(height: 82)),
            ],
          ),
          SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: SkeletonCard(height: 82)),
              SizedBox(width: 10),
              Expanded(child: SkeletonCard(height: 82)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.controller,
    required this.group,
    required this.onNotifications,
  });

  final AppController controller;
  final Chama group;
  final VoidCallback onNotifications;

  @override
  Widget build(BuildContext context) {
    final user = controller.user;
    final label = user == null || user.displayName.isEmpty
        ? 'there'
        : firstName(user.displayName);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Avatar(name: user?.displayName ?? label, size: 45),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Hi, $label',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: ChamaColors.ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 4),
              PopupMenuButton<Chama>(
                tooltip: 'Switch chama',
                enabled: controller.groups.length > 1,
                onSelected: controller.selectGroup,
                itemBuilder: (context) => [
                  for (final item in controller.groups)
                    PopupMenuItem(
                      value: item,
                      child: Row(
                        children: [
                          Expanded(child: Text(item.name)),
                          if (item.id == group.id)
                            const Icon(
                              Icons.check_rounded,
                              size: 18,
                              color: ChamaColors.purple,
                            ),
                        ],
                      ),
                    ),
                ],
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        group.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: ChamaColors.muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (controller.groups.length > 1) ...[
                      const SizedBox(width: 3),
                      const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 17,
                        color: ChamaColors.muted,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        CircleIconButton(
          icon: Icons.notifications_none_rounded,
          onTap: onNotifications,
          badge: controller.unread > 0,
        ),
      ],
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({
    required this.dashboard,
    required this.loading,
    required this.hidden,
    required this.onToggle,
  });

  final GroupDashboard? dashboard;
  final bool loading;
  final bool hidden;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    if (dashboard == null) {
      return const SkeletonCard(height: 188);
    }
    final kpis = dashboard!.kpis;
    return GradientPanel(
      padding: const EdgeInsets.fromLTRB(20, 18, 16, 19),
      child: Stack(
        children: [
          Positioned(
            right: -24,
            bottom: -28,
            child: Icon(
              Icons.savings_outlined,
              size: 132,
              color: Colors.white.withValues(alpha: 0.06),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Chama savings',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: onToggle,
                    visualDensity: VisualDensity.compact,
                    tooltip: hidden ? 'Show balance' : 'Hide balance',
                    icon: Icon(
                      hidden
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: Colors.white70,
                      size: 19,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: Text(
                  hidden ? maskedMoney() : money(kpis.savings),
                  key: ValueKey(hidden),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(height: 13),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.arrow_upward_rounded,
                          color: ChamaColors.green,
                          size: 12,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          '${money(kpis.collected)} this period',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  if (loading)
                    const SizedBox(
                      width: 13,
                      height: 13,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: Colors.white54,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PeriodStrip extends StatelessWidget {
  const _PeriodStrip({required this.dashboard, required this.group});

  final GroupDashboard? dashboard;
  final Chama group;

  @override
  Widget build(BuildContext context) {
    final period = dashboard?.periodLabel;
    return Row(
      children: [
        const Icon(
          Icons.calendar_today_outlined,
          size: 13,
          color: ChamaColors.muted,
        ),
        const SizedBox(width: 5),
        Text(
          period == null || period.isEmpty ? 'Current period' : period,
          style: const TextStyle(
            color: ChamaColors.muted,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        Text(
          memberCount(group.activeMembers),
          style: const TextStyle(
            color: ChamaColors.muted,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _NextContributionCard extends StatelessWidget {
  const _NextContributionCard({required this.group});

  final Chama group;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.all(15),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: ChamaColors.warningSoft,
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(
              Icons.schedule_rounded,
              color: ChamaColors.warning,
              size: 21,
            ),
          ),
          const SizedBox(width: 12),
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
                  '${money(group.contributionAmount)} · due ${dueLabel(group.contributionDay, group.contributionFrequency)}',
                  style: const TextStyle(
                    color: ChamaColors.muted,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            color: ChamaColors.muted,
            size: 20,
          ),
        ],
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4F3),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFBD5D2)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: ChamaColors.danger, fontSize: 12),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _NoChama extends StatelessWidget {
  const _NoChama({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 30),
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: BrandLockup(markSize: 36),
          ),
          const SizedBox(height: 54),
          const Icon(
            Icons.groups_2_outlined,
            color: ChamaColors.purple,
            size: 54,
          ),
          const SizedBox(height: 18),
          const Text(
            'No chama yet.',
            style: TextStyle(
              color: ChamaColors.ink,
              fontSize: 27,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Join with an invite code or start your own.',
            style: TextStyle(
              color: ChamaColors.muted,
              fontSize: 14,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 26),
          FilledButton(
            onPressed: () => showJoinChamaSheet(context, controller),
            child: const Text('Join a chama'),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () => showCreateChamaSheet(context, controller),
            child: const Text('Start a chama'),
          ),
        ],
      ),
    );
  }
}

class _PendingChama extends StatelessWidget {
  const _PendingChama({required this.group, required this.onOpenChamas});

  final Chama group;
  final VoidCallback onOpenChamas;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 30),
        children: [
          Row(
            children: [
              const Expanded(child: BrandLockup(markSize: 34)),
              CircleIconButton(
                icon: Icons.groups_outlined,
                onTap: onOpenChamas,
              ),
            ],
          ),
          const SizedBox(height: 54),
          SurfaceCard(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const StatusPill(status: 'pending'),
                const SizedBox(height: 16),
                Text(
                  group.name,
                  style: const TextStyle(
                    color: ChamaColors.ink,
                    fontSize: 23,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'An admin needs to approve your request.',
                  style: TextStyle(
                    color: ChamaColors.muted,
                    fontSize: 13.5,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: ChamaColors.soft,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Row(
                    children: [
                      const Text(
                        'Invite code',
                        style: TextStyle(
                          color: ChamaColors.muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        group.inviteCode,
                        style: const TextStyle(
                          color: ChamaColors.purple,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          OutlinedButton(
            onPressed: onOpenChamas,
            child: const Text('View my chamas'),
          ),
        ],
      ),
    );
  }
}
