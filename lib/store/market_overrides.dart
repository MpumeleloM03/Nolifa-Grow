import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ubuntu_core/ubuntu_core.dart'
    show
        SupabaseBoot,
        SupabaseMarketRepository,
        SupabaseWaterRepository,
        liveOverrides,
        LocalMarketRepository,
        LocalWaterRepository,
        marketNameProvider,
        marketRepositoryProvider,
        marketUidProvider,
        waterRepositoryProvider,
        waterUtilityProvider;
import '../services/auth_service.dart';
import '../water/supplier_store.dart';

/// Plugs the shared Nolifa Drop package into Nolifa's own sign-in and storage,
/// so a farmer is the same person in both apps and shares the same Supabase database.
///
/// Supabase is checked when each provider is first read, not here, because
/// this list is built before the app knows whether it came up.
List<Override> marketOverrides() => [
      ...liveOverrides(() => SupabaseBoot.ready),
      marketUidProvider.overrideWith(
          (ref) => ref.watch(currentUserProvider)?.uid ?? 'guest'),
      marketNameProvider.overrideWith((ref) {
        final name = ref.watch(currentUserProvider)?.name.trim() ?? '';
        return name.isEmpty ? 'Neighbour' : name.split(' ').first;
      }),
      marketRepositoryProvider.overrideWith((ref) => SupabaseBoot.ready
          ? SupabaseMarketRepository()
          : LocalMarketRepository()),
      waterRepositoryProvider.overrideWith((ref) => SupabaseBoot.ready
          ? SupabaseWaterRepository()
          : LocalWaterRepository()),
      // A farm that registers as a water supplier can answer community requests.
      waterUtilityProvider.overrideWith((ref) => ref.watch(supplierProvider).supplier.enabled),
    ];
