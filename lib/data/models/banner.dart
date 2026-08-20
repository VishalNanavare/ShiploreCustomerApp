import '../../../core/utils/formatx.dart';

class HomeBanner {
  const HomeBanner({
    required this.id,
    required this.title,
    this.subtitle,
    this.imageUrl,
    this.targetUrl,
  });

  final int id;
  final String title;
  final String? subtitle;
  final String? imageUrl;
  final String? targetUrl;

  factory HomeBanner.fromJson(Map<String, dynamic> j) => HomeBanner(
        id: Formatx.toInt(j['id']),
        title: (j['title'] as String?) ?? '',
        subtitle: j['subtitle'] as String?,
        imageUrl: j['image_url'] as String?,
        targetUrl: j['target_url'] as String?,
      );
}
