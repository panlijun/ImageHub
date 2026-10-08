import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show AppExitResponse;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/platform_resource.dart';
import '../../../platform/export_gateway.dart';
import '../../gallery/data/library_repository.dart';
import '../../gallery/domain/library_models.dart';
import '../../gallery/presentation/asset_widgets.dart';
import '../../gallery/presentation/gallery_providers.dart';
import '../application/file_exporter.dart';
import '../application/processing_coordinator.dart';
import '../domain/export_models.dart';
import '../domain/output_models.dart';
import '../domain/processing_models.dart';
import 'output_preview.dart';
import '../../upload/presentation/upload_exit.dart';
import '../../upload/presentation/upload_tasks_screen.dart';

final exportGatewayProvider = Provider<ExportGateway>(
  (ref) => const ExportGateway(),
);

/// One shared workbench. All byte writes are owned by application/data services.
class ProcessingWorkbench extends ConsumerStatefulWidget {
  const ProcessingWorkbench({super.key});

  @override
  ConsumerState<ProcessingWorkbench> createState() =>
      _ProcessingWorkbenchState();
}

class _ProcessingWorkbenchState extends ConsumerState<ProcessingWorkbench> {
  LibraryRepository? _repository;
  GalleryPage? _page;
  List<ProcessedOutput> _outputs = [];
  final List<String> _selected = [];
  final Map<String, TextEditingController> _frames = {};
  final _side = TextEditingController(text: '1600');
  final _quality = TextEditingController(text: '85');
  final _gap = TextEditingController(text: '0');
  final _background = TextEditingController(text: 'FFFFFFFF');
  final _x = TextEditingController(text: '0');
  final _y = TextEditingController(text: '0');
  final _width = TextEditingController(text: '1');
  final _height = TextEditingController(text: '1');
  ProcessingOperation _operation = ProcessingOperation.compress;
  ProcessingMode _mode = ProcessingMode.fidelity;
  ProcessingFormat _format = ProcessingFormat.png;
  StitchLayout _layout = StitchLayout.grid;
  OutputRetention _retention = OutputRetention.day;
  bool _staticConfirmed = false;
  bool _backgroundConfirmed = false;
  bool _orderConfirmed = false;
  bool _defaultsApplied = false;
  bool _loading = true;
  bool _busy = false;
  bool _allowPop = false;
  String? _error;
  String? _feedback;
  String _progress = '';
  CancellationToken? _token;
  Future<void>? _active;
  int _loadRevision = 0;
  Offset? _dragStart;
  AppLifecycleListener? _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onExitRequested: _exitRequested);
    ref.listenManual(libraryReplacementRevisionProvider, (_, _) {
      unawaited(_afterReplacement());
    });
    unawaited(_reload());
  }

  Future<void> _afterReplacement() async {
    final revision = ++_loadRevision;
    _token?.cancel();
    setState(() {
      _page = null;
      _outputs = [];
      _selected.clear();
      // Retain controller ownership until normal disposal. Replacing the
      // library must not dispose controllers still attached to EditableText.
      for (final controller in _frames.values) {
        controller.text = '0';
      }
      _staticConfirmed = _backgroundConfirmed = _orderConfirmed = false;
      _defaultsApplied = false;
      _loading = true;
      _error = null;
      _feedback = '资料库已替换，请重新选择原图并确认处理参数。';
    });
    await _active;
    if (mounted && revision == _loadRevision) await _reload();
  }

  @override
  void dispose() {
    _token?.cancel();
    _lifecycle?.dispose();
    for (final controller in [
      _side,
      _quality,
      _gap,
      _background,
      _x,
      _y,
      _width,
      _height,
      ..._frames.values,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _reload({bool more = false}) async {
    if (_busy || (more && _loading)) return;
    final revision = ++_loadRevision;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repository = (await ref.read(librarySessionProvider.future))
          .repository;
      final previous = _page;
      var page = await repository.listAssets(
        limit: 60,
        offset: more ? previous?.items.length ?? 0 : 0,
      );
      if (more && previous != null) {
        if (page.total != previous.total) {
          page = await repository.listAssets(limit: 60);
        } else {
          final ids = previous.items.map((asset) => asset.id).toSet();
          page = GalleryPage([
            ...previous.items,
            ...page.items.where((asset) => ids.add(asset.id)),
          ], page.total);
        }
      }
      final outputs = await repository.listOutputs();
      if (!mounted || revision != _loadRevision) return;
      setState(() {
        if (!_defaultsApplied) {
          final defaults = repository.currentDeviceSettings;
          _quality.text = defaults.quality.toString();
          _side.text = defaults.longestSide.toString();
          _mode = defaults.processingMode;
          _retention = defaults.defaultOutputRetention;
          _defaultsApplied = true;
        }
        _repository = repository;
        _page = page;
        _outputs = outputs;
      });
    } catch (_) {
      if (mounted && revision == _loadRevision) {
        setState(() => _error = '加载失败：无法安全读取资料库。上次有效列表仍保留，请重试。');
      }
    } finally {
      if (mounted && revision == _loadRevision) {
        setState(() => _loading = false);
      }
    }
  }

  Future<bool> _confirmStop() async {
    if (!_busy) return true;
    final stop = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('操作尚未结束'),
        content: const Text('停止并等待实际读写结束后离开？已确认的结果和永久图片会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('继续操作'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('停止并离开'),
          ),
        ],
      ),
    );
    if (stop != true) return false;
    _token?.cancel();
    if (mounted) setState(() => _progress = '正在停止，等待实际读写结束…');
    await _active;
    return true;
  }

  Future<AppExitResponse> _exitRequested() async {
    if (!await _confirmStop()) return AppExitResponse.cancel;
    if (!mounted) return AppExitResponse.cancel;
    final session = ref.read(librarySessionProvider).asData?.value;
    if (session != null && !await requestLibraryExit(context, session)) {
      return AppExitResponse.cancel;
    }
    return AppExitResponse.exit;
  }

  Future<void> _uploadOutput(ProcessedOutput output) async {
    if (_busy || !output.usable) return;
    _lifecycle?.dispose();
    _lifecycle = null;
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => UploadTasksScreen(initialOutputIds: [output.id]),
        ),
      );
    } finally {
      if (mounted) {
        _lifecycle = AppLifecycleListener(onExitRequested: _exitRequested);
      }
    }
  }

  Future<void> _leave() async {
    if (!await _confirmStop() || !mounted) return;
    setState(() => _allowPop = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.of(context).pop();
  }

  // _active includes the finally path, so cancellation never means IO is done.
  void _run(Future<void> Function(CancellationToken) action) {
    if (_busy) return;
    final token = CancellationToken();
    _token = token;
    setState(() {
      _busy = true;
      _feedback = null;
      _error = null;
    });
    _active = () async {
      try {
        await action(token);
      } catch (error) {
        if (mounted) {
          setState(
            () => _error = switch (error) {
              ProcessingFailure() => error.message,
              ResourceFailure() => error.message,
              _ => '操作未确认，请检查结果记录后重试；永久图片保留。',
            },
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _busy = false;
            _progress = '';
          });
        }
        _token = null;
      }
    }();
    unawaited(_active!);
  }

  int _integer(
    TextEditingController controller,
    String name,
    int min,
    int max,
  ) {
    final value = int.tryParse(controller.text.trim());
    if (value == null || value < min || value > max) {
      throw ProcessingFailure(
        ProcessingFailureKind.invalidParameters,
        '$name 必须是 $min–$max 的整数。',
      );
    }
    return value;
  }

  _Draft _snapshot() {
    final ids = List<String>.unmodifiable(_selected);
    if (ids.isEmpty) {
      throw const ProcessingFailure(
        ProcessingFailureKind.invalidParameters,
        '请先选择图片。',
      );
    }
    if (_operation == ProcessingOperation.crop && ids.length != 1) {
      throw const ProcessingFailure(
        ProcessingFailureKind.invalidParameters,
        '裁剪必须只选择一张图片。',
      );
    }
    if (_operation == ProcessingOperation.stitch &&
        (ids.length < 2 || !_orderConfirmed)) {
      throw const ProcessingFailure(
        ProcessingFailureKind.invalidParameters,
        '拼接至少两张图片，请确认下方顺序。',
      );
    }
    final side =
        _mode == ProcessingMode.sizeFirst &&
            _operation == ProcessingOperation.compress
        ? _integer(_side, '最长边', 1, 16384)
        : 1600;
    final quality =
        _format == ProcessingFormat.png || _mode == ProcessingMode.fidelity
        ? null
        : _integer(_quality, '质量', 1, 100);
    final background = int.tryParse(_background.text.trim(), radix: 16);
    if (!RegExp(r'^[a-fA-F0-9]{8}$').hasMatch(_background.text.trim()) ||
        background == null) {
      throw const ProcessingFailure(
        ProcessingFailureKind.invalidParameters,
        '背景颜色必须是 8 位 ARGB 十六进制，例如 FFFFFFFF。',
      );
    }
    final assets = {for (final asset in _page!.items) asset.id: asset};
    final versions = <String, ImageVersion>{};
    final frames = <String, int>{};
    for (final id in ids) {
      final asset = assets[id];
      if (asset == null) {
        throw const ProcessingFailure(
          ProcessingFailureKind.inputChanged,
          '选中图片已不在当前列表，请重新选择。',
        );
      }
      versions[id] = asset.version;
      if (asset.version.isAnimated) {
        if (!_staticConfirmed) {
          throw const ProcessingFailure(
            ProcessingFailureKind.confirmationRequired,
            '动画处理需要明确确认转为静态图并选择帧。',
          );
        }
        frames[id] = _integer(
          _frames[id]!,
          '动画帧',
          0,
          asset.version.frameCount - 1,
        );
      }
    }
    PixelCrop? crop;
    if (_operation == ProcessingOperation.crop) {
      final version = versions.values.single;
      crop = PixelCrop(
        _integer(_x, 'X', 0, version.width - 1),
        _integer(_y, 'Y', 0, version.height - 1),
        _integer(_width, '宽', 1, version.width),
        _integer(_height, '高', 1, version.height),
      );
      if (crop.x + crop.width > version.width ||
          crop.y + crop.height > version.height) {
        throw const ProcessingFailure(
          ProcessingFailureKind.invalidParameters,
          '裁剪区域越界，请核对整数像素坐标。',
        );
      }
    }
    return _Draft(
      ids,
      Map.unmodifiable(versions),
      Map.unmodifiable(frames),
      _operation,
      _mode,
      _format,
      side,
      quality,
      crop,
      _layout,
      _operation == ProcessingOperation.stitch
          ? _integer(_gap, '间距', 0, 1024)
          : 0,
      background,
      _backgroundConfirmed,
      _staticConfirmed,
      _retention,
    );
  }

  void _process() {
    _Draft draft;
    try {
      draft = _snapshot();
    } catch (error) {
      setState(() => _error = '$error');
      return;
    }
    final repository = _repository!;
    _run((token) async {
      final groups = draft.operation == ProcessingOperation.compress
          ? draft.ids.map((id) => [id]).toList()
          : [draft.ids];
      final summary = <String>[];
      for (var i = 0; i < groups.length; i++) {
        if (token.isCancelled) {
          summary.add('${groups.length - i} 项未开始（已取消）');
          break;
        }
        final group = groups[i];
        if (mounted) {
          setState(() => _progress = '处理 ${i + 1}/${groups.length}，参数已冻结');
        }
        try {
          final output = await ProcessingCoordinator(repository).process(
            group,
            draft.request,
            displayName:
                '${draft.operation == ProcessingOperation.stitch ? '拼接' : _assetName(group.single)}_${draft.operation.name}.${draft.format.name}',
            retention: draft.retention,
            cancellation: token,
          );
          summary.add('${output.displayName}：${_stateLabel(output)}');
        } catch (error) {
          summary.add('${group.map(_assetName).join('、')}：$error');
        }
        final outputs = await repository.listOutputs();
        if (mounted) setState(() => _outputs = outputs);
      }
      if (mounted) setState(() => _feedback = summary.join('\n'));
    });
  }

  String _assetName(String id) =>
      _page?.items.where((asset) => asset.id == id).firstOrNull?.displayName ??
      id;

  void _save(ProcessedOutput output) {
    final repository = _repository!;
    _run((token) async {
      final result = await repository.saveOutput(
        output.id,
        cancellation: token,
      );
      final outputs = await repository.listOutputs();
      final page = await repository.listAssets(limit: 60);
      if (mounted) {
        setState(() {
          _outputs = outputs;
          _page = page;
          _feedback = result.persisted
              ? '已永久保存：${result.asset!.displayName}'
              : '未永久保存：${result.failure?.message ?? result.status.name}';
        });
      }
      if (mounted && result.persisted) {
        await ref.read(galleryProvider.notifier).reload();
      }
    });
  }

  void _export(List<String> ids) {
    final repository = _repository!;
    _run((token) async {
      final directory = await ref.read(exportGatewayProvider).pickDirectory();
      if (directory == null) {
        if (mounted) setState(() => _feedback = '已取消目录选择。');
        return;
      }
      final results = <ExportItemResult>[];
      // Each result owns a lease until its real export IO has completed.
      for (final id in List<String>.unmodifiable(ids)) {
        if (token.isCancelled) {
          results.add(
            ExportItemResult(
              id: id,
              status: ExportStatus.cancelled,
              reason: '未开始，已取消',
            ),
          );
          continue;
        }
        OutputFileLease? lease;
        try {
          lease = await repository.acquireOutputLease(id);
          final output = lease.output;
          results.addAll(
            await const FileExporter().exportToDirectory(
              [
                ExportInput(
                  id: id,
                  source: output.file!,
                  displayName: output.displayName,
                  expectedSha256: output.version!.sha256,
                  expectedByteCount: output.version!.byteCount,
                ),
              ],
              directory,
              cancellation: token,
            ),
          );
        } catch (error) {
          results.add(
            ExportItemResult(
              id: id,
              status: ExportStatus.failed,
              reason: '$error',
            ),
          );
        } finally {
          await lease?.release();
        }
      }
      if (mounted) {
        setState(
          () => _feedback = results
              .map(
                (result) =>
                    '${_outputs.where((output) => output.id == result.id).firstOrNull?.displayName ?? result.id}：${switch (result.status) {
                      ExportStatus.saved => '已导出 ${result.fileName}',
                      ExportStatus.failed => '失败 ${result.reason}',
                      ExportStatus.cancelled => '已取消 ${result.reason ?? ''}',
                    }}',
              )
              .join('\n'),
        );
      }
    });
  }

  void _cleanup() {
    final repository = _repository!;
    _run((token) async {
      final result = await repository.cleanupOutputs();
      final outputs = await repository.listOutputs();
      if (mounted) {
        setState(() {
          _outputs = outputs;
          _feedback =
              '到期清理：移除 ${result.removed} 项，保护 ${result.protected} 项，失败 ${result.failedIds.length} 项。';
        });
      }
    });
  }

  void _toggle(ImageAsset asset) {
    setState(() {
      if (_selected.contains(asset.id)) {
        _selected.remove(asset.id);
      } else {
        _selected.add(asset.id);
        _frames.putIfAbsent(asset.id, () => TextEditingController(text: '0'));
      }
      _orderConfirmed = false;
      if (_selected.length == 1) _resetCrop();
    });
  }

  void _resetCrop() {
    final asset = _page?.items
        .where((asset) => _selected.contains(asset.id))
        .firstOrNull;
    if (asset == null) return;
    _x.text = '0';
    _y.text = '0';
    _width.text = '${asset.version.width}';
    _height.text = '${asset.version.height}';
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _allowPop || !_busy,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) unawaited(_leave());
    },
    child: Scaffold(
      appBar: AppBar(
        title: const Text('图片处理工作台'),
        leading: IconButton(
          tooltip: '返回图库',
          onPressed: _leave,
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: EdgeInsets.all(constraints.maxWidth < 600 ? 12 : 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '独立处理 · 新结果不覆盖原图',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text('保真优先默认 PNG、不缩小、不丢透明；不承诺文件变小。动画必须明确选帧转换。'),
              const SizedBox(height: 16),
              if (_error != null) _notice(_error!, error: true),
              if (_feedback != null) _notice(_feedback!),
              if (_busy) ...[
                const LinearProgressIndicator(),
                _notice(_progress.isEmpty ? '正在读写，请等待…' : _progress),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () {
                      _token?.cancel();
                      setState(() => _progress = '正在停止，等待实际读写结束…');
                    },
                    child: const Text('停止后续操作'),
                  ),
                ),
              ],
              if (_loading) const LinearProgressIndicator(),
              const SizedBox(height: 12),
              if (constraints.maxWidth >= 1000)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _inputs()),
                    const SizedBox(width: 20),
                    Expanded(child: _settings()),
                  ],
                )
              else ...[
                _inputs(),
                const SizedBox(height: 16),
                _settings(),
              ],
              const SizedBox(height: 24),
              _results(),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _notice(String message, {bool error = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(
      message,
      style: TextStyle(
        color: error ? Theme.of(context).colorScheme.error : null,
      ),
    ),
  );

  Widget _panel(String title, List<Widget> children) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    ),
  );

  Widget _inputs() => _panel('1 · 选择原图（${_selected.length} 项）', [
    Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: _busy || _loading ? null : _reload,
        icon: const Icon(Icons.refresh),
        label: const Text('刷新原图与结果'),
      ),
    ),
    if (_page == null) Text(_loading ? '正在打开本机图库…' : '图库加载失败，请重试刷新。'),
    if (_page?.items.isEmpty ?? false) const Text('图库还是空的，请返回图库导入图片。'),
    for (final asset in _page?.items ?? <ImageAsset>[])
      Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: CheckboxListTile(
          key: Key('processing-asset-${asset.id}'),
          contentPadding: EdgeInsets.zero,
          value: _selected.contains(asset.id),
          onChanged: _busy ? null : (_) => _toggle(asset),
          title: Text(
            asset.displayName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${asset.version.format} · ${asset.version.width}×${asset.version.height} · ${formatBytes(asset.version.byteCount)}${asset.version.isAnimated ? ' · ${asset.version.frameCount} 帧' : ''}',
          ),
          secondary: SizedBox(
            width: 48,
            height: 48,
            child: AssetPreviewImage(asset: asset, compact: true),
          ),
        ),
      ),
    if (_page != null && _page!.items.length < _page!.total)
      TextButton(
        onPressed: _busy || _loading ? null : () => _reload(more: true),
        child: Text('加载更多（${_page!.items.length}/${_page!.total}）'),
      ),
  ]);

  Widget _settings() => _panel('2 · 确认参数', [
    _dropdown<ProcessingOperation>(
      '操作',
      _operation,
      ProcessingOperation.values,
      (value) => setState(() {
        _operation = value;
        _resetCrop();
      }),
      (value) => switch (value) {
        ProcessingOperation.compress => '压缩',
        ProcessingOperation.crop => '裁剪（单张）',
        ProcessingOperation.stitch => '拼接（一组）',
      },
    ),
    _dropdown<ProcessingMode>(
      '策略',
      _mode,
      ProcessingMode.values,
      (value) => setState(() => _mode = value),
      (value) => value == ProcessingMode.fidelity ? '保真优先' : '体积优先',
    ),
    _dropdown<ProcessingFormat>(
      '输出格式',
      _format,
      ProcessingFormat.values,
      (value) => setState(() => _format = value),
      (value) => value.name.toUpperCase(),
    ),
    if (_mode == ProcessingMode.sizeFirst &&
        _operation == ProcessingOperation.compress)
      _field(_side, '最长边（1–16384，不放大小图）', 'processing-longest-side'),
    if (_format != ProcessingFormat.png && _mode == ProcessingMode.sizeFirst)
      _field(_quality, '编码质量（1–100）', 'processing-quality'),
    if (_format == ProcessingFormat.png) const Text('PNG 没有有损质量参数。'),
    if (_operation == ProcessingOperation.crop) _cropEditor(),
    if (_operation == ProcessingOperation.stitch) ...[
      _dropdown<StitchLayout>(
        '布局',
        _layout,
        StitchLayout.values,
        (value) => setState(() => _layout = value),
        (value) => switch (value) {
          StitchLayout.horizontal => '横向',
          StitchLayout.vertical => '纵向',
          StitchLayout.grid => '近正方形网格',
        },
      ),
      _field(_gap, '间距（0–1024 像素）', 'processing-gap'),
      const Text('缺省不缩放输入，按下列顺序摆放：'),
      for (var index = 0; index < _selected.length; index++)
        Row(
          children: [
            Expanded(
              child: Text(
                '${index + 1}. ${_assetName(_selected[index])}',
                maxLines: 2,
              ),
            ),
            IconButton(
              tooltip: '上移',
              onPressed: _busy || index == 0 ? null : () => _move(index, -1),
              icon: const Icon(Icons.arrow_upward),
            ),
            IconButton(
              tooltip: '下移',
              onPressed: _busy || index == _selected.length - 1
                  ? null
                  : () => _move(index, 1),
              icon: const Icon(Icons.arrow_downward),
            ),
          ],
        ),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('确认以上拼接顺序'),
        value: _orderConfirmed,
        onChanged: _busy
            ? null
            : (value) => setState(() => _orderConfirmed = value!),
      ),
    ],
    _field(
      _background,
      '背景 ARGB（FFFFFFFF 白 / 00000000 透明）',
      'processing-background',
    ),
    CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('确认需要丢弃透明度时使用此背景颜色'),
      value: _backgroundConfirmed,
      onChanged: _busy
          ? null
          : (value) => setState(() => _backgroundConfirmed = value!),
    ),
    for (final asset
        in _page?.items.where(
              (asset) =>
                  _selected.contains(asset.id) && asset.version.isAnimated,
            ) ??
            <ImageAsset>[])
      _field(
        _frames[asset.id]!,
        '${asset.displayName} · 选帧（0–${asset.version.frameCount - 1}）',
        'processing-frame-${asset.id}',
      ),
    if (_page?.items.any(
          (asset) => _selected.contains(asset.id) && asset.version.isAnimated,
        ) ??
        false)
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('明确将所选动画帧转换为静态图片（丢弃动画）'),
        value: _staticConfirmed,
        onChanged: _busy
            ? null
            : (value) => setState(() => _staticConfirmed = value!),
      ),
    _dropdown<OutputRetention>(
      '临时保留',
      _retention,
      OutputRetention.values,
      (value) => setState(() => _retention = value),
      (value) => switch (value) {
        OutputRetention.hour => '1 小时',
        OutputRetention.day => '24 小时（默认）',
        OutputRetention.week => '7 天',
      },
    ),
    Text(
      '当前处理内存上限：${_repository == null ? '待加载' : formatBytes(_repository!.processingBudgetBytes)}。超出时请降低尺寸或减少输入。',
    ),
    const SizedBox(height: 12),
    FilledButton.icon(
      key: const Key('processing-start'),
      onPressed: _busy || _loading || _repository == null ? null : _process,
      icon: const Icon(Icons.play_arrow),
      label: const Text('确认参数并开始处理'),
    ),
  ]);

  void _move(int index, int delta) => setState(() {
    final id = _selected.removeAt(index);
    _selected.insert(index + delta, id);
    _orderConfirmed = false;
  });

  Widget _field(TextEditingController controller, String label, String key) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: TextField(
          key: Key(key),
          controller: controller,
          enabled: !_busy,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
          ),
          onChanged: (_) {
            if ([
              _x,
              _y,
              _width,
              _height,
              ..._frames.values,
            ].contains(controller)) {
              setState(() {});
            }
          },
        ),
      );

  Widget _dropdown<T>(
    String label,
    T value,
    List<T> values,
    ValueChanged<T> onChanged,
    String Function(T) name,
  ) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: DropdownButtonFormField<T>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: values
          .map(
            (value) => DropdownMenuItem(value: value, child: Text(name(value))),
          )
          .toList(),
      onChanged: _busy
          ? null
          : (value) {
              if (value != null) onChanged(value);
            },
    ),
  );

  Widget _cropEditor() {
    final selected =
        _page?.items.where((asset) => _selected.contains(asset.id)).toList() ??
        [];
    if (selected.length != 1) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: Text('裁剪请只选择一张图片。'),
      );
    }
    final asset = selected.single;
    final frame = asset.version.isAnimated
        ? int.tryParse(_frames[asset.id]!.text)
        : null;
    if (asset.version.isAnimated &&
        (frame == null || frame < 0 || frame >= asset.version.frameCount)) {
      return const Text('请填写范围内的动画帧，预览与裁剪将使用同一选定帧。');
    }
    final size = Size(
      asset.version.width.toDouble(),
      asset.version.height.toDouble(),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('在方向正确的图片上拖动框选，或输入整数像素区域。'),
        LayoutBuilder(
          builder: (context, constraints) {
            final height = math.min(
              340.0,
              constraints.maxWidth / size.aspectRatio,
            );
            final width = height * size.aspectRatio;
            return Center(
              child: SizedBox(
                width: width,
                height: height,
                child: GestureDetector(
                  key: const Key('processing-crop-preview'),
                  onPanStart: _busy
                      ? null
                      : (details) {
                          _dragStart = details.localPosition;
                        },
                  onPanUpdate: _busy
                      ? null
                      : (details) {
                          if (_dragStart == null) return;
                          final end = details.localPosition;
                          final start = _dragStart!;
                          final left = math
                              .min(start.dx, end.dx)
                              .clamp(0.0, width);
                          final top = math
                              .min(start.dy, end.dy)
                              .clamp(0.0, height);
                          final right = math
                              .max(start.dx, end.dx)
                              .clamp(0.0, width);
                          final bottom = math
                              .max(start.dy, end.dy)
                              .clamp(0.0, height);
                          final x = (left / width * size.width).floor();
                          final y = (top / height * size.height).floor();
                          final w = (right / width * size.width).ceil() - x;
                          final h = (bottom / height * size.height).ceil() - y;
                          if (w < 1 ||
                              h < 1 ||
                              x >= size.width ||
                              y >= size.height) {
                            return;
                          }
                          setState(() {
                            _x.text = '$x';
                            _y.text = '$y';
                            _width.text = '$w';
                            _height.text = '$h';
                          });
                        },
                  onPanEnd: (_) => _dragStart = null,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      AssetPreviewImage(asset: asset, selectedFrame: frame),
                      IgnorePointer(
                        child: CustomPaint(
                          painter: _CropPainter(
                            _numericRect(width, height, size),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        for (final field in [
          (_x, 'X', 'x'),
          (_y, 'Y', 'y'),
          (_width, '宽', 'width'),
          (_height, '高', 'height'),
        ])
          _field(field.$1, '${field.$2}（整数像素）', 'processing-crop-${field.$3}'),
        TextButton(
          onPressed: _busy ? null : () => setState(_resetCrop),
          child: const Text('重置为全图'),
        ),
      ],
    );
  }

  Rect? _numericRect(double width, double height, Size size) {
    final x = int.tryParse(_x.text),
        y = int.tryParse(_y.text),
        w = int.tryParse(_width.text),
        h = int.tryParse(_height.text);
    if (x == null ||
        y == null ||
        w == null ||
        h == null ||
        x < 0 ||
        y < 0 ||
        w < 1 ||
        h < 1 ||
        x + w > size.width ||
        y + h > size.height) {
      return null;
    }
    return Rect.fromLTWH(
      x / size.width * width,
      y / size.height * height,
      w / size.width * width,
      h / size.height * height,
    );
  }

  String _stateLabel(ProcessedOutput output) => switch (output.state) {
    OutputState.writing => '正在写入（不可使用）',
    OutputState.prepared => '待恢复提交（不可使用）',
    OutputState.ready =>
      output.usable ? '已就绪' : '${copyLabel(output.availability)}（不可使用）',
    OutputState.failed => '失败',
    OutputState.cancelled => '已取消',
    OutputState.deleting => '待重试清理（不可使用）',
  };

  Widget _results() => _panel('3 · 处理结果（${_outputs.length} 项）', [
    Wrap(
      spacing: 8,
      children: [
        TextButton.icon(
          onPressed: _busy || _loading ? null : _reload,
          icon: const Icon(Icons.refresh),
          label: const Text('重载结果'),
        ),
        TextButton(
          onPressed: _busy || _repository == null ? null : _cleanup,
          child: const Text('清理到期且无保护的结果'),
        ),
        TextButton(
          onPressed:
              _busy ||
                  !ref.watch(exportGatewayProvider).supportsDirectoryExport ||
                  !_outputs.any((output) => output.usable)
              ? null
              : () => _export(
                  _outputs
                      .where((output) => output.usable)
                      .map((output) => output.id)
                      .toList(),
                ),
          child: const Text('导出全部可用结果'),
        ),
      ],
    ),
    if (!ref.watch(exportGatewayProvider).supportsDirectoryExport)
      const Text('此平台的原生文件导出尚未接入，导出已禁用。'),
    if (_outputs.isEmpty) const Text('还没有处理输出。临时输出只有完成文件校验和提交后才可使用。'),
    for (final output in _outputs)
      Card(
        key: Key('processing-output-${output.id}'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                output.displayName,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(_stateLabel(output)),
              if (output.failureMessage != null) Text(output.failureMessage!),
              Text(
                '来源：${output.request.inputs.map((input) => '${_page?.items.where((asset) => asset.id == input.assetId).firstOrNull?.displayName ?? '已移除来源记录'} · ${input.version.format} ${input.version.width}×${input.version.height} · ${formatBytes(input.version.byteCount)}').join('；')}',
              ),
              if (output.version != null)
                Text(
                  '结果：${output.version!.format} ${output.version!.width}×${output.version!.height} · ${formatBytes(output.version!.byteCount)}',
                ),
              if (output.byteSavings != null)
                Text(
                  output.byteSavings! > 0
                      ? '实际减少 ${formatBytes(output.byteSavings!)}'
                      : output.byteSavings! == 0
                      ? '体积没有减少'
                      : '体积增加 ${formatBytes(-output.byteSavings!)}，没有压缩收益；原图仍保留。',
                ),
              for (final warning in output.warnings) Text(warning),
              Text(
                '创建 ${output.createdAt.toLocal()} · 到期 ${output.expiresAt.toLocal()}',
              ),
              if (output.savedVersionId != null)
                const Text('已永久保存；永久副本不受临时期限制。'),
              if (output.usable)
                SizedBox(
                  height: 180,
                  child: OutputPreview(outputId: output.id),
                ),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton(
                    key: Key('processing-save-${output.id}'),
                    onPressed: _busy || !output.usable
                        ? null
                        : () => _save(output),
                    child: const Text('永久保存到图库'),
                  ),
                  TextButton(
                    onPressed:
                        _busy ||
                            !output.usable ||
                            !ref
                                .watch(exportGatewayProvider)
                                .supportsDirectoryExport
                        ? null
                        : () => _export([output.id]),
                    child: const Text('导出此结果'),
                  ),
                  TextButton.icon(
                    onPressed: _busy || !output.usable
                        ? null
                        : () => _uploadOutput(output),
                    icon: const Icon(Icons.cloud_upload_outlined),
                    label: const Text('选择目标并入队'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
  ]);
}

class _Draft {
  const _Draft(
    this.ids,
    this.versions,
    this.frames,
    this.operation,
    this.mode,
    this.format,
    this.side,
    this.quality,
    this.crop,
    this.layout,
    this.gap,
    this.background,
    this.backgroundConfirmed,
    this.staticConfirmed,
    this.retention,
  );
  final List<String> ids;
  final Map<String, ImageVersion> versions;
  final Map<String, int> frames;
  final ProcessingOperation operation;
  final ProcessingMode mode;
  final ProcessingFormat format;
  final int side;
  final int? quality;
  final PixelCrop? crop;
  final StitchLayout layout;
  final int gap;
  final int background;
  final bool backgroundConfirmed;
  final bool staticConfirmed;
  final OutputRetention retention;

  ProcessingRequest request(List<ProcessingInput> inputs) {
    for (final input in inputs) {
      if (input.version != versions[input.assetId]) {
        throw const ProcessingFailure(
          ProcessingFailureKind.inputChanged,
          '来源版本已改变，请重新创建处理任务。',
        );
      }
    }
    return ProcessingRequest(
      operation: operation,
      inputs: inputs.map(
        (input) => ProcessingInput(
          file: input.file,
          assetId: input.assetId,
          version: input.version,
          selectedFrame: frames[input.assetId],
        ),
      ),
      mode: mode,
      outputFormat: format,
      longestSide: side,
      quality: quality,
      crop: crop,
      layout: layout,
      gap: gap,
      backgroundArgb: background,
      backgroundConfirmed: backgroundConfirmed,
      explicitStaticConversion: staticConfirmed,
    );
  }
}

class _CropPainter extends CustomPainter {
  const _CropPainter(this.rect);
  final Rect? rect;
  @override
  void paint(Canvas canvas, Size size) {
    if (rect == null) return;
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        Path()..addRect(rect!),
      ),
      Paint()..color = const Color(0x77000000),
    );
    canvas.drawRect(
      rect!,
      Paint()
        ..color = const Color(0xff0b7967)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_CropPainter oldDelegate) => oldDelegate.rect != rect;
}
