import '../../core/network/api_client.dart';
import '../models/notification_item.dart';
import '../models/user.dart';

class CustomerRepository {
  CustomerRepository(this._api);

  final ApiClient _api;

  Future<AppUser> getProfile() async {
    final data = await _api.get('/customer/profile') as Map;
    return AppUser.fromJson((data['profile'] as Map).cast<String, dynamic>());
  }

  Future<AppUser> updateProfile({required String name, String? email}) async {
    final data = await _api.put('/customer/profile', body: {
          'name': name,
          if (email != null && email.isNotEmpty) 'email': email,
        }) as Map;
    return AppUser.fromJson(
        (data['profile'] as Map).cast<String, dynamic>());
  }

  Future<List<NotificationItem>> notifications() async {
    final res = await _api.getPage('/customer/notifications');
    return ((res.data as List?) ?? const [])
        .map((e) => NotificationItem.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<int> unreadNotificationCount() async {
    final data = await _api.get('/customer/notifications/unread-count') as Map;
    return (data['unread'] as num?)?.toInt() ?? 0;
  }

  Future<void> markNotificationRead(int id) =>
      _api.post('/customer/notifications/$id/read');

  Future<void> markAllNotificationsRead() =>
      _api.post('/customer/notifications/read-all');

  Future<void> deleteNotification(int id) =>
      _api.delete('/customer/notifications/$id');

  Future<void> clearAllNotifications() =>
      _api.delete('/customer/notifications/all');

  Future<void> createSupportTicket({required String subject, required String message}) =>
      _api.post('/customer/support', body: {'subject': subject, 'message': message});
}
