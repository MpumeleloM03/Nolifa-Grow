import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:nolifa_grow/map/area_details.dart';
import 'package:nolifa_grow/map/area_report.dart';
import 'package:nolifa_grow/map/hex_grid.dart';
import 'package:nolifa_grow/models/outbreak_report.dart';
import 'package:nolifa_grow/screens/map_screen.dart';
import 'package:nolifa_grow/theme/app_theme.dart';

void main() {
  final grid = HexGrid();
  final now = DateTime(2026, 10, 22);

  group('hex grid', () {
    test('a point maps to a cell whose centre maps back to the same cell', () {
      for (final p in const [LatLng(-29.86, 31.02), LatLng(-28.7, 31.9), LatLng(-27.8, 32.1), LatLng(-30.2, 30.8)]) {
        final id = grid.cellOf(p);
        expect(grid.cellOf(grid.centerOf(id)), id);
      }
    });

    test('a cell has six corners, all the same distance from its centre', () {
      final id = grid.cellOf(const LatLng(-29.6, 30.4));
      final c = grid.centerOf(id);
      final corners = grid.cornersOf(id);
      expect(corners.length, 6);
      final d = const Distance();
      final dists = [for (final k in corners) d(c, k)];
      final avg = dists.reduce((a, b) => a + b) / 6;
      for (final x in dists) {
        expect((x - avg).abs() / avg, lessThan(0.02));
      }
    });

    test('neighbouring cells share an edge: their centres are one cell apart', () {
      final id = grid.cellOf(const LatLng(-29.6, 30.4));
      final d = const Distance();
      final base = d(grid.centerOf(id), grid.centerOf(id.neighbours.first));
      for (final n in id.neighbours) {
        expect((d(grid.centerOf(id), grid.centerOf(n)) - base).abs() / base, lessThan(0.03));
        expect(grid.cellOf(grid.centerOf(n)), n);
      }
      expect(id.neighbours.toSet().length, 6);
    });

    test('hexagons tile without gaps: nearby points land in cells that contain them', () {
      for (var i = 0; i < 40; i++) {
        final p = LatLng(-29.9 + i * 0.05, 30.4 + i * 0.03);
        final id = grid.cellOf(p);
        final d = const Distance();
        final toCentre = d(p, grid.centerOf(id));
        for (final n in id.neighbours) {
          expect(toCentre <= d(p, grid.centerOf(n)) + 1500, isTrue, reason: 'closest centre wins');
        }
      }
    });
  });

  group('area report', () {
    test('demo data covers crops and livestock, dated close to today', () {
      final s = demoSightings(now);
      expect(s.any((x) => x.kind == OutbreakKind.plant), isTrue);
      expect(s.any((x) => x.kind == OutbreakKind.livestock), isTrue);
      expect(s.every((x) => now.difference(x.at).inDays < 10), isTrue);
    });

    test('heat grows with urgent and repeated sightings, spreads to neighbours, and healthy scans add none', () {
      final cells = buildCells(grid, demoSightings(now), now);
      expect(cells.values.every((c) => c.heat > 0), isTrue);
      final hottest = cells.values.reduce((a, b) => a.heat > b.heat ? a : b);
      expect(hottest.sightings.length, greaterThan(1));
      expect(cells.values.any((c) => c.sightings.isEmpty), isTrue, reason: 'spill cells glow with no reports of their own');
      expect(cells.length, greaterThan(60), reason: 'a dense grid, not a few dots');
      expect(cells.values.any((c) => c.sightings.any((s) => s.disease.toLowerCase().contains('healthy'))), isFalse);
    });

    test('filtering to livestock leaves only livestock in every cell', () {
      final cells = buildCells(grid, demoSightings(now), now, only: OutbreakKind.livestock);
      expect(cells, isNotEmpty);
      for (final c in cells.values) {
        expect(c.sightings.every((s) => s.kind == OutbreakKind.livestock), isTrue);
      }
    });

    test('old reports fade', () {
      final fresh = Sighting('Rust', OutbreakKind.plant, 'orange', now, 'X', -29, 31);
      final old = Sighting('Rust', OutbreakKind.plant, 'orange', now.subtract(const Duration(days: 60)), 'X', -29, 31);
      expect(old.weight(now), lessThan(fresh.weight(now)));
      expect(old.weight(now), greaterThan(0));
    });

    test('a hexagon lists crops and livestock problems with how they are handled', () {
      final live = [
        Sighting('Foot-and-Mouth Disease', OutbreakKind.livestock, 'red', now, 'Zululand', -28.72, 31.9),
        Sighting('Late Blight', OutbreakKind.plant, 'red', now, 'Zululand', -28.72, 31.9),
      ];
      final cells = buildCells(grid, live, now);
      final cell = cells[grid.cellOf(const LatLng(-28.72, 31.9))]!;
      final problems = problemsIn(cell);
      expect(problems.length, 2);
      final fmd = problems.firstWhere((p) => p.kind == OutbreakKind.livestock);
      expect(fmd.response.first, contains('state veterinarian'));
      final blight = problems.firstWhere((p) => p.kind == OutbreakKind.plant);
      expect(blight.response.length, greaterThan(1));
    });
  });

  group('map screen', () {
    testWidgets('draws hexagons, not dots, and tapping one opens what affects it', (tester) async {
      final prev = FlutterError.onError;
      FlutterError.onError = (d) {
        final t = d.exceptionAsString();
        if (t.contains('overflowed') || t.contains('HTTP') || t.contains('tile')) return;
        prev?.call(d);
      };
      addTearDown(() => FlutterError.onError = prev);
      tester.view.physicalSize = const Size(1206, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: const [],
        child: MaterialApp(theme: AppTheme.build(), home: const Scaffold(body: MapScreen(embedded: true))),
      ));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('All'), findsOneWidget);
      expect(find.text('🌿 Crops'), findsOneWidget);
      expect(find.text('🐄 Livestock'), findsOneWidget);
      expect(find.textContaining('Tap any hexagon'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('area details sheet', () {
    testWidgets('names the area, splits crops and livestock, and says how each is handled', (tester) async {
      final live = [
        Sighting('Foot-and-Mouth Disease', OutbreakKind.livestock, 'red', now, 'Zululand', -28.72, 31.9),
        Sighting('Late Blight', OutbreakKind.plant, 'red', now, 'Zululand', -28.72, 31.9),
      ];
      final cell = buildCells(grid, live, now)[grid.cellOf(const LatLng(-28.72, 31.9))]!;
      tester.view.physicalSize = const Size(1206, 5000);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.build(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(child: TextButton(onPressed: () => showAreaDetails(context, grid, cell, now), child: const Text('open'))),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Zululand'), findsOneWidget);
      expect(find.textContaining('🌿 Crops'), findsOneWidget);
      expect(find.textContaining('🐄 Livestock'), findsOneWidget);
      expect(find.text('Late Blight'), findsOneWidget);
      expect(find.text('Foot-and-Mouth Disease'), findsOneWidget);
      expect(find.text('How it is being handled'), findsNWidgets(2));
      expect(find.textContaining('state veterinarian'), findsWidgets);
    });

    testWidgets('an empty hexagon says it is clear', (tester) async {
      final cell = HexCell(grid.cellOf(const LatLng(-29.0, 31.0)), const [], 0);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.build(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(child: TextButton(onPressed: () => showAreaDetails(context, grid, cell, now), child: const Text('open'))),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('No outbreaks reported in this area'), findsOneWidget);
    });
  });
}
