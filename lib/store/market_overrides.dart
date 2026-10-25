import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
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
        driverApplicationScreenProvider,
        driverApprovalProvider,
        navigateProvider,
        proofPhotoProvider,
        Plan,
        waterRepositoryProvider,
        waterUtilityProvider;
import '../driver/driver_application.dart';
import '../members/application_screen.dart';
import '../members/members_service.dart';
import '../services/auth_service.dart';
import '../services/proof_photo.dart';
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
      // Drivers: directions open in the phone's maps app, and delivery proof is a
      // real camera photo.
      navigateProvider.overrideWithValue((destination) => launchUrl(
            Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${Uri.encodeComponent(destination)}'),
            mode: LaunchMode.externalApplication,
          )),
      proofPhotoProvider.overrideWithValue(() async => (await pickProofPhoto()) != null),
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
        // Drivers apply in the app and Nolifa staff approve them; the server
        // only gives delivery jobs to approved drivers.
        driverApplicationScreenProvider.overrideWithValue(() => const DriverApplicationScreen()),
        driverApprovalProvider.overrideWith((ref) => ref.watch(approvedDriverProvider).valueOrNull),
        // The plan, and so the commission, is set by Nolifa after payment.
        sellerPlanProvider.overrideWith((ref) {
          final p = ref.watch(serverPlanProvider).valueOrNull ?? 'starter';
          return Plan.values.firstWhere((x) => x.name == p, orElse: () => Plan.starter);
        }),
      ],
      // On the shared backend only an account Nolifa has granted the water
      // provider permission can answer requests; the server refuses anyone else.
      // On the phone alone, a farm that registers as a supplier gets the desk.
      waterUtilityProvider.overrideWith((ref) {
        if (SupabaseBoot.ready) {
          ref.watch(currentUserProvider.select((u) => u?.uid));
          return SupabaseBoot.client.auth.currentUser?.appMetadata['utility'] == true;
        }
        return ref.watch(supplierProvider).supplier.enabled;
      }),
    ];
