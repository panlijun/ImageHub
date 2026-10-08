import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';

import '../../../core/bake_image_orientation.dart';
import '../../../core/platform_resource.dart';
import '../../gallery/domain/library_models.dart';
import '../domain/processing_models.dart';
import 'metadata_policy.dart';

/// Shared static pixel engine. Budgets are candidate limits, not measured RAM.
/// The caller must hold source leases until this future completes (including
/// failures): onExit is awaited before returning and all worker file I/O is sync.
class ImageProcessor {
  const ImageProcessor();

  ProcessingPlan plan(
    ProcessingRequest request, {
    int memoryBudgetBytes = 512 * 1024 * 1024,
  }) => planProcessing(request, memoryBudgetBytes);

  Future<ProcessingResult> process(
    ProcessingRequest request, {
    int memoryBudgetBytes = 512 * 1024 * 1024,
    CancellationToken? cancellation,
    File? destination,
  }) async {
    final snapshot = request.toSnapshot();
    final frozen = ProcessingRequest.fromSnapshot(snapshot);
    plan(frozen, memoryBudgetBytes: memoryBudgetBytes);
    _cancelled(cancellation);
    Directory? temporaryDirectory;
    File? output;
    var ownsOutput = false;
    var succeeded = false;
    Isolate? worker;
    Timer? timer;
    final events = ReceivePort();
    final stopped = Completer<void>();
    Map<Object?, Object?>? reply;
    var wasCancelled = false;
    final subscription = events.listen((message) {
      if (message == null) {
        if (!stopped.isCompleted) stopped.complete();
      } else if (message is Map) {
        reply = message;
      } else {
        reply = {'error': 'invalidImage', 'message': '图片处理工作线程异常。'};
      }
    });
    try {
      if (destination == null) {
        temporaryDirectory = await Directory.systemTemp.createTemp(
          'imagehost_processing_',
        );
        output = File(
          path.join(
            temporaryDirectory.path,
            '${const Uuid().v4()}.${frozen.outputFormat.name}',
          ),
        );
      } else {
        output = destination.absolute;
      }
      await _validateDestination(frozen, output);
      // Exclusive reservation prevents clobbering even when another actor races.
      await output.create(exclusive: true);
      ownsOutput = true;
      _cancelled(cancellation);
      worker = await Isolate.spawn<List<Object?>>(
        _processWorker,
        [events.sendPort, snapshot, memoryBudgetBytes, output.path],
        onExit: events.sendPort,
        onError: events.sendPort,
        errorsAreFatal: true,
        debugName: 'imagehost-static-processing',
      );
      void checkCancellation() {
        if (cancellation?.isCancelled == true && !stopped.isCompleted) {
          wasCancelled = true;
          worker?.kill(priority: Isolate.immediate);
        }
      }

      timer = Timer.periodic(
        const Duration(milliseconds: 15),
        (_) => checkCancellation(),
      );
      checkCancellation();
      await stopped.future;
      _cancelled(cancellation);
      if (wasCancelled) {
        throw const ProcessingFailure(
          ProcessingFailureKind.cancelled,
          '处理已取消。',
        );
      }
      final response = reply;
      if (response == null || response['error'] != null) {
        throw ProcessingFailure(
          response == null
              ? ProcessingFailureKind.invalidImage
              : ProcessingFailureKind.values.byName(
                  response['error'] as String,
                ),
          response?['message'] as String? ?? '图片处理工作线程未返回有效结果。',
        );
      }
      final result = ProcessingResult(
        file: output,
        version: versionFromSnapshot(
          response['version'] as Map<Object?, Object?>,
        ),
        request: frozen,
        lossy: response['lossy'] as bool,
        transparencyRemoved: response['transparencyRemoved'] as bool,
        animationRemoved: response['animationRemoved'] as bool,
        warnings: (response['warnings'] as List<Object?>).cast<String>(),
        temporaryDirectory: temporaryDirectory,
      );
      succeeded = true;
      return result;
    } on ProcessingFailure {
      rethrow;
    } on FileSystemException {
      throw const ProcessingFailure(
        ProcessingFailureKind.storage,
        '无法创建或写入临时结果，请检查目录权限和可用空间。',
      );
    } finally {
      timer?.cancel();
      if (worker != null && !stopped.isCompleted) {
        worker.kill(priority: Isolate.immediate);
        await stopped.future;
      }
      await subscription.cancel();
      events.close();
      if (!succeeded) {
        if (ownsOutput && output != null && await output.exists()) {
          await output.delete();
        }
        if (temporaryDirectory != null && await temporaryDirectory.exists()) {
          await temporaryDirectory.delete();
        }
      }
    }
  }
}

