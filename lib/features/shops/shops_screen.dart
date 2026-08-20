import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/catalog.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../providers/location_provider.dart';
import '../../widgets/app_scale_tap.dart';
import '../../widgets/network_image.dart';
import '../../widgets/skeletons.dart';
import '../../widgets/states.dart';

/// Browse page listing nearby shops/stores for the current delivery location.
class ShopsScreen extends StatefulWidget {
  const ShopsScreen({super.key});

  @override
  State<ShopsScreen> createState() => _ShopsScreenState();
}

class _ShopsScreenState extends State<ShopsScreen> {
  Future<List<Shop>>? _future;
  DeliveryLocation? _lastLoadedLocation;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final loc = context.read<LocationProvider>().location;
    if (_future == null ||
        loc?.lat != _lastLoadedLocation?.lat ||
        loc?.lng != _lastLoadedLocation?.lng) {
      _lastLoadedLocation = loc;
      _future = _load();
    }
  }

  Future<List<Shop>> _load() {
    final loc = context.read<LocationProvider>().location;
    return context.read<CatalogRepository>().shops(lat: loc?.lat, lng: loc?.lng);
  }

  Future<void> _refresh() async {
    _lastLoadedLocation = context.read<LocationProvider>().location;
    final f = _load();
    setState(() => _future = f);
    await f;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stores near you'),
        automaticallyImplyLeading: false,
        leading: BackButton(onPressed: () => context.canPop() ? context.pop() : context.go('/')),
      ),
      body: FutureBuilder<List<Shop>>(
        future: _future,
        builder: (context, snap) {
          if (_future == null || snap.connectionState == ConnectionState.waiting) {
            return const _ShopListSkeleton();
          }
          if (snap.hasError) return ErrorView(error: snap.error!, onRetry: _refresh);
          final shops = snap.data ?? const <Shop>[];
          if (shops.isEmpty) {
            return const EmptyView(
              title: 'No stores near you',
              icon: Icons.storefront_outlined,
            );
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              itemCount: shops.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                return _ShopCard(shop: shops[i])
                    .animate()
                    .fadeIn(duration: 280.ms, delay: (40 * i).ms)
                    .slideY(begin: 0.08, end: 0, curve: Curves.easeOut);
              },
            ),
          );
        },
      ),
    );
  }
}

class _ShopCard extends StatelessWidget {
  const _ShopCard({required this.shop});
  final Shop shop;

  String get _meta {
    final parts = <String>[];
    final eta = shop.etaMin;
    final km = shop.distanceKm;
    if (eta != null) parts.add('⏱ $eta min');
    if (km != null) parts.add('${km.toStringAsFixed(1)} km');
    if (parts.isEmpty) {
      final type = (shop.businessType ?? '').trim();
      return type.isEmpty ? 'Store' : type;
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final type = (shop.businessType ?? '').trim();
    return ScaleTap(
      onTap: () => context.push('/shop/${shop.id}?name=${Uri.encodeComponent(shop.name)}'),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: AppShadows.card,
        ),
        child: Row(
          children: [
            _Logo(url: shop.imageUrl),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    shop.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: AppColors.ink,
                    ),
                  ),
                  if (type.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      type,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    _meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.cta,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded, color: AppColors.inkSoft),
          ],
        ),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: AppColors.bgTint,
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.center,
        child: const Icon(Icons.storefront_rounded, color: AppColors.primary, size: 26),
      );
    }
    return AppImage(url: url, size: 56, radius: 14);
  }
}

class _ShopListSkeleton extends StatelessWidget {
  const _ShopListSkeleton();

  @override
  Widget build(BuildContext context) {
    return Shimmery(
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 7,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, _) => Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Row(
            children: [
              SkeletonBox(width: 56, height: 56, radius: 14),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(width: 140, height: 13),
                    SizedBox(height: 8),
                    SkeletonBox(width: 90, height: 11),
                    SizedBox(height: 8),
                    SkeletonBox(width: 110, height: 11),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
