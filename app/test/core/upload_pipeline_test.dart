import 'package:imagehost/core/network_state.dart';

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/core/secret_store.dart';
import 'package:imagehost/features/accounts/domain/account_models.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/processing/application/processing_coordinator.dart';
import 'package:imagehost/features/processing/domain/processing_models.dart';
import 'package:imagehost/features/upload/application/upload_coordinator.dart';
import 'package:imagehost/features/upload/data/library_upload_queue_store.dart';
import 'package:imagehost/features/upload/data/provider_adapters.dart';
import 'package:imagehost/features/upload/domain/provider_models.dart';
import 'package:imagehost/features/upload/domain/queue_policy.dart';

void main() {
  for (final rejectImgBB in [false, true]) {
    test(
      'IT-004 controlled subflow real file multipart queue ${rejectImgBB ? 'isolated authorization rejection' : 'two confirmations and secure management'} survives reopen',
      () async {
        final sandbox = await Directory.systemTemp.createTemp(
          'imagehost-upload-pipeline-',
        );
        final root = Directory('${sandbox.path}/library');
        final secrets = _Secrets();
        var repository = await LibraryRepository.open(
          root,
          secretStore: secrets,
        );
        UploadCoordinator? queue;
        try {
          final originalBytes = img.encodePng(img.Image(width: 9, height: 7));
          final asset = (await repository.importResource(
            PlatformResource(
              displayName: '真实输入.png',
              openRead: () => Stream.value(originalBytes),
            ),
          )).asset!;
          final output = await ProcessingCoordinator(repository).process(
            [asset.id],
            (inputs) => ProcessingRequest(
              operation: ProcessingOperation.compress,
              inputs: inputs,
              longestSide: 4,
              mode: ProcessingMode.sizeFirst,
            ),
            displayName: '确认输出.png',
          );
          final catbox = await repository.saveTarget(
            service: ImageHostService.catbox,
            alias: '历史名称',
            anonymous: false,
            credential: 'SyntheticAccountFixture0123456789',
          );
          final imgbb = await repository.saveTarget(
            service: ImageHostService.imgbb,
            alias: '历史名称',
            anonymous: false,
            credential: 'synthetic-only-api-key',
          );
          final transport = ControlledUploadTransport(rejectImgBB);
          final limits = ProviderUploadLimits(
            maximumBytes: 1000000,
            formats: {'png'},
          );
          queue = UploadCoordinator(
            initialNetwork: NetworkSnapshot.connected([NetworkTransport.wifi]),
            LibraryUploadQueueStore(repository),
            adapters: [
              CatboxAdapter(limits: limits, transportFactory: () => transport),
              ImgBBAdapter(limits: limits, transportFactory: () => transport),
            ],
          );
          final batch = await repository.enqueueUploads(
            intentId: 'pipeline-intent',
            outputIds: [output.id],
            targetIds: [catbox, imgbb],
          );
          expect(
            (await repository.enqueueUploads(
              intentId: 'pipeline-intent',
              outputIds: [output.id],
              targetIds: [catbox, imgbb],
            )).id,
            batch.id,
          );
          expect(transport.requests, isEmpty);
          await queue.setNetworkAllowed(true);
          await _until(() async {
            final items = (await repository.listUploadBatches()).single.items;
            return items.first.state == PublishState.succeeded &&
                (rejectImgBB
                    ? items.last.state == PublishState.waiting
                    : items.last.state == PublishState.succeeded) &&
                queue!.activeCount == 0;
          });
          expect(transport.requests.length, 2);
          final actualBytes = await output.file!.readAsBytes();
          for (final request in transport.requests) {
            expect(request.bytes.length, request.contentLength);
            expect(_containsBytes(request.bytes, actualBytes), isTrue);
            expect(_containsBytes(request.bytes, originalBytes), isFalse);
            expect(request.url.scheme, 'https');
          }
          final items = (await repository.listUploadBatches()).single.items;
          expect(items.every((i) => i.input.version == output.version), isTrue);
          expect(items.every((i) => i.attemptCount == 1), isTrue);
          final results = await repository.listUploadResults();
          expect(results.length, rejectImgBB ? 1 : 2);
          if (!rejectImgBB) {
            expect(
              results
                  .singleWhere((r) => r.target.id == imgbb)
                  .managementAvailable,
              isTrue,
            );
            expect(
              secrets.values.values,
              contains(ControlledUploadTransport.management),
            );
          }
          await repository.saveTarget(
            id: catbox,
            service: ImageHostService.catbox,
            alias: '改名后',
            anonymous: false,
            credential: 'SyntheticAccountFixture0123456789',
          );
          final reuse = await repository.enqueueUploads(
            intentId: 'reuse-confirmed',
            outputIds: [output.id],
            targetIds: [catbox],
          );
          expect(reuse.items.single.state, PublishState.succeeded);
          await queue.refresh();
          expect(transport.requests.length, 2);
          await queue.close();
          queue = null;
          await repository.close();
          repository = await LibraryRepository.open(root, secretStore: secrets);
          final history = await repository.listUploadResults();
          expect(history.length, results.length);
          expect(history.every((r) => r.target.alias == '历史名称'), isTrue);
          expect(
            history.every((r) => r.input.version == output.version),
            isTrue,
          );
          expect((await repository.listUploadBatches()).length, 2);
          // Inspect the application's own ordinary database bytes after close,
          // including WAL. These synthetic secrets never enter ordinary storage.
          await repository.close();
          for (final entity in root.listSync()) {
            if (entity is File && entity.path.contains('library.sqlite')) {
              final bytes = await entity.readAsBytes();
              expect(
                _containsBytes(bytes, utf8.encode('synthetic-only-api-key')),
                isFalse,
              );
              expect(
                _containsBytes(
                  bytes,
                  utf8.encode(ControlledUploadTransport.management),
                ),
                isFalse,
              );
              expect(
                _containsBytes(bytes, utf8.encode('managementToken0123456789')),
                isFalse,
              );
            }
          }
        } finally {
          await queue?.close();
          await repository.close();
          await sandbox.delete(recursive: true);
        }
      },
    );
  }
}

