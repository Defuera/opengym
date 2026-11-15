import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

import 'api/open_gym_api.dart';

/// Device pickers behind an interface, so stores and tests never touch plugins.
abstract class Pickers {
  Future<List<UploadItem>> pickFiles();

  /// Camera or photo library. Null when cancelled.
  Future<UploadItem?> pickPhoto({required bool camera});
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

  @override
  Future<UploadItem?> pickPhoto({required bool camera}) async {
    final XFile? x = await ImagePicker().pickImage(
      source: camera ? ImageSource.camera : ImageSource.gallery,
    );
    if (x == null) {
      return null;
    }
    return UploadItem(path: x.path, name: x.name);
  }
}

/// For tests and the gallery: returns nothing.
class NoPickers implements Pickers {
  @override
  Future<List<UploadItem>> pickFiles() async => <UploadItem>[];

  @override
  Future<UploadItem?> pickPhoto({required bool camera}) async => null;
}
