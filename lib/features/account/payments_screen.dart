import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatx.dart';

class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({super.key});
  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _instruments = [];
  List<Map<String, dynamic>> _history = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await context.read<ApiClient>().get('/customer/payment-instruments') as Map;
      if (!mounted) return;
      setState(() {
        _instruments = ((data['instruments'] as List?) ?? [])
            .map((e) => (e as Map).cast<String, dynamic>()).toList();
        _history = ((data['history'] as List?) ?? [])
            .map((e) => (e as Map).cast<String, dynamic>()).toList();
        _loading = false;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() { _error = e.message; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _error = 'Could not load payment methods.'; _loading = false; });
    }
  }

  Future<void> _delete(int id) async {
    try {
      await context.read<ApiClient>().delete('/customer/payment-instruments/$id');
      setState(() => _instruments.removeWhere((e) => e['id'] == id));
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  Future<void> _setDefault(int id) async {
    try {
      await context.read<ApiClient>().post('/customer/payment-instruments/$id/default');
      setState(() {
        for (final e in _instruments) {
          e['is_default'] = e['id'] == id;
        }
      });
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  Future<void> _showAddSheet() async {
    final api = context.read<ApiClient>();
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddInstrumentSheet(api: api),
    );
    if (added == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Payment Methods'),
        actions: [
          TextButton.icon(
            onPressed: _showAddSheet,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add UPI'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, style: const TextStyle(color: AppColors.inkSoft)),
                      const SizedBox(height: 12),
                      FilledButton(onPressed: _load, child: const Text('Retry')),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: CustomScrollView(
                    slivers: [
                      // ── Saved instruments ────────────────────────────────────
                      SliverToBoxAdapter(
                        child: _SectionHeader(
                          icon: Icons.account_balance_wallet_outlined,
                          title: 'Saved UPI IDs',
                          action: TextButton(
                            onPressed: _showAddSheet,
                            child: const Text('+ Add'),
                          ),
                        ),
                      ),
                      if (_instruments.isEmpty)
                        const SliverToBoxAdapter(
                          child: _EmptyCard(
                            icon: Icons.contactless_outlined,
                            text: 'No saved UPI IDs yet.\nAdd one for faster checkout.',
                          ),
                        )
                      else
                        SliverList.separated(
                          itemCount: _instruments.length,
                          separatorBuilder: (_, _) =>
                              const Divider(height: 1, indent: 16, endIndent: 16, color: AppColors.line),
                          itemBuilder: (_, i) => _InstrumentTile(
                            item: _instruments[i],
                            onDelete: () => _delete(_instruments[i]['id'] as int),
                            onSetDefault: () => _setDefault(_instruments[i]['id'] as int),
                          ),
                        ),

                      const SliverToBoxAdapter(child: SizedBox(height: 16)),

                      // ── Payment history ──────────────────────────────────────
                      SliverToBoxAdapter(
                        child: _SectionHeader(
                          icon: Icons.receipt_long_rounded,
                          title: 'Payment History',
                        ),
                      ),
                      if (_history.isEmpty)
                        const SliverToBoxAdapter(
                          child: _EmptyCard(
                            icon: Icons.payment_rounded,
                            text: 'No payment history yet.',
                          ),
                        )
                      else
                        SliverList.separated(
                          itemCount: _history.length,
                          separatorBuilder: (_, _) =>
                              const Divider(height: 1, indent: 56, endIndent: 16, color: AppColors.line),
                          itemBuilder: (_, i) => _HistoryTile(txn: _history[i]),
                        ),
                      const SliverToBoxAdapter(child: SizedBox(height: 32)),
                    ],
                  ),
                ),
    );
  }
}

// ── Instrument tile ─────────────────────────────────────────────────────────

class _InstrumentTile extends StatelessWidget {
  const _InstrumentTile({required this.item, required this.onDelete, required this.onSetDefault});
  final Map<String, dynamic> item;
  final VoidCallback onDelete;
  final VoidCallback onSetDefault;

  @override
  Widget build(BuildContext context) {
    final type       = item['type'] as String? ?? 'upi';
    final label      = item['label'] as String? ?? type.toUpperCase();
    final instrument = item['instrument'] as String? ?? '';
    final isDefault  = item['is_default'] == true;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: AppColors.primary.withAlpha(14),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(_typeIcon(type), color: AppColors.primary, size: 20),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          if (isDefault)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.success.withAlpha(22),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text('DEFAULT',
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800,
                      color: AppColors.success, letterSpacing: 0.5)),
            ),
        ],
      ),
      subtitle: Text(instrument,
          style: const TextStyle(fontSize: 12, color: AppColors.inkSoft)),
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert_rounded, size: 18, color: AppColors.inkSoft),
        onSelected: (v) {
          if (v == 'default') onSetDefault();
          if (v == 'copy') {
            Clipboard.setData(ClipboardData(text: instrument));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Copied to clipboard')),
            );
          }
          if (v == 'delete') _confirmDelete(context);
        },
        itemBuilder: (_) => [
          if (!isDefault)
            const PopupMenuItem(value: 'default', child: Text('Set as default')),
          const PopupMenuItem(value: 'copy', child: Text('Copy')),
          const PopupMenuItem(
            value: 'delete',
            child: Text('Remove', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Remove payment method?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: const Text('This will remove the saved UPI ID.'),
        actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        actions: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton(
                onPressed: () { Navigator.pop(ctx); onDelete(); },
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Remove'),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: () => Navigator.pop(ctx),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  side: const BorderSide(color: AppColors.line, width: 1.5),
                  foregroundColor: AppColors.ink,
                ),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  IconData _typeIcon(String type) => switch (type) {
        'card' => Icons.credit_card_rounded,
        'netbanking' => Icons.account_balance_rounded,
        'wallet' => Icons.account_balance_wallet_rounded,
        _ => Icons.contactless_rounded,
      };
}

// ── History tile ─────────────────────────────────────────────────────────────

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.txn});
  final Map<String, dynamic> txn;

  @override
  Widget build(BuildContext context) {
    final method    = (txn['method'] as String? ?? '').toUpperCase();
    final status    = txn['status'] as String? ?? '';
    final amount    = (txn['amount'] as num?)?.toDouble() ?? 0;
    final orderNo   = txn['order_no'] as String? ?? '';
    final capturedAt = txn['captured_at']?.toString() ?? '';
    final dt        = DateTime.tryParse(capturedAt)?.toLocal();
    final dateStr   = dt != null ? DateFormat('d MMM yyyy').format(dt) : '—';

    final isSuccess = status == 'captured';
    final isRefund  = status == 'refunded';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: isRefund
              ? AppColors.info.withAlpha(18)
              : isSuccess
                  ? AppColors.success.withAlpha(18)
                  : AppColors.danger.withAlpha(18),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          isRefund
              ? Icons.undo_rounded
              : isSuccess
                  ? Icons.check_circle_outline_rounded
                  : Icons.cancel_outlined,
          color: isRefund
              ? AppColors.info
              : isSuccess ? AppColors.success : AppColors.danger,
          size: 20,
        ),
      ),
      title: Text(
        method.isEmpty ? 'Payment' : method,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        orderNo.isNotEmpty ? '$dateStr · #$orderNo' : dateStr,
        style: const TextStyle(fontSize: 11, color: AppColors.inkSoft),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            Formatx.money(amount),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          Text(
            isRefund ? 'Refunded' : isSuccess ? 'Paid' : status,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: isRefund
                  ? AppColors.info
                  : isSuccess ? AppColors.success : AppColors.danger,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Add instrument bottom sheet ───────────────────────────────────────────────

class _AddInstrumentSheet extends StatefulWidget {
  const _AddInstrumentSheet({required this.api});
  final ApiClient api;

  @override
  State<_AddInstrumentSheet> createState() => _AddInstrumentSheetState();
}

class _AddInstrumentSheetState extends State<_AddInstrumentSheet> {
  final _formKey  = GlobalKey<FormState>();
  final _upiCtrl  = TextEditingController();
  final _lblCtrl  = TextEditingController();
  bool _saving = false;
  String? _apiError;

  @override
  void dispose() {
    _upiCtrl.dispose();
    _lblCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() { _saving = true; _apiError = null; });
    try {
      await widget.api.post('/customer/payment-instruments', body: {
        'type': 'upi',
        'label': _lblCtrl.text.trim().isEmpty ? 'UPI' : _lblCtrl.text.trim(),
        'instrument': _upiCtrl.text.trim(),
      });
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      setState(() { _apiError = e.message; _saving = false; });
    } catch (_) {
      setState(() { _apiError = 'Could not save. Please try again.'; _saving = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottom),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.all(Radius.circular(24)),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withAlpha(14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.contactless_rounded, color: AppColors.primary, size: 20),
                ),
                const SizedBox(width: 12),
                const Text('Add UPI ID',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _upiCtrl,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              decoration: _field('UPI ID', 'e.g. yourname@paytm'),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'UPI ID is required';
                if (!RegExp(r'^[\w.\-]+@[\w]+$').hasMatch(v.trim())) {
                  return 'Enter a valid UPI ID (e.g. name@upi)';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _lblCtrl,
              textInputAction: TextInputAction.done,
              decoration: _field('Label (optional)', 'e.g. My Paytm, PhonePe'),
              onFieldSubmitted: (_) => _save(),
            ),
            if (_apiError != null) ...[
              const SizedBox(height: 10),
              Text(_apiError!, style: const TextStyle(color: AppColors.danger, fontSize: 12)),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _saving
                    ? const SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Save UPI ID', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _field(String label, String hint) => InputDecoration(
        labelText: label,
        hintText: hint,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      );
}

// ── Shared helpers ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.title, this.action});
  final IconData icon;
  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(title,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                    color: AppColors.inkSoft, letterSpacing: 0.7)),
          ),
          ?action,
        ],
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.bgTint,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.inkSoft, size: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Text(text,
                style: const TextStyle(color: AppColors.inkSoft, fontSize: 13, height: 1.5)),
          ),
        ],
      ),
    );
  }
}
