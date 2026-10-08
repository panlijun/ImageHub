import 'package:unorm_dart/unorm_dart.dart' as unorm;

import 'unicode_case_folding.dart';

/// Shared, versioned text rules. Apply these on submission, never while typing.
abstract final class TextPolicy {
  static const unicodeVersion = unicodeCaseFoldingVersion;
  static const maxNameScalars = 64;
  static const maxTags = 50;

  /// Display name: trim and NFC, with a Unicode scalar (not grapheme) limit.
  static String normalizeName(String input) {
    final name = unorm.nfc(input.trim());
    final count = name.runes.length;
    if (count == 0) {
      throw const FormatException('名称不能为空。');
    }
    if (count > maxNameScalars) {
      throw const FormatException('名称不能超过 64 个 Unicode 字符。');
    }
    return name;
  }

  /// Identity/search key: NFC → Unicode 17 default full case folding → NFC.
  /// Length validation is separate so search input is not a display name.
  static String key(String input) =>
      unorm.nfc(unicodeDefaultCaseFold(unorm.nfc(input.trim())));

  /// Validate all names and keep the first display spelling of each identity.
  /// Nothing is applied to the caller's values if any entry is invalid.
  static List<String> tags(Iterable<String> input) {
    final result = <String>[];
    final identities = <String>{};
    for (final value in input) {
      final name = normalizeName(value);
      if (!identities.add(key(name))) continue;
      result.add(name);
      if (result.length > maxTags) {
        throw const FormatException('每项最多允许 50 个标签。');
      }
    }
    return List<String>.unmodifiable(result);
  }

  /// Parse a submitted draft, allowing trailing/repeated separators to remain
  /// untouched in the editor until submission. Blank segments add no tag.
  static List<String> parseTags(String draft) => tags(
    draft.split(RegExp(r'[,，;；\r\n]')).where((part) => part.trim().isNotEmpty),
  );
}
