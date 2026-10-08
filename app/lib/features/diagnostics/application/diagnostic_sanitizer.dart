import '../../../core/secret_redactor.dart';
import '../domain/diagnostic_models.dart';

/// Diagnostics have a narrower output contract than ordinary library text.
final class DiagnosticSanitizer {
  DiagnosticSanitizer(this.redactor);
  final SecretRedactor redactor;
  static const excluded = '[诊断已排除]';
  static const _maxStringScalars = 4096;

  static String _key(String value) {
    var decoded = value;
    for (var index = 0; index < 2; index++) {
      try {
        decoded = Uri.decodeQueryComponent(decoded);
      } on FormatException {
        break;
      }
    }
    return decoded.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  static bool _excludedField(String key) {
    final normalized = _key(key);
    return const {
          'image',
          'images',
          'imagebytes',
          'imagedata',
          'pixels',
          'pixeldata',
          'thumbnail',
          'thumbnailbytes',
          'previewbytes',
          'bytes',
          'binary',
          'base64',
          'body',
          'rawbody',
          'responsebody',
          'requestbody',
          'rawresponse',
          'rawrequest',
          'raw',
          'payload',
          'credentialref',
          'credentialreference',
          'secretreference',
          'secretref',
          'managementsecretref',
          'deletionsecretref',
          'managementreference',
          'credentialid',
          'secretid',
          'deletionsecretid',
          'externalpath',
          'sourcepath',
          'filepath',
          'absolutepath',
          'path',
        }.contains(normalized) ||
        normalized.endsWith('secretref') ||
        normalized.endsWith('secretreference') ||
        normalized.endsWith('credentialref') ||
        normalized.endsWith('credentialreference') ||
        normalized.endsWith('bytes') ||
        normalized.endsWith('body');
  }

  /// The first traversal is the shared secret boundary, before truncation.
  Object? sanitize(Object? input) {
    final safe = redactor.redact(input);
    var nodes = 0;
    Object? visit(Object? value, int depth) {
      if (++nodes > 10000 || depth > 32) return SecretRedactor.unavailable;
      if (value == null || value is bool || value is int) return value;
      if (value is double) {
        return value.isFinite ? value : SecretRedactor.unavailable;
      }
      if (value is String) return text(value);
      if (value is Map<String, Object?>) {
        final result = <String, Object?>{};
        for (final entry in value.entries) {
          if (++nodes > 10000) return SecretRedactor.unavailable;
          if (_excludedField(entry.key)) continue;
          final key = text(entry.key);
          // A transformed key may collide. Never overwrite an earlier field.
          if (result.containsKey(key)) return SecretRedactor.unavailable;
          result[key] = visit(entry.value, depth + 1);
        }
        return result;
      }
      if (value is List) {
        final result = <Object?>[];
        for (final entry in value) {
          if (nodes >= 10000) return SecretRedactor.unavailable;
          result.add(visit(entry, depth + 1));
        }
        return result;
      }
      return SecretRedactor.unavailable;
    }

    return visit(safe, 0);
  }

  // The shared redactor rewrites assignments as ': [已隐藏]'. Its inserted
  // whitespace remains inside the original URL token, including the tail.
  static final _url = RegExp(
    r'''https?://(?:[^\s<>"']|\s+(?=\[已隐藏\]))+''',
    caseSensitive: false,
  );
  static final _fileUri = RegExp(
    r'''file:(?://)?[^\s<>"']+''',
    caseSensitive: false,
  );
  static final _windows = RegExp(r'''\b[a-zA-Z]:[\\/][^\r\n<>"']*''');
  static final _unc = RegExp(r'''\\\\[^\r\n<>"']+''');
  static final _posix = RegExp(r'''(^|[\s=(\[{,:"'])/(?!/)[^\r\n<>"']+''');
  static final _encodedPath = RegExp(
    r'''(?:file%3a|[a-z]%3a(?:%5c|%2f)|%5c%5c|(?:^|(?<=[\s=(\[{,:"']))%2f)[^\r\n<>"']+''',
    caseSensitive: false,
  );
  static final _opaqueAssignment = RegExp(
    r'''\b(?:[a-z_]*secret[_ -]?(?:ref(?:erence)?|id)|credential[_ -]?(?:ref(?:erence)?|id))\s*[:=]\s*[^,;\r\n}\]]+''',
    caseSensitive: false,
  );
  static final _imageData = RegExp(
    r'''data:image/[^\s<>"']+''',
    caseSensitive: false,
  );

  String text(String input) {
    var result = redactor.redactText(input);
    result = result.replaceAll(_imageData, excluded);
    // Do this before file path removal so URL paths are not mistaken for IO.
    final urls = <String>[];
    result = result.replaceAllMapped(_url, (match) {
      final raw = match[0]!;
      String safeUrl = SecretRedactor.unavailable;
      try {
        final base = raw.split(RegExp(r'[?#]')).first;
        final uri = Uri.parse(base);
        if ((uri.scheme == 'http' || uri.scheme == 'https') &&
            uri.host.isNotEmpty &&
            uri.userInfo.isEmpty &&
            !base.contains(SecretRedactor.hidden) &&
            !base.contains('\\')) {
          safeUrl = Uri(
            scheme: uri.scheme,
            host: uri.host,
            port: uri.hasPort ? uri.port : null,
            path: uri.path,
          ).toString();
        }
      } catch (_) {
        // There is no raw string fallback for malformed URLs.
      }
      urls.add(safeUrl);
      return '\u0000${urls.length - 1}\u0000';
    });
    result = result.replaceAll(_fileUri, excluded);
    result = result.replaceAll(_encodedPath, excluded);
    result = result.replaceAll(_windows, excluded);
    result = result.replaceAll(_unc, excluded);
    result = result.replaceAllMapped(_posix, (match) => '${match[1]}$excluded');
    result = result.replaceAll(_opaqueAssignment, excluded);
    result = result.replaceAllMapped(RegExp(r'\x00([0-9]+)\x00'), (match) {
      final index = int.tryParse(match[1]!);
      return index != null && index < urls.length
          ? urls[index]
          : SecretRedactor.unavailable;
    });
    // Invalid scalar input cannot be safely serialized as supplied.
    for (var index = 0; index < result.length; index++) {
      final unit = result.codeUnitAt(index);
      if (unit >= 0xd800 && unit <= 0xdbff) {
        if (++index >= result.length) return SecretRedactor.unavailable;
        final low = result.codeUnitAt(index);
        if (low < 0xdc00 || low > 0xdfff) return SecretRedactor.unavailable;
      } else if (unit >= 0xdc00 && unit <= 0xdfff) {
        return SecretRedactor.unavailable;
      }
    }
    return _truncate(result, _maxStringScalars);
  }

  DiagnosticEvent event(DiagnosticEvent input) {
    if (redactor.redactText(input.id) != input.id ||
        redactor.redactText(input.code) != input.code) {
      throw const DiagnosticFailure();
    }
    String? association(String? value) =>
        value == null || redactor.redactText(value) != value ? null : value;
    return DiagnosticEvent(
      id: input.id,
      occurredAt: input.occurredAt,
      kind: input.kind,
      level: input.level,
      code: input.code,
      summary: _truncate(text(input.summary), 2048),
      recoveryAction: _truncate(text(input.recoveryAction), 2048),
      entityId: association(input.entityId),
      batchId: association(input.batchId),
      attemptId: association(input.attemptId),
      details: sanitize(input.details),
    );
  }

  static String _truncate(String input, int max) {
    final scalars = input.runes;
    if (scalars.length <= max) return input;
    return '${String.fromCharCodes(scalars.take(max - 1))}…';
  }
}
