import 'package:flutter_test/flutter_test.dart';
import 'package:imagehost/core/time_source.dart';
import 'package:imagehost/features/upload/application/upload_retry_policy.dart';
import 'package:imagehost/features/upload/domain/provider_models.dart';

final class _Time implements TimeSource {
  @override
  DateTime get utcNow => DateTime.utc(2026, 10, 5);
  @override
  Duration get monotonic => Duration.zero;
}

void main() {
  final time = _Time();
  test('UT-060 every permanent or unknown transport result refuses automatic retry', () {
    for (final kind in UploadFailureKind.values) {
      expect(
        automaticUploadRetryDelay(
          ProviderUploadUnknown(kind),
          completedAttempts: 1,
          time: time,
        ),
        isNull,
      );
      expect(
        automaticUploadRetryDelay(
          ProviderUploadFailure(kind, UploadDeliveryEvidence.uncertain),
          completedAttempts: 1,
          time: time,
        ),
        isNull,
      );
      if (![
        UploadFailureKind.network,
        UploadFailureKind.timeout,
        UploadFailureKind.rateLimited,
      ].contains(kind)) {
        expect(
          automaticUploadRetryDelay(
            ProviderUploadFailure(kind, UploadDeliveryEvidence.notSent),
            completedAttempts: 1,
            time: time,
          ),
          isNull,
        );
      }
    }
    expect(
      automaticUploadRetryDelay(
        const ProviderUploadCancelled(UploadDeliveryEvidence.notSent),
        completedAttempts: 1,
        time: time,
      ),
      isNull,
    );
  });
  test(
    'UT-059/061 safe rejection honors seconds/date and retry exhaustion',
    () {
      expect(
        automaticUploadRetryDelay(
          const ProviderUploadFailure(
            UploadFailureKind.rateLimited,
            UploadDeliveryEvidence.confirmedRejected,
            retryAfterSeconds: 20,
          ),
          completedAttempts: 2,
          time: time,
        ),
        const Duration(seconds: 20),
      );
      final header = ProviderUploadFailure(
        UploadFailureKind.rateLimited,
        UploadDeliveryEvidence.confirmedRejected,
        retryAfterUtc: time.utcNow.add(const Duration(seconds: 30)),
      );
      expect(
        automaticUploadRetryDelay(header, completedAttempts: 1, time: time),
        const Duration(seconds: 30),
      );
      expect(
        automaticUploadRetryDelay(header, completedAttempts: 4, time: time),
        isNull,
      );
    },
  );
  test('UT-061 malformed/overflow waits never fall back to shorter automatic delay', () {
    for (final invalid in [
      const ProviderUploadFailure(
        UploadFailureKind.rateLimited,
        UploadDeliveryEvidence.confirmedRejected,
        retryAfterInvalid: true,
      ),
      const ProviderUploadFailure(
        UploadFailureKind.rateLimited,
        UploadDeliveryEvidence.confirmedRejected,
        retryAfterSeconds: 9223372036855,
      ),
    ]) {
      expect(
        automaticUploadRetryDelay(invalid, completedAttempts: 1, time: time),
        isNull,
      );
    }
  });
}
