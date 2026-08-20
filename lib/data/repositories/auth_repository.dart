import '../../core/network/api_client.dart';
import '../models/user.dart';

typedef AuthSession = ({String token, AppUser user});

/// Wraps the /auth/* endpoints. OTP is the primary login; password is supported.
class AuthRepository {
  AuthRepository(this._api);
  final ApiClient _api;

  /// Request an OTP. Returns the dev code if the server echoes one (dev only;
  /// production never returns it). The response is intentionally generic so it
  /// can't be used to tell whether an account exists.
  Future<String?> requestOtp(String identifier) async {
    final page = await _api.postPage('/auth/otp/request', body: {'identifier': identifier});
    return page.meta['dev_code']?.toString();
  }

  AuthSession _session(dynamic data) {
    final m = (data as Map).cast<String, dynamic>();
    return (
      token: (m['token'] ?? '').toString(),
      user: AppUser.fromJson((m['user'] as Map).cast<String, dynamic>()),
    );
  }

  Future<AuthSession> verifyOtp(String identifier, String code) async {
    final data = await _api.post('/auth/otp/verify', body: {'identifier': identifier, 'code': code});
    return _session(data);
  }

  /// Exchange a verified Firebase ID token (from Firebase Phone Auth) for the
  /// backend JWT session. The server verifies the token and signs-in/up the
  /// customer by the verified phone number.
  Future<AuthSession> firebaseExchange(String idToken) async {
    final data = await _api.post('/auth/firebase', body: {'id_token': idToken});
    return _session(data);
  }

  Future<AuthSession> login(String identifier, String password) async {
    final data = await _api.post('/auth/login', body: {'identifier': identifier, 'password': password});
    return _session(data);
  }

  /// Exchange the current (still-valid) token for a fresh one. allowRefresh:false
  /// avoids recursion through the 401 interceptor.
  Future<AuthSession> refresh() async {
    final data = await _api.post('/auth/refresh', allowRefresh: false);
    return _session(data);
  }
}
