import 'package:opengym/data/pickers.dart';
import 'package:opengym/models.dart';

/// Pickers that hand back what the test sets.
class FakePickers implements Pickers {
  List<UploadItem> files = <UploadItem>[];
  UploadItem? photo;
  bool fail = false;
  bool? lastCamera;

  @override
  Future<List<UploadItem>> pickFiles() async {
    if (fail) {
      throw StateError('no picker');
    }
    return files;
  }

  @override
  Future<UploadItem?> pickPhoto({required bool camera}) async {
    if (fail) {
      throw StateError('no picker');
    }
    lastCamera = camera;
    return photo;
  }
}

const int entryNow = 1700000000000;

UploadItem upload(String name) => UploadItem(path: '/x/$name', name: name, bytes: <int>[1, 2, 3]);

EntryFile imageFile(String id, {String name = 'meal.jpg', String? url}) => EntryFile(
      id: id,
      name: name,
      mime: 'image/jpeg',
      size: 3,
      kind: 'image',
      createdAt: 1,
      url: url ?? 'https://files.test/$id',
    );

EntryFile docFile(String id, {String name = 'plan.pdf'}) => EntryFile(
      id: id,
      name: name,
      mime: 'application/pdf',
      size: 3,
      kind: 'pdf',
      createdAt: 1,
      url: 'https://files.test/$id',
    );

LogEntry note(String id, String text, int at, {List<EntryFile> files = const <EntryFile>[]}) =>
    LogEntry(id: id, text: text, at: at, createdAt: at, files: files);
