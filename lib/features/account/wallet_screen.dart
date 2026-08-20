import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatx.dart';
import '../../data/repositories/order_repository.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});
  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  bool _loading = true;
  String? _error;
  double _balance = 0;
  String _currency = 'INR';
  String _status = 'active';
  List<Map<String, dynamic>> _txns = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await context.read<OrderRepository>().walletData() as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _balance  = (data['balance'] as num?)?.toDouble() ?? 0;
        _currency = (data['currency'] as String?) ?? 'INR';
        _status   = (data['status'] as String?) ?? 'active';
        _txns     = ((data['transactions'] as List?) ?? [])
            .map((e) => (e as Map).cast<String, dynamic>())
            .toList();
        _loading  = false;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() { _error = e.message; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _error = 'Could not load wallet.'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Wallet')),
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
                      SliverToBoxAdapter(child: _buildBalanceCard()),
                      if (_txns.isEmpty)
                        const SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(
                            child: Text(
                              'No transactions yet.',
                              style: TextStyle(color: AppColors.inkSoft, fontSize: 14),
                            ),
                          ),
                        )
                      else ...[
                        const SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                            child: Text(
                              'TRANSACTION HISTORY',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                                  color: AppColors.inkSoft, letterSpacing: 0.7),
                            ),
                          ),
                        ),
                        SliverList.separated(
                          itemCount: _txns.length,
                          separatorBuilder: (_, _) =>
                              const Divider(height: 1, indent: 56, endIndent: 16, color: AppColors.line),
                          itemBuilder: (_, i) => _TxnTile(txn: _txns[i]),
                        ),
                        const SliverToBoxAdapter(child: SizedBox(height: 24)),
                      ],
                    ],
                  ),
                ),
    );
  }

  Widget _buildBalanceCard() {
    final frozen = _status == 'frozen';
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1C3C6B), Color(0xFF0B1E38)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_balance_wallet_rounded, color: Colors.white70, size: 18),
              const SizedBox(width: 8),
              const Text('Shiplore Wallet',
                  style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500)),
              const Spacer(),
              if (frozen)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withAlpha(60),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text('FROZEN',
                      style: TextStyle(color: AppColors.danger, fontSize: 10, fontWeight: FontWeight.w800)),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            Formatx.money(_balance),
            style: const TextStyle(color: Colors.white, fontSize: 32,
                fontWeight: FontWeight.w800, height: 1.0),
          ),
          const SizedBox(height: 4),
          Text(
            _currency,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 16),
          Text(
            frozen
                ? 'Wallet frozen — contact support.'
                : 'Credits are applied automatically at checkout.',
            style: const TextStyle(color: Colors.white60, fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _TxnTile extends StatelessWidget {
  const _TxnTile({required this.txn});
  final Map<String, dynamic> txn;

  @override
  Widget build(BuildContext context) {
    final isCredit = txn['type'] == 'credit';
    final amount   = (txn['amount'] as num?)?.toDouble() ?? 0;
    final reason   = (txn['reason'] as String?) ?? (isCredit ? 'Credit' : 'Debit');
    final refType  = (txn['ref_type'] as String?) ?? '';
    final dateStr  = txn['created_at']?.toString() ?? '';
    final dt       = DateTime.tryParse(dateStr)?.toLocal();
    final formatted = dt != null ? DateFormat('d MMM yyyy, h:mm a').format(dt) : dateStr;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: isCredit
              ? AppColors.success.withAlpha(22)
              : AppColors.danger.withAlpha(22),
          shape: BoxShape.circle,
        ),
        child: Icon(
          isCredit ? Icons.add_rounded : Icons.remove_rounded,
          color: isCredit ? AppColors.success : AppColors.danger,
          size: 18,
        ),
      ),
      title: Text(
        reason,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        refType.isNotEmpty ? '$formatted · $refType' : formatted,
        style: const TextStyle(fontSize: 11, color: AppColors.inkSoft),
      ),
      trailing: Text(
        '${isCredit ? '+' : '−'}${Formatx.money(amount)}',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: isCredit ? AppColors.success : AppColors.danger,
        ),
      ),
    );
  }
}
