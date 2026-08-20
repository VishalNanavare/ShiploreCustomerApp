import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Shiplore brand theme — derived from the logo: a deep NAVY badge with an
/// AMBER/orange delivery-route swoosh. Navy carries structure (headers, nav,
/// text); amber leads the actions (ADD, CTAs, price-drops). Quick-commerce
/// look: soft shadows, rounded cards, dense grids.
class AppColors {
  AppColors._();

  // Brand
  static const primary = Color(0xFF13294B); // navy — brand / headers / nav / text
  static const primaryDark = Color(0xFF0B1E38);
  static const navy = primary;

  // Action / accent (the amber swoosh)
  static const cta = Color(0xFFF5821F); // orange — ADD / CTAs / place-order
  static const ctaDark = Color(0xFFE06D0A);
  static const accent = Color(0xFFF7A823); // saffron — badges / highlights
  static const teal = Color(0xFF16B5C9); // sparing tech accent

  // Surfaces
  static const bg = Color(0xFFF4F6FA);
  static const bgTint = Color(0xFFEAF0F8); // navy-tinted tiles
  static const ctaTint = Color(0xFFFFF1DE); // amber-tinted
  static const surface = Colors.white;

  // Text / lines
  static const ink = Color(0xFF13202E);
  static const inkSoft = Color(0xFF647084);
  static const line = Color(0xFFE5E9F0);

  // Semantic (use these instead of hard-coding hexes)
  static const danger = Color(0xFFE5484D);
  static const success = Color(0xFF1BA672);
  static const warning = Color(0xFFF5821F);
  static const info = Color(0xFF1570EF);
  static const star = Color(0xFF1BA672);

  // Amber "attention" notice (No-pin badges, dev notices) — one source of truth
  static const warnSurface = Color(0xFFFFF3E0);
  static const warnBorder = Color(0xFFFFB300);
  static const warnText = Color(0xFFE65100);
}

/// Reusable elevation tokens (cardTheme is flat; use these for the floating-card feel).
class AppShadows {
  AppShadows._();
  static const card = <BoxShadow>[
    BoxShadow(color: Color(0x14101828), blurRadius: 14, offset: Offset(0, 6)),
    BoxShadow(color: Color(0x0A101828), blurRadius: 4, offset: Offset(0, 1)),
  ];
  static const soft = <BoxShadow>[
    BoxShadow(color: Color(0x0F101828), blurRadius: 10, offset: Offset(0, 3)),
  ];
}

class AppGradients {
  AppGradients._();
  // Navy — headers, splash, hero.
  static const brand = LinearGradient(
    colors: [Color(0xFF1C3C6B), Color(0xFF0B1E38)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  // Amber/orange — buttons, cart bar, quantity stepper.
  static const cta = LinearGradient(
    colors: [Color(0xFFF89A2B), Color(0xFFE06D0A)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class AppTextStyles {
  AppTextStyles._();

  static const heading1 = TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.ink, height: 1.2);
  static const heading2 = TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.ink, height: 1.3);
  static const label = TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.ink);
  static const caption = TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: AppColors.inkSoft);
  static const price = TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.ink);
  static const priceMrp = TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: AppColors.inkSoft, decoration: TextDecoration.lineThrough);
}

class AppTheme {
  AppTheme._();

  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        primary: AppColors.primary,
        secondary: AppColors.cta,
        surface: AppColors.surface,
      ),
      scaffoldBackgroundColor: AppColors.bg,
    );
    final text = GoogleFonts.interTextTheme(base.textTheme).apply(
      bodyColor: AppColors.ink,
      displayColor: AppColors.ink,
    );
    return base.copyWith(
      textTheme: text,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: text.titleLarge?.copyWith(fontWeight: FontWeight.w800, fontSize: 19, color: AppColors.ink),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.line),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: AppColors.surface,
        indicatorColor: AppColors.cta.withValues(alpha: 0.16),
        height: 64,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => TextStyle(
            fontSize: 11.5,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: s.contains(WidgetState.selected) ? AppColors.primary : AppColors.inkSoft,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(
            color: s.contains(WidgetState.selected) ? AppColors.primary : AppColors.inkSoft,
          ),
        ),
      ),
      // Filled CTAs lead in amber/orange with white text.
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.cta,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
      ),
      // Outlined ADD/secondary also amber.
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.cta,
          minimumSize: const Size.fromHeight(48),
          side: const BorderSide(color: AppColors.cta, width: 1.4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.primary),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: AppColors.bg,
        side: const BorderSide(color: AppColors.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      // Smooth, modern slide for pushed routes (product, search, checkout, …).
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}
