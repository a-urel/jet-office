import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/src/opc/package.dart';
import 'package:jet_office/src/xlsx/cell_encoder.dart';
import 'package:jet_office/src/xlsx/model/worksheet_part.dart';
import 'package:jet_office/src/xlsx/raw_cell.dart';
import 'package:jet_office/src/xlsx/read/read_exception.dart';
import 'package:jet_office/src/xlsx/read/read_limits.dart';
import 'package:jet_office/src/xlsx/shared_strings.dart';
import 'package:jet_office/src/xlsx/style_registry.dart';
import 'package:jet_office/src/xlsx/warnings.dart';
import 'package:jet_office/src/xml/xml_pull_reader.dart';
import 'package:test/test.dart';

import '../../../tool/src/part_compare.dart';
import '../../fixtures/fixtures.dart';
import '../../support/read_xlsx.dart';
import '../read/support/producers.dart';
import '../read/support/zip_builder.dart';

const String _main =
    'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
const String _mc =
    'http://schemas.openxmlformats.org/markup-compatibility/2006';
const String _x14ac =
    'http://schemas.microsoft.com/office/spreadsheetml/2009/9/ac';
const XlsxReadLimits _limits = XlsxReadLimits();

/// A worksheet part name, as producers name them.
final RegExp _worksheetName = RegExp(r'(^|/)worksheets/[^/]+\.xml$');

/// The differences a load and save makes on purpose, each pinned by a test
/// below: `dimension` and `spans` are recomputed, every row and cell gets
/// its `r` (where the file left it out, the reader placed it), and a number
/// cell's `t="n"` is written as no `t`, which means the same.
final RegExp _normalized = RegExp(
  r'/dimension: attribute ref |/row: attribute spans '
  r'|: attribute r missing vs "[A-Z]*[0-9]+"$'
  r'|: attribute t "n" vs missing$',
);

/// Repairs the reader makes, applied to the expected part: the producer file
/// repeats a cell on purpose, and the later one wins with
/// `cellDuplicated`, so the saved part has only the later one.
const Map<String, (String, String, String)> _repaired =
    <String, (String, String, String)>{
      'producer erp_export': (
        'worksheets/data.xml',
        '<c r="A3" t="str"><v>FT-2026-0002</v></c>',
        '',
      ),
    };

WorksheetPart _read(
  String xml, {
  List<XlsxWarningCode>? warnings,
  XlsxReadLimits limits = _limits,
}) => WorksheetPart.read(
  XmlPullReader(xml),
  part: 'xl/worksheets/sheet1.xml',
  limits: limits,
  warn: (XlsxWarningCode code, String? cell, {String? detail}) =>
      warnings?.add(code),
);

CellEncoder _encoder() => CellEncoder(
  strings: SharedStrings(),
  styles: StyleRegistry(),
  warnings: WarningCollector(),
);

String _encode(WorksheetPart part) {
  part.bindEncoder(_encoder());
  return utf8.decode(<int>[for (final Uint8List c in part.encode()) ...c]);
}

String _sheet(String body, {String attrs = ''}) =>
    '<worksheet xmlns="$_main"$attrs>$body</worksheet>';

/// Every package of the writer fixtures and the producer files.
Map<String, Uint8List> _allPackages() => <String, Uint8List>{
  for (final Fixture f in allFixtures()) f.name: f.build(),
  for (final ProducerFile p in producerFiles()) 'producer ${p.name}': p.bytes,
};

/// The local names of the root's child elements, in order.
List<String> _childNames(String xml) {
  final XmlPullReader r = XmlPullReader(xml);
  final List<String> out = <String>[];
  while (r.next()) {
    if (r.eventType == XmlEventType.startElement && r.depth == 2) {
      out.add(r.localName);
    }
  }
  return out;
}

