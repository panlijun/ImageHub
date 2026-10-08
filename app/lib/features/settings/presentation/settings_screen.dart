import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/network_state.dart';
import '../../accounts/domain/account_models.dart';
import '../../backup/presentation/backup_screen.dart';
import '../../diagnostics/presentation/diagnostics_screen.dart';
import '../../gallery/data/library_repository.dart';
import '../../gallery/presentation/gallery_providers.dart';
import '../../processing/domain/processing_models.dart';
import '../../processing/domain/output_models.dart';
import '../../storage/presentation/storage_screen.dart';
import '../../upload/presentation/upload_exit.dart';
import '../domain/device_settings.dart';

/// The same persisted device policy editor is used by desktop and M1.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({
    super.key,
    this.embedded = false,
    this.active = true,
    this.onBusyChanged,
  });
  final bool embedded, active;
  final ValueChanged<bool>? onBusyChanged;

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _upload = TextEditingController();
  final _processing = TextEditingController();
  final _quality = TextEditingController();
  final _longestSide = TextEditingController();
  final _cacheLimit = TextEditingController();
  final _selected = <String>{};
  ProcessingMode _mode = ProcessingMode.fidelity;
  OutputRetention _retention = OutputRetention.day;
  NetworkUploadPolicy _networkPolicy = NetworkUploadPolicy.wifiAndEthernet;
  LibrarySession? _session;
  SettingsSnapshot? _snapshot;
  StreamSubscription<void>? _settingsChanges;
  StreamSubscription<String>? _accountChanges;
  StreamSubscription<void>? _processingBudgetChanges;
  AppLifecycleListener? _lifecycle;
  Future<void>? _saveOperation;
  int _revision = 0;
  bool _loading = true, _busy = false, _stale = false;
  String? _error, _feedback;

  bool get _editable => !_loading && !_busy && _snapshot != null && !_stale;
  bool get _canSave => _editable && _error == null;
  bool get _pendingDefault =>
      _snapshot?.targets.any(
        (target) =>
            target.pendingOperation &&
            _snapshot!.defaultTargetIds.contains(target.id),
      ) ??
      false;

  @override
  void initState() {
    super.initState();
    _updateLifecycle();
    ref.listenManual(libraryReplacementRevisionProvider, (_, _) {
      _revision++;
      _upload.clear();
      _processing.clear();
      _quality.clear();
      _longestSide.clear();
      _cacheLimit.clear();
      setState(() {
        _snapshot = null;
        _selected.clear();
        _mode = ProcessingMode.fidelity;
        _retention = OutputRetention.day;
        _networkPolicy = NetworkUploadPolicy.wifiAndEthernet;
        _feedback = null;
        _error = null;
        _stale = false;
      });
      unawaited(_reload());
    });
    unawaited(_reload());
  }

  @override
  void didUpdateWidget(SettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) _updateLifecycle();
  }

  void _updateLifecycle() {
    _lifecycle?.dispose();
    _lifecycle = widget.active
        ? AppLifecycleListener(onExitRequested: _exitRequested)
        : null;
  }

  Future<AppExitResponse> _exitRequested() async {
    if (!widget.active ||
        (ModalRoute.of(context)?.isCurrent != true && !_busy)) {
      return AppExitResponse.exit;
    }
    // A persistent commit is never cancelled by navigation or system exit.
    await _saveOperation;
    if (!mounted) return AppExitResponse.cancel;
    final session = _session;
    return session == null || await requestLibraryExit(context, session)
        ? AppExitResponse.exit
        : AppExitResponse.cancel;
  }

  @override
  void dispose() {
    _revision++;
    _lifecycle?.dispose();
    unawaited(_settingsChanges?.cancel());
    unawaited(_accountChanges?.cancel());
    unawaited(_processingBudgetChanges?.cancel());
    _upload.dispose();
    _processing.dispose();
    _quality.dispose();
    _longestSide.dispose();
    _cacheLimit.dispose();
    super.dispose();
  }

  void _attach(LibrarySession session) {
    if (identical(session, _session)) return;
    unawaited(_settingsChanges?.cancel());
    unawaited(_accountChanges?.cancel());
    unawaited(_processingBudgetChanges?.cancel());
    _session = session;
    _settingsChanges = session.repository.settingsChanges.listen(
      (_) => _markStale(),
    );
    _accountChanges = session.repository.accountChanges.listen(
      (_) => _markStale(),
    );
    _processingBudgetChanges = session.repository.processingScheduler.changes
        .listen((_) {
          if (mounted && identical(_session, session)) {
            // Only rebuild budget feedback; never reload or replace editor drafts.
            setState(() {});
          }
        });
  }

  void _markStale() {
    if (!mounted || _busy || _loading || _snapshot == null) return;
    setState(() {
      _stale = true;
      _feedback = null;
      _error = '设置或目标已变化，草稿保留。请重新读取后再编辑和保存。';
    });
  }

  void _apply(SettingsSnapshot snapshot) {
    _snapshot = snapshot;
    final values = snapshot.values;
    _upload.text = '${values.uploadConcurrency}';
    _processing.text = '${values.processingConcurrency}';
    _quality.text = '${values.quality}';
    _longestSide.text = '${values.longestSide}';
    _cacheLimit.text = '${values.cacheLimitMiB}';
    _mode = values.processingMode;
    _retention = values.defaultOutputRetention;
    _networkPolicy = values.networkUploadPolicy;
    _selected
      ..clear()
      ..addAll(snapshot.defaultTargetIds);
    _stale = false;
    _loading = false;
    _error = null;
  }

  Future<void> _reload() async {
    if (!mounted) return;
    final revision = ++_revision;
    setState(() {
      _loading = true;
      _feedback = null;
    });
    try {
      final session = await ref.read(librarySessionProvider.future);
      if (!mounted || revision != _revision) return;
      _attach(session);
      final snapshot = await session.repository.loadSettings();
      if (!mounted || revision != _revision) return;
      setState(() => _apply(snapshot));
    } catch (_) {
      if (!mounted || revision != _revision) return;
      setState(() {
        _loading = false;
        _error = '设置读取失败，保留最后有效值和草稿；保存已暂停，请重新读取。';
      });
    }
  }

  void _draftChanged() {
    setState(() => _feedback = null);
  }

  void _defaults() {
    final values = DeviceSettings.defaults;
    setState(() {
      _upload.text = '${values.uploadConcurrency}';
      _processing.text = '${values.processingConcurrency}';
      _quality.text = '${values.quality}';
      _longestSide.text = '${values.longestSide}';
      _cacheLimit.text = '${values.cacheLimitMiB}';
      _mode = values.processingMode;
      _retention = values.defaultOutputRetention;
      _networkPolicy = values.networkUploadPolicy;
      _selected.clear();
      _feedback = '默认值已填入草稿，尚未保存；默认目标已清空。';
    });
  }

  void _save() {
    if (!_canSave) return;
    _saveOperation = _performSave();
  }

  Future<void> _performSave() async {
    final snapshot = _snapshot!;
    final session = _session!;
    final revision = _revision;
    final epoch = session.repository.executionEpoch;
    DeviceSettings values;
    try {
      values = DeviceSettings(
        uploadConcurrency: int.tryParse(_upload.text.trim()),
        processingConcurrency: int.tryParse(_processing.text.trim()),
        quality: int.tryParse(_quality.text.trim()),
        longestSide: int.tryParse(_longestSide.text.trim()),
        processingMode: _mode,
        cacheLimitMiB: int.tryParse(_cacheLimit.text.trim()),
        defaultOutputRetention: _retention,
        networkUploadPolicy: _networkPolicy,
      );
    } on SettingsFailure catch (failure) {
      setState(() => _feedback = failure.message);
      return;
    }
    final targets = Set<String>.of(_selected);
    setState(() {
      _busy = true;
      _feedback = null;
    });
    widget.onBusyChanged?.call(true);
    var committed = false;
    try {
      await session.repository.saveSettings(
        snapshot,
        values,
        defaultTargetIds: targets,
      );
      committed = true;
      final persisted = await session.repository.loadSettings();
      if (!mounted ||
          revision != _revision ||
          epoch != session.repository.executionEpoch) {
        return;
      }
      setState(() {
        _apply(persisted);
        _feedback = '已保存。';
      });
    } catch (failure) {
      if (!mounted ||
          revision != _revision ||
          epoch != session.repository.executionEpoch) {
        return;
      }
      setState(() {
        if (committed) {
          _error = '保存已提交，但重新读取未完成，草稿保留；请重新读取确认当前值。';
        } else {
          _feedback = failure is SettingsFailure
              ? failure.message
              : '设置保存未确认，草稿与旧有效值保留；请检查后重试。';
        }
      });
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        widget.onBusyChanged?.call(false);
      }
    }
  }

  Widget _number({
    required String keyName,
    required String label,
    required String hint,
    required TextEditingController controller,
  }) => TextField(
    key: ValueKey(keyName),
    controller: controller,
    enabled: _editable,
    keyboardType: const TextInputType.numberWithOptions(signed: true),
    decoration: InputDecoration(
      labelText: label,
      helperText: hint,
      helperMaxLines: 3,
    ),
    onChanged: (_) => _draftChanged(),
  );

  Widget _section(String title, List<Widget> children) => Card(
    key: ValueKey('settings-section-$title'),
    margin: const EdgeInsets.only(bottom: 16),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    ),
  );

  Widget _target(ProviderTarget target) {
    final selected = _selected.contains(target.id);
    // A disabled target that was selected in the persisted snapshot may be
    // retained or cleared. It cannot become a new default selection.
    final allowed =
        target.enabled ||
        (_snapshot?.defaultTargetIds.contains(target.id) ?? false);
    final service = target.service == ImageHostService.catbox
        ? 'Catbox'
        : 'ImgBB';
    return CheckboxListTile(
      key: ValueKey('settings-target-${target.id}'),
      contentPadding: EdgeInsets.zero,
      title: Text('${target.alias} · $service · ${target.identityMarker}'),
      subtitle: Text(
        target.pendingOperation
            ? '凭据操作尚未完成，暂不可编辑'
            : !target.enabled
            ? '已禁用；仅已有默认选择可保留或取消'
            : '稳定目标身份；配置不等于健康',
      ),
      value: selected,
      onChanged: _editable && allowed && !target.pendingOperation
          ? (value) => setState(() {
              if (value == true) {
                _selected.add(target.id);
              } else {
                _selected.remove(target.id);
              }
              _feedback = null;
            })
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final values = _snapshot?.values;
    final repository = _session?.repository;
    final scheduler = repository?.processingScheduler;
    final content = ListView(
      key: const Key('settings-list'),
      padding: const EdgeInsets.all(16),
      children: [
        Text('本机设置', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        const Text('修改先留在草稿，保存确认后才生效。本机设置不会授予网络上传权限。'),
        const SizedBox(height: 12),
        // Keep these slots and section identities stable while an exit request
        // awaits a commit. Inserting a sliver child can otherwise dispose the
        // EditableText lifecycle listeners in Flutter's exit observer snapshot.
        _loading ? const LinearProgressIndicator() : const SizedBox.shrink(),
        _error != null
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(_error!),
              )
            : const SizedBox.shrink(),
        _feedback != null
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(_feedback!),
              )
            : const SizedBox.shrink(),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(
              key: const Key('settings-save'),
              onPressed: _canSave ? _save : null,
              child: Text(_busy ? '正在保存…' : '保存设置'),
            ),
            OutlinedButton(
              key: const Key('settings-reload'),
              onPressed: !_busy && !_loading ? _reload : null,
              child: const Text('重新读取（替换草稿）'),
            ),
            TextButton(
              key: const Key('settings-defaults'),
              onPressed: _canSave && !_pendingDefault ? _defaults : null,
              child: const Text('恢复默认到草稿'),
            ),
          ],
        ),
        _pendingDefault
            ? const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('默认目标凭据操作尚未完成，暂不能整体恢复默认；数值仍可编辑并保存。'),
              )
            : const SizedBox.shrink(),
        const SizedBox(height: 16),
        _section('上传策略', [
          DropdownButtonFormField<NetworkUploadPolicy>(
            key: ValueKey('settings-network-${_networkPolicy.name}-$_revision'),
            initialValue: _networkPolicy,
            isExpanded: true,
            isDense: false,
            itemHeight: null,
            decoration: const InputDecoration(labelText: '允许自动派发的网络类型'),
            items: const [
              DropdownMenuItem(
                value: NetworkUploadPolicy.wifiAndEthernet,
                child: Text('仅 Wi-Fi / 有线网络'),
              ),
              DropdownMenuItem(
                value: NetworkUploadPolicy.anyKnownNetwork,
                child: Text('所有已识别网络（含移动网络）'),
              ),
            ],
            onChanged: _editable
                ? (value) {
                    if (value != null) {
                      setState(() {
                        _networkPolicy = value;
                        _feedback = null;
                      });
                    }
                  }
                : null,
          ),
          const SizedBox(height: 12),
          const Text(
            '仅控制已确认上传任务的自动派发；保存设置不会授予本次会话上传许可。断网、网络类型未确认或不在允许范围时等待；恢复为允许的网络后自动继续，用户暂停的任务仍保持暂停。',
          ),
          const SizedBox(height: 16),
          _number(
            keyName: 'settings-upload-concurrency',
            label: '上传并发',
            hint:
                '1–8 个任务；当前生效：${repository?.currentDeviceSettings.uploadConcurrency ?? '未读取'}',
            controller: _upload,
          ),
          const SizedBox(height: 12),
          const Text(
            '固定安全策略：120 秒无活动超时；累计执行 30 分钟超时。最多初次加 3 次尝试，退避 2 / 4 / 8 秒且不剪短 Retry-After。结果未知或不能确认安全重传时，不自动重传。服务精确能力未知时等待确认，不派发。',
          ),
        ]),
        _section('处理与新工作台默认值', [
          _number(
            keyName: 'settings-processing-concurrency',
            label: '处理并发',
            hint:
                '1–4 个任务；已保存设置：${values?.processingConcurrency ?? '未读取'}；当前有效：${scheduler?.effectiveConcurrency ?? '未读取'}',
            controller: _processing,
          ),
          const SizedBox(height: 12),
          Text(scheduler?.budgetReason ?? '处理候选内存预算尚未读取。'),
          const Text(
            '按每项 128 MiB 候选预算折算有效并发；总预算更低时仅保留一项，并显示实际预算。这不是四端性能实测。已在执行的工作持有原预算直到真实 IO 结束。',
          ),
          const SizedBox(height: 16),
          _number(
            keyName: 'settings-quality',
            label: '有损输出质量',
            hint: '1–100；当前保存值：${values?.quality ?? '未读取'}',
            controller: _quality,
          ),
          const SizedBox(height: 16),
          _number(
            keyName: 'settings-longest-side',
            label: '体积优先最长边',
            hint: '1–16384 像素；当前保存值：${values?.longestSide ?? '未读取'}',
            controller: _longestSide,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<ProcessingMode>(
            initialValue: _mode,
            key: ValueKey('settings-mode-${_mode.name}-$_revision'),
            isExpanded: true,
            decoration: const InputDecoration(labelText: '新工作台默认模式'),
            items: const [
              DropdownMenuItem(
                value: ProcessingMode.fidelity,
                child: Text('保真优先'),
              ),
              DropdownMenuItem(
                value: ProcessingMode.sizeFirst,
                child: Text('体积优先'),
              ),
            ],
            onChanged: _editable
                ? (value) {
                    if (value != null) {
                      setState(() {
                        _mode = value;
                        _feedback = null;
                      });
                    }
                  }
                : null,
          ),
          const SizedBox(height: 12),
          const Text('质量、最长边和模式只初始化新工作台草稿。已有草稿、任务及输出保留原参数。'),
        ]),
        _section('空间与缓存', [
          _number(
            keyName: 'settings-cache-limit',
            label: '缩略图缓存上限（MiB）',
            hint: '64–2048；当前保存值：${values?.cacheLimitMiB ?? '未读取'} MiB',
            controller: _cacheLimit,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<OutputRetention>(
            key: ValueKey('settings-retention-${_retention.name}-$_revision'),
            initialValue: _retention,
            isExpanded: true,
            decoration: const InputDecoration(labelText: '新工作台临时输出默认保留时间'),
            items: const [
              DropdownMenuItem(
                value: OutputRetention.hour,
                child: Text('1 小时'),
              ),
              DropdownMenuItem(
                value: OutputRetention.day,
                child: Text('24 小时'),
              ),
              DropdownMenuItem(value: OutputRetention.week, child: Text('7 天')),
            ],
            onChanged: _editable
                ? (value) {
                    if (value != null) {
                      setState(() {
                        _retention = value;
                        _feedback = null;
                      });
                    }
                  }
                : null,
          ),
          const SizedBox(height: 12),
          const Text(
            '保留时间只初始化新工作台草稿，已有输出的到期时间不变。缓存按最近使用顺序回收可再生缩略图；正在使用或未安全登记的文件仍保留，因此可能暂时超过上限。',
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            key: const Key('settings-storage'),
            onPressed: !_busy
                ? () => Navigator.of(context).push<void>(
                    MaterialPageRoute(builder: (_) => const StorageScreen()),
                  )
                : null,
            child: const Text('打开空间管理'),
          ),
        ]),
        _section('默认上传目标', [
          const Text('下次新建上传草稿预选这些目标，仍须确认输入和本次会话网络权限。默认选择复用账号页的同一标记。'),
          if (_snapshot != null && _snapshot!.targets.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text('暂无账号目标，请先在账号页配置。'),
            ),
          for (final target in _snapshot?.targets ?? <ProviderTarget>[])
            _target(target),
        ]),
        _section('隐私边界', [
          const Text(
            '处理输出固定去除敏感元数据。上传原图每次另行明确确认元数据风险，不以本机默认设置替代确认。应用无网络遥测或自动外发。凭据及管理秘密保存在系统受保护存储；明确的会话凭据仅在内存，关闭即清空。',
          ),
        ]),
        _section('保留、备份与卸载', [
          const Text(
            '永久副本与可再生缓存分别保留；缓存和缩略图不能作为原图。回收站满 30 天只提示，不自动清除永久字节。清记录与清永久字节分别确认，持久引用和实际 IO 租约仍保护文件。',
          ),
          const SizedBox(height: 12),
          const Text(
            '临时输出按新工作台设置的保留期到期后，仅在没有保护引用时清理；已保存的永久副本不受临时输出保留期影响。本机诊断记录按 30 天或 10,000,000 字节先到的条件清理。',
          ),
          const SizedBox(height: 12),
          const Text(
            '清除应用数据或卸载前，请导出并校验备份。完整备份携带永久图片字节，元数据包不携带图片；可携带备份不含系统凭据、临时输出、活动任务或本机诊断日志。操作日志用于恢复本机提交，不是远端备份。',
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            key: const Key('settings-backup'),
            onPressed: !_busy && !_loading && widget.active
                ? () => Navigator.of(context).push<void>(
                    MaterialPageRoute(builder: (_) => const BackupScreen()),
                  )
                : null,
            child: const Text('打开备份与恢复'),
          ),
          const SizedBox(height: 12),
          const Text(
            '系统保存的凭据需在账号管理中明确移除；本次会话凭据在关闭时清空，可携带备份不含凭据。卸载行为不保证系统删除凭据。卸载或清本机数据不会自动删除远端图片，远端保留与删除遵循服务规则，本机记录不能保证远端永久存在。',
          ),
        ]),
        _section('本机诊断', [
          const Text('查看本机脱敏事件、按范围清理或明确确认后导出 JSON。不会自动外发。'),
          const SizedBox(height: 12),
          OutlinedButton(
            key: const Key('settings-diagnostics'),
            onPressed: !_busy
                ? () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => const DiagnosticsScreen(),
                    ),
                  )
                : null,
            child: const Text('打开本机诊断'),
          ),
        ]),
      ],
    );
    return PopScope(
      canPop: !_busy,
      child: widget.embedded
          ? content
          : Scaffold(
              appBar: AppBar(title: const Text('设置')),
              body: content,
            ),
    );
  }
}
