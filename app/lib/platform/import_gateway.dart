import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../core/platform_resource.dart';
import 'source_readiness.dart';
import 'android_resource_gateway.dart';

/// Adapts native file and photo selection into read-only import resources.
class ImportGateway {
  ImportGateway({
    ImagePicker? picker,
    this.readinessProbe = const SourceReadinessProbe(),
  }) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;
  final SourceReadinessProbe readinessProbe;

  Future<List<PlatformResource>> pickFiles() async {
    try {
      if (Platform.isAndroid) return await AndroidResourceGateway().pick();
      final files = await openFiles();
      return files.map((file) => _resource(file, sourceType: 'file')).toList();
    } on Object catch (error) {
      if (_isCancellation(error)) return const [];
      throw _mapFailure(error);
    }
  }

  Future<List<PlatformResource>> pickPhotos() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      throw const ResourceFailure(FailureKind.unsupported);
    }

    try {
      if (Platform.isAndroid) {
        return await AndroidResourceGateway().pick(photos: true);
      }
      final files = await _picker.pickMultiImage();
      return files.map((file) => _resource(file, sourceType: 'photo')).toList();
    } on Object catch (error) {
      if (_isCancellation(error)) return const [];
      throw _mapFailure(error);
    }
  }

  Future<List<PlatformResource>> retrieveLostPhotos() async {
    if (!Platform.isAndroid) return const [];

    try {
      return await AndroidResourceGateway().recover();
    } on ResourceFailure {
      rethrow;
    } on Object catch (error) {
      if (_isCancellation(error)) return const [];
      throw _mapFailure(error);
    }
  }

  PlatformResource _resource(XFile file, {required String sourceType}) =>
      PlatformResource(
        displayName: file.name,
        sourceType: sourceType,
        openRead: () => _read(file),
        openReadWithCancellation: (token) => _read(file, cancellation: token),
      );

  Stream<List<int>> _read(
    XFile file, {
    CancellationToken? cancellation,
  }) async* {
    try {
      cancellation?.throwIfCancelled();
      final readiness = await readinessProbe.check(file.path);
      cancellation?.throwIfCancelled();
      if (readiness == SourceReadiness.cloudPending) {
        throw const ResourceFailure(FailureKind.cloudPending);
      }
      await for (final chunk in file.openRead()) {
        yield chunk;
      }
    } on ResourceFailure {
      rethrow;
    } on Object catch (error) {
      throw _mapFailure(error);
    }
  }

  ResourceFailure _mapFailure(Object error) {
    if (error is ResourceFailure) return error;
    if (error is FileSystemException) {
      return switch (error.osError?.errorCode) {
        5 || 13 => const ResourceFailure(FailureKind.permissionDenied),
        2 || 3 => const ResourceFailure(FailureKind.sourceMissing),
        _ => const ResourceFailure(FailureKind.unavailable),
      };
    }
    if (error is PlatformException) {
      final code = error.code.toLowerCase();
      if (_cloudPendingCodes.contains(code)) {
        return const ResourceFailure(FailureKind.cloudPending);
      }
      if (_permissionCodes.contains(code)) {
        return const ResourceFailure(FailureKind.permissionDenied);
      }
      if (_missingCodes.contains(code)) {
        return const ResourceFailure(FailureKind.sourceMissing);
      }
    }
    return const ResourceFailure(FailureKind.unavailable);
  }

  bool _isCancellation(Object error) {
    if (error is! PlatformException) return false;
    return _cancellationCodes.contains(error.code.toLowerCase());
  }

  static const _permissionCodes = {
    'permission_denied',
    'access_denied',
    'photo_access_denied',
    'read_external_storage_denied',
    'authorization_denied',
  };

  static const _missingCodes = {'file_not_found', 'source_missing'};

  static const _cloudPendingCodes = {
    'cloud_pending',
    'icloud_download_pending',
    'cloud_resource_pending',
  };

  static const _cancellationCodes = {
    'cancelled',
    'canceled',
    'user_cancelled',
    'user_canceled',
  };
}
