import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/banner.dart';
import '../../data/models/catalog.dart';
import '../../data/models/product.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../data/repositories/customer_repository.dart';
import '../../providers/auth_provider.dart';
import '../../providers/location_provider.dart';
import '../../providers/notification_provider.dart';
import '../location/location_sheet.dart';
import '../../widgets/app_scale_tap.dart';
import '../../widgets/network_image.dart';
import '../../widgets/product_card.dart';
import '../../widgets/skeletons.dart';
import '../../widgets/states.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Future<HomeData>? _future;
  DeliveryLocation? _lastLoadedLocation;
  int? _nearestEta;
  double? _nearestKm;
  bool _emailBannerDismissed = false;

  @override
  void initState() {
    super.initState();
    // Auto-detect the delivery location on first launch (no full-screen map gate).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeAutoDetect();
      _syncProfile();
      if (mounted) context.read<NotificationProvider>().refresh();
    });
  }

  /// Silently refresh the stored user from the server so has_email / name stay
  /// accurate without requiring a re-login. Errors are intentionally swallowed.
  Future<void> _syncProfile() async {
    final auth = context.read<AuthProvider>();
    if (!auth.isLoggedIn) return;
    try {
      final user = await context.read<CustomerRepository>().getProfile();
      if (mounted) await auth.updateUser(user);
    } catch (_) {}
  }

  /// On first launch (no saved location) silently acquire the device location so
  /// Home can show nearby shops. If permission is denied or services are off,
  /// Home just keeps the full (global) catalog + the "set location" bar.
  Future<void> _maybeAutoDetect() async {
    final lp = context.read<LocationProvider>();
    if (lp.hasLocation) return;
    try {
      final loc = await lp.detectCurrent();
      await lp.set(loc); // notifies → didChangeDependencies → scoped reload
    } catch (_) {
      // denied / disabled — global catalog stays; user can tap "set location"
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final loc = context.read<LocationProvider>().location;
    // Always load: global catalog when there's no location yet, scoped once set.
    if (_future == null ||
        loc?.lat != _lastLoadedLocation?.lat ||
        loc?.lng != _lastLoadedLocation?.lng) {
      _lastLoadedLocation = loc;
      _future = _load();
    }
  }

  Future<HomeData> _load() {
    final loc = context.read<LocationProvider>().location;
    final f = context.read<CatalogRepository>().home(lat: loc?.lat, lng: loc?.lng);
    f.then((d) {
      if (!mounted) return;
      int? eta;
      double? km;
      for (final s in d.shops.cast<Shop>()) {
        final e = s.etaMin;
        if (e != null && (eta == null || e < eta)) eta = e;
        final dk = s.distanceKm;
        if (dk != null && (km == null || dk < km)) km = dk;
      }
      context.read<LocationProvider>().setNearestEta(eta);
      setState(() {
        _nearestEta = eta;
        _nearestKm = km;
      });
    }).catchError((_) {});
    return f;
  }

  Future<void> _refresh() async {
    _lastLoadedLocation = context.read<LocationProvider>().location;
    final f = _load();
    setState(() {
      _future = f;
    });
    await f;
  }

  // Optimistically clear the bell badge (the screen marks items read), then
  // re-sync the unread count when the user returns.
  Future<void> _openNotifications() async {
    final notifications = context.read<NotificationProvider>();
    notifications.clear();
    await context.push('/notifications');
    if (mounted) notifications.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocationProvider>().location;
    return Scaffold(
      body: Column(
        children: [
          _HomeHeader(
            location: loc,
            etaMin: _nearestEta,
            distanceKm: _nearestKm,
            onLocationTap: () => showLocationSheet(context),
            onSearchTap: () => context.push('/search'),
            onProfileTap: () => context.go('/account'),
            onNotificationsTap: _openNotifications,
          ),
          if (loc == null) const _LocationBanner(),
          if (!_emailBannerDismissed) _EmailPromptBanner(
            auth: context.watch<AuthProvider>(),
            onDismiss: () => setState(() => _emailBannerDismissed = true),
          ),
          Expanded(
            child: FutureBuilder<HomeData>(
              future: _future,
              builder: (context, snap) {
                if (_future == null) return const SizedBox.shrink();
                if (snap.connectionState == ConnectionState.waiting) return const HomeSkeleton();
                if (snap.hasError) return ErrorView(error: snap.error!, onRetry: _refresh);
                final data = snap.data!;
                if (data.isScoped && data.shops.isEmpty) {
                  return _NoShopsView(onChangeLocation: () => context.push('/location'));
                }
                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: CustomScrollView(
                    slivers: [
                      if (data.categories.isNotEmpty)
                        SliverToBoxAdapter(child: _CategoryQuickTabs(items: data.categories)),
                      if (data.banners.isNotEmpty)
                        SliverToBoxAdapter(child: _BannerCarousel(banners: data.banners)),
                      if (data.categories.isNotEmpty) ...[
                        SliverToBoxAdapter(child: _SectionHeader(title: 'Shop by category', onSeeAll: () => context.go('/categories'))),
                        SliverToBoxAdapter(child: _Categories(items: data.categories)),
                      ],
                      if (data.shops.isNotEmpty) ...[
                        SliverToBoxAdapter(child: _SectionHeader(title: 'Stores near you', onSeeAll: () => context.push('/shops'))),
                        SliverToBoxAdapter(child: _Shops(items: data.shops.cast<Shop>())),
                      ],
                      const SliverToBoxAdapter(child: _SectionHeader(title: 'Bestsellers')),
                      _ProductGrid(items: data.products, isScoped: data.isScoped),
                      const SliverToBoxAdapter(child: SizedBox(height: 28)),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// White header: amber ETA pill + location line + search bar.
class _HomeHeader extends StatelessWidget {
  const _HomeHeader({
    required this.location,
    required this.etaMin,
    required this.distanceKm,
    required this.onLocationTap,
    required this.onSearchTap,
    required this.onProfileTap,
    required this.onNotificationsTap,
  });
  final DeliveryLocation? location;
  final int? etaMin;
  final double? distanceKm;
  final VoidCallback onLocationTap;
  final VoidCallback onSearchTap;
  final VoidCallback onProfileTap;
  final VoidCallback onNotificationsTap;

  @override
  Widget build(BuildContext context) {
    final line = location?.formatted?.isNotEmpty == true
        ? location!.formatted!
        : (location?.city ?? location?.shortLabel ?? 'Set your delivery location');
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Material(
        color: AppColors.surface,
        elevation: 0,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: onLocationTap,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            color: AppColors.ctaTint,
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.bolt_rounded, color: AppColors.cta, size: 16),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  etaMin != null ? 'Deliver in $etaMin mins' : 'Delivery in minutes',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: AppColors.cta, fontWeight: FontWeight.w800, fontSize: 13.5),
                                ),
                              ),
                              const SizedBox(width: 2),
                              const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.cta, size: 18),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _HeaderIconButton(
                      icon: Icons.notifications_outlined,
                      onTap: onNotificationsTap,
                      badgeCount: context.watch<NotificationProvider>().unread,
                    ),
                    const SizedBox(width: 4),
                    _HeaderIconButton(icon: Icons.person_outline_rounded, onTap: onProfileTap),
                  ],
                ),
                const SizedBox(height: 7),
                GestureDetector(
                  onTap: onLocationTap,
                  child: Row(
                    children: [
                      const Icon(Icons.location_on_rounded, color: AppColors.primary, size: 14),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          line,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.inkSoft, fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                ScaleTap(
                  onTap: onSearchTap,
                  child: Container(
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: AppColors.bg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.line),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.search_rounded, color: AppColors.inkSoft, size: 20),
                        SizedBox(width: 10),
                        Expanded(child: Text('Search groceries, medicines & more', style: TextStyle(color: AppColors.inkSoft, fontSize: 14))),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({required this.icon, required this.onTap, this.badgeCount = 0});
  final IconData icon;
  final VoidCallback onTap;
  final int badgeCount;
  @override
  Widget build(BuildContext context) {
    return ScaleTap(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: AppColors.bg, shape: BoxShape.circle),
            child: Icon(icon, color: AppColors.ink, size: 20),
          ),
          if (badgeCount > 0)
            Positioned(
              top: -2,
              right: -2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                constraints: const BoxConstraints(minWidth: 16),
                height: 16,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.cta,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.surface, width: 1.5),
                ),
                child: Text(
                  badgeCount > 99 ? '99+' : '$badgeCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Horizontal quick-access category chips (All / first categories).
class _CategoryQuickTabs extends StatelessWidget {
  const _CategoryQuickTabs({required this.items});
  final List<Category> items;
  @override
  Widget build(BuildContext context) {
    final tabs = items.take(8).toList();
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        itemCount: tabs.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          if (i == 0) return const _QuickChip(label: 'All', selected: true);
          final c = tabs[i - 1];
          return _QuickChip(
            label: c.name,
            onTap: () => context.push('/search?category=${Uri.encodeComponent(c.slug)}'),
          );
        },
      ),
    );
  }
}

class _QuickChip extends StatelessWidget {
  const _QuickChip({required this.label, this.selected = false, this.onTap});
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    return ScaleTap(
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? AppColors.primary : AppColors.line),
        ),
        child: Text(
          label,
          maxLines: 1,
          style: TextStyle(
            color: selected ? Colors.white : AppColors.ink,
            fontWeight: FontWeight.w700,
            fontSize: 12.5,
          ),
        ),
      ),
    );
  }
}

/// Auto-rotating home banners sourced from the backend (max 6).
/// - Empty list: caller hides this widget entirely via the `if` guard in the ListView.
/// - Single banner: shows without dot indicator and no auto-rotate.
/// - Real image via [AppImage] with a gradient text overlay on the bottom half.
/// - No image: falls back to a brand gradient tile with title text.
/// - Tap: routes to [HomeBanner.targetUrl] when set; ignores tap otherwise.
class _BannerCarousel extends StatefulWidget {
  const _BannerCarousel({required this.banners});
  final List<HomeBanner> banners;
  @override
  State<_BannerCarousel> createState() => _BannerCarouselState();
}

class _BannerCarouselState extends State<_BannerCarousel> {
  // Fallback gradients cycle when a banner has no image.
  static const _fallbacks = [
    AppGradients.cta,
    AppGradients.brand,
    LinearGradient(colors: [AppColors.teal, Color(0xFF0E7C8B)], begin: Alignment.topLeft, end: Alignment.bottomRight),
    LinearGradient(colors: [Color(0xFF8B5CF6), Color(0xFF6D28D9)], begin: Alignment.topLeft, end: Alignment.bottomRight),
    LinearGradient(colors: [Color(0xFFEC4899), Color(0xFFBE185D)], begin: Alignment.topLeft, end: Alignment.bottomRight),
    LinearGradient(colors: [Color(0xFF059669), Color(0xFF065F46)], begin: Alignment.topLeft, end: Alignment.bottomRight),
  ];

  late final PageController _ctrl;
  int _page = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _ctrl = PageController(viewportFraction: 0.92);
    if (widget.banners.length > 1) {
      _timer = Timer.periodic(const Duration(seconds: 4), (_) {
        if (!_ctrl.hasClients) return;
        _page = (_page + 1) % widget.banners.length;
        _ctrl.animateToPage(_page, duration: const Duration(milliseconds: 450), curve: Curves.easeInOut);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.banners.length;
    return Column(
      children: [
        const SizedBox(height: 14),
        // 2:1 aspect ratio so banners scale correctly on every screen width.
        // On a 390px device each visible card is ~359px wide → ~180px tall.
        AspectRatio(
          aspectRatio: 2.0,
          child: PageView.builder(
            controller: _ctrl,
            onPageChanged: (i) => setState(() => _page = i),
            itemCount: count,
            itemBuilder: (_, i) => _BannerTile(
              banner: widget.banners[i],
              fallbackGradient: _fallbacks[i % _fallbacks.length],
            ),
          ),
        ),
        if (count > 1) ...[
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              count,
              (i) => AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == _page ? 18 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: i == _page ? AppColors.cta : AppColors.line,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
        ] else
          const SizedBox(height: 10),
      ],
    );
  }
}

/// Single banner tile: real image with gradient overlay, or fallback gradient card.
class _BannerTile extends StatelessWidget {
  const _BannerTile({required this.banner, required this.fallbackGradient});
  final HomeBanner banner;
  final LinearGradient fallbackGradient;

  @override
  Widget build(BuildContext context) {
    final hasImage = (banner.imageUrl ?? '').isNotEmpty;

    return GestureDetector(
      onTap: (banner.targetUrl ?? '').isNotEmpty
          ? () => context.push(banner.targetUrl!)
          : null,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          boxShadow: AppShadows.soft,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: hasImage ? _ImageTile(banner: banner) : _GradientTile(banner: banner, gradient: fallbackGradient),
        ),
      ),
    );
  }
}

/// Real-image banner: full-bleed photo + bottom gradient overlay with text.
class _ImageTile extends StatelessWidget {
  const _ImageTile({required this.banner});
  final HomeBanner banner;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Full-bleed image
        CachedNetworkImage(
          imageUrl: banner.imageUrl!,
          fit: BoxFit.cover,
          placeholder: (_, _) => Container(
            decoration: const BoxDecoration(gradient: AppGradients.brand),
          ),
          errorWidget: (_, _, _) => Container(
            decoration: const BoxDecoration(gradient: AppGradients.cta),
            alignment: Alignment.center,
            child: const Icon(Icons.image_not_supported_outlined, color: Colors.white54, size: 32),
          ),
        ),
        // Bottom gradient scrim for text legibility
        Positioned(
          left: 0, right: 0, bottom: 0,
          child: Container(
            height: 76,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Colors.black.withValues(alpha: 0.72), Colors.transparent],
              ),
            ),
          ),
        ),
        // Text overlay
        Positioned(
          left: 16, right: 16, bottom: 14,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                banner.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 17, shadows: [
                  Shadow(color: Colors.black45, blurRadius: 4),
                ]),
              ),
              if ((banner.subtitle ?? '').isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  banner.subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.88), fontSize: 12.5),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// No-image fallback: brand gradient tile with title + subtitle text.
