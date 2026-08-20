import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../providers/wishlist_provider.dart';
import '../../widgets/product_card.dart';
import '../../widgets/skeletons.dart';
import '../../widgets/states.dart';
import '../cart/cart_bar.dart';

/// The customer's saved (wishlisted) products — a 2-up grid of [ProductCard]
/// (each card's heart un-saves it). Account-synced; prompts login when signed out.
class WishlistScreen extends StatefulWidget {
  const WishlistScreen({super.key});

  @override
  State<WishlistScreen> createState() => _WishlistScreenState();
}

class _WishlistScreenState extends State<WishlistScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && context.read<AuthProvider>().isLoggedIn) {
        context.read<WishlistProvider>().load();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final w = context.watch<WishlistProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          auth.isLoggedIn && w.count > 0 ? 'Wishlist · ${w.count}' : 'Wishlist',
        ),
        leading: BackButton(onPressed: () => context.canPop() ? context.pop() : context.go('/')),
      ),
      bottomNavigationBar: const CartBar(),
      body: !auth.isLoggedIn
          ? EmptyView(
              type: EmptyType.wishlist,
              title: 'Sign in to view your wishlist',
              subtitle: 'Save items you love and find them here.',
              action: ElevatedButton(
                onPressed: () => context.push('/login'),
                child: const Text('Login'),
              ),
            )
          : (w.loading && w.isEmpty)
          ? const ProductGridSkeleton()
          : w.isEmpty
          ? const EmptyView(
              type: EmptyType.wishlist,
              title: 'Your wishlist is empty',
              subtitle: 'Tap the heart on any product to save it here.',
            )
          : RefreshIndicator(
              onRefresh: () => context.read<WishlistProvider>().load(),
              child: GridView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: w.items.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  mainAxisExtent: 232,
                ),
                itemBuilder: (_, i) => ProductCard(product: w.items[i]),
              ),
            ),
    );
  }
}
