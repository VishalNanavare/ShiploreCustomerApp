import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../widgets/shiplore_logo.dart';
import '../../widgets/states.dart';

// Version injected at build time via --dart-define=APP_VERSION=x.y.z and
// --dart-define=APP_BUILD=n.  Falls back to pubspec values when not set.
const _kVersion = String.fromEnvironment('APP_VERSION', defaultValue: '1.0.0');
const _kBuild   = String.fromEnvironment('APP_BUILD',   defaultValue: '1');

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: AppColors.surface,
            foregroundColor: AppColors.ink,
            surfaceTintColor: AppColors.surface,
            automaticallyImplyLeading: false,
            leading: BackButton(onPressed: () => context.canPop() ? context.pop() : context.go('/account')),
            title: const Text('About Shiplore',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          ),
          SliverToBoxAdapter(
            child: Column(
              children: [
                // Hero
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 36),
                  decoration: const BoxDecoration(
                    color: AppColors.surface,
                    border: Border(bottom: BorderSide(color: AppColors.line)),
                  ),
                  child: Column(
                    children: [
                      const ShiploreLogo(size: 80),
                      const SizedBox(height: 16),
                      const Text('Shiplore',
                          style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 26,
                              color: AppColors.primary)),
                      const SizedBox(height: 4),
                      const Text(
                        'Quick commerce, delivered fast.',
                        style: TextStyle(color: AppColors.inkSoft, fontSize: 14),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.bgTint,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'Version $_kVersion (Build $_kBuild)',
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 12.5,
                              color: AppColors.inkSoft),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // About section
                _section(
                  context,
                  title: 'About',
                  children: [
                    _infoTile(
                      icon: Icons.store_rounded,
                      label: 'What is Shiplore?',
                      subtitle:
                          'Shiplore is a quick-commerce platform connecting you with local shops for fast delivery of groceries, electronics, fashion, and more — right to your doorstep.',
                    ),
                    _divider(),
                    _infoTile(
                      icon: Icons.bolt_rounded,
                      label: 'Our Mission',
                      subtitle:
                          'To make local commerce faster, smarter, and more accessible — so you get what you need in minutes, not days.',
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // Legal section
                _section(
                  context,
                  title: 'Legal',
                  children: [
                    _tapTile(
                      context: context,
                      icon: Icons.shield_outlined,
                      label: 'Privacy Policy',
                      onTap: () => _showPolicy(
                        context,
                        title: 'Privacy Policy',
                        body:
                            'Shiplore collects your name, phone number, email address, and delivery location to provide and improve our services. We use Firebase for phone number authentication and never share your personal data with third parties without your consent, except as required by law.\n\nYour payment information is processed securely via PayU — we do not store card or bank details on our servers.\n\nYou may request deletion of your account and personal data at any time by contacting support@shiplore.in.',
                      ),
                    ),
                    _divider(),
                    _tapTile(
                      context: context,
                      icon: Icons.description_outlined,
                      label: 'Terms of Service',
                      onTap: () => _showPolicy(
                        context,
                        title: 'Terms of Service',
                        body:
                            'By using Shiplore, you agree to use the app lawfully and not misuse our services. Orders placed are binding and subject to vendor acceptance. Prices displayed are indicative and may vary.\n\nShiplore acts as a marketplace platform connecting buyers and local vendors. We are not responsible for product quality but will mediate disputes in good faith.\n\nWe reserve the right to suspend accounts that violate these terms or engage in fraudulent activity.',
                      ),
                    ),
                    _divider(),
                    _tapTile(
                      context: context,
                      icon: Icons.replay_rounded,
                      label: 'Refund Policy',
                      onTap: () => _showPolicy(
                        context,
                        title: 'Refund Policy',
                        body:
                            'Refunds are issued for:\n• Items not delivered\n• Wrong items delivered\n• Damaged or defective products\n• Cancelled orders (before pickup)\n\nRefunds are processed within 5–7 business days to the original payment method. COD refunds are issued as bank transfer or store credit.\n\nTo initiate a return or refund, go to Account → My Orders → track the order → tap "Return" on the item.',
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // Contact section
                _section(
                  context,
                  title: 'Contact',
                  children: [
                    _copyTile(
                      context: context,
                      icon: Icons.email_rounded,
                      label: 'Email',
                      value: 'support@shiplore.in',
                    ),
                    _divider(),
                    _copyTile(
                      context: context,
                      icon: Icons.phone_rounded,
                      label: 'Phone',
                      value: '+91 98765 43210',
                    ),
                    _divider(),
                    _copyTile(
                      context: context,
                      icon: Icons.language_rounded,
                      label: 'Website',
                      value: 'www.shiplore.in',
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // App info
                _section(
                  context,
                  title: 'App Info',
                  children: [
                    _infoRow('App Version', '$_kVersion ($_kBuild)'),
                    _divider(),
                    _infoRow('Platform', 'iOS & Android'),
                    _divider(),
                    _infoRow('Made in', 'India 🇮🇳'),
                  ],
                ),

                const SizedBox(height: 32),
                const Center(
                  child: Text('© 2026 Shiplore. All rights reserved.',
                      style: TextStyle(color: AppColors.inkSoft, fontSize: 12)),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(BuildContext context,
      {required String title, required List<Widget> children}) {
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
                  letterSpacing: 0.6),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              boxShadow: AppShadows.soft,
            ),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }

  Widget _infoTile({required IconData icon, required String label, required String subtitle}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
                color: AppColors.bgTint, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: AppColors.primary, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.ink)),
                const SizedBox(height: 4),
                Text(subtitle,
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.inkSoft, height: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tapTile({
    required BuildContext context,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(0),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                  color: AppColors.bgTint, borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: AppColors.primary, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.ink)),
            ),
            const Icon(Icons.chevron_right, color: AppColors.inkSoft, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _copyTile({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String value,
  }) {
    return InkWell(
      onTap: () {
        Clipboard.setData(ClipboardData(text: value));
        showSnack(context, '$label copied');
      },
      borderRadius: BorderRadius.circular(0),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                  color: AppColors.bgTint, borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: AppColors.primary, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: AppColors.inkSoft)),
                  Text(value,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: AppColors.ink)),
                ],
              ),
            ),
            const Icon(Icons.copy_rounded, color: AppColors.inkSoft, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        children: [
          Text(label,
              style: const TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.inkSoft)),
          const Spacer(),
          Text(value,
              style: const TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.ink)),
        ],
      ),
    );
  }

  Widget _divider() =>
      const Padding(padding: EdgeInsets.only(left: 62), child: Divider(height: 1, color: AppColors.line));

  void _showPolicy(BuildContext context, {required String title, required String body}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        expand: false,
        builder: (_, ctrl) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(title,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: ctrl,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                child: Text(body,
                    style: const TextStyle(
                        fontSize: 14, color: AppColors.inkSoft, height: 1.7)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
