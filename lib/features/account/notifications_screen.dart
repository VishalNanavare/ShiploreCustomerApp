import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/notification_item.dart';
import '../../data/repositories/customer_repository.dart';
import '../../widgets/states.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<NotificationItem> _items = [];
  bool _loading = true;
  Object? _error;

  int get _unreadCount => _items.where((n) => !n.isRead).length;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final items = await context.read<CustomerRepository>().notifications();
      if (mounted) setState(() { _items = items; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e; _loading = false; });
    }
  }

  // Navigate FIRST (before any setState) so the State's context stays valid.
  Future<void> _onTap(NotificationItem n) async {
    final route = _routeFor(n);
    if (route != null && mounted) context.push(route);

    if (!n.isRead && mounted) {
      setState(() {
        final idx = _items.indexWhere((x) => x.id == n.id);
        if (idx >= 0) _items[idx] = _withReadNow(_items[idx]);
      });
      context.read<CustomerRepository>().markNotificationRead(n.id).catchError((_) {});
    }
  }

  // Optimistic — update UI immediately, then confirm with server.
  Future<void> _markAllRead() async {
    if (_unreadCount == 0) return;
    setState(() {
      _items = _items.map((n) => n.isRead ? n : _withReadNow(n)).toList();
    });
    try {
      await context.read<CustomerRepository>().markAllNotificationsRead();
    } catch (_) {
      if (mounted) _load(); // restore from server on failure
    }
  }

  static NotificationItem _withReadNow(NotificationItem n) => NotificationItem(
        id: n.id,
        title: n.title,
        body: n.body,
        eventCode: n.eventCode,
        createdAt: n.createdAt,
        readAt: DateTime.now(),
        data: n.data,
      );

  Future<void> _dismiss(NotificationItem n) async {
    final snapshot = List<NotificationItem>.from(_items);
    setState(() { _items = _items.where((x) => x.id != n.id).toList(); });
    try {
      await context.read<CustomerRepository>().deleteNotification(n.id);
    } catch (_) {
      if (mounted) setState(() { _items = snapshot; });
    }
  }

  Future<void> _clearAll() async {
    if (_items.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
        titlePadding: const EdgeInsets.fromLTRB(24, 28, 24, 12),
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.danger.withAlpha(20),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.delete_sweep_rounded, color: AppColors.danger, size: 20),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Clear all notifications?',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        content: const Text(
          'All notifications will be permanently removed.',
          style: TextStyle(fontSize: 14, color: AppColors.inkSoft, height: 1.5),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        actions: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton(
                onPressed: () => ctx.pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Clear all', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: () => ctx.pop(false),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  side: const BorderSide(color: AppColors.line, width: 1.5),
                  foregroundColor: AppColors.ink,
                ),
                child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w500)),
              ),
            ],
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final snapshot = List<NotificationItem>.from(_items);
    setState(() { _items = []; });
    try {
      await context.read<CustomerRepository>().clearAllNotifications();
    } catch (_) {
      if (mounted) setState(() { _items = snapshot; });
    }
  }

  String? _routeFor(NotificationItem n) {
    final data = n.data;

    final explicit = data['route'] as String?;
    if (explicit != null && explicit.isNotEmpty) return explicit;

    final orderNo = (data['order_no'] as String?)?.trim();
    if (orderNo != null && orderNo.isNotEmpty) return '/track/$orderNo';

    final code = n.eventCode.toLowerCase();
    if (code.contains('order') || code.contains('deliver') ||
        code.contains('payment') || code.contains('refund') ||
        code.contains('return')) {
      return '/orders';
    }
    if (code.contains('promo') || code.contains('offer')) return '/';
    return null;
  }

  List<dynamic> get _listItems {
    if (_items.isEmpty) return const [];
    final result = <dynamic>[];
    String? lastGroup;
    for (final n in _items) {
      final group = _groupLabel(n.createdAt);
      if (group != lastGroup) { result.add(group); lastGroup = group; }
      result.add(n);
    }
    return result;
  }

  String _groupLabel(DateTime? raw) {
    if (raw == null) return 'Earlier';
    final dt = raw.toLocal();
    final now = DateTime.now();
    final diff = DateTime(now.year, now.month, now.day)
        .difference(DateTime(dt.year, dt.month, dt.day))
        .inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return DateFormat('EEEE').format(dt);
    return dt.year == now.year
        ? DateFormat('d MMMM').format(dt)
        : DateFormat('d MMM y').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final unread = _unreadCount;
    final hasItems = _items.isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text('Notifications'),
        leading: BackButton(
          onPressed: () => context.canPop() ? context.pop() : context.go('/account'),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.line),
        ),
        actions: [
          if (!_loading && hasItems)
            PopupMenuButton<_Action>(
              icon: const Icon(Icons.more_vert_rounded),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              onSelected: (a) {
                if (a == _Action.markRead) _markAllRead();
                if (a == _Action.clearAll) _clearAll();
              },
              itemBuilder: (_) => [
                if (unread > 0)
                  const PopupMenuItem(
                    value: _Action.markRead,
                    child: ListTile(
                      leading: Icon(Icons.done_all_rounded),
                      title: Text('Mark all as read'),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                  ),
                const PopupMenuItem(
                  value: _Action.clearAll,
                  child: ListTile(
                    leading: Icon(Icons.delete_sweep_rounded, color: AppColors.danger),
                    title: Text('Clear all', style: TextStyle(color: AppColors.danger)),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                ),
              ],
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorView(error: _error!, onRetry: _load)
              : !hasItems
                  ? const _EmptyNotifications()
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.only(top: 8, bottom: 32),
                        itemCount: _listItems.length,
                        itemBuilder: (_, i) {
                          final item = _listItems[i];
                          if (item is String) return _DateHeader(label: item);
                          final n = item as NotificationItem;
                          return _NotifTile(
                            key: ValueKey(n.id),
                            n: n,
                            navigable: _routeFor(n) != null,
                            onTap: () => _onTap(n),
                            onDismiss: () => _dismiss(n),
                          );
                        },
                      ),
                    ),
    );
  }
}

