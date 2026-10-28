import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

import 'support/workbook_builder.dart';
import 'support/zip_builder.dart';

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

  test('reads back the dates, times and durations the writer wrote', () {
    final XlsxWriter w = XlsxWriter();
    w.addSheet('D').row(<Object?>[
      DateTime(2026, 10, 28, 13, 45, 30),
      const XlsxDate(2026, 2, 28),
      const XlsxCell(0.5, style: XlsxStyle(numFmt: XlsxNumFmt.time)),
      const XlsxCell(1.5, style: XlsxStyle(numFmt: XlsxNumFmt.elapsedTime)),
    ]);
    final XlsxReader r = XlsxReader(w.close().bytes);
    final List<XlsxReadCell> cells = r.rows('D').single.cells;
    expect(cells.map((XlsxReadCell c) => c.value), <Object?>[
      DateTime.utc(2026, 10, 28, 13, 45, 30),
      DateTime.utc(2026, 2, 28),
      const Duration(hours: 12),
      const Duration(hours: 36),
    ]);
    expect((cells[0].value! as DateTime).isUtc, isTrue);
    expect((cells[1].value! as DateTime).isUtc, isTrue);
    expect(cells.map((XlsxReadCell c) => c.isDate), everyElement(isTrue));
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

  test('formula groups are per sheet and named with their sheet', () {
    final XlsxReader r = XlsxReader(
      buildWorkbook(<String, String?>{
        'A': worksheet(
          '<row r="1"><c r="A1"><f t="shared" ref="A1:A2" si="0">1</f>'
          '<v>1</v></c></row>'
          '<row r="2"><c r="A2"><f t="shared" si="0"/><v>1</v></c></row>',
        ),
        'B': worksheet(
          '<row r="1"><c r="B1"><f t="shared" si="0"/><v>2</v></c></row>',
        ),
      }),
    );
    expect(
      r.rowsAt(0).last.cells.single.formulaGroup,
      const XlsxFormulaGroup(
        XlsxFormulaGroupKind.shared,
        XlsxRange(0, 0, 1, 0),
        isMaster: false,
      ),
    );
    // Sheet A's si 0 is not B's.
    expect(r.rowsAt(1).single.cells.single.formulaGroup, isNull);
    final XlsxWarning warning = r.warnings.single;
    expect(warning.code, XlsxWarningCode.formulaGroupInvalid);
    expect(warning.sheet, 'B');
    expect(warning.cells, <String>['B1']);
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

  test('reading a sheet twice gives the same shared string', () {
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

  group('styles and the date system', () {
    const String styles =
        '<styleSheet xmlns="$mainNs"><numFmts count="1">'
        '<numFmt numFmtId="164" formatCode="yyyy-mm-dd"/></numFmts>'
        '<cellXfs count="2"><xf numFmtId="0"/><xf numFmtId="164"/>'
        '</cellXfs></styleSheet>';
    final String sheet = worksheet(
      '<row r="1"><c r="A1" s="1"><v>0</v></c></row>',
    );

    test('opening reads styles', () {
      final Uint8List zip = _corrupt(
        buildWorkbook(
          <String, String?>{'S': sheet},
          styles: styles,
          store: true,
        ),
        '<styleSheet',
      );
      expect(
        () => XlsxReader(zip),
        throwsA(
          isA<XlsxReadException>().having(
            (XlsxReadException e) => e.reason,
            'reason',
            XlsxReadFailure.corruptZip,
          ),
        ),
      );
      final XlsxReader r = XlsxReader(
        buildWorkbook(<String, String?>{'S': sheet}, styles: styles),
      );
      expect(r.rows('S').single.cells.single.numberFormat, 'yyyy-mm-dd');
    });

    test('date1904 is the workbook date system', () {
      final XlsxReader r1900 = XlsxReader(
        buildWorkbook(<String, String?>{'S': sheet}, styles: styles),
      );
      expect(r1900.date1904, isFalse);
      final XlsxReader r = XlsxReader(
        buildWorkbook(
          <String, String?>{'S': sheet},
          styles: styles,
          date1904: true,
        ),
      );
      expect(r.date1904, isTrue);
      expect(r.rows('S').single.cells.single.value, DateTime.utc(1904));
      expect(r.warnings, isEmpty);
    });

    test('a malformed styles part fails the open', () {
      expect(
        () => XlsxReader(
          buildWorkbook(<String, String?>{
            'S': sheet,
          }, styles: '<styleSheet xmlns="$mainNs"><cellXfs>'),
        ),
        throwsA(
          isA<XlsxReadException>()
              .having(
                (XlsxReadException e) => e.reason,
                'reason',
                XlsxReadFailure.malformedXml,
              )
              .having((XlsxReadException e) => e.part, 'part', 'xl/styles.xml'),
        ),
      );
    });

    test('1,000 distinct undefined format ids keep at most 11 warnings', () {
      const int n = 1000;
      final StringBuffer xfs = StringBuffer();
      final StringBuffer rows = StringBuffer();
      for (int i = 0; i < n; i++) {
        xfs.write('<xf numFmtId="${1000 + i}"/>');
        rows.write(
          '<row r="${i + 1}"><c r="A${i + 1}" s="$i"><v>1</v></c></row>',
        );
      }
      final XlsxReader r = XlsxReader(
        buildWorkbook(
          <String, String?>{'S': worksheet(rows.toString())},
          styles:
              '<styleSheet xmlns="$mainNs"><cellXfs count="$n">$xfs'
              '</cellXfs></styleSheet>',
        ),
      );
      expect(r.rows('S'), hasLength(n));
      final List<XlsxWarning> unresolved = r.warnings
          .where(
            (XlsxWarning w) => w.code == XlsxWarningCode.unresolvedNumberFormat,
          )
          .toList();
      expect(unresolved.length, lessThanOrEqualTo(11));
      expect(
        unresolved.fold<int>(0, (int sum, XlsxWarning w) => sum + w.count),
        n,
      );
      expect(unresolved.last.detail, isNull);
    });

    test('no styles part reads General', () {
      final XlsxReader r = XlsxReader(
        buildWorkbook(<String, String?>{
          'S': worksheet('<row r="1"><c r="A1" s="0"><v>5</v></c></row>'),
        }),
      );
      expect(
        r.rows('S').single.cells.single,
        XlsxReadCell(0, XlsxDecimal('5')),
      );
      expect(r.warnings, isEmpty);
    });
  });

  test('duplicate sheet names keep separate warnings', () {
    final XlsxReader r = XlsxReader(
      buildWorkbookList(<(String, String?)>[
        ('A', worksheet('<row r="1"><c r="A1" t="b"><v>x</v></c></row>')),
        ('A', worksheet('<row r="1"><c r="B1" t="b"><v>y</v></c></row>')),
      ]),
    );
    r.rowsAt(0).toList();
    r.rowsAt(1).toList();
    expect(r.warnings.map((XlsxWarning w) => '${w.sheet} ${w.cells}'), <String>[
      'A [A1]',
      'A [B1]',
    ]);
    r.rowsAt(1).toList();
    expect(r.warnings.map((XlsxWarning w) => '${w.sheet} ${w.cells}'), <String>[
      'A [A1]',
      'A [B1]',
    ]);
    expect(r.warnings.map((XlsxWarning w) => w.count), <int>[1, 1]);
  });

  test('an older iterator adds no warnings after a newer pass starts', () {
    final XlsxReader r = XlsxReader(
      buildWorkbook(<String, String?>{
        'S': worksheet(
          '<row r="1"><c r="A1" t="b"><v>x</v></c></row>'
          '<row r="2"><c r="A2" t="b"><v>y</v></c></row>'
          '<row r="3"><c r="A3" t="b"><v>z</v></c></row>',
        ),
      }),
    );
    final Iterator<XlsxReadRow> first = r.rowsAt(0).iterator;
    expect(first.moveNext(), isTrue);
    expect(r.rowsAt(0).toList(), hasLength(3));
    int rows = 1;
    while (first.moveNext()) {
      rows++;
    }
    expect(rows, 3);
    expect(_codes(r), <XlsxWarningCode>[XlsxWarningCode.booleanInvalid]);
    expect(r.warnings.single.count, 3);
    expect(r.warnings.single.cells, <String>['A1', 'A2', 'A3']);
  });

  test('a missing part warns under its index', () {
    final XlsxReader r = XlsxReader(
      buildWorkbookList(<(String, String?)>[('A', null), ('A', null)]),
    );
    expect(r.warnings.map((XlsxWarning w) => w.count), <int>[1, 1]);
    r.rowsAt(1).toList();
    expect(r.warnings.map((XlsxWarning w) => w.count), <int>[1, 1]);
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

  test('an exception message never carries the input at full length', () {
    final String big = 'A' * 1000000;
    for (final String xml in <String>[
      worksheet('<row r="1"><c><v>&$big;</v></c></row>'),
      worksheet('<row r="1"><c><v>1</v></c></row><$big></x$big>'),
    ]) {
      final XlsxReader reader = XlsxReader(
        buildWorkbook(<String, String>{'S': xml}),
      );
      expect(
        () => reader.rowsAt(0).toList(),
        throwsA(
          isA<XlsxReadException>()
              .having(
                (XlsxReadException e) => e.reason,
                'reason',
                XlsxReadFailure.malformedXml,
              )
              .having(
                (XlsxReadException e) => e.message.length,
                'message length',
                lessThan(200),
              ),
        ),
      );
    }
  });

  test('opening refuses more sheets than maxSheets', () {
    final Uint8List bytes = buildWorkbook(<String, String?>{
      'A': null,
      'B': null,
      'C': null,
    });
    expect(
      XlsxReader(bytes, limits: const XlsxReadLimits(maxSheets: 3)).sheets,
      hasLength(3),
    );
    expect(
      () => XlsxReader(bytes, limits: const XlsxReadLimits(maxSheets: 2)),
      throwsA(
        isA<XlsxReadException>()
            .having(
              (XlsxReadException e) => e.reason,
              'reason',
              XlsxReadFailure.limitExceeded,
            )
            .having((XlsxReadException e) => e.part, 'part', 'xl/workbook.xml'),
      ),
    );
  });

  test('a Strict workbook found by its content type is refused', () {
    // No _rels/.rels: the workbook is found through the content type.
    final Uint8List bytes = buildZip(<String, List<int>>{
      '[Content_Types].xml': utf8.encode(
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/'
        'content-types"><Override PartName="/xl/workbook.xml" '
        'ContentType="application/vnd.openxmlformats-officedocument.'
        'spreadsheetml.sheet.main+xml"/></Types>',
      ),
      'xl/workbook.xml': utf8.encode(
        '<workbook xmlns="http://purl.oclc.org/ooxml/spreadsheetml/main">'
        '<sheets><sheet name="A"/></sheets></workbook>',
      ),
    });
    expect(
      () => XlsxReader(bytes),
      throwsA(
        isA<XlsxReadException>().having(
          (XlsxReadException e) => e.reason,
          'reason',
          XlsxReadFailure.unsupportedFormat,
        ),
      ),
    );
  });

  test('sheets has no setter', () {
    final dynamic reader = XlsxReader(
      buildWorkbook(<String, String?>{'A': null}),
    );
    expect(
      // A dynamic call is the only way to reach a setter that must not
      // exist: with a static type this would not compile.
      // ignore: avoid_dynamic_calls
      () => reader.sheets = <XlsxReadSheet>[],
      throwsA(isA<NoSuchMethodError>()),
    );
  });
}
