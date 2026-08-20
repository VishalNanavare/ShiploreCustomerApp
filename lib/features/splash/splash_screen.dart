import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';

typedef _Cat = ({IconData icon, String label, Color color});

// Chip dimensions shared by marquee and chip widgets.
const _kChipW = 126.0;
const _kChipGap = 10.0;
const _kChipH = 46.0;

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scroll;

  // 4 rows × 6 chips = 24 categories across the splash
  static const _r1 = <_Cat>[
    (icon: Icons.shopping_basket,   label: 'Grocery',     color: Color(0xFF43A047)),
    (icon: Icons.restaurant,        label: 'Food',        color: Color(0xFFE53935)),
    (icon: Icons.local_pharmacy,    label: 'Pharmacy',    color: Color(0xFF1E88E5)),
    (icon: Icons.spa,               label: 'Beauty',      color: Color(0xFFD81B60)),
    (icon: Icons.cake,              label: 'Bakery',      color: Color(0xFFFB8C00)),
    (icon: Icons.coffee,            label: 'Coffee',      color: Color(0xFF6D4C41)),
  ];
  static const _r2 = <_Cat>[
    (icon: Icons.devices,           label: 'Electronics', color: Color(0xFF8E24AA)),
    (icon: Icons.checkroom,         label: 'Fashion',     color: Color(0xFFE91E63)),
    (icon: Icons.fitness_center,    label: 'Sports',      color: Color(0xFFEF6C00)),
    (icon: Icons.menu_book,         label: 'Books',       color: Color(0xFF43A047)),
    (icon: Icons.child_care,        label: 'Baby',        color: Color(0xFFFDD835)),
    (icon: Icons.local_florist,     label: 'Flowers',     color: Color(0xFFF06292)),
  ];
  static const _r3 = <_Cat>[
    (icon: Icons.grass,             label: 'Vegetables',  color: Color(0xFF7CB342)),
    (icon: Icons.water_drop,        label: 'Dairy',       color: Color(0xFF29B6F6)),
    (icon: Icons.set_meal,          label: 'Meat',        color: Color(0xFFE53935)),
    (icon: Icons.fastfood,          label: 'Snacks',      color: Color(0xFFFFA726)),
    (icon: Icons.local_bar,         label: 'Drinks',      color: Color(0xFF00ACC1)),
    (icon: Icons.icecream,          label: 'Ice Cream',   color: Color(0xFFF48FB1)),
  ];
  static const _r4 = <_Cat>[
    (icon: Icons.pets,              label: 'Pet Care',    color: Color(0xFFFFA000)),
    (icon: Icons.weekend,           label: 'Home',        color: Color(0xFF5C6BC0)),
    (icon: Icons.kitchen,           label: 'Kitchen',     color: Color(0xFF00897B)),
    (icon: Icons.yard,              label: 'Garden',      color: Color(0xFF558B2F)),
    (icon: Icons.medical_services,  label: 'Health',      color: Color(0xFF039BE5)),
    (icon: Icons.sports_esports,    label: 'Gaming',      color: Color(0xFF7B1FA2)),
  ];

  @override
  void initState() {
    super.initState();
    // 14-second cycle → comfortable scroll pace, loops seamlessly.
    _scroll = AnimationController(
        vsync: this, duration: const Duration(seconds: 14))
      ..repeat();
    Future.delayed(const Duration(milliseconds: 3100), () {
      if (mounted) context.go('/');
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF06091A);
    return Scaffold(
      backgroundColor: bg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Background — subtle radial from deep-blue centre ──────────────
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 1.15,
                colors: [Color(0xFF0D1B3E), Color(0xFF06091A)],
              ),
            ),
          ),

          // ── TOP chip rows ─────────────────────────────────────────────────
          Positioned(
            top: 0, left: 0, right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.only(top: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _FadeMarquee(
                      ctrl: _scroll, items: _r1,
                      reverse: false, fromBottom: false, delayMs: 180,
                    ),
                    const SizedBox(height: 10),
                    _FadeMarquee(
                      ctrl: _scroll, items: _r2,
                      reverse: true, fromBottom: false, delayMs: 300,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── BOTTOM chip rows ──────────────────────────────────────────────
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _FadeMarquee(
                      ctrl: _scroll, items: _r3,
                      reverse: true, fromBottom: true, delayMs: 300,
                    ),
                    const SizedBox(height: 10),
                    _FadeMarquee(
                      ctrl: _scroll, items: _r4,
                      reverse: false, fromBottom: true, delayMs: 180,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Vertical gradient — fades chips into the logo zone ────────────
          const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,     // 0 % — top chips fully visible
                    Color(0xE006091A),      // 22 % — chips start fading
                    Color(0xFF06091A),      // 30 % — fully opaque (logo zone begins)
                    Color(0xFF06091A),      // 70 % — fully opaque (logo zone ends)
                    Color(0xE006091A),      // 78 % — chips start fading
                    Colors.transparent,     // 100 % — bottom chips fully visible
                  ],
                  stops: [0.0, 0.22, 0.30, 0.70, 0.78, 1.0],
                ),
              ),
            ),
          ),

          // ── Centre: logo card + brand + tagline + dots ────────────────────
          const Center(child: _CenterContent()),
        ],
      ),
    );
  }
}

// ── Marquee row wrapped with horizontal fade edges ───────────────────────────

class _FadeMarquee extends StatelessWidget {
  const _FadeMarquee({
    required this.ctrl,
    required this.items,
    required this.reverse,
    required this.fromBottom,
    required this.delayMs,
  });

