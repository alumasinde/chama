import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'format.dart';
import 'theme.dart';

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 36});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _BrandMarkPainter()),
    );
  }
}

class _BrandMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final swoosh = Paint()..color = ChamaColors.green;
    final path = Path()
      ..moveTo(w * 0.08, h * 0.78)
      ..quadraticBezierTo(w * 0.27, h * 0.61, w * 0.48, h * 0.78)
      ..quadraticBezierTo(w * 0.68, h * 0.94, w * 0.92, h * 0.73)
      ..lineTo(w * 0.92, h * 0.9)
      ..quadraticBezierTo(w * 0.68, h * 1.04, w * 0.48, h * 0.9)
      ..quadraticBezierTo(w * 0.27, h * 0.75, w * 0.08, h * 0.91)
      ..close();
    canvas.drawPath(path, swoosh);

    final purple = Paint()..color = ChamaColors.purple;
    final light = Paint()..color = const Color(0xFF9B7BE0);
    final green = Paint()..color = ChamaColors.green;
    _person(canvas, Rect.fromLTWH(w * 0.1, h * 0.25, w * 0.2, h * 0.57), purple);
    _person(canvas, Rect.fromLTWH(w * 0.4, h * 0.08, w * 0.2, h * 0.7), light);
    _person(canvas, Rect.fromLTWH(w * 0.7, h * 0.28, w * 0.2, h * 0.55), green);
  }

  void _person(Canvas canvas, Rect rect, Paint paint) {
    final head = Paint()..color = paint.color;
    canvas.drawCircle(
      Offset(rect.center.dx, rect.top + rect.width * 0.28),
      rect.width * 0.28,
      head,
    );
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        rect.left,
        rect.top + rect.width * 0.62,
        rect.width,
        rect.height - rect.width * 0.44,
      ),
      Radius.circular(rect.width * 0.5),
    );
    canvas.drawRRect(body, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class BrandLockup extends StatelessWidget {
  const BrandLockup({
    super.key,
    this.onDark = false,
    this.markSize = 36,
    this.showTagline = true,
  });

  final bool onDark;
  final double markSize;
  final bool showTagline;

  @override
  Widget build(BuildContext context) {
    final color = onDark ? Colors.white : ChamaColors.ink;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        BrandMark(size: markSize),
        const SizedBox(width: 9),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Chama',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: markSize * 0.45,
                letterSpacing: -0.6,
                height: 1,
              ),
            ),
            if (showTagline) ...[
              const SizedBox(height: 3),
              Text(
                'Together · Save · Grow',
                style: TextStyle(
                  color: onDark ? Colors.white60 : ChamaColors.muted,
                  fontWeight: FontWeight.w600,
                  fontSize: markSize * 0.2,
                  letterSpacing: 0.2,
                  height: 1,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.color = ChamaColors.surface,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: ChamaColors.line),
      ),
      child: child,
    );
    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: content,
      ),
    );
  }
}

class GradientPanel extends StatelessWidget {
  const GradientPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(22),
    this.radius = 24,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [ChamaColors.deep, ChamaColors.purple],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x332E0A5E),
            blurRadius: 28,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: child,
    );
  }
}

class Avatar extends StatelessWidget {
  const Avatar({
    super.key,
    required this.name,
    this.size = 42,
    this.onDark = false,
  });

  final String name;
  final double size;
  final bool onDark;

  static const _colors = [
    Color(0xFF5B2BB5),
    Color(0xFF16A34A),
    Color(0xFFB06A15),
    Color(0xFF3478B5),
    Color(0xFF9B3E69),
  ];

  @override
  Widget build(BuildContext context) {
    final idx = name.codeUnits.fold<int>(0, (a, b) => a + b) % _colors.length;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: onDark ? Colors.white.withValues(alpha: 0.16) : _colors[idx],
        shape: BoxShape.circle,
        border: Border.all(
          color: onDark ? Colors.white.withValues(alpha: 0.25) : Colors.white,
          width: 2,
        ),
      ),
      child: Text(
        initials(name),
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.31,
          letterSpacing: 0.1,
        ),
      ),
    );
  }
}

class AvatarStack extends StatelessWidget {
  const AvatarStack({super.key, required this.names, this.size = 28});

  final List<String> names;
  final double size;

  @override
  Widget build(BuildContext context) {
    final visible = names.take(4).toList();
    return SizedBox(
      height: size,
      width: names.isEmpty ? 0 : size + (visible.length - 1) * size * 0.64,
      child: Stack(
        children: [
          for (var i = 0; i < visible.length; i++)
            Positioned(
              left: i * size * 0.64,
              child: Avatar(name: visible[i], size: size),
            ),
        ],
      ),
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (status) {
      'active' || 'approved' || 'completed' || 'paid' || 'fully_paid' =>
        (ChamaColors.greenSoft, ChamaColors.green),
      'pending' || 'pending_guarantors' || 'pending_approval' =>
        (ChamaColors.warningSoft, ChamaColors.warning),
      'defaulted' || 'rejected' || 'failed' || 'suspended' =>
        (const Color(0xFFFEE4E2), ChamaColors.danger),
      _ => (ChamaColors.soft, ChamaColors.purple),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        titleCase(status),
        style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class SectionHeading extends StatelessWidget {
  const SectionHeading({
    super.key,
    required this.title,
    this.action,
    this.onAction,
  });

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: ChamaColors.ink,
              fontSize: 17,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
        ),
        if (action != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: 4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(action!),
                const SizedBox(width: 2),
                const Icon(Icons.arrow_forward_rounded, size: 16),
              ],
            ),
          ),
      ],
    );
  }
}

