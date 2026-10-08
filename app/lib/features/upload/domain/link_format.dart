enum UploadLinkFormat { url, markdown, html, bbcode }

final class UnsafeOrdinaryLink implements Exception {
  const UnsafeOrdinaryLink();
  @override
  String toString() => '普通链接未通过安全校验，未复制。';
}

/// Only accepts ordinary links; protected management values never call this
/// API. Keeps URI escapes intact, including query separators and Unicode.
String formatOrdinaryLink({
  required String ordinaryUrl,
  required String name,
  required UploadLinkFormat format,
}) {
  final uri = _ordinaryUri(ordinaryUrl);
  final url = uri.toString();
  final label = name.replaceAll(RegExp(r'[\x00-\x20\x7f\u2028\u2029]+'), ' ');
  return switch (format) {
    UploadLinkFormat.url => url,
    UploadLinkFormat.markdown =>
      '![${label.replaceAllMapped(RegExp(r'[\\\[\]*_`]'), (m) => '\\${m[0]}')}]'
          '(${url.replaceAll('(', '%28').replaceAll(')', '%29')})',
    UploadLinkFormat.html => '<img src="${_html(url)}" alt="${_html(label)}">',
    UploadLinkFormat.bbcode =>
      '[img]${url.replaceAll('[', '%5B').replaceAll(']', '%5D')}[/img]',
  };
}

Uri _ordinaryUri(String value) {
  try {
    if (value.isEmpty ||
        value.length > 8192 ||
        RegExp(r'[\x00-\x20\x7f\\]').hasMatch(value)) {
      throw const UnsafeOrdinaryLink();
    }
    final uri = Uri.parse(value);
    if (!{'http', 'https'}.contains(uri.scheme) ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(Uri.decodeFull(uri.toString()))) {
      throw const UnsafeOrdinaryLink();
    }
    // Management URLs are not ordinary image links, even though HTTPS itself
    // is safe. This supplements the provider/result boundary, not replaces it.
    final sensitiveFields = {
      'key',
      'api_key',
      'userhash',
      'token',
      'delete_url',
      'delete',
      'secret',
    };
    if (uri.queryParameters.keys.any(
          (key) => sensitiveFields.contains(key.toLowerCase()),
        ) ||
        uri.host == 'ibb.co' && uri.pathSegments.length > 1) {
      throw const UnsafeOrdinaryLink();
    }
    return uri;
  } on UnsafeOrdinaryLink {
    rethrow;
  } catch (_) {
    throw const UnsafeOrdinaryLink();
  }
}

String _html(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

final class FormattedLinkBatch {
  const FormattedLinkBatch(
    this.text,
    this.copied,
    this.skipped,
    this.duplicates,
  );
  final String text;
  final int copied, skipped, duplicates;
}

/// The caller supplies the explicitly confirmed order and visible scope. No
/// repository search or hidden result is added by formatting or local copying.
FormattedLinkBatch formatOrdinaryLinks(
  Iterable<({String? url, String name})> confirmedOrder,
  UploadLinkFormat format,
) {
  final unique = <String>{};
  var skipped = 0, duplicates = 0;
  for (final item in confirmedOrder) {
    if (item.url == null) {
      skipped++;
      continue;
    }
    try {
      final text = formatOrdinaryLink(
        ordinaryUrl: item.url!,
        name: item.name,
        format: format,
      );
      if (!unique.add(text)) duplicates++;
    } on UnsafeOrdinaryLink {
      skipped++;
    }
  }
  return FormattedLinkBatch(
    unique.join('\n'),
    unique.length,
    skipped,
    duplicates,
  );
}
