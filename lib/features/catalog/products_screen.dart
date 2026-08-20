import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatx.dart';
import '../../data/models/catalog.dart';
import '../../data/models/product.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../providers/location_provider.dart';
import '../../widgets/app_scale_tap.dart';
import '../../widgets/network_image.dart';
import '../../widgets/product_card.dart';
import '../../widgets/skeletons.dart';
import '../../widgets/states.dart';
import '../cart/cart_bar.dart';

/// Sort options the backend supports (value sent as the `sort` query param).
enum _Sort {
  featured('featured', 'Featured'),
  priceAsc('price_asc', 'Price: Low to High'),
  priceDesc('price_desc', 'Price: High to Low'),
  name('name', 'Name (A–Z)');

  const _Sort(this.value, this.label);
  final String value;
  final String label;

  static _Sort fromValue(String? v) => switch (v) {
    'price_asc'  => _Sort.priceAsc,
    'price_desc' => _Sort.priceDesc,
    'name'       => _Sort.name,
    _            => _Sort.featured,
  };
}

/// Upper bound for the price range filter (rupees).
const double _kMaxPrice = 50000;

/// Closed set of product labels; keys match `product_labels.label` in the DB.
const _kLabels = <String, String>{
  'hot_deal':    'Hot Deal',
  'new_arrival': 'New Arrival',
  'bestseller':  'Bestseller',
  'trending':    'Trending',
  'featured':    'Featured',
};

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({
    super.key,
    this.initialQuery,
    this.category,
    this.shopId,
    this.title,
    this.brand,
    this.onOffer,
    this.minPrice,
    this.maxPrice,
    this.initialSort,
    this.label,
  });
  final String? initialQuery;
  final String? category;
  final int? shopId;
  final String? title;
  final int? brand;
  final bool? onOffer;
  final double? minPrice;
  final double? maxPrice;
  final String? initialSort;
  final String? label;

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final List<Product> _items = [];
  String _q = '';
  String? _category;
  int _page = 1;
  int _pages = 1;
  bool _loading = false;
  Object? _error;

  // Left sub-category rail (only built when a category is active).
  List<Category> _siblings = const [];

  // Sort + filters.
  _Sort _sort = _Sort.featured;
  RangeValues _price = const RangeValues(0, _kMaxPrice);
  bool _inStock = false;
  bool _onOffer = false;
  int? _brand;
  String? _brandName;
  String? _label;

  List<String> _recent = const [];
  bool _showDiscovery = false;

  static const _kRecentKey = 'search_recent';
  static const _kTrending = ['Milk', 'Eggs', 'Bread', 'Atta', 'Pulses', 'Rice', 'Dal', 'Sugar'];

  // Location locked at reload time so all pages use the same coordinates.
  double? _lat;
  double? _lng;
  DeliveryLocation? _lastLoadedLocation;

  bool get _hasMinPrice => _price.start > 0;
  bool get _hasMaxPrice => _price.end < _kMaxPrice;
  bool get _priceActive => _hasMinPrice || _hasMaxPrice;
  bool get _anyActive =>
      _sort != _Sort.featured || _priceActive || _inStock || _onOffer || _brand != null || _label != null;

  double? get _minPrice => _hasMinPrice ? _price.start : null;
  double? get _maxPrice => _hasMaxPrice ? _price.end : null;

  @override
  void initState() {
    super.initState();
    _q = widget.initialQuery ?? '';
    _category = widget.category;
    _controller.text = _q;
    if (widget.brand != null) _brand = widget.brand;
    if (widget.onOffer == true) _onOffer = true;
    if (widget.minPrice != null) _price = RangeValues(widget.minPrice!, _price.end);
    if (widget.maxPrice != null) _price = RangeValues(_price.start, widget.maxPrice!);
    if (widget.initialSort != null) _sort = _Sort.fromValue(widget.initialSort);
    if (widget.label != null) _label = widget.label;
    _showDiscovery = widget.initialQuery == null && widget.category == null && widget.shopId == null;
    if (_showDiscovery) _loadRecent();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 400) _loadMore();
    });
    if (widget.shopId != null) {
      _loadShopRail();
    } else if (_category != null) {
      _loadRail();
    }
  }

  Future<void> _loadRecent() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _recent = prefs.getStringList(_kRecentKey) ?? const []);
  }

  Future<void> _saveRecent(String query) async {
    if (query.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_kRecentKey) ?? [];
    list.remove(query);
    list.insert(0, query);
    if (list.length > 5) list.removeLast();
    await prefs.setStringList(_kRecentKey, list);
    if (mounted) setState(() => _recent = list);
  }

  Future<void> _removeRecent(String query) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_kRecentKey) ?? [];
    list.remove(query);
    await prefs.setStringList(_kRecentKey, list);
    if (mounted) setState(() => _recent = list);
  }

  /// Loads the categories that have products in this shop to build the left
  /// rail, prepending a "Top Picks" pseudo-entry (empty slug) meaning "all of
  /// this shop". Only shown when there are real categories to switch between.
  Future<void> _loadShopRail() async {
    try {
      final shopCats =
          (await context.read<CatalogRepository>().shopCategories(widget.shopId!))
              .where((c) => c.hasProducts) // hide categories the shop doesn't stock
              .toList();
      if (!mounted) return;
      if (shopCats.length < 2) return; // nothing meaningful to switch between
      setState(() => _siblings = [
            Category(name: 'Top Picks', slug: ''),
            ...shopCats,
          ]);
    } catch (_) {
      // Rail is a non-essential enhancement; ignore failures silently.
    }
  }

  /// Loads the sibling sub-categories for the active category to build the
  /// left rail: categories sharing its parent, or — when it's a top group —
  /// its own children.
  Future<void> _loadRail() async {
    try {
      final all = await context.read<CatalogRepository>().categories();
      if (!mounted) return;
      final active = all.where((c) => c.slug == _category).firstOrNull;
      if (active == null) return;
      final siblings = (active.parentId != null
              ? all.where((c) => c.parentId == active.parentId)
              : all.where((c) => c.parentId == active.id))
          .where((c) => c.hasProducts || c.slug == _category) // hide empty sub-categories
          .toList();
      if (siblings.length < 2) return; // nothing meaningful to switch between
      setState(() => _siblings = siblings);
    } catch (_) {
      // Rail is a non-essential enhancement; ignore failures silently.
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final loc = context.read<LocationProvider>().location;
    if (_lastLoadedLocation == null ||
        loc?.lat != _lastLoadedLocation?.lat ||
        loc?.lng != _lastLoadedLocation?.lng) {
      _lastLoadedLocation = loc;
      _lat = loc?.lat;
      _lng = loc?.lng;
      _reload();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final loc = context.read<LocationProvider>().location;
    _lat = loc?.lat;
    _lng = loc?.lng;
    _lastLoadedLocation = loc;
    setState(() {
      _items.clear();
      _page = 1;
      _pages = 1;
      _error = null;
    });
    await _fetch(1);
  }

  Future<void> _loadMore() async {
    if (_loading || _page >= _pages) return;
    await _fetch(_page + 1);
  }

  void _selectCategory(String slug) {
    // An empty slug is the shop rail's "Top Picks" pseudo-entry → all products.
    final next = slug.isEmpty ? null : slug;
    if (next == _category) return;
    setState(() => _category = next);
    _reload();
  }

  Future<void> _fetch(int page) async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final res = await context.read<CatalogRepository>().products(
            q: _q,
            category: _category,
            sort: _sort.value,
            minPrice: _minPrice,
            maxPrice: _maxPrice,
            inStock: _inStock,
            onOffer: _onOffer,
            shopId: widget.shopId,
            brand: _brand,
            label: _label,
            page: page,
            lat: _lat,
            lng: _lng,
          );
      if (!mounted) return;
      setState(() {
        _items.addAll(res.items);
        _page = res.page;
        _pages = res.pages;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ---- sort / filter sheets ----

  Future<void> _openSort() async {
    final picked = await showModalBottomSheet<_Sort>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _SheetHandle(),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Sort by',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
              ),
            ),
            RadioGroup<_Sort>(
              groupValue: _sort,
              onChanged: (v) => Navigator.pop(ctx, v),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final s in _Sort.values)
                    RadioListTile<_Sort>(
                      value: s,
                      activeColor: AppColors.primary,
                      title: Text(s.label),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || picked == null || picked == _sort) return;
    setState(() => _sort = picked);
    await _reload();
  }

  Future<void> _openFilters() async {
    var draft = _price;
    var inStock = _inStock;
    var onOffer = _onOffer;
    int? draftBrand = _brand;
    String? draftLabel = _label;

    List<({int id, String name, int count})> brands = [];
    try {
      brands = await context
          .read<CatalogRepository>()
          .brands(category: widget.category ?? _category);
    } catch (_) {}

    if (!mounted) return;

    final applied = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SheetHandle(),
                Row(
                  children: [
                    const Text('Filters',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                    const Spacer(),
                    TextButton(
                      onPressed: () => setSheet(() {
                        draft = const RangeValues(0, _kMaxPrice);
                        inStock = false;
                        onOffer = false;
                        draftBrand = null;
                        draftLabel = null;
                      }),
                      child: const Text('Reset'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text('Price range',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                Text(
                  '${Formatx.money(draft.start)} – '
                  '${draft.end >= _kMaxPrice ? '${Formatx.money(_kMaxPrice)}+' : Formatx.money(draft.end)}',
                  style: const TextStyle(color: AppColors.inkSoft, fontSize: 13),
                ),
                RangeSlider(
                  values: draft,
                  min: 0,
                  max: _kMaxPrice,
                  divisions: 100,
                  activeColor: AppColors.primary,
                  labels: RangeLabels(
                    Formatx.money(draft.start),
                    draft.end >= _kMaxPrice
                        ? '${Formatx.money(_kMaxPrice)}+'
                        : Formatx.money(draft.end),
                  ),
                  onChanged: (v) => setSheet(() => draft = v),
                ),
                const SizedBox(height: 4),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: AppColors.primary,
                  title: const Text('In stock only'),
                  value: inStock,
                  onChanged: (v) => setSheet(() => inStock = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: AppColors.primary,
                  title: const Text('On offer'),
                  value: onOffer,
                  onChanged: (v) => setSheet(() => onOffer = v),
                ),
                if (brands.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('Brand',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: brands
                        .map((b) => ChoiceChip(
                              label: Text('${b.name} (${b.count})'),
                              selected: draftBrand == b.id,
                              onSelected: (sel) =>
                                  setSheet(() => draftBrand = sel ? b.id : null),
                              selectedColor:
                                  AppColors.primary.withValues(alpha: 0.15),
                            ))
                        .toList(),
                  ),
                ],
                const SizedBox(height: 12),
                const Text('Product label',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _kLabels.entries
                      .map((e) => ChoiceChip(
                            label: Text(e.value),
                            selected: draftLabel == e.key,
                            onSelected: (sel) =>
                                setSheet(() => draftLabel = sel ? e.key : null),
                            selectedColor:
                                AppColors.primary.withValues(alpha: 0.15),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Apply'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (!mounted || applied != true) return;
    setState(() {
      _price = draft;
      _inStock = inStock;
      _onOffer = onOffer;
      _brand = draftBrand;
      _brandName = draftBrand == null
          ? null
          : brands.where((b) => b.id == draftBrand).firstOrNull?.name;
      _label = draftLabel;
    });
    await _reload();
  }

  void _clearSort() {
    setState(() => _sort = _Sort.featured);
    _reload();
  }

  void _clearPrice() {
    setState(() => _price = const RangeValues(0, _kMaxPrice));
    _reload();
  }

  void _clearInStock() {
    setState(() => _inStock = false);
    _reload();
  }

  void _clearOnOffer() {
    setState(() => _onOffer = false);
    _reload();
  }

  void _clearBrand() {
    setState(() { _brand = null; _brandName = null; });
    _reload();
  }

  void _clearLabel() {
    setState(() => _label = null);
    _reload();
  }

  String get _priceChipLabel {
    if (_hasMinPrice && _hasMaxPrice) {
      return '${Formatx.money(_price.start)}–${Formatx.money(_price.end)}';
    }
    if (_hasMaxPrice) return 'Under ${Formatx.money(_price.end)}';
    return 'Over ${Formatx.money(_price.start)}';
  }

  @override
  Widget build(BuildContext context) {
    final shopMode = widget.shopId != null;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: shopMode ? null : 0,
        title: shopMode
            ? Text(widget.title ?? 'Store', overflow: TextOverflow.ellipsis)
            : Padding(
                padding: const EdgeInsets.only(right: 12),
                child: TextField(
                  controller: _controller,
                  autofocus:
                      widget.initialQuery == null && widget.category == null,
                  textInputAction: TextInputAction.search,
                  maxLength: 100,
                  inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'[<>{}\\]'))],
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (v) {
                    final q = v.trim();
                    if (q.isNotEmpty) {
                      _q = q;
                      _showDiscovery = false;
                      _saveRecent(q);
                      _reload();
                    }
                  },
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: 'Search products',
                    prefixIcon: const Icon(Icons.search),
                    contentPadding: const EdgeInsets.symmetric(
                        vertical: 0, horizontal: 12),
                    suffixIcon: _controller.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              _controller.clear();
                              setState(() { _q = ''; _showDiscovery = true; });
                            },
                          ),
                  ),
                ),
              ),
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(
            shopMode
                ? (_anyActive ? 156 : 109)
                : (_anyActive ? 100 : 53),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (shopMode)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
                  child: TextField(
                    controller: _controller,
                    textInputAction: TextInputAction.search,
                    maxLength: 100,
                    inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'[<>{}\\]'))],
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (v) {
                      _q = v.trim();
                      _reload();
                    },
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: 'Search in store…',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 0, horizontal: 12),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      suffixIcon: _controller.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () {
                                _controller.clear();
                                _q = '';
                                _reload();
                              },
                            ),
                    ),
                  ),
                ),
              _SortFilterBar(
                sortLabel: _sort.label,
                sortActive: _sort != _Sort.featured,
                filtersActive: _priceActive || _inStock || _onOffer || _brand != null || _label != null,
                onSort: _openSort,
                onFilters: _openFilters,
                chips: _buildChips(),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const CartBar(),
      body: _siblings.isEmpty
          ? _buildResults()
          : Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SubCategoryRail(
                  categories: _siblings,
                  selectedSlug: _category,
                  onSelect: _selectCategory,
                ),
                Expanded(child: _buildResults()),
              ],
            ),
    );
  }

  /// The product grid (or its loading / empty / error states). Shared between
  /// the full-width search layout and the right pane of the category layout.
  Widget _buildResults() {
    if (_showDiscovery) return _buildDiscovery();
    if (_error != null && _items.isEmpty) {
      return ErrorView(error: _error!, onRetry: _reload);
    }
    if (_items.isEmpty && _loading) {
      return const ProductGridSkeleton();
    }
    if (_items.isEmpty) {
      return const EmptyView(
        title: 'No products found',
        subtitle: 'Try a different search.',
        type: EmptyType.search,
      );
    }
    return RefreshIndicator(
      onRefresh: _reload,
      child: GridView.builder(
        controller: _scroll,
        padding: const EdgeInsets.all(12),
        itemCount: _items.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          mainAxisExtent: 240,
        ),
        itemBuilder: (_, i) {
          final card = ProductCard(product: _items[i]);
          if (i < 8) {
            return card
                .animate()
                .fadeIn(delay: (i % 4 * 50).ms, duration: 220.ms)
                .slideY(begin: 0.06, duration: 220.ms, curve: Curves.easeOut);
          }
          return card;
        },
      ),
    );
  }

  List<Widget> _buildChips() {
    final chips = <Widget>[];
    if (_sort != _Sort.featured) {
      final arrow = _sort == _Sort.priceAsc
          ? ' ↑'
          : _sort == _Sort.priceDesc
              ? ' ↓'
              : '';
      chips.add(_FilterChipPill(label: 'Sort$arrow', onClear: _clearSort));
    }
    if (_priceActive) {
      chips.add(_FilterChipPill(label: _priceChipLabel, onClear: _clearPrice));
    }
    if (_inStock) {
      chips.add(_FilterChipPill(label: 'In stock', onClear: _clearInStock));
    }
    if (_onOffer) {
      chips.add(_FilterChipPill(label: 'On offer', onClear: _clearOnOffer));
    }
    if (_brand != null) {
      chips.add(_FilterChipPill(label: _brandName ?? 'Brand', onClear: _clearBrand));
    }
    if (_label != null) {
      final displayLabel = _label!.replaceAll('_', ' ');
      chips.add(_FilterChipPill(label: displayLabel, onClear: _clearLabel));
    }
    return chips;
  }

  Widget _buildDiscovery() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        if (_recent.isNotEmpty) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Recent searches', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              TextButton(
                onPressed: () async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.remove(_kRecentKey);
                  if (mounted) setState(() => _recent = const []);
                },
                style: TextButton.styleFrom(foregroundColor: AppColors.inkSoft, padding: const EdgeInsets.symmetric(horizontal: 4)),
                child: const Text('Clear all', style: TextStyle(fontSize: 13)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ...List.generate(_recent.length, (i) => Dismissible(
            key: Key(_recent[i]),
            direction: DismissDirection.endToStart,
            onDismissed: (_) => _removeRecent(_recent[i]),
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 16),
              child: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
            ),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.history_rounded, color: AppColors.inkSoft, size: 20),
              title: Text(_recent[i], style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              trailing: const Icon(Icons.north_west_rounded, color: AppColors.inkSoft, size: 16),
              onTap: () {
                _controller.text = _recent[i];
                _q = _recent[i];
                _showDiscovery = false;
                _saveRecent(_recent[i]);
                _reload();
              },
            ),
          )),
          const Divider(height: 24),
        ],
        const Text('Trending searches', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _kTrending.map((t) => ActionChip(
            label: Text(t),
            avatar: const Icon(Icons.trending_up_rounded, size: 14, color: AppColors.cta),
            backgroundColor: AppColors.ctaTint,
            side: BorderSide.none,
            labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            onPressed: () {
              _controller.text = t;
              _q = t;
              _showDiscovery = false;
              _saveRecent(t);
              _reload();
            },
          )).toList(),
        ),
      ],
    );
  }
}

