import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

import 'profile_image_picker.dart';

ProfileImagePicker createPicker() => _IoProfileImagePicker();

class _IoProfileImagePicker implements ProfileImagePicker {
  final ImagePicker _picker = ImagePicker();

  @override
  Future<Uint8List?> pickImageBytes({
    required ProfileImageSource source,
  }) async {
    final imageSource = source == ProfileImageSource.camera
        ? ImageSource.camera
        : ImageSource.gallery;
    final XFile? file = await _picker.pickImage(
      source: imageSource,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 82,
    );
    if (file == null) {
      return null;
    }
    return file.readAsBytes();
  }
}
