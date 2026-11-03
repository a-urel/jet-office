import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/docx/warnings.dart' show DocxWarningCollector;
import 'package:test/test.dart';

void main() {
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
}
