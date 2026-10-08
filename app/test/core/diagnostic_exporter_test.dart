import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/diagnostics/application/diagnostic_exporter.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/processing/application/file_exporter.dart';
import 'package:imagehost/features/processing/domain/export_models.dart';

class _NamedExporter extends FileExporter {
  const _NamedExporter();
  @override
  Future<List<ExportItemResult>> exportToDirectory(
    List<ExportInput> inputs,
    Directory directory, {
    CancellationToken? cancellation,
    ExportFaultHook? faultHook,
  }) async {
    final input = inputs.single;
    final named = ExportInput(
      id: input.id,
      source: input.source,
      displayName: 'same.json',
      expectedSha256: input.expectedSha256,
      expectedByteCount: input.expectedByteCount,
    );
    return super.exportToDirectory(
      [named],
      directory,
      cancellation: cancellation,
      faultHook: faultHook,
    );
  }
}

void main() {
  test('UT-085 committed export remains saved when an altered private source cannot be safely cleaned', () async {
    final root = await Directory.systemTemp.createTemp(
      'diagnostic-cleanup-test-',
    );
    addTearDown(() => root.delete(recursive: true));
    String? source;
    final document = DiagnosticExportDocument(
      utf8.encode('{"eventCount":0}'),
      0,
    );
    final result = await const DiagnosticExporter().export(
      document,
      root,
      faultHook: (boundary, input, _) async {
        source = input.source.path;
        if (boundary == ExportBoundary.afterTargetVerification) {
          await input.source.writeAsString('changed-source', flush: true);
        }
      },
    );
    expect(result.status, ExportStatus.saved);
    expect(result.reason, contains('清理未确认'));
    expect(await File(result.destinationPath!).readAsBytes(), document.bytes);
    expect(await File(source!).readAsString(), 'changed-source');
    final temporary = File(source!).parent;
    expect(temporary.path.startsWith(Directory.systemTemp.path), isTrue);
    expect(
      temporary.path
          .split(Platform.pathSeparator)
          .last
          .startsWith('imagehost-diagnostics-'),
      isTrue,
    );
    await temporary.delete(recursive: true);
  });
  test(
    'UT-085 diagnostics JSON flush verifies content and preserves same name',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'diagnostic-export-test-',
      );
      addTearDown(() => root.delete(recursive: true));
      final existing = File('${root.path}/same.json');
      await existing.writeAsString('existing', flush: true);
      final bytes = utf8.encode('{"eventCount":1,"summary":"本机记录"}');
      final document = DiagnosticExportDocument(bytes, 1);
      String? source;
      final result =
          await const DiagnosticExporter(fileExporter: _NamedExporter()).export(
            document,
            root,
            faultHook: (boundary, input, _) async {
              source = input.source.path;
            },
          );
      expect(result.status, ExportStatus.saved);
      expect(result.fileName, 'same (1).json');
      expect(await existing.readAsString(), 'existing');
      expect(await File(result.destinationPath!).readAsBytes(), bytes);
      expect(await File(source!).exists(), isFalse);
      expect(await File(source!).parent.exists(), isFalse);
    },
  );

  test(
    'UT-085 cancellation waits target close and removes owned partial files',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'diagnostic-cancel-test-',
      );
      addTearDown(() => root.delete(recursive: true));
      final entered = Completer<void>(), release = Completer<void>();
      final cancellation = CancellationToken();
      String? source;
      var completed = false;
      final operation = const DiagnosticExporter().export(
        DiagnosticExportDocument(utf8.encode('{"eventCount":0}'), 0),
        root,
        cancellation: cancellation,
        faultHook: (boundary, input, _) async {
          source = input.source.path;
          if (boundary == ExportBoundary.beforeTargetClose) {
            entered.complete();
            await release.future;
          }
        },
      );
      unawaited(operation.then((_) => completed = true));
      try {
        await entered.future;
        cancellation.cancel();
        await Future<void>.delayed(Duration.zero);
        expect(completed, isFalse);
      } finally {
        release.complete();
      }
      expect((await operation).status, ExportStatus.cancelled);
      expect(await root.list().isEmpty, isTrue);
      expect(await File(source!).parent.exists(), isFalse);
    },
  );

  test('UT-085 unknown export exception gives fixed feedback and cleans owned source', () async {
    final root = await Directory.systemTemp.createTemp(
      'diagnostic-failure-test-',
    );
    addTearDown(() => root.delete(recursive: true));
    String? source;
    final result = await const DiagnosticExporter().export(
      DiagnosticExportDocument(utf8.encode('{"eventCount":0}'), 0),
      root,
      faultHook: (_, input, _) async {
        source = input.source.path;
        throw StateError('secret-private-path');
      },
    );
    expect(result.status, ExportStatus.failed);
    expect(result.reason, isNot(contains('secret-private-path')));
    expect(await File(source!).parent.exists(), isFalse);
    expect(await root.list().isEmpty, isTrue);
  });
}
