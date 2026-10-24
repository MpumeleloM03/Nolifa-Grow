import 'package:flutter/material.dart' hide Text;
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../../models/cattle.dart';
import '../../models/health_event.dart';
import '../../models/species.dart';
import '../../services/auth_service.dart';
import '../../services/cattle_service.dart';
import '../../services/region_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/glass.dart';
import 'animal_detail_screen.dart';
import 'herd_widgets.dart';

import 'package:ubuntu_core/tr_text.dart' show Text;
/// Sick animals that sit within this distance of each other may be spreading
/// something between them.
const clusterMetres = 1500.0;

/// Groups of two or more sick animals close together. Each group is a list of
/// animals; animals are only listed once.
List<List<Cattle>> sickClusters(Iterable<Cattle> sick) {
  const d = Distance();
  final left = [for (final a in sick) if (a.hasLocation) a];
  final groups = <List<Cattle>>[];
  while (left.isNotEmpty) {
    final group = [left.removeLast()];
    var grew = true;
    while (grew) {
      grew = false;
      for (var i = left.length - 1; i >= 0; i--) {
        final near = group.any((g) => d(LatLng(g.lat!, g.lng!), LatLng(left[i].lat!, left[i].lng!)) <= clusterMetres);
        if (near) {
          group.add(left.removeAt(i));
          grew = true;
        }
      }
    }
    if (group.length >= 2) groups.add(group);
  }
  return groups;
}

/// Every pinned animal on a map, coloured by health.
class HerdMapScreen extends ConsumerStatefulWidget {
  const HerdMapScreen({super.key});

  @override
  ConsumerState<HerdMapScreen> createState() => _HerdMapScreenState();
}

class _HerdMapScreenState extends ConsumerState<HerdMapScreen> {
  Species? _species;

  @override
  Widget build(BuildContext context) {
    final herd = ref.watch(herdProvider).valueOrNull ?? const <Cattle>[];
    final health = ref.watch(animalHealthProvider);
    final active = [for (final a in herd) if (a.status == CattleStatus.active) a];
    final shown = [for (final a in active) if (_species == null || a.species == _species) a];
    final pinned = [for (final a in shown) if (a.hasLocation) a];
    final sick = [for (final a in pinned) if (stateOf(health, a) == HealthState.sick) a];
    final clusters = sickClusters(sick);

    final region = ref.watch(currentUserProvider)?.region ?? '';
    final centre = (RegionService.findByName(region) ?? RegionService.regions.first).center;
    final start = pinned.isEmpty
        ? LatLng(centre.latitude, centre.longitude)
        : LatLng(
            pinned.map((a) => a.lat!).reduce((x, y) => x + y) / pinned.length,
            pinned.map((a) => a.lng!).reduce((x, y) => x + y) / pinned.length,
          );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Herd map'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: const GlassBar(),
      ),
      body: Stack(children: [
        FlutterMap(
          options: MapOptions(initialCenter: start, initialZoom: pinned.length < 2 ? 12 : 13),
          children: [
            TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.nolifa.grow'),
            CircleLayer(circles: [
              for (final g in clusters)
                CircleMarker(
                  point: LatLng(g.map((a) => a.lat!).reduce((x, y) => x + y) / g.length,
                      g.map((a) => a.lng!).reduce((x, y) => x + y) / g.length),
                  radius: clusterMetres,
                  useRadiusInMeter: true,
                  color: const Color(0x33FF4D4D),
                  borderColor: const Color(0xAAFF4D4D),
                  borderStrokeWidth: 2,
                ),
            ]),
            MarkerLayer(markers: [
              for (final a in pinned)
                Marker(
                  point: LatLng(a.lat!, a.lng!),
                  width: 42,
                  height: 42,
                  child: GestureDetector(
                    onTap: () => Navigator.push(
                        context, MaterialPageRoute(builder: (_) => AnimalDetailScreen(animalId: a.id))),
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: healthColor(stateOf(health, a)), width: 3),
                      ),
                      child: Text(a.species.emoji, style: const TextStyle(fontSize: 20)),
                    ),
                  ),
                ),
            ]),
          ],
        ),
        Positioned(
          left: AppTheme.s3,
          right: AppTheme.s3,
          top: AppTheme.s3,
          child: SafeArea(
            child: GlassCard(
              padding: const EdgeInsets.all(AppTheme.s3),
              radius: AppTheme.rControl,
              child: SpeciesChips(herd: herd, selected: _species, onChanged: (s) => setState(() => _species = s)),
            ),
          ),
        ),
        Positioned(
          left: AppTheme.s3,
          right: AppTheme.s3,
          bottom: AppTheme.s4,
          child: SafeArea(
            child: GlassCard(
              padding: const EdgeInsets.all(AppTheme.s4),
              radius: AppTheme.rControl,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (clusters.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppTheme.s2),
                    child: Text(
                        '${clusters.length == 1 ? 'A group of ${clusters.first.length} sick animals' : '${clusters.length} groups of sick animals'} '
                        'within 1.5 km of each other. Isolate them and call your vet.',
                        style: AppTheme.footnote.copyWith(color: AppTheme.danger, fontWeight: FontWeight.w600)),
                  ),
                Wrap(spacing: AppTheme.s3, children: [
                  for (final s in HealthState.values)
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      HealthDot(s),
                      const SizedBox(width: 4),
                      Text(s.label, style: AppTheme.caption),
                    ]),
                ]),
                const SizedBox(height: AppTheme.s2),
                Text(
                    pinned.isEmpty
                        ? 'No animals have a pin yet. Open an animal and drop a pin on the map.'
                        : '${pinned.length} of ${shown.length} pinned. The rest have no location.',
                    style: AppTheme.footnote),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}