void _cancelled(CancellationToken? token) {
  if (token?.isCancelled == true) {
    throw const ProcessingFailure(ProcessingFailureKind.cancelled, '处理已取消。');
  }
}

Future<void> _validateDestination(
  ProcessingRequest request,
  File output,
) async {
  if (await FileSystemEntity.type(output.path, followLinks: false) !=
      FileSystemEntityType.notFound) {
    throw const ProcessingFailure(
      ProcessingFailureKind.storage,
      '处理结果路径已存在，不能覆盖。',
    );
  }
  // No source or destination symlinks, including a symlinked ancestor.
  for (final target in [
    ...request.inputs.map((input) => input.file.absolute.path),
    output.path,
  ]) {
    var cursor = target;
    while (true) {
      if (await FileSystemEntity.type(cursor, followLinks: false) ==
          FileSystemEntityType.link) {
        throw const ProcessingFailure(
          ProcessingFailureKind.storage,
          '处理路径不能包含符号链接。',
        );
      }
      final parent = path.dirname(cursor);
      if (parent == cursor) break;
      cursor = parent;
    }
  }
  final parent = await output.parent.resolveSymbolicLinks();
  final resolvedOutput = path.join(parent, path.basename(output.path));
  for (final input in request.inputs) {
    if (path.equals(await input.file.resolveSymbolicLinks(), resolvedOutput)) {
      throw const ProcessingFailure(
        ProcessingFailureKind.storage,
        '处理结果不能覆盖输入图片。',
      );
    }
  }
}

