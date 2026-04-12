// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:typed_data';
import 'dart:html' as html;

import 'profile_image_picker.dart';

ProfileImagePicker createPicker() => _WebProfileImagePicker();

class _WebProfileImagePicker implements ProfileImagePicker {
  @override
  Future<Uint8List?> pickImageBytes({
    required ProfileImageSource source,
  }) async {
    final input = html.FileUploadInputElement()..accept = 'image/*';
    if (source == ProfileImageSource.camera) {
      input.setAttribute('capture', 'environment');
    }
    input.click();

    await input.onChange.first;
    final files = input.files;
    if (files == null || files.isEmpty) {
      return null;
    }

    final file = files.first;
    final reader = html.FileReader();
    final completer = Completer<Uint8List?>();

    reader.onLoadEnd.listen((_) {
      final result = reader.result;
      if (result is ByteBuffer) {
        completer.complete(Uint8List.view(result));
        return;
      }
      completer.complete(null);
    });

    reader.onError.listen((_) {
      completer.completeError(reader.error ?? 'Failed to read image file.');
    });

    reader.readAsArrayBuffer(file);
    return completer.future;
  }
}
