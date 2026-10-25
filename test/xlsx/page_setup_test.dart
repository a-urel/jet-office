import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

import '../support/read_xlsx.dart';
import '../support/xlsx_checker.dart';

const String _sheet1 = 'xl/worksheets/sheet1.xml';

/// Sheet 1 of a workbook in which [setup] sets up the sheet `S`.
String _sheet(void Function(XlsxSheetWriter sheet) setup) {
  final XlsxWriter book = XlsxWriter();
  final XlsxSheetWriter sheet = book.addSheet('S')..row(<Object?>['x']);
  setup(sheet);
  return readXlsx(book.close().bytes)[_sheet1]!;
}

String _setup(XlsxPageSetup setup) =>
    _sheet((XlsxSheetWriter s) => s.pageSetup(setup));

const String _normalMargins =
    '<pageMargins left="0.7" right="0.7" top="0.75" bottom="0.75" '
    'header="0.3" footer="0.3"/>';

Matcher _argumentNamed(String name) => throwsA(
  isA<ArgumentError>().having((ArgumentError e) => e.name, 'name', name),
);

void main() {
  group('writing', () {
    test('landscape A4 fit to one page wide', () {
      final String xml = _setup(
        const XlsxPageSetup(
          orientation: XlsxOrientation.landscape,
          paperSize: XlsxPaperSize.a4,
          fitToWidth: 1,
        ),
      );
      expect(xml, contains('<sheetPr><pageSetUpPr fitToPage="1"/></sheetPr>'));
      expect(xml, contains(_normalMargins));
      expect(
        xml,
        contains(
          '<pageSetup paperSize="9" fitToWidth="1" fitToHeight="0" '
          'orientation="landscape"/>',
        ),
      );
      expect(xml, isNot(contains('<printOptions')));
    });

    test('pageSetUpPr follows tabColor and outlinePr', () {
      final XlsxWriter book = XlsxWriter();
      book.addSheet('S')
        ..tabColor(XlsxColor.hex('FF0000'))
        ..outlineSummary(below: false)
        ..row(<Object?>['x'])
        ..pageSetup(const XlsxPageSetup(fitToHeight: 2));
      final String xml = readXlsx(book.close().bytes)[_sheet1]!;
      expect(
        xml,
        contains(
          '<sheetPr><tabColor rgb="FFFF0000"/><outlinePr summaryBelow="0"/>'
          '<pageSetUpPr fitToPage="1"/></sheetPr>',
        ),
      );
      expect(xml, contains('<pageSetup fitToWidth="0" fitToHeight="2"/>'));
    });

    test('a scale writes scale and no pageSetUpPr', () {
      final String xml = _setup(const XlsxPageSetup(scale: 85));
      expect(xml, contains('<pageSetup scale="85"/>'));
      expect(xml, isNot(contains('pageSetUpPr')));
      expect(xml, isNot(contains('<sheetPr')));
    });

    test('a first page number writes useFirstPageNumber', () {
      final String xml = _setup(
        const XlsxPageSetup(
          firstPageNumber: 3,
          pageOrder: XlsxPageOrder.overThenDown,
          blackAndWhite: true,
          draft: true,
        ),
      );
      expect(
        xml,
        contains(
          '<pageSetup firstPageNumber="3" pageOrder="overThenDown" '
          'blackAndWhite="1" draft="1" useFirstPageNumber="1"/>',
        ),
      );
    });

    test('defaults write pageMargins only', () {
      final String xml = _setup(const XlsxPageSetup());
      expect(xml, contains(_normalMargins));
      expect(xml, isNot(contains('<pageSetup')));
      expect(xml, isNot(contains('<printOptions')));
      expect(xml, isNot(contains('<sheetPr')));
    });

    test('the default paper size and scale are not written', () {
      final String xml = _setup(
        const XlsxPageSetup(
          paperSize: XlsxPaperSize.letter,
          scale: 100,
          orientation: XlsxOrientation.portrait,
        ),
      );
      expect(xml, contains('<pageSetup orientation="portrait"/>'));
    });

    test('margins are written as given', () {
      final String xml = _setup(
        const XlsxPageSetup(
          margins: XlsxPageMargins(
            left: 0.25,
            right: 0.5,
            top: 1,
            bottom: 1.25,
            header: 0,
            footer: 0.1,
          ),
        ),
      );
      expect(
        xml,
        contains(
          '<pageMargins left="0.25" right="0.5" top="1" bottom="1.25" '
          'header="0" footer="0.1"/>',
        ),
      );
    });

    test('centering, gridlines and headings write printOptions', () {
      final String xml = _setup(
        const XlsxPageSetup(
          centerHorizontally: true,
          centerVertically: true,
          printHeadings: true,
          printGridLines: true,
        ),
      );
      expect(
        xml,
        contains(
          '<printOptions horizontalCentered="1" verticalCentered="1" '
          'headings="1" gridLines="1"/>',
        ),
      );
      expect(
        _setup(const XlsxPageSetup(printGridLines: true)),
        contains('<printOptions gridLines="1"/>'),
      );
    });

    test('a later call replaces the earlier one', () {
      final String xml = _sheet((XlsxSheetWriter s) {
        s.pageSetup(const XlsxPageSetup(scale: 50));
        s.pageSetup(const XlsxPageSetup(scale: 60));
      });
      expect(xml, contains('scale="60"'));
      expect(xml, isNot(contains('scale="50"')));
    });

    test('every paper size constant has its id', () {
      expect(
        <int>[
          XlsxPaperSize.letter.id,
          XlsxPaperSize.tabloid.id,
          XlsxPaperSize.legal.id,
          XlsxPaperSize.executive.id,
          XlsxPaperSize.a3.id,
          XlsxPaperSize.a4.id,
          XlsxPaperSize.a5.id,
          XlsxPaperSize.b4.id,
          XlsxPaperSize.b5.id,
        ],
        <int>[1, 3, 5, 7, 8, 9, 11, 12, 13],
      );
    });
  });

  group('order', () {
    test('printOptions, pageMargins, pageSetup follow hyperlinks and '
        'precede the x14 extLst', () {
      final XlsxWriter book = XlsxWriter();
      book.addSheet('S')
        ..row(<Object?>[XlsxHyperlink.location('S!A1'), 1])
        ..conditionalFormat(
          XlsxConditionalFormat(
            <XlsxRange>[XlsxRange.parse('B1:B5')],
            <XlsxConditionalRule>[XlsxDataBar(color: XlsxColor.hex('638EC6'))],
          ),
        )
        ..pageSetup(const XlsxPageSetup(scale: 90, centerHorizontally: true));
      final XlsxResult result = book.close();
      final String xml = readXlsx(result.bytes)[_sheet1]!;
      final List<int> at = <int>[
        xml.indexOf('<hyperlinks'),
        xml.indexOf('<printOptions'),
        xml.indexOf('<pageMargins'),
        xml.indexOf('<pageSetup'),
        xml.indexOf('<extLst>', xml.indexOf('<pageSetup')),
      ];
      expect(at, everyElement(greaterThan(-1)));
      for (int i = 1; i < at.length; i++) {
        expect(at[i - 1], lessThan(at[i]));
      }
      expect(xml, endsWith('</extLst></worksheet>'));
      expect(checkXlsx(result.bytes), isEmpty);
    });
  });

  group('value type', () {
    test('equal values are equal, with a hash and a description', () {
      expect(const XlsxPageSetup(scale: 80), const XlsxPageSetup(scale: 80));
      expect(
        const XlsxPageSetup(scale: 80).hashCode,
        const XlsxPageSetup(scale: 80).hashCode,
      );
      expect(
        const XlsxPageSetup(scale: 80),
        isNot(const XlsxPageSetup(scale: 81)),
      );
      expect(
        const XlsxPageSetup(margins: XlsxPageMargins(left: 1)),
        isNot(const XlsxPageSetup()),
      );
      expect(const XlsxPageMargins(), const XlsxPageMargins());
      expect(
        const XlsxPageMargins().hashCode,
        const XlsxPageMargins().hashCode,
      );
      expect(const XlsxPaperSize(9), XlsxPaperSize.a4);
      expect(const XlsxPaperSize(9).hashCode, XlsxPaperSize.a4.hashCode);
      expect(const XlsxPageSetup(scale: 80).toString(), contains('scale: 80'));
      expect(const XlsxPageMargins().toString(), contains('left: 0.7'));
      expect(XlsxPaperSize.a4.toString(), contains('9'));
    });
  });

  group('checks', () {
    test('scale together with a fit axis throws', () {
      expect(
        () => _setup(const XlsxPageSetup(scale: 80, fitToWidth: 1)),
        _argumentNamed('scale'),
      );
      expect(
        () => _setup(const XlsxPageSetup(scale: 80, fitToHeight: 1)),
        _argumentNamed('scale'),
      );
    });

    test('scale outside 10 to 400 throws; the bounds are allowed', () {
      expect(
        () => _setup(const XlsxPageSetup(scale: 9)),
        _argumentNamed('scale'),
      );
      expect(
        () => _setup(const XlsxPageSetup(scale: 401)),
        _argumentNamed('scale'),
      );
      expect(_setup(const XlsxPageSetup(scale: 10)), contains('scale="10"'));
      expect(_setup(const XlsxPageSetup(scale: 400)), contains('scale="400"'));
    });

    test('a fit axis outside 0 to 32767 throws', () {
      expect(
        () => _setup(const XlsxPageSetup(fitToWidth: -1)),
        _argumentNamed('fitToWidth'),
      );
      expect(
        () => _setup(const XlsxPageSetup(fitToHeight: 32768)),
        _argumentNamed('fitToHeight'),
      );
      expect(
        _setup(const XlsxPageSetup(fitToHeight: 32767)),
        contains('fitToHeight="32767"'),
      );
    });

    test('a first page number outside 1 to 32767 throws', () {
      expect(
        () => _setup(const XlsxPageSetup(firstPageNumber: 0)),
        _argumentNamed('firstPageNumber'),
      );
      expect(
        () => _setup(const XlsxPageSetup(firstPageNumber: 32768)),
        _argumentNamed('firstPageNumber'),
      );
    });

    test('a paper size outside 1 to 118 throws', () {
      expect(
        () => _setup(const XlsxPageSetup(paperSize: XlsxPaperSize(0))),
        _argumentNamed('paperSize'),
      );
      expect(
        () => _setup(const XlsxPageSetup(paperSize: XlsxPaperSize(119))),
        _argumentNamed('paperSize'),
      );
      expect(
        _setup(const XlsxPageSetup(paperSize: XlsxPaperSize(118))),
        contains('paperSize="118"'),
      );
    });

    test('a negative, NaN or infinite margin throws', () {
      final Map<String, XlsxPageMargins> bad = <String, XlsxPageMargins>{
        'margins.left': const XlsxPageMargins(left: -0.1),
        'margins.right': const XlsxPageMargins(right: double.nan),
        'margins.top': const XlsxPageMargins(top: double.infinity),
        'margins.bottom': const XlsxPageMargins(bottom: -1),
        'margins.header': const XlsxPageMargins(header: double.nan),
        'margins.footer': const XlsxPageMargins(footer: -2),
      };
      bad.forEach((String name, XlsxPageMargins margins) {
        expect(
          () => _setup(XlsxPageSetup(margins: margins)),
          _argumentNamed(name),
        );
      });
    });

    test('a call that throws records nothing and keeps the earlier one', () {
      final String xml = _sheet((XlsxSheetWriter s) {
        s.pageSetup(const XlsxPageSetup(scale: 50));
        expect(
          () => s.pageSetup(const XlsxPageSetup(scale: 5)),
          throwsArgumentError,
        );
      });
      expect(xml, contains('scale="50"'));
    });

    test('pageSetup on a finished sheet is a StateError', () {
      final XlsxWriter book = XlsxWriter();
      final XlsxSheetWriter sheet = book.addSheet('S')..row(<Object?>['x']);
      book.addSheet('T');
      expect(() => sheet.pageSetup(const XlsxPageSetup()), throwsStateError);
    });
  });
}
