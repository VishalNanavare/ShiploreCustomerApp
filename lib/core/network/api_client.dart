import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import 'api_exception.dart';

/// One decoded API envelope: the `data` payload + `meta` (pagination, flags).
typedef ApiPage = ({dynamic data, Map<String, dynamic> meta});

/// Retries transient network failures (timeouts, connection drops) up to
/// [_maxRetries] times with exponential back-off. Does NOT retry 4xx/5xx
/// responses — those are intentional server replies handled by [ApiClient._send].
class _RetryInterceptor extends Interceptor {
  _RetryInterceptor(this._dio);
  final Dio _dio;

  static const _maxRetries = 2;
  static const _retryKey = 'retry_count';

  static bool _isTransient(DioException e) =>
      e.type == DioExceptionType.connectionError ||
      e.type == DioExceptionType.connectionTimeout ||
      e.type == DioExceptionType.receiveTimeout ||
      e.type == DioExceptionType.sendTimeout;

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final options = err.requestOptions;
    final retries = (options.extra[_retryKey] as int?) ?? 0;
    if (!_isTransient(err) || retries >= _maxRetries) {
      handler.next(err);
      return;
    }
    // Exponential back-off: 1s, 2s.
    await Future<void>.delayed(Duration(seconds: 1 << retries));
    options.extra[_retryKey] = retries + 1;
    try {
      final response = await _dio.fetch<dynamic>(options);
      handler.resolve(response);
    } on DioException catch (e) {
      handler.next(e);
    }
  }
}

/// Thin, secure HTTP client over Dio.
///
/// Security:
///  - HTTPS-only base URL; optional SHA-256 certificate pinning (AppConfig).
///  - Bearer token attached per request from [tokenProvider] (never cached in
///    memory beyond the call).
///  - On 401 it attempts a single token refresh via [onRefresh] then retries;
///    if refresh fails it triggers [onAuthFailure] (logout) — so a revoked or
///    expired token can never silently keep failing.
///  - Server envelope is unwrapped centrally; non-success becomes [ApiException].
class ApiClient {
  ApiClient() {
    _dio = Dio(BaseOptions(
      baseUrl: AppConfig.apiBaseUrl,
      connectTimeout: AppConfig.connectTimeout,
      receiveTimeout: AppConfig.receiveTimeout,
      headers: const {'Accept': 'application/json'},
      // We read error bodies ourselves, so don't let Dio throw on 4xx.
      validateStatus: (status) => status != null && status < 500,
      responseType: ResponseType.json,
    ));
    _dio.httpClientAdapter = _buildAdapter();
    _dio.interceptors.add(InterceptorsWrapper(onRequest: _onRequest));
    _dio.interceptors.add(_RetryInterceptor(_dio));
  }

  late final Dio _dio;

  /// Returns the current JWT (or null). Set by the auth layer.
  Future<String?> Function()? tokenProvider;

  /// Exchanges the current token for a fresh one. Returns the new token or null.
  Future<String?> Function()? onRefresh;

  /// Called when authentication is no longer recoverable (force logout).
  Future<void> Function()? onAuthFailure;

  HttpClientAdapter _buildAdapter() {
    final adapter = IOHttpClientAdapter();
    if (AppConfig.pinningEnabled) {
      final pin = AppConfig.certSha256.toUpperCase().replaceAll(' ', '');
      adapter.validateCertificate = (cert, host, port) {
        if (cert == null) return false;
        final digest = sha256.convert(cert.der).bytes;
        final hex = digest.map((b) => b.toRadixString(16).padLeft(2, '0')).join(':').toUpperCase();
        return hex == pin;
      };
    } else if (kDebugMode) {
      // Accept self-signed / locally-issued certs in debug builds so the app
      // works on simulators whose trust store doesn't include the dev CA.
      adapter.validateCertificate = (cert, host, port) => true;
    }
    // Debug-only DNS shim. The API host (test.eriklocal.online) resolves only on
    // the dev Mac's /etc/hosts; an Android emulator/physical device can't resolve
    // it. When DEV_HOST_IP is provided (e.g. 10.0.2.2 for the emulator, or a LAN IP
    // for a device), redirect the TCP connection to that IP WITHOUT touching the
    // URL — the Host header still carries the real hostname so nginx routes the
    // right vhost. The connectionFactory must return an already-TLS'd socket
    // (Dart does not wrap it), so we use SecureSocket and accept the dev host's
    // cert since we connect by IP. Compiled out of release builds.
    const devHostIp = String.fromEnvironment('DEV_HOST_IP');
    if (kDebugMode && devHostIp.isNotEmpty) {
      final apiHost = Uri.parse(AppConfig.apiBaseUrl).host;
      adapter.createHttpClient = () {
        final client = HttpClient();
        client.connectionFactory = (uri, proxyHost, proxyPort) {
          final redirectToDev = uri.host == apiHost;
          final target = redirectToDev ? devHostIp : uri.host;
          if (uri.scheme == 'https') {
            return SecureSocket.startConnect(
              target,
              uri.port,
              onBadCertificate: redirectToDev ? (X509Certificate _) => true : null,
            );
          }
          return Socket.startConnect(target, uri.port);
        };
        return client;
      };
    }
    return adapter;
  }

