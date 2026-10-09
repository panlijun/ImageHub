import 'dart:convert';
import 'dart:io';

/// Run from app/: dart tool/versioning.dart generate|check|describe [platform].
/// No package imports or native-asset hooks: usable before pub resolution.
void main(List<String> arguments) {
  try {
    final root = File.fromUri(Platform.script).parent.parent;
    final manifest = readVersionManifest(root);
    final command = arguments.isEmpty ? 'check' : arguments.first;
    if (command == 'describe') {
      if (arguments.length != 2 || !platformNames.contains(arguments[1])) {
        throw const FormatException('describe requires a supported platform.');
      }
      final platform = arguments[1];
      final own = manifest.platforms[platform]!;
      stdout.writeln(
        jsonEncode({
          'formatVersion': 1,
          'platform': platform,
          'kernelVersion': manifest.kernel.version,
          'kernelRevision': manifest.kernel.build,
          'platformVersion': own.version,
          'platformBuild': own.build,
        }),
      );
      return;
    }
    if (arguments.length > 1 || (command != 'check' && command != 'generate')) {
      throw const FormatException(
        'Use generate, check, or describe <platform>.',
      );
    }
    final expectedPubspec =
        '${manifest.kernel.version}+${manifest.kernel.build}';
    final pubspecFile = File('${root.path}/pubspec.yaml');
    final pubspec = pubspecFile.readAsStringSync();
    final synchronizedPubspec = synchronizePubspecVersion(
      pubspec,
      expectedPubspec,
    );
    if (command == 'check' && pubspec != synchronizedPubspec) {
      throw const FormatException(
        'pubspec version must match the kernel identity.',
      );
    }
    final outputs = generatedVersionFiles(manifest);
    if (command == 'generate' && pubspec != synchronizedPubspec) {
      pubspecFile.writeAsStringSync(synchronizedPubspec, flush: true);
    }
    for (final entry in outputs.entries) {
      final file = File('${root.path}/${entry.key}');
      if (command == 'generate') {
        file.parent.createSync(recursive: true);
        file.writeAsStringSync(entry.value, flush: true);
      } else if (!file.existsSync() ||
          file.readAsStringSync().replaceAll('\r\n', '\n') != entry.value) {
        throw FormatException('Version output is stale: ${entry.key}');
      }
    }
    stdout.writeln(
      'PASS five independent product versions; ${outputs.length} synchronized outputs',
    );
  } on Object {
    stderr.writeln(
      'Version validation failed. Check versions.json, pubspec.yaml and generated outputs.',
    );
    exitCode = 1;
  }
}

/// Derive only the top-level package version, preserving dependency and comment
/// text and the existing newline style. Ambiguous/missing declarations reject.
String synchronizePubspecVersion(String source, String identity) {
  final declaration = RegExp(
    r'^(version:[ \t]*)([^\r\n#]+?)([ \t]*(?:#[^\r\n]*)?)\r?$',
    multiLine: true,
  );
  final matches = declaration.allMatches(source).toList();
  if (matches.length != 1) {
    throw const FormatException(
      'A single top-level pubspec version is required.',
    );
  }
  final match = matches.single;
  final newlineSuffix = match.group(0)!.endsWith('\r') ? '\r' : '';
  return source.replaceRange(
    match.start,
    match.end,
    '${match.group(1)}$identity${match.group(3)}$newlineSuffix',
  );
}

const platformNames = ['windows', 'macos', 'android', 'ios'];

final class VersionEntry {
  const VersionEntry(this.version, this.build);
  final String version;
  final int build;
}

final class VersionManifest {
  const VersionManifest(this.kernel, this.platforms);
  final VersionEntry kernel;
  final Map<String, VersionEntry> platforms;
}

VersionManifest readVersionManifest(Directory root) {
  final value = jsonDecode(
    File('${root.path}/versions.json').readAsStringSync(),
  );
  final object = exactObject(value, {'formatVersion', 'kernel', 'platforms'});
  if (object['formatVersion'] is! int || object['formatVersion'] != 1) {
    throw const FormatException('Future or invalid format.');
  }
  final kernel = readVersionEntry(object['kernel'], 'revision', 2147483647);
  final platforms = exactObject(object['platforms'], platformNames.toSet());
  return VersionManifest(kernel, {
    for (final name in platformNames)
      name: readVersionEntry(platforms[name], 'build', switch (name) {
        'windows' => 65535,
        'android' => 2100000000,
        _ => 2147483647,
      }),
  });
}

Map<String, dynamic> exactObject(Object? value, Set<String> keys) {
  if (value is! Map<String, dynamic> ||
      value.length != keys.length ||
      !value.keys.every(keys.contains)) {
    throw const FormatException('Invalid keys.');
  }
  return value;
}

VersionEntry readVersionEntry(
  Object? value,
  String buildKey,
  int maximumBuild,
) {
  final object = exactObject(value, {'version', buildKey});
  final version = object['version'];
  final build = object[buildKey];
  if (version is! String ||
      version.length > 17 ||
      !RegExp(r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$')
          .hasMatch(version) ||
      version.split('.').any((part) => int.parse(part) > 65535) ||
      build is! int ||
      build < 1 ||
      build > maximumBuild) {
    throw const FormatException('Invalid version or build.');
  }
  return VersionEntry(version, build);
}

Map<String, String> generatedVersionFiles(VersionManifest manifest) {
  final kernel = manifest.kernel;
  final windows = manifest.platforms['windows']!;
  final android = manifest.platforms['android']!;
  final outputs = <String, String>{
    'lib/core/app_versions.g.dart':
        '''// Generated by tool/versioning.dart from versions.json. Do not edit.
part of 'app_versions.dart';

const imageHubVersions = AppVersionCatalog(
  kernel: KernelVersion('${kernel.version}', ${kernel.build}),
  platforms: {
${[for (final name in platformNames) "    AppPlatform.$name: PlatformVersion('${manifest.platforms[name]!.version}', ${manifest.platforms[name]!.build}),"].join('\n')}
  },
);
''',
    'windows/runner/imagehub_versions.h':
        '''// Generated by tool/versioning.dart. Do not edit.
#pragma once
#define IMAGEHUB_PLATFORM_VERSION_NUMBER ${windows.version.replaceAll('.', ',')},${windows.build}
#define IMAGEHUB_PLATFORM_VERSION_STRING "${windows.version}+${windows.build}"
#define IMAGEHUB_KERNEL_VERSION_STRING "${kernel.version}+${kernel.build}"
''',
    'android/imagehub-versions.properties':
        '''# Generated by tool/versioning.dart. Do not edit.
platform.version=${android.version}
platform.build=${android.build}
kernel.version=${kernel.version}
kernel.revision=${kernel.build}
''',
  };
  for (final name in ['macos', 'ios']) {
    final own = manifest.platforms[name]!;
    outputs['$name/Flutter/ImageHubVersions.xcconfig'] =
        '''// Generated by tool/versioning.dart. Do not edit.
IMAGEHUB_PLATFORM_VERSION = ${own.version}
IMAGEHUB_PLATFORM_BUILD = ${own.build}
IMAGEHUB_KERNEL_VERSION = ${kernel.version}
IMAGEHUB_KERNEL_REVISION = ${kernel.build}
''';
  }
  return outputs;
}