class _GradientTile extends StatelessWidget {
  const _GradientTile({required this.banner, required this.gradient});
  final HomeBanner banner;
  final LinearGradient gradient;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(gradient: gradient),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            banner.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 19),
          ),
          if ((banner.subtitle ?? '').isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              banner.subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.onSeeAll});
  final String title;
  final VoidCallback? onSeeAll;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
      child: Row(
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17.5)),
          const Spacer(),
          if (onSeeAll != null)
            TextButton(
              onPressed: onSeeAll,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('See all', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
        ],
      ),
    );
  }
}

class _Categories extends StatelessWidget {
  const _Categories({required this.items});
  final List<Category> items;

  static const _bgColors = [
    AppColors.ctaTint, // amber-tint
    Color(0xFFE0F7FA), // teal-tint
    Color(0xFFF3E5F5), // purple-tint
    Color(0xFFE8F5E9), // green-tint
    Color(0xFFE3F2FD), // blue-tint
    Color(0xFFFCE4EC), // pink-tint
    Color(0xFFF9FBE7), // lime-tint
    Color(0xFFECEFF1), // gray-tint
  ];

  static const _iconColors = [
    AppColors.cta,
    AppColors.teal,
    Color(0xFF8B5CF6),
    AppColors.success,
    AppColors.info,
    Color(0xFFEC4899),
    Color(0xFF84CC16),
    AppColors.inkSoft,
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 108,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (_, i) {
          final c = items[i];
          final bgColor = _bgColors[i % _bgColors.length];
          final iconColor = _iconColors[i % _iconColors.length];
          return ScaleTap(
            onTap: () => context.push('/search?category=${Uri.encodeComponent(c.slug)}'),
            child: SizedBox(
              width: 68,
              child: Column(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
                    padding: const EdgeInsets.all(12),
                    child: c.imageUrl.isEmpty
                        ? Icon(Icons.category_rounded, color: iconColor, size: 24)
                        : ClipOval(child: AppImage(url: c.imageUrl, radius: 0)),
                  ),
                  const SizedBox(height: 6),
                  Text(c.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, height: 1.1)),
                ],
              ),
            ),
          );
        },
      ),
    ).animate().fadeIn(duration: 300.ms);
  }
}

