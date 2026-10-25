import 'dart:math' as math;
import 'package:flutter/material.dart' hide Text;
import 'package:latlong2/latlong.dart';
import 'package:ubuntu_core/ubuntu_core.dart' show Pill;
import '../models/outbreak_report.dart';
import '../services/region_service.dart';
import '../store/store_common.dart' show SheetFrame, timeAgo;
import '../theme/app_theme.dart';
import 'area_report.dart';
import 'hex_grid.dart';

import 'package:ubuntu_core/tr_text.dart' show Text;
/// The nearest named region to a point, for labelling a hexagon.
String regionNear(LatLng p) {
  RegionInfo? best;
  var d = double.infinity;
  for (final r in RegionService.regions) {
    if (r.name == 'Other') continue;
    final dd = math.pow(r.center.latitude - p.latitude, 2) + math.pow(r.center.longitude - p.longitude, 2);
    if (dd < d) {
      d = dd.toDouble();
      best = r;
    }
  }
  return best?.name ?? 'KwaZulu-Natal';
}

/// What a tapped hexagon is affected by, for crops and livestock, and how each
/// problem is being dealt with.
Future<void> showAreaDetails(BuildContext context, HexGrid grid, HexCell cell, DateTime now) {
  final centre = grid.centerOf(cell.id);
  final area = regionNear(centre);
  final problems = problemsIn(cell);
  final crops = problems.where((p) => p.kind == OutbreakKind.plant).toList();
  final animals = problems.where((p) => p.kind == OutbreakKind.livestock).toList();

  Widget group(String title, String emoji, List<AreaProblem> list) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: AppTheme.s3, bottom: AppTheme.s2),
            child: Text(title, style: AppTheme.headline),
          ),
          if (list.isEmpty)
            Text('Nothing reported.', style: AppTheme.footnote)
          else
            for (final p in list)
              Container(
                margin: const EdgeInsets.only(bottom: AppTheme.s2),
                padding: const EdgeInsets.all(AppTheme.s3),
                decoration: BoxDecoration(
                  color: AppTheme.glassFill,
                  borderRadius: BorderRadius.circular(AppTheme.rControl),
                  border: Border.all(color: AppTheme.glassBorderSoft),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(p.disease, style: AppTheme.subhead.copyWith(color: AppTheme.textPrimary, fontWeight: FontWeight.w700))),
                    Pill(p.severity == 'red' ? 'Urgent' : 'Watch', color: p.severity == 'red' ? AppTheme.danger : AppTheme.warn),
                  ]),
                  Text('${p.reports} report${p.reports == 1 ? '' : 's'}  •  ${timeAgo(p.latest, now: now)}', style: AppTheme.caption),
                  const SizedBox(height: AppTheme.s2),
                  Text('How it is being handled', style: AppTheme.caption.copyWith(color: AppTheme.sprout)),
                  for (final step in p.response)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('•  ', style: AppTheme.footnote),
                        Expanded(child: Text(step, style: AppTheme.footnote)),
                      ]),
                    ),
                ]),
              ),
        ],
      );

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => SheetFrame(
      title: area,
      subtitle: cell.isEmpty
          ? (cell.heat > 0
              ? 'No reports exactly here, but outbreaks in the areas around it are spreading heat into this one.'
              : 'No outbreaks reported in this area. If you see something, report it so neighbours can prepare.')
          : '${problems.length} problem${problems.length == 1 ? '' : 's'} affecting this area',
      children: [
        if (!cell.isEmpty) ...[
          group('Crops', '🌿', crops),
          group('Livestock', '🐄', animals),
        ],
        const SizedBox(height: AppTheme.s2),
        Text('Each hexagon covers about 10 km. Reports are placed by area, never at a farm.', style: AppTheme.caption),
      ],
    ),
  );
}
