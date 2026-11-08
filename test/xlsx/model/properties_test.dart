import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/opc/change_log.dart';
import 'package:jet_office/src/xlsx/model/xlsx_workbook.dart';
import 'package:test/test.dart';

import '../../../tool/src/part_compare.dart';
import '../../fixtures/fixtures.dart';
import '../../support/read_xlsx.dart';
import '../read/support/zip_builder.dart';

Uint8List _fixture(String name) =>
    allFixtures().firstWhere((Fixture f) => f.name == name).build();

final OfficeProperties _m3 = OfficeProperties(
  title: 'Quarterly report',
  subject: 'Accounts',
  creator: 'Ahmet Urel',
  keywords: 'report; accounts',
  description: 'Fixture for the document properties',
  lastModifiedBy: 'Jet Office',
  category: 'Finance',
  contentStatus: 'Final',
  company: 'Jetronik',
  manager: 'Ayse Yilmaz',
  created: DateTime.utc(2026, 10, 24, 9, 30),
  modified: DateTime.utc(2026, 10, 25, 18, 45, 10),
  custom: <String, Object>{
    'Project': 'Atlas',
    'Count': 3,
    'Ratio': 0.5,
    'Final': true,
    'Due': DateTime.utc(2026, 10, 24),
  },
);

const String _coreNs =
    'http://schemas.openxmlformats.org/package/2006/metadata/core-properties';
const String _appNs =
    'http://schemas.openxmlformats.org/officeDocument/2006/extended-properties';
const String _customNs =
    'http://schemas.openxmlformats.org/officeDocument/2006/custom-properties';
const String _vtNs =
    'http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes';
const String _fmtid = '{D5CDD505-2E9C-101B-9397-08002B2CF9AE}';

String _core(String body) =>
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<cp:coreProperties xmlns:cp="$_coreNs" '
    'xmlns:dc="http://purl.org/dc/elements/1.1/" '
    'xmlns:dcterms="http://purl.org/dc/terms/" '
    'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">$body'
    '</cp:coreProperties>';

String _app(String body) =>
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Properties xmlns="$_appNs">$body</Properties>';

String _custom(String body) =>
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Properties xmlns="$_customNs" xmlns:vt="$_vtNs">$body</Properties>';

String _prop(int pid, String name, String value, {String fmtid = _fmtid}) =>
    '<property fmtid="$fmtid" pid="$pid" name="$name">$value</property>';

/// A one-sheet workbook of the model, saved, with [parts] replacing or
/// adding entries, and the root relationships and content types edited by
/// [rels] and [types] (raw text before the closing tag).
Uint8List _package({
  Map<String, String> parts = const <String, String>{},
  String rels = '',
  String types = '',
}) {
  final XlsxWorkbook base = XlsxWorkbook()..addSheet('S');
  final Map<String, Uint8List> all = readXlsxBytes(base.save().bytes);
  for (final MapEntry<String, String> p in parts.entries) {
    all[p.key] = Uint8List.fromList(utf8.encode(p.value));
  }
  String edit(String name, String closing, String add) {
    final String text = utf8.decode(all[name]!);
    return text.replaceFirst(closing, '$add$closing');
  }

  all['_rels/.rels'] = Uint8List.fromList(
    utf8.encode(edit('_rels/.rels', '</Relationships>', rels)),
  );
  all['[Content_Types].xml'] = Uint8List.fromList(
    utf8.encode(edit('[Content_Types].xml', '</Types>', types)),
  );
  return buildZipOrdered(<(String, List<int>)>[
    for (final MapEntry<String, Uint8List> p in all.entries) (p.key, p.value),
  ]);
}

const String _customRel =
    '<Relationship Id="rIdC" Type="http://schemas.openxmlformats.org/'
    'officeDocument/2006/relationships/custom-properties" '
    'Target="docProps/custom.xml"/>';
const String _customType =
    '<Override PartName="/docProps/custom.xml" ContentType="application/'
    'vnd.openxmlformats-officedocument.custom-properties+xml"/>';

Uint8List _withCustom(String body) => _package(
  parts: <String, String>{'docProps/custom.xml': _custom(body)},
  rels: _customRel,
  types: _customType,
);

String _part(XlsxWorkbook book, String name) =>
    readXlsx(book.save().bytes)[name]!;

