import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

class ImageStore {
  static const int _maxDimension = 3840;
  static const int _jpegQuality = 92;
  static final _uuid = Uuid();

  /// Compress and save a photo to app documents directory.
  /// Returns the absolute path of the saved compressed file.
  static Future<String> saveCompressed(File sourceFile) async {
    final bytes = await sourceFile.readAsBytes();
    var image = img.decodeImage(bytes);
    if (image == null) throw Exception('Could not decode image');

    // Downscale if either dimension exceeds maxDimension (3840px 4K UHD)
    if (image.width > _maxDimension || image.height > _maxDimension) {
      image = img.copyResize(
        image,
        width: image.width > image.height ? _maxDimension : null,
        height: image.height >= image.width ? _maxDimension : null,
      );
    }

    // Auto-enhance faint dot-matrix / thermal prints: boost contrast & darken mid-tone ink
    image = img.adjustColor(
      image,
      contrast: 1.30,
      gamma: 0.75,
    );

    final dir = await getApplicationDocumentsDirectory();
    final destPath = p.join(dir.path, 'invoices', '${_uuid.v4()}.jpg');
    await Directory(p.dirname(destPath)).create(recursive: true);

    final compressed = img.encodeJpg(image, quality: _jpegQuality);
    await File(destPath).writeAsBytes(compressed);
    return destPath;
  }

  static Future<void> deleteFile(String path) async {
    final f = File(path);
    if (await f.exists()) await f.delete();
  }
}
