import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Coloured pill for order / sub-order / delivery statuses with a leading icon.
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status});
  final String status;

  static const _green = {'delivered', 'completed', 'paid'};
  static const _amber = {'confirmed', 'accepted', 'packed', 'ready', 'created', 'pending', 'partially_fulfilled'};
  static const _blue = {'out_for_delivery', 'picked_up', 'assigned', 'offered'};
  static const _red = {'cancelled', 'failed'};

  Color get _color {
    final s = status.toLowerCase();
    if (_green.contains(s)) return AppColors.success;
    if (_blue.contains(s)) return AppColors.info;
    if (_amber.contains(s)) return const Color(0xFFB54708);
    if (_red.contains(s)) return AppColors.danger;
    return AppColors.inkSoft;
  }

  IconData get _icon {
    final s = status.toLowerCase();
    if (_green.contains(s)) return Icons.check_circle_rounded;
    if (_blue.contains(s)) return Icons.local_shipping_rounded;
    if (_amber.contains(s)) return Icons.schedule_rounded;
    if (_red.contains(s)) return Icons.cancel_rounded;
    return Icons.info_outline_rounded;
  }

  String get _label => status.replaceAll('_', ' ').split(' ').map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');

  @override
  Widget build(BuildContext context) {
    final c = _color;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_icon, color: c, size: 13),
          const SizedBox(width: 4),
          Text(_label, style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: 11)),
        ],
      ),
    );
  }
}