  Future<void> _onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final token = await tokenProvider?.call();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  // ---- public verbs (return the unwrapped `data`) ----
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async =>
      (await _send(() => _dio.get(path, queryParameters: query))).data;

  Future<dynamic> post(String path, {Object? body, bool allowRefresh = true}) async =>
      (await _send(() => _dio.post(path, data: body), allowRefresh: allowRefresh)).data;

  Future<dynamic> put(String path, {Object? body}) async =>
      (await _send(() => _dio.put(path, data: body))).data;

  Future<dynamic> delete(String path, {Object? body}) async =>
      (await _send(() => _dio.delete(path, data: body))).data;

  /// Download PDF bytes — returns raw bytes without going through the JSON wrapper.
  Future<List<int>> getBytes(String path) async {
    if (!AppConfig.isHttps) {
      throw ApiException(code: 'SERVER_ERROR', message: 'Insecure API URL blocked.');
    }
    try {
      final token = await tokenProvider?.call();
      final headers = token != null ? {'Authorization': 'Bearer $token'} : <String, String>{};
      final res = await _dio.get<List<int>>(
        path,
        options: Options(responseType: ResponseType.bytes, headers: headers),
      );
      if (res.data == null) throw ApiException(code: 'SERVER_ERROR', message: 'Empty response.');
      return res.data!;
    } on DioException catch (e) {
      throw ApiException.fromEnvelope(null, e.response?.statusCode);
    }
  }

  /// For list endpoints — returns both `data` and `meta` (pagination).
  Future<ApiPage> getPage(String path, {Map<String, dynamic>? query}) =>
      _send(() => _dio.get(path, queryParameters: query));

  /// POST returning both `data` and `meta` (e.g. OTP request echoes a dev code in meta).
  Future<ApiPage> postPage(String path, {Object? body, bool allowRefresh = true}) =>
      _send(() => _dio.post(path, data: body), allowRefresh: allowRefresh);

  Future<ApiPage> _send(
    Future<Response<dynamic>> Function() call, {
    bool allowRefresh = true,
  }) async {
    if (!AppConfig.isHttps) {
      throw ApiException(code: 'SERVER_ERROR', message: 'Insecure API URL blocked.');
    }
    try {
      final res = await call();
      final body = res.data;
      if (body is Map && body['success'] == true) {
        return (
          data: body['data'],
          meta: (body['meta'] is Map) ? (body['meta'] as Map).cast<String, dynamic>() : <String, dynamic>{},
        );
      }
      // success == false → typed error. Retry once on 401 after refresh.
      if (res.statusCode == 401 && allowRefresh && onRefresh != null) {
        final fresh = await onRefresh!.call();
        if (fresh != null && fresh.isNotEmpty) {
          return _send(call, allowRefresh: false);
        }
        await onAuthFailure?.call();
      }
      throw ApiException.fromEnvelope(body is Map ? body.cast<String, dynamic>() : null, res.statusCode);
    } on DioException catch (e) {
      final underlying = e.error;
      // A TLS/handshake failure (e.g. an old emulator that doesn't trust the cert
      // chain) is NOT "no internet" — surface it distinctly.
      if (underlying is HandshakeException || underlying is TlsException || underlying is CertificateException) {
        throw ApiException(
          code: 'SERVER_ERROR',
          message: kDebugMode
              ? 'TLS error: $underlying'
              : 'Secure connection failed. Check the device date/time and OS version.',
        );
      }
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout) {
        // In debug, include the real reason (DNS lookup, refused, timeout, …) so the
        // cause is visible instead of a blanket "no internet".
        final detail = kDebugMode ? '\n[${e.type.name}] ${e.message ?? underlying ?? ''}\nURL: ${AppConfig.apiBaseUrl}' : '';
        throw ApiException.network('Can’t reach the server — check your internet connection.$detail');
      }
      final data = e.response?.data;
      throw ApiException.fromEnvelope(data is Map ? data.cast<String, dynamic>() : null, e.response?.statusCode);
    }
  }
}
