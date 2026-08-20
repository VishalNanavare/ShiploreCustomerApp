import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/location_provider.dart';
import '../../widgets/app_scale_tap.dart';
import '../../widgets/states.dart';

/// Blinkit-style single-screen delivery-point picker: a full-screen map with a
/// fixed center pin (the map moves under it), India-biased Places search, a GPS
/// button, a live reverse-geocoded address card, and an expandable details
/// sheet. Self-contained — it persists the choice via [LocationProvider] and
/// then pops (or routes home when launched as the first-run gate).
class MapPickerScreen extends StatefulWidget {
  const MapPickerScreen({super.key, this.initial});
  final LatLng? initial;

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  static const _fallback = LatLng(19.0760, 72.8777); // Mumbai

  // Runtime Maps API key: starts from dart-define, falls back to native
  // Info.plist value read via MethodChannel so no re-build is needed.
  String _mapsApiKey = AppConfig.googleMapsApiKey;
  bool _mapsKeyLoaded = AppConfig.googleMapsApiKey.isNotEmpty;

  // Plain field — mutated in onCameraMove WITHOUT setState to keep panning
  // perfectly smooth. setState only fires when the resolved address changes.
  late LatLng _center = widget.initial ?? _fallback;
  GoogleMapController? _mapCtrl;
  final _dio = Dio();

  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  Timer? _searchDebounce;
  Timer? _geocodeDebounce;

  List<Map<String, dynamic>> _suggestions = [];
  // Session token groups autocomplete+detail into one billing session.
  String _sessionToken = '';
  // Monotonic counter — each fetch increments it; responses for older requests
  // are discarded to prevent stale results from overwriting fresher ones.
  int _searchSeq = 0;
  bool _searching = false;
  bool _locating = false;
  bool _resolving = false;
  bool _showSuggestions = false;
  bool _detailsExpanded = false;
  bool _confirming = false;
  bool _mapMoving = false;

  // Live reverse-geocoded address shown on the bottom card.
  String _formatted = '';

  // Editable address fields (mirrors the retired form screen).
  final _label = TextEditingController(text: 'Home');
  final _line1 = TextEditingController();
  final _city = TextEditingController();
  final _state = TextEditingController(text: '27');
  final _pincode = TextEditingController();

  /// Read the Maps API key from native (Info.plist / AndroidManifest meta-data)
  /// so the map works even when --dart-define is not passed at build time.
  Future<void> _initMapsKey() async {
    try {
      final k = await const MethodChannel('com.shiplore/config')
          .invokeMethod<String>('getMapsApiKey') ?? '';
      if (mounted) {
        setState(() {
          if (k.isNotEmpty) _mapsApiKey = k;
          _mapsKeyLoaded = true;
        });
      }
    } catch (_) {
      // Channel not available (e.g. Android without handler) — mark loaded so
      // the UI doesn't stay in a permanent loading state.
      if (mounted) setState(() => _mapsKeyLoaded = true);
    }
  }

  @override
  void initState() {
    super.initState();
    if (!_mapsKeyLoaded) _initMapsKey();
    final loc = context.read<LocationProvider>().location;
    if (loc != null) {
      if (widget.initial == null) _center = LatLng(loc.lat, loc.lng);
      _label.text = loc.label ?? 'Home';
      _line1.text = loc.line1 ?? '';
      _city.text = loc.city ?? '';
      _state.text = loc.stateCode ?? '27';
      _pincode.text = loc.pincode ?? '';
      _formatted = loc.formatted ?? '';
    }
    // Resolve the starting point so the card is populated on first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => _reverseGeocode(_center));
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _geocodeDebounce?.cancel();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _label.dispose();
    _line1.dispose();
    _city.dispose();
    _state.dispose();
    _pincode.dispose();
    _mapCtrl?.dispose();
    super.dispose();
  }

