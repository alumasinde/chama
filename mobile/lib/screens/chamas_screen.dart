import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import 'group_screen.dart';
import 'sheets.dart';

class ChamasScreen extends StatelessWidget {
  const ChamasScreen({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final groups = controller.groups;
        return SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Chamas',
                      style: TextStyle(
                        color: ChamaColors.ink,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.7,
                      ),
                    ),
                  ),
                  CircleIconButton(
                    icon: Icons.add_rounded,
                    onTap: () => showCreateChamaSheet(context, controller),
                  ),
                  const SizedBox(width: 8),
                  CircleIconButton(
                    icon: Icons.link_rounded,
                    onTap: () => showJoinChamaSheet(context, controller),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (groups.isEmpty)
                _EmptyChamas(controller: controller)
              else ...[
                for (final group in groups) ...[
                  _ChamaTile(
                    group: group,
                    selected: controller.active?.id == group.id,
                    onTap: () {
                      if (group.isPending) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'This chama is waiting for approval.',
                            ),
                          ),
                        );
                        return;
                      }
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              GroupScreen(controller: controller, group: group),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                ],
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => showJoinChamaSheet(context, controller),
                  child: const Text('Join another chama'),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ChamaTile extends StatelessWidget {
  const _ChamaTile({
    required this.group,
    required this.selected,
    required this.onTap,
  });

  final Chama group;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      onTap: onTap,
      padding: const EdgeInsets.all(15),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? ChamaColors.soft : ChamaColors.greenSoft,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              initials(group.name),
              style: TextStyle(
                color: selected ? ChamaColors.purple : ChamaColors.green,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        group.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: ChamaColors.ink,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (selected)
                      const Icon(
                        Icons.check_circle_rounded,
                        size: 15,
                        color: ChamaColors.purple,
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${memberCount(group.activeMembers)} · ${compactMoney(group.contributionAmount)} ${frequencyUnit(group.contributionFrequency)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: ChamaColors.muted,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              StatusPill(status: group.status),
              const SizedBox(height: 7),
              Text(
                titleCase(group.role),
                style: const TextStyle(
                  color: ChamaColors.muted,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(width: 4),
          const Icon(
            Icons.chevron_right_rounded,
            color: ChamaColors.muted,
            size: 19,
          ),
        ],
      ),
    );
  }
}

class _EmptyChamas extends StatelessWidget {
  const _EmptyChamas({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(18, 30, 18, 22),
      child: Column(
        children: [
          const Icon(
            Icons.groups_2_outlined,
            color: ChamaColors.purple,
            size: 47,
          ),
          const SizedBox(height: 14),
          const Text(
            'No chamas yet.',
            style: TextStyle(
              color: ChamaColors.ink,
              fontSize: 19,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'Join one or start your own.',
            textAlign: TextAlign.center,
            style: TextStyle(color: ChamaColors.muted, fontSize: 13),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => showJoinChamaSheet(context, controller),
            child: const Text('Join a chama'),
          ),
          const SizedBox(height: 9),
          OutlinedButton(
            onPressed: () => showCreateChamaSheet(context, controller),
            child: const Text('Start a chama'),
          ),
        ],
      ),
    );
  }
}
