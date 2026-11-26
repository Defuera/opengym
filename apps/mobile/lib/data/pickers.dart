import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

import 'upload_item.dart';

export 'upload_item.dart';

/// Device pickers behind an interface, so stores and tests never touch plugins.
abstract class Pickers {
  Future<List<UploadItem>> pickFiles();

  /// Camera or photo library, one photo. Null when cancelled.
  Future<UploadItem?> pickPhoto({required bool camera});

  /// The photo library, several photos at once. Empty when cancelled.
  Future<List<UploadItem>> pickPhotos();
}

class DevicePickers implements Pickers {
  @override
  Future<List<UploadItem>> pickFiles() async {
    final FilePickerResult? result =
        await FilePicker.platform.pickFiles(allowMultiple: true);
    final List<UploadItem> out = <UploadItem>[];
    if (result == null) {
      return out;
    }
    for (int i = 0; i < result.files.length; i++) {
      final String? path = result.files[i].path;
      if (path != null) {
        out.add(UploadItem(path: path, name: result.files[i].name));
      }
    }
    return out;
  }

  // A phone photo is several megabytes; this size still reads well and uploads fast.
  static const double _maxSide = 2048;
  static const int _quality = 85;

  @override
  Future<UploadItem?> pickPhoto({required bool camera}) async {
    final XFile? x = await ImagePicker().pickImage(
      source: camera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: _maxSide,
      maxHeight: _maxSide,
      imageQuality: _quality,
    );
    if (x == null) {
      return null;
    }
    return UploadItem(path: x.path, name: x.name);
  }

  @override
  Future<List<UploadItem>> pickPhotos() async {
    final List<XFile> picked = await ImagePicker().pickMultiImage(
      maxWidth: _maxSide,
      maxHeight: _maxSide,
      imageQuality: _quality,
    );
    return <UploadItem>[for (final XFile x in picked) UploadItem(path: x.path, name: x.name)];
  }
}

/// For tests and the gallery: returns nothing.
class NoPickers implements Pickers {
  @override
  Future<List<UploadItem>> pickFiles() async => <UploadItem>[];

  @override
  Future<UploadItem?> pickPhoto({required bool camera}) async => null;

  @override
  Future<List<UploadItem>> pickPhotos() async => <UploadItem>[];
}
