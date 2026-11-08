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
          returnsNormally,
        );
      }
    });

    test('headers that differ only in Turkish case clash', () {
      rejects(
        DocxListExport(const <DocxListColumn>[
          DocxListColumn('liste'),
          DocxListColumn('L\u0130STE'),
        ]),
        'columns[1].header',
      );
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
  });

  group('values', () {
    /// The tables of [document]'s body.
    List<DocxTable> tables(DocxDocument document) =>
        document.body.blocks.whereType<DocxTable>().toList();

    /// The cell texts of every row of the one table [export] writes.
    List<List<String>> written(
      DocxListExport export,
      List<List<Object?>> rows, {
      List<Object?>? totals,
    }) {
      final DocxDocument doc = DocxDocument();
      export.writeTo(doc, rows, totals: totals);
      final List<DocxTable> t = tables(doc);
      expect(t, hasLength(1));
      return <List<String>>[
        for (final DocxTableRow r in t.single.rows)
          <String>[for (final DocxTableCell c in r.cells) c.text],
      ];
    }

    final FormatDecimal decimal = FormatDecimal('1234.5');

    test('a header row, the data rows and a totals row', () {
      expect(
        written(
          DocxListExport(_two),
          <List<Object?>>[
            <Object?>['A', 1],
            <Object?>['B', 2.5],
          ],
          totals: <Object?>['Total', 3.5],
        ),
        <List<String>>[
          <String>['Code', 'Amount'],
          <String>['A', '1.00'],
          <String>['B', '2.50'],
          <String>['Total', '3.50'],
        ],
      );
    });

    test('the header row repeats and the table has equal columns', () {
      final DocxDocument doc = DocxDocument();
      DocxListExport(_two).writeTo(doc, <List<Object?>>[
        <Object?>['A', 1],
      ]);
      final DocxTable table = tables(doc).single;
      expect(table.rows.first.properties.repeatAsHeader, isTrue);
      expect(table.rows.last.properties.repeatAsHeader, isNot(isTrue));
      expect(table.rows, hasLength(2));
    });

    test('a short row leaves its last cells empty', () {
      expect(
        written(DocxListExport(_two), <List<Object?>>[
          <Object?>['A'],
        ]).last,
        <String>['A', ''],
      );
    });

    test('a number with a code in tr-TR', () {
      final DocxListExport e = DocxListExport(_two, locale: FormatLocale.trTR);
      expect(
        written(e, <List<Object?>>[
          <Object?>['x', decimal],
          <Object?>['y', 1234.5],
        ]).skip(1).map((List<String> r) => r[1]),
        <String>['1.234,50', '1.234,50'],
      );
    });

    test('the same decimal in en-US reads as the formatter gives it', () {
      final List<List<String>> out = written(
        DocxListExport(_two),
        <List<Object?>>[
          <Object?>['x', decimal],
        ],
      );
      expect(out.last[1], '1,234.50');
      expect(
        out.last[1],
        NumberFormatter().format(decimal, numberFormat: '#,##0.00').text,
      );
    });

    test('General without a code, and a boolean in tr-TR', () {
      final DocxListExport e = DocxListExport(const <DocxListColumn>[
        DocxListColumn('A'),
        DocxListColumn('B'),
      ], locale: FormatLocale.trTR);
      final List<String> row = written(e, <List<Object?>>[
        <Object?>[12, true],
      ]).last;
      expect(row[0], '12');
      expect(row[1], 'DO\u011eRU');
      expect(
        row[1],
        NumberFormatter(locale: FormatLocale.trTR).format(true).text,
      );
    });

    test('a date without a code is the locale short date', () {
      final DocxListExport e = DocxListExport(const <DocxListColumn>[
        DocxListColumn('D'),
      ], locale: FormatLocale.trTR);
      final String text = written(e, <List<Object?>>[
        <Object?>[DateTime(2026, 11, 8)],
      ]).last.single;
      expect(text, '08.11.2026');
      expect(
        text,
        NumberFormatter(
          locale: FormatLocale.trTR,
        ).format(DateTime(2026, 11, 8), numberFormatId: 14).text,
      );
    });

    test('a date with a code', () {
      final DocxListExport e = DocxListExport(const <DocxListColumn>[
        DocxListColumn('D', numberFormat: 'd mmmm yyyy'),
      ], locale: FormatLocale.trTR);
      final String text = written(e, <List<Object?>>[
        <Object?>[DateTime(2026, 11, 8)],
      ]).last.single;
      expect(
        text,
        NumberFormatter(
          locale: FormatLocale.trTR,
        ).format(DateTime(2026, 11, 8), numberFormat: 'd mmmm yyyy').text,
      );
      expect(text, '8 Kas\u0131m 2026');
    });

    test('a duration with a code', () {
      final DocxListExport e = DocxListExport(const <DocxListColumn>[
        DocxListColumn('T', numberFormat: '[h]:mm'),
      ]);
      expect(
        written(e, <List<Object?>>[
          <Object?>[const Duration(hours: 26, minutes: 5)],
        ]).last.single,
        '26:05',
      );
    });

    test('a string with a tab holds a DocxTab', () {
      final DocxDocument doc = DocxDocument();
      DocxListExport(_two).writeTo(doc, <List<Object?>>[
        <Object?>['a\tb', null],
      ]);
      final DocxTableCell cell = tables(doc).single.rows.last.cells.first;
      final DocxParagraph p = cell.blocks.whereType<DocxParagraph>().first;
      final List<DocxRunContent> contents = <DocxRunContent>[
        for (final DocxInline i in p.inlines)
          if (i is DocxRun) ...i.content,
      ];
      expect(contents.whereType<DocxTab>(), hasLength(1));
      expect(cell.text, 'a\tb');
    });

    test('null is an empty cell', () {
      expect(
        written(DocxListExport(_two), <List<Object?>>[
          <Object?>[null, null],
        ]).last,
        <String>['', ''],
      );
    });

    test('a value of another type is named', () {
      final DocxDocument doc = DocxDocument();
      _throwsNamed(
        () => DocxListExport(_two).writeTo(doc, <List<Object?>>[
          <Object?>['A', Uri.parse('https://example.com')],
        ]),
        'rows[0][1]',
      );
    });

    test('a row longer than the columns is named and earlier rows stay', () {
      final DocxDocument doc = DocxDocument();
      _throwsNamed(
        () => DocxListExport(_two).writeTo(doc, <List<Object?>>[
          <Object?>['A', 1],
          <Object?>['B', 2],
          <Object?>['C', 3, 4],
        ]),
        'rows[2]',
      );
      expect(tables(doc).single.rows, hasLength(3));
    });

    test('totals are checked before anything is written', () {
      for (final (List<Object?>, String) c in <(List<Object?>, String)>[
        (<Object?>[Uri.parse('https://example.com')], 'totals[0]'),
        (<Object?>['a', 1, 2], 'totals'),
      ]) {
        final DocxDocument doc = DocxDocument();
        final Uint8List before = _saved(doc);
        _throwsNamed(
          () => DocxListExport(_two).writeTo(doc, <List<Object?>>[
            <Object?>['A', 1],
          ], totals: c.$1),
          c.$2,
        );
        expect(_saved(doc), before);
        _throwsNamed(
          () => DocxListExport(_two).toDocx(<List<Object?>>[
            <Object?>['A', 1],
          ], totals: c.$1),
          c.$2,
        );
      }
    });

    test('toDocx saves a document that reads back, with its properties', () {
      final DocxResult out = DocxListExport(_two).toDocx(
        <List<Object?>>[
          <Object?>['A', 1],
        ],
        totals: <Object?>['Total', 1],
        properties: const OfficeProperties(title: 'Accounts'),
      );
      final DocxDocument back = DocxDocument.open(out.bytes);
      expect(tables(back).single.rows, hasLength(3));
      expect(back.properties.title, 'Accounts');
    });
  });
}
