import 'dart:typed_data';

import 'profile_image_picker.dart';

ProfileImagePicker createPicker() => _UnsupportedProfileImagePicker();

class _UnsupportedProfileImagePicker implements ProfileImagePicker {
  @override
  Future<Uint8List?> pickImageBytes({required ProfileImageSource source}) async {
    return null;
  }
}
