import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/secret_store.dart';
import '../../gallery/data/library_repository.dart';
import '../../gallery/presentation/gallery_providers.dart';
import '../domain/account_models.dart';
import '../../upload/presentation/upload_exit.dart';

/// Local upload configuration and observations from committed attempts.
class AccountsScreen extends ConsumerStatefulWidget {
  const AccountsScreen({super.key});

  @override
  ConsumerState<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends ConsumerState<AccountsScreen> {
  List<ProviderTarget> _targets = const [];
  bool _loading = true;
  bool _hasLoaded = false;
  bool _busy = false;
  int _revision = 0;
  String? _loadError;
  Future<void>? _activeFuture;
  StreamSubscription<void>? _healthChanges;
  LibraryRepository? _healthRepository;
  bool _healthReloadPending = false;
  bool _exitPending = false;
  DialogRoute<bool>? _impactRoute;
  NavigatorState? _impactNavigator;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onExitRequested: _exitRequested);
    ref.listenManual(libraryReplacementRevisionProvider, (_, _) {
      _dismissImpact();
      setState(() {
        _targets = const [];
        _hasLoaded = false;
        _loading = false;
        _loadError = null;
      });
      unawaited(_reload());
    });
    unawaited(_reload());
  }

  @override
  void dispose() {
    _dismissImpact();
    unawaited(_healthChanges?.cancel());
    _lifecycle.dispose();
    super.dispose();
  }

  Future<AppExitResponse> _exitRequested() async {
    _exitPending = true;
    _dismissImpact();
    try {
      final active = _activeFuture;
      if (active != null) await active;
      if (!mounted) return AppExitResponse.cancel;
      final session = ref.read(librarySessionProvider).asData?.value;
      if (session != null && !await requestLibraryExit(context, session)) {
        return AppExitResponse.cancel;
      }
      return AppExitResponse.exit;
    } finally {
      _exitPending = false;
    }
  }

  void _dismissImpact() {
    final route = _impactRoute, navigator = _impactNavigator;
    _impactRoute = null;
    _impactNavigator = null;
    if (route != null &&
        route.isActive &&
        navigator != null &&
        navigator.mounted) {
      navigator.removeRoute(route);
    }
  }

  Future<void> _reload() async {
    if (_loading && _hasLoaded) return;
    final revision = ++_revision;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final future = _loadTargets();
      _track(future);
      final targets = await future;
      if (!mounted || revision != _revision) return;
      setState(() {
        _targets = targets;
        _hasLoaded = true;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || revision != _revision) return;
      setState(() {
        _hasLoaded = true;
        _loading = false;
        _loadError = '账号列表读取失败，请重试。';
      });
    } finally {
      _drainHealthReload();
    }
  }

  Future<List<ProviderTarget>> _loadTargets() async {
    final session = await ref.read(librarySessionProvider.future);
    if (mounted && !identical(_healthRepository, session.repository)) {
      await _healthChanges?.cancel();
      if (!mounted) return const [];
      _healthRepository = session.repository;
      _healthChanges = session.repository.accountHealthChanges.listen((_) {
        if (!mounted) return;
        _healthReloadPending = true;
        _drainHealthReload();
      });
    }
    return session.repository.listTargets(includeRemoved: true);
  }

  // Health is display-only. Defer refresh while a draft save or list load is
  // active, so its tracking/feedback is not replaced by a background reload.
  void _drainHealthReload() {
    if (!mounted || _busy || _loading || !_healthReloadPending) return;
    _healthReloadPending = false;
    unawaited(_reload());
  }

  void _track<T>(Future<T> future) {
    final active = future.then<void>((_) {}, onError: (_, _) {});
    _activeFuture = active;
    unawaited(
      active.whenComplete(() {
        if (identical(_activeFuture, active)) _activeFuture = null;
      }),
    );
  }

  Future<String?> _save(AccountDraft draft) {
    if (_busy) return Future.value('请等待当前账号操作完成。');
    setState(() => _busy = true);
    final operation = _performSave(draft);
    _track(operation);
    return operation;
  }

  Future<String?> _performSave(AccountDraft draft) async {
    try {
      final session = await ref.read(librarySessionProvider.future);
      final previous = _targets.where((t) => t.id == draft.id).firstOrNull;
      if (previous != null && previous.enabled && !draft.enabled) {
        if (!await _confirmImpact(
          session.repository,
          previous,
          removing: false,
        )) {
          return '已取消停用，编辑草稿保留。';
        }
        if (!mounted) return '账号页面已关闭，未修改配置。';
      }
      final operation = session.repository.saveTarget(
        id: draft.id,
        service: draft.service,
        alias: draft.alias,
        anonymous: false,
        enabled: draft.enabled,
        selectedByDefault: draft.selectedByDefault,
        credential: draft.credential,
        persistence: draft.persistence,
      );
      await operation;
      return null;
    } on AccountFailure catch (error) {
      return error.message;
    } on SecretStorageException {
      return SecretStorageException.message;
    } catch (_) {
      return '账号配置保存未完成，请刷新核对后重试。';
    } finally {
      if (mounted) setState(() => _busy = false);
      _drainHealthReload();
    }
  }

  Future<String?> _remove(String id) {
    if (_busy) return Future.value('请等待当前账号操作完成。');
    setState(() => _busy = true);
    final operation = _performRemove(id);
    _track(operation);
    return operation;
  }

  Future<String?> _performRemove(String id) async {
    try {
      final session = await ref.read(librarySessionProvider.future);
      final operation = session.repository.removeTarget(id);
      await operation;
      return null;
    } on AccountFailure catch (error) {
      return error.message;
    } on SecretStorageException {
      return SecretStorageException.message;
    } catch (_) {
      return '移除未完成，请重试；已有历史仍保留。';
    } finally {
      if (mounted) setState(() => _busy = false);
      _drainHealthReload();
    }
  }

  Future<void> _add() async {
    if (_busy) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => _TargetDialog(onSave: _save),
    );
    if (saved == true && mounted) await _reload();
  }

  Future<void> _edit(ProviderTarget target) async {
    if (_busy ||
        target.removed ||
        target.pendingOperation ||
        target.anonymous) {
      return;
    }
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => _TargetDialog(target: target, onSave: _save),
    );
    if (saved == true && mounted) await _reload();
  }

  Future<void> _confirmRemove(ProviderTarget target) async {
    if (_busy || target.removed) return;
    setState(() => _busy = true);
    var confirmed = false;
    try {
      final session = await ref.read(librarySessionProvider.future);
      final operation = _confirmImpact(
        session.repository,
        target,
        removing: true,
      );
      _track(operation);
      confirmed = await operation;
    } catch (_) {
      if (mounted) _showMessage('受影响任务读取失败，未移除账号；请刷新后重试。');
    } finally {
      if (mounted) setState(() => _busy = false);
      _drainHealthReload();
    }
    if (!confirmed || !mounted) return;
    final error = await _remove(target.id);
    if (!mounted) return;
    if (error != null) _showMessage(error);
    await _reload();
  }

  Future<bool> _confirmImpact(
    LibraryRepository repository,
    ProviderTarget target, {
    required bool removing,
  }) async {
    final impact = await repository.targetUploadImpact(target.id);
    if (!mounted || _exitPending) return false;
    final navigator = Navigator.of(context, rootNavigator: true);
    final route = DialogRoute<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(removing ? '移除账号目标？' : '停用账号目标？'),
        content: Text(
          '${_serviceName(target.service)}「${target.alias}」（身份标记 ${target.identityMarker}）\n'
          '待执行 ${impact.pending} 项 · 正在运行 ${impact.running} 项 · 结果未知 ${impact.unknown} 项。\n\n'
          '这是当前目标的任务快照，确认前后任务状态可能变化。后续请求将被阻止；已发出的请求只能尽力停止，不能保证撤回远端副作用。'
          '晚到确认与已有历史仍保留，不会删除远端文件。'
          '${removing ? '若秘密清理失败，系统会保留恢复提示。' : '继续使用需重新启用并核对任务条件。'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: Text(removing ? '确认移除' : '确认停用'),
          ),
        ],
      ),
    );
    _impactRoute = route;
    _impactNavigator = navigator;
    try {
      return await navigator.push(route) == true;
    } finally {
      if (identical(_impactRoute, route)) {
        _impactRoute = null;
        _impactNavigator = null;
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('图床账号'),
        actions: [
          IconButton(
            onPressed: _busy || _loading ? null : _reload,
            icon: const Icon(Icons.refresh),
            tooltip: '刷新账号状态',
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 560;
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1040),
              child: ListView(
                padding: EdgeInsets.all(compact ? 16 : 28),
                children: [
                  _intro(compact),
                  const SizedBox(height: 20),
                  _providerInformation(),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '配置目标',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: _busy ? null : _add,
                        icon: const Icon(Icons.add),
                        label: const Text('添加目标'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_loading && !_hasLoaded)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    )
                  else if (_loadError != null && _targets.isEmpty)
                    _errorCard()
                  else if (_targets.isEmpty)
                    _emptyCard()
                  else ...[
                    if (_loadError != null) ...[
                      _inlineError(),
                      const SizedBox(height: 10),
                    ],
                    for (final target in _targets) ...[
                      _targetCard(target, compact),
                      const SizedBox(height: 10),
                    ],
                  ],
                ],
              ),
            ),
          );
        },
      ),
    ),
  );

  Widget _intro(bool compact) => Card(
    child: Padding(
      padding: EdgeInsets.all(compact ? 16 : 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('管理本机保存的图床目标', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text('凭据仅写入系统安全存储，或明确选择只在本次会话使用。账号配置不会发起网络请求。'),
          const SizedBox(height: 8),
          const Text('配置不代表服务已经验证可用。状态来自当前目标的上传结果观察；未确认结果不会被当作成功。'),
        ],
      ),
    ),
  );

  Widget _providerInformation() => Card(
    clipBehavior: Clip.antiAlias,
    child: ExpansionTile(
      leading: const Icon(Icons.info_outline),
      title: const Text('服务信息与当前限制'),
      children: [
        for (final info in ProviderInformation.values)
          ListTile(
            title: Text(info.name),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '${info.details}\n官方资料：${info.officialUrl}\n资料核对日期：${info.checkedOn}',
              ),
            ),
            isThreeLine: true,
          ),
      ],
    ),
  );

  Widget _errorCard() => Card(
    child: Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        children: [
          const Text('账号列表暂时无法读取，已有资料不会被覆盖。'),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _loading ? null : _reload,
            icon: const Icon(Icons.refresh),
            label: const Text('重试'),
          ),
        ],
      ),
    ),
  );

  Widget _inlineError() => Card(
    color: Theme.of(context).colorScheme.errorContainer,
    child: ListTile(
      title: const Text('刷新失败，仍显示上次读取的账号列表。'),
      trailing: IconButton(
        onPressed: _loading ? null : _reload,
        tooltip: '重试',
        icon: const Icon(Icons.refresh),
      ),
    ),
  );

  Widget _emptyCard() => Card(
    child: Padding(
      padding: const EdgeInsets.all(26),
      child: Column(
        children: [
          const Icon(Icons.cloud_outlined, size: 34),
          const SizedBox(height: 10),
          const Text('还没有账号目标'),
          const SizedBox(height: 6),
          const Text('添加目标只会保存本机配置，不会验证凭据或上传图片。'),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : _add,
            icon: const Icon(Icons.add),
            label: const Text('添加目标'),
          ),
        ],
      ),
    ),
  );

  Widget _targetCard(ProviderTarget target, bool compact) {
    final badges = <Widget>[
      _badge(_healthName(target.health), _healthIcon(target.health)),
      if (target.enabled && !target.removed)
        _badge('已启用', Icons.check_circle_outline),
      if (target.selectedByDefault && !target.removed)
        _badge('默认目标', Icons.star_outline),
      if (target.anonymous) _badge('匿名历史 · 已停用', Icons.person_outline),
      if (target.sessionOnly) _badge('仅本次会话', Icons.hourglass_bottom),
      if (target.pendingOperation)
        _badge('凭据操作待恢复', Icons.sync_problem_outlined),
      if (target.removed) _badge('已移除', Icons.delete_outline),
    ];
    return Card(
      child: Padding(
        padding: EdgeInsets.all(compact ? 14 : 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  _serviceName(target.service),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  target.alias,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  '身份 ${target.identityMarker}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: badges),
            if (target.anonymous) ...[
              const SizedBox(height: 8),
              const Text('匿名上传已停用；此目标仅保留既有历史，可移除本地配置，不能编辑、启用或设为默认。'),
            ],
            if (target.pendingOperation) ...[
              const SizedBox(height: 10),
              Text(
                target.sessionOnly
                    ? '旧凭据清理待恢复；当前凭据仅在本次会话使用。'
                    : '凭据操作待恢复；请刷新重试后再使用此目标。',
              ),
            ],
            if (target.health == AccountHealth.temporarilyUnavailable) ...[
              const SizedBox(height: 8),
              const Text('安全存储暂不可用；凭据内容不会在此显示。'),
            ],
            if (!target.removed) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    onPressed:
                        _busy || target.pendingOperation || target.anonymous
                        ? null
                        : () => _edit(target),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('编辑'),
                  ),
                  TextButton.icon(
                    onPressed: _busy ? null : () => _confirmRemove(target),
                    icon: const Icon(Icons.remove_circle_outline),
                    label: const Text('移除'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _badge(String text, IconData icon) => Chip(
    avatar: Icon(icon, size: 16),
    label: Text(text),
    visualDensity: VisualDensity.compact,
  );

  static String _serviceName(ImageHostService service) => switch (service) {
    ImageHostService.catbox => 'Catbox',
    ImageHostService.imgbb => 'ImgBB',
  };

  static String _healthName(AccountHealth health) => switch (health) {
    AccountHealth.unconfigured => '未配置',
    AccountHealth.unverified => '未验证',
    AccountHealth.available => '可用',
    AccountHealth.authorizationInvalid => '授权失效',
    AccountHealth.temporarilyUnavailable => '暂时不可用',
  };

  static IconData _healthIcon(AccountHealth health) => switch (health) {
    AccountHealth.unconfigured => Icons.key_off_outlined,
    AccountHealth.unverified => Icons.help_outline,
    AccountHealth.available => Icons.check_circle_outline,
    AccountHealth.authorizationInvalid => Icons.lock_outline,
    AccountHealth.temporarilyUnavailable => Icons.error_outline,
  };
}

class AccountDraft {
  const AccountDraft({
    this.id,
    required this.service,
    required this.alias,
    required this.enabled,
    required this.selectedByDefault,
    required this.credential,
    required this.persistence,
  });

  final String? id;
  final ImageHostService service;
  final String alias;
  final bool enabled;
  final bool selectedByDefault;
  final String? credential;
  final CredentialPersistence persistence;
}

typedef _SaveTarget = Future<String?> Function(AccountDraft draft);

class _TargetDialog extends StatefulWidget {
  const _TargetDialog({this.target, required this.onSave});

  final ProviderTarget? target;
  final _SaveTarget onSave;

  @override
  State<_TargetDialog> createState() => _TargetDialogState();
}

class _TargetDialogState extends State<_TargetDialog> {
  late final TextEditingController _alias;
  late final TextEditingController _credential;
  late ImageHostService _service;
  late bool _enabled;
  late bool _selectedByDefault;
  CredentialPersistence? _persistence;
  bool _saving = false;
  bool _credentialUnavailable = false;
  String? _error;

  bool get _editing => widget.target != null;

  @override
  void initState() {
    super.initState();
    final target = widget.target;
    _service = target?.service ?? ImageHostService.catbox;
    _enabled = target?.enabled ?? true;
    _selectedByDefault = target?.selectedByDefault ?? false;
    _credentialUnavailable =
        target != null &&
        !target.anonymous &&
        target.health == AccountHealth.temporarilyUnavailable;
    _alias = TextEditingController(text: target?.alias ?? '');
    _credential = TextEditingController();
  }

  @override
  void dispose() {
    _alias.clear();
    _credential.clear();
    _alias.dispose();
    _credential.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    final alias = _alias.text.trim();
    final credential = _credential.text;
    if (alias.isEmpty) {
      setState(() => _error = '请填写显示名称。');
      return;
    }
    if (!_editing && credential.trim().isEmpty) {
      setState(() => _error = '新建账号目标必须填写凭据。');
      return;
    }
    if (credential.isNotEmpty && _persistence == null) {
      setState(() => _error = '请选择凭据保存位置。');
      return;
    }
    if (_editing && credential.isEmpty && _credentialUnavailable) {
      setState(() => _error = '现有凭据无法读取。可取消编辑并添加一个独立的仅本次会话目标。');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final error = await widget.onSave(
      AccountDraft(
        id: widget.target?.id,
        service: _service,
        alias: alias,
        enabled: _enabled,
        selectedByDefault: _selectedByDefault,
        credential: credential.isEmpty ? null : credential,
        persistence: _persistence ?? CredentialPersistence.protected,
      ),
    );
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _saving = false;
        _error = error;
      });
      return;
    }
    _credential.clear();
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: Text(_editing ? '编辑账号目标' : '添加账号目标'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<ImageHostService>(
                initialValue: _service,
                decoration: const InputDecoration(labelText: '服务'),
                items: [
                  for (final service in ImageHostService.values)
                    DropdownMenuItem(
                      value: service,
                      child: Text(_serviceName(service)),
                    ),
                ],
                onChanged: _editing || _saving
                    ? null
                    : (value) => setState(() {
                        _service = value!;
                        _credential.clear();
                        _persistence = null;
                      }),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _alias,
                enabled: !_saving,
                decoration: const InputDecoration(
                  labelText: '显示名称',
                  hintText: '可与其他目标重名',
                ),
              ),
              ...[
                const SizedBox(height: 14),
                TextField(
                  controller: _credential,
                  enabled: !_saving,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: _editing ? '新凭据（留空表示不更改）' : '凭据',
                    helperText: _credentialUnavailable
                        ? '现有凭据暂不可读；可添加独立的仅本次会话目标。'
                        : null,
                  ),
                ),
                const SizedBox(height: 8),
                Text('凭据保存位置', style: Theme.of(context).textTheme.labelLarge),
                RadioGroup<CredentialPersistence>(
                  groupValue: _persistence,
                  onChanged: (value) {
                    if (!_saving) setState(() => _persistence = value);
                  },
                  child: Column(
                    children: [
                      RadioListTile<CredentialPersistence>(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('系统安全存储'),
                        value: CredentialPersistence.protected,
                        enabled: !_saving,
                      ),
                      RadioListTile<CredentialPersistence>(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('仅本次会话'),
                        subtitle: const Text('关闭应用后需要重新配置。'),
                        value: CredentialPersistence.session,
                        enabled: !_saving,
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 4),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('启用目标'),
                value: _enabled,
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _enabled = value ?? false),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('设为默认目标'),
                value: _selectedByDefault,
                onChanged: _saving
                    ? null
                    : (value) =>
                          setState(() => _selectedByDefault = value ?? false),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('保存'),
        ),
      ],
    ),
  );

  static String _serviceName(ImageHostService service) => switch (service) {
    ImageHostService.catbox => 'Catbox',
    ImageHostService.imgbb => 'ImgBB',
  };
}