  // ---- Places Autocomplete (India-biased) ----------------------------------

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    if (query.trim().length < 3) {
      setState(() {
        _suggestions = [];
        _showSuggestions = false;
      });
      return;
    }
    _searchDebounce = Timer(
      const Duration(milliseconds: 400),
      () => _fetchSuggestions(query.trim()),
    );
  }

  Future<void> _fetchSuggestions(String query) async {
    final key = _mapsApiKey;
    if (key.isEmpty) return;
    // Start a new session token when the user begins a fresh search.
    if (_sessionToken.isEmpty) {
      _sessionToken = DateTime.now().millisecondsSinceEpoch.toString();
    }
    final seq = ++_searchSeq;
    if (mounted) setState(() => _searching = true);
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        'https://maps.googleapis.com/maps/api/place/autocomplete/json',
        queryParameters: {
          'input': query,
          'key': key,
          // No 'types' filter — allows both establishments (buildings, societies)
          // and geocode results (roads, areas) matching what the website shows.
          'components': 'country:in',
          'language': 'en',
          // Bias toward current map centre so closer results rank higher.
          'location': '${_center.latitude},${_center.longitude}',
          'radius': '50000',
          'sessiontoken': _sessionToken,
        },
        options: Options(receiveTimeout: const Duration(seconds: 5)),
      );
      // Discard response if a newer request has already been issued.
      if (!mounted || seq != _searchSeq) return;
      final preds = (res.data?['predictions'] as List?) ?? [];
      setState(() {
        _suggestions = preds.cast<Map<String, dynamic>>().take(5).toList();
        _showSuggestions = _suggestions.isNotEmpty;
        _searching = false;
      });
    } catch (_) {
      if (!mounted || seq != _searchSeq) return;
      setState(() {
        _searching = false;
        _showSuggestions = false;
      });
    }
  }

  Future<void> _selectSuggestion(Map<String, dynamic> pred) async {
    final placeId = pred['place_id'] as String?;
    if (placeId == null) return;
    _searchCtrl.text = (pred['structured_formatting']?['main_text'] as String?) ??
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
        // A new place was chosen — refresh the address fields from it (clear
        // stale values first so the new pincode/city/line actually take).
        _line1.clear();
        _city.clear();
        _state.clear();
        _pincode.clear();
        final components = (result?['address_components'] as List?) ?? [];
        final formatted = (result?['formatted_address'] as String?) ?? '';
        if (components.isNotEmpty) {
          _applyAddressComponents(components, formatted, overwrite: true);
        }
        await _mapCtrl?.animateCamera(CameraUpdate.newLatLngZoom(target, 16));
        await _reverseGeocode(target); // fills anything the place didn't provide
      }
    } catch (_) {
      // Silently fall through — the user can still move the map manually.
    } finally {
      // Reset session token — next autocomplete session gets a fresh one.
      _sessionToken = '';
      if (mounted) setState(() => _searching = false);
    }
  }

  // ---- GPS ------------------------------------------------------------------

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
      if (_label.text.trim().isEmpty || _label.text.trim() == 'Home') {
        _label.text = 'Current location';
      }
      await _mapCtrl?.animateCamera(CameraUpdate.newLatLngZoom(target, 16));
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

  // ---- Reverse geocode ------------------------------------------------------

  void _onCameraIdle() {
    setState(() => _mapMoving = false);
    _geocodeDebounce?.cancel();
    _geocodeDebounce =
        Timer(const Duration(milliseconds: 600), () => _reverseGeocode(_center));
  }

  /// Native device geocoding (iOS CLGeocoder / Android Geocoder) — no API key needed.
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
        final stateIsDefault = _state.text.trim().isEmpty || _state.text.trim() == '27';
        if (state.isNotEmpty && stateIsDefault) _state.text = state;
        if (pin.length == 6 && _pincode.text.trim().isEmpty) _pincode.text = pin;
      });
    } catch (_) {
      // Native geocoding is best-effort; silently skip on error.
    } finally {
      if (mounted && _resolving) setState(() => _resolving = false);
    }
  }

  Future<void> _reverseGeocode(LatLng point) async {
    final key = _mapsApiKey;
    if (key.isEmpty) {
      // No Maps API key — use native OS geocoding as fallback.
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
      final results = (res.data?['results'] as List?) ?? [];
      if (results.isEmpty) {
        if (_resolving) setState(() => _resolving = false);
        return;
      }
      final first = results.first as Map<String, dynamic>;
      final formatted = (first['formatted_address'] as String?) ?? '';
      final components = (first['address_components'] as List?) ?? [];
      // Camera-move geocode: fill only empty fields (don't clobber user edits).
      _applyAddressComponents(components, formatted, overwrite: false);
      if (mounted && _resolving) setState(() => _resolving = false);
    } catch (_) {
      // Geocoding is best-effort; silently skip on error.
      if (mounted && _resolving) setState(() => _resolving = false);
    }
  }

  /// Parse Google address components into the editable fields. The postal code is
  /// stripped to digits (Google sometimes returns "400 053" with a space, which
  /// would fail the 6-digit pincode check and block "Confirm location"). When
  /// [overwrite] is true (an explicit search selection) it replaces the fields;
  /// otherwise it only fills empty ones.
  void _applyAddressComponents(List<dynamic> components, String formatted, {required bool overwrite}) {
    String city = '', pincode = '', route = '', streetNum = '', sublocality = '', stateCode = '';
    for (final c in components.cast<Map>()) {
      final types = (c['types'] as List).cast<String>();
      final long = c['long_name'] as String? ?? '';
      final short = c['short_name'] as String? ?? '';
      if (types.contains('postal_code')) pincode = long.replaceAll(RegExp(r'[^0-9]'), '');
      if (types.contains('locality')) city = long;
      if (city.isEmpty && types.contains('administrative_area_level_2')) city = long;
      if (types.contains('route')) route = long;
      if (types.contains('street_number')) streetNum = long;
      if (sublocality.isEmpty && types.contains('sublocality')) sublocality = long;
      if (types.contains('administrative_area_level_1')) stateCode = short; // e.g. "MH"
    }
    final line1 = [streetNum, route].where((s) => s.isNotEmpty).join(', ');
    final l1 = line1.isNotEmpty ? line1 : sublocality;
    if (!mounted) return;
    final stateIsDefault = _state.text.trim().isEmpty || _state.text.trim() == '27';
    setState(() {
      if (formatted.isNotEmpty) _formatted = formatted;
      if (pincode.length == 6 && (overwrite || _pincode.text.trim().isEmpty)) _pincode.text = pincode;
      if (city.isNotEmpty && (overwrite || _city.text.trim().isEmpty)) _city.text = city;
      if (l1.isNotEmpty && (overwrite || _line1.text.trim().isEmpty)) _line1.text = l1;
      if (stateCode.isNotEmpty && (overwrite || stateIsDefault)) _state.text = stateCode;
    });
  }

  // ---- Misc UI helpers ------------------------------------------------------

  void _dismissSuggestions() {
    if (_showSuggestions || _searchFocus.hasFocus) {
      setState(() => _showSuggestions = false);
      _searchFocus.unfocus();
    }
  }

  Future<void> _confirm() async {
    if (_confirming) return;
    // Normalise to digits — Google geocoding can return "400 053" (with a space),
    // which would otherwise fail the 6-digit check and block confirming.
    final pin = _pincode.text.replaceAll(RegExp(r'[^0-9]'), '');
    // Pincode is OPTIONAL for setting the map point (deliverability uses lat/lng),
    // but if one is present it must be a clean 6 digits (orders require it). A
    // malformed manual entry expands the details so the user can fix it.
    if (pin.isNotEmpty && pin.length != 6) {
      setState(() => _detailsExpanded = true);
      showSnack(context, 'Pincode must be 6 digits', error: true);
      return;
    }
    setState(() => _confirming = true);
    final line1 = _line1.text.trim();
    final city = _city.text.trim();
    final formatted = _formatted.isNotEmpty
        ? _formatted
        : [line1, city, pin].where((s) => s.isNotEmpty).join(', ');
    final lp = context.read<LocationProvider>();
    final delivery = DeliveryLocation(
      lat: _center.latitude,
      lng: _center.longitude,
      label: _label.text.trim().isEmpty ? 'Home' : _label.text.trim(),
      line1: line1,
      city: city,
      stateCode: _state.text.trim(),
      pincode: pin.isEmpty ? null : pin,
      formatted: formatted,
    );
    // Use go_router's context.pop() (not Navigator.of(context).pop()) so GoRouter
    // manages its own route stack correctly on iOS. Then defer lp.set() to
    // addPostFrameCallback: on iOS, firing notifyListeners() during the pop
    // animation causes GoRouter to rebuild its widget tree mid-transition,
    // which cancels the pop and leaves the user stuck on the map screen.
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await lp.set(delivery);
    });
  }

  // ---- Build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // Wait for the native key channel call before deciding which UI to show.
    if (!_mapsKeyLoaded) {
      return Scaffold(
        appBar: AppBar(title: const Text('Set delivery location')),
        body: const LoadingView(),
      );
    }
    if (_mapsApiKey.isEmpty) {
      return _buildUnconfigured();
    }
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(target: _center, zoom: 16),
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            onMapCreated: (ctrl) => _mapCtrl = ctrl,
            // No setState here — keep the pan buttery smooth.
            onCameraMove: (pos) => _center = pos.target,
            onCameraMoveStarted: () => setState(() => _mapMoving = true),
            onCameraIdle: _onCameraIdle,
            onTap: (_) => _dismissSuggestions(),
          ),
          _buildCenterPin(),
          _buildSearchOverlay(),
          _buildGpsFab(),
          _buildBottomSheet(),
        ],
      ),
    );
  }

  Widget _buildUnconfigured() {
    return Scaffold(
      appBar: AppBar(title: const Text('Set delivery location')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: ListView(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: AppShadows.card,
              ),
              child: const Row(
                children: [
                  Icon(Icons.map_outlined, color: AppColors.inkSoft),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Map is not configured. Use GPS or enter the address manually.',
                      style: TextStyle(color: AppColors.inkSoft),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _locating ? null : _goToMyLocation,
              icon: _locating
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location),
              label: const Text('Use current location'),
            ),
            const SizedBox(height: 16),
            ..._addressFields(),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: (_confirming || _searching) ? null : _confirm,
              child: _confirming
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Confirm location'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCenterPin() {
    // Total pin height: head 44 + stem 14 + shadow 5 = 63.
    // bottom: 63 puts the shadow tip exactly at screen center.
    return IgnorePointer(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 63),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_resolving)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
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
              // Pin head + stem lift 6 px when the map is moving (Blinkit feel).
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
                            color:
                                AppColors.primary.withValues(alpha: 0.45),
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
              // Ground shadow shrinks when pin lifts.
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
                      onPressed: () {
                        if (Navigator.of(context).canPop()) {
                          Navigator.pop(context);
                        } else {
                          context.go('/');
                        }
                      },
                    ),
                    suffixIcon: _searching
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
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
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
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
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                        child: ListView.separated(
                          padding: EdgeInsets.zero,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _suggestions.length,
                          separatorBuilder: (_, _) =>
                              const Divider(height: 1, color: AppColors.line),
                          itemBuilder: (_, i) {
                            final s = _suggestions[i];
                            final main =
                                (s['structured_formatting']?['main_text'] as String?) ??
                                    (s['description'] as String? ?? '');
                            final secondary = s['structured_formatting']
                                    ?['secondary_text'] as String? ??
                                '';
                            return ScaleTap(
                              onTap: () => _selectSuggestion(s),
                              child: ListTile(
                                dense: true,
                                leading: const Icon(Icons.location_on_outlined,
                                    size: 20, color: AppColors.primary),
                                title: Text(main,
                                    maxLines: 1, overflow: TextOverflow.ellipsis),
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
                      // Required attribution per Google Places API ToS.
                      const Divider(height: 1, color: AppColors.line),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text('powered by ',
                                style: TextStyle(
                                    fontSize: 10, color: AppColors.inkSoft)),
                            const Text('Google',
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.inkSoft)),
                          ],
                        ),
                      ),
                    ],
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
      bottom: 250,
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
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                _buildAddressCard(),
                const SizedBox(height: 12),
                _buildDetailsToggle(),
                AnimatedCrossFade(
                  duration: const Duration(milliseconds: 200),
                  crossFadeState: _detailsExpanded
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  firstChild: const SizedBox(width: double.infinity),
                  secondChild: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: _addressFields(),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: (_confirming || _searching) ? null : _confirm,
                  child: _confirming
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Confirm location'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAddressCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bgTint,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.location_pin, color: AppColors.primary),
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
    );
  }

  Widget _buildDetailsToggle() {
    return ScaleTap(
      onTap: () => setState(() => _detailsExpanded = !_detailsExpanded),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            _detailsExpanded ? 'Hide address details' : 'Add address details',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
          Icon(
            _detailsExpanded ? Icons.expand_less : Icons.expand_more,
            color: AppColors.primary,
            size: 20,
          ),
        ],
      ),
    );
  }

  List<Widget> _addressFields() {
    return [
      TextField(
        controller: _label,
        decoration: const InputDecoration(labelText: 'Label (Home / Work)'),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _line1,
        decoration: const InputDecoration(labelText: 'Flat / House / Street'),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _city,
              decoration: const InputDecoration(labelText: 'City'),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 90,
            child: TextField(
              controller: _state,
              decoration: const InputDecoration(labelText: 'State'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _pincode,
        keyboardType: TextInputType.number,
        maxLength: 6,
        decoration: const InputDecoration(
          labelText: 'Pincode (optional)',
          counterText: '',
        ),
      ),
    ];
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
