import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ubuntu_core/ubuntu_core.dart' show SecurePrefs;
import '../services/auth_service.dart';

/// A farm that can supply water to a community: a borehole, a tanker, a dam.
class WaterSupplier {
  final bool enabled;
  final String source;
  final int litresPerDay;
  final bool canDeliver;
  final bool free;
  final int radiusKm;
  const WaterSupplier({
    this.enabled = false,
    this.source = 'Borehole',
    this.litresPerDay = 5000,
    this.canDeliver = true,
    this.free = false,
    this.radiusKm = 25,
  });

  WaterSupplier copyWith({bool? enabled, String? source, int? litresPerDay, bool? canDeliver, bool? free, int? radiusKm}) =>
      WaterSupplier(
        enabled: enabled ?? this.enabled,
        source: source ?? this.source,
        litresPerDay: litresPerDay ?? this.litresPerDay,
        canDeliver: canDeliver ?? this.canDeliver,
        free: free ?? this.free,
        radiusKm: radiusKm ?? this.radiusKm,
      );

  String get priceLabel => free ? 'free' : 'at cost';

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'source': source,
        'litres': litresPerDay,
        'deliver': canDeliver,
        'free': free,
        'radius': radiusKm,
      };

  factory WaterSupplier.fromJson(Map<String, dynamic> m) => WaterSupplier(
        enabled: m['enabled'] as bool? ?? false,
        source: m['source'] as String? ?? 'Borehole',
        litresPerDay: (m['litres'] as num?)?.toInt() ?? 5000,
        canDeliver: m['deliver'] as bool? ?? true,
        free: m['free'] as bool? ?? false,
        radiusKm: (m['radius'] as num?)?.toInt() ?? 25,
      );
}

/// One time this farm helped a community.
class WaterOffer {
  final String incidentId;
  final String zoneName;
  final int litres;
  final int etaMinutes;
  final DateTime at;
  const WaterOffer(this.incidentId, this.zoneName, this.litres, this.etaMinutes, this.at);

  Map<String, dynamic> toJson() => {
        'id': incidentId,
        'zone': zoneName,
        'litres': litres,
        'eta': etaMinutes,
        'at': at.millisecondsSinceEpoch,
      };

  factory WaterOffer.fromJson(Map<String, dynamic> m) => WaterOffer(
      m['id'] as String,
      m['zone'] as String? ?? '',
      (m['litres'] as num?)?.toInt() ?? 0,
      (m['eta'] as num?)?.toInt() ?? 0,
      DateTime.fromMillisecondsSinceEpoch((m['at'] as num).toInt()));
}

class SupplierState {
  final WaterSupplier supplier;
  final List<WaterOffer> offers; // newest first
  const SupplierState(this.supplier, this.offers);
  int get litresGiven => offers.fold(0, (a, o) => a + o.litres);
}

class SupplierStore extends Notifier<SupplierState> {
  String get _key => 'water_supplier_${ref.read(currentUserProvider)?.uid ?? 'guest'}';
  Future<void> _ready = Future.value();

  @override
  SupplierState build() {
    ref.watch(currentUserProvider.select((u) => u?.uid));
    _ready = _load();
    return const SupplierState(WaterSupplier(), []);
  }

  Future<void> _load() async {
    final raw = await SecurePrefs.getString(_key);
    if (raw == null) return;
    try {
      final m = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final saved = [for (final o in (m['offers'] as List? ?? const [])) WaterOffer.fromJson(Map<String, dynamic>.from(o as Map))];
      final ids = {for (final o in state.offers) o.incidentId};
      state = SupplierState(
        state.supplier.enabled ? state.supplier : WaterSupplier.fromJson(Map<String, dynamic>.from(m['supplier'] as Map)),
        [...state.offers, for (final o in saved) if (!ids.contains(o.incidentId)) o],
      );
    } catch (_) {
      // Unreadable save: start clean.
    }
  }

  Future<void> _save() async {
    final key = _key; // read before awaiting: the store may be disposed by then
    final payload = jsonEncode({'supplier': state.supplier.toJson(), 'offers': [for (final o in state.offers) o.toJson()]});
    await _ready;
    await SecurePrefs.setString(key, payload);
  }

  void update(WaterSupplier s) {
    state = SupplierState(s, state.offers);
    _save();
  }

  void recordOffer(WaterOffer o) {
    state = SupplierState(state.supplier, [o, ...state.offers.where((x) => x.incidentId != o.incidentId)]);
    _save();
  }
}

final supplierProvider = NotifierProvider<SupplierStore, SupplierState>(SupplierStore.new);