ProcessingPlan planProcessing(ProcessingRequest request, int budget) {
  void invalid(String message) =>
      throw ProcessingFailure(ProcessingFailureKind.invalidParameters, message);
  if (budget <= 0) invalid('处理预算必须是正整数。');
  if (request.longestSide < 1 || request.longestSide > 16384) {
    invalid('最长边必须是 1–16384 的整数。');
  }
  if (request.outputFormat == ProcessingFormat.png && request.quality != null) {
    invalid('PNG 不接受有损质量参数。');
  }
  if (request.quality != null &&
      (request.quality! < 1 || request.quality! > 100)) {
    invalid('质量必须是 1–100 的整数。');
  }
  if (request.gap < 0 || request.gap > 1024) invalid('拼接间距必须是 0–1024 的整数。');
  if (request.backgroundArgb < 0 || request.backgroundArgb > 0xffffffff) {
    invalid('背景必须是有效 ARGB 颜色。');
  }
  if (request.inputs.isEmpty ||
      (request.operation == ProcessingOperation.stitch
          ? request.inputs.length < 2
          : request.inputs.length != 1)) {
    invalid('裁剪和单项压缩需要一张图片；拼接至少需要两张。');
  }
  if (request.operation != ProcessingOperation.crop && request.crop != null) {
    invalid('只有裁剪任务可以携带裁剪区域。');
  }
  var decoded = BigInt.zero;
  var encodedInput = BigInt.zero;
  for (final input in request.inputs) {
    final version = input.version;
    if (input.assetId.isEmpty ||
        version.id.isEmpty ||
        version.width < 1 ||
        version.height < 1 ||
        version.frameCount < 1 ||
        version.byteCount < 1 ||
        version.orientation < 1 ||
        version.orientation > 8 ||
        !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(version.sha256)) {
      invalid('输入版本身份或尺寸无效。');
    }
    if (!{'PNG', 'JPEG', 'WebP', 'GIF', 'BMP'}.contains(version.format)) {
      throw const ProcessingFailure(
        ProcessingFailureKind.unsupported,
        '暂不支持该输入格式。',
      );
    }
    if (input.selectedFrame != null &&
        (input.selectedFrame! < 0 ||
            input.selectedFrame! >= version.frameCount)) {
      invalid('选定帧超出动画范围。');
    }
    if (version.isAnimated &&
        (input.selectedFrame == null || !request.explicitStaticConversion)) {
      throw const ProcessingFailure(
        ProcessingFailureKind.confirmationRequired,
        '动画不能报告为保真静态结果，请确认静态转换并明确选择帧，或保留原图。',
      );
    }
    // Decode all animation frames to correctly compose frame disposal/offsets.
    decoded +=
        BigInt.from(version.width) *
        BigInt.from(version.height) *
        BigInt.from(8) *
        BigInt.from(version.frameCount);
    encodedInput += BigInt.from(version.byteCount) * BigInt.from(3);
  }
  // Bound geometry calculations before any potentially overflowing native int.
  if (decoded + encodedInput > BigInt.from(budget)) _budgetFailure();
  final sizes = request.inputs
      .map((input) => PixelSize(input.version.width, input.version.height))
      .toList();
  PixelSize output;
  final positions = <ImagePlacement>[];
  switch (request.operation) {
    case ProcessingOperation.compress:
      output = request.mode == ProcessingMode.sizeFirst
          ? fitLongestSide(sizes.single, request.longestSide)
          : sizes.single;
      positions.add(const ImagePlacement(0, 0));
    case ProcessingOperation.crop:
      final crop = request.crop;
      if (crop == null) invalid('请确认裁剪区域。');
      final confirmed = crop!;
      final size = sizes.single;
      if (confirmed.x < 0 ||
          confirmed.y < 0 ||
          confirmed.width < 1 ||
          confirmed.height < 1 ||
          confirmed.x > size.width - confirmed.width ||
          confirmed.y > size.height - confirmed.height) {
        invalid('裁剪区域必须是方向正确后图内的整数像素区域。');
      }
      output = PixelSize(confirmed.width, confirmed.height);
      positions.add(const ImagePlacement(0, 0));
    case ProcessingOperation.stitch:
      final maxWidth = sizes.map((size) => size.width).reduce(math.max);
      final maxHeight = sizes.map((size) => size.height).reduce(math.max);
      if (request.layout == StitchLayout.horizontal) {
        output = PixelSize(
          sizes.fold(0, (sum, size) => sum + size.width) +
              request.gap * (sizes.length - 1),
          maxHeight,
        );
        var x = 0;
        for (final size in sizes) {
          positions.add(ImagePlacement(x, (maxHeight - size.height) ~/ 2));
          x += size.width + request.gap;
        }
      } else if (request.layout == StitchLayout.vertical) {
        output = PixelSize(
          maxWidth,
          sizes.fold(0, (sum, size) => sum + size.height) +
              request.gap * (sizes.length - 1),
        );
        var y = 0;
        for (final size in sizes) {
          positions.add(ImagePlacement((maxWidth - size.width) ~/ 2, y));
          y += size.height + request.gap;
        }
      } else {
        final columns = math.sqrt(sizes.length).ceil();
        final rows = (sizes.length + columns - 1) ~/ columns;
        output = PixelSize(
          maxWidth * columns + request.gap * (columns - 1),
          maxHeight * rows + request.gap * (rows - 1),
        );
        for (var i = 0; i < sizes.length; i++) {
          positions.add(
            ImagePlacement(
              (i % columns) * (maxWidth + request.gap) +
                  (maxWidth - sizes[i].width) ~/ 2,
              (i ~/ columns) * (maxHeight + request.gap) +
                  (maxHeight - sizes[i].height) ~/ 2,
            ),
          );
        }
      }
  }
  // Decode + orientation/palette copies + canvas/resize + encoded pixel scratch.
  // Conservative per-pixel multipliers cover uint16 PNG and VP8/VP8L workspaces;
  // they are estimates, not guarantees against OS pressure or malformed codecs.
  final estimate =
      encodedInput +
      decoded * BigInt.from(3) +
      BigInt.from(output.width) * BigInt.from(output.height) * BigInt.from(64) +
      BigInt.from(1024 * 1024);
  if (estimate > BigInt.from(budget)) _budgetFailure();
  if (request.outputFormat == ProcessingFormat.jpeg &&
      (output.width > 65535 || output.height > 65535)) {
    throw const ProcessingFailure(
      ProcessingFailureKind.unsupported,
      'JPEG 编码器不支持此输出尺寸，请选择 PNG 或减小尺寸。',
    );
  }
  if (request.outputFormat == ProcessingFormat.webp &&
      (output.width > 16383 || output.height > 16383)) {
    throw const ProcessingFailure(
      ProcessingFailureKind.unsupported,
      'WebP 编码器不支持此输出尺寸，请选择 PNG 或减小尺寸。',
    );
  }
  return ProcessingPlan(output, positions, estimate.toInt());
}

