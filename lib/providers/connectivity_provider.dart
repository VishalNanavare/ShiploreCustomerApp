import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Tracks device connectivity so the shell can show an offline banner.
class ConnectivityProvider extends ChangeNotifier {
  ConnectivityProvider() {
    _init();
  }

  final Connectivity _conn = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _sub;
  bool _offline = false;

  bool get isOffline => _offline;

  Future<void> _init() async {
    try {
      _apply(await _conn.checkConnectivity());
    } catch (_) {/* assume online */}
    _sub = _conn.onConnectivityChanged.listen(_apply);
  }

  void _apply(List<ConnectivityResult> results) {
    final off = results.isEmpty || results.every((r) => r == ConnectivityResult.none);
    if (off != _offline) {
      _offline = off;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
