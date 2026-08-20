import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The chosen delivery location. Persisted locally (non-sensitive) and sent to
/// the location-aware + deliverability APIs.
class DeliveryLocation {
  DeliveryLocation({
    required this.lat,
    required this.lng,
    this.label,
    this.line1,
    this.city,
    this.stateCode,
    this.pincode,
    this.formatted,
  });

  final double lat;
  final double lng;
  final String? label;
  final String? line1;
  final String? city;
  final String? stateCode;
  final String? pincode;
  final String? formatted;

  String get shortLabel => label ?? formatted ?? city ?? 'Selected location';

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lng': lng,
        'label': label,
        'line1': line1,
        'city': city,
        'state_code': stateCode,
        'pincode': pincode,
        'formatted': formatted,
      };

  factory DeliveryLocation.fromJson(Map<String, dynamic> j) => DeliveryLocation(
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        label: j['label'] as String?,
        line1: j['line1'] as String?,
        city: j['city'] as String?,
        stateCode: j['state_code'] as String?,
        pincode: j['pincode'] as String?,
        formatted: j['formatted'] as String?,
      );
}

class LocationProvider extends ChangeNotifier {
  static const _key = 'delivery_location';

  DeliveryLocation? _location;
  bool _ready = false;
  int? _nearestEtaMin;

  DeliveryLocation? get location => _location;
  bool get ready => _ready;
  bool get hasLocation => _location != null;

  /// Nearest shop ETA in minutes, updated whenever home data is loaded.
  int? get nearestEtaMin => _nearestEtaMin;

  void setNearestEta(int? etaMin) {
    if (_nearestEtaMin == etaMin) return;
    _nearestEtaMin = etaMin;
    notifyListeners();
  }

  Future<void> bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null) {
      try {
        _location = DeliveryLocation.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {}
    }
    _ready = true;
    notifyListeners();
  }

  Future<void> set(DeliveryLocation loc) async {
    _location = loc;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(loc.toJson()));
    notifyListeners();
  }

  /// Detect the device location (requests permission). Throws on denial.
  Future<DeliveryLocation> detectCurrent() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw Exception('Location services are disabled.');
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      throw Exception('Location permission denied.');
    }
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
    return DeliveryLocation(lat: pos.latitude, lng: pos.longitude, label: 'Current location');
  }
}
