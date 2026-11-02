import 'package:jet_office/src/opc/opaque_xml.dart';
import 'package:jet_office/src/xlsx/raw_cell.dart';
import 'package:jet_office/src/xlsx/read/read_exception.dart';
import 'package:jet_office/src/xlsx/read/read_limits.dart';
import 'package:jet_office/src/xlsx/read/sheet_reader.dart';
import 'package:jet_office/src/xlsx/warnings.dart';
import 'package:jet_office/src/xml/xml_pull_reader.dart';
import 'package:test/test.dart';

const String _main =
    'http://schemas.openxmlformats.org/spreadsheetml/2006/main';

const String _x14ac =
    'http://schemas.microsoft.com/office/spreadsheetml/2009/9/ac';

/// The rows of a worksheet whose `<sheetData>` holds [rows], read with
/// [keepExtras]; the warnings go to [warnings] as `code cell`.
List<RawRow> _rows(
  String rows, {
  bool keepExtras = true,
  List<String>? warnings,
  XlsxReadLimits limits = const XlsxReadLimits(),
}) {
  final XmlPullReader r = XmlPullReader(
    '<worksheet xmlns="$_main" xmlns:x14ac="$_x14ac">'
    '<sheetData>$rows</sheetData></worksheet>',
  );
  while (r.next()) {
    if (r.eventType == XmlEventType.startElement &&
        r.localName == 'sheetData') {
      break;
    }
  }
  final RawRowReader reader = RawRowReader(
    r,
    part: 'xl/worksheets/sheet1.xml',
    keepExtras: keepExtras,
    limits: limits,
    warn: (XlsxWarningCode code, String? cell, {String? detail}) =>
        warnings?.add('${code.name} $cell'),
  );
  return <RawRow>[for (RawRow? row; (row = reader.next()) != null;) row!];
}

Map<String, String> _attributes(List<KeptAttribute> kept) => <String, String>{
  for (final KeptAttribute a in kept) a.qualifiedName: a.value,
};

