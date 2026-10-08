import '../../gallery/data/library_repository.dart';
import '../domain/link_transfer.dart';

/// Validates the repository-owned, explicitly confirmed text plan before a
/// local system action. Retrying never creates an upload or alters a result.
final class LinkTransferCoordinator {
  const LinkTransferCoordinator(this.repository, this.gateway);

  final LibraryRepository repository;
  final LinkTransferGateway gateway;

  Future<LinkTransferReport> copy(LinkCopyPlan plan) =>
      _transfer(plan, () => gateway.copyText(plan.batch.text));

  Future<LinkTransferReport> share(
    LinkCopyPlan plan, {
    LinkShareAnchor? anchor,
  }) =>
      _transfer(plan, () => gateway.shareText(plan.batch.text, anchor: anchor));

  Future<LinkTransferReport> _transfer(
    LinkCopyPlan plan,
    Future<LinkTransferStatus> Function() action,
  ) async {
    LinkTransferReport report(LinkTransferStatus status) => LinkTransferReport(
      status: status,
      copied: plan.batch.copied,
      skipped: plan.batch.skipped,
      duplicates: plan.batch.duplicates,
    );
    try {
      await repository.validateLinkCopyPlan(plan);
    } catch (_) {
      return report(LinkTransferStatus.stale);
    }
    if (plan.batch.text.isEmpty) return report(LinkTransferStatus.empty);
    try {
      return report(await action());
    } catch (_) {
      return report(LinkTransferStatus.failed);
    }
  }
}
