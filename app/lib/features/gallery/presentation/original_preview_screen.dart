import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../application/original_preview_reader.dart';
import '../domain/library_models.dart';
import 'gallery_providers.dart';
import 'original_preview_controller.dart';
import '../../upload/presentation/upload_exit.dart';

/// One common viewer for desktop A and mobile M1; originals remain untouched.
class OriginalPreviewScreen extends ConsumerStatefulWidget {
  const OriginalPreviewScreen({super.key, required this.asset});
  final ImageAsset asset;
  @override
  ConsumerState<OriginalPreviewScreen> createState() =>
      _OriginalPreviewScreenState();
}

class _OriginalPreviewScreenState extends ConsumerState<OriginalPreviewScreen> {
  OriginalPreviewController? _controller;
  AppLifecycleListener? _lifecycle;
  LibrarySession? _session;
  ui.Image? _displayImage, _sourceImage;
  final _transform = TransformationController();
  bool _leaving = false;
  Future<void>? _leaveWork;

  @override
  void initState() {
    super.initState();
    ref.listenManual(libraryReplacementRevisionProvider, (_, _) {
      unawaited(_leave());
    });
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) =>
          _controller?.setForeground(state == AppLifecycleState.resumed),
      onExitRequested: () async {
        if (ModalRoute.of(context)?.isCurrent != true) {
          return ui.AppExitResponse.exit;
        }
        try {
          final session = _session;
          if (session == null) {
            await (_leaveWork ??= _drain());
            await _session?.close();
            return ui.AppExitResponse.exit;
          }
          final closed = await requestLibraryExit(
            context,
            session,
            beforeClose: () => _leaveWork ??= _drain(),
          );
          if (!closed && mounted && _controller?.closed == true) {
            // The close failure dialog has returned. This viewer has already
            // drained; return to the library rather than leave disabled controls.
            setState(() {});
            await WidgetsBinding.instance.endOfFrame;
            if (mounted) Navigator.of(context).pop();
          }
          return closed ? ui.AppExitResponse.exit : ui.AppExitResponse.cancel;
        } catch (_) {
          return ui.AppExitResponse.cancel;
        }
      },
    );
    _start();
  }

  void _start() {
    final controller = OriginalPreviewController(
      loader: (cancellation) async {
        final session = await ref.read(librarySessionProvider.future);
        _session = session;
        return OriginalPreviewReader(session.repository)
            .read(widget.asset, cancellation: cancellation);
      },
    );
    _controller = controller;
    controller.setForeground(
      WidgetsBinding.instance.lifecycleState == null ||
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
    );
    controller.addListener(_changed);
    unawaited(controller.start());
  }

  void _changed() {
    if (!mounted || _leaving) return;
    final source = _controller?.image;
    if (!identical(source, _sourceImage)) {
      final old = _displayImage;
      _displayImage = source?.clone();
      _sourceImage = source;
      // RawImage may still own its old render handle until this frame builds.
      WidgetsBinding.instance.addPostFrameCallback((_) => old?.dispose());
    }
    setState(() {});
  }

  Future<void> _drain() async {
    _leaving = true;
    _controller?.pause();
    final old = _displayImage;
    _displayImage = null;
    _sourceImage = null;
    if (mounted) {
      setState(() {});
      await WidgetsBinding.instance.endOfFrame;
    }
    old?.dispose();
    await _controller?.close();
    if (mounted) {
      setState(() {});
      // Update PopScope only after actual native decoding has drained.
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  Future<void> _leave() async {
    if (_leaveWork != null) return;
    await (_leaveWork = _drain());
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _retry() async {
    if (_leaving) return;
    final old = _controller!;
    await _drain();
    old.removeListener(_changed);
    old.dispose();
    if (!mounted) return;
    _leaving = false;
    _transform.value = Matrix4.identity();
    _start();
    setState(() {});
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    _controller?.removeListener(_changed);
    _displayImage?.dispose();
    _displayImage = null;
    _controller?.dispose();
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller!;
    final image = _displayImage;
    final version = widget.asset.version;
    return PopScope(
      canPop: _leaving && controller.closed,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !_leaving) unawaited(_leave());
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            key: const Key('original-preview-back'),
            tooltip: '关闭预览',
            onPressed: _leaving ? null : _leave,
            icon: const Icon(Icons.arrow_back),
          ),
          title: Text(
            widget.asset.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            IconButton(
              tooltip: '重置缩放',
              onPressed: image == null || _leaving
                  ? null
                  : () => _transform.value = Matrix4.identity(),
              icon: const Icon(Icons.fit_screen),
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: _leaving
                  ? const Center(child: Text('正在结束预览…'))
                  : controller.error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              controller.error!,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            TextButton.icon(
                              onPressed: _retry,
                              icon: const Icon(Icons.refresh),
                              label: const Text('重试预览'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : image == null
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 12),
                          Text('正在校验并读取永久副本…'),
                        ],
                      ),
                    )
                  : Semantics(
                      label: '${widget.asset.displayName}，本机永久副本预览',
                      image: true,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return InteractiveViewer(
                            transformationController: _transform,
                            minScale: 1,
                            maxScale: 8,
                            child: SizedBox(
                              width: constraints.maxWidth,
                              height: constraints.maxHeight,
                              child: RawImage(
                                image: image,
                                fit: BoxFit.contain,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                child: Column(
                  children: [
                    if (controller.animated)
                      Wrap(
                        spacing: 12,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          TextButton.icon(
                            key: const Key('original-preview-play-pause'),
                            onPressed: _leaving || controller.error != null
                                ? null
                                : () => controller.playing
                                      ? controller.pause()
                                      : controller.play(),
                            icon: Icon(
                              controller.playing
                                  ? Icons.pause
                                  : Icons.play_arrow,
                            ),
                            label: Text(controller.playing ? '暂停动画' : '播放动画'),
                          ),
                          Text(
                            '第 ${controller.frameIndex + 1} / ${controller.frameCount} 帧',
                          ),
                        ],
                      ),
                    Text(
                      '${version.format} · ${version.width} × ${version.height}',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '从永久副本预览，可缩放查看；显示最长边最多 2048 像素，原字节不变。',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