class QuickAction extends StatelessWidget {
  const QuickAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = ChamaColors.soft,
    this.iconColor = ChamaColors.purple,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(18),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 35,
                height: 35,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, size: 19, color: iconColor),
              ),
              const SizedBox(height: 12),
              Text(
                label,
                maxLines: 2,
                style: const TextStyle(
                  color: ChamaColors.ink,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  height: 1.15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.body,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 62,
              height: 62,
              decoration: const BoxDecoration(
                color: ChamaColors.soft,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: ChamaColors.purple, size: 28),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: ChamaColors.ink,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (body != null) ...[
              const SizedBox(height: 6),
              Text(
                body!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: ChamaColors.muted,
                  fontSize: 13.5,
                  height: 1.45,
                ),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 20),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.cloud_off_rounded,
      title: 'Could not load this screen',
      body: message,
      action: FilledButton(
        onPressed: onRetry,
        style: FilledButton.styleFrom(backgroundColor: ChamaColors.purple),
        child: const Text('Try again'),
      ),
    );
  }
}

class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    required this.height,
    this.width,
    this.radius = 12,
  });

  final double height;
  final double? width;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: ChamaColors.line.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key, this.height = 160});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: ChamaColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: ChamaColors.line),
      ),
      padding: const EdgeInsets.all(18),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(height: 12, width: 90),
          SizedBox(height: 12),
          SkeletonBox(height: 28, width: 190),
          Spacer(),
          SkeletonBox(height: 12, width: 130),
        ],
      ),
    );
  }
}

class TransactionTile extends StatelessWidget {
  const TransactionTile({super.key, required this.entry, this.onTap});

  final dynamic entry;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isIn = isInflow(entry.type as String);
    final color = isIn ? ChamaColors.green : ChamaColors.ink;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isIn ? ChamaColors.greenSoft : ChamaColors.soft,
                shape: BoxShape.circle,
              ),
              child: Icon(
                isIn ? Icons.south_west_rounded : Icons.north_east_rounded,
                color: isIn ? ChamaColors.green : ChamaColors.purple,
                size: 19,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    transactionTitle(entry.type as String),
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
                    entry.member as String? ?? '',
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
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  transactionSignedAmount(entry.type as String, entry.amount as String),
                  style: TextStyle(
                    color: color,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  relativeTime(entry.createdAt as String),
                  style: const TextStyle(
                    color: ChamaColors.muted,
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class CircleIconButton extends StatelessWidget {
  const CircleIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.color = ChamaColors.surface,
    this.iconColor = ChamaColors.ink,
    this.size = 42,
    this.badge = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color color;
  final Color iconColor;
  final double size;
  final bool badge;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          color: color,
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: size,
              height: size,
              child: Icon(icon, color: iconColor, size: 21),
            ),
          ),
        ),
        if (badge)
          Positioned(
            top: 1,
            right: 1,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: ChamaColors.danger,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
            ),
          ),
      ],
    );
  }
}

class Stagger extends StatefulWidget {
  const Stagger({super.key, required this.child, this.duration = const Duration(milliseconds: 420)});

  final Widget child;
  final Duration duration;

  @override
  State<Stagger> createState() => _StaggerState();
}

class _StaggerState extends State<Stagger> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  )..forward();
  late final Animation<double> _opacity = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOut,
  );
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, 0.035),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

class HeaderWave extends StatelessWidget {
  const HeaderWave({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _WavePainter(),
      child: const SizedBox(height: 26, width: double.infinity),
    );
  }
}

class _WavePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = ChamaColors.canvas;
    final path = Path()
      ..moveTo(0, size.height)
      ..quadraticBezierTo(
        size.width * 0.25,
        size.height * 0.25,
        size.width * 0.5,
        size.height * 0.65,
      )
      ..quadraticBezierTo(
        size.width * 0.75,
        size.height * 1.05,
        size.width,
        size.height * 0.35,
      )
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class Sparkline extends StatelessWidget {
  const Sparkline({super.key, required this.values});

  final List<double> values;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _SparkPainter(values),
      child: const SizedBox(height: 36, width: 88),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.values);

  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final maxValue = values.reduce(math.max);
    final minValue = values.reduce(math.min);
    final spread = math.max(maxValue - minValue, 1);
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = size.width * i / (values.length - 1);
      final y = size.height -
          ((values[i] - minValue) / spread) * (size.height - 5) -
          2.5;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.8)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _SparkPainter oldDelegate) => false;
}
