import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/location_provider.dart';

class OrderSuccessScreen extends StatelessWidget {
  const OrderSuccessScreen({super.key, required this.orderNo});
  final String orderNo;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.10),
                      shape: BoxShape.circle,
                    ),
                  )
                      .animate()
                      .scale(duration: 500.ms, curve: Curves.easeOutBack, begin: const Offset(0.3, 0.3))
                      .fadeIn(duration: 300.ms),
                  Container(
                    width: 88,
                    height: 88,
                    decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle),
                    child: const Icon(Icons.check_rounded, color: Colors.white, size: 52),
                  )
                      .animate()
                      .scale(delay: 150.ms, duration: 450.ms, curve: Curves.elasticOut, begin: const Offset(0, 0))
                      .fadeIn(duration: 200.ms),
                ],
              ),
              const SizedBox(height: 24),
              const Text('Order placed!', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 26))
                  .animate()
                  .fadeIn(delay: 350.ms, duration: 400.ms)
                  .slideY(begin: 0.3, curve: Curves.easeOut),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.bgTint,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Order $orderNo',
                  style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ).animate().fadeIn(delay: 450.ms, duration: 400.ms),
              const SizedBox(height: 16),
              Builder(
                builder: (context) {
                  final etaMin = context.watch<LocationProvider>().nearestEtaMin;
                  final etaText = etaMin != null ? 'Arriving in ~$etaMin mins' : 'On its way to you';
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.schedule_rounded, color: AppColors.cta, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        etaText,
                        style: const TextStyle(color: AppColors.ctaDark, fontWeight: FontWeight.w800, fontSize: 14),
                      ),
                    ],
                  );
                },
              ).animate().fadeIn(delay: 550.ms, duration: 400.ms),
              const SizedBox(height: 8),
              const Text(
                'We’ll notify you as it’s packed and on the way.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.inkSoft),
              ).animate().fadeIn(delay: 600.ms, duration: 400.ms),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: () => context.go('/track/$orderNo'),
                child: const Text('Track order'),
              ).animate().fadeIn(delay: 650.ms, duration: 400.ms).slideY(begin: 0.4, curve: Curves.easeOut),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: () => context.go('/'),
                child: const Text('Continue shopping'),
              ).animate().fadeIn(delay: 750.ms, duration: 400.ms).slideY(begin: 0.4, curve: Curves.easeOut),
            ],
          ),
        ),
      ),
    );
  }
}
