import '../../core/network/api_client.dart';
import '../models/banner.dart';
import '../models/catalog.dart';
import '../models/product.dart';

typedef HomeData = ({
  List<Category> categories,
  List<Shop> shops,
  List<Product> products,
  List<HomeBanner> banners,
  bool isScoped, // true when lat/lng were sent and backend filtered by shop radius
});
typedef ProductsPage = ({List<Product> items, int total, int page, int pages});

class CatalogRepository {
  CatalogRepository(this._api);
  final ApiClient _api;

  // --- Session-level TTL caches (persist while the singleton lives) ---
  List<Category>? _catCache;
  DateTime? _catAt;
  static const _catTtl = Duration(minutes: 5);

  HomeData? _homeGlobalCache;
  DateTime? _homeGlobalAt;
  static const _homeTtl = Duration(seconds: 60);

  List<Shop>? _shopsCache;
  DateTime? _shopsAt;
  static const _shopsTtl = Duration(seconds: 60);

  final Map<int, List<Category>> _shopCatCache = {};
  final Map<int, DateTime> _shopCatAt = {};
  static const _shopCatTtl = Duration(minutes: 5);
  // --------------------------------------------------------------------

  List<T> _list<T>(dynamic raw, T Function(Map<String, dynamic>) f) =>
      ((raw as List?) ?? const []).map((e) => f((e as Map).cast<String, dynamic>())).toList();

  Map<String, dynamic> _geo(double? lat, double? lng) =>
      (lat != null && lng != null) ? {'lat': lat, 'lng': lng} : {};

  Future<HomeData> home({double? lat, double? lng}) async {
    final global = lat == null || lng == null;
    if (global &&
        _homeGlobalCache != null &&
        DateTime.now().difference(_homeGlobalAt!) < _homeTtl) {
      return _homeGlobalCache!;
    }
    final data = await _api.get('/customer/home', query: _geo(lat, lng)) as Map;
    final loc = (data['location'] as Map?)?.cast<String, dynamic>() ?? const {};
    final result = (
      categories: _list(data['categories'], Category.fromJson),
      shops: _list(data['shops'], Shop.fromJson),
      products: _list(data['products'], Product.fromJson),
      banners: _list(data['banners'], HomeBanner.fromJson),
      isScoped: (loc['scoped'] as bool?) ?? false,
    );
    if (global) {
      _homeGlobalCache = result;
      _homeGlobalAt = DateTime.now();
    }
    return result;
  }

  Future<ProductsPage> products({
    String? q,
    String? category,
    String? sort,
    double? minPrice,
    double? maxPrice,
    bool inStock = false,
    bool onOffer = false,
    int? shopId,
    int? vendorId,
    int? brand,
    String? label,
    int page = 1,
    double? lat,
    double? lng,
  }) async {
    final res = await _api.getPage('/customer/products', query: {
      if ((q ?? '').isNotEmpty) 'q': q,
      if ((category ?? '').isNotEmpty) 'category': category,
      if ((sort ?? '').isNotEmpty) 'sort': sort,
      'min_price': ?minPrice,
      'max_price': ?maxPrice,
      if (inStock) 'in_stock': '1',
      if (onOffer) 'on_offer': '1',
      'shop_id': ?shopId,
      'vendor_id': ?vendorId,
      if (brand != null) 'brand': '$brand',
      if ((label ?? '').isNotEmpty) 'label': label,
      'page': page,
      ..._geo(lat, lng),
    });
    final pg = (res.meta['pagination'] as Map?)?.cast<String, dynamic>() ?? const {};
    return (
      items: _list(res.data, Product.fromJson),
      total: (pg['total'] as num?)?.toInt() ?? 0,
      page: (pg['page'] as num?)?.toInt() ?? page,
      pages: (pg['pages'] as num?)?.toInt() ?? 1,
    );
  }

  /// Full active category tree (for the grouped Categories tab). Cached for 5 min.
  Future<List<Category>> categories() async {
    if (_catCache != null && DateTime.now().difference(_catAt!) < _catTtl) {
      return _catCache!;
    }
    final data = await _api.get('/customer/categories');
    _catCache = _list(data, Category.fromJson);
    _catAt = DateTime.now();
    return _catCache!;
  }

  /// Categories that have products in a given shop (for the shop page's left rail). Cached per shop for 5 min.
  Future<List<Category>> shopCategories(int shopId) async {
    final at = _shopCatAt[shopId];
    if (_shopCatCache.containsKey(shopId) &&
        at != null &&
        DateTime.now().difference(at) < _shopCatTtl) {
      return _shopCatCache[shopId]!;
    }
    final data = await _api.get('/customer/shop-categories', query: {'shop_id': shopId});
    final result = _list(data, Category.fromJson);
    _shopCatCache[shopId] = result;
    _shopCatAt[shopId] = DateTime.now();
    return result;
  }

  Future<ProductDetail> product(String slug) async {
    final data = await _api.get('/customer/product/$slug') as Map;
    return ProductDetail.fromJson(data.cast<String, dynamic>());
  }

  Future<void> submitReview(int productId, int rating, String title, String body) =>
      _api.post('/customer/products/$productId/review',
          body: {'rating': rating, 'title': title, 'body': body});

  Future<List<({int id, String name, int count})>> brands({String? category}) async {
    final data = await _api.get('/customer/brands', query: {
      if ((category ?? '').isNotEmpty) 'category': category,
    }) as List?;
    return ((data ?? []) as List).map((e) {
      final m = (e as Map).cast<String, dynamic>();
      return (id: (m['id'] as num).toInt(), name: m['name'] as String, count: (m['cnt'] as num? ?? 0).toInt());
    }).toList();
  }

  /// Nearby shops. Global (no-location) calls cached for 60 s; location-specific calls bypass cache.
  Future<List<Shop>> shops({double? lat, double? lng}) async {
    final global = lat == null || lng == null;
    if (global &&
        _shopsCache != null &&
        DateTime.now().difference(_shopsAt!) < _shopsTtl) {
      return _shopsCache!;
    }
    final res = await _api.getPage('/customer/shops', query: _geo(lat, lng));
    final result = _list(res.data, Shop.fromJson);
    if (global) {
      _shopsCache = result;
      _shopsAt = DateTime.now();
    }
    return result;
  }
}
