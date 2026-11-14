import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/docx/warnings.dart' show DocxWarningCollector;
import 'package:test/test.dart';

/// The warning of [code] of a save of [doc].
DocxWarning _warning(DocxDocument doc, DocxWarningCode code) =>
    doc.save().warnings.singleWhere((DocxWarning w) => w.code == code);

void main() {
  test('styleNotFound names a paragraph in a cell by its full path', () {
    final DocxDocument doc = DocxDocument();
    final DocxTable table = doc.body.addTable(columns: 1);
    table.addRow(<String?>['a']);
    (table.rows.single.cells.single.blocks.single as DocxParagraph).style =
        'Bilinmez';
    final DocxWarning w = _warning(doc, DocxWarningCode.styleNotFound);
    expect(w.locations, <String>['body/tbl[0]/tr[0]/tc[0]/p[0]']);
    expect(w.detail, 'Bilinmez');
  });

  test('numberingNotFound names a paragraph in a cell by its full path', () {
    final DocxDocument doc = DocxDocument();
    final DocxTable table = doc.body.addTable(columns: 1);
    table.addRow(<String?>['a']);
    (table.rows.single.cells.single.blocks.single as DocxParagraph)
        .properties
        .numbering = DocxNumberingRef(
      42,
    );
    final DocxWarning w = _warning(doc, DocxWarningCode.numberingNotFound);
    expect(w.locations, <String>['body/tbl[0]/tr[0]/tc[0]/p[0]']);
    expect(w.detail, '42');
  });

  test('styleNotFound names a table and a nested table by their paths', () {
    final DocxDocument doc = DocxDocument();
    final DocxTable table = doc.body.addTable(columns: 1);
    table.addRow(<String?>['a']);
    table.properties.style = 'Bilinmez';
    final DocxTable nested = table.rows.single.cells.single.addTable(
      columns: 1,
    );
    nested.addRow(<String?>['b']);
    nested.properties.style = 'Bilinmez';
    expect(_warning(doc, DocxWarningCode.styleNotFound).locations, <String>[
      'body/tbl[0]',
      'body/tbl[0]/tr[0]/tc[0]/tbl[0]',
    ]);
  });

  test('a table style of another type counts as not found', () {
    final DocxDocument doc = DocxDocument();
    final DocxTable table = doc.body.addTable(columns: 1);
    table.addRow(<String?>['a']);
    table.properties.style = 'Normal';
    expect(_warning(doc, DocxWarningCode.styleNotFound).locations, <String>[
      'body/tbl[0]',
    ]);
  });

  test('invalidCharactersRemoved aggregates per part with ten locations', () {
    final DocxWarningCollector collector = DocxWarningCollector();
    for (int i = 0; i < 25; i++) {
      collector.add(
        DocxWarningCode.invalidCharactersRemoved,
        part: '/word/document.xml',
        location: 'body/p[$i]/r[0]',
      );
    }
    collector.add(
      DocxWarningCode.invalidCharactersRemoved,
      part: '/word/header1.xml',
      location: 'header1.xml/p[0]',
    );
    final List<DocxWarning> warnings = collector.warnings;
    expect(warnings, hasLength(2));
    expect(warnings.first.part, '/word/document.xml');
    expect(warnings.first.count, 25);
    expect(warnings.first.locations, hasLength(10));
    expect(warnings.first.locations.first, 'body/p[0]/r[0]');
    expect(warnings.first.detail, isNull);
    expect(warnings.last.part, '/word/header1.xml');
    expect(warnings.last.count, 1);
  });

  test('message is in en, de and tr and names the count and part', () {
    final DocxWarningCollector collector = DocxWarningCollector();
    for (int i = 0; i < 3; i++) {
      collector.add(
        DocxWarningCode.invalidCharactersRemoved,
        part: '/word/document.xml',
        location: 'body/p[$i]',
      );
    }
    final DocxWarning w = collector.warnings.single;
    for (final OfficeLocale locale in OfficeLocale.values) {
      final String m = w.message(locale);
      expect(m, contains('3'), reason: '$locale');
      expect(m, contains('document.xml'), reason: '$locale');
      expect(m, contains('body/p[0]'), reason: '$locale');
    }
    expect(w.message(OfficeLocale.de), isNot(w.message()));
    expect(w.message(OfficeLocale.tr), isNot(w.message()));
  });

  test('more than ten locations end with an ellipsis', () {
    final DocxWarningCollector collector = DocxWarningCollector();
    for (int i = 0; i < 11; i++) {
      collector.add(
        DocxWarningCode.invalidCharactersRemoved,
        part: '/word/document.xml',
        location: 'body/p[$i]',
      );
    }
    final String m = collector.warnings.single.message();
    expect(m, contains('body/p[9], …)'));
    expect(m, isNot(contains('body/p[10]')));
  });

  group('location list ellipsis', () {
    test('one run with two removed characters has no ellipsis', () {
      final DocxWarning w =
          (DocxWarningCollector()..add(
                DocxWarningCode.invalidCharactersRemoved,
                part: '/word/document.xml',
                location: 'body/p[0]/r[0]',
                count: 2,
              ))
              .warnings
              .single;
      expect(w.count, 2);
      for (final OfficeLocale locale in OfficeLocale.values) {
        expect(w.message(locale), contains('(body/p[0]/r[0])'));
        expect(w.message(locale), isNot(contains('…')), reason: '$locale');
      }
    });

    test('a saved paragraph with two bad characters has no ellipsis', () {
      final DocxDocument document = DocxDocument();
      document.body.addParagraph('a\u0001\u0002b');
      final DocxWarning w = document.save().warnings.single;
      expect(w.count, 2);
      expect(w.locations, hasLength(1));
      expect(w.message(), isNot(contains('…')));
    });

    test('eleven runs with removed characters end with an ellipsis', () {
      final DocxWarningCollector collector = DocxWarningCollector();
      for (int i = 0; i < 11; i++) {
        collector.add(
          DocxWarningCode.invalidCharactersRemoved,
          part: '/word/document.xml',
          location: 'body/p[0]/r[$i]',
          count: 2,
        );
      }
      final DocxWarning w = collector.warnings.single;
      expect(w.count, 22);
      for (final OfficeLocale locale in OfficeLocale.values) {
        expect(w.message(locale), contains('body/p[0]/r[9], …)'));
      }
    });

    test('ten runs name every location without an ellipsis', () {
      final DocxWarningCollector collector = DocxWarningCollector();
      for (int i = 0; i < 10; i++) {
        collector.add(
          DocxWarningCode.invalidCharactersRemoved,
          part: '/word/document.xml',
          location: 'body/p[0]/r[$i]',
          count: 3,
        );
      }
      expect(collector.warnings.single.message(), isNot(contains('…')));
    });
  });

  group('one removed character is singular', () {
    DocxWarning warning(int count) =>
        (DocxWarningCollector()..add(
              DocxWarningCode.invalidCharactersRemoved,
              part: '/word/document.xml',
              location: 'body/p[0]/r[0]',
              count: count,
            ))
            .warnings
            .single;

    test('en', () {
      expect(
        warning(1).message(),
        startsWith(
          '1 character that XML does '
          'not allow was removed',
        ),
      );
      expect(
        warning(2).message(),
        startsWith(
          '2 characters that XML does '
          'not allow were removed',
        ),
      );
    });

    test('de', () {
      expect(
        warning(1).message(OfficeLocale.de),
        startsWith('1 Zeichen, das XML nicht erlaubt, wurde'),
      );
      expect(
        warning(2).message(OfficeLocale.de),
        startsWith('2 Zeichen, die XML nicht erlaubt, wurden'),
      );
    });

    test('tr', () {
      // Turkish keeps the noun singular after a numeral.
      expect(
        warning(1).message(OfficeLocale.tr),
        contains("XML'in izin vermediği 1 karakter çıkarıldı"),
      );
      expect(
        warning(2).message(OfficeLocale.tr),
        contains("XML'in izin vermediği 2 karakter çıkarıldı"),
      );
    });
  });

  test('detail codes name the detail in every locale', () {
    final DocxWarningCollector collector = DocxWarningCollector()
      ..add(
        DocxWarningCode.contentTypeMissing,
        part: '/word/document.xml',
        detail: 'application/xml',
      )
      ..add(
        DocxWarningCode.mainPartContentTypeUnexpected,
        part: '/word/document.xml',
        detail: 'text/plain',
      );
    expect(collector.warnings, hasLength(2));
    for (final DocxWarning w in collector.warnings) {
      for (final OfficeLocale locale in OfficeLocale.values) {
        expect(w.message(locale), contains('document.xml'));
        expect(w.message(locale), contains(w.detail!));
      }
    }
  });

  test('styleNotFound has en, de and tr text naming count, part and id', () {
    final DocxWarningCollector many = DocxWarningCollector();
    for (int i = 0; i < 2; i++) {
      many.add(
        DocxWarningCode.styleNotFound,
        part: '/word/document.xml',
        location: 'body/p[$i]',
        detail: 'Bilinmez',
      );
    }
    final DocxWarningCollector one = DocxWarningCollector()
      ..add(
        DocxWarningCode.styleNotFound,
        part: '/word/document.xml',
        location: 'body/p[0]',
        detail: 'Bilinmez',
      );
    final DocxWarning plural = many.warnings.single;
    final DocxWarning singular = one.warnings.single;
    expect(
      plural.message(),
      '2 references in /word/document.xml (body/p[0], body/p[1]) name the '
      'style Bilinmez, which the document does not define; Word shows them '
      'in the default style.',
    );
    expect(
      singular.message(),
      '1 reference in /word/document.xml (body/p[0]) names the style '
      'Bilinmez, which the document does not define; Word shows it in the '
      'default style.',
    );
    for (final OfficeLocale locale in OfficeLocale.values) {
      for (final DocxWarning w in <DocxWarning>[plural, singular]) {
        expect(w.message(locale), contains('${w.count}'));
        expect(w.message(locale), contains('/word/document.xml'));
        expect(w.message(locale), contains('body/p[0]'));
        expect(w.message(locale), contains('Bilinmez'));
      }
    }
    expect(
      plural.message(OfficeLocale.de),
      isNot(singular.message(OfficeLocale.de)),
    );
  });

  test('locations and warnings are the same objects on each call', () {
    final DocxWarningCollector collector = DocxWarningCollector();
    final List<DocxWarning> warnings = collector.warnings;
    collector.add(
      DocxWarningCode.styleNotFound,
      part: '/word/document.xml',
      location: 'body/p[0]',
      detail: 'Bilinmez',
    );
    expect(identical(collector.warnings, warnings), isTrue);
    expect(warnings, hasLength(1));
    final DocxWarning w = warnings.single;
    final List<String> locations = w.locations;
    collector.add(
      DocxWarningCode.styleNotFound,
      part: '/word/document.xml',
      location: 'body/p[1]',
      detail: 'Bilinmez',
    );
    expect(identical(w.locations, locations), isTrue);
    expect(locations, hasLength(2));
  });

  test('toString is English', () {
    final DocxWarning w =
        (DocxWarningCollector()..add(
              DocxWarningCode.invalidCharactersRemoved,
              part: '/word/document.xml',
              location: 'body/p[0]',
            ))
            .warnings
            .single;
    expect(w.toString(), w.message(OfficeLocale.en));
    expect(w.toString(), contains('character'));
  });

  test(
    'propertyValueInvalid names the part and the element in every language',
    () {
      final DocxWarningCollector collector = DocxWarningCollector();
      collector.add(
        DocxWarningCode.propertyValueInvalid,
        part: '/docProps/core.xml',
        detail: 'cp:revision',
      );
      final DocxWarning w = collector.warnings.single;
      expect(
        w.message(),
        'Document property cp:revision in /docProps/core.xml could not be '
        'read; it was kept as it is.',
      );
      expect(w.message(OfficeLocale.de), contains('cp:revision'));
      expect(w.message(OfficeLocale.tr), contains('/docProps/core.xml'));
    },
  );

  group('template codes', () {
    test('every template code has a message naming the part and the tag', () {
      for (final DocxWarningCode code in DocxWarningCode.values.where(
        (DocxWarningCode c) => c.name.startsWith('template'),
      )) {
        final DocxWarningCollector c = DocxWarningCollector()
          ..add(
            code,
            part: '/word/document.xml',
            location: 'body/p[0]',
            detail: '{{musteri.unvan}}',
          );
        for (final OfficeLocale l in OfficeLocale.values) {
          final String m = c.warnings.single.message(l);
          expect(m, contains('/word/document.xml'), reason: '$code $l');
          expect(m, contains('{{musteri.unvan}}'), reason: '$code $l');
        }
      }
    });

    test(
      'thirteen template codes',
      () => expect(
        DocxWarningCode.values.where(
          (DocxWarningCode c) => c.name.startsWith('template'),
        ),
        hasLength(13),
      ),
    );
  });
}
