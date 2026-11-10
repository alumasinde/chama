import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/widgets.dart';

class MarketplaceScreen extends StatelessWidget {
  const MarketplaceScreen({super.key, required this.onOpenChamas});

  final VoidCallback onOpenChamas;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
        children: [
          const Text(
            'Marketplace',
            style: TextStyle(
              color: ChamaColors.ink,
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.7,
            ),
          ),
          const SizedBox(height: 40),
          const EmptyState(
            icon: Icons.storefront_outlined,
            title: 'No listings yet.',
            body: 'Products and services from your chama will appear here.',
          ),
          const SizedBox(height: 20),
          OutlinedButton(
            onPressed: onOpenChamas,
            child: const Text('Go to my chamas'),
          ),
        ],
      ),
    );
  }
}
