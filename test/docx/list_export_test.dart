// The value semantics and argument checks of DocxListColumn and
// DocxListExport (milestone D6, Task 1). It imports the public library only,
// so it runs on the web as well.
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

const List<DocxListColumn> _two = <DocxListColumn>[
  DocxListColumn('Code'),
  DocxListColumn('Amount', numberFormat: '#,##0.00'),
];

/// The bytes of [document] as saved now.
Uint8List _saved(DocxDocument document) => document.save().bytes;

/// Expects [call] to throw an [ArgumentError] named [name].
void _throwsNamed(void Function() call, String name) {
  expect(
    call,
    throwsA(
      isA<ArgumentError>().having((ArgumentError e) => e.name, 'name', name),
    ),
  );
}

void main() {
  group('checks', () {
    void rejects(DocxListExport export, String name) {
      final DocxDocument doc = DocxDocument();
      final Uint8List before = _saved(doc);
      _throwsNamed(
        () => export.writeTo(doc, <List<Object?>>[
          <Object?>['A', 1],
        ]),
        name,
      );
      expect(_saved(doc), before, reason: 'writeTo changed the document');
      _throwsNamed(() => export.toDocx(<List<Object?>>[]), name);
    }

    test('no columns', () {
      rejects(DocxListExport(const <DocxListColumn>[]), 'columns');
    });

    test('an empty header', () {
      rejects(
        DocxListExport(const <DocxListColumn>[
          DocxListColumn('A'),
          DocxListColumn(''),
        ]),
        'columns[1].header',
      );
    });

    test('a header that repeats an earlier one ignoring case', () {
      rejects(
        DocxListExport(const <DocxListColumn>[
          DocxListColumn('Name'),
          DocxListColumn('name'),
        ]),
        'columns[1].header',
      );
    });

    for (final double width in <double>[0, -1, double.nan]) {
      test('a width of $width', () {
        rejects(
          DocxListExport(<DocxListColumn>[DocxListColumn('A', widthPt: width)]),
          'columns[0].widthPt',
        );
      });
    }

    test('an infinite width', () {
      rejects(
        DocxListExport(const <DocxListColumn>[
          DocxListColumn('A', widthPt: double.infinity),
        ]),
        'columns[0].widthPt',
      );
    });

    test('a number format that cannot be read', () {
      rejects(
        DocxListExport(const <DocxListColumn>[
          DocxListColumn('A', numberFormat: '0.00"'),
        ]),
        'columns[0].numberFormat',
      );
    });

    test('a logo height of 0', () {
      rejects(DocxListExport(_two, logoHeightPt: 0), 'logoHeightPt');
    });

    test('a logo height that is not finite', () {
      rejects(DocxListExport(_two, logoHeightPt: double.nan), 'logoHeightPt');
    });

    test('a header shading that is not six hex digits', () {
      rejects(DocxListExport(_two, headerShading: 'GGGGGG'), 'headerShading');
      rejects(DocxListExport(_two, headerShading: 'D9D9D'), 'headerShading');
      rejects(DocxListExport(_two, headerShading: '#D9D9D9'), 'headerShading');
    });

    test('too many columns', () {
      rejects(
        DocxListExport(<DocxListColumn>[
          for (int i = 0; i <= maxTableColumns; i++) DocxListColumn('C$i'),
        ]),
        'columns',
      );
    });

    test('a header shading in either case passes the checks', () {
      final DocxDocument doc = DocxDocument();
      for (final String? shading in <String?>['d9d9D9', 'D9D9D9', null]) {
        expect(
          () => DocxListExport(
            _two,
            headerShading: shading,
          ).writeTo(doc, <List<Object?>>[]),
          throwsUnimplementedError,
        );
      }
    });
  });

  group('DocxListColumn', () {
    test('keeps its fields', () {
      const DocxListColumn c = DocxListColumn(
        'Amount',
        widthPt: 60,
        numberFormat: '0.00',
        alignment: DocxAlignment.right,
      );
      expect(c.header, 'Amount');
      expect(c.widthPt, 60);
      expect(c.numberFormat, '0.00');
      expect(c.alignment, DocxAlignment.right);
      const DocxListColumn bare = DocxListColumn('A');
      expect(bare.widthPt, isNull);
      expect(bare.numberFormat, isNull);
      expect(bare.alignment, isNull);
    });

    test('== and hashCode cover every field', () {
      const DocxListColumn base = DocxListColumn(
        'A',
        widthPt: 10,
        numberFormat: '0',
        alignment: DocxAlignment.left,
      );
      const DocxListColumn same = DocxListColumn(
        'A',
        widthPt: 10,
        numberFormat: '0',
        alignment: DocxAlignment.left,
      );
      expect(base, same);
      expect(base.hashCode, same.hashCode);
      for (final DocxListColumn other in const <DocxListColumn>[
        DocxListColumn(
          'B',
          widthPt: 10,
          numberFormat: '0',
          alignment: DocxAlignment.left,
        ),
        DocxListColumn(
          'A',
          widthPt: 11,
          numberFormat: '0',
          alignment: DocxAlignment.left,
        ),
        DocxListColumn(
          'A',
          widthPt: 10,
          numberFormat: '0.0',
          alignment: DocxAlignment.left,
        ),
        DocxListColumn(
          'A',
          widthPt: 10,
          numberFormat: '0',
          alignment: DocxAlignment.right,
        ),
        DocxListColumn('A', numberFormat: '0', alignment: DocxAlignment.left),
      ]) {
        expect(base == other, isFalse, reason: '$other');
      }
      expect(base == Object(), isFalse);
    });

    test('toString names every field', () {
      expect(
        const DocxListColumn(
          'A',
          widthPt: 10,
          numberFormat: '0',
          alignment: DocxAlignment.left,
        ).toString(),
        'DocxListColumn(A, widthPt: 10.0, numberFormat: 0, '
        'alignment: DocxAlignment.left)',
      );
    });
  });

  group('DocxListExport', () {
    DocxListExport make({
      List<DocxListColumn> columns = _two,
      String? title = 'Report',
      OfficeImage? logo,
      double logoHeightPt = 28,
      DateTime? date,
      String? dateFormat,
      String? caption,
      DocxPageSize? pageSize,
      DocxPageMargins? margins,
      String footerBefore = 'Page ',
      String footerMiddle = ' of ',
      String footerAfter = '',
      FormatLocale locale = FormatLocale.enUS,
      String? headerShading = 'D9D9D9',
    }) => DocxListExport(
      columns,
      title: title,
      logo: logo,
      logoHeightPt: logoHeightPt,
      date: date,
      dateFormat: dateFormat,
      caption: caption,
      pageSize: pageSize,
      margins: margins,
      footerBefore: footerBefore,
      footerMiddle: footerMiddle,
      footerAfter: footerAfter,
      locale: locale,
      headerShading: headerShading,
    );

    test('has the documented defaults', () {
      final DocxListExport e = DocxListExport(_two);
      expect(e.columns, _two);
      expect(e.title, isNull);
      expect(e.logo, isNull);
      expect(e.logoHeightPt, 28);
      expect(e.date, isNull);
      expect(e.dateFormat, isNull);
      expect(e.caption, isNull);
      expect(e.pageSize, isNull);
      expect(e.margins, isNull);
      expect(e.footerBefore, 'Page ');
      expect(e.footerMiddle, ' of ');
      expect(e.footerAfter, '');
      expect(e.locale, FormatLocale.enUS);
      expect(e.headerShading, 'D9D9D9');
    });

    test('the columns are unmodifiable and copied', () {
      final List<DocxListColumn> given = <DocxListColumn>[..._two];
      final DocxListExport e = DocxListExport(given);
      given.clear();
      expect(e.columns, _two);
      expect(
        () => e.columns.add(const DocxListColumn('X')),
        throwsUnsupportedError,
      );
    });

    test('== and hashCode cover every field', () {
      final Uint8List png = Uint8List.fromList(<int>[1, 2, 3]);
      final DateTime day = DateTime(2026, 11, 8);
      final DocxPageSize size = DocxPageSize.letter();
      final DocxPageMargins margins = DocxPageMargins(
        top: 72,
        right: 72,
        bottom: 72,
        left: 72,
        header: 36,
        footer: 36,
        gutter: 0,
      );
      DocxListExport full() => make(
        logo: OfficeImage(png),
        date: day,
        dateFormat: 'dd.mm.yyyy',
        caption: 'Cap',
        pageSize: size,
        margins: margins,
      );
      expect(full(), full());
      expect(full().hashCode, full().hashCode);
      expect(make(), make());
      final List<DocxListExport> others = <DocxListExport>[
        make(
          columns: const <DocxListColumn>[DocxListColumn('Other')],
          logo: OfficeImage(png),
          date: day,
          dateFormat: 'dd.mm.yyyy',
          caption: 'Cap',
          pageSize: size,
          margins: margins,
        ),
        make(
          title: 'Other',
          logo: OfficeImage(png),
          date: day,
          dateFormat: 'dd.mm.yyyy',
          caption: 'Cap',
          pageSize: size,
          margins: margins,
        ),
        make(
          date: day,
          dateFormat: 'dd.mm.yyyy',
          caption: 'Cap',
          pageSize: size,
          margins: margins,
        ),
        make(
          logo: OfficeImage(png),
          logoHeightPt: 30,
          date: day,
          dateFormat: 'dd.mm.yyyy',
          caption: 'Cap',
          pageSize: size,
          margins: margins,
        ),
        make(
          logo: OfficeImage(png),
          date: DateTime(2026, 11, 9),
          dateFormat: 'dd.mm.yyyy',
          caption: 'Cap',
          pageSize: size,
          margins: margins,
        ),
        make(
          logo: OfficeImage(png),
          date: day,
          dateFormat: 'yyyy',
          caption: 'Cap',
          pageSize: size,
          margins: margins,
        ),
        make(
          logo: OfficeImage(png),
          date: day,
          dateFormat: 'dd.mm.yyyy',
          caption: 'Other',
          pageSize: size,
          margins: margins,
        ),
        make(
          logo: OfficeImage(png),
          date: day,
          dateFormat: 'dd.mm.yyyy',
          caption: 'Cap',
          pageSize: DocxPageSize.a4(),
          margins: margins,
        ),
        make(
          logo: OfficeImage(png),
          date: day,
          dateFormat: 'dd.mm.yyyy',
          caption: 'Cap',
          pageSize: size,
        ),
        make(
          logo: OfficeImage(png),
          date: day,
          dateFormat: 'dd.mm.yyyy',
          caption: 'Cap',
          pageSize: size,
          margins: margins,
          footerBefore: 'P ',
        ),
        make(
          logo: OfficeImage(png),
          date: day,
          dateFormat: 'dd.mm.yyyy',
          caption: 'Cap',
          pageSize: size,
          margins: margins,
          footerMiddle: ' / ',
        ),
        make(
          logo: OfficeImage(png),
          date: day,
          dateFormat: 'dd.mm.yyyy',
          caption: 'Cap',
          pageSize: size,
          margins: margins,
          footerAfter: '.',
        ),
        make(
          logo: OfficeImage(png),
          date: day,
          dateFormat: 'dd.mm.yyyy',
          caption: 'Cap',
          pageSize: size,
          margins: margins,
          locale: FormatLocale.trTR,
        ),
        make(
          logo: OfficeImage(png),
          date: day,
          dateFormat: 'dd.mm.yyyy',
          caption: 'Cap',
          pageSize: size,
          margins: margins,
          headerShading: null,
        ),
      ];
      for (int i = 0; i < others.length; i++) {
        expect(full() == others[i], isFalse, reason: 'variant $i');
      }
      expect(full() == Object(), isFalse);
    });

    test('toString names every field', () {
      final String text = make(
        date: DateTime(2026, 11, 8),
        caption: 'Cap',
      ).toString();
      for (final String part in <String>[
        'DocxListExport(',
        'DocxListColumn(Code',
        'title: Report',
        'logo: null',
        'logoHeightPt: 28.0',
        'date: 2026-11-08',
        'dateFormat: null',
        'caption: Cap',
        'pageSize: null',
        'margins: null',
        'footerBefore: Page ',
        'footerMiddle:  of ',
        'footerAfter: ',
        'locale: ',
        'headerShading: D9D9D9',
      ]) {
        expect(text, contains(part));
      }
    });

    test('writeTo and toDocx run the checks, then are not yet written', () {
      final DocxListExport e = DocxListExport(_two);
      expect(
        () => e.writeTo(DocxDocument(), <List<Object?>>[]),
        throwsUnimplementedError,
      );
      expect(() => e.toDocx(<List<Object?>>[]), throwsUnimplementedError);
    });
  });
}
