import 'package:path/path.dart' as p;

String exportMimeType(String name) => switch (p.extension(name).toLowerCase()) {
  '.jpg' || '.jpeg' => 'image/jpeg',
  '.png' => 'image/png',
  '.webp' => 'image/webp',
  '.gif' => 'image/gif',
  '.bmp' => 'image/bmp',
  '.zip' => 'application/zip',
  '.json' => 'application/json',
  _ => 'application/octet-stream',
};
