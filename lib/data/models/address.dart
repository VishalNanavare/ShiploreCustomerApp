import '../../core/utils/formatx.dart';

/// A saved customer delivery address (customer_addresses).
class Address {
  Address({
    required this.id,
    required this.label,
    this.recipientName,
    this.phone,
    required this.line1,
    this.line2,
    this.city,
    this.stateCode,
    this.pincode,
    this.formattedAddress,
    this.latitude,
    this.longitude,
    this.isDefault = false,
  });

  final int id;
  final String label;
  final String? recipientName;
  final String? phone;
  final String line1;
  final String? line2;
  final String? city;
  final String? stateCode;
  final String? pincode;
  final String? formattedAddress;
  final double? latitude;
  final double? longitude;
  final bool isDefault;

  String get oneLine {
    final parts = [line1, line2, city, pincode].where((p) => (p ?? '').trim().isNotEmpty).toList();
    return formattedAddress?.isNotEmpty == true ? formattedAddress! : parts.join(', ');
  }

  factory Address.fromJson(Map<String, dynamic> j) => Address(
        id: Formatx.toInt(j['id']),
        label: (j['label'] ?? 'Home').toString(),
        recipientName: j['recipient_name']?.toString(),
        phone: j['phone']?.toString(),
        line1: (j['line1'] ?? '').toString(),
        line2: j['line2']?.toString(),
        city: j['city']?.toString(),
        stateCode: j['state_code']?.toString(),
        pincode: j['pincode']?.toString(),
        formattedAddress: j['formatted_address']?.toString(),
        latitude: j['latitude'] == null ? null : Formatx.toDouble(j['latitude']),
        longitude: j['longitude'] == null ? null : Formatx.toDouble(j['longitude']),
        isDefault: Formatx.toInt(j['is_default']) == 1,
      );
}
