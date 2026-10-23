import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'market_models.dart';
import 'market_store.dart';
import '../water/water_screens.dart';
import 'shop_screens.dart';

/// One place that decides what tapping an alert does, so the shop, store and
/// alert feed all behave the same way.
///
/// Farm-side alerts (outbreaks, frost) are handed to [onFarmAlert], because the
/// screens they open (crop scan, herd register) belong to the farm app.
void handleAlert(BuildContext context, WidgetRef ref, MarketAlert a,
    {VoidCallback? openListing, void Function(MarketAlert)? onFarmAlert}) {
  HapticFeedback.mediumImpact();
  if (a.farmSide) {
    if (a.id == 'a-frost') {
      openListing?.call();
    } else {
      onFarmAlert?.call(a);
    }
    return;
  }
  if (a.id.startsWith('w-')) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const WaterScreen()));
    return;
  }
  if (a.bundle.isNotEmpty) {
    ref.read(marketProvider.notifier).loadBundle(a);
    Navigator.push(context, MaterialPageRoute(builder: (_) => const CheckoutScreen()));
  }
}
