import '../../accounts/domain/account_models.dart';

/// Exact provider limits need independent protocol evidence. A null value is
/// unknown, never an unlimited allowance or a guessed conversion of MB.
final class ProviderUploadLimits {
  ProviderUploadLimits({
    this.maximumBytes,
    Set<String>? formats,
    Map<String, int> formatMaximumBytes = const {},
  }) : formats = formats == null ? null : Set.unmodifiable(formats),
       formatMaximumBytes = _normalizeFormatMaximumBytes(formatMaximumBytes);
  const ProviderUploadLimits.unknown()
    : maximumBytes = null,
      formats = null,
      formatMaximumBytes = const {};
  final int? maximumBytes;
  final Set<String>? formats;
  final Map<String, int> formatMaximumBytes;
  bool get verified =>
      maximumBytes != null &&
      maximumBytes! > 0 &&
      formats != null &&
      formats!.isNotEmpty &&
      formatMaximumBytes.entries.every(
        (entry) => entry.value > 0 && _supportsFormat(entry.key),
      );

  int? maximumBytesFor(String format) {
    final normalized = format.toLowerCase();
    if (!verified || !_supportsFormat(normalized)) return null;
    final specific = formatMaximumBytes[normalized];
    return specific != null && specific < maximumBytes!
        ? specific
        : maximumBytes;
  }

  bool _supportsFormat(String normalized) =>
      formats?.any((value) => value.toLowerCase() == normalized) ?? false;

  static Map<String, int> _normalizeFormatMaximumBytes(
    Map<String, int> values,
  ) {
    final normalized = <String, int>{};
    for (final entry in values.entries) {
      final key = entry.key.toLowerCase();
      if (normalized.containsKey(key)) {
        throw ArgumentError('Duplicate format limit after case normalization.');
      }
      normalized[key] = entry.value;
    }
    return Map.unmodifiable(normalized);
  }
}

enum UploadFailureKind {
  authorization,
  quota,
  rateLimited,
  network,
  timeout,
  fileUnavailable,
  formatUnsupported,
  sizeExceeded,
  capabilityUnknown,
  targetUnavailable,
  protocol,
  unknown,
}

enum UploadDeliveryEvidence { notSent, confirmedRejected, uncertain }

enum UploadActivityDirection { sending, receiving }

final class UploadActivity {
  const UploadActivity(this.direction, this.bytes, this.totalBytes);
  final UploadActivityDirection direction;

  /// Actual transport bytes, including multipart framing for sending.
  final int bytes;

  /// Null when the transport has no reliable total.
  final int? totalBytes;
}

typedef UploadActivityCallback = void Function(UploadActivity activity);

/// Kept only in memory until the application writes it to SecretStore. This
/// value must never be serialized into a task, history or ordinary diagnostic.
final class SensitiveManagementSecret {
  SensitiveManagementSecret(this._value);
  final String _value;
  String revealForProtectedStorage() => _value;
  @override
  String toString() => 'SensitiveManagementSecret([受保护])';
}

sealed class ProviderUploadResult {
  const ProviderUploadResult();
}

/// IO cleanup failed. The application must retain its durable protection and
/// handle this explicit failure, never stringify a transport/native exception.
final class ProviderCleanupException implements Exception {
  const ProviderCleanupException();
  @override
  String toString() => '网络执行收尾未确认，请保留文件保护并重试。';
}

/// Transport confirmation only; the application still has to commit history.
final class ProviderUploadSuccess extends ProviderUploadResult {
  const ProviderUploadSuccess({
    required this.service,
    required this.remoteId,
    required this.directUrl,
    this.viewerUrl,
    this.managementSecret,
  });
  final ImageHostService service;
  final String remoteId;
  final Uri directUrl;
  final Uri? viewerUrl;
  final SensitiveManagementSecret? managementSecret;
  bool get usesInsecureHttp => directUrl.scheme == 'http';
  @override
  String toString() => 'ProviderUploadSuccess($service, [已确认])';
}

final class ProviderUploadFailure extends ProviderUploadResult {
  const ProviderUploadFailure(
    this.kind,
    this.evidence, {
    this.retryAfterSeconds,
    this.retryAfterUtc,
    this.retryAfterInvalid = false,
  });
  final UploadFailureKind kind;
  final UploadDeliveryEvidence evidence;

  /// Header evidence only. Scheduler owns its clock and must not shorten it.
  final int? retryAfterSeconds;
  final DateTime? retryAfterUtc;
  final bool retryAfterInvalid;
  String get message => switch (kind) {
    UploadFailureKind.authorization => '授权缺失或被服务拒绝，请更新凭据。',
    UploadFailureKind.quota => '服务额度不足，请更换目标。',
    UploadFailureKind.rateLimited => '服务限制请求频率，请稍后重试。',
    UploadFailureKind.network => '网络请求未能完成。',
    UploadFailureKind.timeout => '网络请求超时。',
    UploadFailureKind.fileUnavailable => '本机文件失效或实际字节与版本不符。',
    UploadFailureKind.formatUnsupported => '目标不支持此输出格式。',
    UploadFailureKind.sizeExceeded => '实际输出超过目标大小限制。',
    UploadFailureKind.capabilityUnknown => '目标的精确大小或格式能力尚未核验，暂不能派发。',
    UploadFailureKind.targetUnavailable => '目标已停用、移除或尚未完成配置。',
    UploadFailureKind.protocol => '服务响应未通过安全协议校验。',
    UploadFailureKind.unknown => '远端结果未确认，请核查后再决定是否再次上传。',
  };
  @override
  String toString() => message;
}

final class ProviderUploadUnknown extends ProviderUploadResult {
  const ProviderUploadUnknown(this.kind);
  final UploadFailureKind kind;
  UploadDeliveryEvidence get evidence => UploadDeliveryEvidence.uncertain;
  String get message => '远端结果未确认，请核查后再决定是否再次上传。';
  @override
  String toString() => message;
}

final class ProviderUploadCancelled extends ProviderUploadResult {
  const ProviderUploadCancelled(this.evidence);
  final UploadDeliveryEvidence evidence;
  String get message => evidence == UploadDeliveryEvidence.notSent
      ? '已取消，未发送请求。'
      : '已取消，远端可能已收到文件。';
  @override
  String toString() => message;
}
