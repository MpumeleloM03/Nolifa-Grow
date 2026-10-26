import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens directions in the phone's maps app. Apple Maps on iPhone, Google
/// Maps elsewhere. Returns false if nothing could be opened.
Future<bool> openDirections(String destination) async {
  final q = Uri.encodeComponent(destination);
  final uri = !kIsWeb && Platform.isIOS
      ? Uri.parse('https://maps.apple.com/?daddr=$q&dirflg=d')
      : Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$q&travelmode=driving');
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (e) {
    debugPrint('maps: could not open directions: $e');
    return false;
  }
}

/// Opens the camera for a proof photo. A phone without a camera (the iOS
/// Simulator) falls back to the photo library so the flow can still be tried.
Future<bool> takeProofPhoto() async {
  final picker = ImagePicker();
  try {
    final shot = await picker.pickImage(
        source: ImageSource.camera, imageQuality: 70, maxWidth: 1600);
    return shot != null;
  } catch (e) {
    debugPrint('camera: unavailable, using the library: $e');
    try {
      final shot = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
      return shot != null;
    } catch (_) {
      return false;
    }
  }
}
