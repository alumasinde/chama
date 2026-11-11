import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/app_state.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../core/widgets.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    widget.controller.loadNotifications();
  }

  Future<void> _markAll() async {
    try {
      await widget.controller.markAllRead();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is ApiException
                ? error.message
                : 'Could not update notifications.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          ListenableBuilder(
            listenable: widget.controller,
            builder: (context, _) => TextButton(
              onPressed: widget.controller.unread > 0 ? _markAll : null,
              child: const Text('Mark all read'),
            ),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final items = widget.controller.notifications;
          if (items.isEmpty && widget.controller.notificationsLoading) {
            return const LoadingList();
          }
          if (items.isEmpty && widget.controller.notificationsError != null) {
            return ErrorState(
              message: widget.controller.notificationsError!,
              onRetry: widget.controller.loadNotifications,
            );
          }
          if (items.isEmpty) {
            return const EmptyState(
              icon: Icons.notifications_none_rounded,
              title: 'You are all caught up.',
            );
          }
          return RefreshIndicator(
            color: ChamaColors.purple,
            onRefresh: widget.controller.loadNotifications,
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = items[index];
                return _NotificationTile(
                  item: item,
                  onTap: () => _showDetail(context, item),
                );
              },
            ),
          );
        },
      ),
    );
  }

  void _showDetail(BuildContext context, AppNotification item) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 4, 22, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 7),
            Text(
              item.body,
              style: const TextStyle(
                color: ChamaColors.muted,
                fontSize: 13.5,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '${relativeTime(item.createdAt)} · ${timeLabel(item.createdAt)}',
              style: const TextStyle(color: ChamaColors.muted, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.item, required this.onTap});

  final AppNotification item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final unread = !item.read;
    return SurfaceCard(
      onTap: onTap,
      color: unread ? ChamaColors.soft : ChamaColors.surface,
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 37,
            height: 37,
            decoration: BoxDecoration(
              color: unread ? ChamaColors.purple : ChamaColors.line,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              switch (item.type) {
                'payment' || 'payment_received' => Icons.payments_outlined,
                'loan' || 'loan_update' => Icons.account_balance_outlined,
                'fine' => Icons.receipt_long_outlined,
                'rotation' => Icons.sync_rounded,
                _ => Icons.notifications_none_rounded,
              },
              color: unread ? Colors.white : ChamaColors.muted,
              size: 18,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: ChamaColors.ink,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (unread)
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: ChamaColors.purple,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  item.body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: ChamaColors.muted,
                    fontSize: 11.5,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  relativeTime(item.createdAt),
                  style: const TextStyle(
                    color: ChamaColors.muted,
                    fontSize: 10,
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
