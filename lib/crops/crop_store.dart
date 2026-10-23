import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ubuntu_core/ubuntu_core.dart' show SecurePrefs;
import '../services/auth_service.dart';
import 'crop_models.dart';

/// The farmer's plots, kept on the phone per account.
class CropStore extends Notifier<List<CropPlot>> {
  String get _key => 'crop_plots_${ref.read(currentUserProvider)?.uid ?? 'guest'}';
  Future<void> _ready = Future.value();

  @override
  List<CropPlot> build() {
    ref.watch(currentUserProvider.select((u) => u?.uid));
    _ready = _load();
    return const [];
  }

  Future<void> _load() async {
    final raw = await SecurePrefs.getString(_key);
    if (raw != null) {
      try {
        final saved = [for (final m in jsonDecode(raw) as List) CropPlot.fromJson(Map<String, dynamic>.from(m as Map))];
        // Anything added while the save was still loading wins over the old copy.
        final ids = {for (final p in state) p.id};
        state = [...state, for (final p in saved) if (!ids.contains(p.id)) p];
      } catch (_) {
        // An unreadable save is treated as empty rather than crashing the page.
      }
    }
  }

  Future<void> _save() async {
    final key = _key; // read before awaiting: the store may be disposed by then
    final payload = jsonEncode([for (final p in state) p.toJson()]);
    await _ready;
    await SecurePrefs.setString(key, payload);
  }

  void _set(List<CropPlot> next) {
    state = next;
    _save();
  }

  CropPlot add({required String crop, required String name, required DateTime plantedOn, required double areaM2}) {
    var plot = CropPlot(
      id: 'plot-${DateTime.now().microsecondsSinceEpoch}',
      crop: crop,
      name: name.trim().isEmpty ? '$crop plot' : name.trim(),
      plantedOn: plantedOn,
      areaM2: areaM2,
    );
    // Keep the first prediction, so the real harvest can be judged against it.
    plot = CropPlot(
      id: plot.id,
      crop: plot.crop,
      name: plot.name,
      plantedOn: plot.plantedOn,
      areaM2: plot.areaM2,
      predictedOn: CropAdvisor.assess(plot, DateTime.now()).harvestOn,
    );
    _set([plot, ...state]);
    return plot;
  }

  void remove(String id) => _set([for (final p in state) if (p.id != id) p]);

  void update(CropPlot plot) => _set([for (final p in state) if (p.id == plot.id) plot else p]);

  void addCheck(String id, String label, String severity) {
    final cur = state.where((p) => p.id == id);
    if (cur.isEmpty) return;
    final p = cur.first;
    update(p.copyWith(checks: [HealthCheck(DateTime.now(), label, severity), ...p.checks].take(20).toList()));
  }

  void setSprinkler(String id, SprinklerPlan plan) {
    final cur = state.where((p) => p.id == id);
    if (cur.isEmpty) return;
    update(cur.first.copyWith(sprinkler: plan));
  }
}

final cropStoreProvider = NotifierProvider<CropStore, List<CropPlot>>(CropStore.new);
