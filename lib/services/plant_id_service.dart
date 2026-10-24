import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:ubuntu_core/ubuntu_core.dart' show SupabaseBoot;

/// Online leaf check through the `plant-id` function. The Plant.id key stays on
/// the server, and each signed-in person has a daily allowance. Returns null when
/// there is no signal, no allowance left, or no key: the caller then uses the
/// model on the phone.
class PlantIdService {
  /// Why the last call returned null: 'limit', 'unavailable', 'offline' or 'signed-out'.
  String? lastReason;

  Future<Map<String, dynamic>?> diagnose(File imageFile) async {
    lastReason = null;
    if (!SupabaseBoot.ready || SupabaseBoot.client.auth.currentSession == null) {
      lastReason = 'signed-out';
      return null;
    }
    try {
      final photo = _shrink(await imageFile.readAsBytes());
      final res = await SupabaseBoot.client.functions
          .invoke('plant-id', body: {'image': base64Encode(photo)}).timeout(const Duration(seconds: 25));
      final data = res.data;
      if (res.status != 200 || data is! Map || data['error'] != null) {
        lastReason = 'unavailable';
        return null;
      }
      return Map<String, dynamic>.from(data);
    } on SocketException {
      lastReason = 'offline';
      return null;
    } catch (e) {
      // A 429 arrives as a FunctionException; anything else is treated as down.
      lastReason = '$e'.contains('429') ? 'limit' : '$e'.toLowerCase().contains('socket') ? 'offline' : 'unavailable';
      debugPrint('plant id: $lastReason');
      return null;
    }
  }

  /// A phone photo is several MB. A leaf reads fine at 1024 px, and the upload
  /// is often over mobile data.
  static Uint8List _shrink(Uint8List bytes) {
    final src = img.decodeImage(bytes);
    if (src == null) return bytes;
    final longest = src.width > src.height ? src.width : src.height;
    final out = longest > 1024
        ? img.copyResize(src, width: src.width >= src.height ? 1024 : null, height: src.height > src.width ? 1024 : null)
        : src;
    return Uint8List.fromList(img.encodeJpg(out, quality: 85));
  }
}
