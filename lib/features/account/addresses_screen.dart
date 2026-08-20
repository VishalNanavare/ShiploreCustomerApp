import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../../core/config/app_config.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/address.dart';
import '../../data/repositories/address_repository.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/app_scale_tap.dart';
import '../../widgets/states.dart';

class AddressesScreen extends StatefulWidget {
  const AddressesScreen({super.key});
  @override
  State<AddressesScreen> createState() => _AddressesScreenState();
}

class _AddressesScreenState extends State<AddressesScreen> {
  late Future<List<Address>> _future;
  // Tracks which address is currently being set as default (shows inline loader).
  int? _settingDefaultId;

  @override
  void initState() {
    super.initState();
    _future = context.read<AddressRepository>().list();
  }

  void _reload() => setState(() {
        _future = context.read<AddressRepository>().list();
      });

  Future<void> _openForm([Address? existing]) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => _AddressMapPicker(existing: existing)),
    );
    if (saved == true) _reload();
  }

  Future<void> _setDefault(Address a) async {
    if (_settingDefaultId != null) return;
    setState(() => _settingDefaultId = a.id);
    try {
      // PUT requires the full body — sending only is_default triggers
      // server-side validation errors for required fields like recipient_name.
      await context.read<AddressRepository>().update(a.id, {
        'label': a.label,
        'recipient_name': a.recipientName ?? '',
        'phone': a.phone ?? '',
        'line1': a.line1,
        'line2': a.line2 ?? '',
        'city': a.city ?? '',
        'state_code': a.stateCode ?? '',
        'pincode': a.pincode ?? '',
        'formatted_address': a.formattedAddress ?? '',
        'latitude': a.latitude,
        'longitude': a.longitude,
        'is_default': true,
      });
      if (!mounted) return;
      showSnack(context, '${a.label} set as default address');
      _reload();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _settingDefaultId = null);
    }
  }

  Future<void> _delete(Address a) async {
    final repo = context.read<AddressRepository>();
    final ok = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.delete_outline_rounded,
                    color: AppColors.danger, size: 28),
              ),
              const SizedBox(height: 16),
              const Text(
                'Delete address?',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                '${a.label} · ${a.oneLine}',
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.inkSoft,
                    height: 1.45),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.ink,
                        side: const BorderSide(color: AppColors.line),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Cancel',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.danger,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Delete',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (ok != true) return;
    try {
      await repo.remove(a.id);
      if (!mounted) return;
      showSnack(context, 'Address deleted');
      _reload();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved addresses'),
        leading: BackButton(onPressed: () => context.canPop() ? context.pop() : context.go('/account')),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('Add address'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<List<Address>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const LoadingView();
          }
          if (snap.hasError) {
            return ErrorView(error: snap.error!, onRetry: _reload);
          }
          final list = snap.data!;
          if (list.isEmpty) {
            return const EmptyView(
              title: 'No saved addresses',
              subtitle: 'Add one to check out faster.',
              icon: Icons.location_on_outlined,
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              final a = list[i];
              final isSetting = _settingDefaultId == a.id;
              return Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: a.isDefault
                        ? AppColors.primary.withValues(alpha: 0.5)
                        : AppColors.line,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 6, 0),
                      child: Row(
                        children: [
                          Text(a.label,
                              style: const TextStyle(fontWeight: FontWeight.w800)),
                          const SizedBox(width: 8),
                          if (a.isDefault)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Text('Default',
                                  style: TextStyle(
                                      color: AppColors.primary,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800)),
                            ),
                          if (a.latitude == null) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.warnSurface,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: AppColors.warnBorder),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.location_off_rounded,
                                      size: 10, color: AppColors.warnText),
                                  SizedBox(width: 3),
                                  Text('No pin',
                                      style: TextStyle(
                                          color: AppColors.warnText,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700)),
                                ],
                              ),
                            ),
                          ],
                          const Spacer(),
                          IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.edit_outlined, size: 20),
                              onPressed: () => _openForm(a)),
                          IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.delete_outline,
                                  size: 20, color: AppColors.danger),
                              onPressed: () => _delete(a)),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
                      child: Text(a.oneLine,
                          style: const TextStyle(color: AppColors.inkSoft)),
                    ),
                    if ((a.recipientName ?? '').isNotEmpty ||
                        (a.phone ?? '').isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 3, 14, 0),
                        child: Text(
                          '${a.recipientName ?? ''} ${a.phone ?? ''}'.trim(),
                          style: const TextStyle(
                              color: AppColors.inkSoft, fontSize: 12),
                        ),
                      ),
                    if (!a.isDefault) ...[
                      const Padding(
                        padding: EdgeInsets.fromLTRB(14, 10, 14, 0),
                        child: Divider(height: 1, color: AppColors.line),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
                        child: isSetting
                            ? const Padding(
                                padding: EdgeInsets.symmetric(vertical: 10),
                                child: Center(
                                  child: SizedBox(
                                    height: 16,
                                    width: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  ),
                                ),
                              )
                            : TextButton.icon(
                                onPressed: _settingDefaultId != null
                                    ? null
                                    : () => _setDefault(a),
                                icon: const Icon(Icons.check_circle_outline,
                                    size: 16),
                                label: const Text('Use as default address'),
                                style: TextButton.styleFrom(
                                  foregroundColor: AppColors.primary,
                                  textStyle: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600),
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                      ),
                    ] else
                      const SizedBox(height: 12),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ─── Map-based address picker ─────────────────────────────────────────────────

class _AddressMapPicker extends StatefulWidget {
  const _AddressMapPicker({this.existing});
  final Address? existing;

  @override
  State<_AddressMapPicker> createState() => _AddressMapPickerState();
}

class _AddressMapPickerState extends State<_AddressMapPicker> {
  static const _fallback = LatLng(19.0760, 72.8777);

  late LatLng _center;
  GoogleMapController? _mapCtrl;
  final _dio = Dio();

  // Runtime Maps API key: starts from dart-define, falls back to native
  // Info.plist value read via MethodChannel so no re-build is needed.
  String _mapsApiKey = AppConfig.googleMapsApiKey;

  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  Timer? _searchDebounce;
  Timer? _geocodeDebounce;

  List<Map<String, dynamic>> _suggestions = [];
  // Session token groups autocomplete+detail into one billing session.
  String _sessionToken = '';
  bool _searching = false;
  bool _locating = false;
  bool _resolving = false;
  bool _showSuggestions = false;

  // Reverse-geocoded address shown on the bottom card
  String _formatted = '';

  // Auto-filled fields (from map / Places API)
  final _line1 = TextEditingController();
  final _city = TextEditingController();
  final _state = TextEditingController(text: '27');
  final _pincode = TextEditingController();

  // User-entered fields
  late final TextEditingController _name;
  late final TextEditingController _phone;

  static const _labels = ['Home', 'Work', 'Other'];
  late String _selectedLabel;
  bool _default = false;
  bool _busy = false;
  bool _mapMoving = false;

  // Approximate height of the bottom form sheet (drag-handle → save button +
  // iOS home-indicator safe area). Used to centre the map pin in the visible
  // map area and to shift the GoogleMap camera reference so _center stays in
  // sync with what the user sees the pin pointing at.
  static const _kSheetH = 440.0;

  Future<void> _initMapsKey() async {
    try {
      final k = await const MethodChannel('com.shiplore/config')
          .invokeMethod<String>('getMapsApiKey') ?? '';
      if (mounted && k.isNotEmpty) setState(() => _mapsApiKey = k);
    } catch (_) {
      // Channel not available — Places search will silently not fire.
    }
  }

  @override
  void initState() {
    super.initState();
    if (_mapsApiKey.isEmpty) _initMapsKey();
    final a = widget.existing;
    final user = context.read<AuthProvider>().user;

    _center = (a?.latitude != null && a?.longitude != null)
        ? LatLng(a!.latitude!, a.longitude!)
        : _fallback;

    _name = TextEditingController(
        text: a?.recipientName ?? user?.name ?? '');
    _phone = TextEditingController(
        text: a?.phone ?? user?.phone ?? '');
    _line1.text = a?.line1 ?? '';
    _city.text = a?.city ?? '';
    _state.text = a?.stateCode ?? '27';
    _pincode.text = a?.pincode ?? '';
    _formatted = a?.formattedAddress ?? '';

    final lbl = a?.label ?? 'Home';
    _selectedLabel = _labels.contains(lbl) ? lbl : 'Other';
    _default = a?.isDefault ?? false;

    WidgetsBinding.instance
        .addPostFrameCallback((_) => _reverseGeocode(_center));
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _geocodeDebounce?.cancel();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _line1.dispose();
    _city.dispose();
    _state.dispose();
    _pincode.dispose();
    _name.dispose();
    _phone.dispose();
    _mapCtrl?.dispose();
    super.dispose();
  }

  // ── Places Autocomplete ──────────────────────────────────────────────────

  void _onSearchChanged(String q) {
    _searchDebounce?.cancel();
    if (q.trim().length < 3) {
      setState(() {
        _suggestions = [];
        _showSuggestions = false;
      });
      return;
    }
    _searchDebounce = Timer(
      const Duration(milliseconds: 400),
      () => _fetchSuggestions(q.trim()),
    );
  }

  Future<void> _fetchSuggestions(String query) async {
    final key = _mapsApiKey;
    if (key.isEmpty) return;
    if (_sessionToken.isEmpty) {
      _sessionToken = DateTime.now().millisecondsSinceEpoch.toString();
    }
    if (mounted) setState(() => _searching = true);
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        'https://maps.googleapis.com/maps/api/place/autocomplete/json',
        queryParameters: {
          'input': query,
          'key': key,
          // No 'types' filter — allows establishments, roads, areas.
          'components': 'country:in',
          'language': 'en',
          'location': '${_center.latitude},${_center.longitude}',
          'radius': '50000',
          'sessiontoken': _sessionToken,
        },
        options: Options(receiveTimeout: const Duration(seconds: 5)),
      );
      if (!mounted) return;
      final status = res.data?['status'] as String? ?? '';
      final preds = (res.data?['predictions'] as List?) ?? [];
      if (status != 'OK' && status != 'ZERO_RESULTS' && status.isNotEmpty) {
        // Places API returned an error (e.g. REQUEST_DENIED, billing not enabled).
        // Show a hint so user knows to use the map pin instead.
        setState(() { _searching = false; _showSuggestions = false; });
        showSnack(context, 'Address search unavailable — move the pin to set your location.', error: true);
        return;
      }
      setState(() {
        _suggestions = preds.cast<Map<String, dynamic>>().take(5).toList();
        _showSuggestions = _suggestions.isNotEmpty;
        _searching = false;
      });
    } catch (_) {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _selectSuggestion(Map<String, dynamic> pred) async {
    final placeId = pred['place_id'] as String?;
    if (placeId == null) return;
    _searchCtrl.text =
        (pred['structured_formatting']?['main_text'] as String?) ??
            (pred['description'] as String? ?? '');
    setState(() {
      _showSuggestions = false;
      _suggestions = [];
      _searching = true;
    });
    _searchFocus.unfocus();
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        'https://maps.googleapis.com/maps/api/place/details/json',
        queryParameters: {
          'place_id': placeId,
          'fields': 'geometry,address_components,formatted_address',
          'key': _mapsApiKey,
          'sessiontoken': _sessionToken,
        },
        options: Options(receiveTimeout: const Duration(seconds: 5)),
      );
      final result = res.data?['result'] as Map<String, dynamic>?;
      final loc = result?['geometry']?['location'];
      if (loc != null) {
        final target = LatLng(
          (loc['lat'] as num).toDouble(),
          (loc['lng'] as num).toDouble(),
        );
        if (!mounted) return;
        _center = target;
        _line1.clear();
        _city.clear();
        _pincode.clear();
        final components = (result?['address_components'] as List?) ?? [];
        final formatted =
            (result?['formatted_address'] as String?) ?? '';
        if (components.isNotEmpty) {
          _applyComponents(components, formatted, overwrite: true);
        }
        await _mapCtrl?.animateCamera(
            CameraUpdate.newLatLngZoom(target, 16));
        await _reverseGeocode(target);
      }
    } catch (_) {
      // fall through
    } finally {
      // Reset session token — next autocomplete session gets a fresh one.
      _sessionToken = '';
      if (mounted) setState(() => _searching = false);
    }
  }

  // ── GPS ─────────────────────────────────────────────────────────────────

  Future<void> _goToMyLocation() async {
    setState(() => _locating = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        throw Exception('denied');
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      if (!mounted) return;
      final target = LatLng(pos.latitude, pos.longitude);
      _center = target;
      await _mapCtrl?.animateCamera(
          CameraUpdate.newLatLngZoom(target, 16));
      await _reverseGeocode(target);
    } catch (_) {
      if (mounted) {
        showSnack(context, 'Could not detect location. Enable GPS & permission.',
            error: true);
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  // ── Reverse geocode ──────────────────────────────────────────────────────

  void _onCameraIdle() {
    setState(() => _mapMoving = false);
    _geocodeDebounce?.cancel();
    _geocodeDebounce = Timer(
      const Duration(milliseconds: 600),
      () => _reverseGeocode(_center),
    );
  }

  /// Reverse geocode via native OS (iOS CLGeocoder / Android Geocoder) —
  /// no API key needed. Used as primary path when key is empty and as
  /// fallback when the Google Geocoding API fails.
  Future<void> _reverseGeocodeNative(LatLng point) async {
    if (mounted && !_resolving) setState(() => _resolving = true);
    try {
      final marks = await placemarkFromCoordinates(point.latitude, point.longitude);
      if (!mounted || marks.isEmpty) return;
      final p = marks.first;
      final streetNum = p.subThoroughfare ?? '';
      final street = p.thoroughfare ?? '';
      final sub = p.subLocality ?? '';
      final l1 = [streetNum, street].where((s) => s.isNotEmpty).join(' ');
      final city = p.locality ?? p.subAdministrativeArea ?? '';
      final state = p.administrativeArea ?? '';
      final pin = (p.postalCode ?? '').replaceAll(RegExp(r'[^0-9]'), '');
      final formattedParts = [l1.isNotEmpty ? l1 : sub, city, state]
          .where((s) => s.isNotEmpty);
      final formatted = formattedParts.join(', ');
      if (!mounted) return;
      setState(() {
        if (formatted.isNotEmpty) _formatted = formatted;
        if ((l1.isNotEmpty || sub.isNotEmpty) && _line1.text.trim().isEmpty) {
          _line1.text = l1.isNotEmpty ? l1 : sub;
        }
        if (city.isNotEmpty && _city.text.trim().isEmpty) _city.text = city;
        if (pin.length == 6 && _pincode.text.trim().isEmpty) _pincode.text = pin;
      });
    } catch (_) {
      // Native geocoding is best-effort.
    } finally {
      if (mounted && _resolving) setState(() => _resolving = false);
    }
  }

  Future<void> _reverseGeocode(LatLng point) async {
    final key = _mapsApiKey;
    if (key.isEmpty) {
      return _reverseGeocodeNative(point);
    }
    if (mounted && !_resolving) setState(() => _resolving = true);
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        'https://maps.googleapis.com/maps/api/geocode/json',
        queryParameters: {
          'latlng': '${point.latitude},${point.longitude}',
          'key': key,
          'region': 'in',
          'language': 'en',
        },
        options: Options(receiveTimeout: const Duration(seconds: 5)),
      );
      if (!mounted) return;
      final status = res.data?['status'] as String? ?? '';
      final results = (res.data?['results'] as List?) ?? [];
      if (results.isNotEmpty && (status == 'OK' || status.isEmpty)) {
        final first = results.first as Map<String, dynamic>;
        _applyComponents(
          (first['address_components'] as List?) ?? [],
          (first['formatted_address'] as String?) ?? '',
          overwrite: false,
        );
      } else {
        // Geocoding API not available — fall back to native OS geocoding.
        await _reverseGeocodeNative(point);
      }
    } catch (_) {
      await _reverseGeocodeNative(point);
    } finally {
      if (mounted && _resolving) setState(() => _resolving = false);
    }
  }

  void _applyComponents(
    List<dynamic> components,
    String formatted, {
    required bool overwrite,
  }) {
    String city = '', pincode = '', route = '', streetNum = '',
        sublocality = '';
    for (final c in components.cast<Map>()) {
      final types = (c['types'] as List).cast<String>();
      final long = c['long_name'] as String? ?? '';
      if (types.contains('postal_code')) {
        pincode = long.replaceAll(RegExp(r'[^0-9]'), '');
      }
      if (types.contains('locality')) city = long;
      if (city.isEmpty &&
          types.contains('administrative_area_level_2')) { city = long; }
      if (types.contains('route')) route = long;
      if (types.contains('street_number')) streetNum = long;
      if (sublocality.isEmpty && types.contains('sublocality')) {
        sublocality = long;
      }
    }
    final line1 =
        [streetNum, route].where((s) => s.isNotEmpty).join(', ');
    final l1 = line1.isNotEmpty ? line1 : sublocality;
    if (!mounted) return;
    setState(() {
      if (formatted.isNotEmpty) _formatted = formatted;
      if (pincode.length == 6 &&
          (overwrite || _pincode.text.trim().isEmpty)) {
        _pincode.text = pincode;
      }
      if (city.isNotEmpty &&
          (overwrite || _city.text.trim().isEmpty)) {
        _city.text = city;
      }
      if (l1.isNotEmpty &&
          (overwrite || _line1.text.trim().isEmpty)) {
        _line1.text = l1;
      }
    });
  }

  // ── Save ─────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      showSnack(context, 'Recipient name is required', error: true);
      return;
    }
    if (_busy) return;

    final pin =
        _pincode.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (pin.isNotEmpty && pin.length != 6) {
      showSnack(context, 'Pincode must be 6 digits', error: true);
      return;
    }

    final line1 = _line1.text.trim();
    final city = _city.text.trim();
    final formatted = _formatted.isNotEmpty
        ? _formatted
        : [line1, city, pin].where((s) => s.isNotEmpty).join(', ');

    setState(() => _busy = true);
    try {
      final body = {
        'label': _selectedLabel,
        'recipient_name': _name.text.trim(),
        'phone': _phone.text.trim(),
        'line1': line1,
        'line2': '',
        'city': city,
        'state_code': _state.text.trim(),
        'pincode': pin,
        'formatted_address': formatted,
        'latitude': _center.latitude,
        'longitude': _center.longitude,
        'is_default': _default,
      };
      final repo = context.read<AddressRepository>();
      if (widget.existing != null) {
        await repo.update(widget.existing!.id, body);
      } else {
        await repo.add(body);
      }
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition:
                CameraPosition(target: _center, zoom: 16),
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            // Tell the map that the bottom _kSheetH pixels are obscured so the
            // camera's reference point (target) sits at the centre of the
            // visible map area, keeping _center in sync with the pin position.
            padding: const EdgeInsets.only(bottom: _kSheetH),
            onMapCreated: (ctrl) => _mapCtrl = ctrl,
            onCameraMove: (pos) => _center = pos.target,
            onCameraMoveStarted: () => setState(() => _mapMoving = true),
            onCameraIdle: _onCameraIdle,
            onTap: (_) {
              if (_showSuggestions || _searchFocus.hasFocus) {
                setState(() => _showSuggestions = false);
                _searchFocus.unfocus();
              }
            },
          ),
          _buildCenterPin(),
          _buildSearchOverlay(),
          _buildGpsFab(),
          _buildBottomSheet(),
        ],
      ),
    );
  }

  Widget _buildCenterPin() {
    // Positioned.fill with bottom: _kSheetH constrains the centering to the
    // visible map area (above the bottom sheet), so the pin tip sits at the
    // camera target rather than at the full-screen centre.
    return Positioned.fill(
      bottom: _kSheetH,
      child: IgnorePointer(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 63),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_resolving)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.ink,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Finding address…',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  curve: Curves.easeOut,
                  transform:
                      Matrix4.translationValues(0, _mapMoving ? -6 : 0, 0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.45),
                              blurRadius: _mapMoving ? 18 : 10,
                              spreadRadius: _mapMoving ? 3 : 1,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Container(
                            width: 14,
                            height: 14,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                      CustomPaint(
                        size: const Size(18, 14),
                        painter: _PinStemPainter(AppColors.primary),
                      ),
                    ],
                  ),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  curve: Curves.easeOut,
                  width: _mapMoving ? 6 : 12,
                  height: _mapMoving ? 3 : 5,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchOverlay() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: AppShadows.card,
                ),
                child: TextField(
                  controller: _searchCtrl,
                  focusNode: _searchFocus,
                  onChanged: _onSearchChanged,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search area, street, landmark…',
                    filled: false,
                    prefixIcon: IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => Navigator.pop(context),
                    ),
                    suffixIcon: _searching
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2),
                            ),
                          )
                        : _searchCtrl.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  setState(() {
                                    _suggestions = [];
                                    _showSuggestions = false;
                                  });
                                },
                              )
                            : null,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 14),
                  ),
                ),
              ),
            ),
            if (_showSuggestions)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: AppShadows.card,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: ListView.separated(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _suggestions.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1, color: AppColors.line),
                      itemBuilder: (_, i) {
                        final s = _suggestions[i];
                        final main = (s['structured_formatting']
                                    ?['main_text'] as String?) ??
                            (s['description'] as String? ?? '');
                        final secondary = s['structured_formatting']
                                ?['secondary_text'] as String? ??
                            '';
                        return ScaleTap(
                          onTap: () => _selectSuggestion(s),
                          child: ListTile(
                            dense: true,
                            leading: const Icon(
                                Icons.location_on_outlined,
                                size: 20,
                                color: AppColors.primary),
                            title: Text(main,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            subtitle: secondary.isNotEmpty
                                ? Text(secondary,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis)
                                : null,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildGpsFab() {
    return Positioned(
      right: 16,
      bottom: _kSheetH + 12,
      child: ScaleTap(
        onTap: _locating ? null : _goToMyLocation,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.surface,
            shape: BoxShape.circle,
            boxShadow: AppShadows.card,
          ),
          child: _locating
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.my_location, color: AppColors.primary),
        ),
      ),
    );
  }

  Widget _buildBottomSheet() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: AppShadows.card,
        ),
        child: SafeArea(
          top: false,
          child: Material(
            color: Colors.transparent,
            child: Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              12,
              16,
              MediaQuery.of(context).viewInsets.bottom + 12,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // drag handle
                  Center(
                    child: Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.line,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // address card
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.bgTint,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.location_pin,
                            color: AppColors.primary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Delivering to',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.inkSoft,
                                  letterSpacing: 0.3,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _resolving && _formatted.isEmpty
                                    ? 'Finding address…'
                                    : (_formatted.isEmpty
                                        ? 'Move the map to set your spot'
                                        : _formatted),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.ink,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // label chips
                  Row(
                    children: _labels.map((lbl) {
                      final selected = _selectedLabel == lbl;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ScaleTap(
                          onTap: () =>
                              setState(() => _selectedLabel = lbl),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: selected
                                  ? AppColors.primary
                                  : AppColors.bgTint,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: selected
                                    ? AppColors.primary
                                    : AppColors.line,
                              ),
                            ),
                            child: Text(
                              lbl,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: selected
                                    ? Colors.white
                                    : AppColors.inkSoft,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),

                  // name + phone row
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _name,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'Name',
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _phone,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'Mobile',
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // flat / house / street — auto-filled from map, user can edit
                  TextField(
                    controller: _line1,
                    decoration: const InputDecoration(
                      labelText: 'Flat / House / Street',
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 4),

                  // default toggle
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _default,
                    activeThumbColor: AppColors.primary,
                    onChanged: (v) => setState(() => _default = v),
                    title: const Text(
                      'Set as default address',
                      style: TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                  ),

                  // save button
                  ElevatedButton(
                    onPressed: _busy ? null : _save,
                    child: _busy
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : Text(widget.existing == null
                            ? 'Save address'
                            : 'Update address'),
                  ),
                ],
              ),
            ),
          ),
        ),
        ),
      ),
    );
  }
}

/// Draws the tapered triangle stem of the map pin.
class _PinStemPainter extends CustomPainter {
  final Color color;
  const _PinStemPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      Path()
        ..moveTo(0, 0)
        ..lineTo(size.width / 2, size.height)
        ..lineTo(size.width, 0)
        ..close(),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_PinStemPainter old) => old.color != color;
}