PixelSize fitLongestSide(PixelSize size, int longestSide) {
  if (size.width < 1 ||
      size.height < 1 ||
      longestSide < 1 ||
      longestSide > 16384) {
    throw const ProcessingFailure(
      ProcessingFailureKind.invalidParameters,
      '尺寸和最长边必须是有效正整数。',
    );
  }
  final longest = math.max(size.width, size.height);
  if (longest <= longestSide) return size;
  int scaled(int dimension) {
    final numerator = BigInt.from(dimension) * BigInt.from(longestSide);
    final divisor = BigInt.from(longest);
    return math.max(
      1,
      ((numerator * BigInt.two + divisor) ~/ (divisor * BigInt.two)).toInt(),
    );
  }

  return PixelSize(scaled(size.width), scaled(size.height));
}

Never _budgetFailure() => throw const ProcessingFailure(
  ProcessingFailureKind.resourceBudget,
  '处理超出当前候选内存预算，请降低尺寸、减少输入或取消。',
);

void _processWorker(List<Object?> arguments) {
  final port = arguments[0] as SendPort;
  try {
    final request = ProcessingRequest.fromSnapshot(
      arguments[1] as Map<Object?, Object?>,
    );
    final result = _processSync(
      request,
      arguments[2] as int,
      arguments[3] as String,
    );
    Isolate.exit(port, result);
  } on ProcessingFailure catch (failure) {
    Isolate.exit(port, {
      'error': failure.kind.name,
      'message': failure.message,
    });
  } on FileSystemException {
    Isolate.exit(port, {
      'error': ProcessingFailureKind.storage.name,
      'message': '读取输入或写入临时结果失败。',
    });
  } catch (_) {
    Isolate.exit(port, {
      'error': ProcessingFailureKind.invalidImage.name,
      'message': '图片内容无法完整解码或编码。',
    });
  }
}

