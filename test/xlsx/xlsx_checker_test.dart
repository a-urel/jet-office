import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

import '../support/xlsx_checker.dart';

/// A small valid workbook: two sheets, shared strings, styled cells (one
/// with a custom number format) and a formula.
Uint8List _good() {
  final XlsxWriter book = XlsxWriter();
  book.addSheet('Data')
    ..row(<Object?>['a', 'b', 1])
    ..row(<Object?>['a', 2.5, const XlsxDate(2026, 10, 24)]);
  book.addSheet('Other').row(<Object?>[
    'c',
    const XlsxFormula('1+1'),
    const XlsxCell(1.5, style: XlsxStyle(numFmt: XlsxNumFmt.custom('0.000'))),
  ]);
  return book.close().bytes;
}

/// Rebuilds [source] with each part in [edit] replaced by the function's
/// result (a null result drops the part) and the parts in [add] appended.
Uint8List _rebuild(
  Uint8List source, {
  Map<String, String? Function(String xml)> edit =
      const <String, String? Function(String)>{},
  Map<String, String> add = const <String, String>{},
}) {
  final Archive input = ZipDecoder().decodeBytes(source);
  final Archive output = Archive();
  for (final ArchiveFile file in input.files) {
    final String? Function(String)? change = edit[file.name];
    if (change == null) {
      output.add(ArchiveFile.bytes(file.name, file.content));
      continue;
    }
    final String? text = change(utf8.decode(file.content));
    if (text != null) {
      output.add(ArchiveFile.bytes(file.name, utf8.encode(text)));
    }
  }
  add.forEach((String name, String text) {
    output.add(ArchiveFile.bytes(name, utf8.encode(text)));
  });
  return Uint8List.fromList(ZipEncoder().encode(output));
}

Uint8List _broken(String part, String Function(String xml) change) =>
    _rebuild(_good(), edit: <String, String? Function(String)>{part: change});

void _expectRule(Uint8List bytes, int rule) {
  final List<String> violations = checkXlsx(bytes);
  expect(
    violations.where((String v) => v.startsWith('rule $rule:')),
    isNotEmpty,
    reason: 'violations: $violations',
  );
}

const String _sheet1 = 'xl/worksheets/sheet1.xml';
const String _sheet2 = 'xl/worksheets/sheet2.xml';

