import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

/// A proof photo from the camera. A phone with no camera (the iOS Simulator)
/// falls back to the photo library so the flow can still be tried.
Future<File?> pickProofPhoto() async {
  final picker = ImagePicker();
  try {
    final shot = await picker.pickImage(source: ImageSource.camera, imageQuality: 75, maxWidth: 1280);
    return shot == null ? null : File(shot.path);
  } catch (e) {
    debugPrint('camera unavailable, using the library: $e');
    try {
      final shot = await picker.pickImage(source: ImageSource.gallery, imageQuality: 75, maxWidth: 1280);
      return shot == null ? null : File(shot.path);
    } catch (_) {
      return null;
    }
  }
}