Map<String, Object?> _processSync(
  ProcessingRequest request,
  int budget,
  String outputPath,
) {
  final plan = planProcessing(request, budget);
  final images = <img.Image>[];
  final colors = <ColorMetadata>[];
  var actualInputBytes = 0;
  for (final input in request.inputs) {
    final size = input.file.lengthSync();
    if (size > budget ~/ 3 - actualInputBytes) _budgetFailure();
    actualInputBytes += size;
    if (size != input.version.byteCount) _inputChanged();
    final bytes = input.file.readAsBytesSync();
    if (sha256.convert(bytes).toString() != input.version.sha256) {
      _inputChanged();
    }
    final format = _identifyFormat(bytes);
    if (format != input.version.format) _inputChanged();
    final decoder = img.findDecoderForData(bytes);
    final info = decoder?.startDecode(bytes);
    final frames = info is img.WebPInfo && !info.hasAnimation
        ? 1
        : info?.numFrames ?? 0;
    if (info == null || info.width < 1 || info.height < 1 || frames < 1) {
      _invalidImage();
    }
    final color = MetadataPolicy.inspect(bytes, format);
    if (format == 'PNG' && color.orientation != input.version.orientation) {
      _inputChanged();
    }
    final orientation = format == 'JPEG'
        ? color.orientation
        : input.version.orientation;
    final headerWidth = orientation >= 5 ? info.height : info.width;
    final headerHeight = orientation >= 5 ? info.width : info.height;
    // JPEG's decoder already bakes EXIF, so the existing inspector records 1.
    if (frames != input.version.frameCount ||
        headerWidth != input.version.width ||
        headerHeight != input.version.height ||
        (format == 'JPEG' &&
            input.version.orientation != 1 &&
            input.version.orientation != orientation)) {
      _inputChanged();
    }
    // Header and metadata agree; the plan now bounds actual decoded allocation.
    colors.add(color);
    final decoded = decoder!.decode(bytes);
    if (decoded == null || decoded.numFrames != frames) _invalidImage();
    if (format != 'JPEG' &&
        format != 'PNG' &&
        (decoded.exif.imageIfd.orientation ?? 1) != orientation) {
      _inputChanged();
    }
    var image = img.Image.from(
      decoded.getFrame(input.selectedFrame ?? 0),
      noAnimation: true,
    );
    if (format == 'PNG') image.exif.imageIfd.orientation = color.orientation;
    if (format != 'JPEG') image = bakeImageOrientation(image);
    if (image.width != input.version.width ||
        image.height != input.version.height) {
      _inputChanged();
    }
    if (image.hasPalette) image = image.convert(numChannels: 4);
    MetadataPolicy.clearPrivateMetadata(image);
    images.add(image);
  }
  final color = MetadataPolicy.combine(colors, request.outputFormat);
  final stitchRemovesTransparency =
      request.operation == ProcessingOperation.stitch &&
      (request.backgroundArgb >> 24) == 255 &&
      images.any((image) => image.any((pixel) => pixel.aNormalized < 1));
  if (stitchRemovesTransparency && !request.backgroundConfirmed) {
    throw const ProcessingFailure(
      ProcessingFailureKind.confirmationRequired,
      '使用不透明拼接背景需要确认背景颜色，或选择透明背景。',
    );
  }
  var image = switch (request.operation) {
    ProcessingOperation.compress => images.single,
    ProcessingOperation.crop => img.copyCrop(
      images.single,
      x: request.crop!.x,
      y: request.crop!.y,
      width: request.crop!.width,
      height: request.crop!.height,
    ),
    ProcessingOperation.stitch => _stitch(images, plan, request.backgroundArgb),
  };
  if (request.operation == ProcessingOperation.compress &&
      (image.width != plan.outputSize.width ||
          image.height != plan.outputSize.height)) {
    image = img.copyResize(
      image,
      width: plan.outputSize.width,
      height: plan.outputSize.height,
      interpolation: img.Interpolation.average,
    );
  }
  final hadTransparency = image.any((pixel) => pixel.aNormalized < 1);
  final transparencyRemoved =
      stitchRemovesTransparency ||
      (request.outputFormat == ProcessingFormat.jpeg && hadTransparency);
  if (request.outputFormat == ProcessingFormat.jpeg && hadTransparency) {
    if (!request.backgroundConfirmed || (request.backgroundArgb >> 24) != 255) {
      throw const ProcessingFailure(
        ProcessingFailureKind.confirmationRequired,
        '透明图转 JPEG 需要确认不透明背景颜色，缺省为白色。',
      );
    }
    final flattened = img.Image(
      width: image.width,
      height: image.height,
      numChannels: 4,
      format: image.format,
    );
    img.fill(flattened, color: _argb(request.backgroundArgb));
    img.compositeImage(flattened, image);
    image = flattened;
  }
  MetadataPolicy.clearPrivateMetadata(image);
  final lossy =
      request.outputFormat == ProcessingFormat.jpeg ||
      (request.outputFormat == ProcessingFormat.webp &&
          image.bitsPerChannel > 8) ||
      (request.outputFormat == ProcessingFormat.webp &&
          request.mode == ProcessingMode.sizeFirst);
  var encoded = switch (request.outputFormat) {
    ProcessingFormat.png => img.encodePng(image, singleFrame: true),
    ProcessingFormat.jpeg => img.encodeJpg(
      image,
      quality: request.quality!,
      chroma: img.JpegChroma.yuv444,
    ),
    ProcessingFormat.webp => img.encodeWebP(
      image,
      lossless: request.mode == ProcessingMode.fidelity,
      quality: request.quality!,
      singleFrame: true,
    ),
  };
  encoded = MetadataPolicy.applyAndVerify(encoded, request.outputFormat, color);
  final outputDecoder = img.findDecoderForData(encoded);
  final outputInfo = outputDecoder?.startDecode(encoded);
  if (outputInfo == null ||
      outputInfo.width != image.width ||
      outputInfo.height != image.height ||
      (outputInfo is img.WebPInfo
          ? outputInfo.hasAnimation
          : outputInfo.numFrames > 1)) {
    _invalidImage();
  }
  final verified = outputDecoder!.decode(encoded);
  if (verified == null ||
      verified.numFrames != 1 ||
      (verified.exif.imageIfd.orientation ?? 1) != 1) {
    _invalidImage();
  }
  // Recheck every source after pixel work, before publishing a valid temp file.
  for (final input in request.inputs) {
    if (input.file.lengthSync() != input.version.byteCount ||
        sha256.convert(input.file.readAsBytesSync()).toString() !=
            input.version.sha256) {
      _inputChanged();
    }
  }
  if (FileSystemEntity.typeSync(outputPath, followLinks: false) !=
      FileSystemEntityType.file) {
    throw const ProcessingFailure(
      ProcessingFailureKind.storage,
      '临时结果路径已变化，未写入结果。',
    );
  }
  File(outputPath).writeAsBytesSync(encoded, flush: true);
  final bytesWritten = File(outputPath).readAsBytesSync();
  if (bytesWritten.length != encoded.length ||
      sha256.convert(bytesWritten) != sha256.convert(encoded)) {
    throw const ProcessingFailure(
      ProcessingFailureKind.storage,
      '临时结果写入后校验失败。',
    );
  }
  final warnings = <String>[];
  final animationRemoved = request.inputs.any(
    (input) => input.version.isAnimated,
  );
  if (animationRemoved) warnings.add('已按确认帧转为静态图，动画不再保留。');
  if (lossy) warnings.add('此输出采用有损编码，质量参数不表示保真百分比。');
  if (transparencyRemoved) warnings.add('已使用确认背景合成透明像素。');
  if (bytesWritten.length >=
      request.inputs.fold<int>(
        0,
        (sum, input) => sum + input.version.byteCount,
      )) {
    warnings.add('输出体积未减小。');
  }
  return {
    'version': versionSnapshot(
      ImageVersion(
        id: const Uuid().v4(),
        sha256: sha256.convert(bytesWritten).toString(),
        byteCount: bytesWritten.length,
        format: _identifyFormat(bytesWritten),
        width: image.width,
        height: image.height,
        frameCount: 1,
        orientation: 1,
      ),
    ),
    'lossy': lossy,
    'transparencyRemoved': transparencyRemoved,
    'animationRemoved': animationRemoved,
    'warnings': warnings,
  };
}

