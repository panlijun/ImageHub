enum RemoteDeletionState { prepared, sending, notSent, unknown }

enum RemoteDeletionReason {
  cancelled,
  timeout,
  unsupported,
  authorizationChanged,
  interrupted,
  unconfirmed,
}

/// No confirmed-delete state is available without a verified service contract.
final class RemoteDeletionOutcome {
  const RemoteDeletionOutcome(this.state, this.reason, {this.httpStatus});
  final RemoteDeletionState state;
  final RemoteDeletionReason reason;
  final int? httpStatus;
  static const cancelled = RemoteDeletionOutcome(
    RemoteDeletionState.notSent,
    RemoteDeletionReason.cancelled,
  );
  static const unknown = RemoteDeletionOutcome(
    RemoteDeletionState.unknown,
    RemoteDeletionReason.unconfirmed,
  );
  bool get valid =>
      (state == RemoteDeletionState.notSent ||
          state == RemoteDeletionState.unknown) &&
      (httpStatus == null || httpStatus! >= 100 && httpStatus! <= 599) &&
      (state != RemoteDeletionState.notSent || httpStatus == null);
}

/// Ephemeral protected request. Never serialize, print or put this in a plan.
final class CatboxDeletionRequest {
  CatboxDeletionRequest({required this.filename, required this.userhash}) {
    if (!validFilename(filename) ||
        userhash.isEmpty ||
        userhash.length > 4096 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(userhash)) {
      throw const FormatException('删除授权或单文件标识无效。');
    }
  }
  final String filename, userhash;
  static bool validFilename(String value) =>
      RegExp(r'^[A-Za-z0-9]{1,128}\.(?:png|jpg|jpeg|webp|gif|bmp)$')
          .hasMatch(value);
  @override
  String toString() => 'CatboxDeletionRequest([受保护请求])';
}

/// Ordinary audit: UUIDs, counters, fingerprints and classifications only.
final class RemoteDeletionRecord {
  const RemoteDeletionRecord({
    required this.id,
    required this.resultId,
    required this.attemptId,
    required this.targetId,
    required this.fingerprint,
    required this.targetGeneration,
    required this.state,
    required this.createdUtc,
    this.finishedUtc,
    this.reason,
    this.httpStatus,
  });
  final String id, resultId, attemptId, targetId, fingerprint;
  final int targetGeneration, createdUtc;
  final int? finishedUtc, httpStatus;
  final RemoteDeletionState state;
  final RemoteDeletionReason? reason;
  String get message => switch (state) {
    RemoteDeletionState.prepared => '删除请求已记录，尚未发送。',
    RemoteDeletionState.sending => '删除请求可能已发送，正在等待真实网络收尾。',
    RemoteDeletionState.notSent => '删除请求未发送，本地图片与链接保留。',
    RemoteDeletionState.unknown => '删除结果未确认，可能已生效；本地图片与链接保留。不会自动重试。',
  };
}
