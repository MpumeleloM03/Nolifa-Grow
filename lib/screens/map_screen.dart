import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/outbreak_report.dart';
import '../services/auth_service.dart';
import '../services/outbreak_service.dart';
import '../services/region_service.dart';
import '../theme/app_theme.dart';
import '../map/area_details.dart';
import '../map/area_report.dart';
import '../map/hex_grid.dart';
import '../utils/translations.dart';
import '../utils/language_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DiseasePoint {
  final String region;
  final LatLng location;
  final String disease;
  final String severity;
  final String date;

  const DiseasePoint({
    required this.region,
    required this.location,
    required this.disease,
    required this.severity,
    required this.date,
  });
}

/// Demonstration sightings across KZN, so the map and the area list are useful
/// before the community has filled them in.
const List<DiseasePoint> kDemoDiseasePoints = [
  // Greater Durban — mixed
  DiseasePoint(region: 'Greater Durban', location: LatLng(-29.8587, 31.0218), disease: 'Early Blight', severity: 'orange', date: '28 May 2026'),
  DiseasePoint(region: 'Greater Durban', location: LatLng(-29.9, 30.98), disease: 'Healthy', severity: 'green', date: '27 May 2026'),
  DiseasePoint(region: 'Greater Durban', location: LatLng(-29.82, 31.05), disease: 'Leaf Spot', severity: 'orange', date: '26 May 2026'),
  DiseasePoint(region: 'Greater Durban', location: LatLng(-29.95, 31.02), disease: 'Healthy', severity: 'green', date: '25 May 2026'),

  // KZN Midlands — high activity
  DiseasePoint(region: 'KZN Midlands', location: LatLng(-29.6167, 30.3833), disease: 'Late Blight', severity: 'red', date: '28 May 2026'),
  DiseasePoint(region: 'KZN Midlands', location: LatLng(-29.55, 30.42), disease: 'Late Blight', severity: 'red', date: '27 May 2026'),
  DiseasePoint(region: 'KZN Midlands', location: LatLng(-29.65, 30.31), disease: 'Powdery Mildew', severity: 'orange', date: '26 May 2026'),
  DiseasePoint(region: 'KZN Midlands', location: LatLng(-29.58, 30.38), disease: 'Early Blight', severity: 'orange', date: '25 May 2026'),

  // North Coast
  DiseasePoint(region: 'North Coast', location: LatLng(-29.4, 31.2), disease: 'Healthy', severity: 'green', date: '28 May 2026'),
  DiseasePoint(region: 'North Coast', location: LatLng(-29.3, 31.3), disease: 'Leaf Miner', severity: 'orange', date: '27 May 2026'),
  DiseasePoint(region: 'North Coast', location: LatLng(-29.35, 31.15), disease: 'Healthy', severity: 'green', date: '26 May 2026'),

  // South Coast
  DiseasePoint(region: 'South Coast', location: LatLng(-30.2, 30.8), disease: 'Rust', severity: 'orange', date: '28 May 2026'),
  DiseasePoint(region: 'South Coast', location: LatLng(-30.35, 30.72), disease: 'Healthy', severity: 'green', date: '27 May 2026'),
  DiseasePoint(region: 'South Coast', location: LatLng(-30.15, 30.85), disease: 'Fungal Infection', severity: 'orange', date: '26 May 2026'),

  // Zululand
  DiseasePoint(region: 'Zululand', location: LatLng(-28.75, 31.88), disease: 'Maize Streak Virus', severity: 'red', date: '28 May 2026'),
  DiseasePoint(region: 'Zululand', location: LatLng(-28.65, 31.95), disease: 'Maize Streak Virus', severity: 'red', date: '27 May 2026'),
  DiseasePoint(region: 'Zululand', location: LatLng(-28.8, 31.82), disease: 'Grey Leaf Spot', severity: 'orange', date: '26 May 2026'),

  // Northern KZN
  DiseasePoint(region: 'Northern KZN', location: LatLng(-27.8, 32.1), disease: 'Healthy', severity: 'green', date: '28 May 2026'),
  DiseasePoint(region: 'Northern KZN', location: LatLng(-27.9, 32.05), disease: 'Bacterial Infection', severity: 'orange', date: '27 May 2026'),
  DiseasePoint(region: 'Northern KZN', location: LatLng(-27.75, 32.15), disease: 'Healthy', severity: 'green', date: '26 May 2026'),
];

