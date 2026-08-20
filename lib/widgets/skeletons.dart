import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../core/theme/app_theme.dart';

/// A single shimmering placeholder block.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, this.width, this.height = 14, this.radius = 8});
  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(radius)),
      );
}

/// Wraps children in a shimmer sweep (use with [SkeletonBox] placeholders).
class Shimmery extends StatelessWidget {
  const Shimmery({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Shimmer.fromColors(
        baseColor: const Color(0xFFE9ECEF),
        highlightColor: const Color(0xFFF7F8FA),
        child: child,
      );
}

/// Full home-screen skeleton: category row, shop row, product grid.
class HomeSkeleton extends StatelessWidget {
  const HomeSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmery(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        physics: const NeverScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: 96,
            child: ListView(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              children: List.generate(
                6,
                (_) => const Padding(
                  padding: EdgeInsets.only(right: 14),
                  child: Column(children: [
                    SkeletonBox(width: 60, height: 60, radius: 18),
                    SizedBox(height: 8),
                    SkeletonBox(width: 50, height: 9),
                  ]),
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          const SkeletonBox(width: 160, height: 16),
          const SizedBox(height: 12),
          SizedBox(
            height: 92,
            child: ListView(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              children: List.generate(
                3,
                (_) => const Padding(
                  padding: EdgeInsets.only(right: 12),
                  child: SkeletonBox(width: 170, height: 92, radius: 16),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const SkeletonBox(width: 130, height: 16),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 4,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              mainAxisExtent: 240,
            ),
            itemBuilder: (_, __) => const _ProductCardSkeleton(),
          ),
        ],
      ),
    );
  }
}

/// Grid of shimmering product cards (search/listing loading state).
class ProductGridSkeleton extends StatelessWidget {
  const ProductGridSkeleton({super.key, this.count = 6});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Shimmery(
      child: GridView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: count,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          mainAxisExtent: 220,
        ),
        itemBuilder: (_, __) => const _ProductCardSkeleton(),
      ),
    );
  }
}

class _ProductCardSkeleton extends StatelessWidget {
  const _ProductCardSkeleton();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SkeletonBox(radius: 12, height: 130),
          SizedBox(height: 6),
          SkeletonBox(height: 13),
          SizedBox(height: 4),
          SkeletonBox(width: 80, height: 14),
          SizedBox(height: 6),
          SkeletonBox(height: 30, radius: 8),
        ],
      ),
    );
  }
}
