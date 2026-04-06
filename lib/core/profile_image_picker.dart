import 'dart:typed_data';

import 'profile_image_picker_stub.dart'
    if (dart.library.io) 'profile_image_picker_io.dart'
    if (dart.library.html) 'profile_image_picker_web.dart';

enum ProfileImageSource { camera, gallery }

abstract class ProfileImagePicker {
  Future<Uint8List?> pickImageBytes({required ProfileImageSource source});
}

ProfileImagePicker createProfileImagePicker() => createPicker();
