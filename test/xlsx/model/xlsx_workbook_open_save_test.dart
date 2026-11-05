import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/opc/package.dart';
import 'package:jet_office/src/xlsx/model/xlsx_sheet.dart';
import 'package:jet_office/src/xlsx/model/xlsx_workbook.dart';
import 'package:test/test.dart';
import '../../../tool/src/part_compare.dart';
import '../../fixtures/fixtures.dart';
import '../../support/read_xlsx.dart';
import '../read/support/workbook_builder.dart';
import '../read/support/zip_builder.dart';
import 'support/workbook_support.dart';

void main() {
  test('a new workbook saves a sheet with values', () {
    final XlsxWorkbook book = XlsxWorkbook();
    final XlsxSheet sheet = book.addSheet('Liste');
    sheet
      ..setCell(0, 0, 'Ürün')
      ..setCell(0, 1, 12)
      ..setCell(0, 2, XlsxDecimal('12.50'))
      ..setCell(0, 3, true)
      ..setCell(0, 4, DateTime.utc(2026, 11, 2, 9, 30))
      ..setCell(0, 5, const XlsxFormula('A1&"!"'));
    final XlsxResult result = book.save();
    expect(result.warnings, isEmpty);
    final XlsxReader reader = XlsxReader(result.bytes);
    expect(reader.sheets.single.name, 'Liste');
    final List<XlsxReadCell> cells = reader.rowsAt(0).single.cells;
    expect(cells[0].value, 'Ürün');
    expect(cells[1].value, XlsxDecimal('12'));
    expect(cells[2].value, XlsxDecimal('12.50'));
    expect(cells[3].value, true);
    expect(cells[4].value, DateTime.utc(2026, 11, 2, 9, 30));
    expect(cells[4].isDate, isTrue);
    expect(cells[5].formula, 'A1&"!"');
    // The writer computes no result either.
    expect(reader.warnings.single.code, XlsxWarningCode.formulaWithoutValue);
    // The model's own view agrees with the reader.
    expect(sheet.rows.toList(), reader.rowsAt(0).toList());
    expect(sheet.cellAt(0, 4), cells[4]);
    expect(sheet.cellAt(5, 5), isNull);
  });

  test('a new workbook starts empty', () {
    final XlsxWorkbook book = XlsxWorkbook();
    expect(book.sheets, isEmpty);
    expect(book.date1904, isFalse);
    expect(book.warnings, isEmpty);
  });

  test('save without a sheet throws StateError', () {
    final XlsxWorkbook book = XlsxWorkbook();
    expect(
      book.save,
      throwsA(
        isA<StateError>().having(
          (StateError e) => e.message,
          'message',
          'A workbook needs at least one sheet; add one first.',
        ),
      ),
    );
    expect(
      () => book.saveTo(ByteConversionSink.withCallback((_) {})),
      throwsStateError,
    );
  });

  test('an opened workbook with only hidden sheets saves as it came', () {
    final Uint8List bytes = buildZip(<String, List<int>>{
      ...readXlsxBytes(buildWorkbook(<String, String>{'S': worksheet('')})),
      'xl/workbook.xml': utf8.encode(
        '<workbook xmlns="$mainNs" xmlns:r="$relNs"><sheets>'
        '<sheet name="S" sheetId="1" state="hidden" r:id="rId1"/>'
        '</sheets></workbook>',
      ),
    });
    final XlsxWorkbook book = XlsxWorkbook.open(bytes);
    expect(book.sheets.single.visibility, XlsxSheetVisibility.hidden);
    final Uint8List output = book.save().bytes;
    expect(comparePackages(bytes, output), isEmpty);
    final BytesBuilder sink = BytesBuilder();
    book.saveTo(ByteConversionSink.withCallback(sink.add));
    expect(sink.takeBytes(), output);
    expect(
      XlsxWorkbook.open(output).sheets.single.visibility,
      XlsxSheetVisibility.hidden,
    );
  });

  test('an opened workbook without sheets saves as it came', () {
    final Uint8List bytes = buildWorkbook(<String, String>{});
    final XlsxWorkbook book = XlsxWorkbook.open(bytes);
    expect(book.sheets, isEmpty);
    final Uint8List output = book.save().bytes;
    expect(comparePackages(bytes, output), isEmpty);
    expect(XlsxWorkbook.open(output).sheets, isEmpty);
  });

  test('open checks every entry: a damaged part nothing reads is '
      'corruptZip at open', () {
    Uint8List package({required bool damaged}) {
      final Uint8List zip = buildZip(<String, List<int>>{
        ...readXlsxBytes(
          buildWorkbook(<String, String>{
            'S': worksheet('<row r="1"><c r="A1"><v>1</v></c></row>'),
          }),
        ),
        'docProps/custom.xml': utf8.encode('<Properties>hello</Properties>'),
      }, store: true);
      if (!damaged) return zip;
      final List<int> needle = utf8.encode('hello');
      for (int i = 0; i + needle.length <= zip.length; i++) {
        int k = 0;
        while (k < needle.length && zip[i + k] == needle[k]) {
          k++;
        }
        if (k == needle.length) return Uint8List.fromList(zip)..[i] ^= 0x20;
      }
      throw StateError('No "hello" in the package.');
    }

    expect(
      () => XlsxWorkbook.open(package(damaged: true)),
      throwsA(
        isA<XlsxReadException>()
            .having(
              (XlsxReadException e) => e.reason,
              'reason',
              XlsxReadFailure.corruptZip,
            )
            .having(
              (XlsxReadException e) => e.part,
              'part',
              'docProps/custom.xml',
            ),
      ),
    );
    // An intact file opens with nothing loaded but the workbook part.
    final XlsxWorkbook book = XlsxWorkbook.open(package(damaged: false));
    final OpcPackage opc = packageOf(book);
    expect(
      <String>[
        for (final String name in opc.partNames)
          if (opc.isLoaded(name)) name,
      ],
      <String>['/xl/workbook.xml'],
    );
    expect(isLoadedSheet(book.sheets.single), isFalse);
  });

  test('saveTo writes the bytes save returns', () {
    final XlsxWorkbook book = XlsxWorkbook()..addSheet('A').setCell(0, 0, 1);
    final BytesBuilder sink = BytesBuilder();
    book.saveTo(ByteConversionSink.withCallback(sink.add));
    expect(sink.takeBytes(), book.save().bytes);
  });

  test('open then save with no change is semantically equal and loads '
      'nothing', () {
    final XlsxWriter writer = XlsxWriter();
    writer.addSheet('One').row(<Object?>['a', 1, DateTime.utc(2026)]);
    writer.addSheet('Two').row(<Object?>['b']);
    final Uint8List input = writer.close().bytes;
    final XlsxWorkbook book = XlsxWorkbook.open(input);
    final Uint8List output = book.save().bytes;
    expect(comparePackages(input, output), isEmpty);
    final OpcPackage package = packageOf(book);
    expect(
      <String>[
        for (final String name in package.partNames)
          if (package.isLoaded(name)) name,
      ],
      <String>['/xl/workbook.xml'],
    );
  });

  test('sheets are listed in tab order and found ignoring case', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      buildWorkbook(<String, String>{
        'Özet': worksheet(''),
        'Liste': worksheet(''),
      }),
    );
    expect(book.sheets.map((XlsxSheet s) => s.name), <String>['Özet', 'Liste']);
    expect(() => book.sheets.add(book.sheets.first), throwsUnsupportedError);
    expect(book.sheet('LISTE'), same(book.sheets[1]));
    expect(book.sheet('özet'), same(book.sheets[0]));
    expect(() => book.sheet('Nope'), throwsArgumentError);
  });

  test('open throws XlsxReadException for a file it cannot open', () {
    expect(
      () => XlsxWorkbook.open(Uint8List.fromList(<int>[1, 2, 3])),
      throwsA(isA<XlsxReadException>()),
    );
    expect(
      () => XlsxWorkbook.open(
        buildWorkbook(<String, String>{'S': worksheet('')}),
        limits: const XlsxReadLimits(maxSheets: 0),
      ),
      throwsArgumentError,
    );
  });

  test('an unloaded sheet keeps its strings', () {
    final XlsxWriter writer = XlsxWriter();
    writer.addSheet('One').row(<Object?>['alpha', 'beta']);
    writer.addSheet('Two').row(<Object?>['gamma', 'beta', 'delta']);
    final Uint8List input = writer.close().bytes;
    final XlsxWorkbook book = XlsxWorkbook.open(input);
    book.sheets[0].setCell(1, 0, 'a new string');
    final Uint8List output = book.save().bytes;
    expect(isLoadedSheet(book.sheets[1]), isFalse);
    expect(
      XlsxReader(output).rowsAt(1).toList(),
      XlsxReader(input).rowsAt(1).toList(),
    );
    expect(
      XlsxReader(output).rowsAt(0).last.cells.single.value,
      'a new string',
    );
  });

  group('shared strings count', () {
    test('is left out while a sheet is unloaded', () {
      final XlsxWriter writer = XlsxWriter();
      writer.addSheet('One').row(<Object?>['alpha']);
      writer.addSheet('Two').row(<Object?>['alpha']);
      final XlsxWorkbook book = XlsxWorkbook.open(writer.close().bytes);
      book.sheets[0].setCell(0, 1, 'beta');
      final String sst = partText(book.save().bytes, 'xl/sharedStrings.xml');
      expect(sst, isNot(contains(' count=')));
      expect(sst, contains('uniqueCount="2"'));
    });

    test('is recounted when every sheet is loaded', () {
      final XlsxWriter writer = XlsxWriter();
      writer.addSheet('One').row(<Object?>['alpha', 'alpha']);
      writer.addSheet('Two').row(<Object?>['alpha']);
      final XlsxWorkbook book = XlsxWorkbook.open(writer.close().bytes);
      book.sheets[0].setCell(0, 1, 'beta');
      book.sheets[1].rows.toList();
      final String sst = partText(book.save().bytes, 'xl/sharedStrings.xml');
      expect(sst, contains('count="3"'));
      expect(sst, contains('uniqueCount="2"'));
    });
  });

  test('addSheet in a file with unusual names', () {
    final Uint8List input = buildZip(<String, List<int>>{
      '[Content_Types].xml': utf8.encode(
        '<Types xmlns="$ctNs"><Override PartName="/book/main.xml" '
        'ContentType="$wbType"/><Override PartName="/book/ws/data.xml" '
        'ContentType="$wsType"/></Types>',
      ),
      '_rels/.rels': utf8.encode(
        '<Relationships xmlns="$pkgRelNs"><Relationship Id="rId1" '
        'Type="$relNs/officeDocument" Target="book/main.xml"/>'
        '</Relationships>',
      ),
      'book/main.xml': utf8.encode(
        '<workbook xmlns="$mainNs" xmlns:r="$relNs"><sheets>'
        '<sheet name="Sheet2" sheetId="7" r:id="rId7"/>'
        '<sheet name="history " sheetId="x" r:id="rId9"/></sheets>'
        '</workbook>',
      ),
      'book/_rels/main.xml.rels': utf8.encode(
        '<Relationships xmlns="$pkgRelNs"><Relationship Id="rId7" '
        'Type="$relNs/worksheet" Target="ws/data.xml"/><Relationship '
        'Id="rId9" Type="$relNs/worksheet" Target="/book/worksheets/'
        'sheet3.xml"/></Relationships>',
      ),
      'book/ws/data.xml': utf8.encode(
        worksheet('<row r="1"><c r="A1"><v>1</v></c></row>'),
      ),
      'book/worksheets/sheet3.xml': utf8.encode(worksheet('')),
    });
    final XlsxWorkbook book = XlsxWorkbook.open(input);
    final XlsxSheet added = book.addSheet('sheet2');
    expect(added.name, 'sheet2 (2)');
    expect(book.addSheet('').name, 'Sheet4');
    expect(book.addSheet('History').name, 'History (2)');
    expect(book.warnings.map((XlsxWarning w) => w.code), <XlsxWarningCode>[
      XlsxWarningCode.sheetNameDuplicated,
      XlsxWarningCode.sheetNameChanged,
      XlsxWarningCode.sheetNameDuplicated,
    ]);
    added.setCell(0, 0, 'new');
    final Uint8List output = book.save().bytes;
    final Map<String, String> parts = readXlsx(output);
    expect(parts['book/ws/data.xml'], isNotNull);
    expect(parts['book/worksheets/sheet3.xml'], isNotNull);
    expect(parts['book/worksheets/sheet4.xml'], contains('t="s"'));
    expect(parts['book/sharedStrings.xml'], contains('<t>new</t>'));
    expect(parts['book/main.xml'], contains('sheetId="7" r:id="rId7"'));
    expect(parts['book/main.xml'], contains('sheetId="x" r:id="rId9"'));
    expect(
      parts['book/main.xml'],
      contains('<sheet name="sheet2 (2)" sheetId="8" r:id="rId1"/>'),
    );
    expect(parts['book/_rels/main.xml.rels'], contains('Id="rId7"'));
    expect(
      parts['book/_rels/main.xml.rels'],
      contains('Target="worksheets/sheet4.xml"'),
    );
    expect(
      parts['[Content_Types].xml'],
      contains('/book/worksheets/sheet4.xml'),
    );
    final XlsxReader reader = XlsxReader(output);
    expect(reader.sheets.map((XlsxReadSheet s) => s.name), <String>[
      'Sheet2',
      'history ',
      'sheet2 (2)',
      'Sheet4',
      'History (2)',
    ]);
    expect(reader.rowsAt(0).single.cells.single.value, XlsxDecimal('1'));
    expect(reader.rowsAt(2).single.cells.single.value, 'new');
    expect(reader.warnings, isEmpty);
  });

  test('a sheet without a part reads as empty and warns', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      buildWorkbook(<String, String?>{'A': worksheet(''), 'Gone': null}),
    );
    expect(book.warnings.single.code, XlsxWarningCode.sheetPartMissing);
    expect(book.sheets[1].rows, isEmpty);
    expect(() => book.sheets[1].setCell(0, 0, 1), throwsStateError);
  });

  test('a broken sheet throws on first access, not on open', () {
    final String broken =
        '<worksheet xmlns="$mainNs"><sheetData>'
        '${'<x>' * 300}${'</x>' * 300}</sheetData></worksheet>';
    final Uint8List input = buildWorkbook(<String, String>{
      'Good': worksheet('<row r="1"><c r="A1"><v>1</v></c></row>'),
      'Bad': broken,
    });
    final XlsxWorkbook book = XlsxWorkbook.open(input);
    expect(
      () => book.sheets[1].cellAt(0, 0),
      throwsA(isA<XlsxReadException>()),
    );
    expect(() => book.sheets[1].rows, throwsA(isA<XlsxReadException>()));
    // A programmer error is one whatever the sheet holds.
    expect(() => book.sheets[1].setCell(0, 0, Object()), throwsArgumentError);
    expect(
      () => book.sheets[1].setCell(0, 0, const XlsxCell(XlsxCell(1))),
      throwsArgumentError,
    );
    book.sheets[0].setCell(1, 0, 2);
    final Uint8List output = book.save().bytes;
    expect(
      readXlsxBytes(output)['xl/worksheets/sheet2.xml'],
      utf8.encode(broken),
    );
  });

  test('an xlsm keeps vbaProject.bin and its content type', () {
    const String macroType =
        'application/vnd.ms-excel.sheet.macroEnabled.main+xml';
    final List<int> vba = List<int>.generate(64, (int i) => i * 7 % 256);
    final Uint8List input = packageWith(
      rows: '<row r="1"><c r="A1"><v>1</v></c></row>',
      contentType: macroType,
      extraTypes:
          '<Default Extension="bin" '
          'ContentType="application/vnd.ms-office.vbaProject"/>',
      extraRels:
          '<Relationship Id="rId3" Type="http://schemas.microsoft.com/'
          'office/2006/relationships/vbaProject" Target="vbaProject.bin"/>',
    );
    final Uint8List withVba = buildZip(<String, List<int>>{
      ...readXlsxBytes(input),
      'xl/vbaProject.bin': vba,
    });
    final XlsxWorkbook book = XlsxWorkbook.open(withVba);
    book.sheets.single.setCell(0, 0, 2);
    final Uint8List output = book.save().bytes;
    final Map<String, Uint8List> parts = readXlsxBytes(output);
    expect(parts['xl/vbaProject.bin'], vba);
    final String types = utf8.decode(parts['[Content_Types].xml']!);
    expect(types, contains(macroType));
    expect(types, contains('application/vnd.ms-office.vbaProject'));
    expect(
      utf8.decode(parts['xl/_rels/workbook.xml.rels']!),
      contains('vbaProject.bin'),
    );
    expect(
      comparePackages(
        withVba,
        output,
        ignoreParts: const <String>{'xl/worksheets/sheet1.xml'},
      ),
      isEmpty,
    );
  });

  test('loading the shared strings keeps the sst root and its extras', () {
    const String x14ac =
        'http://schemas.microsoft.com/office/spreadsheetml/2009/9/ac';
    const String mc =
        'http://schemas.openxmlformats.org/markup-compatibility/2006';
    final XlsxWorkbook book = XlsxWorkbook.open(
      buildWorkbook(
        <String, String>{
          'S': worksheet('<row r="1"><c r="A1" t="s"><v>0</v></c></row>'),
        },
        sharedStrings:
            '<sst xmlns="$mainNs" xmlns:mc="$mc" xmlns:x14ac="$x14ac" '
            'mc:Ignorable="x14ac" count="1" uniqueCount="1" x14ac:k="v">'
            '<si><t>a</t></si>'
            '<extLst><ext uri="u"><x14ac:z/></ext></extLst></sst>',
      ),
    );
    book.sheets.single.setCell(1, 0, 'b');
    final String sst = partText(book.save().bytes, 'xl/sharedStrings.xml');
    expect(sst, contains('xmlns:x14ac="$x14ac"'));
    expect(sst, contains('xmlns:mc="$mc"'));
    expect(sst, contains('mc:Ignorable="x14ac"'));
    expect(sst, contains('x14ac:k="v"'));
    expect(sst, contains('count="2"'));
    expect(sst, contains('uniqueCount="2"'));
    expect(
      sst,
      contains('<si><t>b</t></si><extLst><ext uri="u"><x14ac:z/></ext>'),
    );
    expect(RegExp(' count=').allMatches(sst), hasLength(1));
    expect(RegExp('uniqueCount=').allMatches(sst), hasLength(1));
  });

  group('a declaration with a forbidden character saves', () {
    /// [bytes] with a hostile declaration on the first [element] of [part].
    Uint8List declaredOn(Uint8List bytes, String part, String element) =>
        buildZipOrdered(<(String, List<int>)>[
          for (final MapEntry<String, Uint8List> p in readXlsxBytes(
            bytes,
          ).entries)
            (
              p.key,
              p.key != part
                  ? p.value
                  : utf8.encode(
                      utf8
                          .decode(p.value)
                          .replaceFirst(
                            RegExp('<$element(?=[ />])'),
                            '<$element xmlns:o="urn:&#1;o"',
                          ),
                    ),
            ),
        ]);

    for (final String name in <String>[
      'm2_merges_filter',
      'm2_columns_rows',
      'm3_conditional_x14',
      'm3_properties',
    ]) {
      test('on every element of $name, edited or not', () {
        final Uint8List input = allFixtures()
            .firstWhere((Fixture f) => f.name == name)
            .build();
        final RegExp tag = RegExp(r'<([A-Za-z][\w:.]*)');
        readXlsx(input).forEach((String part, String text) {
          if (part.endsWith('.rels') || part.startsWith('[')) return;
          for (final String element
              in tag.allMatches(text).map((Match m) => m.group(1)!).toSet()) {
            final Uint8List hostile = declaredOn(input, part, element);
            final String where = '$element in $part';
            expect(
              () => XlsxWorkbook.open(hostile).save(),
              returnsNormally,
              reason: where,
            );
            final XlsxWorkbook book = XlsxWorkbook.open(hostile);
            for (final XlsxSheet sheet in book.sheets) {
              sheet.rows.toList();
              sheet.setCell(0, 0, 'x');
            }
            expect(book.save, returnsNormally, reason: where);
          }
        });
      });
    }
  });
}
