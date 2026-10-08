import 'package:flutter_test/flutter_test.dart';
import 'package:imagehost/features/upload/domain/link_format.dart';

void main() {
  test(
    'UT-069 four ordinary templates preserve escaped query and Unicode targets',
    () {
      const url = 'https://example.test/图片/a%20b(1).png?q=a&x=%22x%22';
      const name = '"one" (two) [three]\nfour <&> \\';
      final values = {
        for (final format in UploadLinkFormat.values)
          format: formatOrdinaryLink(
            ordinaryUrl: url,
            name: name,
            format: format,
          ),
      };
      final safeUrl = Uri.parse(url).toString();
      expect(values[UploadLinkFormat.url], safeUrl);
      final html = values[UploadLinkFormat.html]!;
      expect(html, contains('q=a&amp;x=%22x%22'));
      expect(html, contains('&quot;one&quot;'));
      expect(html, contains('&lt;&amp;&gt;'));
      expect(html, isNot(contains('%2520')));
      final markdown = values[UploadLinkFormat.markdown]!;
      expect(markdown, startsWith('!["one" (two) \\[three\\] four'));
      expect(markdown, contains('%281%29.png'));
      expect(markdown, isNot(contains('\n')));
      final bbcode = values[UploadLinkFormat.bbcode]!;
      expect(bbcode, '[img]$safeUrl[/img]');
      expect(
        Uri.decodeComponent(
          Uri.parse(
            markdown.substring(markdown.indexOf('](') + 2, markdown.length - 1),
          ).path,
        ),
        Uri.decodeComponent(Uri.parse(url).path),
      );
    },
  );
  test(
    'UT-069 dangerous/control/management URLs cannot enter ordinary templates',
    () {
      for (final url in [
        '',
        'javascript:alert(1)',
        'file:///a.png',
        'data:image/png;base64,a',
        'https://user:secret@example.test/a',
        'https://example.test/a\nb.png',
        'https://example.test/a%0Ab.png',
        'https://example.test/a\\b.png',
        'https://example.test/a?api_key=secret',
        'https://ibb.co/identity/0123456789abcdef',
      ]) {
        for (final format in UploadLinkFormat.values) {
          expect(
            () => formatOrdinaryLink(
              ordinaryUrl: url,
              name: 'name',
              format: format,
            ),
            throwsA(isA<UnsafeOrdinaryLink>()),
          );
        }
      }
    },
  );
  test('UT-070 confirms caller scope/order, exact formatting dedupe and partial feedback', () {
    final input = [
      (url: 'https://example.test/B.png', name: 'B'),
      (url: 'https://example.test/A.png', name: 'A'),
      (url: 'https://example.test/B.png', name: 'B'),
      (url: null, name: 'C'),
      (url: 'javascript:bad', name: 'unsafe'),
    ];
    final first = formatOrdinaryLinks(input, UploadLinkFormat.url);
    final second = formatOrdinaryLinks(input, UploadLinkFormat.url);
    expect(
      first.text,
      'https://example.test/B.png\nhttps://example.test/A.png',
    );
    expect(second.text, first.text);
    expect(first.copied, 2);
    expect(first.skipped, 2);
    expect(first.duplicates, 1);
  });
}
