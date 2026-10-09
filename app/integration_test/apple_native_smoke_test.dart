import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:imagehost/app.dart';
import 'package:imagehost/core/network_state.dart';
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/gallery/application/original_preview_reader.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/domain/library_models.dart';
import 'package:imagehost/features/gallery/domain/recycle_models.dart';
import 'package:imagehost/features/gallery/presentation/desktop_gallery.dart';
import 'package:imagehost/features/gallery/presentation/gallery_providers.dart';
import 'package:imagehost/features/gallery/presentation/mobile_gallery.dart';
import 'package:imagehost/platform/image_preview_codec.dart';
import 'package:imagehost/platform/generated/apple_files.g.dart';
import 'package:imagehost/platform/storage_capacity.dart';
import 'package:imagehost/platform/system_network_monitor.dart';
import 'package:imagehost/platform/system_secret_store.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'support/apple_xctest_startup.dart';

// Run on the real macOS engine or iOS Simulator engine, without platform
// overrides, mock channels or a fake SecretStore. These are partial software
// checks, not Apple hardware PT, performance, signing or real provider tests.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerAppleXctestStartup(binding);

  testWidgets(
    'IT-004 UT-036/075 partial Apple real Pigeon file bridge ownership rejection',
    (tester) async {
      _requireAppleEngine();
      final host = AppleFileHost();
      await expectLater(
        host.pickBackup('invalid-selection'),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'safe code',
            'invalidInput',
          ),
        ),
      );
      final unowned = const Uuid().v4();
      final read = await host.readResource(unowned);
      expect(read.code, AppleIoCode.invalidInput);
      expect(read.bytes, isEmpty);
      expect(read.eof, false);
      await expectLater(
        host.closeResource(unowned),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'safe code',
            'invalidInput',
          ),
        ),
      );
      await host.cancelSelection(const Uuid().v4());
      final operation = const Uuid().v4();
      await host.cancelExport(operation);
      final refused = await host.exportFile(
        AppleExportRequest(
          operationId: operation,
          sourcePath: '/unowned-not-opened.png',
          displayName: 'not-created.png',
          mimeType: 'image/png',
          sha256: 'a' * 64,
          byteCount: 3,
          kind: AppleDestinationKind.directory,
          destinationHandle: unowned,
        ),
      );
      expect(
        refused.code,
        Platform.isIOS ? AppleIoCode.invalidInput : AppleIoCode.unsupported,
      );
      expect(refused.uri, isNull);
      expect(refused.cleanupPending, false);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'IT-001/002 UT-004/012/102 partial Apple native storage SQLite pixels gallery and IO protection',
    (tester) async {
      _requireAppleEngine();
      final temporary = await getTemporaryDirectory();
      await temporary.create(recursive: true);
      final canonicalTemporary = await temporary.resolveSymbolicLinks();
      final prefix = 'imagehost-apple-native-${const Uuid().v4()}-';
      final sandbox = await Directory(canonicalTemporary).createTemp(prefix);
      final canonicalSandbox = await sandbox.resolveSymbolicLinks();
      expect(p.dirname(canonicalSandbox), canonicalTemporary);
      expect(p.basename(canonicalSandbox), startsWith(prefix));
      final root = Directory(p.join(canonicalSandbox, 'library'));
      const capacity = StorageCapacity();
      LibraryRepository? repository;
      LibrarySession? session;
      ProviderContainer? container;
      LibraryFileLease? heldLease;
      Future<void>? closing;
      Future<ImportResult>? cancelledImport;
      final continueSource = Completer<void>();

      Future<void> unmount() async {
        await tester.pumpWidget(const SizedBox());
        container?.dispose();
        container = null;
        try {
          await session?.close();
        } finally {
          session = null;
          await repository?.close();
          repository = null;
        }
      }

      try {
        expect(capacity.supportsPlatform, true);
        expect(
          await capacity.availableBytes(sandbox),
          greaterThan(32 * 1024 * 1024),
          reason: 'The real statfs backend must confirm the write reserve.',
        );
        final existing = await File(p.join(canonicalSandbox, '已存在 é.bin'))
            .writeAsBytes([1, 2, 3], flush: true);
        final staged = await File(p.join(canonicalSandbox, '暂存 中文📷.part'))
            .writeAsBytes([4, 5, 6], flush: true);
        expect(await capacity.publishExclusive(staged, existing), false);
        expect(await existing.readAsBytes(), [1, 2, 3]);
        expect(await staged.readAsBytes(), [4, 5, 6]);
        final published = File(p.join(canonicalSandbox, '发布 中文📷.bin'));
        expect(await capacity.publishExclusive(staged, published), true);
        expect(await staged.exists(), false);
        expect(await published.readAsBytes(), [4, 5, 6]);

        final initial = await _open(root, capacity);
        repository = initial;
        final bytes = _png(27);
        final source = await File(p.join(canonicalSandbox, '来源 é 中文📷.png'))
            .writeAsBytes(bytes, flush: true);
        final imported = await initial.importResource(
          PlatformResource.file(source),
        );
        expect(imported.status, ImportStatus.saved);
        final asset = imported.asset!;
        expect(asset.displayName, '来源 é 中文📷.png');
        expect(asset.version.sha256, sha256.convert(bytes).toString());
        expect(asset.version.byteCount, bytes.length);
        expect([asset.version.width, asset.version.height], [9, 6]);
        final original = await initial.originalFor(asset);
        expect(p.isWithin(p.join(root.path, 'originals'), original.path), true);
        expect(original.path, isNot(source.path));
        expect(await original.readAsBytes(), bytes);
        await source.delete();
        expect(await initial.verifyCopy(asset), CopyAvailability.available);

        final thumbnail = (await initial.acquireThumbnailLease(asset))!;
        try {
          expect(
            p.isWithin(p.join(root.path, 'cache'), thumbnail.file.path),
            true,
          );
          await _assertSdkPixels(await thumbnail.readBytes());
        } finally {
          await thumbnail.release();
        }
        final preview = await OriginalPreviewReader(initial).read(asset);
        ui.Codec? codec;
        try {
          expect(preview.bytes, bytes);
          codec = await decodeOriginalPreview(
            preview.bytes,
            memoryBudgetBytes: preview.memoryBudgetBytes,
          );
          await _assertFrame(codec);
        } finally {
          codec?.dispose();
          preview.release();
        }

        // Use the production app, repository and gallery providers. Only the
        // library location/session is isolated; no native picker is invoked.
        session = LibrarySession(initial, initial.recoveryIssues);
        final visibleSession = session!;
        container = ProviderContainer(
          overrides: [
            librarySessionProvider.overrideWith((ref) async => visibleSession),
          ],
        );
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container!,
            child: const ImageHostApp(),
          ),
        );
        final assetTile = find.byKey(
          Key('${Platform.isIOS ? 'mobile' : 'desktop'}-asset-${asset.id}'),
        );
        await _until(tester, () => assetTile.evaluate().isNotEmpty);
        expect(
          Platform.isIOS
              ? find.byType(MobileGallery)
              : find.byType(DesktopGallery),
          findsOneWidget,
        );
        await tester.tap(assetTile);
        await _until(tester, () => find.text('本机副本可用').evaluate().isNotEmpty);
        expect(tester.takeException(), isNull);
        await unmount();

        final reopened = await _open(root, capacity);
        repository = reopened;
        final persisted = (await reopened.getAsset(asset.id))!;
        expect(persisted, asset);
        expect(
          await (await reopened.originalFor(persisted)).readAsBytes(),
          bytes,
        );
        expect(
          await reopened.verifyCopy(persisted),
          CopyAvailability.available,
        );
        expect(reopened.recoveryIssues, isEmpty);
        final invalid = await reopened.importResource(
          PlatformResource(
            displayName: '损坏来源.png',
            openRead: () => Stream.value([1, 2, 3]),
          ),
        );
        expect(invalid.status, ImportStatus.failed);
        expect((await reopened.listAssets()).items, [asset]);

        // A real file lease holds the actual library shutdown barrier until
        // the caller has completed its file read and explicitly released it.
        final lease = await reopened.acquireAssetLease([
          asset.id,
        ], purpose: 'apple-native-smoke-read');
        heldLease = lease;
        var closeFinished = false;
        final closeWithLease = reopened.close().then<void>((_) {
          closeFinished = true;
        });
        closing = closeWithLease;
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(closeFinished, false);
        final leased = await File(lease.pathsByVersion[asset.version.id]!)
            .readAsBytes();
        expect(leased, bytes);
        await lease.release();
        heldLease = null;
        await closeWithLease;
        closing = null;
        repository = null;

        final forCancellation = await _open(root, capacity);
        repository = forCancellation;
        final cancelSource = await File(p.join(canonicalSandbox, '取消来源.png'))
            .writeAsBytes(_png(83), flush: true);
        final copied = Completer<void>();
        final sourceWaiting = Completer<void>();
        final sourceFinished = Completer<void>();
        final token = CancellationToken();
        var importFinished = false;
        final importing = forCancellation
            .importResource(
              PlatformResource(
                displayName: '取消来源.png',
                openRead: () async* {
                  try {
                    await for (final chunk in cancelSource.openRead()) {
                      yield chunk;
                      // Controlled IO fault boundary. Cancelling the async stream
                      // must wait for this actual source subscription to drain.
                      if (!sourceWaiting.isCompleted) sourceWaiting.complete();
                      await continueSource.future;
                    }
                  } finally {
                    sourceFinished.complete();
                  }
                },
              ),
              cancellation: token,
              onProgress: (progress) {
                if (progress.bytesCopied > 0 && !copied.isCompleted) {
                  copied.complete();
                }
              },
            )
            .then((result) {
              importFinished = true;
              return result;
            });
        cancelledImport = importing;
        await copied.future.timeout(const Duration(seconds: 20));
        await sourceWaiting.future.timeout(const Duration(seconds: 20));
        token.cancel();
        var cancellationCloseFinished = false;
        final cancellationClose = forCancellation.close().then<void>((_) {
          cancellationCloseFinished = true;
        });
        closing = cancellationClose;
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(importFinished, false);
        expect(sourceFinished.isCompleted, false);
        expect(cancellationCloseFinished, false);
        continueSource.complete();
        expect((await importing).status, ImportStatus.cancelled);
        cancelledImport = null;
        expect(sourceFinished.isCompleted, true);
        await cancellationClose;
        closing = null;
        repository = null;

        final finalOpen = await _open(root, capacity);
        repository = finalOpen;
        expect((await finalOpen.listAssets()).items, [asset]);
        expect(await finalOpen.verifyCopy(asset), CopyAvailability.available);
        expect(await (await finalOpen.originalFor(asset)).readAsBytes(), bytes);
        expect(finalOpen.recoveryIssues, isEmpty);
        expect(await finalOpen.listUploadBatches(), isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        if (!continueSource.isCompleted) continueSource.complete();
        try {
          await cancelledImport;
        } finally {
          try {
            await heldLease?.release();
          } finally {
            try {
              await closing;
            } finally {
              await unmount();
            }
          }
        }
        // Canonicalize Apple's temporary-root aliases before creating this
        // namespace, then verify the exact owned directory again before delete.
        final target = await sandbox.resolveSymbolicLinks();
        if (target != canonicalSandbox ||
            p.dirname(target) != canonicalTemporary ||
            !p.basename(target).startsWith(prefix)) {
          throw StateError(
            'Apple smoke cleanup ownership could not be confirmed.',
          );
        }
        await Directory(target).delete(recursive: true);
      }
    },
  );

  testWidgets(
    'UT/IT partial Apple native Keychain isolated write new-instance read delete',
    (tester) async {
      _requireAppleEngine();
      final reference = const Uuid().v4();
      final synthetic = 'apple-ci-synthetic-${const Uuid().v4()}';
      final native = _KeychainEvidenceStorage();
      final store = SystemSecretStore(storage: native);
      var stage = 'initial read';
      String? failure;
      try {
        expect(await store.read(reference) == null, true);
        stage = 'write with verified read-back';
        await store.write(reference, synthetic);
        stage = 'read through a new store instance';
        expect(
          await SystemSecretStore(storage: native).read(reference) == synthetic,
          true,
        );
        stage = 'delete with verified read-back';
        await store.delete(reference);
        stage = 'read absence through a new store instance';
        expect(
          await SystemSecretStore(storage: native).read(reference) == null,
          true,
        );
      } catch (_) {
        failure =
            'Apple SystemSecretStore failed during $stage; '
            '${native.evidence}. Check runner Keychain/signing entitlements. '
            'No fake or plaintext fallback was used.';
      } finally {
        // Only this newly generated UUID is addressed, even after a failed
        // write. No readAll/deleteAll or pre-existing application data is used.
        try {
          await store.delete(reference);
          expect(await store.read(reference) == null, true);
        } catch (_) {
          failure =
              '${failure ?? 'Apple Keychain checks completed.'} '
              'Final isolated UUID cleanup/read-back failed; ${native.evidence}.';
        }
      }
      if (failure != null) fail(failure);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('UT/IT partial Apple passive native network read listen cancel', (
    tester,
  ) async {
    _requireAppleEngine();
    const channel = MethodChannel('io.imagehost/network');
    const events = MethodChannel('io.imagehost/network_changes');
    // Direct strict calls expose a missing backend rather than allowing an
    // unknown fallback to masquerade as a successful native handshake.
    final raw = await channel.invokeMethod<Object?>('read');
    final snapshot = NetworkSnapshot.fromPlatform(raw);
    expect(NetworkStatus.values, contains(snapshot.status));
    try {
      await events.invokeMethod<void>('listen');
    } finally {
      await events.invokeMethod<void>('cancel');
    }
    final monitor = SystemNetworkMonitor();
    try {
      await monitor.start();
      await monitor.refresh();
      final observed = monitor.current;
      expect(NetworkStatus.values, contains(observed.status));
      if (observed.status == NetworkStatus.connected) {
        expect(observed.transports, isNotEmpty);
      } else {
        expect(observed.transports, isEmpty);
      }
    } finally {
      await monitor.close();
    }
    // Close is idempotent and refresh after close cannot resume listening.
    final ended = monitor.current;
    await monitor.close();
    await monitor.refresh();
    expect(monitor.current, ended);
    expect(tester.takeException(), isNull);
  });
}

void _requireAppleEngine() {
  expect(
    Platform.isMacOS || Platform.isIOS,
    true,
    reason: 'Requires a real macOS or iOS Flutter engine with native plugins.',
  );
}

Future<LibraryRepository> _open(Directory root, StorageCapacity capacity) =>
    LibraryRepository.open(
      root,
      availableStorageBytes: capacity.availableBytes,
      publishCacheExclusive: capacity.publishExclusive,
      secretStore: SystemSecretStore(),
    );

Uint8List _png(int red) {
  final picture = img.Image(width: 9, height: 6, numChannels: 3);
  img.fill(picture, color: img.ColorRgb8(red, 80, 120));
  return img.encodePng(picture);
}

Future<void> _assertSdkPixels(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    await _assertFrame(codec);
  } finally {
    codec.dispose();
  }
}