Future<void> _until(Future<bool> Function() predicate) async {
  for (var i = 0; i < 300; i++) {
    if (await predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('真实上传调用链未结束');
}

bool _containsBytes(List<int> haystack, List<int> needle) {
  if (needle.isEmpty) return true;
  for (var i = 0; i <= haystack.length - needle.length; i++) {
    var equal = true;
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        equal = false;
        break;
      }
    }
    if (equal) return true;
  }
  return false;
}

class _Secrets implements SecretStore {
  final values = <String, String>{};
  @override
  Future<void> write(String reference, String value) async =>
      values[reference] = value;
  @override
  Future<String?> read(String reference) async => values[reference];
  @override
  Future<void> delete(String reference) async => values.remove(reference);
}

/// A controlled transport executes the actual adapters and consumes actual
/// multipart streams. It never connects to an external service, and its limits
/// are test fixtures rather than a production service guarantee.
class ControlledUploadTransport implements HttpClientAdapter {
  ControlledUploadTransport(this.rejectImgBB);
  static const management = 'https://ibb.co/remoteID/managementToken0123456789';
  final bool rejectImgBB;
  final requests = <({Uri url, List<int> bytes, int contentLength})>[];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final bytes = await requestStream!.expand((chunk) => chunk).toList();
    requests.add((
      url: options.uri,
      bytes: bytes,
      contentLength: int.parse(
        options.headers[Headers.contentLengthHeader].toString(),
      ),
    ));
    if (options.uri.host == 'catbox.moe') {
      return ResponseBody.fromString(
        'https://files.catbox.moe/fixture.png',
        200,
        headers: {
          Headers.contentTypeHeader: ['text/plain'],
        },
      );
    }
    if (rejectImgBB) {
      return ResponseBody.fromString('authorization rejected', 401);
    }
    return ResponseBody.fromString(
      jsonEncode({
        'success': true,
        'status': 200,
        'data': {
          'id': 'remoteID',
          'url': 'https://i.ibb.co/remoteID/fixture.png',
          'url_viewer': 'https://ibb.co/remoteID',
          'delete_url': management,
        },
      }),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
