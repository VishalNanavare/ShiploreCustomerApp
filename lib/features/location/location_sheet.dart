import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/address.dart';
import '../../data/repositories/address_repository.dart';
import '../../providers/location_provider.dart';
import '../../widgets/app_scale_tap.dart';
import '../../widgets/states.dart';

/// Blinkit-style "Select delivery location" sheet: current location, add new,
/// and saved addresses. Sets the chosen location via [LocationProvider].
Future<void> showLocationSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (_) => const _LocationSheet(),
  );
}

class _LocationSheet extends StatefulWidget {
  const _LocationSheet();
  @override
  State<_LocationSheet> createState() => _LocationSheetState();
}

class _LocationSheetState extends State<_LocationSheet> {
  late final Future<List<Address>> _addrs = context.read<AddressRepository>().list();
  bool _locating = false;

  Future<void> _useCurrent() async {
    setState(() => _locating = true);
    final provider = context.read<LocationProvider>();
    try {
      final loc = await provider.detectCurrent();
      await provider.set(loc);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (!mounted) return;
      setState(() => _locating = false);
      showSnack(context, 'Could not get location. Enable GPS & permission.', error: true);
    }
  }

  Future<void> _pick(Address a) async {
    if (a.latitude == null || a.longitude == null) {
      showSnack(context, 'This address has no map pin yet. Edit it to drop one.', error: true);
      return;
    }
    await context.read<LocationProvider>().set(DeliveryLocation(
          lat: a.latitude!,
          lng: a.longitude!,
          label: a.label,
          line1: a.line1,
          city: a.city,
          stateCode: a.stateCode,
          pincode: a.pincode,
          formatted: a.oneLine,
        ));
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Row(
              children: [
                const Text('Select delivery location', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                const Spacer(),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
              ],
            ),
            const SizedBox(height: 6),
            _ActionTile(
              icon: Icons.my_location_rounded,
              color: AppColors.cta,
              title: 'Use current location',
              subtitle: _locating ? 'Detecting…' : 'Fastest way to set your spot',
              busy: _locating,
              onTap: _locating ? null : _useCurrent,
            ),
            const SizedBox(height: 10),
            _ActionTile(
              icon: Icons.add_location_alt_outlined,
              color: AppColors.primary,
              title: 'Add a new address',
              subtitle: 'Pick the exact spot on the map',
              onTap: () {
                Navigator.pop(context);
                context.push('/location');
              },
            ),
            const SizedBox(height: 18),
            const Text('SAVED ADDRESSES',
                style: TextStyle(color: AppColors.inkSoft, fontWeight: FontWeight.w700, fontSize: 11.5, letterSpacing: 0.4)),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.36),
              child: FutureBuilder<List<Address>>(
                future: _addrs,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Padding(padding: EdgeInsets.all(16), child: Center(child: SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2))));
                  }
                  final list = snap.data ?? const <Address>[];
                  if (list.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text('No saved addresses yet.', style: TextStyle(color: AppColors.inkSoft)),
                    );
                  }
                  return ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _AddressTile(address: list[i], onTap: () => _pick(list[i])),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.icon, required this.color, required this.title, required this.subtitle, this.onTap, this.busy = false});
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool busy;
  @override
  Widget build(BuildContext context) {
    return ScaleTap(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), boxShadow: AppShadows.soft),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: busy
                  ? const Padding(padding: EdgeInsets.all(11), child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: color)),
                  Text(subtitle, style: const TextStyle(color: AppColors.inkSoft, fontSize: 12.5)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.inkSoft),
          ],
        ),
      ),
    );
  }
}

class _AddressTile extends StatelessWidget {
  const _AddressTile({required this.address, required this.onTap});
  final Address address;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return ScaleTap(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(color: AppColors.bgTint, shape: BoxShape.circle),
              child: Icon(
                address.label.toLowerCase().contains('work') ? Icons.work_outline_rounded : Icons.home_outlined,
                color: AppColors.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(address.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                      if (address.isDefault) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(color: AppColors.cta.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(6)),
                          child: const Text('Default', style: TextStyle(color: AppColors.ctaDark, fontSize: 10, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(address.oneLine, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.inkSoft, fontSize: 12.5)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