/// The differences of the properties parts, the root relationships and the
/// content types of [a] and [b].
List<String> _propertyDifferences(Uint8List a, Uint8List b) => <String>[
  for (final String line in comparePackages(a, b))
    if (line.startsWith('docProps/') ||
        line.startsWith('_rels/.rels') ||
        line.startsWith('[Content_Types].xml'))
      line,
];

void main() {
  group('reading', () {
    test('reads m3_properties', () {
      final XlsxWorkbook book = XlsxWorkbook.open(_fixture('m3_properties'));
      expect(book.properties, _m3);
      expect(book.properties.created!.isUtc, isTrue);
      expect(book.properties.custom.keys, <String>[
        'Project',
        'Count',
        'Ratio',
        'Final',
        'Due',
      ]);
      expect(book.warnings, isEmpty);
    });

    test('reads m1_properties', () {
      final XlsxWorkbook book = XlsxWorkbook.open(_fixture('m1_properties'));
      expect(
        book.properties,
        OfficeProperties(
          title: 'Quarterly report',
          subject: 'Sales',
          creator: 'Ahmet Urel',
          keywords: 'sales; q3',
          description: 'A test workbook',
          lastModifiedBy: 'jet_office',
          category: 'Reports',
          company: 'Jetronik',
          created: DateTime.utc(2026, 10, 24, 8, 30),
          modified: DateTime.utc(2026, 10, 24, 9, 45, 30),
        ),
      );
    });

    test('a new workbook has no properties', () {
      expect(XlsxWorkbook().properties, const OfficeProperties());
    });

    test('a file without the parts has no properties', () {
      final Map<String, Uint8List> all = readXlsxBytes(
        (XlsxWorkbook()..addSheet('S')).save().bytes,
      );
      final String rels = utf8
          .decode(all['_rels/.rels']!)
          .replaceAll(RegExp(r'<Relationship [^>]*docProps[^>]*/>'), '');
      final XlsxWorkbook book = XlsxWorkbook.open(
        buildZipOrdered(<(String, List<int>)>[
          for (final MapEntry<String, Uint8List> p in all.entries)
            if (!p.key.startsWith('docProps/'))
              (p.key, p.key == '_rels/.rels' ? utf8.encode(rels) : p.value),
        ]),
      );
      expect(book.properties, const OfficeProperties());
      book.properties = const OfficeProperties(title: 'T', company: 'C');
      final XlsxWorkbook again = XlsxWorkbook.open(book.save().bytes);
      expect(
        again.properties,
        const OfficeProperties(title: 'T', company: 'C'),
      );
      expect(
        readXlsx(book.save().bytes).keys,
        containsAll(<String>['docProps/core.xml', 'docProps/app.xml']),
      );
    });

    test('a date without xsi:type, with an offset or a date only reads', () {
      final XlsxWorkbook book = XlsxWorkbook.open(
        _package(
          parts: <String, String>{
            'docProps/core.xml': _core(
              '<dcterms:created>2026-10-24T09:30:00Z</dcterms:created>'
              '<dcterms:modified xsi:type="dcterms:W3CDTF">'
              '2026-10-24T11:30:00+02:00</dcterms:modified>',
            ),
          },
        ),
      );
      expect(book.properties.created, DateTime.utc(2026, 10, 24, 9, 30));
      expect(book.properties.modified, DateTime.utc(2026, 10, 24, 9, 30));
      expect(book.warnings, isEmpty);
    });

    test('a part under another name is found by its relationship', () {
      final String core = _core('<dc:title>Found</dc:title>');
      final Map<String, Uint8List> all = readXlsxBytes(
        (XlsxWorkbook()..addSheet('S')).save().bytes,
      );
      final Uint8List bytes = buildZipOrdered(<(String, List<int>)>[
        for (final MapEntry<String, Uint8List> p in all.entries)
          if (p.key == 'docProps/core.xml')
            ('meta/info.xml', utf8.encode(core))
          else if (p.key == '_rels/.rels')
            (
              p.key,
              utf8.encode(
                utf8
                    .decode(p.value)
                    .replaceFirst('docProps/core.xml', 'meta/info.xml'),
              ),
            )
          else if (p.key == '[Content_Types].xml')
            (
              p.key,
              utf8.encode(
                utf8
                    .decode(p.value)
                    .replaceFirst('/docProps/core.xml', '/meta/info.xml'),
              ),
            )
          else
            (p.key, p.value),
      ]);
      final XlsxWorkbook book = XlsxWorkbook.open(bytes);
      expect(book.properties.title, 'Found');
      book.properties = const OfficeProperties(title: 'Changed');
      final Map<String, String> saved = readXlsx(book.save().bytes);
      expect(saved['meta/info.xml'], contains('Changed'));
      expect(saved.containsKey('docProps/core.xml'), isFalse);
    });

    test('a part that is not XML throws when read, not before', () {
      final Uint8List bytes = _package(
        parts: <String, String>{'docProps/core.xml': '<cp:core'},
      );
      final XlsxWorkbook book = XlsxWorkbook.open(bytes);
      expect(() => book.properties, throwsA(isA<XlsxReadException>()));
      expect(
        readXlsxBytes(book.save().bytes)['docProps/core.xml'],
        readXlsxBytes(bytes)['docProps/core.xml'],
      );
    });

    test('a part with another root reads as nothing and is kept', () {
      final Uint8List bytes = _package(
        parts: <String, String>{
          'docProps/core.xml': '<other xmlns="urn:x"><a/></other>',
        },
      );
      final XlsxWorkbook book = XlsxWorkbook.open(bytes);
      expect(book.properties, const OfficeProperties());
      expect(comparePackages(bytes, book.save().bytes), isEmpty);
      expect(
        () => book.properties = const OfficeProperties(title: 'T'),
        throwsStateError,
      );
      expect(book.properties, const OfficeProperties());
      expect(comparePackages(bytes, book.save().bytes), isEmpty);
    });

    test('bad values are kept and reported', () {
      final Uint8List bytes = _package(
        parts: <String, String>{
          'docProps/core.xml': _core(
            '<dc:title>Fine</dc:title>'
            '<dcterms:created xsi:type="dcterms:W3CDTF">yesterday'
            '</dcterms:created>',
          ),
          'docProps/custom.xml': _custom(
            _prop(2, 'Count', '<vt:i4>abc</vt:i4>') +
                _prop(3, 'Ok', '<vt:i4>7</vt:i4>') +
                _prop(4, 'Flag', '<vt:bool>maybe</vt:bool>') +
                _prop(5, 'Big', '<vt:i4>99999999999</vt:i4>') +
                _prop(6, 'Nan', '<vt:r8>NaN</vt:r8>'),
          ),
        },
        rels: _customRel,
        types: _customType,
      );
      final XlsxWorkbook book = XlsxWorkbook.open(bytes);
      expect(
        book.properties,
        const OfficeProperties(
          title: 'Fine',
          custom: <String, Object>{'Ok': 7},
        ),
      );
      final List<String?> details = <String?>[
        for (final XlsxWarning w in book.warnings)
          if (w.code == XlsxWarningCode.featureEntryInvalid) w.detail,
      ];
      expect(details, contains('dcterms:created'));
      expect(details, contains('vt:i4'));
      expect(details, contains('vt:bool'));
      expect(details, contains('vt:r8'));
      // Reading again reports nothing new.
      final int count = book.warnings.length;
      book.properties;
      expect(book.warnings.length, count);
      expect(comparePackages(bytes, book.save().bytes), isEmpty);
      book.properties = const OfficeProperties(
        title: 'New',
        custom: <String, Object>{'Ok': 7},
      );
      final String saved = _part(book, 'docProps/core.xml');
      expect(saved, contains('New'));
      expect(saved, contains('yesterday'));
      expect(_part(book, 'docProps/custom.xml'), contains('abc'));
    });

    test('a duplicate custom name keeps the first in the map', () {
      final XlsxWorkbook book = XlsxWorkbook.open(
        _withCustom(
          _prop(2, 'Dup', '<vt:lpwstr>one</vt:lpwstr>') +
              _prop(3, 'dup', '<vt:lpwstr>two</vt:lpwstr>') +
              _prop(4, 'Dup', '<vt:lpwstr>three</vt:lpwstr>'),
        ),
      );
      expect(book.properties.custom, <String, Object>{'Dup': 'one'});
      final String before = _part(book, 'docProps/custom.xml');
      expect(before, contains('two'));
      expect(before, contains('three'));
      book.properties = const OfficeProperties(
        custom: <String, Object>{'Dup': 'uno'},
      );
      final String after = _part(book, 'docProps/custom.xml');
      expect(after, contains('uno'));
      expect(after, contains('two'));
      expect(after, contains('three'));
      expect(after, isNot(contains('>one<')));
    });

    test('a huge custom part is bounded by the limits', () {
      final String many = <String>[
        for (int i = 0; i < 30; i++)
          _prop(i + 2, 'P$i', '<vt:lpwstr>x</vt:lpwstr>'),
      ].join();
      final XlsxWorkbook book = XlsxWorkbook.open(
        _withCustom(many),
        limits: const XlsxReadLimits(maxSheets: 10),
      );
      expect(
        () => book.properties,
        throwsA(
          isA<XlsxReadException>().having(
            (XlsxReadException e) => e.reason,
            'reason',
            XlsxReadFailure.limitExceeded,
          ),
        ),
      );
      final XlsxWorkbook text = XlsxWorkbook.open(
        _withCustom(_prop(2, 'Long', '<vt:lpwstr>${'a' * 50}</vt:lpwstr>')),
        limits: const XlsxReadLimits(maxTextLength: 10),
      );
      expect(() => text.properties, throwsA(isA<XlsxReadException>()));
    });
  });

  group('setting', () {
    test('set writes what the writer writes', () {
      for (final String name in <String>['m3_properties', 'm1_properties']) {
        final XlsxWorkbook source = XlsxWorkbook.open(_fixture(name));
        final OfficeProperties value = source.properties;
        final XlsxWorkbook book = XlsxWorkbook()..addSheet(_sheetOf(name));
        book.properties = value;
        expect(book.properties, value);
        expect(
          _propertyDifferences(_fixture(name), book.save().bytes),
          isEmpty,
          reason: name,
        );
      }
    });

    test('an unchanged file keeps its parts', () {
      final Uint8List input = _fixture('m3_properties');
      final XlsxWorkbook unread = XlsxWorkbook.open(input);
      final Map<String, Uint8List> before = readXlsxBytes(input);
      final Map<String, Uint8List> after = readXlsxBytes(unread.save().bytes);
      for (final String part in <String>[
        'docProps/core.xml',
        'docProps/app.xml',
        'docProps/custom.xml',
      ]) {
        expect(after[part], before[part], reason: part);
      }
      final XlsxWorkbook read = XlsxWorkbook.open(input);
      read.properties;
      expect(comparePackages(input, read.save().bytes), isEmpty);
      // The same value is no edit.
      final ChangeLog log = changeLogOf(read);
      read.properties = _m3;
      expect(log.hasChanges, isFalse);
    });

    test('other elements stay', () {
      final Uint8List bytes = _package(
        parts: <String, String>{
          'docProps/core.xml': _core(
            '<dc:title>Old</dc:title><dc:language>tr-TR</dc:language>'
            '<cp:revision>7</cp:revision>',
          ),
          'docProps/app.xml': _app(
            '<Application>Microsoft Excel</Application>'
            '<TitlesOfParts><vt:vector xmlns:vt="$_vtNs" size="1" '
            'baseType="lpstr"><vt:lpstr>S</vt:lpstr></vt:vector>'
            '</TitlesOfParts><Company>Old Co</Company>',
          ),
        },
      );
      final XlsxWorkbook book = XlsxWorkbook.open(bytes);
      book.properties = const OfficeProperties(
        title: 'New',
        creator: 'Me',
        company: 'New Co',
        manager: 'Boss',
      );
      final String core = _part(book, 'docProps/core.xml');
      expect(core, contains('<dc:title>New</dc:title>'));
      expect(core, contains('<dc:language>tr-TR</dc:language>'));
      expect(core, contains('<cp:revision>7</cp:revision>'));
      expect(core.indexOf('dc:title'), lessThan(core.indexOf('dc:language')));
      expect(core, contains('dc:creator'));
      final String app = _part(book, 'docProps/app.xml');
      expect(app, contains('Microsoft Excel'));
      expect(app, contains('TitlesOfParts'));
      expect(app, contains('<Company>New Co</Company>'));
      expect(app, contains('<Manager>Boss</Manager>'));
      expect(app, isNot(contains('Old Co')));
      // A null field's element goes, the others stay.
      book.properties = const OfficeProperties(creator: 'Me');
      final String cleared = _part(book, 'docProps/core.xml');
      expect(cleared, isNot(contains('dc:title')));
      expect(cleared, contains('dc:language'));
      expect(_part(book, 'docProps/app.xml'), isNot(contains('Company')));
      expect(_part(book, 'docProps/app.xml'), contains('TitlesOfParts'));
    });

    test('a root attribute keeps its one declaration', () {
      const String mc =
          'http://schemas.openxmlformats.org/markup-compatibility/2006';
      final Map<String, Uint8List> parts = readXlsxBytes(
        _fixture('m3_properties'),
      );
      parts['docProps/core.xml'] = Uint8List.fromList(
        utf8.encode(
          _core('<dc:title>t</dc:title>').replaceFirst(
            '<cp:coreProperties ',
            '<cp:coreProperties xmlns:mc="$mc" mc:Ignorable="dc" ',
          ),
        ),
      );
      final XlsxWorkbook book = XlsxWorkbook.open(
        buildZip(<String, List<int>>{...parts}),
      );
      book.properties = const OfficeProperties(title: 'New');
      final Uint8List saved = book.save().bytes;
      final String core = readXlsx(saved)['docProps/core.xml']!;
      expect(RegExp('xmlns:mc=').allMatches(core), hasLength(1));
      expect(core, contains('mc:Ignorable="dc"'));
      expect(XlsxWorkbook.open(saved).properties.title, 'New');
    });

    test('modified and lastModifiedBy are not touched by a save', () {
      final XlsxWorkbook book = XlsxWorkbook.open(_fixture('m3_properties'));
      book.sheets.first.setCell(5, 1, 'x');
      final OfficeProperties saved = XlsxWorkbook.open(
        book.save().bytes,
      ).properties;
      expect(saved.modified, _m3.modified);
      expect(saved.lastModifiedBy, _m3.lastModifiedBy);
    });

    test('custom part joins and leaves', () {
      final XlsxWorkbook book = XlsxWorkbook()..addSheet('S');
      final Map<String, String> plain = readXlsx(book.save().bytes);
      expect(plain.containsKey('docProps/custom.xml'), isFalse);
      book.properties = const OfficeProperties(
        custom: <String, Object>{'A': 1, 'B': 'two'},
      );
      for (int i = 0; i < 2; i++) {
        final Map<String, String> parts = readXlsx(book.save().bytes);
        expect(parts['docProps/custom.xml'], contains('name="B"'));
        expect(parts['_rels/.rels'], contains('custom-properties'));
        expect(parts['_rels/.rels'], contains('docProps/custom.xml'));
        expect(parts['[Content_Types].xml'], contains('/docProps/custom.xml'));
      }
      book.properties = const OfficeProperties();
      for (int i = 0; i < 2; i++) {
        final Map<String, String> parts = readXlsx(book.save().bytes);
        expect(parts.containsKey('docProps/custom.xml'), isFalse);
        expect(parts['_rels/.rels'], isNot(contains('custom-properties')));
        expect(
          parts['[Content_Types].xml'],
          isNot(contains('/docProps/custom.xml')),
        );
      }
      expect(
        comparePackages(
          (XlsxWorkbook()..addSheet('S')).save().bytes,
          book.save().bytes,
        ),
        isEmpty,
      );
    });

    test('custom part of a file that holds none stays when untouched', () {
      final Uint8List bytes = _withCustom('');
      final XlsxWorkbook book = XlsxWorkbook.open(bytes);
      expect(book.properties.custom, isEmpty);
      expect(comparePackages(bytes, book.save().bytes), isEmpty);
    });

    test('a custom part leaves when no property is left', () {
      final XlsxWorkbook book = XlsxWorkbook.open(
        _withCustom(_prop(2, 'A', '<vt:lpwstr>x</vt:lpwstr>')),
      );
      book.properties = const OfficeProperties();
      expect(
        readXlsx(book.save().bytes).containsKey('docProps/custom.xml'),
        isFalse,
      );
    });

    test('a custom part holding a kept property stays', () {
      final XlsxWorkbook book = XlsxWorkbook.open(
        _withCustom(
          _prop(2, 'A', '<vt:lpwstr>x</vt:lpwstr>') +
              _prop(3, 'D', '<vt:decimal>1.5</vt:decimal>'),
        ),
      );
      book.properties = const OfficeProperties();
      final String custom = _part(book, 'docProps/custom.xml');
      expect(custom, contains('vt:decimal'));
      expect(custom, isNot(contains('name="A"')));
    });

    test('other variants stay kept and unlisted', () {
      final XlsxWorkbook book = XlsxWorkbook.open(
        _withCustom(
          _prop(2, 'Text', '<vt:lpwstr>x</vt:lpwstr>') +
              _prop(3, 'Dec', '<vt:decimal>1.5</vt:decimal>') +
              _prop(5, 'Big', '<vt:i8>9</vt:i8>', fmtid: '{OTHER}') +
              _prop(
                7,
                'Vec',
                '<vt:vector size="1" baseType="lpstr"><vt:lpstr>q</vt:lpstr>'
                    '</vt:vector>',
              ),
        ),
      );
      expect(book.properties.custom, <String, Object>{'Text': 'x'});
      expect(book.warnings, isEmpty);
      book.properties = const OfficeProperties(
        custom: <String, Object>{'Text': 'x', 'New': 1, 'New2': true},
      );
      final String custom = _part(book, 'docProps/custom.xml');
      expect(custom, contains('<vt:decimal>1.5</vt:decimal>'));
      expect(custom, contains('{OTHER}'));
      expect(custom, contains('<vt:vector'));
      // The kept property keeps its pid; new ones take the lowest free.
      expect(custom, contains('pid="2" name="Text"'));
      expect(custom, contains('pid="4" name="New"'));
      expect(custom, contains('pid="6" name="New2"'));
      final XlsxWorkbook again = XlsxWorkbook.open(book.save().bytes);
      expect(again.properties.custom, <String, Object>{
        'Text': 'x',
        'New': 1,
        'New2': true,
      });
    });

    test('a bad value throws and nothing changes', () {
      final Uint8List input = _fixture('m3_properties');
      final XlsxWorkbook book = XlsxWorkbook.open(input);
      final ChangeLog log = changeLogOf(book);
      for (final OfficeProperties bad in <OfficeProperties>[
        const OfficeProperties(title: 'a\u0000b'),
        const OfficeProperties(company: 'a\u0001'),
        const OfficeProperties(custom: <String, Object>{'': 1}),
        const OfficeProperties(custom: <String, Object>{'A': 1, 'a': 2}),
        const OfficeProperties(custom: <String, Object>{'A': double.nan}),
        const OfficeProperties(custom: <String, Object>{'A': Object()}),
      ]) {
        expect(() => book.properties = bad, throwsArgumentError);
      }
      expect(log.hasChanges, isFalse);
      expect(book.properties, _m3);
      expect(comparePackages(input, book.save().bytes), isEmpty);
    });

    test('undo restores the properties', () {
      final Uint8List input = _fixture('m3_properties');
      final XlsxWorkbook book = XlsxWorkbook.open(input);
      final ChangeLog log = changeLogOf(book);
      final ChangeSet set = log.transaction(() {
        book.properties = const OfficeProperties(
          title: 'Other',
          custom: <String, Object>{'Z': 1},
        );
      });
      expect(book.properties.title, 'Other');
      log.revertSet(set);
      expect(book.properties, _m3);
      expect(comparePackages(input, book.save().bytes), isEmpty);
      log.reapplySet(set);
      expect(book.properties.title, 'Other');
      expect(_part(book, 'docProps/custom.xml'), contains('name="Z"'));
    });

    test('save, undo, save', () {
      final XlsxWorkbook book = XlsxWorkbook()..addSheet('S');
      final Uint8List empty = book.save().bytes;
      final ChangeLog log = changeLogOf(book);
      final ChangeSet set = log.transaction(() {
        book.properties = const OfficeProperties(
          title: 'T',
          custom: <String, Object>{'A': 1},
        );
      });
      expect(readXlsx(book.save().bytes)['docProps/custom.xml'], isNotNull);
      log.revertSet(set);
      expect(comparePackages(empty, book.save().bytes), isEmpty);
      log.reapplySet(set);
      final Map<String, String> parts = readXlsx(book.save().bytes);
      expect(parts['docProps/custom.xml'], contains('name="A"'));
      expect(parts['docProps/core.xml'], contains('<dc:title>T</dc:title>'));
    });

    test('a changed value keeps its place in the map order', () {
      final XlsxWorkbook book = XlsxWorkbook.open(_fixture('m3_properties'));
      final OfficeProperties value = OfficeProperties(
        custom: <String, Object>{
          'Due': DateTime.utc(2027),
          'Project': 'Atlas',
          'Extra': 9.5,
        },
      );
      book.properties = value;
      expect(book.properties.custom, value.custom);
      expect(
        XlsxWorkbook.open(book.save().bytes).properties.custom,
        value.custom,
      );
    });
  });
}

String _sheetOf(String name) => name == 'm3_properties' ? 'Info' : 'Props';
