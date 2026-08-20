import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../data/repositories/customer_repository.dart';
import '../../widgets/states.dart';

class HelpScreen extends StatefulWidget {
  const HelpScreen({super.key});
  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  int? _expandedIndex;

  static const _faqs = [
    _FaqSection(
      title: 'Orders & Delivery',
      icon: Icons.local_shipping_rounded,
      color: AppColors.info,
      items: [
        _FaqItem(
          q: 'When will my order be delivered?',
          a: 'Delivery time depends on your location and the shop. Estimated delivery time is shown on the checkout screen and in your order tracking page. Most orders arrive within 30–90 minutes.',
        ),
        _FaqItem(
          q: 'How do I track my order?',
          a: 'Go to Account → My Orders, then tap "Track" on any active order. You can see real-time status updates, delivery partner details, and estimated arrival time.',
        ),
        _FaqItem(
          q: 'Can I cancel my order?',
          a: 'You can cancel individual items from the Order Tracking page as long as the status is "Confirmed", "Accepted", "Packed", or "Ready". Tap the item card and select "Cancel item". Once a delivery partner picks up your order, cancellation is not available.',
        ),
        _FaqItem(
          q: 'What if my order is delayed?',
          a: 'If your order is significantly delayed, you can contact our support team. We will check with the store and delivery partner and keep you updated. Excessive delays may qualify for a refund.',
        ),
        _FaqItem(
          q: 'My order shows delivered but I haven\'t received it.',
          a: 'This can happen if the delivery partner marked it delivered incorrectly. Please contact us within 24 hours of the delivery time shown, and we will investigate and issue a refund if confirmed.',
        ),
      ],
    ),
    _FaqSection(
      title: 'Returns & Refunds',
      icon: Icons.assignment_return_rounded,
      color: AppColors.success,
      items: [
        _FaqItem(
          q: 'How do I return an item?',
          a: 'Go to Account → My Orders → find the delivered order → tap "Return" on the item you want to return. Select the items and provide a reason. Our team will review and arrange a pickup.',
        ),
        _FaqItem(
          q: 'How long do refunds take?',
          a: 'Refunds are processed within 5–7 business days after the return is approved. The amount is credited to the original payment method. For COD orders, refunds are issued as store credit or bank transfer.',
        ),
        _FaqItem(
          q: 'What items can be returned?',
          a: 'Most items can be returned within 7 days of delivery if they are unused and in original packaging. Perishables, personal care items, and customised products are generally non-returnable.',
        ),
        _FaqItem(
          q: 'I received the wrong item.',
          a: 'We are sorry about that. Please contact us immediately with a photo of what you received. We will arrange a free return and send the correct item as soon as possible.',
        ),
      ],
    ),
    _FaqSection(
      title: 'Payments',
      icon: Icons.payment_rounded,
      color: AppColors.cta,
      items: [
        _FaqItem(
          q: 'What payment methods are accepted?',
          a: 'We accept Cash on Delivery (COD) and online payments via UPI, credit/debit cards, and net banking through our secure PayU payment gateway.',
        ),
        _FaqItem(
          q: 'My payment failed but money was deducted.',
          a: 'Do not worry — failed payment deductions are automatically reversed within 5–7 business days by your bank. If you do not receive the refund after 7 days, please contact your bank with the transaction reference.',
        ),
        _FaqItem(
          q: 'Is my payment information safe?',
          a: 'Yes. We never store your card or bank details. All payments are processed securely via PayU\'s PCI-DSS compliant gateway with end-to-end encryption.',
        ),
        _FaqItem(
          q: 'Can I pay using a coupon or discount code?',
          a: 'Yes. Enter your coupon code on the checkout screen in the "Add a coupon" section. Valid coupons are automatically applied to your order total.',
        ),
      ],
    ),
    _FaqSection(
      title: 'Account & Profile',
      icon: Icons.person_rounded,
      color: AppColors.primary,
      items: [
        _FaqItem(
          q: 'How do I log in?',
          a: 'You can log in using your mobile number (OTP verification) or email and password. Phone OTP login is recommended for fastest access.',
        ),
        _FaqItem(
          q: 'I forgot my password.',
          a: 'Use "Login with OTP" instead of password. Enter your registered phone number or email and verify with the OTP sent to you. You can reset your password from Account settings after logging in.',
        ),
        _FaqItem(
          q: 'How do I save a delivery address?',
          a: 'Go to Account → Saved Addresses and tap the + button to add a new address. You can pick your location on the map, add house/flat details, label it (Home/Work/Other), and set it as your default address.',
        ),
        _FaqItem(
          q: 'Can I use the app without creating an account?',
          a: 'Yes! You can browse products and add items to the cart without an account. However, you will need to log in to place an order, save addresses, or access your order history.',
        ),
      ],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() {
          _query = _searchCtrl.text.trim().toLowerCase();
          _expandedIndex = null;
        }));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<_FaqItem> get _searchResults {
    if (_query.isEmpty) return [];
    final results = <_FaqItem>[];
    for (final section in _faqs) {
      for (final item in section.items) {
        if (item.q.toLowerCase().contains(_query) || item.a.toLowerCase().contains(_query)) {
          results.add(item);
        }
      }
    }
    return results;
  }

