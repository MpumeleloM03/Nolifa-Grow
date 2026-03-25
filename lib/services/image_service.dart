import 'dart:io';
import 'package:image_picker/image_picker.dart';

class ImageService {
  final ImagePicker _picker = ImagePicker();

  Future<File?> pickFromCamera() async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 224,
        maxHeight: 224,
      );
      if (photo == null) return null;
      return File(photo.path);
    } catch (e) {
      return null;
    }
  }

  Future<File?> pickFromGallery() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 224,
        maxHeight: 224,
      );
      if (image == null) return null;
      return File(image.path);
    } catch (e) {
      return null;
    }
  }
}