void main() {
  group('read then encode', () {
    final Map<String, Uint8List> all = _allPackages();
    var sheets = 0;
    for (final MapEntry<String, Uint8List> e in all.entries) {
      final Map<String, Uint8List> parts = readXlsxBytes(e.value);
      for (final String name in parts.keys.where(_worksheetName.hasMatch)) {
        sheets++;
        test('is semantically equal: ${e.key} $name', () {
          final WorksheetPart part = WorksheetPart.read(
            XmlPullReader(utf8.decode(parts[name]!)),
            part: name,
            limits: _limits,
            warn: (XlsxWarningCode code, String? cell, {String? detail}) {},
          );
          final String out = _encode(part);
          final Uint8List replaced = buildZipOrdered(<(String, List<int>)>[
            for (final MapEntry<String, Uint8List> p in parts.entries)
              (p.key, p.key == name ? utf8.encode(out) : p.value),
          ]);
          Uint8List expected = e.value;
          final (String, String, String)? repair = _repaired[e.key];
          if (repair != null && repair.$1 == name) {
            final String text = utf8.decode(parts[name]!);
            expect(text, contains(repair.$2));
            expected = buildZipOrdered(<(String, List<int>)>[
              for (final MapEntry<String, Uint8List> p in parts.entries)
                (
                  p.key,
                  p.key == name
                      ? utf8.encode(text.replaceFirst(repair.$2, repair.$3))
                      : p.value,
                ),
            ]);
          }
          final List<String> differences = <String>[
            for (final String d in comparePackages(expected, replaced))
              if (!_normalized.hasMatch(d)) d,
          ];
          expect(differences, isEmpty);
        });
      }
    }

    test('there are worksheet parts to check', () {
      expect(sheets, greaterThan(20));
    });

    test('a row and cell without r get theirs; t="n" is dropped', () {
      final String out = _encode(
        _read(
          _sheet(
            '<sheetData><row><c t="n"><v>1</v></c><c><v>2</v></c></row>'
            '</sheetData>',
          ),
        ),
      );
      expect(
        out,
        contains(
          '<row r="1" spans="1:2"><c r="A1"><v>1</v></c>'
          '<c r="B1"><v>2</v></c></row>',
        ),
      );
    });

    test('a sheet with correct dimension and spans is unchanged', () {
      final String xml = _sheet(
        '<dimension ref="B2:C3"/><sheetData>'
        '<row r="2" spans="2:3"><c r="B2"><v>1</v></c><c r="C2"><v>2</v></c>'
        '</row><row r="3" spans="3:3"><c r="C3"><v>3</v></c></row>'
        '</sheetData>',
      );
      expect(compareXml('s', xml, _encode(_read(xml))), isEmpty);
    });
  });

  group('children', () {
    test('opaque children keep their position', () {
      const String r =
          'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
      final String xml = _sheet(
        '<sheetPr><tabColor rgb="FFFF0000"/></sheetPr>'
        '<sheetViews><sheetView workbookViewId="0"/></sheetViews>'
        '<sheetData><row r="1" spans="1:1"><c r="A1"><v>1</v></c></row>'
        '</sheetData><hyperlinks><hyperlink ref="A1" r:id="rId1"/></hyperlinks>'
        '<pageMargins left="0.7" right="0.7" top="0.75" bottom="0.75" '
        'header="0.3" footer="0.3"/>'
        '<legacyDrawing r:id="rId2"/>'
        '<extLst><ext uri="{X}"><foo/></ext></extLst>',
        attrs: ' xmlns:r="$r"',
      );
      final String out = _encode(_read(xml));
      expect(_childNames(out), <String>[
        'sheetPr',
        'sheetViews',
        'sheetData',
        'hyperlinks',
        'pageMargins',
        'legacyDrawing',
        'extLst',
      ]);
      expect(compareXml('s', xml, out), isEmpty);
    });

    test('mc:Ignorable and x14ac:dyDescent survive', () {
      final String xml = _sheet(
        '<dimension ref="A1"/>'
        '<sheetFormatPr defaultRowHeight="15" x14ac:dyDescent="0.25"/>'
        '<sheetData><row r="1" spans="1:1" x14ac:dyDescent="0.25">'
        '<c r="A1"><v>1</v></c></row></sheetData>',
        attrs: ' xmlns:mc="$_mc" xmlns:x14ac="$_x14ac" mc:Ignorable="x14ac"',
      );
      final String out = _encode(_read(xml));
      expect(out, contains('mc:Ignorable="x14ac"'));
      expect(out, contains('xmlns:x14ac="$_x14ac"'));
      expect(out, contains('<row r="1" spans="1:1" x14ac:dyDescent="0.25">'));
      expect(compareXml('s', xml, out), isEmpty);
    });

    test('a strict root is refused', () {
      expect(
        () => _read(
          '<worksheet xmlns="http://purl.oclc.org/ooxml/spreadsheetml/main">'
          '<sheetData/></worksheet>',
        ),
        throwsA(
          isA<XlsxReadException>().having(
            (XlsxReadException e) => e.reason,
            'reason',
            XlsxReadFailure.unsupportedFormat,
          ),
        ),
      );
    });

    test('a root that is not a worksheet is written back unchanged', () {
      const String xml =
          '<?xml version="1.0"?>\n'
          '<chartsheet xmlns="$_main"><sheetViews/></chartsheet>';
      final WorksheetPart part = _read(xml);
      expect(part.cells.cellCount, 0);
      expect(_encode(part), xml);
    });

    test('cells put in a part that is not a worksheet fail the save', () {
      final WorksheetPart part = _read('<chartsheet xmlns="$_main"/>');
      part.cells.put(0, 0, const RawCell(kind: RawCellKind.number, value: '1'));
      part.bindEncoder(_encoder());
      expect(part.encode, throwsStateError);
    });

    test('encode without an encoder throws', () {
      expect(WorksheetPart.empty().encode, throwsStateError);
    });

    test('a prefixed worksheet writes its cells in the main namespace', () {
      const String xml =
          '<x:worksheet xmlns:x="$_main"><x:sheetData><x:row r="1" spans="1:1">'
          '<x:c r="A1"><x:v>5</x:v></x:c></x:row></x:sheetData>'
          '</x:worksheet>';
      final String out = _encode(_read(xml));
      expect(compareXml('s', xml, out), isEmpty);
    });
  });

  group('dimension and spans', () {
    test('dimension and spans are recomputed', () {
      final String xml = _sheet(
        '<dimension ref="A1:Z9"/><sheetData>'
        '<row r="2" spans="1:26"><c r="B2"><v>1</v></c><c r="D2"><v>2</v></c>'
        '</row><row r="4" spans="1:2"><c r="C4"><v>3</v></c></row>'
        '</sheetData>',
      );
      final String out = _encode(_read(xml));
      expect(out, contains('<dimension ref="B2:D4"/>'));
      expect(out, contains('<row r="2" spans="2:4">'));
      expect(out, contains('<row r="4" spans="3:3">'));
    });

    test('a single cell gives a single-cell dimension', () {
      final String xml = _sheet(
        '<dimension ref="A1:B2"/><sheetData>'
        '<row r="3"><c r="C3"><v>1</v></c></row></sheetData>',
      );
      expect(_encode(_read(xml)), contains('<dimension ref="C3"/>'));
    });

    test('a row without cells keeps its attributes and gets no spans', () {
      final String xml = _sheet(
        '<dimension ref="A1"/><sheetData>'
        '<row r="1" spans="1:3"><c r="A1"><v>1</v></c></row>'
        '<row r="2" spans="1:3" hidden="1" ht="20" customHeight="1"/>'
        '</sheetData>',
      );
      final String out = _encode(_read(xml));
      expect(out, contains('<row r="2" hidden="1" ht="20" customHeight="1"/>'));
      expect('hidden='.allMatches(out).length, 1);
    });

    test('rows out of order are written in order', () {
      final String xml = _sheet(
        '<sheetData><row r="3"><c r="A3"><v>3</v></c></row>'
        '<row r="1"><c r="A1"><v>1</v></c></row></sheetData>',
      );
      final List<XlsxWarningCode> warnings = <XlsxWarningCode>[];
      final String out = _encode(_read(xml, warnings: warnings));
      expect(warnings, contains(XlsxWarningCode.rowOutOfOrder));
      expect(out.indexOf('<row r="1"'), lessThan(out.indexOf('<row r="3"')));
    });

    test('a changed cell moves the dimension', () {
      final WorksheetPart part = _read(
        _sheet(
          '<dimension ref="A1"/><sheetData>'
          '<row r="1"><c r="A1"><v>1</v></c></row></sheetData>',
        ),
      );
      part.cells.put(9, 4, const RawCell(kind: RawCellKind.number, value: '2'));
      final String out = _encode(part);
      expect(out, contains('<dimension ref="A1:E10"/>'));
      expect(out, contains('<row r="10" spans="5:5">'));
    });
  });

  group('empty and missing parts', () {
    test('an empty part has sheetData and dimension A1', () {
      final String out = _encode(WorksheetPart.empty());
      expect(_childNames(out), <String>['dimension', 'sheetData']);
      expect(out, contains('<dimension ref="A1"/>'));
      expect(out, startsWith('<?xml'));
    });

    test('an emptied part writes dimension A1', () {
      final WorksheetPart part = _read(
        _sheet(
          '<dimension ref="A1:B2"/><sheetData>'
          '<row r="2"><c r="B2"><v>1</v></c></row></sheetData>',
        ),
      );
      part.cells.remove(1, 1);
      final String out = _encode(part);
      expect(out, contains('<dimension ref="A1"/>'));
      expect(out, isNot(contains('<row')));
    });

    test('a missing sheetData is inserted in schema position', () {
      final String xml = _sheet(
        '<sheetPr/><dimension ref="A1"/><sheetViews/><cols>'
        '<col min="1" max="1" width="9"/></cols>'
        '<pageMargins left="0.7" right="0.7" top="0.75" bottom="0.75" '
        'header="0.3" footer="0.3"/>',
      );
      final String out = _encode(_read(xml));
      expect(_childNames(out), <String>[
        'sheetPr',
        'dimension',
        'sheetViews',
        'cols',
        'sheetData',
        'pageMargins',
      ]);
    });

    test('an empty root gets sheetData', () {
      final String out = _encode(_read('<worksheet xmlns="$_main"/>'));
      expect(_childNames(out), <String>['sheetData']);
    });

    test('the child order runs from sheetPr to extLst', () {
      expect(worksheetChildOrder.first, 'sheetPr');
      expect(worksheetChildOrder.last, 'extLst');
      expect(
        worksheetChildOrder.indexOf('dimension'),
        lessThan(worksheetChildOrder.indexOf('sheetData')),
      );
    });
  });

  test('a part is a PartContent', () {
    expect(WorksheetPart.empty(), isA<PartContent>());
  });
}