void main() {
  test('RawRowReader keeps row and cell extras', () {
    final List<RawRow> rows = _rows(
      '<row r="2" spans="1:2" x14ac:dyDescent="0.25" customHeight="1" '
      'ht="20"><c r="A2" s="1" cm="1" t="n"><f ca="1">NOW()</f><v>1</v>'
      '</c></row>',
    );
    expect(rows, hasLength(1));
    final RawRow row = rows.single;
    expect(row.index, 1);
    expect(row.hidden, isFalse);
    expect(_attributes(row.attributes), <String, String>{
      'x14ac:dyDescent': '0.25',
      'customHeight': '1',
      'ht': '20',
    });
    expect(row.attributes.first.namespaceUri, _x14ac);
    expect(row.columns, <int>[0]);
    final RawCell cell = row.cells.single;
    expect(cell.kind, RawCellKind.number);
    expect(cell.style, 1);
    expect(_attributes(cell.attributes), <String, String>{'cm': '1'});
    expect(cell.formula!.text, 'NOW()');
    expect(_attributes(cell.formula!.attributes), <String, String>{'ca': '1'});
  });

  test('RawRowReader keeps an inline rich string as opaque XML', () {
    const String inline =
        '<is><r><rPr><b/></rPr><t>bold</t></r><r><t> plain</t></r></is>';
    final RawCell cell = _rows(
      '<row r="1"><c r="A1" t="inlineStr">$inline</c></row>',
    ).single.cells.single;
    expect(cell.kind, RawCellKind.inlineString);
    expect(cell.inline!.xml, inline);
    expect(cell.inline!.inheritedNamespaces, <String, String>{'': _main});
    expect(cell.value, isNull);
    expect(cell.isEmpty, isFalse);
  });

  test('keepExtras false keeps nothing extra', () {
    final List<RawRow> rows = _rows(
      '<row r="1" customHeight="1" ht="20"><c r="A1" cm="1" s="x">'
      '<f ca="1">A2</f><v>1</v></c>'
      '<c r="B1" t="inlineStr"><is><t>a</t></is></c></row>'
      '<row r="3" ht="30"/>',
      keepExtras: false,
    );
    expect(rows, hasLength(1));
    final RawRow row = rows.single;
    expect(row.attributes, isEmpty);
    expect(row.columns, <int>[0, 1]);
    expect(row.cells[0].attributes, isEmpty);
    expect(row.cells[0].style, isNull);
    expect(row.cells[0].formula!.attributes, isEmpty);
    expect(row.cells[1].inline, isNull);
  });

  test('RawRowReader keeps the digits as written', () {
    final RawCell cell = _rows(
      '<row r="1"><c r="A1" s="2"><v>1.50</v></c></row>',
    ).single.cells.single;
    expect(cell.value, '1.50');
    expect(cell.style, 2);
  });

  test('a shared string keeps its index, an error its code', () {
    final List<RawCell> cells = _rows(
      '<row r="1"><c r="A1" t="s"><v>07</v></c><c r="B1" t="e"><v>#N/A</v>'
      '</c><c r="C1" t="x"><v>1</v></c></row>',
    ).single.cells;
    expect(cells[0].kind, RawCellKind.sharedString);
    expect(cells[0].value, '07');
    expect(cells[1].kind, RawCellKind.error);
    expect(cells[1].value, '#N/A');
    expect(cells[2].kind, RawCellKind.unknown);
    expect(cells[2].typeText, 'x');
  });

  test('a formula keeps its type, ref, si and decoded text', () {
    final List<RawCell> cells = _rows(
      '<row r="1"><c r="A1"><f t="shared" ref="A1:A2" si="0">'
      'B1&amp;_x0041_</f><v>1</v></c></row>'
      '<row r="2"><c r="A2"><f t="shared" si="0"/><v>2</v></c></row>',
    ).expand((RawRow r) => r.cells).toList();
    final RawFormula master = cells[0].formula!;
    expect(master.type, FormulaType.shared);
    expect(master.ref, 'A1:A2');
    expect(master.si, '0');
    expect(master.text, 'B1&A');
    final RawFormula follower = cells[1].formula!;
    expect(follower.ref, isNull);
    expect(follower.si, '0');
    expect(follower.text, isNull);
  });

  test('an invalid s is kept as an attribute, not a style', () {
    final RawCell cell = _rows(
      '<row r="1"><c r="A1" s="-1"><v>1</v></c></row>',
    ).single.cells.single;
    expect(cell.style, isNull);
    expect(_attributes(cell.attributes), <String, String>{'s': '-1'});
  });

  test('a styled empty cell and a row with attributes are kept', () {
    final List<RawRow> rows = _rows(
      '<row r="1"><c r="B1" s="3"/></row><row r="4" ht="30"/>',
    );
    expect(rows.map((RawRow r) => r.index), <int>[0, 3]);
    expect(rows[0].columns, <int>[1]);
    expect(rows[0].cells.single.isEmpty, isTrue);
    expect(rows[0].cells.single.style, 3);
    expect(rows[1].cells, isEmpty);
    expect(_attributes(rows[1].attributes), <String, String>{'ht': '30'});
  });

  test('cells come in column order; a duplicate keeps the last and warns', () {
    final List<String> warnings = <String>[];
    final RawRow row = _rows(
      '<row r="1"><c r="C1"><v>3</v></c><c r="A1"><v>1</v></c>'
      '<c r="C1"><v>4</v></c></row>',
      warnings: warnings,
    ).single;
    expect(row.columns, <int>[0, 2]);
    expect(row.cells.map((RawCell c) => c.value), <String>['1', '4']);
    expect(warnings, <String>['cellDuplicated C1']);
  });

  test('positions are checked and warned about', () {
    final List<String> warnings = <String>[];
    final List<RawRow> rows = _rows(
      '<row r="3"><c r="A9"><v>1</v></c><c r="XFE3"><v>2</v></c></row>'
      '<row r="2"><c><v>3</v></c></row>',
      warnings: warnings,
    );
    expect(rows.map((RawRow r) => r.index), <int>[2, 1]);
    expect(rows[0].columns, <int>[0]);
    expect(warnings, <String>[
      'cellReferenceInvalid A3',
      'cellOutsideSheet XFE3',
      'rowOutOfOrder A2',
    ]);
  });

  test('an inline text over maxTextLength throws limitExceeded', () {
    expect(
      () => _rows(
        '<row r="1"><c r="A1" t="inlineStr"><is><t>abcdef</t></is></c></row>',
        limits: const XlsxReadLimits(maxTextLength: 5),
      ),
      throwsA(
        isA<XlsxReadException>().having(
          (XlsxReadException e) => e.reason,
          'reason',
          XlsxReadFailure.limitExceeded,
        ),
      ),
    );
  });

  test('an empty sheetData has no rows', () {
    final XmlPullReader r = XmlPullReader(
      '<worksheet xmlns="$_main"><sheetData/></worksheet>',
    );
    while (r.next()) {
      if (r.eventType == XmlEventType.startElement &&
          r.localName == 'sheetData') {
        break;
      }
    }
    final RawRowReader reader = RawRowReader(
      r,
      part: 'p',
      keepExtras: true,
      limits: const XlsxReadLimits(),
      warn: (XlsxWarningCode code, String? cell, {String? detail}) {},
    );
    expect(reader.next(), isNull);
    expect(reader.next(), isNull);
  });
}
