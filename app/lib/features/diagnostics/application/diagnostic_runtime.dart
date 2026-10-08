import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart' hide DiagnosticLevel;
import 'package:uuid/uuid.dart';

import '../domain/diagnostic_models.dart';

/// SDK entry points keep only fixed classifications, never exception/stack data.
final class DiagnosticRuntime {
  DiagnosticRuntime();
  static final instance = DiagnosticRuntime();
  bool _installed = false;
  FlutterExceptionHandler? _oldFlutter;
  bool Function(Object, StackTrace)? _oldPlatform;
  late final FlutterExceptionHandler _flutterHandler;
  late final bool Function(Object, StackTrace) _platformHandler;
  final List<DiagnosticEvent> _pending = [];
  Future<void> _tail = Future.value();
  Future<void> Function(DiagnosticEvent)? _sink;
  Object? _owner;
  bool get installed => _installed;

  void install() {
    if (_installed) return;
    _installed = true;
    _oldFlutter = FlutterError.onError;
    _oldPlatform = PlatformDispatcher.instance.onError;
    _flutterHandler = (_) => _capture('sdk.flutter');
    _platformHandler = (_, _) {
      _capture('sdk.platform');
      return true;
    };
    FlutterError.onError = _flutterHandler;
    PlatformDispatcher.instance.onError = _platformHandler;
  }

  void _capture(String code) {
    final event = DiagnosticEvent(
      id: const Uuid().v4(),
      occurredAt: clock.now().toUtc(),
      kind: DiagnosticKind.system,
      level: DiagnosticLevel.error,
      code: code,
      summary: '应用运行发生异常，原始异常内容未进入诊断。',
      recoveryAction: '请先核查已保存资料，重开应用；若仍发生，主动导出诊断供检查。',
    );
    if (_sink == null) {
      if (_pending.length == 100) _pending.removeAt(0);
      _pending.add(event);
    } else {
      _enqueue(event, _sink!);
    }
  }

  void _enqueue(
    DiagnosticEvent event,
    Future<void> Function(DiagnosticEvent) sink,
  ) {
    _tail = _tail.then((_) async {
      try {
        await sink(event);
      } catch (_) {
        // Do not recursively report a logger failure or print raw exceptions.
      }
    });
  }

  /// Each attachment owns its detach, so an old scope cannot detach a new one.
  Future<void> Function() attach(Future<void> Function(DiagnosticEvent) sink) {
    if (!_installed) return () async {};
    final owner = Object();
    _owner = owner;
    _sink = sink;
    for (final event in _pending) {
      _enqueue(event, sink);
    }
    _pending.clear();
    return () async {
      if (identical(_owner, owner)) {
        _owner = null;
        _sink = null;
      }
      await _tail;
    };
  }

  Future<void> flush() => _tail;

  /// Used by controlled handler tests; restore only the handlers we still own.
  Future<void> uninstall() async {
    _sink = null;
    _owner = null;
    await _tail;
    if (_installed) {
      if (identical(FlutterError.onError, _flutterHandler)) {
        FlutterError.onError = _oldFlutter;
      }
      if (identical(PlatformDispatcher.instance.onError, _platformHandler)) {
        PlatformDispatcher.instance.onError = _oldPlatform;
      }
    }
    _pending.clear();
    _installed = false;
  }
}
