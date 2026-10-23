import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../theme/app_theme.dart';
import '../../theme/glass.dart';

/// Tap the map where the animal is kept. Returns the chosen point.
class LocationPickerScreen extends StatefulWidget {
  final LatLng start;
  final LatLng? current;
  final String title;
  const LocationPickerScreen({super.key, required this.start, this.current, this.title = 'Where are they?'});

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  late LatLng? _pin = widget.current;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: const GlassBar(),
      ),
      body: Stack(children: [
        FlutterMap(
          options: MapOptions(
            initialCenter: widget.current ?? widget.start,
            initialZoom: widget.current == null ? 11 : 14,
            onTap: (_, p) => setState(() => _pin = p),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.nolifa.grow',
            ),
            if (_pin != null)
              MarkerLayer(markers: [
                Marker(
                  point: _pin!,
                  width: 44,
                  height: 44,
                  alignment: Alignment.topCenter,
                  child: const Icon(Icons.location_on_rounded, size: 44, color: Color(0xFFE8A33D)),
                ),
              ]),
          ],
        ),
        Positioned(
          left: AppTheme.s4,
          right: AppTheme.s4,
          bottom: AppTheme.s6,
          child: SafeArea(
            child: GlassCard(
              padding: const EdgeInsets.all(AppTheme.s4),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(_pin == null ? 'Tap the map to drop a pin on the camp.' : 'Pin placed. Tap again to move it.',
                    style: AppTheme.callout),
                const SizedBox(height: AppTheme.s3),
                GlassButton(
                  label: 'Use this spot',
                  icon: Icons.check_rounded,
                  accent: AppTheme.livestockAccent,
                  onPressed: _pin == null ? null : () => Navigator.pop(context, _pin),
                ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}
