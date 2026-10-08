import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/processing/application/file_exporter.dart';
import 'package:imagehost/features/processing/domain/export_models.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory sandbox;
  late Directory destination;
  const exporter = FileExporter();

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('imagehost-export-');
    destination = await Directory(p.join(sandbox.path, 'destination')).create();
  });

  tearDown(() async {
    await sandbox.delete(recursive: true);
  });

  Future<ExportInput> makeInput(
    String id, {
    String name = 'result.png',
    List<int> bytes = const [1, 2, 3, 4],
  }) async {
    final file = await File(p.join(sandbox.path, '$id.png'))
        .writeAsBytes(bytes);
    return ExportInput(
      id: id,
      source: file,
      displayName: name,
      expectedSha256: sha256.convert(bytes).toString(),
      expectedByteCount: bytes.length,
    );
  }

  test('UT-036 成功必须关闭写入并独立核对目标字节', () async {
    final input = await makeInput('success');
    final results = await exporter.exportToDirectory([input], destination);
    expect(results.single.status, ExportStatus.saved);
    expect(results.single.fileName, 'result.png');
    expect(
      await File(results.single.destinationPath!).readAsBytes(),
      await input.source.readAsBytes(),
    );
    expect(await input.source.exists(), isTrue);
  });

  test('UT-036 同名旧文件与目录保留并生成实际新名', () async {
    final input = await makeInput('collision');
    final old = await File(p.join(destination.path, 'result.png'))
        .writeAsBytes([9, 9]);
    await Directory(p.join(destination.path, 'result (1).png')).create();
    final results = await exporter.exportToDirectory([input], destination);
    expect(results.single.status, ExportStatus.saved);
    expect(results.single.fileName, 'result (2).png');
    expect(await old.readAsBytes(), [9, 9]);
    expect(await input.source.readAsBytes(), [1, 2, 3, 4]);
  });

  test('UT-036 源文件在目标目录且同名仍不覆盖源', () async {
    final input = await makeInput('self', name: 'self.png');
    final results = await exporter.exportToDirectory([input], sandbox);
    expect(results.single.status, ExportStatus.saved);
    expect(results.single.fileName, 'self (1).png');
    expect(await input.source.readAsBytes(), [1, 2, 3, 4]);
  });

  test('UT-036 并发名称竞争通过exclusive create保留两份', () async {
    final first = await makeInput('first');
    final second = await makeInput('second', bytes: [5, 6]);
    final results = await Future.wait([
      exporter.exportToDirectory([first], destination),
      exporter.exportToDirectory([second], destination),
    ]);
    expect(
      results.expand((items) => items).map((item) => item.status),
      everyElement(ExportStatus.saved),
    );
    expect(results.map((items) => items.single.fileName).toSet(), {
      'result.png',
      'result (1).png',
    });
    for (var i = 0; i < results.length; i++) {
      expect(
        await File(results[i].single.destinationPath!).readAsBytes(),
        await [first, second][i].source.readAsBytes(),
      );
    }
  });

  test('UT-036 批次逐项成功拒权和取消 保留旧文件及源', () async {
    final first = await makeInput('one', name: 'one.png');
    final second = await makeInput('two', name: 'two.png');
    final third = await makeInput('three', name: 'three.png');
    final fourth = await makeInput('four', name: 'four.png');
    final cancellation = CancellationToken();
    final results = await exporter.exportToDirectory(
      [first, second, third, fourth],
      destination,
      cancellation: cancellation,
      faultHook: (boundary, input, target) async {
        if (boundary != ExportBoundary.afterTargetClose) return;
        if (input.id == 'two') {
          throw const ExportFailure(
            ExportFailureKind.permissionDenied,
            '目标拒绝授权。',
          );
        }
        if (input.id == 'three') cancellation.cancel();
      },
    );
    expect(results.map((item) => item.status), [
      ExportStatus.saved,
      ExportStatus.failed,
      ExportStatus.cancelled,
      ExportStatus.cancelled,
    ]);
    expect(results[1].failureKind, ExportFailureKind.permissionDenied);
    expect(results[3].destinationPath, isNull);
    expect(destination.listSync().length, 1);
    for (final input in [first, second, third, fourth]) {
      expect(await input.source.exists(), isTrue);
    }
  });

  test('UT-036 已取消批次不创建目标 结果数量保持准确', () async {
    final input = await makeInput('cancelled');
    final cancellation = CancellationToken()..cancel();
    final results = await exporter.exportToDirectory(
      [input, input],
      destination,
      cancellation: cancellation,
    );
    expect(results.length, 2);
    expect(
      results.map((item) => item.status),
      everyElement(ExportStatus.cancelled),
    );
    expect(destination.listSync(), isEmpty);
  });

  test('UT-036 输入预先变更拒绝且不创建输出', () async {
    final input = await makeInput('changed');
    await input.source.writeAsBytes([8]);
    final results = await exporter.exportToDirectory([input], destination);
    expect(results.single.status, ExportStatus.failed);
    expect(results.single.failureKind, ExportFailureKind.inputChanged);
    expect(destination.listSync(), isEmpty);
    expect(await input.source.readAsBytes(), [8]);
  });

  test('UT-036 源变更清除本次字节 目标变化保守保留并反馈残留', () async {
    final first = await makeInput('source-change', name: 'source.png');
    final second = await makeInput('target-change', name: 'target.png');
    final results = await exporter.exportToDirectory(
      [first, second],
      destination,
      faultHook: (boundary, input, target) async {
        if (boundary != ExportBoundary.beforeTargetVerification) return;
        if (input.id == first.id) {
          await input.source.writeAsBytes([7]);
        } else {
          await target.writeAsBytes([7]);
        }
      },
    );
    expect(
      results.map((item) => item.status),
      everyElement(ExportStatus.failed),
    );
    expect(
      results.map((item) => item.failureKind),
      everyElement(ExportFailureKind.inputChanged),
    );
    expect(destination.listSync().length, 1);
    expect(await File(results[1].destinationPath!).readAsBytes(), [7]);
    expect(results[1].reason, contains('无法安全清除'));
    expect(await first.source.readAsBytes(), [7]);
    expect(await second.source.exists(), isTrue);
  });

  test('UT-036 关闭边界失败关闭真实句柄后清除独占输出', () async {
    final input = await makeInput('close-failure');
    final results = await exporter.exportToDirectory(
      [input],
      destination,
      faultHook: (boundary, input, target) async {
        if (boundary == ExportBoundary.beforeTargetClose) {
          throw FileSystemException('injected path ${input.source.path}');
        }
      },
    );
    expect(results.single.status, ExportStatus.failed);
    expect(results.single.reason, isNot(contains(input.source.path)));
    expect(destination.listSync(), isEmpty);
    expect(await input.source.exists(), isTrue);
  });

  test('UT-036 缺失目录与缺失源逐项失败不创建目录', () async {
    final input = await makeInput('missing');
    final missingDirectory = Directory(p.join(sandbox.path, 'not-created'));
    final directoryResult = await exporter.exportToDirectory([
      input,
    ], missingDirectory);
    expect(directoryResult.single.status, ExportStatus.failed);
    expect(await missingDirectory.exists(), isFalse);
    await input.source.delete();
    final sourceResult = await exporter.exportToDirectory([input], destination);
    expect(sourceResult.single.failureKind, ExportFailureKind.sourceMissing);
    expect(destination.listSync(), isEmpty);
  });

  test('UT-036 清理不递归删除被替换的目录及无关旧内容', () async {
    final input = await makeInput('cleanup');
    final old = await File(p.join(destination.path, 'old.png'))
        .writeAsBytes([9]);
    File? marker;
    final results = await exporter.exportToDirectory(
      [input],
      destination,
      faultHook: (boundary, input, target) async {
        if (boundary != ExportBoundary.afterTargetClose) return;
        await target.delete();
        final replacement = await Directory(target.path).create();
        marker = await File(p.join(replacement.path, 'external.txt'))
            .writeAsString('preserved');
        throw const ExportFailure(ExportFailureKind.storage, '注入失败。');
      },
    );
    expect(results.single.status, ExportStatus.failed);
    expect(results.single.reason, contains('无法安全清除'));
    expect(await marker!.readAsString(), 'preserved');
    expect(await old.readAsBytes(), [9]);
    expect(await input.source.exists(), isTrue);
  });

  test('UT-036 主动替换普通目标文件后失败清理保留替换内容', () async {
    final input = await makeInput('replaced-file');
    final results = await exporter.exportToDirectory(
      [input],
      destination,
      faultHook: (boundary, input, target) async {
        if (boundary != ExportBoundary.afterTargetClose) return;
        await target.delete();
        await File(target.path).writeAsBytes([9, 8, 7, 6]);
        throw const ExportFailure(ExportFailureKind.storage, '注入替换后失败。');
      },
    );
    expect(results.single.status, ExportStatus.failed);
    expect(results.single.reason, contains('无法安全清除'));
    expect(await File(results.single.destinationPath!).readAsBytes(), [
      9,
      8,
      7,
      6,
    ]);
    expect(await input.source.readAsBytes(), [1, 2, 3, 4]);
  });

  test('UT-036 清理路径片段非法名称保留默认扩展', () async {
    final input = await makeInput('safe-name', name: '../folder/CON:?');
    final results = await exporter.exportToDirectory([input], destination);
    expect(results.single.status, ExportStatus.saved);
    expect(results.single.fileName, 'CON__.png');
    expect(p.dirname(results.single.destinationPath!), destination.path);
  });

  test('UT-036 拒绝源目标和祖先符号链接', () async {
    final input = await makeInput('links');
    final sourceLink = Link(p.join(sandbox.path, 'source-link.png'));
    try {
      await sourceLink.create(input.source.path);
    } on FileSystemException {
      markTestSkipped('此主机未授权创建符号链接；需在可创建链接的平台补验。');
      return;
    }
    final linkedInput = ExportInput(
      id: input.id,
      source: File(sourceLink.path),
      displayName: input.displayName,
      expectedSha256: input.expectedSha256,
      expectedByteCount: input.expectedByteCount,
    );
    final sourceResults = await exporter.exportToDirectory([
      linkedInput,
    ], destination);
    expect(sourceResults.single.failureKind, ExportFailureKind.unsafePath);
    final destinationLink = Link(p.join(sandbox.path, 'destination-link'));
    await destinationLink.create(destination.path);
    final rootResults = await exporter.exportToDirectory([
      input,
    ], Directory(destinationLink.path));
    expect(rootResults.single.failureKind, ExportFailureKind.unsafePath);
    final existingLink = Link(p.join(destination.path, 'result.png'));
    await existingLink.create(input.source.path);
    final targetResults = await exporter.exportToDirectory([
      input,
    ], destination);
    expect(targetResults.single.failureKind, ExportFailureKind.unsafePath);
    expect(await input.source.readAsBytes(), [1, 2, 3, 4]);
    await existingLink.delete();
    await destinationLink.delete();
    await sourceLink.delete();
  });
}
