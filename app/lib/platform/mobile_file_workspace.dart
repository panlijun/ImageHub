import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/platform_resource.dart';
import '../features/backup/data/backup_temporary_workspace.dart';
import 'android_resource_gateway.dart';
import 'apple_resource_gateway.dart';
import 'storage_capacity.dart';

/// Owns only explicitly registered, closed, unchanged private transfer files.
class MobileFileWorkspace {
  MobileFileWorkspace._(this.directory)
    : _ownership = BackupTemporaryWorkspace(directory);
  final Directory directory;
  final BackupTemporaryWorkspace _ownership;

  static Future<MobileFileWorkspace> create({Directory? parent}) async {
    final selected = parent ?? await mobileTemporaryParent();
    final canonical = Directory(await selected.resolveSymbolicLinks());
    return MobileFileWorkspace._(
      await canonical.createTemp('imagehost-transfer-'),
    );
  }

  Future<void> registerClosed(File file) async {
    _ownership.registerFile(file);
    await _ownership.verifyAndRecordFile(file);
  }

  Future<void> close() => _ownership.remove();
}

class BackupSource {
  const BackupSource(this.file, {this.release});
  final File file;
  final Future<void> Function()? release;
}

Future<BackupSource?> acquireAndroidBackup(
  CancellationToken? cancellation,
) async => acquireManagedBackup(
  await AndroidResourceGateway().pick(backup: true),
  cancellation: cancellation,
);

Future<BackupSource?> acquireAppleBackup(
  CancellationToken? cancellation,
) async => acquireManagedBackup(
  await AppleResourceGateway().pickBackup(cancellation: cancellation),
  cancellation: cancellation,
);

/// Shares the existing transfer ownership rules across native source adapters.
Future<BackupSource?> acquireManagedBackup(
  List<PlatformResource> resources, {
  CancellationToken? cancellation,
  Future<MobileFileWorkspace> Function()? createWorkspace,
  Future<int> Function(Directory directory)? availableBytes,
}) async {
  MobileFileWorkspace? workspace;
  RandomAccessFile? writer;
  File? target;
  var writerClosed = false;
  var writerCloseUncertain = false;
  var transferred = false;
  var registered = false;
  Object? failure;
  try {
    cancellation?.throwIfCancelled();
    if (resources.isEmpty) return null;
    if (resources.length != 1 || resources.single.sourceType != 'backup') {
      throw const ResourceFailure(FailureKind.unavailable);
    }
    workspace = await (createWorkspace?.call() ?? MobileFileWorkspace.create());
    target = File(p.join(workspace.directory.path, 'selected.zip'));
    await target.create(exclusive: true);
    writer = await target.open(mode: FileMode.writeOnly);
    var sinceCapacityCheck = 2 * 1024 * 1024;
    await for (final chunk in resources.single.read(
      cancellation: cancellation,
    )) {
      cancellation?.throwIfCancelled();
      if (sinceCapacityCheck >= 2 * 1024 * 1024) {
        final available =
            await (availableBytes?.call(workspace.directory) ??
                const StorageCapacity().availableBytes(workspace.directory));
        if (available < 32 * 1024 * 1024 + chunk.length) {
          throw const ResourceFailure(FailureKind.lowSpace);
        }
        sinceCapacityCheck = 0;
      }
      await writer.writeFrom(chunk);
      sinceCapacityCheck += chunk.length;
    }
    await writer.flush();
    try {
      await writer.close();
    } catch (_) {
      writerCloseUncertain = true;
      rethrow;
    }
    writer = null;
    writerClosed = true;
    cancellation?.throwIfCancelled();
    await workspace.registerClosed(target);
    registered = true;
    // The caller receives ownership only after all native source grants have
    // really retired. A late failure must not orphan a supposedly handed-off ZIP.
  } catch (error) {
    failure = error;
  } finally {
    if (writer != null) {
      try {
        await writer.close();
        writerClosed = !writerCloseUncertain;
      } catch (_) {
        failure = const ResourceFailure(FailureKind.storage);
      }
    }
    for (final resource in resources) {
      try {
        await resource.release?.call();
      } catch (_) {
        failure = const ResourceFailure(FailureKind.storage);
      }
    }
    transferred = failure == null && registered;
    if (!transferred && workspace != null) {
      try {
        if (!registered && target != null && writerClosed) {
          await workspace.registerClosed(target);
          registered = true;
        }
        // An uncertain writer is deliberately not registered for deletion.
        await workspace.close();
      } catch (_) {
        failure = const ResourceFailure(FailureKind.storage);
      }
    }
  }
  if (failure != null) {
    throw failure is ResourceFailure
        ? failure
        : const ResourceFailure(FailureKind.unavailable);
  }
  return transferred ? BackupSource(target!, release: workspace!.close) : null;
}

Future<Directory> mobileTemporaryParent() async {
  final parent = await getTemporaryDirectory();
  await parent.create(recursive: true);
  return Directory(await parent.resolveSymbolicLinks());
}

Future<String> fileSha256(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();
