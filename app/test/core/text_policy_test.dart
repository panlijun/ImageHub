import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imagehost/core/text_policy.dart';
import 'package:imagehost/core/unicode_case_folding.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;

void main() {
  group('UT-014 标签连续输入与规范化', () {
    test('trim/NFC 去重且保留首次显示名与输入顺序', () {
      expect(TextPolicy.tags([' A ', 'a', 'e\u0301', 'É', '工作']), [
        'A',
        'é',
        '工作',
      ]);
    });

    test('默认完整折叠包含 Σ/σ/ς 和 ß/SS，并排除 Turkic T', () {
      expect(TextPolicy.tags(['Σ', 'σ', 'ς', 'ß', 'SS']), ['Σ', 'ß']);
      expect(TextPolicy.key('I'), 'i');
      expect(TextPolicy.key('İ'), 'i\u0307');
      expect(TextPolicy.key('ı'), 'ı');
      expect(TextPolicy.key('Straße'), TextPolicy.key('STRASSE'));
      expect(TextPolicy.key('É'), TextPolicy.key('e\u0301'));
    });

    test('只在提交时解析逗号/分号/换行且不改变编辑草稿', () {
      var draft = '';
      for (final character in ['A', ',', ' ', 'b', '，', 'c', ';']) {
        draft += character;
        final beforeSubmission = draft;
        TextPolicy.parseTags(draft);
        expect(draft, beforeSubmission);
      }
      expect(draft, 'A, b，c;');
      expect(TextPolicy.parseTags(draft), ['A', 'b', 'c']);
      expect(TextPolicy.parseTags('a,b，c;d；e\nf\r\ng'), [
        'a',
        'b',
        'c',
        'd',
        'e',
        'f',
        'g',
      ]);
      expect(TextPolicy.parseTags(' ,，;；\r\n '), isEmpty);
    });

    test('固定官方全部 C/F 数据与纯 Dart 映射一致，折叠后再 NFC', () {
      final source = File('tool/unicode/CaseFolding-17.0.0.txt');
      final bytes = source.readAsBytesSync();
      expect(sha256.convert(bytes).toString(), unicodeCaseFoldingSourceSha256);
      var mappings = 0;
      for (final line in const LineSplitter().convert(utf8.decode(bytes))) {
        final record = line.split('#').first.trim();
        if (record.isEmpty) continue;
        final fields = record.split(';').map((value) => value.trim()).toList();
        if (fields[1] != 'C' && fields[1] != 'F') continue;
        final input = String.fromCharCode(int.parse(fields[0], radix: 16));
        final expected = String.fromCharCodes(
          fields[2].split(RegExp(r'\s+')).map((v) => int.parse(v, radix: 16)),
        );
        expect(unicodeDefaultCaseFold(input), expected, reason: fields[0]);
        expect(
          TextPolicy.key(input),
          unorm.nfc(unicodeDefaultCaseFold(unorm.nfc(input))),
        );
        mappings++;
      }
      expect(mappings, greaterThan(1500));
      expect(unicodeDefaultCaseFold('工作🙂'), '工作🙂');
    });
  });

  group('UT-015 标签数量与名称边界', () {
    test('1/64 Unicode scalar 合法，空白和65拒绝且原因具体', () {
      expect(TextPolicy.normalizeName('x'), 'x');
      expect(TextPolicy.normalizeName('🙂' * 64), '🙂' * 64);
      expect(TextPolicy.normalizeName('e\u0301' * 64), 'é' * 64);
      expect(
        () => TextPolicy.normalizeName('🙂' * 65),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'reason',
            contains('64'),
          ),
        ),
      );
      expect(
        () => TextPolicy.normalizeName('  \t\n '),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'reason',
            contains('不能为空'),
          ),
        ),
      );
    });

    test('组合 emoji 按 scalar 计数而非 UTF16 或 grapheme', () {
      const family = '👨‍👩‍👧‍👦';
      expect(family.runes.length, 7);
      expect(TextPolicy.normalizeName(family * 9), family * 9);
      expect(
        () => TextPolicy.normalizeName(family * 10),
        throwsFormatException,
      );
    });

    test('去重后50合法，51拒绝，不修改原集合或截断输入', () {
      final original = List.generate(50, (i) => 'Tag$i');
      final snapshot = List<String>.of(original);
      expect(TextPolicy.tags([...original, 'TAG0']), original);
      final overLimit = [...original, 'Tag50'];
      expect(
        () => TextPolicy.tags(overLimit),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'reason',
            contains('50'),
          ),
        ),
      );
      expect(original, snapshot);
      expect(overLimit.length, 51);
      expect(() => TextPolicy.tags(['工作', ' ']), throwsFormatException);
      expect(original, snapshot);
    });

    test('分类调用共同名字校验与完整折叠身份键', () {
      expect(TextPolicy.normalizeName('  Straße  '), 'Straße');
      expect(TextPolicy.key(' Straße '), TextPolicy.key('STRASSE'));
      expect(() => TextPolicy.normalizeName('分类' * 33), throwsFormatException);
    });
  });
}
