// Tests of DocxListColumn and DocxListExport (milestone D6): the value
// semantics and argument checks, the page, header and footer written into a
// section, the values as Excel shows them, and the body. It runs on the web
// as well; the package:archive and tool/src imports below only read the
// saved bytes.
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

import '../../tool/src/part_compare.dart';
import '../fixtures/docx_fixtures.dart';

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

/// The first 33 bytes of a PNG of [width] by [height] pixels: its signature
/// and the start of its `IHDR`, which is all the model reads of it.
Uint8List _pngOfSize(int width, int height) {
  int byte(int value, int shift) => (value >> shift) & 0xFF;
  return Uint8List.fromList(<int>[
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
    0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52, //
    byte(width, 24), byte(width, 16), byte(width, 8), byte(width, 0), //
    byte(height, 24), byte(height, 16), byte(height, 8), byte(height, 0), //
    8, 2, 0, 0, 0, 0, 0, 0, 0, //
  ]);
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

    test('a date format that cannot be read', () {
      rejects(
        DocxListExport(_two, date: DateTime(2026, 11, 8), dateFormat: '[Red'),
        'dateFormat',
      );
      rejects(DocxListExport(_two, dateFormat: '0.00"'), 'dateFormat');
    });

    test('a date format that can be read passes the checks', () {
      final DocxDocument doc = DocxDocument();
      DocxListExport(
        _two,
        date: DateTime(2026, 11, 8),
        dateFormat: 'yyyy-mm-dd',
      ).writeTo(doc, <List<Object?>>[]);
      expect(
        (doc.sections.last.header.blocks.single as DocxParagraph).text,
        '\t\t2026-11-08',
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

  group('page', () {
    DocxSection last(DocxDocument d) => d.sections.last;

    DocxDocument written(DocxListExport e, [DocxDocument? into]) {
      final DocxDocument doc = into ?? DocxDocument();
      e.writeTo(doc, <List<Object?>>[
        <Object?>['A', 1],
      ]);
      return doc;
    }

    /// The paragraph of the section's header, which must be its only block.
    DocxParagraph headerParagraph(DocxSection section) {
      expect(section.header.blocks, hasLength(1));
      return section.header.blocks.single as DocxParagraph;
    }

    List<String> runTexts(DocxParagraph p) => <String>[
      for (final DocxInline i in p.inlines) i.text,
    ];

    test('the defaults are A4 portrait and Word\'s blank margins', () {
      final DocxSection s = last(written(DocxListExport(_two)));
      expect(s.pageSize, DocxPageSize.a4());
      final DocxPageMargins m = s.margins!;
      expect(m.topPt, 70.85);
      expect(m.rightPt, 70.85);
      expect(m.bottomPt, 70.85);
      expect(m.leftPt, 70.85);
      expect(m.headerPt, 35.4);
      expect(m.footerPt, 35.4);
      expect(m.gutterPt, 0);
    });

    test('a given page size and margins are set as given', () {
      final DocxPageMargins margins = DocxPageMargins(
        top: 36,
        right: 40,
        bottom: 36,
        left: 40,
        header: 18,
        footer: 18,
        gutter: 2,
      );
      final DocxSection s = last(
        written(
          DocxListExport(
            _two,
            pageSize: DocxPageSize.a4(landscape: true),
            margins: margins,
          ),
        ),
      );
      expect(s.pageSize, DocxPageSize.a4(landscape: true));
      expect(s.margins, margins);
    });

    test('the header holds the logo, a tab, the title, a tab and the date', () {
      final DocxSection s = last(
        written(
          DocxListExport(
            _two,
            logo: OfficeImage(_pngOfSize(100, 50)),
            logoHeightPt: 30,
            title: 'Accounts',
            date: DateTime(2026, 11, 8),
            dateFormat: 'dd.mm.yyyy',
          ),
        ),
      );
      final DocxParagraph p = headerParagraph(s);
      expect(runTexts(p), <String>['', '\t', 'Accounts', '\t', '08.11.2026']);
      expect(p.text, '\tAccounts\t08.11.2026');
      final DocxPicture pic =
          (p.inlines.first as DocxRun).content.single as DocxPicture;
      expect(pic.heightPt, 30);
      expect(pic.widthPt, 60);
      expect((p.inlines[2] as DocxRun).properties.bold, isTrue);
      final double width = s.textWidthPt!;
      expect(p.properties.tabs, <DocxTabStop>[
        DocxTabStop(width / 2, alignment: DocxTabAlignment.center),
        DocxTabStop(width, alignment: DocxTabAlignment.right),
      ]);
    });

    test('the tab stops follow the text width of the page', () {
      final DocxSection s = last(
        written(
          DocxListExport(
            _two,
            pageSize: DocxPageSize.a4(landscape: true),
            title: 'T',
          ),
        ),
      );
      final double width = s.textWidthPt!;
      expect(width, greaterThan(700));
      expect(headerParagraph(s).properties.tabs, <DocxTabStop>[
        DocxTabStop(width / 2, alignment: DocxTabAlignment.center),
        DocxTabStop(width, alignment: DocxTabAlignment.right),
      ]);
    });

    test('absent pieces leave their tabs', () {
      DocxParagraph of(DocxListExport e) => headerParagraph(last(written(e)));
      expect(runTexts(of(DocxListExport(_two, title: 'T'))), <String>[
        '\t',
        'T',
      ]);
      expect(
        runTexts(
          of(DocxListExport(_two, title: null, date: DateTime(2026, 11, 8))),
        ),
        <String>['\t', '\t', '11/8/26'],
      );
      expect(
        runTexts(
          of(
            DocxListExport(
              _two,
              title: 'T',
              logo: OfficeImage(_pngOfSize(10, 10)),
            ),
          ),
        ),
        <String>['', '\t', 'T'],
      );
      expect(
        runTexts(
          of(
            DocxListExport(
              _two,
              title: null,
              logo: OfficeImage(_pngOfSize(10, 10)),
              date: DateTime(2026, 11, 8),
            ),
          ),
        ),
        <String>['', '\t', '\t', '11/8/26'],
      );
    });

    test('the date shows in the locale\'s short date without a code', () {
      final DocxSection s = last(
        written(
          DocxListExport(
            _two,
            title: null,
            date: DateTime(2026, 11, 8),
            locale: FormatLocale.trTR,
          ),
        ),
      );
      expect(headerParagraph(s).text, '\t\t08.11.2026');
    });

    test('with no logo, title or date there is no own header', () {
      final DocxDocument doc = written(DocxListExport(_two, title: null));
      expect(last(doc).header.isInherited, isFalse);
      expect(last(doc).header.blocks, isEmpty);
      final Set<String> parts = <String>{
        for (final ArchiveFile f in ZipDecoder().decodeBytes(_saved(doc)).files)
          f.name,
      };
      expect(parts.where((String n) => n.contains('header')), isEmpty);
      expect(parts.where((String n) => n.contains('footer')), hasLength(1));
    });

    test('the footer is centred: Page, PAGE, of, NUMPAGES', () {
      final DocxSection s = last(written(DocxListExport(_two)));
      expect(s.footer.blocks, hasLength(1));
      final DocxParagraph p = s.footer.blocks.single as DocxParagraph;
      expect(p.properties.alignment, DocxAlignment.center);
      expect(p.inlines, hasLength(4));
      expect((p.inlines[0] as DocxRun).text, 'Page ');
      expect((p.inlines[1] as DocxField).instruction.trim(), 'PAGE');
      expect((p.inlines[2] as DocxRun).text, ' of ');
      expect((p.inlines[3] as DocxField).instruction.trim(), 'NUMPAGES');
      expect(p.text, 'Page 1 of 1');
    });

    test('footer texts are replaced and empty ones left out', () {
      final DocxSection s = last(
        written(
          DocxListExport(_two, footerBefore: 'Sayfa ', footerMiddle: ' / '),
        ),
      );
      expect((s.footer.blocks.single as DocxParagraph).text, 'Sayfa 1 / 1');
      final DocxSection bare = last(
        written(
          DocxListExport(
            _two,
            footerBefore: '',
            footerMiddle: '',
            footerAfter: '',
          ),
        ),
      );
      final DocxParagraph p = bare.footer.blocks.single as DocxParagraph;
      expect(p.inlines.whereType<DocxRun>(), isEmpty);
      expect(p.text, '11');
      final DocxSection after = last(
        written(DocxListExport(_two, footerAfter: ' pages')),
      );
      expect(
        (after.footer.blocks.single as DocxParagraph).text,
        'Page 1 of 1 pages',
      );
    });

    group('in an opened document', () {
      /// A document of two sections whose both have their own header and
      /// footer, and whose last has a title page.
      DocxDocument twoSections() {
        final DocxDocument doc = DocxDocument();
        doc.body.addParagraph('first');
        final DocxSection one = doc.sections.last;
        one.ownHeader(DocxHeaderFooterType.primary).addParagraph('H1');
        one.ownFooter(DocxHeaderFooterType.primary).addParagraph('F1');
        doc.body.addSection();
        final DocxSection two = doc.sections.last;
        two.ownHeader(DocxHeaderFooterType.primary).addParagraph('H2');
        two.ownFooter(DocxHeaderFooterType.primary).addParagraph('F2');
        two.ownHeader(DocxHeaderFooterType.first).addParagraph('First page');
        expect(two.titlePage, isTrue);
        return DocxDocument.open(doc.save().bytes);
      }

      test('the last section\'s header and footer are replaced', () {
        final DocxDocument doc = twoSections();
        written(DocxListExport(_two, title: 'List'), doc);
        final DocxSection one = doc.sections.first;
        final DocxSection two = doc.sections.last;
        expect(one.header.blocks.single, isA<DocxParagraph>());
        expect((one.header.blocks.single as DocxParagraph).text, 'H1');
        expect((one.footer.blocks.single as DocxParagraph).text, 'F1');
        expect(headerParagraph(two).text, '\tList');
        expect(two.footer.blocks, hasLength(1));
        expect((two.footer.blocks.single as DocxParagraph).text, 'Page 1 of 1');
      });

      test('a section of several columns is set to one', () {
        final DocxDocument doc = twoSections();
        doc.sections.last.columns = DocxColumns(
          count: 3,
          spacingPt: 20,
          separator: true,
        );
        written(DocxListExport(_two), doc);
        expect(doc.sections.last.columns, DocxColumns(spacingPt: 20));
        expect(
          DocxDocument.open(doc.save().bytes).sections.last.columns?.count,
          1,
        );
      });

      test('a section of unequal columns is set to one', () {
        final DocxDocument doc = twoSections();
        doc.sections.last.columns = DocxColumns(
          widths: <DocxColumn>[DocxColumn(100, spacingPt: 10), DocxColumn(200)],
        );
        written(DocxListExport(_two), doc);
        expect(doc.sections.last.columns?.count, 1);
        expect(doc.sections.last.columns?.widths, isNull);
      });

      test('one column, or none, stays as it is', () {
        final DocxDocument doc = twoSections();
        doc.sections.last.columns = DocxColumns(spacingPt: 12, separator: true);
        written(DocxListExport(_two), doc);
        expect(
          doc.sections.last.columns,
          DocxColumns(spacingPt: 12, separator: true),
        );
        final DocxDocument none = DocxDocument();
        none.sections.last.columns = null;
        written(DocxListExport(_two), none);
        expect(none.sections.last.columns, isNull);
      });

      test('a title page is turned off so page 1 shows the header', () {
        final DocxDocument doc = twoSections();
        written(DocxListExport(_two, title: 'List'), doc);
        expect(doc.sections.last.titlePage, isFalse);
        final DocxDocument back = DocxDocument.open(doc.save().bytes);
        expect(back.sections.last.titlePage, isFalse);
      });

      test('a title page is turned off with no header to write too', () {
        final DocxDocument doc = twoSections();
        written(DocxListExport(_two, title: null, logo: null, date: null), doc);
        expect(doc.sections.last.titlePage, isFalse);
        expect(
          DocxDocument.open(doc.save().bytes).sections.last.titlePage,
          isFalse,
        );
      });

      test('with nothing for the header the section\'s own is dropped', () {
        final DocxDocument doc = twoSections();
        written(DocxListExport(_two, title: null), doc);
        final DocxSection two = doc.sections.last;
        expect(two.header.isInherited, isTrue);
        expect((two.header.blocks.single as DocxParagraph).text, 'H1');
      });

      /// [twoSections] with its last section's own even header and footer,
      /// and odd and even headers [on].
      DocxDocument withEven({required bool on}) {
        final DocxDocument doc = twoSections();
        doc.sections.last.ownHeader(DocxHeaderFooterType.even)
          ..addParagraph('Even header')
          ..addParagraph('Second');
        doc.sections.last
            .ownFooter(DocxHeaderFooterType.even)
            .addParagraph('Even footer');
        doc.evenAndOddHeaders = on;
        return DocxDocument.open(doc.save().bytes);
      }

      test('with odd and even headers the even stories are replaced too', () {
        final DocxDocument doc = withEven(on: true);
        written(DocxListExport(_two, title: 'List'), doc);
        final DocxSection two = doc.sections.last;
        expect(two.evenHeader.blocks, hasLength(1));
        expect((two.evenHeader.blocks.single as DocxParagraph).text, '\tList');
        expect(two.evenFooter.blocks, hasLength(1));
        expect(
          (two.evenFooter.blocks.single as DocxParagraph).text,
          'Page 1 of 1',
        );
        final DocxDocument back = DocxDocument.open(doc.save().bytes);
        expect(
          (back.sections.last.evenHeader.blocks.single as DocxParagraph).text,
          '\tList',
        );
        expect(back.evenAndOddHeaders, isTrue);
      });

      test('with nothing for the header the own even header is dropped', () {
        final DocxDocument doc = withEven(on: true);
        written(DocxListExport(_two, title: null), doc);
        final DocxSection two = doc.sections.last;
        expect(two.evenHeader.blocks, isEmpty);
        expect(
          two.evenFooter.blocks.map((DocxBlock b) => (b as DocxParagraph).text),
          <String>['Page 1 of 1'],
        );
      });

      test('without odd and even headers the even stories stay', () {
        final DocxDocument doc = withEven(on: false);
        written(DocxListExport(_two, title: 'List'), doc);
        final DocxSection two = doc.sections.last;
        expect(two.evenHeader.blocks, hasLength(2));
        expect(
          (two.evenHeader.blocks.first as DocxParagraph).text,
          'Even header',
        );
        expect(
          (two.evenFooter.blocks.single as DocxParagraph).text,
          'Even footer',
        );
      });
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

    test('a bad row is named and the document does not change', () {
      for (final (List<List<Object?>>, String) c
          in <(List<List<Object?>>, String)>[
            (
              <List<Object?>>[
                <Object?>['A', 1],
                <Object?>['B', 2],
                <Object?>['C', 3, 4],
              ],
              'rows[2]',
            ),
            (
              <List<Object?>>[
                <Object?>['A', 1],
                <Object?>['B', Uri.parse('https://example.com')],
              ],
              'rows[1][1]',
            ),
          ]) {
        final DocxDocument doc = DocxDocument();
        final Uint8List before = _saved(doc);
        _throwsNamed(() => DocxListExport(_two).writeTo(doc, c.$1), c.$2);
        expect(_saved(doc), before);
        expect(doc.body.blocks.whereType<DocxTable>(), isEmpty);
      }
    });

    test('rows are read once', () {
      int reads = 0;
      Iterable<List<Object?>> rows() sync* {
        reads++;
        yield <Object?>['A', 1];
        yield <Object?>['B', 2];
      }

      final DocxDocument doc = DocxDocument();
      DocxListExport(_two).writeTo(doc, rows());
      expect(reads, 1);
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
    test('toDocx with default properties saves no docProps part', () {
      final DocxResult out = DocxListExport(_two).toDocx(<List<Object?>>[
        <Object?>['A', 1],
      ]);
      final List<String> names = <String>[
        for (final ArchiveFile f in ZipDecoder().decodeBytes(out.bytes).files)
          f.name,
      ];
      expect(names.where((String n) => n.startsWith('docProps')), isEmpty);
    });
  });

  group('body', () {
    final List<List<Object?>> three = <List<Object?>>[
      <Object?>['A', 1],
      <Object?>['B', 2],
      <Object?>['C', 3],
    ];

    DocxTable tableOf(DocxDocument d) =>
        d.body.blocks.whereType<DocxTable>().single;

    List<DocxRun> runsOf(DocxTableCell c) => <DocxRun>[
      for (final DocxBlock b in c.blocks)
        if (b is DocxParagraph) ...b.inlines.whereType<DocxRun>(),
    ];

    DocxAlignment? alignOf(DocxTableCell c) =>
        (c.blocks.first as DocxParagraph).properties.alignment;

    bool isBlank(DocxBlock b) =>
        b is DocxParagraph && b.inlines.isEmpty && b.section == null;

    test('a caption, the table and one empty paragraph, no leading one', () {
      final DocxDocument doc = DocxDocument();
      DocxListExport(_two, caption: 'Accounts').writeTo(doc, three);
      final List<DocxBlock> blocks = doc.body.blocks;
      expect(blocks, hasLength(3));
      final DocxParagraph caption = blocks[0] as DocxParagraph;
      expect(caption.text, 'Accounts');
      expect(caption.inlines, hasLength(1));
      final DocxRun run = caption.inlines.single as DocxRun;
      expect(run.properties.bold, isTrue);
      expect(run.properties.sizePt, 14);
      expect(blocks[1], isA<DocxTable>());
      expect(isBlank(blocks[2]), isTrue);
    });

    test('without a caption the table comes first', () {
      final DocxDocument doc = DocxDocument();
      DocxListExport(_two).writeTo(doc, three);
      expect(doc.body.blocks, hasLength(2));
      expect(doc.body.blocks.first, isA<DocxTable>());
      expect(isBlank(doc.body.blocks.last), isTrue);
    });

    test('a body ending in a paragraph with a section break keeps it', () {
      final DocxDocument doc = DocxDocument();
      doc.body.addSection();
      final int before = doc.body.blocks.length;
      DocxListExport(_two).writeTo(doc, three);
      expect(doc.body.blocks.length, before + 2);
    });

    test('the grid has the given widths and shares the rest equally', () {
      final DocxDocument doc = DocxDocument();
      DocxListExport(const <DocxListColumn>[
        DocxListColumn('A', widthPt: 100),
        DocxListColumn('B'),
        DocxListColumn('C'),
      ]).writeTo(doc, three);
      final double text = doc.sections.last.textWidthPt!;
      final List<double?> grid = tableOf(doc).gridColumnsPt!;
      expect(grid, hasLength(3));
      expect(grid[0], 100);
      expect(grid[1], closeTo((text - 100) / 2, 0.1));
      expect(grid[2], closeTo((text - 100) / 2, 0.1));
    });

    test('all widths null share the text width', () {
      final DocxDocument doc = DocxDocument();
      DocxListExport(_two).writeTo(doc, three);
      final double text = doc.sections.last.textWidthPt!;
      for (final double? w in tableOf(doc).gridColumnsPt!) {
        expect(w, closeTo(text / 2, 0.1));
      }
    });

    test('the widths follow the page the list sets', () {
      final DocxDocument doc = DocxDocument();
      DocxListExport(
        _two,
        pageSize: DocxPageSize.a4(landscape: true),
      ).writeTo(doc, three);
      final double text = doc.sections.last.textWidthPt!;
      expect(tableOf(doc).gridColumnsPt!.first, closeTo(text / 2, 0.1));
    });

    test('widths that leave nothing throw before the document changes', () {
      final DocxDocument doc = DocxDocument();
      final Uint8List before = _saved(doc);
      const List<DocxListColumn> cols = <DocxListColumn>[
        DocxListColumn('A', widthPt: 453),
        DocxListColumn('B'),
      ];
      _throwsNamed(() => DocxListExport(cols).writeTo(doc, three), 'columns');
      expect(_saved(doc), before);
      _throwsNamed(() => DocxListExport(cols).toDocx(three), 'columns');
    });

    test('the check uses the page the list sets', () {
      final DocxDocument doc = DocxDocument();
      // 400 leaves 53.6 pt on A4 portrait but nothing on a narrow page.
      _throwsNamed(
        () => DocxListExport(const <DocxListColumn>[
          DocxListColumn('A', widthPt: 400),
          DocxListColumn('B'),
        ], pageSize: DocxPageSize(450, 600)).writeTo(doc, three),
        'columns',
      );
    });

    test('every width given is written as given, even past the page', () {
      final DocxDocument doc = DocxDocument();
      DocxListExport(const <DocxListColumn>[
        DocxListColumn('A', widthPt: 400),
        DocxListColumn('B', widthPt: 300),
      ]).writeTo(doc, three);
      expect(tableOf(doc).gridColumnsPt, <double?>[400, 300]);
    });

    test('the header row repeats, holds bold runs and is shaded', () {
      final DocxDocument doc = DocxDocument();
      DocxListExport(_two).writeTo(doc, three);
      final DocxTableRow row = tableOf(doc).rows.first;
      expect(row.properties.repeatAsHeader, isTrue);
      expect(row.properties.cantSplit, isTrue);
      for (final DocxTableCell c in row.cells) {
        expect(runsOf(c).single.properties.bold, isTrue);
        final DocxShading shading = c.properties.shading!;
        expect(shading.pattern, DocxShadingPattern.clear);
        expect(shading.fill, DocxColor.rgb('D9D9D9'));
      }
      for (final DocxTableCell c in tableOf(doc).rows[1].cells) {
        expect(c.properties.shading, isNull);
        expect(runsOf(c).single.properties.bold, isNot(isTrue));
      }
    });

    test('headerShading null leaves the header unshaded', () {
      final DocxDocument doc = DocxDocument();
      DocxListExport(_two, headerShading: null).writeTo(doc, three);
      for (final DocxTableCell c in tableOf(doc).rows.first.cells) {
        expect(c.properties.shading, isNull);
        expect(runsOf(c).single.properties.bold, isTrue);
      }
    });

    test('headerShading in lower case is stored as RGB', () {
      final DocxDocument doc = DocxDocument();
      DocxListExport(_two, headerShading: 'ff8800').writeTo(doc, three);
      expect(
        tableOf(doc).rows.first.cells.first.properties.shading!.fill,
        DocxColor.rgb('FF8800'),
      );
    });

    test('a number format aligns to the end, header and cells', () {
      final DocxDocument doc = DocxDocument();
      DocxListExport(_two).writeTo(doc, three, totals: <Object?>['T', 6]);
      for (final DocxTableRow r in tableOf(doc).rows) {
        expect(alignOf(r.cells[0]), isNull);
        expect(alignOf(r.cells[1]), DocxAlignment.end);
      }
    });

    test('a column alignment wins, header and totals too', () {
      final DocxDocument doc = DocxDocument();
      DocxListExport(const <DocxListColumn>[
        DocxListColumn('A', alignment: DocxAlignment.center),
        DocxListColumn('B', numberFormat: '0', alignment: DocxAlignment.left),
      ]).writeTo(doc, three, totals: <Object?>['T', 6]);
      for (final DocxTableRow r in tableOf(doc).rows) {
        expect(alignOf(r.cells[0]), DocxAlignment.center);
        expect(alignOf(r.cells[1]), DocxAlignment.left);
      }
    });

    test('the totals row is last and bold, without shading', () {
      final DocxDocument doc = DocxDocument();
      DocxListExport(_two).writeTo(doc, three, totals: <Object?>['T', 6]);
      final DocxTableRow row = tableOf(doc).rows.last;
      expect(row.cells.map((DocxTableCell c) => c.text), <String>['T', '6.00']);
      for (final DocxTableCell c in row.cells) {
        expect(runsOf(c).single.properties.bold, isTrue);
        expect(c.properties.shading, isNull);
      }
      expect(row.properties.repeatAsHeader, isNot(isTrue));
    });

    test('no rows: the header and totals rows only', () {
      final DocxDocument doc = DocxDocument();
      DocxListExport(
        _two,
      ).writeTo(doc, const <List<Object?>>[], totals: <Object?>['T', 0]);
      expect(tableOf(doc).rows, hasLength(2));
    });

    test('an empty cell has no run to make bold', () {
      final DocxDocument doc = DocxDocument();
      DocxListExport(
        _two,
      ).writeTo(doc, const <List<Object?>>[], totals: <Object?>['T']);
      expect(tableOf(doc).rows.last.cells[1].text, '');
    });

    test('writing twice gives two tables with a paragraph between', () {
      final DocxDocument doc = DocxDocument();
      DocxListExport(_two).writeTo(doc, three);
      DocxListExport(_two).writeTo(doc, three);
      final List<DocxBlock> b = doc.body.blocks;
      expect(b, hasLength(4));
      expect(b[0], isA<DocxTable>());
      expect(isBlank(b[1]), isTrue);
      expect(b[2], isA<DocxTable>());
      expect(isBlank(b[3]), isTrue);
    });

    test('a second caption stands after the separating paragraph', () {
      final DocxDocument doc = DocxDocument();
      DocxListExport(_two).writeTo(doc, three);
      DocxListExport(_two, caption: 'Again').writeTo(doc, three);
      final List<DocxBlock> b = doc.body.blocks;
      expect(b, hasLength(5));
      expect(isBlank(b[1]), isTrue);
      expect((b[2] as DocxParagraph).text, 'Again');
    });

    test('a letter before the list stays', () {
      final DocxDocument doc = DocxDocument();
      doc.body.addParagraph().addRun('Letter');
      DocxListExport(_two).writeTo(doc, three);
      final List<DocxBlock> b = doc.body.blocks;
      expect(b.whereType<DocxTable>(), hasLength(1));
      expect(
        b.any((DocxBlock x) => x is DocxParagraph && x.text == 'Letter'),
        isTrue,
      );
      expect(isBlank(b.last), isTrue);
    });

    test('the saved bytes open without warnings and round trip', () {
      final DocxResult out = DocxListExport(
        _two,
        title: 'T',
        caption: 'Caption',
      ).toDocx(three, totals: <Object?>['Total', 6]);
      expect(out.warnings, isEmpty);
      final DocxDocument back = DocxDocument.open(out.bytes);
      expect(back.warnings, isEmpty);
      expect(tableOf(back).rows, hasLength(5));
      expect(comparePackages(out.bytes, back.save().bytes), isEmpty);
    });

    test('a control character warns', () {
      final DocxResult out = DocxListExport(_two).toDocx(<List<Object?>>[
        <Object?>['a\u0001b', 1],
      ]);
      expect(
        out.warnings.map((DocxWarning w) => w.code),
        contains(DocxWarningCode.invalidCharactersRemoved),
      );
    });

    test('toDocx sets the title', () {
      final DocxResult out = DocxListExport(
        _two,
      ).toDocx(three, properties: const OfficeProperties(title: 'X'));
      expect(DocxDocument.open(out.bytes).properties.title, 'X');
    });
  });

  group('the D6 fixtures, by hand', () {
    DocxFixture fixture(String name) =>
        docxFixtures().singleWhere((DocxFixture f) => f.name == name);

    /// The lines of [text] that are table rows: a row's cells are joined by
    /// tabs, and no other line of these fixtures holds a tab.
    List<String> rowLines(String text) => <String>[
      for (final String line in text.split('\n'))
        if (line.contains('\t')) line,
    ];

    test('d6_list: 122 rows, the totals last', () {
      final String text = fixture('d6_list').expectedText;
      final List<String> rows = rowLines(text);
      // The header, 120 data rows and the totals row, five cells each.
      expect(rows, hasLength(122));
      expect(rows.every((String r) => '\t'.allMatches(r).length == 4), isTrue);
      expect(rows.first, startsWith('Kod\t'));
      expect(rows.last, startsWith('Toplam'));
      expect(
        text.split('\n').where((String l) => l.startsWith('Toplam')),
        hasLength(1),
      );
    });

    test('d6_list: the header shows the date, the footer the page', () {
      // The date is in the header, not the body, so the stories hold it.
      final String? stories = fixture('d6_list').headerFooterText;
      expect(stories, contains('08.11.2026'));
      expect(stories, contains('Sayfa {PAGE} / {NUMPAGES}'));
    });

    test('d6_list_landscape: 41 rows of 12 cells', () {
      final List<String> rows = rowLines(
        fixture('d6_list_landscape').expectedText,
      );
      expect(rows, hasLength(41));
      expect(rows.every((String r) => '\t'.allMatches(r).length == 11), isTrue);
      expect(rows.first, startsWith('Code\t'));
    });
  });
}