/// Sticky bar under the AppBar: Sort + Filters controls plus active chips.
class _SortFilterBar extends StatelessWidget {
  const _SortFilterBar({
    required this.sortLabel,
    required this.sortActive,
    required this.filtersActive,
    required this.onSort,
    required this.onFilters,
    required this.chips,
  });

  final String sortLabel;
  final bool sortActive;
  final bool filtersActive;
  final VoidCallback onSort;
  final VoidCallback onFilters;
  final List<Widget> chips;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        boxShadow: AppShadows.soft,
      ),
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: _BarButton(
                    icon: Icons.swap_vert_rounded,
                    label: 'Sort',
                    active: sortActive,
                    onTap: onSort,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _BarButton(
                    icon: Icons.tune_rounded,
                    label: 'Filters',
                    active: filtersActive,
                    onTap: onFilters,
                  ),
                ),
              ],
            ),
          ),
          if (chips.isNotEmpty)
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                itemCount: chips.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) => chips[i],
              ),
            ),
        ],
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.primary : AppColors.ink;
    return ScaleTap(
      onTap: onTap,
      child: Container(
        height: 38,
        decoration: BoxDecoration(
          color: active ? AppColors.bgTint : AppColors.bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: active ? AppColors.primary : AppColors.line),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(fontWeight: FontWeight.w700, color: color)),
          ],
        ),
      ),
    );
  }
}

