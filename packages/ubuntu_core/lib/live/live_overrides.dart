import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../market/market_store.dart' show marketStartsLiveProvider;
import '../roads/supabase_road_repository.dart';
import '../roads/road_repository.dart';
import '../roads/road_store.dart' show roadRepositoryProvider;
import '../warehouse/warehouse_repository.dart';
import '../delivery/hub_desk.dart' show hubStaffProvider;
import '../warehouse/warehouse_store.dart' show certifierProvider, warehouseRepositoryProvider;
import 'staff.dart';
import 'device_location.dart';
import 'location.dart';

/// What every shipped app does the same way: show no demo content, read the
/// phone's real position, and keep road warnings and warehouse records in the
/// shared database once it is connected (on the phone until then).
///
/// [ready] is asked when each provider is first read, because the apps do not
/// know whether Supabase came up when this list is built.
List<Override> liveOverrides(bool Function() ready) => [
      marketStartsLiveProvider.overrideWithValue(true),
      userLocationProvider.overrideWith((ref) => deviceLocation()),
      roadRepositoryProvider.overrideWith(
          (ref) => ready() ? SupabaseRoadRepository() : LocalRoadRepository(seeds: false)),
      hubStaffProvider.overrideWith((ref) => ready() && (ref.watch(staffRolesProvider).valueOrNull?.hub ?? false)),
      certifierProvider.overrideWith((ref) => ready() && (ref.watch(staffRolesProvider).valueOrNull?.certifier ?? false)),
      warehouseRepositoryProvider.overrideWith(
          (ref) => ready() ? SupabaseWarehouseRepository() : LocalWarehouseRepository()),
    ];
