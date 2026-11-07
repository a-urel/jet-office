import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/opc/change_log.dart';
import 'package:jet_office/src/xlsx/model/xlsx_workbook.dart';
import 'package:test/test.dart';

import '../../../tool/src/part_compare.dart';
import '../../fixtures/fixtures.dart';
import '../../support/read_xlsx.dart';
import '../read/support/workbook_builder.dart';
import '../read/support/zip_builder.dart';
import 'support/workbook_support.dart';

const String _sheetRels = 'xl/worksheets/_rels/sheet1.xml.rels';

Uint8List _fixture(String name) =>
    allFixtures().firstWhere((Fixture f) => f.name == name).build();

/// A package of one sheet `S` whose worksheet is [xml], with the sheet's
/// relationships part made of [rels] (raw `<Relationship>` elements) when
/// given.
Uint8List _package(String xml, {String? rels}) {
  final Map<String, Uint8List> parts = readXlsxBytes(
    buildWorkbook(<String, String>{'S': xml}),
  );
  if (rels != null) {
    parts[_sheetRels] = Uint8List.fromList(
      utf8.encode('<Relationships xmlns="$pkgRelNs">$rels</Relationships>'),
    );
  }
  return buildZip(<String, List<int>>{...parts});
}

/// A worksheet with [data] (raw rows) and [links] (raw `<hyperlinks>`).
String _worksheet(String links, {String data = ''}) =>
    '<worksheet xmlns="$mainNs" xmlns:r="$relNs"><sheetData>$data'
    '</sheetData>$links</worksheet>';

String _rel(String id, String target) =>
    '<Relationship Id="$id" Type="$relNs/hyperlink" Target="$target" '
    'TargetMode="External"/>';

XlsxWorkbook _open(String links, {String data = '', String? rels}) =>
    XlsxWorkbook.open(_package(_worksheet(links, data: data), rels: rels));

String _sheetXml(XlsxWorkbook book) =>
    partText(book.save().bytes, 'xl/worksheets/sheet1.xml');

String _relsXml(XlsxWorkbook book) {
  final Map<String, String> parts = readXlsx(book.save().bytes);
  return parts[_sheetRels] ?? '';
}

int _relationships(XlsxWorkbook book) =>
    RegExp('<Relationship ').allMatches(_relsXml(book)).length;

int _invalid(XlsxWorkbook book) => book.warnings
    .where((XlsxWarning w) => w.code == XlsxWarningCode.featureEntryInvalid)
    .fold<int>(0, (int s, XlsxWarning w) => s + w.count);

XlsxRange _r(String ref) => XlsxRange.parse(ref);

String _cell(String ref, String text) =>
    '<c r="$ref" t="inlineStr"><is><t>$text</t></is></c>';

/// The model's version of the fixture `m3_hyperlinks`, set cell by cell.
XlsxResult _model3() {
  final XlsxWorkbook book = XlsxWorkbook();
  final XlsxSheet links = book.addSheet('Links');
  links.setColumn(
    2,
    const XlsxColumn(style: XlsxStyle(font: XlsxFont(bold: true))),
  );
  links.setCell(0, 0, XlsxHyperlink.url('https://example.com/a b'));
  links.setCell(
    0,
    1,
    XlsxHyperlink.email(
      'sales@example.com',
      subject: 'Q&A ç',
      tooltip: 'Write to sales',
    ),
  );
  links.setCell(0, 2, XlsxHyperlink.location('Target', text: 'Bold link'));
  links.setCell(
    0,
    3,
    XlsxCell(
      XlsxHyperlink.url('https://example.com/red', text: 'Red link'),
      style: const XlsxStyle(font: XlsxFont(color: XlsxColor.rgb(0xFF0000))),
    ),
  );
  links.setCell(1, 0, XlsxHyperlink.sheet("O'Brien", range: _r('B2')));
  links.setCell(1, 1, XlsxHyperlink.location('Target'));
  final XlsxSheet other = book.addSheet("O'Brien");
  other.setCell(0, 0, 'top');
  other.setCell(1, 1, 'B2');
  other.setCell(2, 2, 'C3');
  book.defineName(const XlsxDefinedName('Target', r"'O''Brien'!$C$3"));
  return book.save();
}

