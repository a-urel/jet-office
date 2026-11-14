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

  test('a long run of open braces scans in linear time', () {
    final s = '{' * 100000;
    final watch = Stopwatch()..start();
    final m = scanTags(s);
    watch.stop();
    expect(m, isNotEmpty);
    expect(watch.elapsedMilliseconds, lessThan(1000));
  });
  test('a long run of open braces then a close scans in linear time', () {
    final s = '${'{' * 50000}x${'}' * 50000}';
    final watch = Stopwatch()..start();
    scanTags(s);
    watch.stop();
    expect(watch.elapsedMilliseconds, lessThan(1000));
  });
}
