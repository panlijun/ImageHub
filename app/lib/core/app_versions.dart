import 'dart:io';

part 'app_versions.g.dart';

/// Product versions are independent of database and portable-file formats.
enum AppPlatform {
  windows('Windows'),
  macos('macOS'),
  android('Android'),
  ios('iOS');

  const AppPlatform(this.label);
  final String label;

  static AppPlatform? forOperatingSystem(String operatingSystem) {
    for (final platform in values) {
      if (platform.name == operatingSystem) return platform;
    }
    return null;
  }

  static AppPlatform? get current =>
      forOperatingSystem(Platform.operatingSystem);
}

final class KernelVersion {
  const KernelVersion(this.version, this.revision);
  final String version;
  final int revision;
  String get identity => '$version+$revision';
}

final class PlatformVersion {
  const PlatformVersion(this.version, this.build);
  final String version;
  final int build;
  String get identity => '$version+$build';
}

final class AppVersionCatalog {
  const AppVersionCatalog({required this.kernel, required this.platforms});
  final KernelVersion kernel;
  final Map<AppPlatform, PlatformVersion> platforms;

  PlatformVersion forPlatform(AppPlatform platform) => platforms[platform]!;
  PlatformVersion? get current =>
      AppPlatform.current == null ? null : platforms[AppPlatform.current];
}
