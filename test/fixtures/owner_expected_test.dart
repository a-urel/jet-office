import 'dart:convert';
import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

import '../support/owner_expected.dart';
import '../xlsx/read/support/workbook_builder.dart';

/// The example of the format, as the owner would confirm it.
const String _example = '''
{
  "file": "excel_products.xlsx",
  "producer": "Microsoft Excel for Mac 16.90",
  "confirmedBy": "owner",
  "date1904": false,
  "sheets": [
    {
      "name": "Ürünler",
      "visibility": "visible",
      "merges": ["G2:G4"],
      "hiddenRows": [9],
      "rows": [
        ["Kod", "Ürün adı", "Fiyat", "KDV", "Tarih", "Aktif"],
        ["00123", "Çay 500 g", {"n": "149.90", "format": "#,##0.00 ₺"},
         {"n": "0.2"}, {"date": "2026-10-28"}, true],
        ["00124", null, {"n": "12", "formula": "B3*2"},
         {"error": "#N/A"}, {"date": "2026-10-28T13:45:00"},
         {"duration": "13:30:00"}]
      ]
    }
  ],
  "warnings": []
}
''';

/// A workbook with one sheet `S`, whose row 1 holds [cell] and which has
/// nothing else.
XlsxReader _reader(Object? cell) {
  final XlsxWriter w = XlsxWriter();
  w.addSheet('S').row(<Object?>[cell]);
  return XlsxReader(w.close().bytes);
}

/// An expectation for sheet `S` whose row 1 holds [cell] (JSON text).
OwnerExpected _expect(String cell, {String extra = ''}) => parseOwnerExpected(
  '{"file": "f.xlsx", "producer": "p", "confirmedBy": "owner", '
  '"sheets": [{"name": "S", "rows": [[$cell]]$extra}]}',
);

/// Whether [cell] (JSON text) matches the value [actual] written to A1.
List<String> _compare(String cell, Object? actual) =>
    compareOwnerFile(_expect(cell), _reader(actual));

Matcher _failsAt(String path) => throwsA(
  isA<FormatException>().having(
    (FormatException e) => e.message,
    'message',
    contains(path),
  ),
);

