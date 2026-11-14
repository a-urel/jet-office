// Tests the template tag scanner: the grammar of `{{...}}` tags, malformed
// findings and linear running time. Pure Dart, so it runs on the web too.
import 'package:jet_office/src/docx/template/tag_scanner.dart';
import 'package:test/test.dart';

void _tag(
  String input,
  int start,
  int end,
  TagKind kind,
  List<String> path, [
  String? format,
]) {
  final matches = scanTags(input);
  expect(matches, hasLength(1), reason: input);
  _expectTag(matches.single, input, start, end, kind, path, format);
}

void _expectTag(
  TagMatch m,
  String input,
  int start,
  int end,
  TagKind kind,
  List<String> path,
  String? format,
) {
  expect(m.start, start);
  expect(m.end, end);
  expect(m.text, input.substring(start, end));
  expect(m.tag, isNotNull, reason: input);
  expect(m.tag!.kind, kind);
  expect(m.tag!.path, path);
  expect(m.tag!.format, format);
}

void _malformed(TagMatch m, String input, int start, int end) {
  expect(m.start, start);
  expect(m.end, end);
  expect(m.tag, isNull);
  expect(m.text, input.substring(start, end));
}

void main() {
  test('a dotted value tag', () {
    _tag('Sayın {{musteri.unvan}},', 6, 23, TagKind.value, [
      'musteri',
      'unvan',
    ]);
  });
  test('a value tag with a format', () {
    _tag('{{ tutar : #,##0.00 ₺ }}', 0, 24, TagKind.value, [
      'tutar',
    ], '#,##0.00 ₺');
  });
  test('a date format', () {
    _tag('{{tarih:dd.mm.yyyy}}', 0, 20, TagKind.value, ['tarih'], 'dd.mm.yyyy');
  });
  test('Unicode segments', () {
    _tag('{{müşteri.adı}}', 0, 15, TagKind.value, ['müşteri', 'adı']);
  });
  test(
    'section',
    () => _tag('{{#kalemler}}', 0, 13, TagKind.section, ['kalemler']),
  );
  test('section with a space after the sigil', () {
    _tag('{{# kalemler }}', 0, 15, TagKind.section, ['kalemler']);
  });
  test('inverted section', () {
    _tag('{{^odendi}}', 0, 11, TagKind.invertedSection, ['odendi']);
  });
  test('section end', () {
    _tag('{{/kalemler}}', 0, 13, TagKind.sectionEnd, ['kalemler']);
  });
  test('current', () => _tag('{{.}}', 0, 5, TagKind.current, []));
  test('current with a format', () {
    _tag('{{.:0.00}}', 0, 10, TagKind.current, [], '0.00');
  });
  test('spaces around a body', () {
    _tag('{{ ad }}', 0, 8, TagKind.value, ['ad']);
  });
  test('no-break spaces count as spaces', () {
    _tag('{{ ad }}', 0, 8, TagKind.value, ['ad']);
  });

  for (final input in [
    '{{ }}',
    '{{a b}}',
    '{{a:}}',
    '{{#a:x}}',
    '{{a..b}}',
    '{{.a}}',
    '{{a\u{FFFC}b}}',
  ]) {
    test('malformed ${input.replaceAll('\u{FFFC}', '<FFFC>')}', () {
      final matches = scanTags(input);
      expect(matches, hasLength(1));
      _malformed(matches.single, input, 0, input.length);
    });
  }

  test('an unclosed tag', () {
    final m = scanTags('{{x');
    expect(m, hasLength(1));
    _malformed(m.single, '{{x', 0, 3);
  });
  test('an outer tag broken by an inner one', () {
    const s = '{{a {{b}}';
    final m = scanTags(s);
    expect(m, hasLength(2));
    _malformed(m[0], s, 0, 4);
    _expectTag(m[1], s, 4, 9, TagKind.value, ['b'], null);
  });
  test('triple braces', () {
    const s = '{{{x}}}';
    final m = scanTags(s);
    expect(m, hasLength(2));
    _malformed(m[0], s, 0, 1);
    _expectTag(m[1], s, 1, 6, TagKind.value, ['x'], null);
  });
  test('no tags', () {
    expect(scanTags('a }} b'), isEmpty);
    expect(scanTags('no tags'), isEmpty);
    expect(scanTags(''), isEmpty);
  });
  test('adjacent tags', () {
    const s = '{{a}}{{b}}';
    final m = scanTags(s);
    expect(m, hasLength(2));
    _expectTag(m[0], s, 0, 5, TagKind.value, ['a'], null);
    _expectTag(m[1], s, 5, 10, TagKind.value, ['b'], null);
  });
  test('a format ends at the first closing braces', () {
    _tag('{{a:#,##0}}x}}', 0, 11, TagKind.value, ['a'], '#,##0');
  });

  test('parseTagBody trims its body', () {
    final t = parseTagBody('  a.b ');
    expect(t, isNotNull);
    expect(t!.kind, TagKind.value);
    expect(t.path, ['a', 'b']);
    expect(parseTagBody('a b'), isNull);
  });

  // The two tests below count the characters the scan's searches read
  // instead of timing it: 1 s bounds on runs of about 10 and 5 ms could fail
  // on a busy machine. The scan reads each character a few times (5 per
  // character on the first input and 3.5 on the second); one that searches
  // for `}}` again from every `{{`, without keeping the last one found, reads
  // about n * n / 2 on the first and n * n / 8 on the second (12.6 s and
  // 3.3 s), which [_expectLinearScan] stops at its bound.
  test('a long run of open braces scans in linear time', () {
    final String s = '{' * 100000;
    expect(_expectLinearScan(s), hasLength(99999));
  });
  test('a long run of open braces then a close scans in linear time', () {
    final String s = '${'{' * 50000}x${'}' * 50000}';
    expect(_expectLinearScan(s), hasLength(49999));
  });
}

/// Scans [text] and returns what [scanTags] found, after checking that its
/// searches read at most 8 characters per character of [text].
///
/// The scan stops with a failure as soon as the reads pass that bound, so a
/// scan in quadratic time fails at once instead of running for minutes.
List<TagMatch> _expectLinearScan(String text) {
  final int bound = 8 * text.length;
  int read = 0;
  final List<TagMatch> matches = scanTags(
    text,
    onSearch: (int start, int end) {
      read += end - start;
      if (read > bound) {
        fail('the scan read more than $bound characters of ${text.length}');
      }
    },
  );
  return matches;
}
