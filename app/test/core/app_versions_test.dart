import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:imagehost/core/app_versions.dart';

import '../../tool/versioning.dart' as tooling;

void main() {
  test(
    'generation derives the package version without changing other text',
    () {
      const input =
          'name: imagehost\r\n'
          'version: 0.1.0+1 # package identity\r\n'
          'dependencies:\r\n  image: 4.10.1\r\n';
      final result = tooling.synchronizePubspecVersion(input, '0.2.0+3');
      expect(result, input.replaceFirst('0.1.0+1', '0.2.0+3'));
      expect(
        () => tooling.synchronizePubspecVersion('name: imagehost\n', '0.2.0+3'),
        throwsFormatException,
      );
      expect(
        () => tooling.synchronizePubspecVersion(
          'version: 0.1.0+1\nversion: 0.1.0+1\n',
          '0.2.0+3',
        ),
        throwsFormatException,
      );
    },
  );

  late Directory temporary;
  late Map<String, dynamic> input;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('imagehub-version-test-');
    input = jsonDecode(
      await File('versions.json').readAsString(),
    ) as Map<String, dynamic>;
  });
  tearDown(() async => temporary.delete(recursive: true));

  tooling.VersionManifest parse() {
    File('${temporary.path}/versions.json')
        .writeAsStringSync(jsonEncode(input));
    return tooling.readVersionManifest(temporary);
  }

  test('platform version changes do not change kernel or other platforms', () {
    final before = parse();
    (input['platforms'] as Map<String, dynamic>)['android'] = {
      'version': '1.2.3',
      'build': 7,
    };
    final after = parse();
    expect(after.kernel.version, before.kernel.version);
    expect(after.kernel.build, before.kernel.build);
    expect(
      after.platforms['windows']!.version,
      before.platforms['windows']!.version,
    );
    expect(
      after.platforms['windows']!.build,
      before.platforms['windows']!.build,
    );
    expect(after.platforms['android']!.version, '1.2.3');
    expect(after.platforms['android']!.build, 7);
    final outputs = tooling.generatedVersionFiles(after);
    expect(
      outputs['android/imagehub-versions.properties'],
      contains('platform.version=1.2.3'),
    );
    expect(outputs['windows/runner/imagehub_versions.h'], contains('0,1,0,1'));
    expect(
      outputs['ios/Flutter/ImageHubVersions.xcconfig'],
      contains('IMAGEHUB_PLATFORM_VERSION = 0.1.0'),
    );
  });

  test('kernel revision changes do not change four platform identities', () {
    final before = parse();
    (input['kernel'] as Map<String, dynamic>)['revision'] = 2;
    final after = parse();
    expect(after.kernel.build, 2);
    for (final name in tooling.platformNames) {
      expect(after.platforms[name]!.version, before.platforms[name]!.version);
      expect(after.platforms[name]!.build, before.platforms[name]!.build);
    }
  });

  test('native bounds and unknown or incomplete manifests are rejected', () {
    final platformEntries = input['platforms'] as Map<String, dynamic>;
    final windows = platformEntries['windows'] as Map<String, dynamic>;
    windows['build'] = 65536;
    expect(parse, throwsFormatException);
    windows['build'] = 1;
    windows['version'] = '../0.1.0';
    expect(parse, throwsFormatException);
    windows['version'] = '0.1.0';
    final android = platformEntries['android'] as Map<String, dynamic>;
    android['build'] = 2100000000;
    expect(parse().platforms['android']!.build, 2100000000);
    android['build'] = 2100000001;
    expect(parse, throwsFormatException);
    android['build'] = 1;
    input['formatVersion'] = 2;
    expect(parse, throwsFormatException);
    input['formatVersion'] = 1.0;
    expect(parse, throwsFormatException);
    input['formatVersion'] = 1;
    platformEntries.remove('ios');
    expect(parse, throwsFormatException);
  });

  test('UI catalog matches the authoritative five-version source', () {
    final manifest = parse();
    expect(
      imageHubVersions.kernel.identity,
      '${manifest.kernel.version}+${manifest.kernel.build}',
    );
    for (final platform in AppPlatform.values) {
      final own = manifest.platforms[platform.name]!;
      expect(
        imageHubVersions.forPlatform(platform).identity,
        '${own.version}+${own.build}',
      );
    }
    expect(AppPlatform.forOperatingSystem('linux'), isNull);
    expect(AppPlatform.forOperatingSystem('android'), AppPlatform.android);
  });
}