img.ColorRgba8 _argb(int value) => img.ColorRgba8(
  (value >> 16) & 255,
  (value >> 8) & 255,
  value & 255,
  value >> 24,
);

img.Image _stitch(List<img.Image> images, ProcessingPlan plan, int background) {
  final canvas = img.Image(
    width: plan.outputSize.width,
    height: plan.outputSize.height,
    numChannels: 4,
    format: images.any((image) => image.format == img.Format.uint16)
        ? img.Format.uint16
        : img.Format.uint8,
  );
  img.fill(canvas, color: _argb(background));
  for (var i = 0; i < images.length; i++) {
    img.compositeImage(
      canvas,
      images[i],
      dstX: plan.placements[i].x,
      dstY: plan.placements[i].y,
    );
  }
  return canvas;
}

String _identifyFormat(Uint8List bytes) =>
    switch (img.findDecoderForData(bytes)?.format) {
      img.ImageFormat.png => 'PNG',
      img.ImageFormat.jpg => 'JPEG',
      img.ImageFormat.webp => 'WebP',
      img.ImageFormat.gif => 'GIF',
      img.ImageFormat.bmp => 'BMP',
      _ => throw const ProcessingFailure(
        ProcessingFailureKind.unsupported,
        '图片内容不是支持的 PNG、JPEG、WebP、GIF 或 BMP。',
      ),
    };

Never _inputChanged() => throw const ProcessingFailure(
  ProcessingFailureKind.inputChanged,
  '输入内容与指定版本不一致，请重新取得该版本。',
);
Never _invalidImage() => throw const ProcessingFailure(
  ProcessingFailureKind.invalidImage,
  '图片内容或实际输出无效。',
);
