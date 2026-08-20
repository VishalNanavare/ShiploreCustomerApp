import 'package:flutter/material.dart';

import '../core/network/api_exception.dart';
import '../core/theme/app_theme.dart';

/// Centered loading spinner.
class LoadingView extends StatelessWidget {
  const LoadingView({super.key});
  @override
  Widget build(BuildContext context) =>
      const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()));
}

/// Friendly error with a retry button. Understands [ApiException].
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, this.onRetry});
  final Object error;
  final VoidCallback? onRetry;

  bool get _isNetwork => error is ApiException && (error as ApiException).isNetwork;

  String get _message {
    final e = error;
    if (e is ApiException) {
      if (e.isNetwork) return 'No internet connection.\nCheck your network and try again.';
      return e.message;
    }
    return 'Something went wrong. Please try again.';
  }

  IconData get _icon => _isNetwork ? Icons.wifi_off_rounded : Icons.cloud_off_rounded;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_icon, size: 44, color: AppColors.inkSoft),
            const SizedBox(height: 12),
            Text(_message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.inkSoft)),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ],
        ),
      ),
    );
  }
}

/// Well-known empty-state contexts — each gets a distinct colored illustration.
enum EmptyType { cart, orders, notifications, wishlist, search, products }

/// Empty placeholder (no results / empty cart).
class EmptyView extends StatelessWidget {
  const EmptyView({super.key, required this.title, this.subtitle, this.icon = Icons.inbox_outlined, this.action, this.type});
  final String title;
  final String? subtitle;
  final IconData icon;
  final Widget? action;
  final EmptyType? type;

  Widget _visual() {
    if (type == null) return Icon(icon, size: 52, color: AppColors.inkSoft);
    final (ic, bg, fg) = switch (type!) {
      EmptyType.cart         => (Icons.shopping_cart_outlined,        AppColors.ctaTint, AppColors.cta),
      EmptyType.orders       => (Icons.receipt_long_outlined,         const Color(0xFFE0F7FA), AppColors.teal),
      EmptyType.notifications=> (Icons.notifications_none_rounded,    const Color(0xFFF3E5F5), const Color(0xFF8B5CF6)),
      EmptyType.wishlist     => (Icons.favorite_border_rounded,       const Color(0xFFFCE4EC), const Color(0xFFEC4899)),
      EmptyType.search       => (Icons.search_off_rounded,            const Color(0xFFECEFF1), AppColors.inkSoft),
      EmptyType.products     => (Icons.inventory_2_outlined,          const Color(0xFFE8F5E9), AppColors.success),
    };
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Icon(ic, size: 44, color: fg),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _visual(),
            const SizedBox(height: 14),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16), textAlign: TextAlign.center),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(subtitle!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.inkSoft)),
            ],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

void showSnack(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? AppColors.danger : AppColors.ink,
      behavior: SnackBarBehavior.floating,
    ));
}
