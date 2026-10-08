enum ImageHostService { catbox, imgbb }

enum AccountHealth {
  unconfigured,
  unverified,
  available,
  authorizationInvalid,
  temporarilyUnavailable,
}

enum CredentialPersistence { protected, session }

enum AccountBoundary { intent, secretWritten, associated, secretDeleted }

/// Read-only counts for one stable target; no input paths or credentials.
class TargetUploadImpact {
  const TargetUploadImpact({
    required this.targetId,
    required this.pending,
    required this.running,
    required this.unknown,
  });
  final String targetId;
  final int pending, running, unknown;
}

typedef AccountFaultHook = Future<void> Function(AccountBoundary boundary);

class ProviderTarget {
  const ProviderTarget({
    required this.id,
    required this.service,
    required this.alias,
    required this.enabled,
    required this.selectedByDefault,
    required this.anonymous,
    required this.health,
    required this.removed,
    required this.generation,
    this.pendingOperation = false,
    this.sessionOnly = false,
  });
  final String id;
  final ImageHostService service;
  final String alias;
  final bool enabled;
  final bool selectedByDefault;
  final bool anonymous;
  final AccountHealth health;
  final bool removed;
  final bool pendingOperation;
  final bool sessionOnly;
  final int generation;
  String get identityMarker => id.substring(0, 8);
  TargetSnapshot get snapshot => TargetSnapshot(id, service, alias, anonymous);
}

/// This is safe ordinary history, never a credential or mutable account lookup.
class TargetSnapshot {
  const TargetSnapshot(this.id, this.service, this.alias, this.anonymous);
  final String id;
  final ImageHostService service;
  final String alias;
  final bool anonymous;
}

/// Dispatch-time-only value. Deliberately has no JSON serializer or raw toString.
class ResolvedTarget {
  const ResolvedTarget(this.target, this.credential);
  final ProviderTarget target;
  final String? credential;
  @override
  String toString() => 'ResolvedTarget([受保护])';
}

class AccountFailure implements Exception {
  const AccountFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

enum CapabilitySupport { supported, unsupported, unknown }

class ProviderInformation {
  const ProviderInformation({
    required this.service,
    required this.name,
    required this.officialUrl,
    required this.details,
  });
  final ImageHostService service;
  final String name;
  final String officialUrl;
  final String details;
  String get checkedOn => '2026-10-07';
  CapabilitySupport get multipartUpload => CapabilitySupport.supported;
  CapabilitySupport get resumableUpload => CapabilitySupport.unknown;
  CapabilitySupport get remoteListing => CapabilitySupport.unknown;
  CapabilitySupport get harmlessCredentialCheck => CapabilitySupport.unknown;
  // Implementation status does not assert a verified service limit or live test.
  bool get uploadImplemented => true;
  CapabilitySupport deletionFor({required bool anonymous}) =>
      service == ImageHostService.catbox && !anonymous
      ? CapabilitySupport.supported
      : CapabilitySupport.unknown;

  static const values = [
    ProviderInformation(
      service: ImageHostService.catbox,
      name: 'Catbox',
      officialUrl: 'https://catbox.moe/tools.php',
      details:
          '应用仅支持 userhash 账号的文件 multipart 上传，不提供匿名上传。账号 API 有删除协议，续传不作承诺。'
          '账号保留规则不能替代本机备份。GIF 文档上限 20 MB，精确字节边界及其他限制待契约核验。'
          '官方 FAQ：https://catbox.moe/faq.php。应用已接入上传、本地处理与结果管理；账号单文件删除请求已接入，响应确认尚未知。既有匿名历史仅保留本地查看与移除能力。',
    ),
    ProviderInformation(
      service: ImageHostService.imgbb,
      name: 'ImgBB',
      officialUrl: 'https://api.imgbb.com/',
      details:
          '需要 API Key，支持文件 multipart 上传；官方标称 32 MB，精确字节和格式边界待契约核验。'
          '默认不设置远端过期时间。返回的管理链接需独立保护，不等同通用删除 API；列表、续传、无副作用凭据验证未获保证。'
          '应用已接入上传、本地处理与结果管理，管理链接持久保存在受保护存储；公开 API 未提供通用远端删除能力。',
    ),
  ];
}
