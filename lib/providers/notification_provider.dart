import 'package:flutter/foundation.dart';

import '../data/repositories/customer_repository.dart';

/// Tracks the unread-notification count for the home bell badge. Refreshed when
/// Home loads; optimistically cleared when the user opens the screen / marks all
/// read. Errors are intentionally swallowed so the badge never blocks the UI.
class NotificationProvider extends ChangeNotifier {
  NotificationProvider(this._repo);
  final CustomerRepository _repo;

  int _unread = 0;
  int get unread => _unread;

  Future<void> refresh() async {
    try {
      final count = await _repo.unreadNotificationCount();
      if (count != _unread) {
        _unread = count;
        notifyListeners();
      }
    } catch (_) {}
  }

  void clear() {
    if (_unread == 0) return;
    _unread = 0;
    notifyListeners();
  }
}
