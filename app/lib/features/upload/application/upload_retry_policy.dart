import '../../../core/time_source.dart';
import '../domain/provider_models.dart';
import '../domain/queue_policy.dart';

/// No request is issued here. The future durable scheduler must persist the
/// ended attempt, then freeze this delay against its monotonic clock once.
/// null means automatic retry is refused, never an instruction to send now.
Duration? automaticUploadRetryDelay(
  ProviderUploadResult result, {
  required int completedAttempts,
  required TimeSource time,
}) {
  if (result is! ProviderUploadFailure ||
      result.evidence == UploadDeliveryEvidence.uncertain ||
      result.retryAfterInvalid) {
    return null;
  }
  final kind = switch (result.kind) {
    UploadFailureKind.network ||
    UploadFailureKind.timeout => RetryableFailure.network,
    UploadFailureKind.rateLimited => RetryableFailure.rateLimited,
    _ => RetryableFailure.other,
  };
  final seconds = result.retryAfterSeconds;
  // Do not overflow Duration or silently shorten unrepresentable server waits.
  if (seconds != null && (seconds < 0 || seconds > 9223372036854)) return null;
  final retryAfter = seconds != null
      ? Duration(seconds: seconds)
      : result.retryAfterUtc?.difference(time.utcNow);
  return AutomaticRetryPolicy.delay(
    completedAttempts: completedAttempts,
    failure: kind,
    confirmedNoUncertainSideEffect: true,
    retryAfter: retryAfter,
  );
}
