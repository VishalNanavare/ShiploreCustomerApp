import 'package:flutter/foundation.dart';

import '../core/network/api_client.dart';
import '../core/storage/secure_store.dart';
import '../data/models/user.dart';
import '../data/repositories/auth_repository.dart';

/// Owns the auth session. Wires the [ApiClient] callbacks so every request
/// carries the token, a 401 triggers a single refresh, and an unrecoverable
/// auth failure forces logout.
class AuthProvider extends ChangeNotifier {
  AuthProvider(this._api, this._store, this._repo);

  final ApiClient _api;
  final SecureStore _store;
  final AuthRepository _repo;

  String? _token;
  AppUser? _user;
  bool _ready = false;

  AppUser? get user => _user;
  bool get ready => _ready;
  bool get isLoggedIn => _token != null && _token!.isNotEmpty && _user != null;

  /// Load any stored session and wire the network callbacks. Call once at startup.
  Future<void> bootstrap() async {
    _token = await _store.readToken();
    _user = AppUser.decode(await _store.readUser());
    _api.tokenProvider = () async => _token;
    _api.onRefresh = _refreshToken;
    _api.onAuthFailure = _forceLogout;
    _ready = true;
    notifyListeners();
  }

  Future<String?> _refreshToken() async {
    if (_token == null) return null;
    try {
      final s = await _repo.refresh();
      await _persist(s);
      return s.token;
    } catch (_) {
      return null;
    }
  }

  Future<void> _persist(AuthSession s) async {
    _token = s.token;
    _user = s.user;
    await _store.writeToken(s.token);
    await _store.writeUser(s.user.encode());
    notifyListeners();
  }

  Future<String?> requestOtp(String identifier) => _repo.requestOtp(identifier.trim());

  Future<void> verifyOtp(String identifier, String code) async =>
      _persist(await _repo.verifyOtp(identifier.trim(), code.trim()));

  /// Complete login from a verified Firebase ID token: exchange it for the
  /// backend JWT session and persist it.
  Future<void> firebaseExchange(String idToken) async =>
      _persist(await _repo.firebaseExchange(idToken));

  Future<void> login(String identifier, String password) async =>
      _persist(await _repo.login(identifier.trim(), password));

  Future<void> logout() async {
    _token = null;
    _user = null;
    await _store.clear();
    notifyListeners();
  }

  Future<void> updateUser(AppUser user) async {
    _user = user;
    await _store.writeUser(user.encode());
    notifyListeners();
  }

  Future<void> _forceLogout() => logout();
}