class _FilterChipPill extends StatelessWidget {
  const _FilterChipPill({required this.label, required this.onClear});
  final String label;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 12, right: 6),
      decoration: BoxDecoration(
        color: AppColors.bgTint,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                  color: AppColors.primaryDark)),
          const SizedBox(width: 2),
          InkResponse(
            onTap: onClear,
            radius: 16,
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.close, size: 14, color: AppColors.primaryDark),
            ),
          ),
        ],
      ),
    );
  }
}

/// Blinkit-style vertical rail of sibling sub-categories (left edge of the
/// category listing). Tapping a tile switches the active category.
class _SubCategoryRail extends StatelessWidget {
  const _SubCategoryRail({
    required this.categories,
    required this.selectedSlug,
    required this.onSelect,
  });

  final List<Category> categories;
  final String? selectedSlug;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 84,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        boxShadow: AppShadows.soft,
      ),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: categories.length,
        itemBuilder: (_, i) {
          final c = categories[i];
          // The "Top Picks" pseudo-entry (empty slug) is selected when no
          // category is active (selectedSlug == null).
          final selected = c.slug.isEmpty
              ? (selectedSlug == null || selectedSlug!.isEmpty)
              : c.slug == selectedSlug;
          return _RailItem(
            category: c,
            selected: selected,
            onTap: () => onSelect(c.slug),
          );
        },
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final Category category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ScaleTap(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: selected ? AppColors.bgTint : null,
          border: Border(
            left: BorderSide(
              color: selected ? AppColors.cta : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(7, 10, 9, 10),
        child: Column(
          children: [
            SizedBox(
              width: 50,
              height: 50,
              child: category.imageUrl.isEmpty
                  ? Container(
                      decoration: BoxDecoration(
                        color: AppColors.bgTint,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.category_rounded,
                          color: AppColors.primary, size: 22),
                    )
                  : AppImage(url: category.imageUrl, radius: 12),
            ),
            const SizedBox(height: 6),
            Text(
              category.name,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                height: 1.1,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: selected ? AppColors.primary : AppColors.inkSoft,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();
  @override
  Widget build(BuildContext context) => Container(
        width: 40,
        height: 4,
        margin: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.line,
          borderRadius: BorderRadius.circular(2),
        ),
      );
}
