import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/outbreak_report.dart';
import '../services/outbreak_service.dart';
import '../theme/app_theme.dart';
import '../widgets/heat_layer.dart';
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

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  bool _showHeat = true;

  static const _months = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };

  static DateTime _parseDate(String raw) {
    final parts = raw.split(' ');
    if (parts.length == 3) {
      final month = _months[parts[1].toLowerCase().substring(0, 3)];
      final day = int.tryParse(parts[0]);
      final year = int.tryParse(parts[2]);
      if (month != null && day != null && year != null) {
        return DateTime(year, month, day);
      }
    }
    return DateTime.now();
  }

  /// The heat layer reads from both the seeded regional data and whatever the
  /// community has reported since, so the map is useful before it has users.
  List<OutbreakReport> _heatReports(List<OutbreakReport> live) => [
        ..._filteredPoints.map((p) => OutbreakReport(
              id: '',
              disease: p.disease,
              severity: p.severity,
              kind: OutbreakKind.plant,
              location: p.location,
              region: p.region,
              reportedAt: _parseDate(p.date),
            )),
        ...live,
      ];

  // Demonstration data across KZN regions
  final List<DiseasePoint> _points = const [
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

  DiseasePoint? _selectedPoint;
  String _selectedFilter = 'all';

  Color _getColor(String severity) {
    switch (severity) {
      case 'green':
        return const Color(0xFF2D6A4F);
      case 'orange':
        return const Color(0xFFE07B39);
      case 'red':
        return const Color(0xFFD62828);
      default:
        return Colors.grey;
    }
  }

  List<DiseasePoint> get _filteredPoints {
    if (_selectedFilter == 'all') return _points;
    return _points.where((p) => p.severity == _selectedFilter).toList();
  }

  int _countBySeverity(String severity) {
    return _points.where((p) => p.severity == severity).length;
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(languageProvider);
    final t = AppTranslations.get;

    return Scaffold(
      backgroundColor: const Color(0xFF1B4332),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1B4332),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t('map_title', lang),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: Colors.white,
              ),
            ),
            Text(
              t('map_subtitle', lang),
              style: const TextStyle(
                fontSize: 11,
                color: Colors.white54,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Stats bar
          Container(
            color: const Color(0xFF1B4332),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                _buildStatChip('All', _points.length, Colors.white24, 'all'),
                const SizedBox(width: 8),
                _buildStatChip(t('map_healthy', lang), _countBySeverity('green'), const Color(0xFF2D6A4F), 'green'),
                const SizedBox(width: 8),
                _buildStatChip(t('map_moderate', lang), _countBySeverity('orange'), const Color(0xFFE07B39), 'orange'),
                const SizedBox(width: 8),
                _buildStatChip(t('map_urgent', lang), _countBySeverity('red'), const Color(0xFFD62828), 'red'),
              ],
            ),
          ),

          // Map
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  options: MapOptions(
                    initialCenter: const LatLng(-29.0, 31.0),
                    initialZoom: 7.0,
                    onTap: (_, __) => setState(() => _selectedPoint = null),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.nolifagrow.nolifa_grow',
                    ),
                    if (_showHeat)
                      HeatLayer(
                        reports: _heatReports(
                          ref.watch(outbreaksProvider).valueOrNull ?? const [],
                        ),
                      ),
                    CircleLayer(
                      circles: _filteredPoints.map((point) {
                        return CircleMarker(
                          point: point.location,
                          radius: 14,
                          color: _getColor(point.severity).withOpacity(0.5),
                          borderColor: _getColor(point.severity),
                          borderStrokeWidth: 2,
                        );
                      }).toList(),
                    ),
                    MarkerLayer(
                      markers: _filteredPoints.map((point) {
                        return Marker(
                          point: point.location,
                          width: 28,
                          height: 28,
                          child: GestureDetector(
                            onTap: () => setState(() => _selectedPoint = point),
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: _getColor(point.severity),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: _getColor(point.severity).withOpacity(0.4),
                                    blurRadius: 8,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),

                // Heat toggle
                Positioned(
                  top: 12,
                  right: 12,
                  child: GestureDetector(
                    onTap: () => setState(() => _showHeat = !_showHeat),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppTheme.forestDeep.withValues(alpha: 0.82),
                        borderRadius: BorderRadius.circular(AppTheme.rControl),
                        border: Border.all(
                          color: _showHeat
                              ? AppTheme.warn
                              : AppTheme.glassBorder,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _showHeat
                                ? Icons.local_fire_department_rounded
                                : Icons.local_fire_department_outlined,
                            size: 17,
                            color: _showHeat
                                ? AppTheme.warn
                                : AppTheme.textTertiary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Heat',
                            style: AppTheme.footnote.copyWith(
                              color: _showHeat
                                  ? AppTheme.textPrimary
                                  : AppTheme.textTertiary,
                              fontWeight: _showHeat
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Demo watermark
                Positioned(
                  bottom: 16,
                  left: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Demonstration data — populates with real user scans',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ),

                // Selected point info card
                if (_selectedPoint != null)
                  Positioned(
                    top: 16,
                    left: 16,
                    right: 16,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.15),
                            blurRadius: 12,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: _getColor(_selectedPoint!.severity),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _selectedPoint!.disease,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    color: Color(0xFF1a1a1a),
                                  ),
                                ),
                                Text(
                                  '${_selectedPoint!.region} — ${_selectedPoint!.date}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.black54,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          GestureDetector(
                            onTap: () => setState(() => _selectedPoint = null),
                            child: const Icon(
                              Icons.close,
                              size: 18,
                              color: Colors.black38,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip(String label, int count, Color color, String filter) {
    final isSelected = _selectedFilter == filter;
    return GestureDetector(
      onTap: () => setState(() => _selectedFilter = filter),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? color : color.withOpacity(0.2),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? Colors.white : color,
            width: 1,
          ),
        ),
        child: Text(
          '$count',
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}