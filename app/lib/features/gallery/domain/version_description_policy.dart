import 'library_models.dart';

/// A narrowly defined correction of this project's earlier PNG audit metadata.
/// Callers must first establish identity or a verified content mapping. This
/// policy never permits conflicting permanent versions to be merged.
abstract final class VersionDescriptionPolicy {
  static bool same(ImageVersion a, ImageVersion b) =>
      a.sha256 == b.sha256 &&
      a.byteCount == b.byteCount &&
      a.format == b.format &&
      a.width == b.width &&
      a.height == b.height &&
      a.frameCount == b.frameCount &&
      a.orientation == b.orientation;

  static bool isPngOrientationCorrection(
    ImageVersion earlier,
    ImageVersion confirmed,
  ) =>
      earlier.sha256 == confirmed.sha256 &&
      earlier.byteCount == confirmed.byteCount &&
      earlier.format == 'PNG' &&
      confirmed.format == 'PNG' &&
      earlier.frameCount == confirmed.frameCount &&
      earlier.orientation == 1 &&
      confirmed.orientation >= 2 &&
      confirmed.orientation <= 8 &&
      earlier.width ==
          (confirmed.orientation >= 5 ? confirmed.height : confirmed.width) &&
      earlier.height ==
          (confirmed.orientation >= 5 ? confirmed.width : confirmed.height);

  static bool auditCompatible(ImageVersion a, ImageVersion b) =>
      same(a, b) ||
      isPngOrientationCorrection(a, b) ||
      isPngOrientationCorrection(b, a);

  /// Select only a comparison descriptor; frozen audit values stay untouched.
  static ImageVersion preferredAudit(ImageVersion a, ImageVersion b) =>
      isPngOrientationCorrection(a, b) ? b : a;
}
