import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ubuntu_core/ubuntu_core.dart'
    show
        SupabaseBoot,
        SupabaseMarketRepository,
        SupabaseWaterRepository,
        farmApplicationScreenProvider,
        liveOverrides,
        sellerApprovalProvider,
        sellerPlanProvider,

        LocalMarketRepository,
        LocalWaterRepository,
        marketNameProvider,
        marketRepositoryProvider,
        marketUidProvider,
        Plan,
        waterRepositoryProvider,
        waterUtilityProvider;
import '../members/application_screen.dart';
import '../members/members_service.dart';
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
      // Selling needs Nolifa staff to approve the farm application.
      if (SupabaseBoot.ready) ...[
        sellerApprovalProvider.overrideWith((ref) {
          final st = ref.watch(applicationProvider.select((a) => a.valueOrNull?['status']));
          return st == 'approved';
        }),
        farmApplicationScreenProvider.overrideWithValue(() => const FarmApplicationScreen()),
        // The plan, and so the commission, is set by Nolifa after payment.
        sellerPlanProvider.overrideWith((ref) {
          final p = ref.watch(serverPlanProvider).valueOrNull ?? 'starter';
          return Plan.values.firstWhere((x) => x.name == p, orElse: () => Plan.starter);
        }),
      ],
      // A farm that registers as a water supplier can answer community requests.
      waterUtilityProvider.overrideWith((ref) => ref.watch(supplierProvider).supplier.enabled),
    ];
