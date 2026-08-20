import 'dart:math';

/// Generates an idempotency key for order placement so a retried/duplicate
/// submit collapses to a single order server-side (api_idempotency_keys).
class IdGen {
  IdGen._();
  static final _rng = Random.secure();

  static String idempotencyKey() {
    final ts = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    final rand = List.generate(8, (_) => _rng.nextInt(16).toRadixString(16)).join();
    return 'app-$ts-$rand';
  }
}
