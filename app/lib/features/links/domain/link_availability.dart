enum LinkAvailability { recorded, accessible, deleted, unknown }

enum LinkProbeReason {
  reachable,
  gone,
  unconfirmed,
  cancelled,
  timeout,
  unsupported,
  interrupted,
}

/// Ordinary evidence only. No response prose, headers or management URL.
final class LinkAvailabilityRecord {
  const LinkAvailabilityRecord({
    this.state = LinkAvailability.recorded,
    this.reason,
    this.checkedAt,
    this.lastAccessibleAt,
    this.httpStatus,
  });
  final LinkAvailability state;
  final LinkProbeReason? reason;
  final DateTime? checkedAt, lastAccessibleAt;
  final int? httpStatus;
}

final class LinkProbeOutcome {
  const LinkProbeOutcome(this.state, this.reason, {this.httpStatus});
  final LinkAvailability state;
  final LinkProbeReason reason;
  final int? httpStatus;
  static const cancelled = LinkProbeOutcome(
    LinkAvailability.unknown,
    LinkProbeReason.cancelled,
  );
  static const unsupported = LinkProbeOutcome(
    LinkAvailability.unknown,
    LinkProbeReason.unsupported,
  );
  static const unconfirmed = LinkProbeOutcome(
    LinkAvailability.unknown,
    LinkProbeReason.unconfirmed,
  );
}

enum LinkProbeBatchStatus { completed, cancelled, failed, rejected }

final class LinkProbeBatchReport {
  const LinkProbeBatchReport({
    required this.status,
    required this.updated,
    required this.skipped,
    required this.total,
  });
  final LinkProbeBatchStatus status;
  final int updated, skipped, total;
}