Future<void> _assertFrame(ui.Codec codec) async {
  expect(codec.frameCount, 1);
  final frame = await codec.getNextFrame();
  try {
    expect([frame.image.width, frame.image.height], [9, 6]);
    final pixels = await frame.image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    expect(pixels, isNotNull);
    expect(pixels!.lengthInBytes, 9 * 6 * 4);
    expect(pixels.buffer.asUint8List(pixels.offsetInBytes, 4), [
      27,
      80,
      120,
      255,
    ]);
  } finally {
    frame.image.dispose();
  }
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 200 && !ready(); i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(
    ready(),
    true,
    reason: 'Timed out waiting for the real Apple gallery UI.',
  );
  expect(tester.takeException(), isNull);
}

// A transparent real-plugin delegate records only numeric OSStatus evidence
// before SystemSecretStore deliberately replaces platform exceptions with its
// fixed public failure. Never expose raw exception text, values or references.
class _KeychainEvidenceStorage extends FlutterSecureStorage {
  String evidence = 'native failure status unavailable';

  Future<T> _record<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on PlatformException catch (error) {
      evidence = error.details is int
          ? 'native Keychain OSStatus=${error.details as int}'
          : 'native platform exception without numeric OSStatus';
      rethrow;
    }
  }

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) => _record(
    () => super.read(
      key: key,
      iOptions: iOptions,
      aOptions: aOptions,
      lOptions: lOptions,
      webOptions: webOptions,
      mOptions: mOptions,
      wOptions: wOptions,
    ),
  );

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) => _record(
    () => super.write(
      key: key,
      value: value,
      iOptions: iOptions,
      aOptions: aOptions,
      lOptions: lOptions,
      webOptions: webOptions,
      mOptions: mOptions,
      wOptions: wOptions,
    ),
  );

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) => _record(
    () => super.delete(
      key: key,
      iOptions: iOptions,
      aOptions: aOptions,
      lOptions: lOptions,
      webOptions: webOptions,
      mOptions: mOptions,
      wOptions: wOptions,
    ),
  );
}
