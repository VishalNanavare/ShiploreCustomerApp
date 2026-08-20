import 'dart:convert';

/// The authenticated account (from the auth envelope's `user`).
class AppUser {
  AppUser({
    required this.id,
    required this.name,
    required this.principalType,
    this.email,
    this.phone,
  });

  final int id;
  final String name;
  final String principalType;
  final String? email;
  final String? phone;

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: int.tryParse('${j['id']}') ?? 0,
        name: (j['name'] ?? '').toString(),
        principalType: (j['principal_type'] ?? 'customer').toString(),
        email: j['email']?.toString(),
        phone: j['phone']?.toString(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'principal_type': principalType,
        'email': email,
        'phone': phone,
      };

  AppUser copyWith({String? name, String? email}) => AppUser(
        id: id,
        name: name ?? this.name,
        principalType: principalType,
        email: email ?? this.email,
        phone: phone,
      );

  String encode() => jsonEncode(toJson());
  static AppUser? decode(String? s) {
    if (s == null || s.isEmpty) return null;
    try {
      return AppUser.fromJson(jsonDecode(s) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }
}
