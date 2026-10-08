import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:imagehost/core/platform_resource.dart';
import 'package:imagehost/features/gallery/data/library_repository.dart';
import 'package:imagehost/features/gallery/domain/library_models.dart';
import 'package:imagehost/features/gallery/presentation/gallery_providers.dart';
import 'package:path/path.dart' as p;

void main() {
  test('UT-013 partial controller ignores old pagination after new filter; concurrent pagination guarded', () async {
    final root = await Directory.systemTemp.createTemp('imagehost_controller_');
    Completer<void>? entered;
    Completer<void>? release;
    final repository = await LibraryRepository.open(
      Directory(p.join(root.path, 'library')),
      faultHook: (boundary) async {
        if (boundary == ImportBoundary.copy && entered != null) {
          entered.complete();
          await release!.future;
        }
      },
    );
    final container = ProviderContainer(
      overrides: [
        librarySessionProvider.overrideWith(
          (ref) => Future.value(LibrarySession(repository, const [])),
        ),
      ],
    );
    final observed = <GalleryPage>[];
    final subscription = container.listen(galleryProvider, (_, next) {
      if (!next.isLoading && next.hasValue) observed.add(next.requireValue);
    });
    addTearDown(() async {
      if (release != null && !release.isCompleted) release.complete();
      subscription.close();
      container.dispose();
      await repository.close();
      await root.delete(recursive: true);
    });
    ImageAsset? favorite;
    for (var i = 0; i < 65; i++) {
      final saved = await repository.importResource(_picture(i, '资产-$i.png'));
      expect(saved.status, ImportStatus.saved);
      if (i == 0) {
        favorite = await repository.setFavorite(saved.asset!.id, true);
      }
    }
    await container.read(galleryProvider.notifier).reload();
    expect(container.read(galleryProvider).requireValue.items.length, 60);

    // The real repository's serial write gate deterministically holds both the
    // old page and new filter query; no timing-sensitive mocks/private seams.
    entered = Completer<void>();
    release = Completer<void>();
    final importing = repository.importResource(_picture(180, '新导入.png'));
    await entered.future;
    final oldPage = container.read(galleryProvider.notifier).loadMore();
    await Future<void>.delayed(Duration.zero);
    observed.clear();
    container.read(galleryQueryProvider.notifier).setFavoritesOnly(true);
    final filtered = container.read(galleryProvider.future);
    await Future<void>.delayed(Duration.zero);
    release.complete();
    await importing;
    await oldPage;
    final finalPage = await filtered;
    expect(finalPage.total, 1);
    expect(finalPage.items.single.id, favorite!.id);
    expect(observed, isNotEmpty);
    expect(
      observed.every((page) => page.items.every((asset) => asset.favorite)),
      isTrue,
      reason: 'A late unfiltered page must never publish after filter changed.',
    );

    entered = null;
    release = null;
    container.read(galleryQueryProvider.notifier).clear();
    await container.read(galleryProvider.future);
    expect(container.read(galleryProvider).requireValue.items.length, 60);
    entered = Completer<void>();
    release = Completer<void>();
    final secondImport = repository.importResource(_picture(181, '第二次导入.png'));
    await entered.future;
    var firstFinished = false;
    final first = container
        .read(galleryProvider.notifier)
        .loadMore()
        .then((_) => firstFinished = true);
    await Future<void>.delayed(Duration.zero);
    await container.read(galleryProvider.notifier).loadMore();
    expect(
      firstFinished,
      isFalse,
      reason: 'The duplicate loadMore returns immediately while the first waits for the actual repository.',
    );
    release.complete();
    await secondImport;
    await first;
    final merged = container.read(galleryProvider).requireValue;
    expect(merged.total, 67);
    expect(
      merged.items.map((asset) => asset.id).toSet().length,
      merged.items.length,
    );
    // A changed total invalidates offsets: replace with a fresh first page,
    // then pagination obtains all identities without a repeated/omitted row.
    expect(merged.items.length, 60);
    await container.read(galleryProvider.notifier).loadMore();
    final stable = container.read(galleryProvider).requireValue;
    expect(stable.items.length, 67);
    expect(stable.items.map((asset) => asset.id).toSet().length, 67);
  });
}

PlatformResource _picture(int red, String name) {
  final image = img.Image(width: 3, height: 2, numChannels: 4);
  img.fill(image, color: img.ColorRgba8(red, 45, 110, 255));
  final bytes = img.encodePng(image);
  return PlatformResource(
    displayName: name,
    openRead: () => Stream.value(bytes),
  );
}
