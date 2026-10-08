import 'dart:collection';

/// A boundary for ordinary output, not a secret persistence mechanism.
/// Callers must register secret values before constructing diagnostic output.
final class SecretRedactor {
  static const hidden = '[已隐藏]';
  static const unavailable = '[无法安全显示]';
  static const _maxDepth = 32;
  static const _maxNodes = 10000;

  // Keep retired values masked for cached diagnostics during this lifetime.
  final Set<String> _history = {};
  final Set<String> _active = {};
  RegExp? _registeredPattern;
  int _revision = 0;

  /// Changes only when an additional historical value requires masking.
  int get revision => _revision;

  void register(String secret) {
    if (secret.isEmpty) return;
    _active.add(secret);
    if (!_history.add(secret)) return;
    _revision++;
    final variants = <String>{};
    for (final value in _history) {
      variants.add(value);
      final component = Uri.encodeComponent(value);
      final query = Uri.encodeQueryComponent(value);
      variants.addAll([
        component,
        query,
        Uri.encodeComponent(component),
        Uri.encodeComponent(query),
      ]);
    }
    final sorted = variants.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    _registeredPattern = RegExp(
      sorted.map(RegExp.escape).join('|'),
      caseSensitive: false,
    );
  }

  /// Stops active use without allowing historical output to reveal the value.
  void unregister(String secret) => _active.remove(secret);

  static bool _sensitiveKey(String key) {
    var decoded = key;
    try {
      decoded = Uri.decodeQueryComponent(decoded);
    } on FormatException {
      // Malformed keys can still be recognized by their literal spelling.
    }
    final normalized = decoded.toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]'),
      '',
    );
    return const {
      'key',
      'apikey',
      'userhash',
      'token',
      'accesstoken',
      'refreshtoken',
      'authtoken',
      'secret',
      'clientsecret',
      'password',
      'passwd',
      'authorization',
      'proxyauthorization',
      'deleteurl',
      'deletionurl',
      'deletekey',
      'deletetoken',
      'credential',
      'credentials',
    }.contains(normalized);
  }

  static final _query = RegExp(r'([?&;])([^=?&;\s#]+)=([^&;\s#]*)');
  static final _assignment = RegExp(
    r'''(["']?)\b(key|api[_ -]?key|user[_ -]?hash|(?:access[_ -]?|refresh[_ -]?|auth[_ -]?)?token|(?:client[_ -]?)?secret|password|passwd|(?:proxy[_ -]?)?authorization|delet(?:e|ion)[_ -]?(?:url|key|token)|credentials?)\1\s*[:=]\s*(?:"(?:\\.|[^"\\])*"?|'(?:\\.|[^'\\])*'?|[^,;&\r\n}\]]*)''',
    caseSensitive: false,
  );
  static final _authorization = RegExp(
    r'\b(?:Bearer|Basic)\s+[^\s,;"\]}]+',
    caseSensitive: false,
  );
  static final _userinfo = RegExp(
    r'(https?://)[^/\s@]+@',
    caseSensitive: false,
  );

  String redactText(String text) {
    // Redact syntax first: a truncated secret is still protected when its
    // field/header context remains. Arbitrary context-free fragments cannot
    // be inferred and must never be constructed by output callers.
    var result = text.replaceAllMapped(_query, (match) {
      if (!_sensitiveKey(match[2]!)) return match[0]!;
      return '${match[1]}${match[2]}=$hidden';
    });
    result = result.replaceAllMapped(_assignment, (match) {
      if (!_sensitiveKey(match[2]!)) return match[0]!;
      return '${match[1]}${match[2]}${match[1]}: $hidden';
    });
    result = result.replaceAll(_authorization, hidden);
    result = result.replaceAllMapped(
      _userinfo,
      (match) => '${match[1]}$hidden@',
    );
    final pattern = _registeredPattern;
    return pattern == null ? result : result.replaceAll(pattern, hidden);
  }

  /// Produces only JSON-like primitives. Unknown objects, cycles, excessive
  /// depth/size and custom collection failures receive a fixed safe marker.
  /// No fallback calls the input's toString (including exception objects).
  Object? redact(Object? input) {
    final ancestors = HashSet<Object>.identity();
    var nodes = 0;
    Object? visit(Object? value, int depth) {
      if (++nodes > _maxNodes || depth > _maxDepth) return unavailable;
      if (value == null) return null;
      if (value is bool || value is int || value is double) {
        // These built-in primitive types have trusted string representations;
        // a type conversion must not bypass registered-value redaction.
        final text = value.toString();
        return redactText(text) == text ? value : hidden;
      }
      if (value is String) return redactText(value);
      if (value is! Map && value is! List) return unavailable;
      if (!ancestors.add(value)) return unavailable;
      try {
        if (value is Map) {
          final result = <String, Object?>{};
          for (final entry in value.entries) {
            if (++nodes > _maxNodes) return unavailable;
            final key = entry.key;
            if (key is! String) return unavailable;
            result[redactText(key)] = _sensitiveKey(key)
                ? hidden
                : visit(entry.value, depth + 1);
          }
          return result;
        }
        final result = <Object?>[];
        for (final entry in value as List) {
          if (nodes > _maxNodes) return unavailable;
          result.add(visit(entry, depth + 1));
        }
        return result;
      } catch (_) {
        return unavailable;
      } finally {
        ancestors.remove(value);
      }
    }

    return visit(input, 0);
  }
}
