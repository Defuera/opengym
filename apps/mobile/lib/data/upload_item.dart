import 'dart:io';

/// A local file picked for upload (chat attachment or import).
class UploadItem {
  const UploadItem({required this.path, required this.name, this.bytes});

  final String path;
  final String name;

  /// Set for tests and in-memory items; otherwise the bytes come from [path].
  final List<int>? bytes;

  Future<List<int>> read() async => bytes ?? await File(path).readAsBytes();

  String get mime => mimeForName(name);
}

/// Content type from the file extension. The server decides the file kind
/// from this and from the name.
String mimeForName(String name) {
  final int dot = name.lastIndexOf('.');
  final String ext = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  switch (ext) {
    case 'txt':
    case 'md':
      return 'text/plain';
    case 'csv':
      return 'text/csv';
    case 'json':
      return 'application/json';
    case 'pdf':
      return 'application/pdf';
    case 'png':
      return 'image/png';
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'heic':
      return 'image/heic';
    case 'gif':
      return 'image/gif';
    case 'webp':
      return 'image/webp';
    case 'm4a':
      return 'audio/mp4';
    case 'mp3':
      return 'audio/mpeg';
    case 'wav':
      return 'audio/wav';
    default:
      return 'application/octet-stream';
  }
}