/// Demonstration livestock sightings, so the map covers cattle as well as crops.
const List<DiseasePoint> kDemoLivestockPoints = [
  DiseasePoint(region: 'Zululand', location: LatLng(-28.72, 31.9), disease: 'Foot-and-Mouth Disease', severity: 'red', date: '28 May 2026'),
  DiseasePoint(region: 'Zululand', location: LatLng(-28.8, 31.95), disease: 'Foot-and-Mouth Disease', severity: 'red', date: '27 May 2026'),
  DiseasePoint(region: 'Zululand', location: LatLng(-28.62, 31.8), disease: 'Lumpy Skin Disease', severity: 'orange', date: '26 May 2026'),
  DiseasePoint(region: 'Northern KZN', location: LatLng(-27.85, 32.08), disease: 'Anthrax', severity: 'red', date: '28 May 2026'),
  DiseasePoint(region: 'Northern KZN', location: LatLng(-27.95, 32.0), disease: 'Redwater', severity: 'orange', date: '25 May 2026'),
  DiseasePoint(region: 'KZN Midlands', location: LatLng(-29.6, 30.35), disease: 'Lumpy Skin Disease', severity: 'orange', date: '28 May 2026'),
  DiseasePoint(region: 'KZN Midlands', location: LatLng(-29.7, 30.45), disease: 'Heartwater', severity: 'orange', date: '27 May 2026'),
  DiseasePoint(region: 'North Coast', location: LatLng(-29.38, 31.25), disease: 'Heartwater', severity: 'orange', date: '27 May 2026'),
  DiseasePoint(region: 'North Coast', location: LatLng(-29.32, 31.1), disease: 'Mastitis', severity: 'orange', date: '24 May 2026'),
  DiseasePoint(region: 'South Coast', location: LatLng(-30.25, 30.78), disease: 'Redwater', severity: 'orange', date: '26 May 2026'),
  DiseasePoint(region: 'Greater Durban', location: LatLng(-29.88, 30.99), disease: 'Pinkeye', severity: 'orange', date: '27 May 2026'),
];

class MapScreen extends ConsumerStatefulWidget {
  /// Draws just the map and its filters, without a Scaffold, so it can sit
  /// inside another page (the Alerts tab).
  final bool embedded;
  const MapScreen({super.key, this.embedded = false});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final _grid = HexGrid();
  OutbreakKind? _only; // null shows crops and livestock together
  HexId? _selected;

  /// Pale pink for a little heat, deep red for a lot, so one hue reads as "hotter".
  static Color heatColor(double t) =>
      Color.lerp(const Color(0xFFF7B7B7), const Color(0xFFD40000), t.clamp(0.0, 1.0))!;

  static double heatAlpha(double t) => 0.22 + 0.62 * math.pow(t.clamp(0.0, 1.0), 0.85).toDouble();

  void _tap(LatLng p, Map<HexId, HexCell> cells, DateTime now) {
    final id = _grid.cellOf(p);
    setState(() => _selected = id);
    final cell = cells[id] ?? HexCell(id, const [], 0);
    showAreaDetails(context, _grid, cell, now).whenComplete(() {
      if (mounted) setState(() => _selected = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(languageProvider);
    final t = AppTranslations.get;
    final now = DateTime.now();
    final live = ref.watch(outbreaksProvider).valueOrNull ?? const <OutbreakReport>[];
    final all = [...demoSightings(now), ...liveSightings(live)];
    final cells = buildCells(_grid, all, now, only: _only);
    final maxHeat = cells.values.fold<double>(1.5, (a, c) => c.heat > a ? c.heat : a);

    final polygons = <Polygon>[
      for (final c in cells.values)
        if (c.heat / maxHeat > 0.04)
          Polygon(
            points: _grid.cornersOf(c.id),
            isFilled: true,
            color: heatColor(c.heat / maxHeat).withValues(alpha: heatAlpha(c.heat / maxHeat)),
            borderColor: c.id == _selected ? Colors.white : Colors.white.withValues(alpha: 0.25),
            borderStrokeWidth: c.id == _selected ? 3 : 0.6,
          ),
    ];

    final home = RegionService.findByName(ref.watch(currentUserProvider)?.region)?.center ??
        const LatLng(-29.0, 31.0);

    final map = Stack(children: [
      FlutterMap(
        options: MapOptions(
          initialCenter: home,
          initialZoom: 8.3,
          onTap: (_, p) => _tap(p, cells, now),
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.nolifagrow.nolifa_grow',
          ),
          PolygonLayer(polygons: polygons),
        ],
      ),
      Positioned(
        left: 12,
        bottom: 12,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Text('Less', style: TextStyle(color: Colors.white70, fontSize: 10)),
            const SizedBox(width: 6),
            for (var i = 0; i < 5; i++)
              Container(width: 18, height: 10, color: heatColor(i / 4).withValues(alpha: heatAlpha(i / 4))),
            const SizedBox(width: 6),
            const Text('More', style: TextStyle(color: Colors.white70, fontSize: 10)),
          ]),
        ),
      ),
      Positioned(
        top: 12,
        left: 12,
        right: 12,
        child: Align(
          alignment: Alignment.topLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
            child: const Text('Tap any hexagon to see what is affecting it',
                style: TextStyle(color: Colors.white70, fontSize: 11)),
          ),
        ),
      ),
    ]);

    Widget chip(String label, OutbreakKind? kind) {
      final on = _only == kind;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: GestureDetector(
          onTap: () => setState(() => _only = kind),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: on ? AppTheme.sprout : AppTheme.glassFill,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: on ? AppTheme.textPrimary : AppTheme.glassBorder),
            ),
            child: Text(label,
                style: TextStyle(
                    color: on ? AppTheme.onAccent : AppTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
          ),
        ),
      );
    }

    final body = Column(children: [
      Container(
        color: AppTheme.pageGreen,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          chip('All', null),
          chip('🌿 Crops', OutbreakKind.plant),
          chip('🐄 Livestock', OutbreakKind.livestock),
        ]),
      ),
      Expanded(child: map),
    ]);
    if (widget.embedded) return body;
    return Scaffold(
      backgroundColor: AppTheme.pageGreen,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1B4332),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t('map_title', lang),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white)),
          Text(t('map_subtitle', lang), style: const TextStyle(fontSize: 11, color: Colors.white54)),
        ]),
      ),
      body: body,
    );
  }
}