void main() {
  test('a valid workbook has no violations', () {
    expect(checkXlsx(_good()), isEmpty);
  });

  group('rule 1: well-formed XML', () {
    test('a part that is not well-formed', () {
      _expectRule(
        _broken(_sheet1, (String x) => x.replaceAll('</row>', '')),
        1,
      );
    });
    test('a .rels part that is not well-formed', () {
      _expectRule(
        _broken('_rels/.rels', (String x) => x.substring(0, x.length - 5)),
        1,
      );
    });
  });

  group('rule 2: relationship targets', () {
    test('a target that does not exist', () {
      _expectRule(
        _broken(
          'xl/_rels/workbook.xml.rels',
          (String x) => x.replaceFirst('styles.xml', 'nothere.xml'),
        ),
        2,
      );
    });
    test('a leading slash is absolute', () {
      final Uint8List ok = _broken(
        'xl/_rels/workbook.xml.rels',
        (String x) => x.replaceFirst('"styles.xml"', '"/xl/styles.xml"'),
      );
      expect(checkXlsx(ok), isEmpty);
      _expectRule(
        _broken(
          'xl/_rels/workbook.xml.rels',
          (String x) => x.replaceFirst('"styles.xml"', '"/styles.xml"'),
        ),
        2,
      );
    });
  });

  group('rule 3: content types', () {
    test('a part with no content type', () {
      _expectRule(
        _rebuild(_good(), add: <String, String>{'xl/extra.bin': 'x'}),
        3,
      );
    });
    test('an override naming a missing part', () {
      _expectRule(
        _broken(
          '[Content_Types].xml',
          (String x) => x.replaceFirst(
            '</Types>',
            '<Override PartName="/xl/ghost.xml" ContentType="a/b"/></Types>',
          ),
        ),
        3,
      );
    });
  });

  group('rule 4: shared-string counts', () {
    test('count differs from the number of string cells', () {
      _expectRule(
        _broken(
          'xl/sharedStrings.xml',
          (String x) => x.replaceFirst(RegExp(r' count="\d+"'), ' count="99"'),
        ),
        4,
      );
    });
    test('uniqueCount differs from the number of si', () {
      _expectRule(
        _broken(
          'xl/sharedStrings.xml',
          (String x) =>
              x.replaceFirst(RegExp(r' uniqueCount="\d+"'), ' uniqueCount="9"'),
        ),
        4,
      );
    });
  });

  test('rule 5: a string index past uniqueCount', () {
    _expectRule(
      _broken(
        _sheet1,
        (String x) => x.replaceFirst('t="s"><v>0</v>', 't="s"><v>7</v>'),
      ),
      5,
    );
  });

  group('rule 6: sheet names', () {
    test('case-insensitive duplicates, Turkish included', () {
      _expectRule(
        _broken(
          'xl/workbook.xml',
          (String x) => x.replaceFirst('name="Other"', 'name="DATA"'),
        ),
        6,
      );
      _expectRule(
        _broken(
          'xl/workbook.xml',
          (String x) => x
              .replaceFirst('name="Data"', 'name="liste"')
              .replaceFirst('name="Other"', 'name="LİSTE"'),
        ),
        6,
      );
    });
    test('decodes _xHHHH_ before comparing: A and an unescaped _x0041_', () {
      _expectRule(
        _broken(
          'xl/workbook.xml',
          (String x) => x
              .replaceFirst('name="Data"', 'name="A"')
              .replaceFirst('name="Other"', 'name="_x0041_"'),
        ),
        6,
      );
    });
    test('an escaped _x005F_x0041_ next to A is not a duplicate', () {
      final List<String> violations = checkXlsx(
        _broken(
          'xl/workbook.xml',
          (String x) => x
              .replaceFirst('name="Data"', 'name="A"')
              .replaceFirst('name="Other"', 'name="_x005F_x0041_"'),
        ),
      );
      expect(violations, isEmpty);
    });
    test('the length is that of the decoded name', () {
      final String escaped = '_x005F_x0041_${'a' * 24}'; // decodes to 31
      expect(
        checkXlsx(
          _broken(
            'xl/workbook.xml',
            (String x) => x.replaceFirst('name="Other"', 'name="$escaped"'),
          ),
        ),
        isEmpty,
      );
      _expectRule(
        _broken(
          'xl/workbook.xml',
          (String x) => x.replaceFirst('name="Other"', 'name="${escaped}a"'),
        ),
        6,
      );
    });
    test('a forbidden character written as an escape is found', () {
      _expectRule(
        _broken(
          'xl/workbook.xml',
          (String x) => x.replaceFirst('name="Other"', 'name="a_x003A_b"'),
        ),
        6,
      );
    });
    test('longer than 31 characters', () {
      _expectRule(
        _broken(
          'xl/workbook.xml',
          (String x) => x.replaceFirst('name="Other"', 'name="${'x' * 32}"'),
        ),
        6,
      );
    });
    test('the reserved name History, in any case', () {
      _expectRule(
        _broken(
          'xl/workbook.xml',
          (String x) => x.replaceFirst('name="Other"', 'name="hISTORY"'),
        ),
        6,
      );
    });
    test('a leading or trailing apostrophe', () {
      _expectRule(
        _broken(
          'xl/workbook.xml',
          (String x) => x.replaceFirst('name="Other"', "name=\"'Other\""),
        ),
        6,
      );
      _expectRule(
        _broken(
          'xl/workbook.xml',
          (String x) => x.replaceFirst('name="Other"', "name=\"Other'\""),
        ),
        6,
      );
    });
    test('a forbidden character', () {
      _expectRule(
        _broken(
          'xl/workbook.xml',
          (String x) => x.replaceFirst('name="Other"', 'name="a:b"'),
        ),
        6,
      );
    });
  });

  group('rule 7: activeTab', () {
    test('past the last sheet', () {
      _expectRule(
        _broken(
          'xl/workbook.xml',
          (String x) => x.replaceFirst('activeTab="0"', 'activeTab="2"'),
        ),
        7,
      );
    });
    test('not a number', () {
      _expectRule(
        _broken(
          'xl/workbook.xml',
          (String x) => x.replaceFirst('activeTab="0"', 'activeTab="x"'),
        ),
        7,
      );
    });
  });

  test('rule 8: a style index past cellXfs', () {
    _expectRule(
      _broken(
        _sheet1,
        (String x) =>
            x.replaceFirst(RegExp(r'<c r="C2" s="\d+"'), '<c r="C2" s="99"'),
      ),
      8,
    );
  });

  group('rule 9: cell references', () {
    test('out of order inside a row', () {
      _expectRule(
        _broken(
          _sheet1,
          (String x) => x
              .replaceFirst('r="A1"', 'r="TMP"')
              .replaceFirst('r="B1"', 'r="A1"')
              .replaceFirst('r="TMP"', 'r="B1"'),
        ),
        9,
      );
    });
    test('a repeated reference', () {
      _expectRule(
        _broken(_sheet1, (String x) => x.replaceFirst('r="B1"', 'r="A1"')),
        9,
      );
    });
    test('a reference on another row', () {
      _expectRule(
        _broken(_sheet1, (String x) => x.replaceFirst('r="A1"', 'r="A2"')),
        9,
      );
    });
  });

  group('rule 10: formula text', () {
    test('an empty formula', () {
      _expectRule(
        _broken(_sheet2, (String x) => x.replaceFirst('<f>1+1</f>', '<f></f>')),
        10,
      );
      _expectRule(
        _broken(_sheet2, (String x) => x.replaceFirst('<f>1+1</f>', '<f/>')),
        10,
      );
    });
    test('a formula longer than 8,192 characters', () {
      final String max = '1+' * 4095 + '11';
      expect(
        checkXlsx(
          _broken(
            _sheet2,
            (String x) => x.replaceFirst('<f>1+1</f>', '<f>$max</f>'),
          ),
        ),
        isEmpty,
      );
      _expectRule(
        _broken(
          _sheet2,
          (String x) => x.replaceFirst('<f>1+1</f>', '<f>${max}1</f>'),
        ),
        10,
      );
    });
  });

  group('rule 11: row numbers', () {
    test('a repeated row number', () {
      _expectRule(
        _broken(
          _sheet1,
          (String x) => x.replaceFirst('<row r="2"', '<row r="1"'),
        ),
        11,
      );
    });
    test('a row number lower than the one before', () {
      _expectRule(
        _broken(
          _sheet1,
          (String x) => x
              .replaceFirst('<row r="1"', '<row r="TMP"')
              .replaceFirst('<row r="2"', '<row r="1"')
              .replaceFirst('<row r="TMP"', '<row r="2"'),
        ),
        11,
      );
    });
  });

  test('rule 12: cellXfs count differs from its xf children', () {
    _expectRule(
      _broken(
        'xl/styles.xml',
        (String x) => x.replaceFirstMapped(
          RegExp(r'<cellXfs count="(\d+)"'),
          (Match m) => '<cellXfs count="${int.parse(m.group(1)!) + 1}"',
        ),
      ),
      12,
    );
  });

  test('rule 13: an xf uses a custom number format that is not declared', () {
    _expectRule(
      _broken(
        'xl/styles.xml',
        (String x) =>
            x.replaceFirst('<numFmt numFmtId="164"', '<numFmt numFmtId="165"'),
      ),
      13,
    );
  });
}
