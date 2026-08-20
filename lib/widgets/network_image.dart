import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../core/theme/app_theme.dart';

/// Product/category image with a shimmer loading placeholder + error fallback.
class AppImage extends StatelessWidget {
  const AppImage({super.key, required this.url, this.size, this.radius = 10, this.fit = BoxFit.cover});

  final String url;
  final double? size;
  final double radius;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final error = Container(
      width: size,
      height: size,
      color: AppColors.bg,
      alignment: Alignment.center,
      child: const Icon(Icons.image_outlined, color: AppColors.inkSoft, size: 22),
    );
    final loading = Shimmer.fromColors(
      baseColor: const Color(0xFFE9ECEF),
      highlightColor: const Color(0xFFF7F8FA),
      child: Container(width: size, height: size, color: Colors.white),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: url.isEmpty
          ? error
          : CachedNetworkImage(
              imageUrl: url,
              width: size,
              height: size,
              fit: fit,
              fadeInDuration: const Duration(milliseconds: 250),
              fadeInCurve: Curves.easeOut,
              placeholder: (_, _) => loading,
              errorWidget: (_, _, _) => error,
            ),
    );
  }
}
