import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/user.dart';
import '../../data/repositories/customer_repository.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/app_scale_tap.dart';

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    final loggedIn = auth.isLoggedIn;
    final subtitle = user?.phone ?? user?.email;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          _Hero(
            name: loggedIn ? (user?.name.isNotEmpty ?? false ? user!.name : 'Account') : 'Guest',
            subtitle: loggedIn ? subtitle : 'Sign in to track orders & more',
            loggedIn: loggedIn,
            onAction: loggedIn
                ? () => _showProfile(context, user)
                : () => context.push('/login'),
          ),
          Transform.translate(
            offset: const Offset(0, -26),
            child: Column(
              children: [
                _QuickActions(
                  items: [
                    _Quick(Icons.account_balance_wallet_outlined, 'Wallet',
                        () => context.push('/wallet')),
                    _Quick(Icons.headset_mic_outlined, 'Support',
                        () => context.push('/help')),
                    _Quick(Icons.credit_card_outlined, 'Payments',
                        () => context.push('/payments')),
                  ],
                ),
                const SizedBox(height: 18),
                _MenuSection(
                  title: 'Your information',
                  items: [
                    _MenuItem(Icons.receipt_long_outlined, 'My orders', () => context.push('/orders')),
                    _MenuItem(Icons.favorite_border_rounded, 'My wishlist', () => context.push('/wishlist')),
                    _MenuItem(Icons.location_on_outlined, 'Saved addresses', () => context.push('/addresses')),
                    _MenuItem(Icons.place_outlined, 'Delivery location', () => context.push('/location')),
                  ],
                ),
                const SizedBox(height: 18),
                _MenuSection(
                  title: 'Other',
                  items: [
                    _MenuItem(Icons.headset_mic_outlined, 'Help & support', () => context.push('/help')),
                    _MenuItem(Icons.info_outline, 'About Shiplore', () => context.push('/about')),
                    if (loggedIn)
                      _MenuItem(
                        Icons.logout,
                        'Log out',
                        () async {
                          await context.read<AuthProvider>().logout();
                          if (context.mounted) context.go('/');
                        },
                        danger: true,
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                const Center(
                  child: Text(
                    'Shiplore • v1.0.0',
                    style: TextStyle(color: AppColors.inkSoft, fontSize: 12),
                  ),
                ),
                const SizedBox(height: 28),
              ],
            ),
          ),
        ],
      ).animate().fadeIn(duration: 300.ms),
    );
  }
}

void _showProfile(BuildContext context, AppUser? user) {
  if (user == null) return;
  final repo = context.read<CustomerRepository>();
  final auth = context.read<AuthProvider>();
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _ProfileSheet(user: user, repo: repo, auth: auth),
  );
}

class _ProfileSheet extends StatefulWidget {
  const _ProfileSheet({required this.user, required this.repo, required this.auth});
  final AppUser user;
  final CustomerRepository repo;
  final AuthProvider auth;

  @override
  State<_ProfileSheet> createState() => _ProfileSheetState();
}

class _ProfileSheetState extends State<_ProfileSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _emailCtrl;
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;
  String? _emailError;

  @override
  void initState() {
    super.initState();
    _nameCtrl  = TextEditingController(text: widget.user.name);
    _emailCtrl = TextEditingController(text: widget.user.email ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _emailError = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      final updated = await widget.repo.updateProfile(
        name: _nameCtrl.text.trim(),
        email: _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
      );
      await widget.auth.updateUser(updated);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated')),
        );
      }
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('CONFLICT') || msg.contains('already in use')) {
        setState(() {
          _saving = false;
          _emailError = 'Email is already in use by another account.';
        });
      } else {
        setState(() => _saving = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not update profile. Please try again.')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 0, 24, 40 + bottom),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Edit Profile',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            const SizedBox(height: 20),
            TextFormField(
              controller: _nameCtrl,
              maxLength: 80,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Name',
                prefixIcon: Icon(Icons.person_rounded),
                counterText: '',
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Name is required.' : null,
            ),
            const SizedBox(height: 14),
            if ((widget.user.phone ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Phone',
                    prefixIcon: Icon(Icons.phone_rounded),
                    suffixIcon: Icon(Icons.lock_outline, size: 16),
                  ),
                  child: Text(
                    widget.user.phone!,
                    style: const TextStyle(
                        fontSize: 15, color: AppColors.inkSoft),
                  ),
                ),
              ),
            TextFormField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: 'Email (optional)',
                prefixIcon: const Icon(Icons.email_rounded),
                errorText: _emailError,
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return null;
                if (!v.contains('@')) return 'Enter a valid email address.';
                return null;
              },
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 46)),
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Save changes'),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: _saving ? null : () => Navigator.pop(context),
              style: TextButton.styleFrom(
                  minimumSize: const Size(double.infinity, 40)),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}