class _Shops extends StatelessWidget {
  const _Shops({required this.items});
  final List<Shop> items;
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (_, i) {
          final s = items[i];
          return ScaleTap(
            onTap: () => context.push('/shop/${s.id}?name=${Uri.encodeComponent(s.name)}'),
            child: Container(
            width: 184,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              boxShadow: AppShadows.card,
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: s.imageUrl.isEmpty
                        ? Container(color: AppColors.bgTint, child: const Icon(Icons.storefront_rounded, color: AppColors.primary, size: 22))
                        : AppImage(url: s.imageUrl, radius: 12),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, height: 1.1)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.access_time_rounded, size: 12, color: AppColors.cta),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              _shopMeta(s),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: AppColors.cta, fontSize: 11, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          );
        },
      ),
    ).animate().fadeIn(duration: 300.ms);
  }
}

/// "32 min · 3.2 km" (or business type / distance) — single line, ellipsized.
String _shopMeta(Shop s) {
  final parts = <String>[];
  if (s.etaMin != null) {
    parts.add('${s.etaMin} min');
  } else if ((s.businessType ?? '').isNotEmpty) {
    parts.add(s.businessType!);
  }
  if (s.distanceKm != null) parts.add('${s.distanceKm!.toStringAsFixed(1)} km');
  return parts.isEmpty ? 'Store' : parts.join(' · ');
}