  @override
  Widget build(BuildContext context) {
    final results = _searchResults;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 130,
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            surfaceTintColor: AppColors.primary,
            automaticallyImplyLeading: false,
            leading: BackButton(
              color: Colors.white,
              onPressed: () => context.canPop() ? context.pop() : context.go('/account'),
            ),
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.fromLTRB(56, 0, 16, 16),
              title: const Text(
                'Help & Support',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18),
              ),
              background: Container(
                decoration: const BoxDecoration(
                  gradient: AppGradients.brand,
                ),
                child: Align(
                  alignment: Alignment.bottomRight,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 24, bottom: 30),
                    child: Icon(Icons.support_agent_rounded,
                        size: 64, color: Colors.white.withValues(alpha: 0.15)),
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Column(
              children: [
                // Contact row
                _ContactRow(context: context),
                // Search
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: 'Search help articles…',
                      hintStyle: const TextStyle(fontSize: 13.5, color: AppColors.inkSoft),
                      prefixIcon: const Icon(Icons.search_rounded, color: AppColors.inkSoft, size: 20),
                      suffixIcon: _query.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.inkSoft),
                              onPressed: _searchCtrl.clear,
                            )
                          : null,
                      filled: true,
                      fillColor: AppColors.surface,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppColors.line)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
                    ),
                  ),
                ),
                if (_query.isNotEmpty) ...[
                  if (results.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 40),
                      child: Column(children: [
                        const Icon(Icons.search_off_rounded, size: 40, color: AppColors.inkSoft),
                        const SizedBox(height: 12),
                        Text('No results for "$_query"',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                        const SizedBox(height: 6),
                        const Text(
                          'Try different keywords or browse topics below.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.inkSoft, fontSize: 13),
                        ),
                      ]),
                    )
                  else
                    _SearchResultsList(items: results),
                ] else ...[
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 8, 16, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Frequently Asked Questions',
                          style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                              color: AppColors.ink)),
                    ),
                  ),
                  ..._faqs.asMap().entries.map((e) => _SectionAccordion(
                        section: e.value,
                        sectionIndex: e.key,
                        expandedIndex: _expandedIndex,
                        onToggle: (i) => setState(() =>
                            _expandedIndex = _expandedIndex == i ? null : i),
                      )),
                ],
                const SizedBox(height: 32),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Contact Row ────────────────────────────────────────────────────────────────

class _ContactRow extends StatelessWidget {
  const _ContactRow({required this.context});
  final BuildContext context;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          boxShadow: AppShadows.card,
        ),
        child: Column(
          children: [
            Row(
              children: [
                _contactBtn(
                  context: context,
                  icon: Icons.chat_rounded,
                  label: 'WhatsApp',
                  color: const Color(0xFF25D366),
                  onTap: () => _showContactDialog(
                    context,
                    title: 'Chat on WhatsApp',
                    detail: '+91 98765 43210',
                    icon: Icons.chat_rounded,
                    color: const Color(0xFF25D366),
                    hint: 'Open WhatsApp and message us at this number',
                  ),
                ),
                _contactBtn(
                  context: context,
                  icon: Icons.email_rounded,
                  label: 'Email',
                  color: AppColors.info,
                  onTap: () => _showContactDialog(
                    context,
                    title: 'Email Us',
                    detail: 'support@shiplore.in',
                    icon: Icons.email_rounded,
                    color: AppColors.info,
                    hint: 'We respond within 24 hours on business days',
                  ),
                ),
                _contactBtn(
                  context: context,
                  icon: Icons.call_rounded,
                  label: 'Call Us',
                  color: AppColors.cta,
                  onTap: () => _showContactDialog(
                    context,
                    title: 'Call Support',
                    detail: '+91 98765 43210',
                    icon: Icons.call_rounded,
                    color: AppColors.cta,
                    hint: 'Available Mon–Sat, 9 AM to 7 PM IST',
                  ),
                ),
              ],
            ),
            const Divider(height: 20, indent: 12, endIndent: 12),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _showTicketSheet(context),
                  icon: const Icon(Icons.confirmation_number_outlined, size: 18),
                  label: const Text('Raise a Support Ticket'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _contactBtn({
    required BuildContext context,
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: 7),
            Text(label,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 12.5, color: AppColors.ink)),
          ],
        ),
      ),
    );
  }

  void _showContactDialog(
    BuildContext context, {
    required String title,
    required String detail,
    required IconData icon,
    required Color color,
    required String hint,
  }) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 10),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(detail,
                  style: TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 18, color: color)),
            ),
            const SizedBox(height: 10),
            Text(hint, style: const TextStyle(color: AppColors.inkSoft, fontSize: 13)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: detail));
              Navigator.pop(context);
              showSnack(context, 'Copied to clipboard');
            },
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: const Text('Copy'),
          ),
        ],
      ),
    );
  }
}

// ── FAQ Section Accordion ──────────────────────────────────────────────────────

