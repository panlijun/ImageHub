import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/gallery/application/import_batch.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/domain/library_models.dart';
import 'package:imagehost/platform/import_gateway.dart';
import 'package:imagehost/platform/source_readiness.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const selector = MethodChannel('plugins.flutter.io/file_selector');
  late Directory sandbox;
  late LibraryRepository repository;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('imagehost_cloud_import_');
    repository = await LibraryRepository.open(
      Directory('${sandbox.path}/library'),
    );
  });
  tearDown(() async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(selector, null);
    await repository.close();
    await sandbox.delete(recursive: true);
  });

  Future<File> picture(String name, int red) async {
    final image = img.Image(width: 3, height: 2, numChannels: 4);
    img.fill(image, color: img.ColorRgba8(red, 40, 150, 255));
    final file = File('${sandbox.path}/$name');
    await file.writeAsBytes(img.encodePng(image), flush: true);
    return file;
  }

  Future<List<PlatformResource>> selected(
    List<String> paths,
    SourceReadinessProbe probe,
  ) async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(selector, (
      call,
    ) async {
      expect(call.method, 'openFile');
      expect((call.arguments as Map)['multiple'], true);
      return paths;
    });
    return ImportGateway(readinessProbe: probe).pickFiles();
  }

  test('UT-010/UT-011 cancellation while readiness is pending prevents source opening', () async {
    final checked = Completer<void>();
    final readiness = Completer<SourceReadiness>();
    final absent = '${sandbox.path}/not-opened.png';
    final resources = await selected([
      absent,
    ], _WaitingProbe(checked, readiness));
    final token = CancellationToken();
    final reading = resources.single.read(cancellation: token).toList();
    final assertion = expectLater(reading, _fails(FailureKind.cancelled));
    try {
      await checked.future;
      token.cancel();
      readiness.complete(SourceReadiness.unknown);
      await assertion;
      // A real open of this absent path would instead report sourceMissing.
      expect(await File(absent).exists(), false);
      expect((await repository.listAssets()).total, 0);
    } finally {
      if (!readiness.isCompleted) readiness.complete(SourceReadiness.unknown);
      await assertion;
    }
  });

  test('UT-008/UT-010/IT-001 explicit cloud pending first source does not block two real PNG commits', () async {
    final cloud = '${sandbox.path}/not-acquired-cloud.png';
    final first = await picture('first.png', 90);
    final second = await picture('second.png', 140);
    final probe = _Probe({cloud: SourceReadiness.cloudPending});
    final resources = await selected([cloud, first.path, second.path], probe);
    expect(
      probe.checked,
      isEmpty,
      reason: 'Selecting alone must not acquire a source.',
    );
    final report = await ImportBatch(repository).run(resources);
    expect(report.count(ImportStatus.failed), 1);
    expect(report.count(ImportStatus.saved), 2);
    expect(report.results.first.failure!.kind, FailureKind.cloudPending);
    expect(
      report.results
          .skip(1)
          .every((result) => result.status == ImportStatus.saved),
      true,
    );
    expect(probe.checked, [cloud, first.path, second.path]);
    expect((await repository.listAssets()).total, 2);
    for (final result in report.results.skip(1)) {
      expect(
        await repository.verifyCopy(result.asset!),
        CopyAvailability.available,
      );
    }
    // If the gateway opened this absent cloud path, sourceMissing would replace
    // the distinct cloudPending result. No real cloud/download PT is claimed.
    expect(await File(cloud).exists(), false);
  });

  test('UT-011 cloud skip and stop preserve committed item without checking later source', () async {
    final cloud = '${sandbox.path}/cloud-pending.png';
    final first = await picture('saved.png', 70);
    final later = await picture('later.png', 170);
    final probe = _Probe({cloud: SourceReadiness.cloudPending});
    final resources = await selected([cloud, first.path, later.path], probe);
    final cancellation = CancellationToken();
    final report = await ImportBatch(repository).run(
      resources,
      cancellation: cancellation,
      onResult: (index, _) {
        if (index == 1) cancellation.cancel();
      },
    );
    expect(report.count(ImportStatus.failed), 1);
    expect(report.count(ImportStatus.saved), 1);
    expect(report.count(ImportStatus.cancelled), 1);
    expect(probe.checked, [cloud, first.path]);
    final page = await repository.listAssets();
    expect(page.total, 1);
    expect(page.items.single.id, report.results[1].asset!.id);
    expect(
      await repository.verifyCopy(page.items.single),
      CopyAvailability.available,
    );
  });

  test('UT-010 unknown readiness preserves real read and missing source classification', () async {
    final valid = await picture('available.png', 120);
    final missing = '${sandbox.path}/missing.png';
    final probe = _Probe({
      valid.path: SourceReadiness.unknown,
      missing: SourceReadiness.unknown,
    });
    final report = await ImportBatch(repository)
        .run(await selected([missing, valid.path], probe));
    expect(report.results[0].failure!.kind, FailureKind.sourceMissing);
    expect(report.results[1].status, ImportStatus.saved);
    expect((await repository.listAssets()).total, 1);
  });

  test('UT-010 cloud acquisition failure leaves existing name favorite tags and bytes intact', () async {
    final valid = await picture('existing.png', 110);
    final committed = await repository.importResource(
      PlatformResource.file(valid),
    );
    final id = committed.asset!.id;
    await repository.setFavorite(id, true);
    await repository.replaceTags([id], ['Existing tag']);
    final before = await repository.getAsset(id);
    final cloud = '${sandbox.path}/cloud-pending.png';
    final report = await ImportBatch(repository).run(
      await selected([cloud], _Probe({cloud: SourceReadiness.cloudPending})),
    );
    expect(report.results.single.failure!.kind, FailureKind.cloudPending);
    expect(await repository.getAsset(id), before);
    expect(await repository.verifyCopy(before!), CopyAvailability.available);
    expect((await repository.listAssets()).total, 1);
  });

  test('UT-010 only exact provider cloud codes classify pending; message text never guesses', () async {
    for (final code in [
      'cloud_pending',
      'icloud_download_pending',
      'cloud_resource_pending',
      'CLOUD_PENDING',
    ]) {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        selector,
        (_) async => throw PlatformException(code: code),
      );
      await expectLater(
        ImportGateway().pickFiles(),
        _fails(FailureKind.cloudPending),
      );
    }
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      selector,
      (_) async => throw PlatformException(
        code: 'unavailable',
        message: 'icloud cloud_pending waiting for download secret-path',
      ),
    );
    await expectLater(
      ImportGateway().pickFiles(),
      _fails(FailureKind.unavailable),
    );
  });
}

Matcher _fails(FailureKind kind) => throwsA(
  isA<ResourceFailure>().having((failure) => failure.kind, 'kind', kind),
);

class _Probe extends SourceReadinessProbe {
  _Probe(this.readiness);
  final Map<String, SourceReadiness> readiness;
  final checked = <String>[];
  @override
  Future<SourceReadiness> check(String path) async {
    checked.add(path);
    return readiness[path] ?? SourceReadiness.ready;
  }
}

class _WaitingProbe extends SourceReadinessProbe {
  _WaitingProbe(this.checked, this.readiness);
  final Completer<void> checked;
  final Completer<SourceReadiness> readiness;
  @override
  Future<SourceReadiness> check(String path) {
    checked.complete();
    return readiness.future;
  }
}