void main() {
  group('reading', () {
    test('reads m3_hyperlinks', () {
      final XlsxWorkbook book = XlsxWorkbook.open(_fixture('m3_hyperlinks'));
      final XlsxSheet links = book.sheets.first;
      expect(links.hyperlinks, <({XlsxRange range, XlsxHyperlink link})>[
        (range: _r('A1'), link: XlsxHyperlink.url('https://example.com/a b')),
        (
          range: _r('B1'),
          link: XlsxHyperlink.email(
            'sales@example.com',
            subject: 'Q&A ç',
            tooltip: 'Write to sales',
          ),
        ),
        (
          range: _r('C1'),
          link: XlsxHyperlink.location('Target', text: 'Bold link'),
        ),
        (
          range: _r('D1'),
          link: XlsxHyperlink.url('https://example.com/red', text: 'Red link'),
        ),
        (
          range: _r('A2'),
          link: XlsxHyperlink.sheet("O'Brien", range: _r('B2')),
        ),
        (range: _r('B2'), link: XlsxHyperlink.location('Target')),
      ]);
      expect(
        links.hyperlinkAt(0, 1)?.address,
        'mailto:sales@example.com?subject=Q%26A%20%C3%A7',
      );
      expect(links.hyperlinkAt(0, 4), isNull);
      expect(book.sheets.last.hyperlinks, isEmpty);
      expect(book.warnings, isEmpty);
    });

    test('the text is the cell string, else the display, else empty', () {
      final XlsxWorkbook book = _open(
        '<hyperlinks><hyperlink ref="A1" location="L" display="shown"/>'
        '<hyperlink ref="A2" location="L"/>'
        '<hyperlink ref="A3" location="L" display="shown"/>'
        '<hyperlink ref="A4" location="L" display="shown"/>'
        '<hyperlink ref="A5" location="L"/></hyperlinks>',
        data:
            '<row r="1">${_cell('A1', 'cell one')}</row>'
            '<row r="2">${_cell('A2', 'cell two')}</row>'
            '<row r="4"><c r="A4"><v>4</v></c></row>',
      );
      expect(
        <String>[for (final h in book.sheets.single.hyperlinks) h.link.text],
        <String>['cell one', 'cell two', 'shown', 'shown', ''],
      );
    });

    test('a plain value set in the cell is the text the link reads', () {
      final XlsxWorkbook book = _open(
        '<hyperlinks><hyperlink ref="A1" location="L" display="old"/>'
        '</hyperlinks>',
        data: '<row r="1">${_cell('A1', 'old')}</row>',
      );
      final XlsxSheet sheet = book.sheets.single..setCell(0, 0, 'new');
      expect(sheet.hyperlinkAt(0, 0)?.text, 'new');
    });

    test('a sheet of very many links reads in linear time', testOn: 'vm', () {
      const int count = 150000;
      final StringBuffer links = StringBuffer('<hyperlinks>');
      final StringBuffer rels = StringBuffer();
      for (int i = 0; i < count; i++) {
        links.write('<hyperlink ref="A${i + 1}" r:id="rId$i"/>');
        rels.write(_rel('rId$i', 'https://a.example/$i'));
      }
      links.write('</hyperlinks>');
      final XlsxSheet sheet = _open(
        links.toString(),
        rels: rels.toString(),
      ).sheets.single;
      // Loads the sheet, so that the getter alone is timed: reading the
      // entries and joining them. A test's timeout cannot stop code that
      // never yields, so the bound is checked after: a fraction of a second
      // here, minutes when quadratic.
      sheet.merges;
      final Stopwatch watch = Stopwatch()..start();
      final List<({XlsxRange range, XlsxHyperlink link})> read =
          sheet.hyperlinks;
      expect(watch.elapsed, lessThan(const Duration(seconds: 15)));
      expect(read, hasLength(count));
      expect(read.last.link.address, 'https://a.example/${count - 1}');
    });

    test('of two relationships with one id the first gives the address', () {
      final XlsxWorkbook book = _open(
        '<hyperlinks><hyperlink ref="A1" r:id="rId1"/></hyperlinks>',
        rels:
            '<Relationship Id="rId1" Type="$relNs/image" Target="i.png"/>'
            '${_rel('rId1', 'https://first.example')}'
            '${_rel('rId1', 'https://second.example')}',
      );
      expect(
        book.sheets.single.hyperlinkAt(0, 0)?.address,
        'https://first.example',
      );
    });

    test('maxMerges bounds the links of a sheet', () {
      const XlsxReadLimits limits = XlsxReadLimits(maxMerges: 5);
      Uint8List file(int count) => _package(
        _worksheet(
          '<hyperlinks>${'<hyperlink ref="A1" location="L"/>' * count}'
          '</hyperlinks>',
        ),
      );
      expect(
        () =>
            XlsxWorkbook.open(file(6), limits: limits).sheets.single.hyperlinks,
        throwsLimit('maxMerges', 5, 'xl/worksheets/sheet1.xml'),
      );
      expect(
        XlsxWorkbook.open(file(5), limits: limits).sheets.single.hyperlinks,
        hasLength(5),
      );
    });

    test('both an address and a location are one link', () {
      final XlsxWorkbook book = _open(
        '<hyperlinks><hyperlink ref="A1" r:id="rId1" location="Sheet2!A1" '
        'tooltip="go" display="d"/></hyperlinks>',
        rels: _rel('rId1', 'file%20one.xlsx'),
      );
      expect(
        book.sheets.single.hyperlinkAt(0, 0),
        const XlsxHyperlink(
          address: 'file%20one.xlsx',
          location: 'Sheet2!A1',
          text: 'd',
          tooltip: 'go',
        ),
      );
    });

    test('A1:B2 reads as one link covering four cells', () {
      final XlsxWorkbook book = _open(
        '<hyperlinks><hyperlink ref="A1:B2" location="L" display="d"/>'
        '</hyperlinks>',
      );
      final XlsxSheet sheet = book.sheets.single;
      expect(sheet.hyperlinks.map((h) => h.range), <XlsxRange>[_r('A1:B2')]);
      for (final (int row, int column) in <(int, int)>[
        (0, 0),
        (0, 1),
        (1, 0),
        (1, 1),
      ]) {
        expect(sheet.hyperlinkAt(row, column)?.location, 'L');
      }
      expect(sheet.hyperlinkAt(2, 0), isNull);
    });

    test('a coordinate outside the grid throws RangeError', () {
      final XlsxSheet sheet = XlsxWorkbook().addSheet('S');
      expect(() => sheet.hyperlinkAt(-1, 0), throwsRangeError);
      expect(() => sheet.removeHyperlink(0, 16384), throwsRangeError);
    });
  });

  group('bad values are kept and reported', () {
    test('a dangling r:id reads with no address and is reported', () {
      final Uint8List input = _package(
        _worksheet(
          '<hyperlinks><hyperlink ref="A1" r:id="rId9" display="d"/>'
          '</hyperlinks>',
        ),
      );
      final XlsxWorkbook book = XlsxWorkbook.open(input);
      final XlsxSheet sheet = book.sheets.single;
      expect(sheet.hyperlinkAt(0, 0), const XlsxHyperlink(text: 'd'));
      expect(sheet.hyperlinks, hasLength(1));
      expect(_invalid(book), 1);
      expect(
        <String?>[
          for (final XlsxWarning w in book.warnings)
            if (w.code == XlsxWarningCode.featureEntryInvalid) w.detail,
        ],
        <String?>['hyperlink'],
      );
      // Once, however often it is read.
      sheet.hyperlinks;
      expect(_invalid(book), 1);
      expect(comparePackages(input, book.save().bytes), isEmpty);
    });

    test('an unreadable ref stays in the file, out of the list', () {
      final Uint8List input = _package(
        _worksheet(
          '<hyperlinks><hyperlink ref="ZZZZZ9" location="L"/>'
          '<hyperlink ref="B2" location="M"/><hyperlink location="N"/>'
          '</hyperlinks>',
        ),
      );
      final XlsxWorkbook book = XlsxWorkbook.open(input);
      final XlsxSheet sheet = book.sheets.single;
      expect(sheet.hyperlinks.map((h) => h.range), <XlsxRange>[_r('B2')]);
      expect(_invalid(book), 2);
      expect(comparePackages(input, book.save().bytes), isEmpty);
      // An edit keeps them.
      sheet.setCell(4, 4, XlsxHyperlink.location('P'));
      final String xml = _sheetXml(book);
      expect(xml, contains('ref="ZZZZZ9"'));
      expect(xml, contains('<hyperlink location="N"/>'));
      expect(xml, contains('ref="E5"'));
    });

    test('a relationship of another type is no link target', () {
      final XlsxWorkbook book = _open(
        '<hyperlinks><hyperlink ref="A1" r:id="rId1" display="d"/>'
        '</hyperlinks>',
        rels:
            '<Relationship Id="rId1" Type="$relNs/drawing" '
            'Target="../drawings/drawing1.xml"/>',
      );
      expect(book.sheets.single.hyperlinkAt(0, 0)?.address, isNull);
      expect(_invalid(book), 1);
      book.sheets.single.removeHyperlink(0, 0);
      expect(_relsXml(book), contains('drawing1.xml'));
    });

    test('a broken rels part throws from the getter that needs it', () {
      final Uint8List input = _package(
        _worksheet(
          '<hyperlinks><hyperlink ref="A1" r:id="rId1" display="d"/>'
          '</hyperlinks>',
        ),
      );
      final Map<String, Uint8List> parts = readXlsxBytes(input);
      parts[_sheetRels] = Uint8List.fromList(utf8.encode('<Relationships'));
      final XlsxWorkbook book = XlsxWorkbook.open(
        buildZip(<String, List<int>>{...parts}),
      );
      expect(
        () => book.sheets.single.hyperlinks,
        throwsA(isA<XlsxReadException>()),
      );
      expect(
        () => book.sheets.single.setCell(
          3,
          3,
          XlsxHyperlink.url('https://a.example'),
        ),
        throwsA(isA<XlsxReadException>()),
      );
      expect(changeLogOf(book).hasChanges, isFalse);
    });

    test('a link with no r:id reads without touching a broken rels part', () {
      final Map<String, Uint8List> parts = readXlsxBytes(
        _package(
          _worksheet(
            '<hyperlinks><hyperlink ref="A1" location="L" display="d"/>'
            '</hyperlinks>',
          ),
        ),
      );
      parts[_sheetRels] = Uint8List.fromList(utf8.encode('<Relationships'));
      final XlsxWorkbook book = XlsxWorkbook.open(
        buildZip(<String, List<int>>{...parts}),
      );
      expect(book.sheets.single.hyperlinks, hasLength(1));
    });
  });

  group('setting', () {
    test('a link set reads back with XlsxReader and the model', () {
      final XlsxWorkbook book = XlsxWorkbook();
      final XlsxSheet sheet = book.addSheet('S');
      final XlsxHyperlink link = XlsxHyperlink.url(
        'https://example.com/a b',
        tooltip: 'open',
      );
      sheet.setCell(0, 0, link);
      expect(sheet.hyperlinkAt(0, 0), link);
      expect(sheet.cellAt(0, 0)?.value, 'https://example.com/a b');
      final Uint8List saved = book.save().bytes;
      expect(
        XlsxReader(saved).rowsAt(0).single.cells.single.value,
        'https://example.com/a b',
      );
      final XlsxSheet again = XlsxWorkbook.open(saved).sheets.single;
      expect(again.hyperlinks, <({XlsxRange range, XlsxHyperlink link})>[
        (range: _r('A1'), link: link),
      ]);
      final String xml = _sheetXml(book);
      expect(
        xml,
        contains(
          '<hyperlinks><hyperlink ref="A1" r:id="rId1" tooltip="open" '
          'display="https://example.com/a b"/></hyperlinks>',
        ),
      );
      expect(
        _relsXml(book),
        contains(
          'Type="$relNs/hyperlink" Target="https://example.com/a%20b" '
          'TargetMode="External"',
        ),
      );
    });

    test('an internal link has no relationship', () {
      final XlsxWorkbook book = XlsxWorkbook();
      final XlsxSheet sheet = book.addSheet('S');
      sheet.setCell(0, 0, XlsxHyperlink.location('S!B2'));
      expect(_sheetXml(book), contains('<hyperlink ref="A1" location="S!B2"'));
      expect(_relsXml(book), isEmpty);
    });

    test('an address with a location keeps both', () {
      final XlsxWorkbook book = XlsxWorkbook();
      final XlsxSheet sheet = book.addSheet('S');
      const XlsxHyperlink link = XlsxHyperlink(
        address: 'other.xlsx',
        location: 'Sheet2!A1',
        text: 'other',
      );
      sheet.setCell(0, 0, link);
      expect(
        _sheetXml(book),
        contains('<hyperlink ref="A1" r:id="rId1" location="Sheet2!A1" '),
      );
      expect(
        XlsxWorkbook.open(book.save().bytes).sheets.single.hyperlinkAt(0, 0),
        link,
      );
    });

    test('the model writes what the writer writes (m3_hyperlinks)', () {
      expect(
        comparePackages(
          _fixture('m3_hyperlinks'),
          _model3().bytes,
          ignoreBookkeeping: true,
        ),
        isEmpty,
      );
    });

    test('a repeated address shares one relationship', () {
      final XlsxWorkbook book = XlsxWorkbook();
      final XlsxSheet sheet = book.addSheet('S');
      sheet.setCell(0, 0, XlsxHyperlink.url('https://a.example', text: 'a'));
      sheet.setCell(1, 0, XlsxHyperlink.url('https://a.example', text: 'b'));
      sheet.setCell(2, 0, XlsxHyperlink.url('https://b.example', text: 'c'));
      expect(_relationships(book), 2);
      final String xml = _sheetXml(book);
      expect(RegExp('r:id="rId1"').allMatches(xml), hasLength(2));
      expect(RegExp('r:id="rId2"').allMatches(xml), hasLength(1));
      // An address the file already has is reused too.
      final XlsxWorkbook opened = _open(
        '<hyperlinks><hyperlink ref="A1" r:id="rId4" display="d"/>'
        '</hyperlinks>',
        rels: _rel('rId4', 'https://a.example'),
      );
      opened.sheets.single.setCell(
        2,
        2,
        XlsxHyperlink.url('https://a.example'),
      );
      expect(_relationships(opened), 1);
      expect(RegExp('r:id="rId4"').allMatches(_sheetXml(opened)), hasLength(2));
    });

    test('replacing a link on its cell keeps one link there', () {
      final XlsxWorkbook book = XlsxWorkbook();
      final XlsxSheet sheet = book.addSheet('S');
      sheet.setCell(0, 0, XlsxHyperlink.url('https://a.example'));
      sheet.setCell(0, 1, XlsxHyperlink.url('https://b.example'));
      sheet.setCell(0, 0, XlsxHyperlink.url('https://c.example', text: 'c'));
      expect(sheet.hyperlinks.map((h) => h.link.address), <String?>[
        'https://c.example',
        'https://b.example',
      ]);
      expect(sheet.cellAt(0, 0)?.value, 'c');
      expect(_relsXml(book), isNot(contains('a.example')));
      expect(_relationships(book), 2);
    });

    test('replacing and removing drop an unused relationship', () {
      final XlsxWorkbook book = XlsxWorkbook();
      final XlsxSheet sheet = book.addSheet('S');
      sheet.setCell(0, 0, XlsxHyperlink.url('https://a.example'));
      sheet.setCell(0, 1, XlsxHyperlink.url('https://a.example'));
      sheet.setCell(0, 2, XlsxHyperlink.url('https://b.example'));
      // Shared: the first removal keeps the relationship.
      sheet.removeHyperlink(0, 0);
      expect(_relsXml(book), contains('a.example'));
      sheet.removeHyperlink(0, 1);
      expect(_relsXml(book), isNot(contains('a.example')));
      expect(_relsXml(book), contains('b.example'));
      // Replaced by an internal link: the relationship goes.
      sheet.setCell(0, 2, XlsxHyperlink.location('S!A1'));
      expect(_relsXml(book), isEmpty);
      sheet.removeHyperlink(0, 2);
      expect(_sheetXml(book), isNot(contains('hyperlink')));
      expect(sheet.hyperlinks, isEmpty);
    });

    test('removing a link leaves the cell value and style', () {
      final XlsxWorkbook book = XlsxWorkbook();
      final XlsxSheet sheet = book.addSheet('S');
      sheet.setCell(0, 0, XlsxHyperlink.url('https://a.example', text: 'a'));
      final XlsxStyle? style = sheet.styleAt(0, 0);
      sheet.removeHyperlink(0, 0);
      expect(sheet.cellAt(0, 0)?.value, 'a');
      expect(sheet.styleAt(0, 0), style);
      expect(sheet.hyperlinkAt(0, 0), isNull);
    });

    test('removing a link whose relationship an unreadable one uses', () {
      final XlsxWorkbook book = _open(
        '<hyperlinks><hyperlink ref="A1" r:id="rId1" display="d"/>'
        '<hyperlink ref="ZZZZZ9" r:id="rId1"/></hyperlinks>',
        rels: _rel('rId1', 'https://a.example'),
      );
      book.sheets.single.removeHyperlink(0, 0);
      expect(_relsXml(book), contains('a.example'));
      expect(_sheetXml(book), contains('ref="ZZZZZ9"'));
    });

    test('removing a multi-cell link removes it whole', () {
      final XlsxWorkbook book = _open(
        '<hyperlinks><hyperlink ref="A1:B2" r:id="rId1" display="d"/>'
        '</hyperlinks>',
        rels: _rel('rId1', 'https://a.example'),
      );
      book.sheets.single.removeHyperlink(1, 1);
      expect(book.sheets.single.hyperlinks, isEmpty);
      expect(_sheetXml(book), isNot(contains('hyperlink')));
      expect(_relsXml(book), isNot(contains('a.example')));
    });

    test('removing where there is no link throws and changes nothing', () {
      final XlsxWorkbook book = _open(
        '<hyperlinks><hyperlink ref="A1" location="L"/></hyperlinks>',
      );
      expect(
        () => book.sheets.single.removeHyperlink(5, 5),
        throwsArgumentError,
      );
      expect(changeLogOf(book).hasChanges, isFalse);
    });

    test('a plain value keeps the link', () {
      final XlsxWorkbook book = XlsxWorkbook();
      final XlsxSheet sheet = book.addSheet('S');
      sheet.setCell(0, 0, XlsxHyperlink.url('https://a.example', text: 'a'));
      sheet.setCell(0, 0, 'plain');
      expect(sheet.cellAt(0, 0)?.value, 'plain');
      expect(sheet.hyperlinkAt(0, 0)?.address, 'https://a.example');
      sheet.setCell(0, 0, null);
      expect(sheet.hyperlinkAt(0, 0)?.address, 'https://a.example');
      expect(_relationships(book), 1);
    });

    test('a plain link keeps the cell style under the link font', () {
      final XlsxWorkbook book = XlsxWorkbook();
      final XlsxSheet sheet = book.addSheet('S');
      sheet.setCell(
        0,
        0,
        const XlsxCell(
          1,
          style: XlsxStyle(
            fill: XlsxFill.solid(XlsxColor.rgb(0xFFFF00)),
            numFmt: XlsxNumFmt.custom('0.00'),
          ),
        ),
      );
      sheet.setCell(0, 0, XlsxHyperlink.url('https://a.example', text: 'a'));
      final XlsxStyle? style = sheet.styleAt(0, 0);
      expect(style?.fill, const XlsxFill.solid(XlsxColor.rgb(0xFFFF00)));
      expect(style?.numFmt, const XlsxNumFmt.custom('0.00'));
      expect(style?.font?.color, const XlsxColor.theme(10));
      expect(style?.font?.underline, XlsxUnderline.single);
    });

    test('an XlsxCell of a link layers as one of a string', () {
      final XlsxWorkbook book = XlsxWorkbook();
      final XlsxSheet sheet = book.addSheet('S');
      sheet.setCell(
        0,
        0,
        XlsxCell(
          XlsxHyperlink.url('https://a.example', text: 'a'),
          style: const XlsxStyle(font: XlsxFont(bold: true)),
        ),
      );
      final XlsxFont? font = sheet.styleAt(0, 0)?.font;
      expect(font?.bold, isTrue);
      expect(font?.color, const XlsxColor.theme(10));
      expect(font?.underline, XlsxUnderline.single);
      expect(sheet.hyperlinkAt(0, 0)?.text, 'a');
    });

    test('a multi-cell link throws and nothing changes', () {
      final Uint8List input = _package(
        _worksheet(
          '<hyperlinks><hyperlink ref="A1:B2" location="L" display="d"/>'
          '</hyperlinks>',
        ),
      );
      final XlsxWorkbook book = XlsxWorkbook.open(input);
      final XlsxSheet sheet = book.sheets.single;
      for (final (int row, int column) in <(int, int)>[(0, 0), (1, 1)]) {
        expect(
          () => sheet.setCell(row, column, XlsxHyperlink.location('M')),
          throwsStateError,
        );
        expect(
          () =>
              sheet.setCell(row, column, XlsxCell(XlsxHyperlink.location('M'))),
          throwsStateError,
        );
      }
      expect(changeLogOf(book).hasChanges, isFalse);
      expect(comparePackages(input, book.save().bytes), isEmpty);
      // A plain value is fine, and a cell beside the range too.
      sheet.setCell(0, 0, 'x');
      sheet.setCell(0, 2, XlsxHyperlink.location('M'));
      expect(sheet.hyperlinks, hasLength(2));
    });

    test('an invalid link throws ArgumentError and nothing changes', () {
      final XlsxWorkbook book = XlsxWorkbook();
      final XlsxSheet sheet = book.addSheet('S');
      expect(
        () => sheet.setCell(0, 0, const XlsxHyperlink(text: 'no target')),
        throwsArgumentError,
      );
      expect(
        () => sheet.setCell(
          0,
          0,
          const XlsxHyperlink(address: '', text: 'empty address'),
        ),
        throwsArgumentError,
      );
      expect(changeLogOf(book).hasChanges, isFalse);
      expect(sheet.cellAt(0, 0), isNull);
    });

    test('a link in a table header cell throws', () {
      final XlsxWriter writer = XlsxWriter();
      writer.addSheet('S')
        ..table(
          XlsxTable('T', _r('A1:B2'), const <XlsxTableColumn>[
            XlsxTableColumn('x'),
            XlsxTableColumn('y'),
          ]),
        )
        ..row(<Object?>[null, null])
        ..row(<Object?>[1, 2]);
      final XlsxWorkbook book = XlsxWorkbook.open(writer.close().bytes);
      expect(
        () => book.sheets.single.setCell(
          0,
          0,
          XlsxHyperlink.url('https://a.example'),
        ),
        throwsStateError,
      );
      expect(changeLogOf(book).hasChanges, isFalse);
    });

    test('a prefixed worksheet binds r and keeps SpreadsheetML', () {
      final Uint8List input = buildZip(<String, List<int>>{
        ...readXlsxBytes(
          buildWorkbook(<String, String>{
            'S':
                '<x:worksheet xmlns:x="$mainNs">'
                '<x:sheetData/></x:worksheet>',
          }),
        ),
      });
      final XlsxWorkbook book = XlsxWorkbook.open(input);
      final XlsxHyperlink link = XlsxHyperlink.url('https://a.example');
      book.sheets.single.setCell(0, 0, link);
      final Uint8List saved = book.save().bytes;
      final String xml = partText(saved, 'xl/worksheets/sheet1.xml');
      expect(xml, contains('<x:hyperlinks>'));
      expect(xml, contains('r:id="rId1"'));
      expect(xml, contains('xmlns:r="$relNs"'));
      final XlsxSheet again = XlsxWorkbook.open(saved).sheets.single;
      expect(again.hyperlinkAt(0, 0), link);
      expect(XlsxReader(saved).rowsAt(0).single.cells.single.value, link.text);
    });

    test('a link past the limit throws XlsxLimitError', () {
      final String links =
          '<hyperlinks>'
          '${<String>[for (int i = 0; i < XlsxLimits.maxHyperlinksPerSheet; i++) '<hyperlink ref="A${i + 1}" location="L"/>'].join()}'
          '</hyperlinks>';
      final XlsxWorkbook book = _open(links);
      final XlsxSheet sheet = book.sheets.single;
      expect(
        () => sheet.setCell(0, 5, XlsxHyperlink.location('M')),
        throwsA(isA<XlsxLimitError>()),
      );
      expect(changeLogOf(book).hasChanges, isFalse);
      // Replacing one of them is not a 65,531st link.
      sheet.setCell(0, 0, XlsxHyperlink.location('M', text: 'm'));
      expect(sheet.hyperlinkAt(0, 0)?.location, 'M');
    });
  });

  group('undo', () {
    test('undo restores the link, the id and the cell', () {
      final Uint8List input = _fixture('m3_hyperlinks');
      final XlsxWorkbook book = XlsxWorkbook.open(input);
      final ChangeLog log = changeLogOf(book);
      final XlsxSheet sheet = book.sheets.first;
      final ChangeSet set = log.transaction(() {
        sheet.setCell(
          0,
          0,
          XlsxHyperlink.url('https://other.example', text: 'other'),
        );
        sheet.setCell(0, 5, XlsxHyperlink.url('https://new.example'));
        sheet.removeHyperlink(0, 3);
      });
      expect(sheet.hyperlinkAt(0, 0)?.address, 'https://other.example');
      expect(sheet.hyperlinkAt(0, 3), isNull);
      // Saving before the undo would add the recalculation flag, which an
      // undo does not take back (rulings 15 and 16 of W2).
      log.revertSet(set);
      expect(
        comparePackages(input, book.save().bytes, ignoreBookkeeping: true),
        isEmpty,
      );
      expect(sheet.hyperlinkAt(0, 0)?.address, 'https://example.com/a%20b');
      expect(sheet.cellAt(0, 0)?.value, 'https://example.com/a b');
      log.reapplySet(set);
      expect(sheet.hyperlinkAt(0, 0)?.address, 'https://other.example');
      expect(sheet.hyperlinkAt(0, 5)?.address, 'https://new.example');
      expect(sheet.hyperlinkAt(0, 3), isNull);
      final String rels = _relsXml(book);
      expect(rels, contains('other.example'));
      expect(rels, contains('new.example'));
      expect(rels, isNot(contains('example.com/red')));
      expect(rels, isNot(contains('example.com/a%20b')));
    });

    test('undo of a first link removes the group and the relationship', () {
      final XlsxWorkbook book = XlsxWorkbook();
      final XlsxSheet sheet = book.addSheet('S');
      final ChangeLog log = changeLogOf(book);
      final ChangeSet set = log.transaction(
        () => sheet.setCell(0, 0, XlsxHyperlink.url('https://a.example')),
      );
      log.revertSet(set);
      expect(sheet.hyperlinks, isEmpty);
      expect(_sheetXml(book), isNot(contains('hyperlink')));
      expect(_relsXml(book), isNot(contains('a.example')));
      log.reapplySet(set);
      expect(sheet.hyperlinkAt(0, 0)?.address, 'https://a.example');
      expect(_relationships(book), 1);
    });
  });

  group('an equal link is no edit', () {
    void unchanged(
      String name,
      String links,
      int row,
      int column, {
      String data = '',
      String? rels,
    }) {
      test(name, () {
        final Uint8List input = _package(
          _worksheet(links, data: data),
          rels: rels,
        );
        final XlsxWorkbook book = XlsxWorkbook.open(input);
        final XlsxSheet sheet = book.sheets.single;
        final XlsxHyperlink link = sheet.hyperlinkAt(row, column)!;
        sheet.setCell(row, column, link);
        expect(changeLogOf(book).hasChanges, isFalse);
        expect(
          comparePackages(input, book.save().bytes, ignoreBookkeeping: true),
          isEmpty,
        );
      });
    }

    unchanged(
      'a display that differs from the cell',
      '<hyperlinks><hyperlink ref="A1" location="L" display="shown"/>'
          '</hyperlinks>',
      0,
      0,
      data: '<row r="1">${_cell('A1', 'cell')}</row>',
    );
    unchanged(
      'a link on a number',
      '<hyperlinks><hyperlink ref="A1" location="L"/></hyperlinks>',
      0,
      0,
      data: '<row r="1"><c r="A1"><v>4</v></c></row>',
    );
    unchanged(
      'a link on no cell',
      '<hyperlinks><hyperlink ref="A1" location="L" display="d"/>'
          '</hyperlinks>',
      0,
      0,
    );
    unchanged(
      'a cell inside a link of several cells',
      '<hyperlinks><hyperlink ref="A1:B2" location="L"/></hyperlinks>',
      1,
      1,
      data: '<row r="1">${_cell('A1', 'first')}</row>',
    );
    unchanged(
      'a link the writer would refuse: an r:id naming nothing',
      '<hyperlinks><hyperlink ref="A1" r:id="rId9"/></hyperlinks>',
      0,
      0,
    );
    unchanged(
      'an address with attributes the model does not type',
      '<hyperlinks><hyperlink ref="A1" r:id="rId1" extra="1"/></hyperlinks>',
      0,
      0,
      data: '<row r="1">${_cell('A1', 'a')}</row>',
      rels: _rel('rId1', 'https://a.example'),
    );

    test('every link of m3_hyperlinks', () {
      final Uint8List input = _fixture('m3_hyperlinks');
      final XlsxWorkbook book = XlsxWorkbook.open(input);
      for (final XlsxSheet sheet in book.sheets) {
        for (final h in sheet.hyperlinks) {
          sheet.setCell(h.range.firstRow, h.range.firstColumn, h.link);
        }
      }
      expect(changeLogOf(book).hasChanges, isFalse);
    });

    test('a link that differs is an edit', () {
      final XlsxWorkbook book = _open(
        '<hyperlinks><hyperlink ref="A1" location="L"/></hyperlinks>',
        data: '<row r="1">${_cell('A1', 'a')}</row>',
      );
      book.sheets.single.setCell(0, 0, XlsxHyperlink.location('L', text: 'b'));
      expect(changeLogOf(book).hasChanges, isTrue);
    });

    test('an invalid link that is not on the cell still throws', () {
      final XlsxWorkbook book = _open(
        '<hyperlinks><hyperlink ref="A1" r:id="rId9"/></hyperlinks>',
      );
      expect(
        () => book.sheets.single.setCell(1, 0, const XlsxHyperlink(text: '')),
        throwsArgumentError,
      );
    });

    test('an XlsxCell of an equal link styles the cell, the link stays', () {
      final XlsxWorkbook book = _open(
        '<hyperlinks><hyperlink ref="A1" location="L" extra="1"/></hyperlinks>',
        data: '<row r="1">${_cell('A1', 'a')}</row>',
      );
      final XlsxSheet sheet = book.sheets.single;
      sheet.setCell(
        0,
        0,
        XlsxCell(
          sheet.hyperlinkAt(0, 0),
          style: const XlsxStyle(font: XlsxFont(bold: true)),
        ),
      );
      expect(_sheetXml(book), contains('extra="1"'));
      expect(book.sheets.single.cellAt(0, 0)?.value, 'a');
    });
  });

  test('an unchanged file with links saves equal', () {
    final Uint8List input = _fixture('m3_hyperlinks');
    final XlsxWorkbook book = XlsxWorkbook.open(input);
    for (final XlsxSheet sheet in book.sheets) {
      sheet.hyperlinks;
    }
    expect(
      comparePackages(input, book.save().bytes, ignoreBookkeeping: true),
      isEmpty,
    );
  });
}