class _SectionAccordion extends StatelessWidget {
  const _SectionAccordion({
    required this.section,
    required this.sectionIndex,
    required this.expandedIndex,
    required this.onToggle,
  });
  final _FaqSection section;
  final int sectionIndex;
  final int? expandedIndex;
  final ValueChanged<int> onToggle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: AppShadows.card,
        ),
        child: Column(
          children: [
            // Section header
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
              child: Row(
                children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: section.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(section.icon, color: section.color, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Text(section.title,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: section.color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('${section.items.length}',
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: section.color)),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.line),
            // FAQ items
            ...section.items.asMap().entries.map((e) {
              final globalIdx = sectionIndex * 100 + e.key;
              final expanded = expandedIndex == globalIdx;
              return _FaqTile(
                item: e.value,
                isLast: e.key == section.items.length - 1,
                expanded: expanded,
                onTap: () => onToggle(globalIdx),
                accentColor: section.color,
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _FaqTile extends StatelessWidget {
  const _FaqTile({
    required this.item,
    required this.isLast,
    required this.expanded,
    required this.onTap,
    required this.accentColor,
  });
  final _FaqItem item;
  final bool isLast;
  final bool expanded;
  final VoidCallback onTap;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(0),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    item.q,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                      color: expanded ? accentColor : AppColors.ink,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedRotation(
                  turns: expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(Icons.keyboard_arrow_down_rounded,
                      color: expanded ? accentColor : AppColors.inkSoft, size: 22),
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox(width: double.infinity),
          secondChild: Container(
            width: double.infinity,
            color: accentColor.withValues(alpha: 0.04),
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Text(item.a,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.inkSoft, height: 1.55)),
          ),
          crossFadeState:
              expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 200),
        ),
        if (!isLast)
          const Padding(
            padding: EdgeInsets.only(left: 14),
            child: Divider(height: 1, color: AppColors.line),
          ),
      ],
    );
  }
}

// ── Search Results ─────────────────────────────────────────────────────────────

class _SearchResultsList extends StatefulWidget {
  const _SearchResultsList({required this.items});
  final List<_FaqItem> items;
  @override
  State<_SearchResultsList> createState() => _SearchResultsListState();
}

class _SearchResultsListState extends State<_SearchResultsList> {
  int? _expanded;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: AppShadows.card,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
              child: Text('${widget.items.length} result${widget.items.length != 1 ? 's' : ''}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: AppColors.inkSoft)),
            ),
            const Divider(height: 1, color: AppColors.line),
            ...widget.items.asMap().entries.map((e) => _FaqTile(
                  item: e.value,
                  isLast: e.key == widget.items.length - 1,
                  expanded: _expanded == e.key,
                  onTap: () => setState(
                      () => _expanded = _expanded == e.key ? null : e.key),
                  accentColor: AppColors.primary,
                )),
          ],
        ),
      ),
    );
  }
}

// ── Support Ticket Sheet ───────────────────────────────────────────────────────

void _showTicketSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _TicketSheet(repo: context.read<CustomerRepository>()),
  );
}

class _TicketSheet extends StatefulWidget {
  const _TicketSheet({required this.repo});
  final CustomerRepository repo;

  @override
  State<_TicketSheet> createState() => _TicketSheetState();
}

class _TicketSheetState extends State<_TicketSheet> {
  final _subjectCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final subject = _subjectCtrl.text.trim();
    final message = _messageCtrl.text.trim();
    if (subject.isEmpty || message.isEmpty) {
      setState(() => _error = 'Please fill in both subject and message.');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await widget.repo.createSupportTicket(subject: subject, message: message);
      if (!mounted) return;
      Navigator.pop(context);
      showSnack(context, 'Ticket submitted! We\'ll get back to you soon.');
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = 'Failed to submit ticket. Please try again.'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottom),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.confirmation_number_outlined, color: AppColors.primary, size: 22),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Raise a Support Ticket',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.ink),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 20, color: AppColors.inkSoft),
                onPressed: () => Navigator.pop(context),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Describe your issue and our team will respond within 24 hours.',
            style: TextStyle(color: AppColors.inkSoft, fontSize: 13),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _subjectCtrl,
            textInputAction: TextInputAction.next,
            enabled: !_loading,
            decoration: _inputDecor('Subject (e.g. "Order not delivered")'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _messageCtrl,
            maxLines: 4,
            textInputAction: TextInputAction.newline,
            enabled: !_loading,
            decoration: _inputDecor('Describe your issue in detail…'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _loading ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
              child: _loading
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Submit Ticket'),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecor(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.inkSoft, fontSize: 13.5),
        filled: true,
        fillColor: AppColors.bg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.line)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
      );
}

// ── Data classes ───────────────────────────────────────────────────────────────

class _FaqSection {
  const _FaqSection({
    required this.title,
    required this.icon,
    required this.color,
    required this.items,
  });
  final String title;
  final IconData icon;
  final Color color;
  final List<_FaqItem> items;
}

class _FaqItem {
  const _FaqItem({required this.q, required this.a});
  final String q;
  final String a;
}