void main() {
  group('parseOwnerExpected', () {
    test('parses the example of the format', () {
      final OwnerExpected e = parseOwnerExpected(_example);
      expect(e.file, 'excel_products.xlsx');
      expect(e.producer, 'Microsoft Excel for Mac 16.90');
      expect(e.confirmedBy, 'owner');
      expect(e.date1904, isFalse);
      expect(e.sheets.single.name, 'Ürünler');
      expect(e.sheets.single.merges.single.ref, 'G2:G4');
      expect(e.sheets.single.hiddenRows, <int>[9]);
      expect(e.sheets.single.rows, hasLength(3));
      expect(e.warnings, isEmpty);
    });

    test('defaults: no merges, no hidden rows, visible, no warnings', () {
      final OwnerExpected e = parseOwnerExpected(
        '{"file": "f.xlsx", "producer": "p", "confirmedBy": null, '
        '"sheets": [{"name": "S", "rows": []}]}',
      );
      expect(e.confirmedBy, isNull);
      expect(e.sheets.single.merges, isEmpty);
      expect(e.sheets.single.hiddenRows, isEmpty);
      expect(e.sheets.single.visibility, XlsxSheetVisibility.visible);
      expect(e.warnings, isEmpty);
    });

    test('parses a negative duration and the veryHidden visibility', () {
      final OwnerExpected e = _expect(
        '{"duration": "-1:30:00"}',
        extra: ', "visibility": "veryHidden"',
      );
      expect(
        e.sheets.single.rows.single.single!.value,
        -const Duration(hours: 1, minutes: 30),
      );
      expect(e.sheets.single.visibility, XlsxSheetVisibility.veryHidden);
    });

    test('an object cell with no value key and no formula is refused', () {
      expect(() => _expect('{}'), _failsAt('sheets[0].rows[0][0]'));
      expect(
        () => _expect('{"format": "0.00"}'),
        _failsAt('sheets[0].rows[0][0]'),
      );
      final OwnerExpected e = _expect('{"formula": "A1+1"}');
      expect(e.sheets.single.rows.single.single!.kind, OwnerKind.empty);
    });

    test('names the path of an unknown key', () {
      expect(
        () => _expect('"a", {"s": "x", "oops": 1}'),
        _failsAt('sheets[0].rows[0][1].oops'),
      );
      expect(
        () => parseOwnerExpected(
          '{"file": "f", "producer": "p", "confirmedBy": null, '
          '"sheets": [], "extra": 1}',
        ),
        _failsAt('extra'),
      );
      expect(
        () => _expect('1', extra: ', "merge": []'),
        _failsAt('sheets[0].merge'),
      );
    });

    test('names the path of a wrong shape', () {
      expect(
        () => _expect('"a", {"n": 1}'),
        _failsAt('sheets[0].rows[0][1].n'),
      );
      expect(() => _expect('1'), _failsAt('sheets[0].rows[0][0]'));
      expect(() => _expect('{"n": "1", "s": "x"}'), _failsAt('rows[0][0]'));
      expect(() => _expect('{"date": "28.10.2026"}'), _failsAt('.date'));
      expect(() => _expect('{"duration": "1:75:00"}'), _failsAt('.duration'));
      expect(() => _expect('{"n": "1e3"}'), _failsAt('.n'));
      expect(
        () => _expect('"a"', extra: ', "hiddenRows": [-1]'),
        _failsAt('sheets[0].hiddenRows[0]'),
      );
      expect(
        () => _expect('"a"', extra: ', "merges": ["A:A"]'),
        _failsAt('sheets[0].merges[0]'),
      );
      expect(
        () => _expect('"a"', extra: ', "visibility": "gone"'),
        _failsAt('sheets[0].visibility'),
      );
      expect(
        () => parseOwnerExpected(
          '{"file": "f", "producer": "p", "confirmedBy": null, '
          '"sheets": [], "warnings": [{"code": "nope", "count": 1}]}',
        ),
        _failsAt('warnings[0].code'),
      );
      expect(() => parseOwnerExpected('[]'), throwsFormatException);
      expect(() => parseOwnerExpected('{'), throwsFormatException);
    });
  });

  group('compareOwnerFile', () {
    test('text, number, boolean and empty cells', () {
      expect(_compare('"Ürün"', 'Ürün'), isEmpty);
      expect(_compare('"Ürün"', 'Urun'), hasLength(1));
      expect(_compare('{"s": "00123"}', '00123'), isEmpty);
      expect(_compare('{"n": "149.90"}', XlsxDecimal('149.90')), isEmpty);
      expect(_compare('{"n": "149.9"}', XlsxDecimal('149.90')), isEmpty);
      expect(_compare('{"n": "149.91"}', XlsxDecimal('149.90')), hasLength(1));
      expect(_compare('{"n": "1"}', 'text'), hasLength(1));
      expect(_compare('"1"', XlsxDecimal('1')), hasLength(1));
      expect(_compare('true', true), isEmpty);
      expect(_compare('false', true), hasLength(1));
      expect(_compare('{"b": true}', true), isEmpty);
      expect(_compare('null', null), isEmpty);
      expect(_compare('null', 'x'), hasLength(1));
      expect(_compare('"x"', null), hasLength(1));
    });

    test('numbers compare with a relative tolerance of 1e-12', () {
      expect(
        _compare('{"n": "0.30000000000000004"}', XlsxDecimal('0.3')),
        isEmpty,
      );
      expect(
        _compare('{"n": "1000000.01"}', XlsxDecimal('1000000')),
        hasLength(1),
      );
      expect(_compare('{"n": "-5"}', XlsxDecimal('-5')), isEmpty);
      expect(_compare('{"n": "5"}', XlsxDecimal('-5')), hasLength(1));
    });

    test('dates and durations compare within one second', () {
      final DateTime stamp = DateTime(2026, 10, 28, 13, 45, 30);
      expect(_compare('{"date": "2026-10-28T13:45:30"}', stamp), isEmpty);
      expect(_compare('{"date": "2026-10-28T13:45:31"}', stamp), hasLength(1));
      expect(_compare('{"date": "2026-10-28"}', stamp), hasLength(1));
      expect(
        _compare('{"date": "2026-10-28"}', const XlsxDate(2026, 10, 28)),
        isEmpty,
      );
      expect(
        _compare('{"date": "2026-10-29"}', const XlsxDate(2026, 10, 28)),
        hasLength(1),
      );
      const XlsxCell twelve = XlsxCell(
        0.5,
        style: XlsxStyle(numFmt: XlsxNumFmt.time),
      );
      expect(_compare('{"duration": "12:00:00"}', twelve), isEmpty);
      expect(_compare('{"duration": "12:00:01"}', twelve), hasLength(1));
      const XlsxCell long = XlsxCell(
        1.5,
        style: XlsxStyle(numFmt: XlsxNumFmt.elapsedTime),
      );
      expect(_compare('{"duration": "36:00:00"}', long), isEmpty);
      expect(_compare('{"date": "2026-10-28"}', long), hasLength(1));
    });

    test('an error cell compares by code', () {
      final XlsxReader r = _raw(
        '<row r="1"><c r="A1" t="e"><f>NA()</f><v>#N/A</v></c></row>',
      );
      List<String> run(String cell) => compareOwnerFile(_expect(cell), r);
      expect(run('{"error": "#N/A", "formula": "NA()"}'), isEmpty);
      expect(run('{"error": "#REF!", "formula": "NA()"}'), hasLength(1));
      expect(run('{"s": "#N/A", "formula": "NA()"}'), hasLength(1));
    });

    test('formula text is exact and always checked', () {
      const XlsxFormula f = XlsxFormula('B1*2', cached: 4);
      expect(_compare('{"n": "4", "formula": "B1*2"}', f), isEmpty);
      expect(_compare('{"n": "4", "formula": "B1 * 2"}', f), hasLength(1));
      expect(_compare('{"n": "4", "formula": "=B1*2"}', f), hasLength(1));
      expect(_compare('{"n": "4"}', f), hasLength(1));
      expect(
        _compare('{"n": "4", "formula": "B1*2"}', XlsxDecimal('4')),
        hasLength(1),
      );
    });

    test('a format is exact when given and not checked when left out', () {
      const XlsxCell priced = XlsxCell(
        1.5,
        style: XlsxStyle(numFmt: XlsxNumFmt.thousands2),
      );
      final XlsxReader r = _reader(priced);
      final String code = r.rowsAt(0).single.cells.single.numberFormat!;
      expect(
        compareOwnerFile(
          _expect('{"n": "1.5", "format": ${jsonEncode(code)}}'),
          r,
        ),
        isEmpty,
      );
      expect(
        compareOwnerFile(_expect('{"n": "1.5", "format": "0.0"}'), r),
        hasLength(1),
      );
      expect(compareOwnerFile(_expect('{"n": "1.5"}'), r), isEmpty);
    });

    test('merges, hidden rows, visibility and date1904', () {
      final XlsxWriter w = XlsxWriter();
      w.addSheet('S')
        ..row(<Object?>['a'])
        ..row(<Object?>['b'], hidden: true)
        ..merge(XlsxRange.parse('A1:B1'));
      w.addSheet('H', visibility: XlsxSheetVisibility.hidden).row(<Object?>[1]);
      final XlsxReader r = XlsxReader(w.close().bytes);
      const String head =
          '{"file": "f", "producer": "p", "confirmedBy": "owner"';
      const String ok =
          '"sheets": [{"name": "S", "merges": ["A1:B1"], '
          '"hiddenRows": [1], "rows": [["a"], ["b"]]}, '
          '{"name": "H", "visibility": "hidden", "rows": [[{"n": "1"}]]}]';
      expect(compareOwnerFile(parseOwnerExpected('$head, $ok}'), r), isEmpty);
      List<String> run(String body) =>
          compareOwnerFile(parseOwnerExpected('$head, $body}'), r);
      expect(run(ok.replaceFirst('"A1:B1"', '"A1:C1"')), isNotEmpty);
      expect(run(ok.replaceFirst('"merges": ["A1:B1"], ', '')), isNotEmpty);
      expect(run(ok.replaceFirst('[1]', '[]')), isNotEmpty);
      expect(run(ok.replaceFirst('"hidden"', '"veryHidden"')), isNotEmpty);
      expect(run(ok.replaceFirst('"name": "H"', '"name": "G"')), isNotEmpty);
      expect(
        run(ok.replaceAll('"rows": [["a"], ["b"]]', '"rows": [["a"]]')),
        isNotEmpty,
      );
      expect(run('$ok, "date1904": true'), isNotEmpty);
      expect(run('"sheets": []'), isNotEmpty);
    });

    test('a row or cell the file has and the expectation lacks fails', () {
      final XlsxWriter w = XlsxWriter();
      w.addSheet('S')
        ..row(<Object?>['a', 'b'])
        ..row(<Object?>['c']);
      final XlsxReader r = XlsxReader(w.close().bytes);
      List<String> run(String rows) => compareOwnerFile(
        parseOwnerExpected(
          '{"file": "f", "producer": "p", "confirmedBy": "owner", '
          '"sheets": [{"name": "S", "rows": $rows}]}',
        ),
        r,
      );
      expect(run('[["a", "b"], ["c"]]'), isEmpty);
      expect(run('[["a", "b"], ["c", null]]'), isEmpty);
      expect(run('[["a"], ["c"]]'), hasLength(1));
      expect(run('[["a", "b"]]'), hasLength(1));
      expect(run('[["a", "b"], ["c", "d"]]'), hasLength(1));
    });

    test('a mismatch names the sheet and the cell', () {
      final List<String> m = _compare('"x"', 'y');
      expect(m.single, allOf(contains('S!A1'), contains('x'), contains('y')));
    });

    test('an unexpected warning is a mismatch; an expected one matches', () {
      final XlsxReader r = _readerWithWarning();
      const String head =
          '{"file": "f", "producer": "p", "confirmedBy": "owner", '
          '"sheets": [{"name": "S", "rows": [[{"n": "1"}, {"formula": "1+1"}]]}]';
      final List<String> without = compareOwnerFile(
        parseOwnerExpected('$head}'),
        r,
      );
      expect(r.warnings, isNotEmpty);
      final XlsxWarning w = r.warnings.first;
      expect(without.join('\n'), contains(w.code.name));
      final int count = r.warnings
          .where((XlsxWarning x) => x.code == w.code)
          .fold(0, (int a, XlsxWarning x) => a + x.count);
      expect(
        compareOwnerFile(
          parseOwnerExpected(
            '$head, "warnings": [{"code": "${w.code.name}", '
            '"count": $count}]}',
          ),
          r,
        ),
        isEmpty,
      );
      expect(
        compareOwnerFile(
          parseOwnerExpected(
            '$head, "warnings": [{"code": "${w.code.name}", '
            '"count": ${count + 1}}]}',
          ),
          r,
        ),
        isNotEmpty,
      );
    });
  });

  group('draftOwnerExpected', () {
    XlsxReader build() {
      final XlsxWriter w = XlsxWriter();
      w.addSheet('Ürünler')
        ..row(<Object?>['Kod', 'Fiyat', 'Not'])
        ..row(<Object?>[
          '00123',
          const XlsxCell(
            1234567.89,
            style: XlsxStyle(numFmt: XlsxNumFmt.thousands2),
          ),
          'line\nbreak',
          DateTime(2026, 10, 28, 13, 45),
          const XlsxDate(2026, 10, 28),
          const XlsxCell(1.5, style: XlsxStyle(numFmt: XlsxNumFmt.elapsedTime)),
          true,
          const XlsxFormula('B2*2', cached: 4.5),
          const XlsxFormula('T(1)', cached: 'txt'),
          const XlsxFormula('A9', cached: true),
        ])
        ..row(<Object?>[], hidden: true)
        ..row(<Object?>[null, 'x'])
        ..merge(XlsxRange.parse('A5:B5'));
      w.addSheet('Gizli', visibility: XlsxSheetVisibility.hidden).row(<Object?>[
        1,
      ]);
      return XlsxReader(w.close().bytes);
    }

    test('the draft parses, is unconfirmed and matches its own file', () {
      final XlsxReader r = build();
      final String json = draftOwnerExpected(r, file: 'a.xlsx');
      final OwnerExpected e = parseOwnerExpected(json);
      expect(e.file, 'a.xlsx');
      expect(e.confirmedBy, isNull);
      expect(e.producer, '');
      expect(e.sheets.map((OwnerSheet s) => s.name), <String>[
        'Ürünler',
        'Gizli',
      ]);
      expect(e.sheets.first.hiddenRows, <int>[2]);
      expect(e.sheets.first.merges.single.ref, 'A5:B5');
      expect(e.sheets.last.visibility, XlsxSheetVisibility.hidden);
      expect(compareOwnerFile(e, r), isEmpty);
      expect(json, contains('"confirmedBy": null'));
      expect(json, contains('Ürünler'), reason: 'non-ASCII is kept');
    });

    test('a date is drafted at the nearest second', () {
      String serial(int ms) =>
          '${(DateTime.utc(2026, 10, 28, 13, 45, 30, ms).difference(DateTime.utc(1899, 12, 30)).inMilliseconds / 86400000)}';
      final XlsxReader r = XlsxReader(
        buildWorkbook(
          <String, String?>{
            'S': worksheet(
              '<row r="1"><c r="A1" s="0"><v>${serial(600)}</v></c>'
              '<c r="B1" s="0"><v>${serial(400)}</v></c></row>',
            ),
          },
          styles:
              '<styleSheet xmlns="$mainNs"><cellXfs>'
              '<xf numFmtId="22"/></cellXfs></styleSheet>',
        ),
      );
      final String json = draftOwnerExpected(r, file: 'a.xlsx');
      expect(json, contains('"date":"2026-10-28T13:45:31"'));
      expect(json, contains('"date":"2026-10-28T13:45:30"'));
    });

    test('an error cell and a formula without a value are drafted', () {
      final XlsxReader r = _raw(
        '<row r="1"><c r="A1" t="e"><f>NA()</f><v>#N/A</v></c></row>',
      );
      final String json = draftOwnerExpected(r, file: 'e.xlsx');
      expect(json, contains('{"error":"#N/A","formula":"NA()"}'));
      expect(compareOwnerFile(parseOwnerExpected(json), r), isEmpty);
      expect(reviewTable(r), allOf(contains('error'), contains('=NA()')));
    });

    test('the draft records the warnings the reader gave', () {
      final XlsxReader r = _readerWithWarning();
      final OwnerExpected e = parseOwnerExpected(
        draftOwnerExpected(r, file: 'w.xlsx'),
      );
      expect(e.warnings, isNotEmpty);
      expect(compareOwnerFile(e, r), isEmpty);
    });

    test('the review table lists every value with type and format', () {
      final String table = reviewTable(build());
      expect(table, contains('Ürünler!A2'));
      expect(table, contains('Ürünler!B2'));
      expect(table, contains('1234567.89'));
      expect(table, contains('number'));
      expect(table, contains('text'));
      expect(table, contains('date'));
      expect(table, contains('duration'));
      expect(table, contains('boolean'));
      expect(table, contains('=B2*2'));
      expect(table, contains('"line\\nbreak"'));
      expect(table, contains('hidden'));
      expect(table, contains('A5:B5'));
    });
  });

  group('ownerDirectoryProblems', () {
    test('an empty directory and an empty manifest have no problems', () {
      expect(
        ownerDirectoryProblems(<String>['README.md', 'manifest.json'], []),
        isEmpty,
      );
    });

    test('a listed file with both parts is fine', () {
      expect(
        ownerDirectoryProblems(
          <String>['a.xlsx', 'a.expected.json', 'README.md', 'manifest.json'],
          <String>['a.xlsx'],
        ),
        isEmpty,
      );
    });

    test('a file missing from the manifest fails', () {
      final List<String> p = ownerDirectoryProblems(<String>[
        'a.xlsx',
        'a.expected.json',
      ], <String>[]);
      expect(p.join('\n'), contains('a.xlsx'));
      expect(
        ownerDirectoryProblems(<String>['a.expected.json'], <String>[]),
        isNotEmpty,
      );
    });

    test('an xlsx without its json, or a json without its xlsx, fails', () {
      expect(
        ownerDirectoryProblems(<String>['a.xlsx'], <String>['a.xlsx']),
        isNotEmpty,
      );
      expect(
        ownerDirectoryProblems(<String>['a.expected.json'], <String>['a.xlsx']),
        hasLength(2),
        reason: 'the xlsx is missing, and the json has none to belong to',
      );
    });

    test('a manifest entry without a file fails', () {
      expect(
        ownerDirectoryProblems(<String>[], <String>['gone.xlsx']),
        isNotEmpty,
      );
    });

    test('other files and README.md and manifest.json are ignored', () {
      expect(
        ownerDirectoryProblems(<String>[
          'README.md',
          'manifest.json',
          '.DS_Store',
          'notes.txt',
        ], <String>[]),
        isEmpty,
      );
    });
  });

  group('ownerConfirmationProblems', () {
    OwnerExpected make(String confirmedBy, {String producer = 'Excel 16'}) =>
        parseOwnerExpected(
          '{"file": "a.xlsx", "producer": "$producer", '
          '"confirmedBy": $confirmedBy, "sheets": []}',
        );

    test('only "owner" confirms', () {
      expect(ownerConfirmationProblems(make('"owner"'), 'a.xlsx'), isEmpty);
      expect(ownerConfirmationProblems(make('null'), 'a.xlsx'), isNotEmpty);
      expect(ownerConfirmationProblems(make('"claude"'), 'a.xlsx'), isNotEmpty);
      expect(ownerConfirmationProblems(make('"Owner"'), 'a.xlsx'), isNotEmpty);
    });

    test('the producer is filled in and the file name is the real one', () {
      expect(
        ownerConfirmationProblems(make('"owner"', producer: ''), 'a.xlsx'),
        isNotEmpty,
      );
      expect(ownerConfirmationProblems(make('"owner"'), 'b.xlsx'), isNotEmpty);
    });
  });
}

/// A reader of a hand-made workbook whose sheet `S` holds [rows] (XML).
XlsxReader _raw(String rows) =>
    XlsxReader(buildWorkbook(<String, String?>{'S': worksheet(rows)}));

/// A reader whose sheet `S` gives a `formulaWithoutValue` warning.
XlsxReader _readerWithWarning() =>
    _raw('<row r="1"><c r="A1"><v>1</v></c><c r="B1"><f>1+1</f></c></row>');
