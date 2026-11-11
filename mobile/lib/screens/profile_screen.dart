import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import 'group_screen.dart';
import 'member_features.dart';
import 'notifications_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({
    super.key,
    required this.controller,
    required this.onOpenChamas,
  });

  final AppController controller;
  final VoidCallback onOpenChamas;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final user = controller.user;
        final group = controller.active;
        return SafeArea(
          bottom: false,
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 26),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [ChamaColors.deep, ChamaColors.purple],
                  ),
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(28),
                    bottomRight: Radius.circular(28),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Profile',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        Avatar(
                          name: user?.displayName ?? '?',
                          size: 62,
                          onDark: true,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                user?.displayName ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 19,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                user == null ? '' : maskPhone(user.phoneNumber),
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                              if (group != null) ...[
                                const SizedBox(height: 9),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 9,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    '${group.name} · ${titleCase(group.role)}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
                child: Column(
                  children: [
                    SurfaceCard(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        children: [
                          _ProfileRow(
                            icon: Icons.person_outline_rounded,
                            label: 'Edit profile',
                            detail: user?.email ?? 'Name and email',
                            onTap: () async {
                              final changed = await showEditProfileSheet(
                                context,
                                controller,
                              );
                              if (changed == true && context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Profile updated.'),
                                  ),
                                );
                              }
                            },
                          ),
                          const Divider(height: 1, indent: 55),
                          _ProfileRow(
                            icon: Icons.lock_outline_rounded,
                            label: 'Security',
                            detail: 'Change PIN',
                            onTap: () async {
                              final changed = await showChangePinSheet(
                                context,
                                controller,
                              );
                              if (changed == true && context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('PIN updated.')),
                                );
                              }
                            },
                          ),
                          const Divider(height: 1, indent: 55),
                          _ProfileRow(
                            icon: Icons.fingerprint_rounded,
                            label: 'Fingerprint sign-in',
                            detail: controller.biometricsEnabled
                                ? 'Enabled'
                                : controller.biometricsAvailable
                                ? 'Off'
                                : 'Not available',
                            onTap: () => _toggleBiometrics(context),
                          ),
                          const Divider(height: 1, indent: 55),
                          _ProfileRow(
                            icon: Icons.groups_outlined,
                            label: 'My chamas',
                            detail: controller.groups.length == 1
                                ? '1 chama'
                                : '${controller.groups.length} chamas',
                            onTap: onOpenChamas,
                          ),
                          const Divider(height: 1, indent: 55),
                          _ProfileRow(
                            icon: Icons.notifications_none_rounded,
                            label: 'Notifications',
                            detail: controller.unread > 0
                                ? '${controller.unread} unread'
                                : null,
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    NotificationsScreen(controller: controller),
                              ),
                            ),
                          ),
                          if (group != null && group.isActive) ...[
                            const Divider(height: 1, indent: 55),
                            _ProfileRow(
                              icon: Icons.info_outline_rounded,
                              label: 'Chama details',
                              detail: group.name,
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => GroupScreen(
                                    controller: controller,
                                    group: group,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _confirmLogout(context),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: ChamaColors.danger,
                          side: const BorderSide(color: Color(0xFFFBD5D2)),
                          backgroundColor: const Color(0xFFFFF4F3),
                        ),
                        icon: const Icon(Icons.logout_rounded, size: 18),
                        label: const Text('Sign out'),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Chama · 1.0.0',
                      style: TextStyle(
                        color: ChamaColors.muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'Your saved session will be removed from this phone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: ChamaColors.danger),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await controller.logout();
    }
  }

  Future<void> _toggleBiometrics(BuildContext context) async {
    if (controller.biometricsEnabled) {
      await controller.disableBiometrics();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fingerprint sign-in disabled.')),
      );
      return;
    }
    final enabled = await controller.enableBiometrics();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          enabled
              ? 'Fingerprint sign-in enabled.'
              : 'Fingerprint sign-in is not available or was cancelled.',
        ),
      ),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.detail,
  });

  final IconData icon;
  final String label;
  final String? detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: ChamaColors.purple, size: 21),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: ChamaColors.ink,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (detail != null) ...[
              Flexible(
                child: Text(
                  detail!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: ChamaColors.muted,
                    fontSize: 11,
                  ),
                ),
              ),
              const SizedBox(width: 4),
            ],
            const Icon(
              Icons.chevron_right_rounded,
              color: ChamaColors.muted,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
