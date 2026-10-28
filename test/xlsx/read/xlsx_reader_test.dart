import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

import 'support/workbook_builder.dart';

List<XlsxWarningCode> _codes(XlsxReader r) =>
    r.warnings.map((XlsxWarning w) => w.code).toList();

/// A copy of [zip] with the first byte of [text] changed, so the stored
/// entry holding it fails its CRC check.
Uint8List _corrupt(Uint8List zip, String text) {
  final List<int> needle = utf8.encode(text);
  for (int i = 0; i + needle.length <= zip.length; i++) {
    bool same = true;
    for (int k = 0; k < needle.length; k++) {
      if (zip[i + k] != needle[k]) {
        same = false;
        break;
      }
    }
    if (same) {
      return Uint8List.fromList(zip)..[i] = 0x5A;
    }
  }
  throw StateError('"$text" is not in the archive.');
}

void main() {
  test('reads rows of typed cells', () {
    final XlsxWriter w = XlsxWriter();
    w.addSheet('Data')
      ..row(<Object?>['Code', 'Price', 'Active'])
      ..row(<Object?>['A-1', XlsxDecimal('12.30'), true]);
    final XlsxReader r = XlsxReader(w.close().bytes);
    final List<XlsxReadRow> rows = r.rows('Data').toList();
    expect(rows[1].cells.map((XlsxReadCell c) => c.value), <Object?>[
      'A-1',
      XlsxDecimal('12.30'),
      true,
    ]);
    expect(
      rows[0],
      XlsxReadRow(0, const <XlsxReadCell>[
        XlsxReadCell(0, 'Code'),
        XlsxReadCell(1, 'Price'),
        XlsxReadCell(2, 'Active'),
      ]),
    );
    expect(r.warnings, isEmpty);
  });

  test('reads a formula with its cached value', () {
    final XlsxWriter w = XlsxWriter();
    w.addSheet('F').row(<Object?>[1, const XlsxFormula('A1*2', cached: 2)]);
    final XlsxReader r = XlsxReader(w.close().bytes);
    expect(
      r.rows('F').single.cells[1],
      XlsxReadCell(1, XlsxDecimal('2'), formula: 'A1*2'),
    );
  });

  test('lists sheets with index and visibility', () {
    final XlsxWriter w = XlsxWriter();
    w.addSheet('One').row(<Object?>[1]);
    w.addSheet('Two', visibility: XlsxSheetVisibility.hidden);
    final XlsxReader r = XlsxReader(w.close().bytes);
    expect(r.sheets.map((XlsxReadSheet s) => s.name), <String>['One', 'Two']);
    expect(r.sheets[1].index, 1);
    expect(r.sheets[0].visibility, XlsxSheetVisibility.visible);
    expect(r.sheets[1].visibility, XlsxSheetVisibility.hidden);
    expect(r.rowsAt(1), isEmpty);
  });

  test('re-reading a sheet replaces its warnings', () {
    final XlsxReader r = XlsxReader(
      buildWorkbook(<String, String?>{
        'S': worksheet('<row r="1"><c r="A1" t="b"><v>7</v></c></row>'),
      }),
    );
    r.rows('S').toList();
    r.rows('S').toList();
    expect(_codes(r), <XlsxWarningCode>[XlsxWarningCode.booleanInvalid]);
    expect(r.warnings.single.count, 1);
    expect(r.warnings.single.cells, <String>['A1']);
  });

  test('a sheet stopped early keeps its warnings; another reads', () {
    final XlsxReader r = XlsxReader(
      buildWorkbook(<String, String?>{
        'A': worksheet(
          '<row r="1"><c r="A1" t="b"><v>x</v></c></row>'
          '<row r="2"><c r="A2" t="b"><v>y</v></c></row>',
        ),
        'B': worksheet('<row r="1"><c r="B1" t="b"><v>z</v></c></row>'),
      }),
    );
    final Iterator<XlsxReadRow> it = r.rows('A').iterator;
    expect(it.moveNext(), isTrue);
    final List<XlsxReadRow> b = r.rows('B').toList();
    expect(b.single.cells.single.column, 1);
    expect(r.warnings.map((XlsxWarning w) => '${w.sheet} ${w.cells}'), <String>[
      'A [A1]',
      'B [B1]',
    ]);
  });

  test('t="s" without sharedStrings.xml warns', () {
    for (final bool relation in <bool>[false, true]) {
      final XlsxReader r = XlsxReader(
        buildWorkbook(<String, String?>{
          'S': worksheet('<row r="1"><c r="A1" t="s"><v>0</v></c></row>'),
        }, sharedStringsRelation: relation),
      );
      expect(r.rows('S').single.cells.single.value, isNull);
      expect(_codes(r), <XlsxWarningCode>[XlsxWarningCode.sharedStringInvalid]);
    }
  });

  test('lists a sheet with a missing part and warns', () {
    final XlsxReader r = XlsxReader(
      buildWorkbook(<String, String?>{'Gone': null, 'Here': worksheet('')}),
    );
    expect(r.sheets.map((XlsxReadSheet s) => s.name), <String>['Gone', 'Here']);
    expect(_codes(r), <XlsxWarningCode>[XlsxWarningCode.sheetPartMissing]);
    expect(r.rows('Gone'), isEmpty);
    expect(r.rows('Gone'), isEmpty);
    expect(_codes(r), <XlsxWarningCode>[XlsxWarningCode.sheetPartMissing]);
    expect(r.warnings.single.count, 1);
  });

  test('unknown sheet name throws ArgumentError', () {
    final XlsxReader r = XlsxReader(
      buildWorkbook(<String, String?>{'S': worksheet('')}),
    );
    expect(() => r.rows('T'), throwsArgumentError);
    expect(() => r.rowsAt(1), throwsRangeError);
    expect(() => r.rowsAt(-1), throwsRangeError);
  });

  test('decompresses nothing before rows are read', () {
    final Uint8List zip = _corrupt(
      buildWorkbook(<String, String?>{
        'Bad': worksheet('<row r="1"><c r="A1"><v>1</v></c></row>'),
        'Good': worksheet('<row r="1"><c r="A1"><v>2</v></c></row>'),
      }, store: true),
      '<row r="1"><c r="A1"><v>1',
    );
    final XlsxReader r = XlsxReader(zip);
    expect(r.sheets, hasLength(2));
    expect(
      () => r.rows('Bad').toList(),
      throwsA(
        isA<XlsxReadException>().having(
          (XlsxReadException e) => e.reason,
          'reason',
          XlsxReadFailure.corruptZip,
        ),
      ),
    );
    expect(r.rows('Good').single.cells.single.value, XlsxDecimal('2'));
  });

  test('a shared strings error propagates and is retried', () {
    final XlsxReader r = XlsxReader(
      buildWorkbook(<String, String?>{
        'S': worksheet('<row r="1"><c r="A1" t="s"><v>0</v></c></row>'),
      }, sharedStrings: '<sst xmlns="$mainNs"><si><t>&bad;</t></si></sst>'),
    );
    for (int i = 0; i < 2; i++) {
      expect(
        () => r.rows('S').toList(),
        throwsA(
          isA<XlsxReadException>().having(
            (XlsxReadException e) => e.reason,
            'reason',
            XlsxReadFailure.malformedXml,
          ),
        ),
      );
    }
  });

  test('reads shared strings once', () {
    final XlsxReader r = XlsxReader(
      buildWorkbook(
        <String, String?>{
          'S': worksheet('<row r="1"><c r="A1" t="s"><v>1</v></c></row>'),
        },
        sharedStrings:
            '<sst xmlns="$mainNs"><si><t>a</t></si>'
            '<si><t>b</t></si></sst>',
      ),
    );
    expect(r.rows('S').single.cells.single.value, 'b');
    expect(r.rows('S').single.cells.single.value, 'b');
  });

  test('the constructor checks the limits', () {
    expect(
      () => XlsxReader(
        buildWorkbook(<String, String?>{'S': worksheet('')}),
        limits: const XlsxReadLimits(maxDepth: 0),
      ),
      throwsArgumentError,
    );
  });

  test('warnings is an unmodifiable live view', () {
    final XlsxReader r = XlsxReader(
      buildWorkbook(<String, String?>{
        'S': worksheet('<row r="1"><c r="A1" t="b"><v>2</v></c></row>'),
      }),
    );
    final List<XlsxWarning> view = r.warnings;
    expect(view, isEmpty);
    r.rows('S').toList();
    expect(view, hasLength(1));
    expect(() => view.clear(), throwsUnsupportedError);
  });

  test('a file that is not a ZIP throws XlsxReadException', () {
    expect(
      () => XlsxReader(Uint8List.fromList(utf8.encode('hello'))),
      throwsA(isA<XlsxReadException>()),
    );
  });
}
