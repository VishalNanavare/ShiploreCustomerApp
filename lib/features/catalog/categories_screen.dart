import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/catalog.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../widgets/app_scale_tap.dart';
import '../../widgets/network_image.dart';
import '../../widgets/skeletons.dart';
import '../../widgets/states.dart';

/// A group header + its sub-category tiles (Blinkit "Grocery & Kitchen" → tiles).
typedef _Section = ({Category group, List<Category> items});

/// Full categories tab — grouped sections built from the category hierarchy.
class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});
  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  Future<List<_Section>>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _load();
  }

  Future<List<_Section>> _load() async {
    final all = await context.read<CatalogRepository>().categories();
    final byId = {for (final c in all) c.id: c};
    // Top groups = level-0 (or orphans). Tiles = their direct children.
    final groups = all.where((c) => c.level == 0 || c.parentId == null || !byId.containsKey(c.parentId));
    final sections = <_Section>[];
    for (final g in groups) {
      if (g.name.toLowerCase().contains('hotel')) continue; // hotels aren't sold here
      // Only sub-categories that actually have products (hide empty ones).
      final items = all.where((c) => c.parentId == g.id && c.hasProducts).toList();
      if (items.isNotEmpty) sections.add((group: g, items: items));
    }
    return sections;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Shop by category')),
      body: FutureBuilder<List<_Section>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Shimmery(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  for (var s = 0; s < 3; s++) ...[
                    const SkeletonBox(width: 160, height: 16),
                    const SizedBox(height: 12),
                    GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: 4,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.78,
                      children: List.generate(8, (_) => const SkeletonBox(radius: 16, height: double.infinity)),
                    ),
                    const SizedBox(height: 20),
                  ],
                ],
              ),
            );
          }
          if (snap.hasError) {
            return ErrorView(error: snap.error!, onRetry: () => setState(() {
                  _future = _load();
                }));
          }
          final sections = snap.data ?? const <_Section>[];
          if (sections.isEmpty) {
            return const EmptyView(title: 'No categories yet', icon: Icons.category_outlined);
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: sections.length,
            itemBuilder: (_, i) => _GroupSection(section: sections[i])
                .animate()
                .fadeIn(delay: (i * 60).ms, duration: 260.ms),
          );
        },
      ),
    );
  }
}

class _GroupSection extends StatelessWidget {
  const _GroupSection({required this.section});
  final _Section section;
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text(section.group.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: section.items.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            mainAxisSpacing: 14,
            crossAxisSpacing: 10,
            childAspectRatio: 0.74,
          ),
          itemBuilder: (_, i) => _CategoryTile(category: section.items[i]),
        ),
      ],
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.category});
  final Category category;
  @override
  Widget build(BuildContext context) {
    return ScaleTap(
      onTap: () => context.push('/search?category=${Uri.encodeComponent(category.slug)}'),
      child: Column(
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.bgTint,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.line),
              ),
              padding: const EdgeInsets.all(10),
              child: category.imageUrl.isEmpty
                  ? const Icon(Icons.category_rounded, color: AppColors.primary, size: 26)
                  : AppImage(url: category.imageUrl, radius: 10),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            category.name,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, height: 1.1),
          ),
        ],
      ),
    );
  }
}