enum _Action { markRead, clearAll }

// ─── Date section header ───────────────────────────────────────────────────

class _DateHeader extends StatelessWidget {
  const _DateHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        child: Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColors.inkSoft,
            letterSpacing: 0.8,
          ),
        ),
      );
}

// ─── Notification tile ─────────────────────────────────────────────────────

class _NotifTile extends StatelessWidget {
  const _NotifTile({
    super.key,
    required this.n,
    required this.navigable,
    required this.onTap,
    required this.onDismiss,
  });

  final NotificationItem n;
  final bool navigable;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  String get _timeLabel {
    final raw = n.createdAt;
    if (raw == null) return '';
    final dt = raw.toLocal();
    final now = DateTime.now();
    final diff = DateTime(now.year, now.month, now.day)
        .difference(DateTime(dt.year, dt.month, dt.day))
        .inDays;
    if (diff == 0) return DateFormat('h:mm a').format(dt);
    if (diff == 1) return 'Yesterday ${DateFormat('h:mm a').format(dt)}';
    return DateFormat('d MMM · h:mm a').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final isRead = n.isRead;
    final category = NotificationCategory.fromCode(n.eventCode);
    final title = n.title;
    final body = n.body;
    final time = _timeLabel;

    return Dismissible(
      key: ValueKey('d_${n.id}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDismiss(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 28),
        color: AppColors.danger,
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.delete_rounded, color: Colors.white, size: 24),
            SizedBox(height: 4),
            Text('Remove', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        margin: isRead
            ? EdgeInsets.zero
            : const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: isRead
            ? null
            : BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                boxShadow: AppShadows.soft,
                border: Border(left: BorderSide(color: AppColors.cta, width: 3)),
              ),
        child: Material(
          color: Colors.transparent,
          borderRadius: isRead ? BorderRadius.zero : BorderRadius.circular(14),
          child: InkWell(
            onTap: onTap,
            borderRadius: isRead ? BorderRadius.zero : BorderRadius.circular(14),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isRead ? 16 : 14,
                vertical: 14,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Category icon
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: isRead ? AppColors.bgTint : category.bg,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      category.icon,
                      size: 20,
                      color: isRead ? AppColors.inkSoft : category.color,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Content
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Title row with unread dot
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: isRead ? FontWeight.w500 : FontWeight.w700,
                                  color: AppColors.ink,
                                  height: 1.35,
                                ),
                              ),
                            ),
                            if (!isRead) ...[
                              const SizedBox(width: 8),
                              Container(
                                width: 8,
                                height: 8,
                                margin: const EdgeInsets.only(top: 5),
                                decoration: const BoxDecoration(
                                  color: AppColors.cta,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ],
                          ],
                        ),
                        // Body
                        if (body.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            body,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.inkSoft,
                              height: 1.45,
                            ),
                          ),
                        ],
                        // Footer: time + "View details" link
                        const SizedBox(height: 7),
                        Row(
                          children: [
                            if (time.isNotEmpty)
                              Text(
                                time,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.inkSoft,
                                ),
                              ),
                            if (navigable) ...[
                              const Spacer(),
                              Text(
                                'View details',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: isRead ? AppColors.inkSoft : AppColors.cta,
                                ),
                              ),
                              Icon(
                                Icons.arrow_forward_ios_rounded,
                                size: 10,
                                color: isRead ? AppColors.inkSoft : AppColors.cta,
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Empty state ───────────────────────────────────────────────────────────

class _EmptyNotifications extends StatelessWidget {
  const _EmptyNotifications();

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: const BoxDecoration(color: AppColors.bgTint, shape: BoxShape.circle),
                child: const Icon(
                  Icons.notifications_none_rounded,
                  size: 48,
                  color: AppColors.inkSoft,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'No notifications yet',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Order updates, delivery alerts and\nspecial offers will appear here.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.inkSoft,
                  height: 1.55,
                ),
              ),
            ],
          ),
        ),
      );
}
