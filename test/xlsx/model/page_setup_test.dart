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

Uint8List _fixture(String name) =>
    allFixtures().firstWhere((Fixture f) => f.name == name).build();

/// A package of one sheet `S` whose worksheet is [xml].
Uint8List _package(String xml) => buildZip(<String, List<int>>{
  ...readXlsxBytes(buildWorkbook(<String, String>{'S': xml})),
});

String _worksheet(String body, {String head = ''}) =>
    '<worksheet xmlns="$mainNs" xmlns:r="$relNs">$head'
    '<sheetData/>$body</worksheet>';

XlsxWorkbook _open(String body, {String head = ''}) =>
    XlsxWorkbook.open(_package(_worksheet(body, head: head)));

String _sheetXml(XlsxWorkbook book) =>
    partText(book.save().bytes, 'xl/worksheets/sheet1.xml');

/// The first element [name] of [xml], whole.
String _element(String xml, String name) =>
    RegExp(
      '<(\\w+:)?$name(\\s[^>]*)?/>|<(\\w+:)?$name[ >].*?</(\\w+:)?$name>',
    ).firstMatch(xml)?.group(0) ??
    '';

/// The elements the writer writes for [setup]: its sheetPr, printOptions,
/// pageMargins and pageSetup.
String _written(XlsxPageSetup setup) {
  final XlsxWriter writer = XlsxWriter();
  writer.addSheet('S').pageSetup(setup);
  final String xml = partText(writer.close().bytes, 'xl/worksheets/sheet1.xml');
  return <String>[
    for (final String n in <String>[
      'sheetPr',
      'printOptions',
      'pageMargins',
      'pageSetup',
    ])
      _element(xml, n),
  ].join('\n');
}

String _modelWrote(XlsxWorkbook book) {
  final String xml = _sheetXml(book);
  return <String>[
    for (final String n in <String>[
      'sheetPr',
      'printOptions',
      'pageMargins',
      'pageSetup',
    ])
      _element(xml, n),
  ].join('\n');
}

int _invalid(XlsxWorkbook book) => book.warnings
    .where((XlsxWarning w) => w.code == XlsxWarningCode.featureEntryInvalid)
    .fold<int>(0, (int s, XlsxWarning w) => s + w.count);

List<String> _details(XlsxWorkbook book) => <String>[
  for (final XlsxWarning w in book.warnings)
    if (w.code == XlsxWarningCode.featureEntryInvalid) '${w.detail}',
];

const XlsxPageMargins _narrow = XlsxPageMargins(
  left: 0.25,
  right: 0.25,
  top: 0.5,
  bottom: 0.5,
  header: 0.2,
  footer: 0.2,
);

