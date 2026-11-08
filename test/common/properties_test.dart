import 'package:jet_office/jet_office.dart' show XlsxLimits, XlsxWriter;
import 'package:jet_office/src/common/properties.dart';
import 'package:jet_office/src/xml/xml_writer.dart';
import 'package:test/test.dart';

import '../support/read_xlsx.dart';

String _core(OfficeProperties p) {
  final StringBuffer out = StringBuffer();
  writeCoreProperties(XmlWriter(out), p);
  return out.toString();
}

String _custom(OfficeProperties p) {
  final StringBuffer out = StringBuffer();
  writeCustomProperties(XmlWriter(out), p);
  return out.toString();
}

String _app(OfficeProperties p) {
  final StringBuffer out = StringBuffer();
  writeAppProperties(XmlWriter(out), p);
  return out.toString();
}

const String _coreRoot =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<cp:coreProperties'
    ' xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties"'
    ' xmlns:dc="http://purl.org/dc/elements/1.1/"'
    ' xmlns:dcterms="http://purl.org/dc/terms/"'
    ' xmlns:dcmitype="http://purl.org/dc/dcmitype/"'
    ' xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">';

void main() {
  test('core writes only the given fields, dates as UTC W3CDTF seconds', () {
    final String xml = _core(
      OfficeProperties(
        title: 'Cari Hesaplar',
        created: DateTime.utc(2026, 10, 24, 9, 30, 15, 500),
      ),
    );
    expect(
      xml,
      '$_coreRoot<dc:title>Cari Hesaplar</dc:title>'
      '<dcterms:created xsi:type="dcterms:W3CDTF">2026-10-24T09:30:15Z</dcterms:created>'
      '</cp:coreProperties>',
    );
    expect(xml, isNot(contains('dcterms:modified')));
  });

  test('empty properties write no dcterms date elements', () {
    final String xml = _core(const OfficeProperties());
    expect(xml, '${_coreRoot.substring(0, _coreRoot.length - 1)}/>');
    expect(xml, isNot(contains('<dcterms:')));
  });

  test('core keeps the order Excel writes', () {
    final String xml = _core(
      OfficeProperties(
        modified: DateTime.utc(2026, 1, 2, 3, 4, 5),
        created: DateTime.utc(2026, 1, 1),
        category: 'cat',
        lastModifiedBy: 'lmb',
        description: 'desc',
        keywords: 'kw',
        creator: 'cr',
        subject: 'sub',
        title: 'ti',
      ),
    );
    final List<String> order = <String>[
      '<dc:title>',
      '<dc:subject>',
      '<dc:creator>',
      '<cp:keywords>',
      '<dc:description>',
      '<cp:lastModifiedBy>',
      '<cp:category>',
      '<dcterms:created ',
      '<dcterms:modified ',
    ];
    final List<int> at = order.map(xml.indexOf).toList();
    expect(at, everyElement(isNonNegative));
    expect(at, orderedEquals(<int>[...at]..sort()));
  });

  test('a local DateTime is converted to UTC', () {
    final DateTime local = DateTime.utc(2026, 6, 1, 12).toLocal();
    // toLocal() on a UTC machine still returns a local value, so this holds
    // everywhere and the test never passes by comparing UTC with UTC.
    expect(local.isUtc, isFalse);
    expect(
      _core(OfficeProperties(modified: local)),
      contains('>2026-06-01T12:00:00Z<'),
    );
  });

  test('fractions of a second are cut, never rounded up', () {
    final String xml = _core(
      OfficeProperties(
        created: DateTime.utc(2026, 10, 24, 9, 30, 15, 999, 999),
        modified: DateTime.utc(2026, 12, 31, 23, 59, 59, 999),
      ),
    );
    expect(xml, contains('>2026-10-24T09:30:15Z<'));
    expect(xml, contains('>2026-12-31T23:59:59Z<'));
  });

  test('text is escaped', () {
    expect(
      _core(const OfficeProperties(title: 'A & B <c>')),
      contains('<dc:title>A &amp; B &lt;c&gt;</dc:title>'),
    );
  });

  test('forbidden characters throw ArgumentError', () {
    expect(
      () => _core(const OfficeProperties(title: 'a\u0000b')),
      throwsArgumentError,
    );
    expect(
      () => _app(const OfficeProperties(company: 'a\uD800')),
      throwsArgumentError,
    );
  });

  test('app writes Application and Company when set', () {
    const String head =
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties">'
        '<Application>jet_office</Application>';
    expect(_app(const OfficeProperties()), '$head</Properties>');
    expect(
      _app(const OfficeProperties(company: 'Jetronik')),
      '$head<Company>Jetronik</Company></Properties>',
    );
  });

  test(
    'manager follows Company in app.xml, contentStatus follows category',
    () {
      final String app = _app(
        const OfficeProperties(company: 'Jetronik', manager: 'Ayse'),
      );
      expect(
        app,
        endsWith(
          '<Company>Jetronik</Company><Manager>Ayse</Manager></Properties>',
        ),
      );
      final String core = _core(
        OfficeProperties(
          contentStatus: 'Final',
          category: 'cat',
          created: DateTime.utc(2026, 1, 1),
        ),
      );
      expect(
        core,
        contains(
          '<cp:category>cat</cp:category>'
          '<cp:contentStatus>Final</cp:contentStatus><dcterms:created ',
        ),
      );
      expect(_core(const OfficeProperties()), isNot(contains('contentStatus')));
      expect(_app(const OfficeProperties()), isNot(contains('Manager')));
    },
  );

  test('forbidden characters in manager and contentStatus throw', () {
    expect(
      () => _app(const OfficeProperties(manager: 'a\u0001')),
      throwsArgumentError,
    );
    expect(
      () => _core(const OfficeProperties(contentStatus: 'a\u0001')),
      throwsArgumentError,
    );
  });

  group('custom properties', () {
    final OfficeProperties five = OfficeProperties(
      custom: <String, Object>{
        'Project': 'Atlas',
        'Count': 3,
        'Ratio': 0.5,
        'Final': true,
        'Due': DateTime.utc(2026, 10, 24),
      },
    );
    const String fmt = '{D5CDD505-2E9C-101B-9397-08002B2CF9AE}';

    test('one property per entry, pids from 2 in map order', () {
      expect(
        _custom(five),
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Properties'
        ' xmlns="http://schemas.openxmlformats.org/officeDocument/2006/custom-properties"'
        ' xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">'
        '<property fmtid="$fmt" pid="2" name="Project">'
        '<vt:lpwstr>Atlas</vt:lpwstr></property>'
        '<property fmtid="$fmt" pid="3" name="Count">'
        '<vt:i4>3</vt:i4></property>'
        '<property fmtid="$fmt" pid="4" name="Ratio">'
        '<vt:r8>0.5</vt:r8></property>'
        '<property fmtid="$fmt" pid="5" name="Final">'
        '<vt:bool>true</vt:bool></property>'
        '<property fmtid="$fmt" pid="6" name="Due">'
        '<vt:filetime>2026-10-24T00:00:00Z</vt:filetime></property>'
        '</Properties>',
      );
    });

    test('false, a local DateTime and escaping', () {
      final String xml = _custom(
        OfficeProperties(
          custom: <String, Object>{
            'A&B': 'x<y',
            'No': false,
            'At': DateTime.utc(2026, 6, 1, 12, 0, 0, 900).toLocal(),
            'Neg': -2147483648,
          },
        ),
      );
      expect(xml, contains('name="A&amp;B"><vt:lpwstr>x&lt;y</vt:lpwstr>'));
      expect(xml, contains('<vt:bool>false</vt:bool>'));
      expect(xml, contains('<vt:filetime>2026-06-01T12:00:00Z<'));
      expect(xml, contains('<vt:i4>-2147483648</vt:i4>'));
    });

    void bad(String label, Map<String, Object> custom, String field) {
      test('$label throws ArgumentError naming $field', () {
        expect(
          () => _custom(OfficeProperties(custom: custom)),
          throwsA(
            isA<ArgumentError>().having(
              (ArgumentError e) => e.name,
              'name',
              field,
            ),
          ),
        );
      });
    }

    bad('an empty name', <String, Object>{'': 'x'}, 'custom');
    bad('a name of 256 units', <String, Object>{'n' * 256: 'x'}, 'custom');
    bad('a forbidden character in a name', <String, Object>{
      'a\u0001': 'x',
    }, 'custom');
    bad('names equal ignoring case', <String, Object>{
      'Name': 'x',
      'NAME': 'y',
    }, 'custom');
    group('numbers on the VM and the web alike', () {
      String value(Object number) => RegExp(r'<vt:\w+>[^<]*</vt:\w+>')
          .firstMatch(
            _custom(OfficeProperties(custom: <String, Object>{'N': number})),
          )!
          .group(0)!;

      test('an int within 32 bits is vt:i4', () {
        expect(value(2147483647), '<vt:i4>2147483647</vt:i4>');
        expect(value(-2147483648), '<vt:i4>-2147483648</vt:i4>');
      });

      test('an int outside 32 bits is vt:r8', () {
        expect(value(2147483648), '<vt:r8>2147483648</vt:r8>');
        expect(value(-2147483649), '<vt:r8>-2147483649</vt:r8>');
        // 2^40, written as a literal: on the web `1 << 40` wraps to 32 bits.
        expect(value(1099511627776), '<vt:r8>1099511627776</vt:r8>');
      });

      test('a whole double within 32 bits is vt:i4, a fraction vt:r8', () {
        // On the web 3.0 is an int; the VM must write the same.
        expect(value(3.0), '<vt:i4>3</vt:i4>');
        expect(value(-2147483648.0), '<vt:i4>-2147483648</vt:i4>');
        expect(value(-0.0), '<vt:i4>0</vt:i4>');
        expect(value(0.5), '<vt:r8>0.5</vt:r8>');
        expect(value(2147483647.5), '<vt:r8>2147483647.5</vt:r8>');
      });

      test('a whole double outside 32 bits is vt:r8, not a throw', () {
        // On the web both are ints; they must not be refused there.
        expect(value(3e9), '<vt:r8>3000000000</vt:r8>');
        expect(value(1e10), '<vt:r8>10000000000</vt:r8>');
      });
    });
    bad('NaN', <String, Object>{'N': double.nan}, 'custom["N"]');
    bad('infinity', <String, Object>{'N': double.infinity}, 'custom["N"]');
    bad('another value type', <String, Object>{
      'N': <int>[1],
    }, 'custom["N"]');
    bad('a forbidden character in a string', <String, Object>{
      'N': 'a\u0000',
    }, 'custom["N"]');

    test('a name of 255 units is accepted', () {
      expect(XlsxLimits.maxCustomPropertyNameLength, 255);
      expect(
        _custom(OfficeProperties(custom: <String, Object>{'n' * 255: 'x'})),
        contains('name="${'n' * 255}"'),
      );
    });

    test('an empty custom map writes no custom part', () {
      final XlsxWriter book = XlsxWriter(
        properties: const OfficeProperties(title: 't'),
      );
      book.addSheet('S');
      final Map<String, String> parts = readXlsx(book.close().bytes);
      expect(parts.keys, isNot(contains('docProps/custom.xml')));
      expect(parts['[Content_Types].xml'], isNot(contains('custom')));
      expect(parts['_rels/.rels'], isNot(contains('custom')));
    });

    test('== and hashCode compare the map entry by entry, in order', () {
      OfficeProperties of(Map<String, Object> m) =>
          OfficeProperties(title: 't', manager: 'm', custom: m);
      final OfficeProperties a = of(<String, Object>{'a': 1, 'b': 'x'});
      expect(a, of(<String, Object>{'a': 1, 'b': 'x'}));
      expect(a.hashCode, of(<String, Object>{'a': 1, 'b': 'x'}).hashCode);
      expect(a, isNot(of(<String, Object>{'b': 'x', 'a': 1})));
      expect(a, isNot(of(<String, Object>{'a': 1, 'b': 'y'})));
      expect(a, isNot(of(<String, Object>{'a': 1})));
      expect(
        const OfficeProperties(contentStatus: 'a'),
        isNot(const OfficeProperties(contentStatus: 'b')),
      );
      expect(const OfficeProperties(), const OfficeProperties());
    });

    test('toString names manager, contentStatus and custom', () {
      final String s = const OfficeProperties(
        manager: 'Ayse',
        contentStatus: 'Final',
        custom: <String, Object>{'k': 1},
      ).toString();
      expect(s, contains('manager: Ayse'));
      expect(s, contains('contentStatus: Final'));
      expect(s, contains('custom: {k: 1}'));
    });
  });

  group('revision and application', () {
    test('revision is written after cp:lastModifiedBy, in Excel order', () {
      final String xml = _core(
        OfficeProperties(
          category: 'cat',
          revision: 7,
          lastModifiedBy: 'lmb',
          created: DateTime.utc(2026, 1, 1),
        ),
      );
      expect(
        xml,
        contains(
          '<cp:lastModifiedBy>lmb</cp:lastModifiedBy>'
          '<cp:revision>7</cp:revision><cp:category>cat</cp:category>',
        ),
      );
      expect(
        _core(const OfficeProperties(revision: 0)),
        contains('<cp:revision>0</cp:revision>'),
      );
      expect(_core(const OfficeProperties()), isNot(contains('revision')));
    });

    test('a negative revision throws ArgumentError naming revision', () {
      expect(
        () => checkProperties(const OfficeProperties(revision: -1)),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => e.name,
            'name',
            'revision',
          ),
        ),
      );
    });

    test('application is written in place of jet_office when set', () {
      expect(
        _app(const OfficeProperties(application: 'Microsoft Office Word')),
        contains('<Application>Microsoft Office Word</Application>'),
      );
      expect(
        _app(const OfficeProperties()),
        contains('<Application>jet_office</Application>'),
      );
      expect(
        () => checkProperties(const OfficeProperties(application: 'a\u0000')),
        throwsArgumentError,
      );
    });

    test('XlsxWriter with no application still writes jet_office', () {
      final XlsxWriter book = XlsxWriter(properties: const OfficeProperties());
      book.addSheet('S');
      final Map<String, String> parts = readXlsx(book.close().bytes);
      expect(
        parts['docProps/app.xml'],
        contains('<Application>jet_office</Application>'),
      );
    });

    test('==, hashCode and toString cover both', () {
      expect(
        const OfficeProperties(revision: 1),
        isNot(const OfficeProperties(revision: 2)),
      );
      expect(
        const OfficeProperties(application: 'a'),
        isNot(const OfficeProperties(application: 'b')),
      );
      expect(
        const OfficeProperties(revision: 3, application: 'x').hashCode,
        const OfficeProperties(revision: 3, application: 'x').hashCode,
      );
      final String s = const OfficeProperties(
        revision: 3,
        application: 'Word',
      ).toString();
      expect(s, contains('revision: 3'));
      expect(s, contains('application: Word'));
    });
  });

  group('copyWith', () {
    final OfficeProperties full = OfficeProperties(
      title: 'Title',
      subject: 'Subject',
      creator: 'Creator',
      keywords: 'one;two',
      description: 'Description',
      lastModifiedBy: 'Editor',
      category: 'Category',
      company: 'Company',
      manager: 'Manager',
      contentStatus: 'Draft',
      revision: 3,
      application: 'Word',
      created: DateTime.utc(2026, 1, 2, 3, 4, 5),
      modified: DateTime.utc(2026, 6, 7, 8, 9, 10),
      custom: const <String, Object>{'Project': 'Alpha', 'Count': 2},
    );

    test('with no argument equals the original', () {
      expect(full.copyWith(), full);
      expect(const OfficeProperties().copyWith(), const OfficeProperties());
    });

    test('keeps every field it is not given', () {
      final OfficeProperties copy = full.copyWith(title: 'New');
      expect(copy.title, 'New');
      expect(
        copy,
        OfficeProperties(
          title: 'New',
          subject: full.subject,
          creator: full.creator,
          keywords: full.keywords,
          description: full.description,
          lastModifiedBy: full.lastModifiedBy,
          category: full.category,
          company: full.company,
          manager: full.manager,
          contentStatus: full.contentStatus,
          revision: full.revision,
          application: full.application,
          created: full.created,
          modified: full.modified,
          custom: full.custom,
        ),
      );
    });

    test('replaces every field when given', () {
      final DateTime created = DateTime.utc(2027, 2, 3);
      final DateTime modified = DateTime.utc(2027, 3, 4);
      const Map<String, Object> custom = <String, Object>{'Other': true};
      final OfficeProperties copy = full.copyWith(
        title: 't',
        subject: 's',
        creator: 'c',
        keywords: 'k',
        description: 'd',
        lastModifiedBy: 'l',
        category: 'g',
        company: 'y',
        manager: 'm',
        contentStatus: 'Final',
        revision: 9,
        application: 'a',
        created: created,
        modified: modified,
        custom: custom,
      );
      expect(copy.title, 't');
      expect(copy.subject, 's');
      expect(copy.creator, 'c');
      expect(copy.keywords, 'k');
      expect(copy.description, 'd');
      expect(copy.lastModifiedBy, 'l');
      expect(copy.category, 'g');
      expect(copy.company, 'y');
      expect(copy.manager, 'm');
      expect(copy.contentStatus, 'Final');
      expect(copy.revision, 9);
      expect(copy.application, 'a');
      expect(copy.created, created);
      expect(copy.modified, modified);
      expect(copy.custom, custom);
    });

    test('each field alone changes only that field', () {
      expect(full.copyWith(subject: 'x').subject, 'x');
      expect(full.copyWith(subject: 'x').title, 'Title');
      expect(full.copyWith(revision: 0).revision, 0);
      expect(full.copyWith(revision: 0).company, 'Company');
      expect(full.copyWith(custom: const <String, Object>{}).custom, isEmpty);
      expect(full.copyWith(custom: const <String, Object>{}).title, 'Title');
    });

    test('null keeps the field; the constructor clears one', () {
      expect(full.copyWith(title: null).title, 'Title');
      expect(full.copyWith(created: null).created, full.created);
    });
  });
}