  final AnimationController ctrl;
  final List<_Cat> items;
  final bool reverse;
  final bool fromBottom;
  final int delayMs;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (r) => const LinearGradient(
        colors: [
          Colors.transparent,
          Colors.white,
          Colors.white,
          Colors.transparent,
        ],
        stops: [0.0, 0.10, 0.90, 1.0],
      ).createShader(r),
      child: _MarqueeRow(ctrl: ctrl, items: items, reverse: reverse),
    )
        .animate(delay: Duration(milliseconds: delayMs))
        .fadeIn(duration: 700.ms)
        .slideY(
          begin: fromBottom ? 0.55 : -0.55,
          end: 0,
          duration: 700.ms,
          curve: Curves.easeOut,
        );
  }
}

// ── Infinite-scroll row ───────────────────────────────────────────────────────

class _MarqueeRow extends StatelessWidget {
  const _MarqueeRow(
      {required this.ctrl, required this.items, required this.reverse});

  final AnimationController ctrl;
  final List<_Cat> items;
  final bool reverse;

  @override
  Widget build(BuildContext context) {
    // Repeat 3× so the seam is never visible during the animation loop.
    final singleW = items.length * (_kChipW + _kChipGap);
    final all = [...items, ...items, ...items];

    return SizedBox(
      height: _kChipH,
      child: ClipRect(
        child: AnimatedBuilder(
          animation: ctrl,
          builder: (_, child) {
            final t = reverse ? (1.0 - ctrl.value) : ctrl.value;
            return Transform.translate(
              offset: Offset(-(t * singleW), 0),
              child: child,
            );
          },
          child: OverflowBox(
            maxWidth: double.infinity,
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: all.map((c) => _Chip(cat: c)).toList(),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Single category chip ──────────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  const _Chip({required this.cat});
  final _Cat cat;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _kChipW,
      height: _kChipH,
      margin: const EdgeInsets.only(right: _kChipGap),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(
            color: Colors.white.withValues(alpha: 0.09), width: 0.8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: cat.color.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: Icon(cat.icon, size: 15, color: cat.color),
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              cat.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
    );
  }
}

// ── Centre content: logo, brand, tagline, dots ────────────────────────────────

class _CenterContent extends StatelessWidget {
  const _CenterContent();

  static const _brand = 'SHIPLORE';

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Logo card with glow ────────────────────────────────────────────
        Stack(
          alignment: Alignment.center,
          children: [
            // Outer ambient glow
            Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.cta.withValues(alpha: 0.22),
                    blurRadius: 70,
                    spreadRadius: 18,
                  ),
                  BoxShadow(
                    color: const Color(0xFF1565C0).withValues(alpha: 0.18),
                    blurRadius: 45,
                    spreadRadius: 8,
                  ),
                ],
              ),
            ),
            // Subtle outer ring
            Container(
              width: 124,
              height: 124,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.07), width: 1),
              ),
            ),
            // Logo badge — clean white circular coin (matches the login hero)
            Container(
              width: 104,
              height: 104,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.38),
                    blurRadius: 32,
                    offset: const Offset(0, 12),
                  ),
                  BoxShadow(
                    color: AppColors.cta.withValues(alpha: 0.18),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipOval(
                child: Image.asset('assets/images/logo.png', fit: BoxFit.cover),
              ),
            ),
          ],
        )
            .animate(delay: 180.ms)
            .scale(
              begin: const Offset(0.15, 0.15),
              end: const Offset(1, 1),
              duration: 700.ms,
              curve: Curves.easeOutBack,
            )
            .fadeIn(duration: 400.ms),

        const SizedBox(height: 30),

        // ── Brand name — letter stagger ────────────────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: List.generate(_brand.length, (i) {
            return Text(
              _brand[i],
              style: const TextStyle(
                color: Colors.white,
                fontSize: 30,
                fontWeight: FontWeight.w900,
                letterSpacing: 5,
                height: 1.0,
              ),
            )
                .animate(delay: Duration(milliseconds: 520 + i * 58))
                .slideY(
                  begin: 0.85,
                  end: 0,
                  duration: 340.ms,
                  curve: Curves.easeOutQuart,
                )
                .fadeIn(duration: 260.ms);
          }),
        ),

        const SizedBox(height: 9),

        // ── Tagline ────────────────────────────────────────────────────────
        const Text(
          'Your everyday superstore',
          style: TextStyle(
            color: Colors.white38,
            fontSize: 12,
            fontWeight: FontWeight.w400,
            letterSpacing: 1.8,
          ),
        ).animate(delay: 980.ms).fadeIn(duration: 500.ms),

        const SizedBox(height: 42),

        // ── Loading dots — staggered scale-in then gentle pulse ────────────
        Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            return Container(
              width: 5.5,
              height: 5.5,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: AppColors.cta,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.cta.withValues(alpha: 0.5),
                    blurRadius: 6,
                  )
                ],
              ),
            )
                .animate(
                  delay: Duration(milliseconds: 1120 + i * 200),
                )
                .scale(
                  begin: const Offset(0, 0),
                  end: const Offset(1, 1),
                  duration: 350.ms,
                  curve: Curves.easeOutBack,
                )
                .fadeIn(duration: 200.ms)
                .then(delay: 200.ms)
                .animate(
                  onPlay: (c) => c.repeat(reverse: true),
                  delay: Duration(milliseconds: i * 180),
                )
                .scaleXY(begin: 1.0, end: 0.5, duration: 600.ms, curve: Curves.easeInOut)
                .fade(begin: 1.0, end: 0.35, duration: 600.ms);
          }),
        ),
      ],
    );
  }
}
