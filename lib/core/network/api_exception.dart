/// A typed error surfaced from the API layer, carrying the server's error code
/// (VALIDATION_ERROR, CONFLICT, NOT_FOUND, FORBIDDEN, UNAUTHENTICATED,
/// SERVER_ERROR) plus a user-facing message and optional field details.
class ApiException implements Exception {
  ApiException({
    required this.code,
    required this.message,
    this.statusCode,
    this.details = const {},
  });

  final String code;
  final String message;
  final int? statusCode;
  final Map<String, dynamic> details;

  bool get isUnauthenticated => code == 'UNAUTHENTICATED' || statusCode == 401;
  bool get isForbidden => code == 'FORBIDDEN' || statusCode == 403;
  bool get isNotFound => code == 'NOT_FOUND' || statusCode == 404;
  bool get isValidation => code == 'VALIDATION_ERROR';
  bool get isConflict => code == 'CONFLICT' || statusCode == 409;
  bool get isNetwork => code == 'NETWORK_ERROR';

  /// Build from the standard error envelope: {error:{code,message,details}}.
  factory ApiException.fromEnvelope(Map<String, dynamic>? body, int? status) {
    final rawErr = body?['error'];
    final err = (rawErr is Map) ? rawErr.cast<String, dynamic>() : null;
    final rawDetails = err?['details'];
    return ApiException(
      code: (err?['code'] as String?) ?? 'SERVER_ERROR',
      message: (err?['message'] as String?) ?? 'Something went wrong. Please try again.',
      statusCode: status,
      details: (rawDetails is Map) ? rawDetails.cast<String, dynamic>() : const {},
    );
  }

  factory ApiException.network([String? message]) => ApiException(
        code: 'NETWORK_ERROR',
        message: message ?? 'No internet connection. Check your network and retry.',
      );

  @override
  String toString() => 'ApiException($code, $statusCode): $message';
}
