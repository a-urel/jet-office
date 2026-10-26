import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

import '../fixtures/m4_fixtures.dart' show jpeg3x5, png4x2;
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
    test('a .vml part that is not well-formed', () {
      _expectRule(
        _rebuild(
          _good(),
          add: const <String, String>{
            'xl/drawings/vmlDrawing1.vml':
                '<xml xmlns:v="urn:schemas-microsoft-com:vml"><v:shape></xml>',
          },
        ),
        1,
      );
    });
    test('a well-formed .vml part is not a rule 1 violation', () {
      final List<String> violations = checkXlsx(
        _rebuild(
          _good(),
          add: const <String, String>{
            'xl/drawings/vmlDrawing1.vml':
                '<xml xmlns:v="urn:schemas-microsoft-com:vml"><v:shape/></xml>',
          },
        ),
      );
      expect(violations.where((String v) => v.startsWith('rule 1:')), isEmpty);
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
    test('a filter name whose sheet name has an undoubled apostrophe', () {
      final XlsxWriter book = XlsxWriter();
      book.addSheet("O'B")
        ..row(<Object?>[1, 2])
        ..autoFilter(XlsxRange.parse('A1:B2'));
      final Uint8List good = book.close().bytes;
      expect(checkXlsx(good), isEmpty);
      _expectRule(
        _rebuild(
          good,
          edit: <String, String? Function(String)>{
            'xl/workbook.xml': (String x) =>
                x.replaceFirst("'O''B'!", "'O'B'!"),
          },
        ),
        21,
      );
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

  group('rule 22: hyperlinks', () {
    Uint8List linked() {
      final XlsxWriter book = XlsxWriter();
      book.addSheet('L').row(<Object?>[
        XlsxHyperlink.url('https://a.org'),
        XlsxHyperlink.location('X'),
      ]);
      return book.close().bytes;
    }

    Uint8List tamper(
      String Function(String xml) change, {
      String part = _sheet1,
    }) => _rebuild(
      linked(),
      edit: <String, String? Function(String)>{part: change},
    );

    const String rels = 'xl/worksheets/_rels/sheet1.xml.rels';

    test('valid hyperlinks have no violations', () {
      expect(checkXlsx(linked()), isEmpty);
    });
    test('a ref outside the sheet', () {
      _expectRule(
        tamper((String x) => x.replaceFirst('ref="B1"', 'ref="B1048577"')),
        22,
      );
    });
    test('a ref that is not a range', () {
      _expectRule(
        tamper((String x) => x.replaceFirst('ref="B1"', 'ref="B"')),
        22,
      );
    });
    test('neither r:id nor location', () {
      _expectRule(
        tamper((String x) => x.replaceFirst(' location="X"', '')),
        22,
      );
    });
    test('an r:id the relationships do not declare', () {
      _expectRule(
        tamper((String x) => x.replaceFirst('r:id="rId1"', 'r:id="rId9"')),
        22,
      );
    });
    test('an r:id and no relationships part', () {
      _expectRule(
        _rebuild(
          linked(),
          edit: <String, String? Function(String)>{rels: (String x) => null},
        ),
        22,
      );
    });
    test('a relationship that is not external', () {
      _expectRule(
        tamper(
          (String x) => x.replaceFirst(' TargetMode="External"', ''),
          part: rels,
        ),
        22,
      );
    });
    test('a relationship of another type', () {
      _expectRule(
        tamper(
          (String x) =>
              x.replaceFirst('relationships/hyperlink', 'relationships/image'),
          part: rels,
        ),
        22,
      );
    });
    test('two hyperlinks with the same ref', () {
      _expectRule(
        tamper((String x) => x.replaceFirst('ref="B1"', 'ref="A1"')),
        22,
      );
    });
    test('more than 65,530 hyperlinks', () {
      _expectRule(
        tamper((String x) {
          final String many = [
            for (int i = 1; i <= 65531; i++)
              '<hyperlink ref="A$i" location="X"/>',
          ].join();
          return x.replaceFirst(
            RegExp('<hyperlinks>.*</hyperlinks>'),
            '<hyperlinks>$many</hyperlinks>',
          );
        }),
        22,
      );
    });
  });

  group('rule 23: data validations', () {
    Uint8List validated() {
      final XlsxWriter book = XlsxWriter();
      book.addSheet('V')
        ..row(<Object?>[1])
        ..dataValidation(
          XlsxDataValidation.whole(
            <XlsxRange>[XlsxRange.parse('A1')],
            XlsxComparison.between,
            1,
            b: 10,
          ),
        )
        ..dataValidation(
          XlsxDataValidation.list(
            <XlsxRange>[XlsxRange.parse('B1:B3')],
            <String>['a', 'b'],
          ),
        )
        ..dataValidation(
          XlsxDataValidation.any(<XlsxRange>[XlsxRange.parse('C1')]),
        );
      return book.close().bytes;
    }

    Uint8List tamper(String Function(String xml) change) => _rebuild(
      validated(),
      edit: <String, String? Function(String)>{_sheet1: change},
    );

    test('valid validations have no violations', () {
      expect(checkXlsx(validated()), isEmpty);
    });
    test('a count that differs from the children', () {
      _expectRule(
        tamper(
          (String x) => x.replaceFirst(
            '<dataValidations count="3">',
            '<dataValidations count="2">',
          ),
        ),
        23,
      );
    });
    test('an sqref outside the sheet', () {
      _expectRule(
        tamper((String x) => x.replaceFirst('sqref="A1"', 'sqref="A1048577"')),
        23,
      );
    });
    test('an sqref that is not a range', () {
      _expectRule(
        tamper((String x) => x.replaceFirst('sqref="B1:B3"', 'sqref="B:B"')),
        23,
      );
    });
    test('two validations whose ranges overlap', () {
      _expectRule(
        tamper((String x) => x.replaceFirst('sqref="C1"', 'sqref="B3"')),
        23,
      );
    });
    test('a missing formula1', () {
      _expectRule(
        tamper((String x) => x.replaceFirst('<formula1>1</formula1>', '')),
        23,
      );
    });
    test('a missing formula2 for between', () {
      _expectRule(
        tamper((String x) => x.replaceFirst('<formula2>10</formula2>', '')),
        23,
      );
    });
    test('a missing formula2 for notBetween', () {
      _expectRule(
        tamper(
          (String x) => x
              .replaceFirst('<formula2>10</formula2>', '')
              .replaceFirst(
                'type="whole"',
                'type="whole" operator="notBetween"',
              ),
        ),
        23,
      );
    });
    test('a comparison without formula2 is fine', () {
      expect(
        checkXlsx(
          tamper(
            (String x) => x
                .replaceFirst('<formula2>10</formula2>', '')
                .replaceFirst(
                  'type="whole"',
                  'type="whole" operator="greaterThan"',
                ),
          ),
        ),
        isEmpty,
      );
    });
  });

  group('rule 24: conditional formats', () {
    Uint8List formatted() {
      final XlsxWriter book = XlsxWriter();
      final XlsxStyle red = XlsxStyle(
        fill: XlsxFill.solid(XlsxColor.hex('FFC7CE')),
      );
      book.addSheet('C')
        ..row(<Object?>[1, 'a'])
        ..conditionalFormat(
          XlsxConditionalFormat(
            <XlsxRange>[XlsxRange.parse('A1:A9')],
            <XlsxConditionalRule>[
              XlsxCellValueRule(
                XlsxComparison.between,
                '1',
                formula2: '5',
                style: red,
              ),
              const XlsxExpressionRule('A1>3'),
            ],
          ),
        )
        ..conditionalFormat(
          XlsxConditionalFormat(
            <XlsxRange>[XlsxRange.parse('B1:B9')],
            <XlsxConditionalRule>[
              const XlsxTextRule(XlsxTextOperator.contains, 'a'),
              XlsxColorScale(
                <XlsxCfValue>[
                  const XlsxCfValue.min(),
                  XlsxCfValue.percentile(50),
                  const XlsxCfValue.max(),
                ],
                <XlsxColor>[
                  XlsxColor.hex('F8696B'),
                  XlsxColor.hex('FFEB84'),
                  XlsxColor.hex('63BE7B'),
                ],
              ),
            ],
          ),
        );
      return book.close().bytes;
    }

    Uint8List tamper(String Function(String xml) change) => _rebuild(
      formatted(),
      edit: <String, String? Function(String)>{_sheet1: change},
    );

    test('valid conditional formats have no violations', () {
      expect(checkXlsx(formatted()), isEmpty);
    });
    test('an sqref outside the sheet', () {
      _expectRule(
        tamper(
          (String x) => x.replaceFirst('sqref="A1:A9"', 'sqref="A1:A1048577"'),
        ),
        24,
      );
    });
    test('an sqref that is not a range', () {
      _expectRule(
        tamper((String x) => x.replaceFirst('sqref="B1:B9"', 'sqref="B:B"')),
        24,
      );
    });
    test('two rules share a priority', () {
      _expectRule(
        tamper((String x) => x.replaceFirst('priority="3"', 'priority="1"')),
        24,
      );
    });
    test('a priority below 1, or missing', () {
      _expectRule(
        tamper((String x) => x.replaceFirst('priority="1"', 'priority="0"')),
        24,
      );
      _expectRule(
        tamper((String x) => x.replaceFirst(' priority="2"', '')),
        24,
      );
    });
    test('a dxfId not below the dxfs count', () {
      _expectRule(
        tamper((String x) => x.replaceFirst('dxfId="0"', 'dxfId="1"')),
        24,
      );
    });
    test('cellIs between with one formula', () {
      _expectRule(
        tamper((String x) => x.replaceFirst('<formula>5</formula>', '')),
        24,
      );
    });
    test('cellIs greaterThan with two formulas', () {
      _expectRule(
        tamper(
          (String x) =>
              x.replaceFirst('operator="between"', 'operator="greaterThan"'),
        ),
        24,
      );
    });
    test('cellIs notBetween with two formulas is fine', () {
      expect(
        checkXlsx(
          tamper(
            (String x) =>
                x.replaceFirst('operator="between"', 'operator="notBetween"'),
          ),
        ),
        isEmpty,
      );
    });
    test('an expression without a formula', () {
      _expectRule(
        tamper((String x) => x.replaceFirst('<formula>A1&gt;3</formula>', '')),
        24,
      );
    });
    test('a text rule with two formulas', () {
      _expectRule(
        tamper(
          (String x) => x.replaceFirst(
            '</formula></cfRule><cfRule type="colorScale"',
            '</formula><formula>1</formula></cfRule><cfRule type="colorScale"',
          ),
        ),
        24,
      );
    });
    test('a color scale whose cfvo and color counts differ', () {
      _expectRule(
        tamper((String x) => x.replaceFirst('<color rgb="FF63BE7B"/>', '')),
        24,
      );
    });
    test('a color scale of one point', () {
      _expectRule(
        tamper(
          (String x) => x
              .replaceFirst('<cfvo type="percentile" val="50"/>', '')
              .replaceFirst('<cfvo type="max"/>', '')
              .replaceFirst('<color rgb="FFFFEB84"/>', '')
              .replaceFirst('<color rgb="FF63BE7B"/>', ''),
        ),
        24,
      );
    });
  });

  group('rule 25: Excel 2010 conditional-format extensions', () {
    Uint8List extended() {
      final XlsxWriter book = XlsxWriter();
      for (final String name in <String>['A', 'B']) {
        book.addSheet(name)
          ..row(<Object?>[1, 2])
          ..conditionalFormat(
            XlsxConditionalFormat(
              <XlsxRange>[XlsxRange.parse('A1:A9')],
              <XlsxConditionalRule>[
                const XlsxExpressionRule('A1>3'),
                XlsxDataBar(color: XlsxColor.hex('638EC6')),
                XlsxIconSet(XlsxIconSetType.threeStars),
              ],
            ),
          );
      }
      return book.close().bytes;
    }

    Uint8List tamper(String part, String Function(String xml) change) =>
        _rebuild(
          extended(),
          edit: <String, String? Function(String)>{part: change},
        );

    /// The `x14:cfRule` of the icon set on sheet 1.
    const String stars =
        '<x14:cfRule type="iconSet" priority="3" '
        'id="{00000001-0000-4000-8000-000000000002}">';

    test('valid extensions have no violations', () {
      expect(checkXlsx(extended()), isEmpty);
    });
    test('a cfRule x14:id without its x14:cfRule', () {
      _expectRule(
        tamper(
          _sheet1,
          (String x) => x.replaceFirst(
            '<x14:id>{00000001-0000-4000-8000-000000000001}</x14:id>',
            '<x14:id>{00000001-0000-4000-8000-0000000000FF}</x14:id>',
          ),
        ),
        25,
      );
    });
    test('an x14 data bar whose cfRule partner is gone', () {
      _expectRule(
        tamper(
          _sheet1,
          (String x) => x.replaceFirst(
            RegExp('<extLst><ext uri="{B025F937[^]*?</extLst>'),
            '',
          ),
        ),
        25,
      );
    });
    test('two x14:cfRule elements share an id', () {
      _expectRule(
        tamper(
          _sheet1,
          (String x) => x.replaceFirst(
            'id="{00000001-0000-4000-8000-000000000002}"',
            'id="{00000001-0000-4000-8000-000000000001}"',
          ),
        ),
        25,
      );
    });
    test('an x14 rule id repeated on another sheet', () {
      _expectRule(
        tamper(_sheet2, (String x) => x.replaceAll('{00000002-', '{00000001-')),
        25,
      );
    });
    test('an x14-only rule repeats a 2007 priority', () {
      _expectRule(
        tamper(
          _sheet1,
          (String x) => x.replaceFirst(
            stars,
            stars.replaceFirst('priority="3"', 'priority="1"'),
          ),
        ),
        25,
      );
    });
    test('an x14-only rule without a priority', () {
      _expectRule(
        tamper(
          _sheet1,
          (String x) =>
              x.replaceFirst(stars, stars.replaceFirst(' priority="3"', '')),
        ),
        25,
      );
    });
    test('an unnamed x14:cfRule is x14-only only for an x14-only icon set', () {
      for (final String set in <String>[
        '3Stars',
        '3Triangles',
        '5Boxes',
        'NoIcons',
      ]) {
        expect(
          checkXlsx(
            tamper(
              _sheet1,
              (String x) => x.replaceFirst(
                '<x14:iconSet iconSet="3Stars">',
                '<x14:iconSet iconSet="$set">',
              ),
            ),
          ),
          isEmpty,
          reason: set,
        );
      }
      // A 2007 icon set always has its own cfRule, so an unnamed x14 rule of
      // one is a stray, as is an unnamed data bar.
      _expectRule(
        tamper(
          _sheet1,
          (String x) => x.replaceFirst(
            '<x14:iconSet iconSet="3Stars">',
            '<x14:iconSet iconSet="3Arrows">',
          ),
        ),
        25,
      );
      _expectRule(
        tamper(
          _sheet1,
          (String x) => x.replaceFirst(
            '<x14:cfRule type="iconSet" priority="3"',
            '<x14:cfRule type="dataBar" priority="3"',
          ),
        ),
        25,
      );
    });
    test('the ext uri of a cfRule and of the worksheet are the ones '
        'Excel writes', () {
      _expectRule(
        tamper(
          _sheet1,
          (String x) => x.replaceFirst(
            '{B025F937-C7B1-47D3-B67F-A62EFF666E3E}',
            '{B025F937-C7B1-47D3-B67F-A62EFF666E3F}',
          ),
        ),
        25,
      );
      _expectRule(
        tamper(
          _sheet1,
          (String x) => x.replaceFirst(
            '{78C0D931-6437-407d-A8EE-F0AAD7539E65}',
            '{78C0D931-6437-407d-A8EE-F0AAD7539E66}',
          ),
        ),
        25,
      );
      // Excel writes the lowercase d; the URI is compared exactly.
      _expectRule(
        tamper(
          _sheet1,
          (String x) =>
              x.replaceFirst('{78C0D931-6437-407d-', '{78C0D931-6437-407D-'),
        ),
        25,
      );
    });
    test('the extLst is not the last worksheet child', () {
      _expectRule(
        tamper(_sheet1, (String x) {
          final RegExpMatch ext = RegExp(
            r'<extLst><ext uri="\{78C0D931[^]*</extLst>',
          ).firstMatch(x)!;
          return x
              .replaceFirst(ext.group(0)!, '')
              .replaceFirst(
                '<conditionalFormatting',
                '${ext.group(0)}<conditionalFormatting',
              );
        }),
        25,
      );
    });
  });

  group('rule 26: protection', () {
    Uint8List protectedBook() {
      final XlsxWriter book = XlsxWriter();
      book.addSheet('P')
        ..row(<Object?>[1])
        ..protect(const XlsxSheetProtection(password: 'password'));
      book.protectWorkbook(const XlsxWorkbookProtection(password: 'test'));
      return book.close().bytes;
    }

    Uint8List tamper(String part, String Function(String xml) change) =>
        _rebuild(
          protectedBook(),
          edit: <String, String? Function(String)>{part: change},
        );

    test('a protected workbook is clean', () {
      expect(checkXlsx(protectedBook()), isEmpty);
    });
    test('a sheet password that is not four hex digits', () {
      for (final String bad in <String>['83A', '83AFF', '83AG', '']) {
        _expectRule(
          tamper(
            _sheet1,
            (String x) => x.replaceFirst('password="83AF"', 'password="$bad"'),
          ),
          26,
        );
      }
    });
    test('a password in lowercase hex is not Excel\'s spelling', () {
      _expectRule(
        tamper(
          _sheet1,
          (String x) => x.replaceFirst('password="83AF"', 'password="83af"'),
        ),
        26,
      );
      _expectRule(
        tamper(
          'xl/workbook.xml',
          (String x) => x.replaceFirst(
            'workbookPassword="CBEB"',
            'workbookPassword="cbeb"',
          ),
        ),
        26,
      );
    });
    test('a workbook password that is not four hex digits', () {
      _expectRule(
        tamper(
          'xl/workbook.xml',
          (String x) => x.replaceFirst(
            'workbookPassword="CBEB"',
            'workbookPassword="CBE"',
          ),
        ),
        26,
      );
    });
    test('a sheetProtection without sheet="1"', () {
      _expectRule(
        tamper(_sheet1, (String x) => x.replaceFirst(' sheet="1"', '')),
        26,
      );
      _expectRule(
        tamper(_sheet1, (String x) => x.replaceFirst('sheet="1"', 'sheet="0"')),
        26,
      );
    });
  });

  group('rule 27: custom properties', () {
    Uint8List customBook() {
      final XlsxWriter book = XlsxWriter(
        properties: const XlsxProperties(
          custom: <String, Object>{'Project': 'Atlas', 'Count': 3},
        ),
      );
      book.addSheet('P').row(<Object?>[1]);
      return book.close().bytes;
    }

    Uint8List tamper(String Function(String xml) change) => _rebuild(
      customBook(),
      edit: <String, String? Function(String)>{'docProps/custom.xml': change},
    );

    test('a workbook with custom properties is clean', () {
      expect(checkXlsx(customBook()), isEmpty);
    });
    test('a duplicate pid', () {
      _expectRule(
        tamper((String x) => x.replaceFirst('pid="3"', 'pid="2"')),
        27,
      );
    });
    test('a pid below 2', () {
      _expectRule(
        tamper((String x) => x.replaceFirst('pid="2"', 'pid="1"')),
        27,
      );
    });
    test('names that are equal ignoring case', () {
      _expectRule(
        tamper((String x) => x.replaceFirst('name="Count"', 'name="PROJECT"')),
        27,
      );
    });
    test('a property with another fmtid or none', () {
      _expectRule(
        tamper(
          (String x) => x.replaceFirst(
            'fmtid="{D5CDD505-2E9C-101B-9397-08002B2CF9AE}" pid="2"',
            'fmtid="{D5CDD505-2E9C-101B-9397-08002B2CF9AF}" pid="2"',
          ),
        ),
        27,
      );
      _expectRule(
        tamper(
          (String x) => x.replaceFirst(
            'fmtid="{D5CDD505-2E9C-101B-9397-08002B2CF9AE}" pid="3"',
            'pid="3"',
          ),
        ),
        27,
      );
    });
    test('a value child outside the vt namespace', () {
      _expectRule(
        tamper(
          (String x) => x.replaceFirst(
            '<vt:i4>3</vt:i4>',
            '<i4 xmlns="urn:other">3</i4>',
          ),
        ),
        27,
      );
      _expectRule(
        tamper(
          (String x) => x.replaceFirst(
            '<vt:lpwstr>Atlas</vt:lpwstr>',
            '<lpwstr>Atlas</lpwstr>',
          ),
        ),
        27,
      );
    });
    test('a property with no value', () {
      _expectRule(
        tamper(
          (String x) => x.replaceFirst('<vt:lpwstr>Atlas</vt:lpwstr>', ''),
        ),
        27,
      );
    });
    test('a property with two values', () {
      _expectRule(
        tamper(
          (String x) => x.replaceFirst(
            '<vt:i4>3</vt:i4>',
            '<vt:i4>3</vt:i4><vt:i4>4</vt:i4>',
          ),
        ),
        27,
      );
    });
  });

  group('rule 28: shared-string items', () {
    Uint8List richBook() {
      final XlsxWriter book = XlsxWriter();
      book.addSheet('R').row(<Object?>[
        'plain',
        XlsxRichText(const <XlsxTextRun>[
          XlsxTextRun('Total: ', font: XlsxFont(bold: true)),
          XlsxTextRun('42'),
        ]),
      ]);
      return book.close().bytes;
    }

    Uint8List tamper(String Function(String xml) change) => _rebuild(
      richBook(),
      edit: <String, String? Function(String)>{'xl/sharedStrings.xml': change},
    );

    test('a workbook with rich text is clean', () {
      expect(checkXlsx(richBook()), isEmpty);
    });
    test('an si with two t', () {
      _expectRule(
        tamper(
          (String x) =>
              x.replaceFirst('<t>plain</t>', '<t>plain</t><t>again</t>'),
        ),
        28,
      );
    });
    test('an si with nothing in it', () {
      _expectRule(
        tamper((String x) => x.replaceFirst('<si><t>plain</t></si>', '<si/>')),
        28,
      );
    });
    test('an si mixing t and r', () {
      _expectRule(
        tamper(
          (String x) =>
              x.replaceFirst('<t>plain</t>', '<t>plain</t><r><t>x</t></r>'),
        ),
        28,
      );
    });
    test('an si with a child other than t and r', () {
      _expectRule(
        tamper((String x) => x.replaceFirst('<t>plain</t>', '<x>plain</x>')),
        28,
      );
    });
    test('an r without t', () {
      _expectRule(
        tamper(
          (String x) => x.replaceFirst('<r><t>42</t></r>', '<r><rPr/></r>'),
        ),
        28,
      );
    });
    test('an r with two t', () {
      _expectRule(
        tamper(
          (String x) =>
              x.replaceFirst('<r><t>42</t></r>', '<r><t>4</t><t>2</t></r>'),
        ),
        28,
      );
    });
    test('an r with two rPr', () {
      _expectRule(
        tamper((String x) => x.replaceFirst('<rPr><b/>', '<rPr/><rPr><b/>')),
        28,
      );
    });
    test('an r with a child other than rPr and t', () {
      _expectRule(
        tamper(
          (String x) =>
              x.replaceFirst('<r><t>42</t></r>', '<r><t>42</t><x/></r>'),
        ),
        28,
      );
    });
  });

  group('rule 29: notes', () {
    const String comments1 = 'xl/comments1.xml';
    const String vml1 = 'xl/drawings/vmlDrawing1.vml';
    const String vml2 = 'xl/drawings/vmlDrawing2.vml';

    /// Two sheets of notes: `N` with notes on XFD1 (shape 1025) and B2
    /// (shape 1026) by two authors, `M` with one on A1048576 (shape 2049).
    Uint8List notesBook() {
      final XlsxWriter book = XlsxWriter();
      book.addSheet('N')
        ..row(<Object?>['x'])
        ..note(1, 1, XlsxNote.plain('b2', author: 'A'))
        ..note(0, 16383, XlsxNote.plain('xfd1', author: 'B'));
      book.addSheet('M').note(1048575, 0, XlsxNote.plain('last'));
      return book.close().bytes;
    }

    Uint8List tamper(Map<String, String Function(String xml)> edits) =>
        _rebuild(
          notesBook(),
          edit: <String, String? Function(String)>{
            for (final MapEntry<String, String Function(String)> e
                in edits.entries)
              e.key: e.value,
          },
        );

    /// Expects a rule 29 violation that contains [fragment].
    void expectViolation(Uint8List bytes, String fragment) {
      final List<String> violations = checkXlsx(bytes);
      expect(
        violations.where(
          (String v) => v.startsWith('rule 29:') && v.contains(fragment),
        ),
        isNotEmpty,
        reason: 'violations: $violations',
      );
    }

    test('a workbook with notes is clean', () {
      expect(checkXlsx(notesBook()), isEmpty);
    });
    test('the book has the parts the tests change', () {
      final Map<String, String> parts = <String, String>{
        for (final ArchiveFile f in ZipDecoder().decodeBytes(notesBook()).files)
          f.name: utf8.decode(f.content),
      };
      expect(
        parts[comments1],
        contains(
          '<authors><author>B</author><author>A</author></authors>'
          '<commentList><comment ref="XFD1" authorId="0">',
        ),
      );
      expect(parts[comments1], contains('<comment ref="B2" authorId="1">'));
      expect(
        parts[_sheet1],
        endsWith('<legacyDrawing r:id="rId1"/></worksheet>'),
      );
      expect(parts[vml1], contains('data="1"'));
      expect(parts[vml1], contains('_x0000_s1025'));
      expect(parts[vml1], contains('_x0000_s1026'));
      expect(
        parts[vml1],
        contains('<x:Anchor>16380, 15, 0, 2, 16382, 15, 4, 16</x:Anchor>'),
      );
      expect(
        parts[vml1],
        contains('<x:Anchor>2, 15, 0, 10, 4, 15, 4, 4</x:Anchor>'),
      );
      expect(parts[vml1], contains('<x:Row>1</x:Row><x:Column>1</x:Column>'));
      expect(parts[vml2], contains('data="2"'));
      expect(parts[vml2], contains('_x0000_s2049'));
      expect(
        parts[vml2],
        contains('<x:Anchor>1, 15, 1048571, 10, 3, 15, 1048575, 4</x:Anchor>'),
      );
    });
    test('a comment ref that is a range', () {
      expectViolation(
        tamper(<String, String Function(String)>{
          comments1: (String x) => x.replaceFirst('ref="B2"', 'ref="B2:C3"'),
        }),
        'is not a single cell',
      );
    });
    test('a comment ref outside the sheet', () {
      expectViolation(
        tamper(<String, String Function(String)>{
          comments1: (String x) => x.replaceFirst('ref="XFD1"', 'ref="XFE1"'),
        }),
        'lies outside the sheet',
      );
    });
    test('two comments on one cell', () {
      expectViolation(
        tamper(<String, String Function(String)>{
          comments1: (String x) => x.replaceFirst('ref="XFD1"', 'ref="B2"'),
        }),
        'two comments share the ref "B2"',
      );
    });
    test('an authorId past the authors', () {
      expectViolation(
        tamper(<String, String Function(String)>{
          comments1: (String x) =>
              x.replaceFirst('authorId="1"', 'authorId="2"'),
        }),
        'authorId "2"',
      );
    });
    test('comments without a legacyDrawing', () {
      expectViolation(
        tamper(<String, String Function(String)>{
          _sheet1: (String x) =>
              x.replaceFirst('<legacyDrawing r:id="rId1"/>', ''),
        }),
        'no <legacyDrawing>',
      );
    });
    test('a legacyDrawing that names the comments part', () {
      expectViolation(
        tamper(<String, String Function(String)>{
          _sheet1: (String x) => x.replaceFirst(
            '<legacyDrawing r:id="rId1"/>',
            '<legacyDrawing r:id="rId2"/>',
          ),
        }),
        'is not a VML drawing relationship',
      );
    });
    test('a comment without its note shape', () {
      expectViolation(
        tamper(<String, String Function(String)>{
          vml1: (String x) {
            final int start = x.indexOf('<v:shape id="_x0000_s1026"');
            final int end = x.indexOf('</v:shape>', start) + 10;
            return x.substring(0, start) + x.substring(end);
          },
        }),
        'has 0 note shapes',
      );
    });
    test('a comment with two note shapes', () {
      expectViolation(
        tamper(<String, String Function(String)>{
          vml1: (String x) {
            final int start = x.indexOf('<v:shape id="_x0000_s1026"');
            final int end = x.indexOf('</v:shape>', start) + 10;
            final String shape = x
                .substring(start, end)
                .replaceFirst('_x0000_s1026', '_x0000_s1027');
            return x.replaceFirst('</xml>', '$shape</xml>');
          },
        }),
        'has 2 note shapes',
      );
    });
    test('a note shape on a row without a comment', () {
      expectViolation(
        tamper(<String, String Function(String)>{
          vml1: (String x) =>
              x.replaceFirst('<x:Row>1</x:Row>', '<x:Row>2</x:Row>'),
        }),
        'row 2, column 1, which has no comment',
      );
    });
    test('a note shape on a column without a comment', () {
      expectViolation(
        tamper(<String, String Function(String)>{
          vml1: (String x) => x.replaceFirst(
            '<x:Column>1</x:Column>',
            '<x:Column>2</x:Column>',
          ),
        }),
        'row 1, column 2, which has no comment',
      );
    });
    test('an anchor without 8 integers', () {
      expectViolation(
        tamper(<String, String Function(String)>{
          vml1: (String x) => x.replaceFirst(
            '<x:Anchor>2, 15, 0, 10, 4, 15, 4, 4</x:Anchor>',
            '<x:Anchor>2, 15, 0, 10, 4, 15, 4</x:Anchor>',
          ),
        }),
        'is not 8 integers',
      );
    });
    test('an anchor past the last column', () {
      expectViolation(
        tamper(<String, String Function(String)>{
          vml1: (String x) => x.replaceFirst(
            '16380, 15, 0, 2, 16382, 15, 4, 16',
            '16382, 15, 0, 2, 16384, 15, 4, 16',
          ),
        }),
        'lies outside the sheet',
      );
    });
    test('an anchor past the last row', () {
      expectViolation(
        tamper(<String, String Function(String)>{
          vml2: (String x) => x.replaceFirst(
            '1, 15, 1048571, 10, 3, 15, 1048575, 4',
            '1, 15, 1048572, 10, 3, 15, 1048576, 4',
          ),
        }),
        'lies outside the sheet',
      );
    });
    test('an anchor with a negative cell', () {
      expectViolation(
        tamper(<String, String Function(String)>{
          vml1: (String x) => x.replaceFirst(
            '2, 15, 0, 10, 4, 15, 4, 4',
            '-1, 15, 0, 10, 4, 15, 4, 4',
          ),
        }),
        'lies outside the sheet',
      );
    });
    test('an anchor whose left is right of its right', () {
      expectViolation(
        tamper(<String, String Function(String)>{
          vml1: (String x) => x.replaceFirst(
            '2, 15, 0, 10, 4, 15, 4, 4',
            '5, 15, 0, 10, 4, 15, 4, 4',
          ),
        }),
        'ends before it starts',
      );
    });
    test('an anchor whose top is below its bottom', () {
      expectViolation(
        tamper(<String, String Function(String)>{
          vml1: (String x) => x.replaceFirst(
            '2, 15, 0, 10, 4, 15, 4, 4',
            '2, 15, 5, 10, 4, 15, 4, 4',
          ),
        }),
        'ends before it starts',
      );
    });
    test('an id block two VML drawings list', () {
      expectViolation(
        tamper(<String, String Function(String)>{
          vml2: (String x) => x.replaceFirst('data="2"', 'data="1,2"'),
        }),
        'block 1 is listed',
      );
    });
    test('a shape id two VML drawings use', () {
      expectViolation(
        tamper(<String, String Function(String)>{
          vml2: (String x) => x
              .replaceFirst('data="2"', 'data="1,2"')
              .replaceFirst('_x0000_s2049', '_x0000_s1025'),
        }),
        'shape id _x0000_s1025 is used',
      );
    });
    test('a shape id outside the blocks of its drawing', () {
      expectViolation(
        tamper(<String, String Function(String)>{
          vml1: (String x) => x.replaceFirst('_x0000_s1026', '_x0000_s5000'),
        }),
        'outside the id blocks',
      );
    });
  });

  group('rule 30: pictures', () {
    const String drawing1 = 'xl/drawings/drawing1.xml';
    const String drawingRels1 = 'xl/drawings/_rels/drawing1.xml.rels';
    const String sheetRels1 = 'xl/worksheets/_rels/sheet1.xml.rels';
    const String types = '[Content_Types].xml';

    /// Two sheets of pictures: `P` with the PNG at B2 (cNvPr 2) and the
    /// JPEG from B6 to E11 (cNvPr 3), `Q` with the same PNG at A1.
    Uint8List picturesBook() {
      final XlsxWriter book = XlsxWriter();
      book.addSheet('P')
        ..row(<Object?>['x'])
        ..picture(
          XlsxPicture(
            XlsxImage(png4x2),
            const XlsxOneCellAnchor(XlsxAnchorPoint(1, 1)),
          ),
        )
        ..picture(
          XlsxPicture(
            XlsxImage(jpeg3x5),
            XlsxTwoCellAnchor.range(const XlsxRange(5, 1, 9, 3)),
          ),
        );
      book
          .addSheet('Q')
          .picture(
            XlsxPicture(
              XlsxImage(png4x2),
              const XlsxOneCellAnchor(XlsxAnchorPoint(0, 0)),
            ),
          );
      return book.close().bytes;
    }

    Uint8List tamper(Map<String, String Function(String xml)> edits) =>
        _rebuild(
          picturesBook(),
          edit: <String, String? Function(String)>{
            for (final MapEntry<String, String Function(String)> e
                in edits.entries)
              e.key: e.value,
          },
        );

    /// Expects a rule 30 violation that contains [fragment].
    void expectViolation(Uint8List bytes, String fragment) {
      final List<String> violations = checkXlsx(bytes);
      expect(
        violations.where(
          (String v) => v.startsWith('rule 30:') && v.contains(fragment),
        ),
        isNotEmpty,
        reason: 'violations: $violations',
      );
    }

    test('a workbook with pictures is clean', () {
      expect(checkXlsx(picturesBook()), isEmpty);
    });
    test('the book has the parts the tests change', () {
      final Map<String, String> parts = <String, String>{
        for (final ArchiveFile f
            in ZipDecoder().decodeBytes(picturesBook()).files)
          if (!f.name.startsWith('xl/media/')) f.name: utf8.decode(f.content),
      };
      expect(parts[_sheet1], endsWith('<drawing r:id="rId1"/></worksheet>'));
      expect(parts[sheetRels1], contains('Id="rId1" Type="$_drawingRelType"'));
      final String drawing = parts[drawing1]!;
      expect(
        drawing,
        contains(
          '<xdr:from><xdr:col>1</xdr:col><xdr:colOff>0</xdr:colOff>'
          '<xdr:row>1</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:from>'
          '<xdr:ext cx="38100" cy="19050"/>',
        ),
      );
      expect(
        drawing,
        contains(
          '<xdr:from><xdr:col>1</xdr:col><xdr:colOff>0</xdr:colOff>'
          '<xdr:row>5</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:from>'
          '<xdr:to><xdr:col>4</xdr:col><xdr:colOff>0</xdr:colOff>'
          '<xdr:row>10</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:to>',
        ),
      );
      expect(drawing, contains('<a:ext cx="38100" cy="19050"/>'));
      expect(drawing, contains('<xdr:cNvPr id="2" name="Picture 1"/>'));
      expect(drawing, contains('<xdr:cNvPr id="3" name="Picture 2"/>'));
      expect(drawing, contains('<a:blip r:embed="rId1"/>'));
      expect(drawing, contains('<a:blip r:embed="rId2"/>'));
      expect(
        parts[drawingRels1],
        allOf(
          contains(
            'Id="rId1" Type="$_imageRelType" Target="../media/image1.png"',
          ),
          contains(
            'Id="rId2" Type="$_imageRelType" Target="../media/image2.jpeg"',
          ),
        ),
      );
      expect(
        parts[types],
        allOf(
          contains('<Default Extension="png" ContentType="image/png"/>'),
          contains('<Default Extension="jpeg" ContentType="image/jpeg"/>'),
        ),
      );
    });
    test('a drawing r:id the sheet does not declare', () {
      expectViolation(
        tamper(<String, String Function(String)>{
          _sheet1: (String x) => x.replaceFirst(
            '<drawing r:id="rId1"/>',
            '<drawing r:id="rId9"/>',
          ),
        }),
        'drawing r:id "rId9" is not a drawing relationship',
      );
    });
    test('a drawing r:id of another relationship type', () {
      expectViolation(
        tamper(<String, String Function(String)>{
          sheetRels1: (String x) =>
              x.replaceFirst(_drawingRelType, _imageRelType),
        }),
        'drawing r:id "rId1" is not a drawing relationship',
      );
    });
    test('a from column past the last', () {
      expectViolation(
        tamper(<String, String Function(String)>{
          drawing1: (String x) => x.replaceFirst(
            '<xdr:col>1</xdr:col>',
            '<xdr:col>16384</xdr:col>',
          ),
        }),
        'lies outside the sheet',
      );
    });
    test('a to row past the last', () {
      expectViolation(
        tamper(<String, String Function(String)>{
          drawing1: (String x) => x.replaceFirst(
            '<xdr:row>10</xdr:row>',
            '<xdr:row>1048576</xdr:row>',
          ),
        }),
        'lies outside the sheet',
      );
    });
    test('a negative cell', () {
      expectViolation(
        tamper(<String, String Function(String)>{
          drawing1: (String x) =>
              x.replaceFirst('<xdr:row>1</xdr:row>', '<xdr:row>-1</xdr:row>'),
        }),
        'lies outside the sheet',
      );
    });
    test('a marker that is not numbers', () {
      expectViolation(
        tamper(<String, String Function(String)>{
          drawing1: (String x) => x.replaceFirst(
            '<xdr:colOff>0</xdr:colOff>',
            '<xdr:colOff>x</xdr:colOff>',
          ),
        }),
        'is not four integers',
      );
    });
    test('a to row before its from', () {
      expectViolation(
        tamper(<String, String Function(String)>{
          drawing1: (String x) =>
              x.replaceFirst('<xdr:row>10</xdr:row>', '<xdr:row>4</xdr:row>'),
        }),
        'ends before it starts',
      );
    });
    test('a to column before its from', () {
      expectViolation(
        tamper(<String, String Function(String)>{
          drawing1: (String x) => x.replaceFirst(
            '<xdr:to><xdr:col>4</xdr:col>',
            '<xdr:to><xdr:col>0</xdr:col>',
          ),
        }),
        'ends before it starts',
      );
    });
    test('a to offset before its from in the same cell', () {
      expectViolation(
        tamper(<String, String Function(String)>{
          drawing1: (String x) => x
              .replaceFirst(
                '<xdr:row>10</xdr:row><xdr:rowOff>0</xdr:rowOff>',
                '<xdr:row>5</xdr:row><xdr:rowOff>0</xdr:rowOff>',
              )
              .replaceFirst(
                '<xdr:row>5</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:from>',
                '<xdr:row>5</xdr:row><xdr:rowOff>9525</xdr:rowOff></xdr:from>',
              ),
        }),
        'ends before it starts',
      );
    });
    test('an anchor ext of size 0', () {
      expectViolation(
        tamper(<String, String Function(String)>{
          drawing1: (String x) =>
              x.replaceFirst('<xdr:ext cx="38100"', '<xdr:ext cx="0"'),
        }),
        'cx "0"',
      );
    });
    test('a negative a:ext', () {
      expectViolation(
        tamper(<String, String Function(String)>{
          drawing1: (String x) => x.replaceFirst(
            '<a:ext cx="38100" cy="19050"/>',
            '<a:ext cx="38100" cy="-5"/>',
          ),
        }),
        'cy "-5"',
      );
    });
    test('two pictures sharing a cNvPr id', () {
      expectViolation(
        tamper(<String, String Function(String)>{
          drawing1: (String x) =>
              x.replaceFirst('cNvPr id="3"', 'cNvPr id="2"'),
        }),
        'cNvPr id "2" repeats',
      );
    });
    test('a blip r:embed the drawing does not declare', () {
      expectViolation(
        tamper(<String, String Function(String)>{
          drawing1: (String x) =>
              x.replaceFirst('r:embed="rId2"', 'r:embed="rId7"'),
        }),
        'r:embed "rId7" is not an image relationship',
      );
    });
    test('a blip r:embed of another relationship type', () {
      expectViolation(
        tamper(<String, String Function(String)>{
          drawingRels1: (String x) =>
              x.replaceFirst(_imageRelType, _drawingRelType),
        }),
        'r:embed "rId1" is not an image relationship',
      );
    });
    test('a blip whose image part is missing', () {
      expectViolation(
        tamper(<String, String Function(String)>{
          drawingRels1: (String x) =>
              x.replaceFirst('../media/image2.jpeg', '../media/image9.jpeg'),
        }),
        'xl/media/image9.jpeg, which does not exist',
      );
    });
    test('a blip whose image has another content type', () {
      expectViolation(
        tamper(<String, String Function(String)>{
          types: (String x) => x.replaceFirst(
            'ContentType="image/jpeg"',
            'ContentType="image/gif"',
          ),
        }),
        'content type "image/gif"',
      );
    });
  });

  group('rule 31: tables', () {
    const String table1 = 'xl/tables/table1.xml';
    const String table2 = 'xl/tables/table2.xml';
    const String table3 = 'xl/tables/table3.xml';

    /// Two sheets of tables: `T` with `Sales` over A1:C5 (header, three
    /// data rows, totals), `Costs` over E1:F3, an auto filter on H1:I3 and
    /// a merge of H6:I6; `U` with `Third` over A1:B3; and the workbook name
    /// `Rate`.
    Uint8List tablesBook() {
      final XlsxWriter book = XlsxWriter();
      book.defineName(const XlsxDefinedName('Rate', '0.18'));
      book.addSheet('T')
        ..table(
          XlsxTable('Sales', XlsxRange.parse('A1:C5'), const <XlsxTableColumn>[
            XlsxTableColumn('Region', totalsLabel: 'Total'),
            XlsxTableColumn('Amount', totalsFunction: XlsxTotalsFunction.sum),
            XlsxTableColumn('Note'),
          ], totalsRow: true),
        )
        ..table(
          XlsxTable('Costs', XlsxRange.parse('E1:F3'), const <XlsxTableColumn>[
            XlsxTableColumn('Item'),
            XlsxTableColumn('Cost'),
          ]),
        )
        ..autoFilter(XlsxRange.parse('H1:I3'))
        ..merge(XlsxRange.parse('H6:I6'))
        ..row(<Object?>[])
        ..row(<Object?>['North', 1, null, null, 'Paper', 2]);
      book
          .addSheet('U')
          .table(
            XlsxTable(
              'Third',
              XlsxRange.parse('A1:B3'),
              const <XlsxTableColumn>[
                XlsxTableColumn('X'),
                XlsxTableColumn('Y'),
              ],
            ),
          );
      return book.close().bytes;
    }

    Uint8List tamper(Map<String, String Function(String xml)> edits) =>
        _rebuild(
          tablesBook(),
          edit: <String, String? Function(String)>{
            for (final MapEntry<String, String Function(String)> e
                in edits.entries)
              e.key: e.value,
          },
        );

    /// Expects a rule 31 violation that contains [fragment].
    void expectViolation(Uint8List bytes, String fragment) {
      final List<String> violations = checkXlsx(bytes);
      expect(
        violations.where(
          (String v) => v.startsWith('rule 31:') && v.contains(fragment),
        ),
        isNotEmpty,
        reason: 'violations: $violations',
      );
    }

    /// Replaces [from] by [to] once in a part, failing when it is missing.
    String Function(String) swap(String from, String to) => (String xml) {
      expect(xml, contains(from));
      return xml.replaceFirst(from, to);
    };

    test('a workbook with tables is clean', () {
      expect(checkXlsx(tablesBook()), isEmpty);
    });

    test('table ids are unique across the workbook', () {
      expectViolation(
        tamper(<String, String Function(String)>{
          table3: swap('id="3"', 'id="1"'),
        }),
        'id "1"',
      );
    });

    test('table names are unique ignoring case', () {
      expectViolation(
        tamper(<String, String Function(String)>{
          table2: swap(
            'name="Costs" displayName="Costs"',
            'name="SALES" displayName="SALES"',
          ),
        }),
        'name "SALES"',
      );
    });

    test('a table name is not a defined name', () {
      expectViolation(
        tamper(<String, String Function(String)>{
          table3: swap(
            'name="Third" displayName="Third"',
            'name="rate" displayName="rate"',
          ),
        }),
        'name "rate"',
      );
    });

    test('a ref lies inside the sheet', () {
      expectViolation(
        tamper(<String, String Function(String)>{
          table3: swap('ref="A1:B3"', 'ref="A1:B1048577"'),
        }),
        'ref "A1:B1048577"',
      );
    });

    test('a ref has rows for the header, a data row and the totals', () {
      expectViolation(
        tamper(<String, String Function(String)>{
          table1: swap('ref="A1:C5"', 'ref="A1:C2"'),
        }),
        'ref "A1:C2" has 2 rows',
      );
    });

    test('tableColumns count equals the width and the children', () {
      expectViolation(
        tamper(<String, String Function(String)>{
          table1: swap('<tableColumns count="3">', '<tableColumns count="4">'),
        }),
        'count "4"',
      );
      expectViolation(
        tamper(<String, String Function(String)>{
          table1: swap('<tableColumn id="3" name="Note"/>', ''),
        }),
        '2 tableColumn',
      );
    });

    test('column names are unique ignoring case', () {
      expectViolation(
        tamper(<String, String Function(String)>{
          table2: swap('name="Cost"', 'name="ITEM"'),
        }),
        'column "ITEM"',
      );
    });

    test('every header cell is a string equal to its column name', () {
      // The text differs.
      expectViolation(
        tamper(<String, String Function(String)>{
          table1: swap('name="Note"', 'name="Notes"'),
        }),
        'header cell C1',
      );
      // Not a string.
      expectViolation(
        tamper(<String, String Function(String)>{
          _sheet1: (String xml) {
            final RegExp c1 = RegExp('<c r="F1" t="s"><v>[0-9]+</v></c>');
            expect(xml, contains(c1));
            return xml.replaceFirst(c1, '<c r="F1"><v>1</v></c>');
          },
        }),
        'header cell F1',
      );
      // Missing.
      expectViolation(
        tamper(<String, String Function(String)>{
          _sheet2: (String xml) {
            final RegExp a1 = RegExp('<c r="A1" t="s"><v>[0-9]+</v></c>');
            expect(xml, contains(a1));
            return xml.replaceFirst(a1, '');
          },
        }),
        'header cell A1',
      );
    });

    test('autoFilter covers the ref without the totals row', () {
      expectViolation(
        tamper(<String, String Function(String)>{
          table1: swap(
            '<autoFilter ref="A1:C4"/>',
            '<autoFilter ref="A1:C5"/>',
          ),
        }),
        'autoFilter ref "A1:C5"',
      );
    });

    test('tables do not overlap each other, the filter or a merge', () {
      expectViolation(
        tamper(<String, String Function(String)>{
          table2: swap('ref="E1:F3"', 'ref="C1:D3"'),
        }),
        'overlaps the table',
      );
      expectViolation(
        tamper(<String, String Function(String)>{
          _sheet1: swap(
            '<autoFilter ref="H1:I3"/>',
            '<autoFilter ref="F3:G4"/>',
          ),
        }),
        'overlaps the autoFilter',
      );
      expectViolation(
        tamper(<String, String Function(String)>{
          _sheet1: swap('<mergeCell ref="H6:I6"/>', '<mergeCell ref="B5:C5"/>'),
        }),
        'overlaps the mergeCell',
      );
    });

    test('a tablePart names a table relationship', () {
      expectViolation(
        tamper(<String, String Function(String)>{
          _sheet1: swap('<tablePart r:id="rId2"/>', '<tablePart r:id="rId9"/>'),
        }),
        'tablePart r:id "rId9"',
      );
    });

    test('every table part is named by exactly one tablePart', () {
      expectViolation(
        tamper(<String, String Function(String)>{
          _sheet1: swap('<tablePart r:id="rId2"/>', ''),
        }),
        '$table2 is named by 0',
      );
      expectViolation(
        tamper(<String, String Function(String)>{
          _sheet1: swap('<tablePart r:id="rId2"/>', '<tablePart r:id="rId1"/>'),
        }),
        '$table1 is named by 2',
      );
    });
  });
}

const String _drawingRelType =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships/'
    'drawing';

const String _imageRelType =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships/'
    'image';