class _Hero extends StatelessWidget {
  const _Hero({
    required this.name,
    required this.subtitle,
    required this.loggedIn,
    required this.onAction,
  });

  final String name;
  final String? subtitle;
  final bool loggedIn;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final initials = _initials(name);

    return Container(
      padding: EdgeInsets.fromLTRB(20, top + 18, 20, 44),
      decoration: const BoxDecoration(
        gradient: AppGradients.brand,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.30), width: 1.5),
            ),
            alignment: Alignment.center,
            child: loggedIn && initials.isNotEmpty
                ? Text(
                    initials,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 22),
                  )
                : const Icon(Icons.person_outline, color: Colors.white, size: 30),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 20),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.78), fontSize: 13.5),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          ScaleTap(
            onTap: onAction,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: BoxDecoration(
                color: loggedIn ? Colors.white.withValues(alpha: 0.14) : AppColors.cta,
                borderRadius: BorderRadius.circular(12),
                border: loggedIn ? Border.all(color: Colors.white.withValues(alpha: 0.30)) : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(loggedIn ? Icons.edit_outlined : Icons.login, color: Colors.white, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    loggedIn ? 'Edit' : 'Login',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13.5),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first).toUpperCase();
  }
}

class _Quick {
  const _Quick(this.icon, this.label, this.onTap);
  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.items});
  final List<_Quick> items;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          boxShadow: AppShadows.card,
        ),
        child: Row(
          children: [
            for (final q in items)
              Expanded(
                child: ScaleTap(
                  onTap: q.onTap,
                  child: Column(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: const BoxDecoration(color: AppColors.bgTint, shape: BoxShape.circle),
                        child: Icon(q.icon, color: AppColors.primary, size: 22),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        q.label,
                        style: const TextStyle(
                          color: AppColors.ink,
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
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
}

class _MenuItem {
  const _MenuItem(this.icon, this.label, this.onTap, {this.danger = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;
}

class _MenuSection extends StatelessWidget {
  const _MenuSection({required this.title, required this.items});
  final String title;
  final List<_MenuItem> items;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Text(
              title.toUpperCase(),
              style: const TextStyle(
                color: AppColors.inkSoft,
                fontWeight: FontWeight.w800,
                fontSize: 11.5,
                letterSpacing: 0.6,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              boxShadow: AppShadows.soft,
            ),
            child: Column(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  _Row(item: items[i]),
                  if (i != items.length - 1)
                    const Padding(
                      padding: EdgeInsets.only(left: 64),
                      child: Divider(height: 1, thickness: 1, color: AppColors.line),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.item});
  final _MenuItem item;

  @override
  Widget build(BuildContext context) {
    final color = item.danger ? AppColors.danger : AppColors.ink;
    final tint = item.danger ? AppColors.danger.withValues(alpha: 0.12) : AppColors.bgTint;
    final iconColor = item.danger ? AppColors.danger : AppColors.primary;

    return ScaleTap(
      onTap: item.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
              child: Icon(item.icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                item.label,
                style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ),
            Icon(Icons.chevron_right, color: item.danger ? AppColors.danger : AppColors.inkSoft, size: 22),
          ],
        ),
      ),
    );
  }
}
