import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../supabase/supabase_boot.dart';

/// A farm's own logo and store picture, as uploaded with its application and
/// published when Nolifa approved it.
class FarmPictures {
  final String? logo, banner;
  const FarmPictures({this.logo, this.banner});

  static String _url(String path) => '$supabaseUrl/storage/v1/object/public/farm-brand/$path';
  ImageProvider? get logoImage => logo == null || logo!.isEmpty ? null : NetworkImage(_url(logo!));
  ImageProvider? get bannerImage => banner == null || banner!.isEmpty ? null : NetworkImage(_url(banner!));
}

/// Every approved farm's pictures, by farm name, kept live from `farm_profiles`.
/// Screens ask [of] and rebuild when this notifies.
class FarmBrands extends ChangeNotifier {
  FarmBrands._();
  static final instance = FarmBrands._();

  Map<String, FarmPictures> _byName = {};
  int _version = 0;
  StreamSubscription<List<Map<String, dynamic>>>? _sub;

  static String _key(String name) => name.trim().toLowerCase();
  FarmPictures? of(String name) => _byName[_key(name)];

  /// Replaces what is known. Called with the rows of `farm_profiles`.
  void load(Iterable<Map<String, dynamic>> rows) {
    final next = <String, FarmPictures>{};
    for (final r in rows) {
      final d = r['data'];
      if (d is! Map) continue;
      final name = '${d['farmName'] ?? ''}';
      if (name.isEmpty) continue;
      final logo = d['logo'] as String?, banner = d['banner'] as String?;
      if ((logo ?? '').isEmpty && (banner ?? '').isEmpty) continue;
      next[_key(name)] = FarmPictures(logo: logo, banner: banner);
    }
    if (mapEquals(_logos(next), _logos(_byName)) && mapEquals(_banners(next), _banners(_byName))) return;
    _byName = next;
    _version++;
    notifyListeners();
  }

  static Map<String, String?> _logos(Map<String, FarmPictures> m) => {for (final e in m.entries) e.key: e.value.logo};
  static Map<String, String?> _banners(Map<String, FarmPictures> m) => {for (final e in m.entries) e.key: e.value.banner};

  /// Follows sign-in: listens while someone is signed in, stops when they leave.
  void start() {
    final auth = Supabase.instance.client.auth;
    void follow(Session? s) {
      _sub?.cancel();
      _sub = null;
      if (s == null) {
        if (_byName.isNotEmpty) {
          _byName = {};
          _version++;
          notifyListeners();
        }
        return;
      }
      _sub = liveTable(Supabase.instance.client, 'farm_profiles', key: 'uid').listen(load, onError: (Object e) => debugPrint('farm pictures: $e'));
    }

    follow(auth.currentSession);
    auth.onAuthStateChange.listen((s) => follow(s.session));
  }
}

/// Watch this in a screen that shows a farm's picture, so it redraws when the picture arrives.
/// (A plain provider, because the registry is a singleton that a provider must not dispose.)
final farmBrandProvider = Provider<int>((ref) {
  void changed() => ref.invalidateSelf();
  FarmBrands.instance.addListener(changed);
  ref.onDispose(() => FarmBrands.instance.removeListener(changed));
  return FarmBrands.instance._version;
});