void main() {
  test('reads m3_page_setup', () {
    final XlsxWorkbook book = XlsxWorkbook.open(_fixture('m3_page_setup'));
    expect(
      book.sheet('Landscape').pageSetup,
      const XlsxPageSetup(
        orientation: XlsxOrientation.landscape,
        paperSize: XlsxPaperSize.a4,
        fitToWidth: 1,
        centerHorizontally: true,
        printGridLines: true,
      ),
    );
    expect(
      book.sheet('Scaled').pageSetup,
      const XlsxPageSetup(
        scale: 85,
        firstPageNumber: 3,
        pageOrder: XlsxPageOrder.overThenDown,
        margins: _narrow,
      ),
    );
    expect(book.warnings, isEmpty);
  });

  test('reads m3_header_footer', () {
    final XlsxWorkbook book = XlsxWorkbook.open(_fixture('m3_header_footer'));
    expect(
      book.sheet('Report').headerFooter,
      XlsxHeaderFooter(
        oddHeader: XlsxHeaderFooter.sections(
          left: XlsxHeaderFooter.literal('R&D'),
          right: XlsxHeaderFooter.date,
        ),
        oddFooter:
            'Page ${XlsxHeaderFooter.pageNumber} of '
            '${XlsxHeaderFooter.pageCount}',
        evenFooter: XlsxHeaderFooter.sheetName,
        firstHeader: 'Cover',
      ),
    );
    expect(book.warnings, isEmpty);
  });

  test('a sheet without the elements reads null', () {
    final XlsxSheet sheet = _open('').sheets.single;
    expect(sheet.pageSetup, isNull);
    expect(sheet.headerFooter, isNull);
  });

  test('fit and first page number are read only when they apply', () {
    final XlsxWorkbook book = _open(
      '<pageSetup fitToWidth="2" fitToHeight="3" firstPageNumber="7" '
      'scale="80"/>',
    );
    expect(
      book.sheets.single.pageSetup,
      const XlsxPageSetup(scale: 80),
      reason: 'no fitToPage and no useFirstPageNumber',
    );
    final XlsxWorkbook fit = _open(
      '<pageSetup fitToWidth="2" fitToHeight="0" firstPageNumber="7" '
      'useFirstPageNumber="1" scale="80"/>',
      head: '<sheetPr><pageSetUpPr fitToPage="1"/></sheetPr>',
    );
    expect(
      fit.sheets.single.pageSetup,
      const XlsxPageSetup(fitToWidth: 2, firstPageNumber: 7),
      reason: 'fitToHeight 0 is automatic; scale is ignored under fitting',
    );
    final XlsxWorkbook absent = _open(
      '<pageSetup/>',
      head: '<sheetPr><pageSetUpPr fitToPage="1"/></sheetPr>',
    );
    expect(
      absent.sheets.single.pageSetup,
      const XlsxPageSetup(fitToWidth: 1, fitToHeight: 1),
    );
    expect(fit.warnings, isEmpty);
  });

  group('set writes what the writer writes', () {
    for (final (String, XlsxPageSetup) c in <(String, XlsxPageSetup)>[
      ('defaults', const XlsxPageSetup()),
      (
        'landscape a4 fit to width',
        const XlsxPageSetup(
          orientation: XlsxOrientation.landscape,
          paperSize: XlsxPaperSize.a4,
          fitToWidth: 1,
          centerHorizontally: true,
          printGridLines: true,
        ),
      ),
      (
        'scaled',
        const XlsxPageSetup(
          scale: 85,
          firstPageNumber: 3,
          pageOrder: XlsxPageOrder.overThenDown,
          margins: _narrow,
        ),
      ),
      (
        'everything',
        const XlsxPageSetup(
          orientation: XlsxOrientation.portrait,
          paperSize: XlsxPaperSize(118),
          fitToWidth: 3,
          fitToHeight: 0,
          firstPageNumber: 1,
          pageOrder: XlsxPageOrder.overThenDown,
          blackAndWhite: true,
          draft: true,
          margins: _narrow,
          centerHorizontally: true,
          centerVertically: true,
          printGridLines: true,
          printHeadings: true,
        ),
      ),
      (
        'letter and 100 percent',
        const XlsxPageSetup(paperSize: XlsxPaperSize.letter, scale: 100),
      ),
    ]) {
      test(c.$1, () {
        final XlsxWorkbook book = XlsxWorkbook();
        final XlsxSheet sheet = book.addSheet('S')..pageSetup = c.$2;
        expect(_modelWrote(book), _written(c.$2));
        expect(_modelWrote(book), contains('<pageMargins '));
        final XlsxWorkbook again = XlsxWorkbook.open(book.save().bytes);
        expect(again.warnings, isEmpty);
        expect(again.sheets.single.pageSetup, isNotNull);
        expect(sheet.pageSetup?.margins, c.$2.margins);
      });
    }

    test('a setup that reads back equal reads back equal', () {
      const XlsxPageSetup setup = XlsxPageSetup(
        orientation: XlsxOrientation.landscape,
        fitToWidth: 2,
        firstPageNumber: 4,
        blackAndWhite: true,
        margins: _narrow,
        printHeadings: true,
      );
      final XlsxWorkbook book = XlsxWorkbook();
      book.addSheet('S').pageSetup = setup;
      expect(
        XlsxWorkbook.open(book.save().bytes).sheets.single.pageSetup,
        setup,
      );
    });

    test('a prefixed worksheet keeps its namespace', () {
      final XlsxWorkbook book = XlsxWorkbook.open(
        _package('<x:worksheet xmlns:x="$mainNs"><x:sheetData/></x:worksheet>'),
      );
      book.sheets.single.pageSetup = const XlsxPageSetup(
        orientation: XlsxOrientation.landscape,
        fitToWidth: 1,
        printGridLines: true,
      );
      book.sheets.single.headerFooter = const XlsxHeaderFooter(
        oddHeader: 'Top',
      );
      final String xml = _sheetXml(book);
      expect(xml, contains('<x:printOptions '));
      expect(xml, contains('<x:pageMargins '));
      expect(xml, contains('<x:pageSetup '));
      expect(xml, contains('<x:sheetPr><x:pageSetUpPr fitToPage="1"/>'));
      expect(xml, contains('<x:headerFooter>'));
      final XlsxWorkbook again = XlsxWorkbook.open(book.save().bytes);
      expect(again.warnings, isEmpty);
      expect(again.sheets.single.pageSetup?.fitToWidth, 1);
      expect(again.sheets.single.headerFooter?.oddHeader, 'Top');
    });

    test('the elements go in schema position', () {
      final XlsxWorkbook book = _open(
        '<hyperlinks/><tableParts count="0"/>',
        head: '<sheetViews><sheetView workbookViewId="0"/></sheetViews>',
      );
      book.sheets.single.pageSetup = const XlsxPageSetup(
        fitToWidth: 1,
        printGridLines: true,
        orientation: XlsxOrientation.landscape,
      );
      book.sheets.single.headerFooter = const XlsxHeaderFooter(oddFooter: 'x');
      final String xml = _sheetXml(book);
      final List<String> order = <String>[
        '<sheetPr',
        '<sheetViews',
        '<sheetData',
        '<hyperlinks',
        '<printOptions',
        '<pageMargins',
        '<pageSetup',
        '<headerFooter',
        '<tableParts',
      ];
      int last = -1;
      for (final String n in order) {
        final int at = xml.indexOf(n);
        expect(at, greaterThan(last), reason: n);
        last = at;
      }
    });
  });

  group('kept attributes stay', () {
    test('r:id and the dpi stay on pageSetup', () {
      final XlsxWorkbook book = _open(
        '<pageMargins left="0.7" right="0.7" top="0.75" bottom="0.75" '
        'header="0.3" footer="0.3"/>'
        '<pageSetup r:id="rId1" horizontalDpi="300" orientation="portrait"/>',
      );
      final XlsxSheet sheet = book.sheets.single;
      expect(
        sheet.pageSetup,
        const XlsxPageSetup(orientation: XlsxOrientation.portrait),
      );
      sheet.pageSetup = const XlsxPageSetup(
        orientation: XlsxOrientation.landscape,
      );
      final String xml = _element(_sheetXml(book), 'pageSetup');
      expect(xml, contains('r:id="rId1"'));
      expect(xml, contains('horizontalDpi="300"'));
      expect(xml, contains('orientation="landscape"'));
      expect(xml, isNot(contains('portrait')));
    });

    test('the element stays for its kept attributes', () {
      final XlsxWorkbook book = _open(
        '<pageMargins left="0.7" right="0.7" top="0.75" bottom="0.75" '
        'header="0.3" footer="0.3"/>'
        '<pageSetup r:id="rId1" copies="2" orientation="landscape"/>',
      );
      book.sheets.single.pageSetup = const XlsxPageSetup();
      final String xml = _element(_sheetXml(book), 'pageSetup');
      expect(xml, contains('r:id="rId1"'));
      expect(xml, contains('copies="2"'));
      expect(xml, isNot(contains('orientation')));
    });

    test('an element left bare goes', () {
      final XlsxWorkbook book = _open(
        '<pageMargins left="0.7" right="0.7" top="0.75" bottom="0.75" '
        'header="0.3" footer="0.3"/><pageSetup orientation="landscape" '
        'paperSize="9"/>',
      );
      book.sheets.single.pageSetup = const XlsxPageSetup();
      expect(_sheetXml(book), isNot(contains('<pageSetup')));
      expect(_sheetXml(book), contains('<pageMargins'));
    });

    test('a spelling whose meaning is kept stays', () {
      final XlsxWorkbook book = _open(
        '<printOptions gridLinesSet="0" headings="true" gridLines="0"/>'
        '<pageMargins left="0.7" right="0.7" top="0.75" bottom="0.75" '
        'header="0.3" footer="0.3"/>'
        '<pageSetup paperSize="1" scale="100" pageOrder="downThenOver"/>',
      );
      book.sheets.single.pageSetup = const XlsxPageSetup(
        printHeadings: true,
        orientation: XlsxOrientation.landscape,
      );
      final String xml = _sheetXml(book);
      expect(_element(xml, 'printOptions'), contains('headings="true"'));
      expect(_element(xml, 'printOptions'), contains('gridLinesSet="0"'));
      final String setup = _element(xml, 'pageSetup');
      expect(setup, contains('paperSize="1"'));
      expect(setup, contains('scale="100"'));
      expect(setup, contains('orientation="landscape"'));
    });

    test('printOptions of all defaults keeps a kept attribute', () {
      final XlsxWorkbook book = _open(
        '<printOptions gridLinesSet="0" headings="1"/>',
      );
      book.sheets.single.pageSetup = const XlsxPageSetup();
      final String options = _element(_sheetXml(book), 'printOptions');
      expect(options, contains('gridLinesSet="0"'));
      expect(options, isNot(contains('headings')));
    });

    test('printOptions of all defaults keeps a bad attribute', () {
      final XlsxWorkbook book = _open(
        '<printOptions gridLines="yes" headings="1"/>',
      );
      book.sheets.single.pageSetup = const XlsxPageSetup();
      final String options = _element(_sheetXml(book), 'printOptions');
      expect(options, contains('gridLines="yes"'));
      expect(options, isNot(contains('headings')));
    });

    test('printOptions goes when the edit leaves it bare', () {
      final XlsxWorkbook book = _open('<printOptions headings="1"/>');
      book.sheets.single.pageSetup = const XlsxPageSetup();
      expect(_sheetXml(book), isNot(contains('printOptions')));
    });

    test('a bare printOptions no edit touches stays', () {
      final XlsxWorkbook book = _open(
        '<printOptions/><pageMargins left="1" right="1" top="1" bottom="1" '
        'header="0.3" footer="0.3"/>',
      );
      book.sheets.single.pageSetup = const XlsxPageSetup();
      expect(_sheetXml(book), contains('<printOptions/>'));
    });

    test('margins change only what differs', () {
      final XlsxWorkbook book = _open(
        '<pageMargins left="1" right="0.7" top="0.75" bottom="0.75" '
        'header="0.3" footer="0.3"/>',
      );
      book.sheets.single.pageSetup = const XlsxPageSetup(
        margins: XlsxPageMargins(left: 1, top: 2),
      );
      final String xml = _element(_sheetXml(book), 'pageMargins');
      expect(xml, contains('left="1"'));
      expect(xml, contains('top="2"'));
      expect(xml, contains('right="0.7"'));
    });

    test('a wanted default drops a non-default attribute', () {
      final XlsxWorkbook book = _open(
        '<pageSetup paperSize="9" scale="50" pageOrder="overThenDown" '
        'blackAndWhite="1" draft="1" firstPageNumber="3" '
        'useFirstPageNumber="1"/>',
      );
      book.sheets.single.pageSetup = const XlsxPageSetup(
        margins: XlsxPageMargins(),
      );
      expect(_sheetXml(book), isNot(contains('<pageSetup')));
      final XlsxWorkbook b2 = _open(
        '<pageSetup paperSize="9" scale="50" pageOrder="overThenDown" '
        'blackAndWhite="1" draft="1" firstPageNumber="3" '
        'useFirstPageNumber="1" r:id="rId9"/>',
      );
      b2.sheets.single.pageSetup = const XlsxPageSetup();
      expect(_element(_sheetXml(b2), 'pageSetup'), '<pageSetup r:id="rId9"/>');
    });
  });

  group('fit to page', () {
    test('joins a new sheetPr and leaves it', () {
      final XlsxWorkbook book = _open('');
      final XlsxSheet sheet = book.sheets.single;
      sheet.pageSetup = const XlsxPageSetup(fitToWidth: 1, fitToHeight: 2);
      expect(
        _element(_sheetXml(book), 'sheetPr'),
        '<sheetPr><pageSetUpPr fitToPage="1"/></sheetPr>',
      );
      expect(
        _element(_sheetXml(book), 'pageSetup'),
        contains('fitToHeight="2"'),
      );
      sheet.pageSetup = const XlsxPageSetup(scale: 50);
      expect(_sheetXml(book), isNot(contains('sheetPr')));
      expect(_sheetXml(book), isNot(contains('fitTo')));
      expect(_element(_sheetXml(book), 'pageSetup'), '<pageSetup scale="50"/>');
    });

    test('joins and leaves an existing sheetPr', () {
      final XlsxWorkbook book = _open(
        '',
        head:
            '<sheetPr codeName="Sheet1"><tabColor rgb="FFFF0000"/>'
            '<outlinePr summaryBelow="0"/></sheetPr>',
      );
      final XlsxSheet sheet = book.sheets.single;
      sheet.pageSetup = const XlsxPageSetup(fitToHeight: 1);
      expect(
        _element(_sheetXml(book), 'sheetPr'),
        '<sheetPr codeName="Sheet1"><tabColor rgb="FFFF0000"/>'
        '<outlinePr summaryBelow="0"/><pageSetUpPr fitToPage="1"/></sheetPr>',
      );
      sheet.pageSetup = null;
      expect(
        _element(_sheetXml(book), 'sheetPr'),
        '<sheetPr codeName="Sheet1"><tabColor rgb="FFFF0000"/>'
        '<outlinePr summaryBelow="0"/></sheetPr>',
      );
    });

    test(
      'an empty sheetPr goes, one with another attribute of pageSetUpPr stays',
      () {
        final XlsxWorkbook book = _open(
          '<pageSetup fitToWidth="1" fitToHeight="1"/>',
          head: '<sheetPr><pageSetUpPr fitToPage="1"/></sheetPr>',
        );
        book.sheets.single.pageSetup = const XlsxPageSetup();
        expect(_sheetXml(book), isNot(contains('sheetPr')));
        expect(_sheetXml(book), isNot(contains('fitTo')));
        final XlsxWorkbook keeps = _open(
          '',
          head:
              '<sheetPr><pageSetUpPr autoPageBreaks="0" fitToPage="1"/>'
              '</sheetPr>',
        );
        keeps.sheets.single.pageSetup = const XlsxPageSetup();
        expect(
          _element(_sheetXml(keeps), 'sheetPr'),
          '<sheetPr><pageSetUpPr autoPageBreaks="0"/></sheetPr>',
        );
      },
    );

    test('a fit axis equal to its default is not written again', () {
      final XlsxWorkbook book = _open(
        '<pageSetup/>',
        head: '<sheetPr><pageSetUpPr fitToPage="1"/></sheetPr>',
      );
      book.sheets.single.pageSetup = const XlsxPageSetup(
        fitToWidth: 1,
        fitToHeight: 3,
      );
      final String xml = _element(_sheetXml(book), 'pageSetup');
      expect(xml, contains('fitToHeight="3"'));
      expect(xml, isNot(contains('fitToWidth')));
    });

    test('stale fit attributes do not come alive', () {
      final XlsxWorkbook book = _open('<pageSetup fitToWidth="5"/>');
      book.sheets.single.pageSetup = const XlsxPageSetup(fitToHeight: 2);
      final XlsxPageSetup read = book.sheets.single.pageSetup!;
      expect(read.fitToWidth, isNull);
      expect(read.fitToHeight, 2);
    });
  });

  group('a value out of range throws; nothing changes', () {
    test('a scale past the limit throws named scale', () {
      final XlsxWorkbook book = _open('<pageSetup orientation="landscape"/>');
      final Uint8List before = book.save().bytes;
      for (final int scale in <int>[9, 401]) {
        expect(
          () => book.sheets.single.pageSetup = XlsxPageSetup(scale: scale),
          throwsA(
            isA<ArgumentError>().having(
              (ArgumentError e) => e.name,
              'name',
              'scale',
            ),
          ),
        );
      }
      expect(
        () => book.sheets.single.pageSetup = const XlsxPageSetup(
          scale: 50,
          fitToWidth: 1,
        ),
        throwsArgumentError,
      );
      expect(
        () => book.sheets.single.pageSetup = const XlsxPageSetup(
          margins: XlsxPageMargins(left: -1),
        ),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => e.name,
            'name',
            'margins.left',
          ),
        ),
      );
      expect(changeLogOf(book).hasChanges, isFalse);
      expect(comparePackages(before, book.save().bytes), isEmpty);
    });

    test('a header text too long throws named after its field', () {
      final XlsxWorkbook book = _open('');
      expect(
        () => book.sheets.single.headerFooter = XlsxHeaderFooter(
          evenFooter: 'x' * 300,
        ),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => e.name,
            'name',
            'evenFooter',
          ),
        ),
      );
      expect(
        () => book.sheets.single.headerFooter = const XlsxHeaderFooter(
          oddHeader: 'a&',
        ),
        throwsArgumentError,
      );
      expect(changeLogOf(book).hasChanges, isFalse);
    });
  });

  group('null removes', () {
    test('the three elements and fitToPage', () {
      final XlsxWorkbook book = _open(
        '<printOptions gridLines="1"/><pageMargins left="1" right="1" '
        'top="1" bottom="1" header="1" footer="1"/>'
        '<pageSetup orientation="landscape" r:id="rId1" fitToWidth="1"/>'
        '<headerFooter><oddHeader>x</oddHeader></headerFooter>',
        head: '<sheetPr><pageSetUpPr fitToPage="1"/></sheetPr>',
      );
      book.sheets.single.pageSetup = null;
      final String xml = _sheetXml(book);
      expect(xml, isNot(contains('printOptions')));
      expect(xml, isNot(contains('pageMargins')));
      expect(xml, isNot(contains('pageSetup')));
      expect(xml, isNot(contains('sheetPr')));
      expect(xml, contains('<headerFooter>'), reason: 'not part of the setup');
      expect(book.sheets.single.pageSetup, isNull);
    });

    test('a headerFooter keeps its flags element until it is null', () {
      final XlsxWorkbook book = _open(
        '<headerFooter><oddHeader>x</oddHeader></headerFooter>'
        '<legacyDrawingHF r:id="rId1"/>',
      );
      book.sheets.single.headerFooter = null;
      final String xml = _sheetXml(book);
      expect(xml, isNot(contains('<headerFooter')));
      expect(xml, contains('<legacyDrawingHF r:id="rId1"/>'));
    });

    test('nothing to remove changes nothing', () {
      final XlsxWorkbook book = _open('');
      book.sheets.single.pageSetup = null;
      book.sheets.single.headerFooter = null;
      expect(changeLogOf(book).hasChanges, isFalse);
    });
  });

  group('an equal set is no edit', () {
    test('page setup read from the fixtures', () {
      final XlsxWorkbook book = XlsxWorkbook.open(_fixture('m3_page_setup'));
      for (final XlsxSheet s in book.sheets) {
        s.pageSetup = s.pageSetup;
      }
      expect(changeLogOf(book).hasChanges, isFalse);
    });

    test('header and footer read from the fixture', () {
      final XlsxWorkbook book = XlsxWorkbook.open(_fixture('m3_header_footer'));
      final XlsxSheet s = book.sheets.single;
      s.headerFooter = s.headerFooter;
      expect(changeLogOf(book).hasChanges, isFalse);
    });

    test('a bad value that reads as the default', () {
      final XlsxWorkbook book = _open(
        '<printOptions headings="x"/><pageMargins left="abc" right="0.7" '
        'top="0.75" bottom="0.75" header="0.3" footer="0.3"/>'
        '<pageSetup orientation="sideways" scale="900"/>'
        '<headerFooter scaleWithDoc="x"><oddHeader>a&amp;</oddHeader>'
        '</headerFooter>',
      );
      final XlsxSheet s = book.sheets.single;
      s.pageSetup = s.pageSetup;
      s.headerFooter = s.headerFooter;
      expect(changeLogOf(book).hasChanges, isFalse);
      final String xml = _sheetXml(book);
      expect(xml, contains('orientation="sideways"'));
      expect(xml, contains('left="abc"'));
    });
  });

  group('bad values are kept and reported', () {
    test('orientation and a margin', () {
      final XlsxWorkbook book = _open(
        '<pageMargins left="abc" right="-1" top="0.75" bottom="0.75" '
        'header="0.3" footer="NaN"/><pageSetup orientation="sideways"/>',
      );
      final XlsxPageSetup? read = book.sheets.single.pageSetup;
      expect(read, const XlsxPageSetup());
      expect(book.sheets.single.pageSetup, const XlsxPageSetup());
      expect(_invalid(book), 2);
      expect(_details(book).toSet(), <String>{'pageSetup', 'pageMargins'});
      final String xml = _sheetXml(book);
      expect(xml, contains('orientation="sideways"'));
      expect(xml, contains('left="abc"'));
    });

    test('a header that is not XML text reads as none and stays', () {
      for (final String text in <String>['&bad;', '&am', '&']) {
        final XlsxWorkbook book = _open(
          '<headerFooter><oddHeader>$text</oddHeader>'
          '<oddFooter>Page</oddFooter></headerFooter>',
        );
        final XlsxSheet sheet = book.sheets.single;
        final XlsxHeaderFooter? read = sheet.headerFooter;
        expect(read?.oddHeader, isNull, reason: text);
        expect(read?.oddFooter, 'Page', reason: text);
        expect(_details(book), <String>['headerFooter'], reason: text);
        sheet.headerFooter = read;
        expect(_sheetXml(book), contains('<oddHeader>$text</oddHeader>'));
      }
    });

    test('flags, numbers and names of every element', () {
      final XlsxWorkbook book = _open(
        '<printOptions gridLines="yes" headings="1"/>'
        '<pageSetup paperSize="0" scale="9" pageOrder="x" draft="2" '
        'firstPageNumber="0" useFirstPageNumber="1" fitToWidth="-1"/>',
        head: '<sheetPr><pageSetUpPr fitToPage="1"/></sheetPr>',
      );
      final XlsxPageSetup read = book.sheets.single.pageSetup!;
      expect(read.printGridLines, isFalse);
      expect(read.printHeadings, isTrue);
      expect(read.paperSize, isNull);
      expect(read.scale, isNull);
      expect(read.pageOrder, isNull);
      expect(read.draft, isFalse);
      expect(read.firstPageNumber, isNull);
      expect(read.fitToWidth, 1);
      expect(read.fitToHeight, 1);
      expect(_details(book).toSet(), <String>{'printOptions', 'pageSetup'});
      expect(_sheetXml(book), contains('paperSize="0"'));
    });

    test('a header or footer', () {
      final XlsxWorkbook book = _open(
        '<headerFooter differentFirst="x" alignWithMargins="2">'
        '<oddHeader>a&amp;</oddHeader><oddFooter>ok</oddFooter>'
        '<evenHeader>_x0001_</evenHeader></headerFooter>',
      );
      expect(
        book.sheets.single.headerFooter,
        const XlsxHeaderFooter(oddFooter: 'ok'),
      );
      expect(_details(book), <String>['headerFooter']);
      expect(_invalid(book), 1);
      expect(_sheetXml(book), contains('<oddHeader>a&amp;</oddHeader>'));
    });
  });

  group('header and footer', () {
    test('set writes what the writer writes', () {
      for (final XlsxHeaderFooter value in <XlsxHeaderFooter>[
        const XlsxHeaderFooter(oddHeader: 'Top'),
        XlsxHeaderFooter(
          oddHeader: XlsxHeaderFooter.sections(
            left: XlsxHeaderFooter.literal('R&D'),
            right: XlsxHeaderFooter.date,
          ),
          oddFooter: 'Page &P of &N',
          evenHeader: 'e',
          evenFooter: '_x0041_ and <tags> & stuff&&',
          firstHeader: 'first',
          firstFooter: 'f',
          scaleWithDocument: false,
          alignWithMargins: false,
        ),
        const XlsxHeaderFooter(differentOddEven: true, differentFirst: true),
        const XlsxHeaderFooter(scaleWithDocument: false),
        const XlsxHeaderFooter(),
      ]) {
        final XlsxWriter writer = XlsxWriter();
        writer.addSheet('S').headerFooter(value);
        final String expected = _element(
          partText(writer.close().bytes, 'xl/worksheets/sheet1.xml'),
          'headerFooter',
        );
        final XlsxWorkbook book = XlsxWorkbook();
        final XlsxSheet sheet = book.addSheet('S')..headerFooter = value;
        expect(_element(_sheetXml(book), 'headerFooter'), expected);
        final XlsxWorkbook again = XlsxWorkbook.open(book.save().bytes);
        expect(again.warnings, isEmpty);
        if (expected.isNotEmpty) {
          expect(again.sheets.single.headerFooter, sheet.headerFooter);
        }
      }
    });

    test('a text and its special characters read back', () {
      const XlsxHeaderFooter value = XlsxHeaderFooter(
        oddHeader: '_x0041_ and <tags> & stuff&&',
        oddFooter: 'R&&D',
        firstFooter: 'x',
        differentFirst: true,
      );
      final XlsxWorkbook book = XlsxWorkbook();
      book.addSheet('S').headerFooter = value;
      expect(
        XlsxWorkbook.open(book.save().bytes).sheets.single.headerFooter,
        const XlsxHeaderFooter(
          oddHeader: '_x0041_ and <tags> & stuff&&',
          oddFooter: 'R&&D',
          firstFooter: 'x',
        ),
        reason: 'differentFirst true is what the writer derives',
      );
    });

    test('_xHHHH_ is decoded', () {
      final XlsxWorkbook book = _open(
        '<headerFooter><oddHeader>_x0041_B_x005F_x0041_</oddHeader>'
        '</headerFooter>',
      );
      expect(book.sheets.single.headerFooter?.oddHeader, 'AB_x0041_');
    });

    test('the flags read null when they are derived', () {
      final XlsxWorkbook book = _open(
        '<headerFooter differentOddEven="1" differentFirst="0">'
        '<evenFooter>e</evenFooter></headerFooter>',
      );
      expect(
        book.sheets.single.headerFooter,
        const XlsxHeaderFooter(evenFooter: 'e'),
      );
      final XlsxWorkbook off = _open(
        '<headerFooter differentOddEven="0"><evenFooter>e</evenFooter>'
        '<firstHeader>f</firstHeader></headerFooter>',
      );
      expect(
        off.sheets.single.headerFooter,
        const XlsxHeaderFooter(
          evenFooter: 'e',
          firstHeader: 'f',
          differentOddEven: false,
          differentFirst: false,
        ),
        reason: 'the texts say on, the flag says off; first is also off',
      );
      final XlsxWorkbook lone = _open('<headerFooter differentFirst="true"/>');
      expect(
        lone.sheets.single.headerFooter,
        const XlsxHeaderFooter(differentFirst: true),
      );
    });

    test('scaleWithDoc and alignWithMargins', () {
      final XlsxWorkbook book = _open(
        '<headerFooter scaleWithDoc="0" alignWithMargins="false"/>',
      );
      expect(
        book.sheets.single.headerFooter,
        const XlsxHeaderFooter(
          scaleWithDocument: false,
          alignWithMargins: false,
        ),
      );
    });

    test('setting replaces the texts and keeps the rest', () {
      final XlsxWorkbook book = _open(
        '<headerFooter differentOddEven="1" xml:space="preserve" '
        'x:foo="1" xmlns:x="urn:x"><oddHeader>old</oddHeader>'
        '<evenFooter>old</evenFooter><x:extra/></headerFooter>'
        '<legacyDrawingHF r:id="rId1"/>',
      );
      book.sheets.single.headerFooter = const XlsxHeaderFooter(
        oddFooter: 'new',
        differentOddEven: true,
      );
      final String xml = _element(_sheetXml(book), 'headerFooter');
      expect(xml, contains('differentOddEven="1"'));
      expect(xml, contains('xml:space="preserve"'));
      expect(xml, contains('x:foo="1"'));
      expect(xml, contains('<x:extra/>'));
      expect(xml, contains('<oddFooter>new</oddFooter>'));
      expect(xml, isNot(contains('old')));
      expect(_sheetXml(book), contains('<legacyDrawingHF r:id="rId1"/>'));
      expect(
        book.sheets.single.headerFooter,
        const XlsxHeaderFooter(oddFooter: 'new', differentOddEven: true),
      );
    });

    test('a text equal to the wanted one keeps its spelling', () {
      final XlsxWorkbook book = _open(
        '<headerFooter><oddHeader>_x0041_</oddHeader></headerFooter>',
      );
      book.sheets.single.headerFooter = const XlsxHeaderFooter(
        oddHeader: 'A',
        oddFooter: 'z',
      );
      final String xml = _element(_sheetXml(book), 'headerFooter');
      expect(xml, contains('<oddHeader>_x0041_</oddHeader>'));
      expect(xml, contains('<oddFooter>z</oddFooter>'));
    });

    test('a flag changes only its own attribute', () {
      final XlsxWorkbook book = _open(
        '<headerFooter scaleWithDoc="false" alignWithMargins="0">'
        '<oddHeader>x</oddHeader></headerFooter>',
      );
      book.sheets.single.headerFooter = const XlsxHeaderFooter(
        oddHeader: 'x',
        alignWithMargins: true,
        scaleWithDocument: false,
      );
      final String xml = _element(_sheetXml(book), 'headerFooter');
      expect(xml, contains('scaleWithDoc="false"'));
      expect(xml, isNot(contains('alignWithMargins')));
    });

    test('a default value empties the element and it goes', () {
      final XlsxWorkbook book = _open(
        '<headerFooter><oddHeader>x</oddHeader></headerFooter>',
      );
      book.sheets.single.headerFooter = const XlsxHeaderFooter();
      expect(_sheetXml(book), isNot(contains('headerFooter')));
      final XlsxWorkbook keeps = _open(
        '<headerFooter xmlns:x="urn:x"><oddHeader>x</oddHeader>'
        '<x:extra/></headerFooter>',
      );
      keeps.sheets.single.headerFooter = const XlsxHeaderFooter();
      expect(_sheetXml(keeps), contains('<x:extra/>'));
      expect(_sheetXml(keeps), isNot(contains('oddHeader')));
    });

    test('a repeated headerFooter stays and is not typed', () {
      final XlsxWorkbook book = _open(
        '<headerFooter><oddHeader>a</oddHeader></headerFooter>'
        '<headerFooter><oddHeader>b</oddHeader></headerFooter>',
      );
      book.sheets.single.headerFooter = const XlsxHeaderFooter(oddHeader: 'c');
      final String xml = _sheetXml(book);
      expect(xml, contains('<oddHeader>c</oddHeader>'));
      expect(xml, contains('<oddHeader>b</oddHeader>'));
    });
  });

  group('undo', () {
    test('a page setup and a header, back to the input', () {
      final Uint8List input = _package(
        _worksheet(
          '<printOptions gridLines="1"/><pageMargins left="1" right="1" '
          'top="1" bottom="1" header="1" footer="1"/>'
          '<pageSetup orientation="landscape" r:id="rId1"/>'
          '<headerFooter><oddHeader>x</oddHeader></headerFooter>',
          head: '<sheetPr><pageSetUpPr fitToPage="1"/></sheetPr>',
        ),
      );
      final XlsxWorkbook book = XlsxWorkbook.open(input);
      final ChangeLog log = changeLogOf(book);
      final ChangeSet set = log.transaction(() {
        book.sheets.single.pageSetup = const XlsxPageSetup(scale: 50);
        book.sheets.single.headerFooter = const XlsxHeaderFooter(
          oddFooter: 'y',
        );
      });
      expect(_sheetXml(book), isNot(contains('<sheetPr')));
      log.revertSet(set);
      expect(comparePackages(input, book.save().bytes), isEmpty);
      log.reapplySet(set);
      expect(_sheetXml(book), contains('scale="50"'));
      final ChangeSet gone = log.transaction(() {
        book.sheets.single.pageSetup = null;
        book.sheets.single.headerFooter = null;
      });
      log.revertSet(gone);
      expect(book.sheets.single.pageSetup, const XlsxPageSetup(scale: 50));
    });

    test('new elements go on undo', () {
      final XlsxWorkbook book = XlsxWorkbook();
      book.addSheet('S');
      final ChangeLog log = changeLogOf(book);
      final ChangeSet set = log.transaction(() {
        book.sheets.single.pageSetup = const XlsxPageSetup(fitToWidth: 1);
        book.sheets.single.headerFooter = const XlsxHeaderFooter(
          oddHeader: 'x',
        );
      });
      log.revertSet(set);
      final String xml = _sheetXml(book);
      for (final String n in <String>[
        'sheetPr',
        'pageMargins',
        'pageSetup',
        'headerFooter',
      ]) {
        expect(xml, isNot(contains(n)), reason: n);
      }
    });
  });

  test('a repeated pageSetup stays and is not typed', () {
    final XlsxWorkbook book = _open(
      '<pageSetup orientation="landscape"/><pageSetup scale="50"/>',
    );
    book.sheets.single.pageSetup = const XlsxPageSetup(
      orientation: XlsxOrientation.landscape,
    );
    expect(_sheetXml(book), contains('scale="50"'));
  });

  test('an edited setup saves and reads back through the writer', () {
    final XlsxWorkbook book = XlsxWorkbook.open(_fixture('m3_page_setup'));
    book.sheet('Scaled').pageSetup = const XlsxPageSetup(
      orientation: XlsxOrientation.landscape,
      scale: 85,
      firstPageNumber: 3,
      margins: _narrow,
    );
    final XlsxWorkbook again = XlsxWorkbook.open(book.save().bytes);
    expect(again.warnings, isEmpty);
    expect(
      again.sheet('Scaled').pageSetup,
      const XlsxPageSetup(
        orientation: XlsxOrientation.landscape,
        scale: 85,
        firstPageNumber: 3,
        margins: _narrow,
      ),
    );
    expect(
      again.sheet('Landscape').pageSetup,
      XlsxWorkbook.open(_fixture('m3_page_setup')).sheet('Landscape').pageSetup,
    );
    expect(utf8.decode(utf8.encode('ok')), 'ok');
  });
}
