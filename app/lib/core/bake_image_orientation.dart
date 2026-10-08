import 'package:image/image.dart' as img;

/// Bakes exactly the supplied frame, without retaining its animation container.
/// image 4.10.1's combined flip for orientation 3 misses the central row of an
/// odd-height image. Its pixel-by-pixel orthogonal rotation handles every row.
img.Image bakeImageOrientation(img.Image image) {
  final frame = img.Image.from(image, noAnimation: true);
  if (frame.exif.imageIfd.orientation == 3) {
    frame.exif.imageIfd.orientation = null;
    return img.copyRotate(frame, angle: 180);
  }
  return img.bakeOrientation(frame);
}
