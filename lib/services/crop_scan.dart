import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/diagnosis_record.dart';
import '../models/disease_info.dart';
import '../models/outbreak_report.dart';
import '../screens/result_screen.dart';
import '../theme/app_theme.dart';
import '../utils/language_provider.dart';
import '../utils/translations.dart';
import 'auth_service.dart';
import 'history_service.dart';
import 'image_service.dart';
import 'inference_service.dart';
import 'outbreak_service.dart';
import 'plant_id_service.dart';
import 'region_service.dart';

import 'package:ubuntu_core/tr_text.dart' show Text;
/// A finished on-phone diagnosis.
class CropScanResult {
  final String id;
  final File image;
  final String label;
  final String plainName;
  final String severity; // 'green', 'orange', 'red'
  final String confidence;
  final bool offline;
  const CropScanResult(this.id, this.image, this.label, this.plainName, this.severity, this.confidence, this.offline);
}

/// Picks a photo (camera or library), diagnoses it online first and on the
/// phone when there is no signal, saves it to history, and returns the result.
/// Returns null if the farmer backed out or nothing could be diagnosed.
Future<CropScanResult?> captureCrop(BuildContext context, WidgetRef ref,
    {bool addToMap = true}) async {
  final lang = ref.read(languageProvider);
  final t = AppTranslations.get;
  final images = ImageService();

  final File? image = await showModalBottomSheet<File?>(
    context: context,
    backgroundColor: AppTheme.sheet,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (sheet) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: AppTheme.s2),
        ListTile(
          leading: Icon(Icons.camera_alt_rounded, color: AppTheme.sprout),
          title: Text(t('take_photo', lang)),
          onTap: () async => Navigator.pop(sheet, await images.pickFromCamera()),
        ),
        ListTile(
          leading: Icon(Icons.photo_library_rounded, color: AppTheme.sprout),
          title: Text(t('choose_gallery', lang)),
          onTap: () async => Navigator.pop(sheet, await images.pickFromGallery()),
        ),
      ]),
    ),
  );
  if (image == null || !context.mounted) return null;

  // Block the screen while the model runs so a second tap cannot start another.
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black54,
    builder: (_) => PopScope(
      canPop: false,
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(color: AppTheme.sprout),
          const SizedBox(height: AppTheme.s4),
          Text(t('analysing', lang),
              style: AppTheme.callout.copyWith(color: Colors.white)),
        ]),
      ),
    ),
  );

  final inference = InferenceService();
  Map<String, dynamic>? result;
  try {
    final net = await Connectivity().checkConnectivity();
    final online =
        net.contains(ConnectivityResult.wifi) || net.contains(ConnectivityResult.mobile);
    if (online) result = await PlantIdService().diagnose(image);
    if (result == null) {
      await inference.loadModel();
      result = await inference.diagnose(image);
      if (result != null) result['offlineMode'] = true;
    }
  } finally {
    inference.dispose();
  }

  if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  if (result == null) return null;

  final label = result['label'] as String? ?? 'Unknown';
  final info = DiseaseDatabase.getInfo(label);
  final confidence = result['confidence'] as String? ?? '0';
  final offline = result['offlineMode'] as bool? ?? false;
  final id = const Uuid().v4();
  await HistoryService().saveRecord(DiagnosisRecord(
    id: id,
    label: label,
    plainName: info.plainName,
    confidence: confidence,
    imagePath: image.path,
    date: DateTime.now(),
    offlineMode: offline,
  ));
  if (addToMap) _contributeToMap(ref, label, info.severityColor);
  return CropScanResult(id, image, label, info.plainName, info.severityColor, confidence, offline);
}

/// The crop scanner, start to finish: capture, diagnose, add to the outbreak
/// map and show the result. The Home tab calls this from its Open camera button.
///
/// [onDiagnosed] runs with the disease label and severity ('green', 'orange',
/// 'red') before the result opens, so a plot can record the check.
Future<void> startCropScan(BuildContext context, WidgetRef ref,
    {void Function(String label, String severity)? onDiagnosed}) async {
  final r = await captureCrop(context, ref);
  if (r == null || !context.mounted) return;
  onDiagnosed?.call(r.plainName, r.severity);
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => ResultScreen(
        image: r.image,
        scanId: r.id,
        label: r.label,
        confidence: r.confidence,
        offlineMode: r.offline,
      ),
    ),
  );
}

/// Adds the diagnosis to the community map inside the farmer's region, never
/// at their own coordinates. Silent on failure: a farmer waiting on a result
/// is never blocked by a map write.
void _contributeToMap(WidgetRef ref, String disease, String severityColor) {
  final region = ref.read(currentUserProvider)?.region;
  if (region == null || region.isEmpty) return;
  final centre = RegionService.findByName(region)?.center;
  if (centre == null) return;
  ref.read(outbreakServiceProvider).report(
        disease: disease,
        severity: severityColor,
        kind: OutbreakKind.plant,
        exactLocation: RegionService.jitter(centre, disease + region),
        region: region,
      );
}
