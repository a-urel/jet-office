import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

import '../support/xlsx_checker.dart';

/// A small valid workbook: two sheets, shared strings, styled cells (one
/// with a custom number format, one with a font, fill and border), a
/// formula, and on the first sheet two styled, grouped columns and grouped
/// rows with heights.
Uint8List _good() {
  final XlsxWriter book = XlsxWriter();
  book.addSheet('Data')
    ..columns(const <XlsxColumn?>[
      XlsxColumn(width: 12, style: XlsxStyle(font: XlsxFont(bold: true))),
      XlsxColumn(outlineLevel: 1),
    ])
    ..row(<Object?>['a', 'b', 1], height: 20, outlineLevel: 1)
    ..row(<Object?>['a', 2.5, const XlsxDate(2026, 10, 24)]);
  book.addSheet('Other').row(<Object?>[
    'c',
    const XlsxFormula('1+1'),
    const XlsxCell(1.5, style: XlsxStyle(numFmt: XlsxNumFmt.custom('0.000'))),
    const XlsxCell(
      7,
      style: XlsxStyle(
        font: XlsxFont(bold: true),
        fill: XlsxFill.solid(XlsxColor.rgb(0xFFFF00)),
        border: XlsxBorder.all(XlsxBorderSide(style: XlsxBorderStyle.thin)),
      ),
    ),
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

  test(
    'only a folder named exactly _rels holds relationships of its parent',
    () {
      // `xl/a_rels/` is not a `_rels` folder, so its targets resolve from
      // that folder itself.
      final Uint8List bytes = _rebuild(
        _good(),
        add: <String, String>{
          'xl/a_rels/x.xml.rels':
              '<Relationships xmlns="http://schemas.openxmlformats.org/package/'
              '2006/relationships"><Relationship Id="rId1" Type="t" '
              'Target="../workbook.xml"/></Relationships>',
        },
      );
      expect(checkXlsx(bytes), isEmpty);
    },
  );

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

  test('rule 5: a string cell when there is no sharedStrings part', () {
    _expectRule(
      _rebuild(
        _good(),
        edit: <String, String? Function(String)>{
          'xl/sharedStrings.xml': (String x) => null,
        },
      ),
      5,
    );
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
    test('a leading apostrophe', () {
      _expectRule(
        _broken(
          'xl/workbook.xml',
          (String x) => x.replaceFirst('name="Other"', "name=\"'Other\""),
        ),
        6,
      );
    });
    test('a trailing apostrophe', () {
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
    test('the length is that of the decoded formula', () {
      // `"_x005F_x0041_"` decodes to `"_x0041_"`, 9 units (decision 0005).
      final String max = '"_x005F_x0041_"&${'1' * 8182}';
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

  group('rule 14: style tables', () {
    Uint8List styles(String Function(String xml) change) =>
        _broken('xl/styles.xml', change);
    String bumpCount(String xml, String table) => xml.replaceFirstMapped(
      RegExp('<$table count="(\\d+)"'),
      (Match m) => '<$table count="${int.parse(m.group(1)!) + 1}"',
    );
    String lastXf(String xml, String attribute, String value) {
      final int xfs = xml.indexOf('<cellXfs');
      final int last = xml.lastIndexOf('<xf ', xml.indexOf('</cellXfs>'));
      expect(last, greaterThan(xfs));
      return xml.substring(0, last) +
          xml
              .substring(last)
              .replaceFirst(RegExp('$attribute="\\d+"'), '$attribute="$value"');
    }

    for (final String table in <String>[
      'fonts',
      'fills',
      'borders',
      'cellStyleXfs',
    ]) {
      test('$table count off by one', () {
        _expectRule(styles((String x) => bumpCount(x, table)), 14);
      });
    }
    test('the good workbook uses its font, fill and border tables', () {
      final String xml = utf8.decode(
        ZipDecoder()
            .decodeBytes(_good())
            .files
            .firstWhere((ArchiveFile f) => f.name == 'xl/styles.xml')
            .content,
      );
      expect(xml, contains('<fonts count="2">'));
      expect(xml, contains('<fills count="3">'));
      expect(xml, contains('<borders count="2">'));
    });
    test('a fontId past the font table', () {
      _expectRule(styles((String x) => lastXf(x, 'fontId', '2')), 14);
    });
    test('a fillId past the fill table', () {
      _expectRule(styles((String x) => lastXf(x, 'fillId', '3')), 14);
    });
    test('a borderId past the border table', () {
      _expectRule(styles((String x) => lastXf(x, 'borderId', '2')), 14);
    });
    test('fill 1 is not gray125', () {
      _expectRule(
        styles(
          (String x) => x.replaceFirst(
            'patternType="gray125"',
            'patternType="lightGray"',
          ),
        ),
        14,
      );
    });
    test('fill 0 is not none', () {
      _expectRule(
        styles(
          (String x) =>
              x.replaceFirst('patternType="none"', 'patternType="gray0625"'),
        ),
        14,
      );
    });
  });

  group('rule 15: worksheet child order', () {
    test('the good sheet has the parts the tests move', () {
      final String xml = utf8.decode(
        ZipDecoder()
            .decodeBytes(_good())
            .files
            .firstWhere((ArchiveFile f) => f.name == _sheet1)
            .content,
      );
      expect(
        xml,
        contains(
          '<sheetViews><sheetView workbookViewId="0"/></sheetViews>'
          '<sheetFormatPr defaultRowHeight="15" outlineLevelRow="1" '
          'outlineLevelCol="1"/>'
          '<cols><col min="1" max="1" width="12" style="1" customWidth="1"/>'
          '<col min="2" max="2" width="9.140625" outlineLevel="1"/></cols>'
          '<sheetData><row r="1" ht="20" customHeight="1" outlineLevel="1">',
        ),
      );
    });
    test('cols after sheetData', () {
      _expectRule(
        _broken(_sheet1, (String x) {
          final int start = x.indexOf('<cols>');
          final int end = x.indexOf('</cols>') + '</cols>'.length;
          final String cols = x.substring(start, end);
          return (x.substring(0, start) + x.substring(end)).replaceFirst(
            '</sheetData>',
            '</sheetData>$cols',
          );
        }),
        15,
      );
    });
    test('sheetViews twice', () {
      const String views =
          '<sheetViews><sheetView workbookViewId="0"/></sheetViews>';
      _expectRule(
        _broken(_sheet1, (String x) => x.replaceFirst(views, '$views$views')),
        15,
      );
    });
    test('an element CT_Worksheet does not know', () {
      _expectRule(
        _broken(
          _sheet1,
          (String x) => x.replaceFirst('<sheetData>', '<columns/><sheetData>'),
        ),
        15,
      );
    });
  });

  group('rule 16: columns', () {
    test('min above max', () {
      _expectRule(
        _broken(
          _sheet1,
          (String x) => x.replaceFirst('<col min="1"', '<col min="3"'),
        ),
        16,
      );
    });
    test('min of 0', () {
      _expectRule(
        _broken(
          _sheet1,
          (String x) =>
              x.replaceFirst('<col min="1" max="1"', '<col min="0" max="1"'),
        ),
        16,
      );
    });
    test('max past column 16,384', () {
      _expectRule(
        _broken(
          _sheet1,
          (String x) => x.replaceFirst(
            '<col min="2" max="2"',
            '<col min="2" max="16385"',
          ),
        ),
        16,
      );
    });
    test('overlapping ranges', () {
      _expectRule(
        _broken(
          _sheet1,
          (String x) => x.replaceFirst('<col min="2"', '<col min="1"'),
        ),
        16,
      );
    });
    test('descending ranges', () {
      _expectRule(
        _broken(
          _sheet1,
          (String x) =>
              x.replaceFirst('<col min="1" max="1"', '<col min="3" max="3"'),
        ),
        16,
      );
    });
    test('a style past cellXfs', () {
      _expectRule(
        _broken(
          _sheet1,
          (String x) => x.replaceFirst('style="1"', 'style="99"'),
        ),
        16,
      );
    });
  });

  group('rule 17: outline levels and heights', () {
    test('a row level above outlineLevelRow', () {
      _expectRule(
        _broken(
          _sheet1,
          (String x) => x.replaceFirst(
            'customHeight="1" outlineLevel="1"',
            'customHeight="1" outlineLevel="2"',
          ),
        ),
        17,
      );
    });
    test('a column level above outlineLevelCol', () {
      _expectRule(
        _broken(
          _sheet1,
          (String x) => x.replaceFirst(
            'width="9.140625" outlineLevel="1"',
            'width="9.140625" outlineLevel="2"',
          ),
        ),
        17,
      );
    });
    test('a level of 8', () {
      _expectRule(
        _broken(
          _sheet1,
          (String x) => x
              .replaceFirst('outlineLevelRow="1"', 'outlineLevelRow="8"')
              .replaceFirst(
                'customHeight="1" outlineLevel="1"',
                'customHeight="1" outlineLevel="8"',
              ),
        ),
        17,
      );
    });
    test('a row level without sheetFormatPr', () {
      _expectRule(
        _broken(
          _sheet1,
          (String x) => x.replaceFirst(RegExp('<sheetFormatPr[^>]*/>'), ''),
        ),
        17,
      );
    });
    test('a row height of 410', () {
      _expectRule(
        _broken(_sheet1, (String x) => x.replaceFirst('ht="20"', 'ht="410"')),
        17,
      );
    });
    test('a negative row height', () {
      _expectRule(
        _broken(_sheet1, (String x) => x.replaceFirst('ht="20"', 'ht="-1"')),
        17,
      );
    });
  });

  group('rule 18: visible sheets and the active tab', () {
    test('every sheet hidden', () {
      _expectRule(
        _broken(
          'xl/workbook.xml',
          (String x) => x.replaceAll('sheetId=', 'state="hidden" sheetId='),
        ),
        18,
      );
    });
    test('the active tab is hidden', () {
      _expectRule(
        _broken(
          'xl/workbook.xml',
          (String x) =>
              x.replaceFirst('sheetId="1"', 'state="veryHidden" sheetId="1"'),
        ),
        18,
      );
    });
    test('a hidden tab that is not active is fine', () {
      expect(
        checkXlsx(
          _broken(
            'xl/workbook.xml',
            (String x) =>
                x.replaceFirst('sheetId="2"', 'state="hidden" sheetId="2"'),
          ),
        ),
        isEmpty,
      );
    });
    test('an explicit state="visible" counts as visible', () {
      expect(
        checkXlsx(
          _broken(
            'xl/workbook.xml',
            (String x) =>
                x.replaceFirst('sheetId="1"', 'state="visible" sheetId="1"'),
          ),
        ),
        isEmpty,
      );
    });
  });

  group('rule 19: frozen panes', () {
    Uint8List frozen() {
      final XlsxWriter book = XlsxWriter();
      book.addSheet('F')
        ..freeze(rows: 2, columns: 3)
        ..row(<Object?>[1]);
      return book.close().bytes;
    }

    Uint8List tamper(String Function(String xml) change) => _rebuild(
      frozen(),
      edit: <String, String? Function(String)>{_sheet1: change},
    );

    test('a valid frozen pane has no violations', () {
      expect(checkXlsx(frozen()), isEmpty);
    });
    test('topLeftCell that is not at the split', () {
      _expectRule(
        tamper(
          (String x) => x.replaceFirst('topLeftCell="D3"', 'topLeftCell="C4"'),
        ),
        19,
      );
    });
    test('a missing topLeftCell', () {
      _expectRule(
        tamper((String x) => x.replaceFirst(' topLeftCell="D3"', '')),
        19,
      );
    });
    test('activePane that does not follow the splits', () {
      _expectRule(
        tamper(
          (String x) => x.replaceFirst(
            'activePane="bottomRight"',
            'activePane="bottomLeft"',
          ),
        ),
        19,
      );
    });
    test('xSplit dropped but the pane left as bottomRight', () {
      _expectRule(tamper((String x) => x.replaceFirst('xSplit="3" ', '')), 19);
    });
    test('a frozen pane without any split', () {
      _expectRule(
        tamper((String x) => x.replaceFirst('xSplit="3" ySplit="2"', '')),
        19,
      );
    });
    test('xSplit past the last column', () {
      _expectRule(
        tamper(
          (String x) => x
              .replaceFirst('xSplit="3"', 'xSplit="16384"')
              .replaceFirst('topLeftCell="D3"', 'topLeftCell="XFE3"'),
        ),
        19,
      );
    });
    test('ySplit past the last row', () {
      _expectRule(
        tamper(
          (String x) => x
              .replaceFirst('ySplit="2"', 'ySplit="1048576"')
              .replaceFirst('topLeftCell="D3"', 'topLeftCell="D1048577"'),
        ),
        19,
      );
    });
    test('the largest splits are valid', () {
      expect(
        checkXlsx(
          tamper(
            (String x) => x
                .replaceFirst('xSplit="3"', 'xSplit="16383"')
                .replaceFirst('ySplit="2"', 'ySplit="1048575"')
                .replaceFirst('topLeftCell="D3"', 'topLeftCell="XFD1048576"'),
          ),
        ),
        isEmpty,
      );
    });
    test('a split pane is not checked', () {
      final XlsxWriter book = XlsxWriter();
      book.addSheet('S')
        ..split(x: 10, y: 10)
        ..row(<Object?>[1]);
      expect(checkXlsx(book.close().bytes), isEmpty);
    });
  });

  group('rule 20: merged cells', () {
    Uint8List merged() {
      final XlsxWriter book = XlsxWriter();
      book.addSheet('M')
        ..row(<Object?>[1])
        ..merge(XlsxRange.parse('A1:B2'))
        ..merge(XlsxRange.parse('D4:E4'));
      return book.close().bytes;
    }

    Uint8List tamper(String Function(String xml) change) => _rebuild(
      merged(),
      edit: <String, String? Function(String)>{_sheet1: change},
    );

    test('valid merges have no violations', () {
      expect(checkXlsx(merged()), isEmpty);
    });
    test('a single-cell merge', () {
      _expectRule(
        tamper((String x) => x.replaceFirst('ref="D4:E4"', 'ref="D4"')),
        20,
      );
    });
    test('a single-cell merge written as a range', () {
      _expectRule(
        tamper((String x) => x.replaceFirst('ref="D4:E4"', 'ref="D4:D4"')),
        20,
      );
    });
    test('overlapping merges', () {
      _expectRule(
        tamper((String x) => x.replaceFirst('ref="D4:E4"', 'ref="B2:C3"')),
        20,
      );
    });
    test('a merge outside the sheet', () {
      _expectRule(
        tamper((String x) => x.replaceFirst('ref="D4:E4"', 'ref="D4:XFE4"')),
        20,
      );
      _expectRule(
        tamper(
          (String x) => x.replaceFirst('ref="D4:E4"', 'ref="D4:E1048577"'),
        ),
        20,
      );
    });
    test('a reversed or malformed merge', () {
      _expectRule(
        tamper((String x) => x.replaceFirst('ref="D4:E4"', 'ref="E4:D4"')),
        20,
      );
      _expectRule(
        tamper((String x) => x.replaceFirst('ref="D4:E4"', 'ref="D4:"')),
        20,
      );
    });
    test('a count that differs from the children', () {
      _expectRule(
        tamper((String x) => x.replaceFirst('count="2"', 'count="3"')),
        20,
      );
    });
    test('a missing count', () {
      _expectRule(
        tamper(
          (String x) =>
              x.replaceFirst('<mergeCells count="2">', '<mergeCells>'),
        ),
        20,
      );
    });
  });

  group('rule 21: defined names and the filter range', () {
    Uint8List filtered() {
      final XlsxWriter book = XlsxWriter();
      book.addSheet('F')
        ..row(<Object?>[1, 2])
        ..autoFilter(XlsxRange.parse('A1:B2'));
      book.addSheet('G').autoFilter(XlsxRange.parse('A1:B2'));
      return book.close().bytes;
    }

    Uint8List tamper(String part, String Function(String xml) change) =>
        _rebuild(
          filtered(),
          edit: <String, String? Function(String)>{part: change},
        );

    test('valid names and filters have no violations', () {
      expect(checkXlsx(filtered()), isEmpty);
    });
    test('the same name twice in one scope', () {
      _expectRule(
        tamper(
          'xl/workbook.xml',
          (String x) => x.replaceFirst('localSheetId="1"', 'localSheetId="0"'),
        ),
        21,
      );
    });
    test('names differing only in case are the same name', () {
      _expectRule(
        tamper(
          'xl/workbook.xml',
          (String x) => x
              .replaceFirst('localSheetId="1"', 'localSheetId="0"')
              .replaceFirst(
                'name="_xlnm._FilterDatabase" localSheetId="0" hidden="1">\'G',
                'name="_XLNM._filterdatabase" localSheetId="0" hidden="1">\'G',
              ),
        ),
        21,
      );
    });
    test('a localSheetId that is not a sheet', () {
      _expectRule(
        tamper(
          'xl/workbook.xml',
          (String x) => x.replaceFirst('localSheetId="1"', 'localSheetId="2"'),
        ),
        21,
      );
    });
    test('a localSheetId that is not a number', () {
      _expectRule(
        tamper(
          'xl/workbook.xml',
          (String x) => x.replaceFirst('localSheetId="1"', 'localSheetId="x"'),
        ),
        21,
      );
    });
    test('a global and a local name of one name are different scopes', () {
      expect(
        checkXlsx(
          tamper(
            'xl/workbook.xml',
            (String x) => x.replaceFirst(
              '</definedNames>',
              '<definedName name="Dup">1</definedName>'
                  '<definedName name="Dup" localSheetId="0">1</definedName>'
                  '</definedNames>',
            ),
          ),
        ),
        isEmpty,
      );
    });
    test('a filtered sheet without its _FilterDatabase name', () {
      _expectRule(
        tamper(
          'xl/workbook.xml',
          (String x) => x.replaceFirst(
            RegExp(
              r'<definedName [^>]*localSheetId="0"[^>]*>[^<]*</definedName>',
            ),
            '',
          ),
        ),
        21,
      );
    });
    test('a _FilterDatabase name on a sheet with no autoFilter', () {
      _expectRule(
        tamper(
          _sheet2,
          (String x) => x.replaceFirst(RegExp(r'<autoFilter [^>]*/>'), ''),
        ),
        21,
      );
    });
    test('a _FilterDatabase name whose range is not the filter', () {
      _expectRule(
        tamper(
          'xl/workbook.xml',
          (String x) => x.replaceFirst(r"'F'!$A$1:$B$2", r"'F'!$A$1:$B$3"),
        ),
        21,
      );
    });
    test('a _FilterDatabase name that names another sheet', () {
      _expectRule(
        tamper(
          'xl/workbook.xml',
          (String x) => x.replaceFirst(r"'F'!$A$1:$B$2", r"'G'!$A$1:$B$2"),
        ),
        21,
      );
    });
    test('a _FilterDatabase name with the range not absolute', () {
      _expectRule(
        tamper(
          'xl/workbook.xml',
          (String x) => x.replaceFirst(r"'F'!$A$1:$B$2", "'F'!A1:B2"),
        ),
        21,
      );
    });
    test('a built-in _xlnm name without a localSheetId', () {
      _expectRule(
        tamper(
          'xl/workbook.xml',
          (String x) => x.replaceFirst(
            '</definedNames>',
            '<definedName name="_xlnm.Print_Area">F!A1</definedName>'
                '</definedNames>',
          ),
        ),
        21,
      );
    });
    test('a defined name with no text', () {
      _expectRule(
        tamper(
          'xl/workbook.xml',
          (String x) => x.replaceFirst(
            '</definedNames>',
            '<definedName name="Empty"> </definedName></definedNames>',
          ),
        ),
        21,
      );
    });
    test('names with print settings and a user name are valid', () {
      final XlsxWriter book = XlsxWriter();
      book.addSheet('F')
        ..printArea(<XlsxRange>[XlsxRange.parse('A1:B2')])
        ..printTitles(rows: (0, 0))
        ..defineName(const XlsxDefinedName('Mine', 'F!A1'));
      book.defineName(const XlsxDefinedName('Mine', '1'));
      expect(checkXlsx(book.close().bytes), isEmpty);
    });
    test('an autoFilter ref that is not a range', () {
      for (final String bad in <String>[
        'A:A',
        'XFE1:XFE2',
        'B2:A1',
        'hello',
        '',
      ]) {
        _expectRule(
          tamper(
            _sheet1,
            (String x) => x.replaceFirst(
              'autoFilter ref="A1:B2"',
              'autoFilter ref="$bad"',
            ),
          ),
          21,
        );
      }
    });
  });
}