/// Renders the product grid as a [SliverGrid] so items are lazily built and
/// only the visible subset is laid out — critical for 60fps on low-end devices.
class _ProductGrid extends StatelessWidget {
  const _ProductGrid({required this.items, required this.isScoped});
  final List<Product> items;
  final bool isScoped;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      final msg = isScoped ? 'No products available in your area' : 'No products here yet';
      return SliverToBoxAdapter(
        child: Padding(padding: const EdgeInsets.all(24), child: EmptyView(title: msg)),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          mainAxisExtent: 240,
        ),
        delegate: SliverChildBuilderDelegate(
          (_, i) => ProductCard(product: items[i])
              .animate()
              .fadeIn(delay: ((i % 8) * 35).ms, duration: 240.ms)
              .slideY(begin: 0.06, end: 0, curve: Curves.easeOut),
          childCount: items.length,
        ),
      ),
    );
  }
}

class _LocationBanner extends StatelessWidget {
  const _LocationBanner();
  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.ctaTint,
      child: InkWell(
        onTap: () => context.push('/location'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.location_on_outlined, color: AppColors.ctaDark, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Set your delivery location to see nearby stores',
                    style: TextStyle(fontSize: 13, color: AppColors.ink)),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => context.push('/location'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.ctaDark,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Set', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmailPromptBanner extends StatelessWidget {
  const _EmailPromptBanner({required this.auth, required this.onDismiss});
  final AuthProvider auth;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    if (!auth.isLoggedIn || (auth.user?.email ?? '').isNotEmpty) {
      return const SizedBox.shrink();
    }
    return Material(
      color: const Color(0xFFFFF8E1),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.mail_outline_rounded, color: Color(0xFFFFA000), size: 20),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Add your email for order updates & account recovery.',
                style: TextStyle(fontSize: 13, color: AppColors.ink),
              ),
            ),
            const SizedBox(width: 4),
            TextButton(
              onPressed: () {
                onDismiss();
                context.go('/account');
              },
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFFFA000),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Add', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 16, color: AppColors.inkSoft),
              onPressed: onDismiss,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoShopsView extends StatelessWidget {
  const _NoShopsView({required this.onChangeLocation});
  final VoidCallback onChangeLocation;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.store_mall_directory_outlined, size: 64, color: AppColors.inkSoft),
            const SizedBox(height: 16),
            const Text('No stores in your area', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
            const SizedBox(height: 8),
            const Text(
              'We don\'t deliver to this location yet. Try a nearby area.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.inkSoft, fontSize: 14),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onChangeLocation,
              icon: const Icon(Icons.edit_location_alt_outlined, size: 18),
              label: const Text('Change location'),
            ),
          ],
        ),
      ),
    );
  }
}
