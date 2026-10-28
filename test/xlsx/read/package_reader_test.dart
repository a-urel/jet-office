import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/src/xlsx/read/package_reader.dart';
import 'package:jet_office/src/xlsx/read/read_exception.dart';
import 'package:jet_office/src/xlsx/read/read_limits.dart';
import 'package:test/test.dart';

import 'support/zip_builder.dart';

const String _rel =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const String _strictRel =
    'http://purl.oclc.org/ooxml/officeDocument/relationships';
const String _mainType =
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml';

List<int> _utf8(String s) => utf8.encode(s);

String _types({String? workbookPart, String type = _mainType}) =>
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
    '<Default Extension="xml" ContentType="application/xml"/>'
    '${workbookPart == null ? '' : '<Override PartName="/$workbookPart" ContentType="$type"/>'}'
    '</Types>';

String _rels(
  Map<String, (String, String)> rels, {
  Set<String> external = const <String>{},
}) =>
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '${rels.entries.map((e) => '<Relationship Id="${e.key}" Type="${e.value.$1}" Target="${e.value.$2}"${external.contains(e.key) ? ' TargetMode="External"' : ''}/>').join()}'
    '</Relationships>';

PackageReader _package(
  Map<String, String> parts, {
  XlsxReadLimits limits = const XlsxReadLimits(),
}) => PackageReader(
  buildZip(<String, List<int>>{
    for (final MapEntry<String, String> e in parts.entries)
      e.key: _utf8(e.value),
  }),
  limits,
);

XlsxReadException _failure(void Function() body) {
  try {
    body();
  } on XlsxReadException catch (e) {
    return e;
  }
  throw StateError('expected an XlsxReadException');
}

void main() {
  group('workbook part and targets', () {
    test('finds a workbook through the root relationship, wherever it is', () {
      final PackageReader p = _package(<String, String>{
        '[Content_Types].xml': _types(),
        '_rels/.rels': _rels(<String, (String, String)>{
          'rId1': ('$_rel/officeDocument', 'data/wb.xml'),
        }),
        'data/wb.xml': '<workbook/>',
        'data/_rels/wb.xml.rels': _rels(
          <String, (String, String)>{
            'rId1': ('$_rel/worksheet', '../sheets/s1.xml'),
            'rId2': ('$_rel/worksheet', '/sheets/s2.xml'),
            'rId3': ('$_rel/hyperlink', 'https://example.com'),
          },
          external: <String>{'rId3'},
        ),
        'sheets/s1.xml': '<worksheet/>',
        'Sheets\\S2.xml': '<worksheet/>',
      });
      expect(p.workbookPart, 'data/wb.xml');
      final List<PartRelationship> rels = p.relationshipsOf('data/wb.xml');
      expect(
        rels.map((PartRelationship r) => (r.id, r.type, r.target)).toList(),
        <(String, String, String)>[
          ('rId1', '$_rel/worksheet', 'sheets/s1.xml'),
          ('rId2', '$_rel/worksheet', 'sheets/s2.xml'),
        ],
      );
      expect(p.hasPart('sheets/s2.xml'), isTrue);
      expect(p.hasPart('SHEETS/s1.xml'), isTrue);
      expect(p.hasPart('sheets/s3.xml'), isFalse);
    });

    test('accepts a root relationship target with a leading slash', () {
      final PackageReader p = _package(<String, String>{
        '_rels/.rels': _rels(<String, (String, String)>{
          'rId1': ('$_rel/officeDocument', '/xl/workbook.xml'),
        }),
        'xl/workbook.xml': '<workbook/>',
      });
      expect(p.workbookPart, 'xl/workbook.xml');
    });

    test('a part without relationships has none', () {
      final PackageReader p = _package(<String, String>{
        '_rels/.rels': _rels(<String, (String, String)>{
          'rId1': ('$_rel/officeDocument', 'xl/workbook.xml'),
        }),
        'xl/workbook.xml': '<workbook/>',
      });
      expect(p.relationshipsOf('xl/workbook.xml'), isEmpty);
    });

    test('retries a target percent-decoded', () {
      final PackageReader p = _package(<String, String>{
        '_rels/.rels': _rels(<String, (String, String)>{
          'rId1': ('$_rel/officeDocument', 'xl/workbook.xml'),
        }),
        'xl/workbook.xml': '<workbook/>',
        'xl/_rels/workbook.xml.rels': _rels(<String, (String, String)>{
          'rId1': ('$_rel/worksheet', 'worksheets/my%20sheet.xml'),
        }),
        'xl/worksheets/my sheet.xml': '<worksheet/>',
      });
      expect(
        p.relationshipsOf('xl/workbook.xml').single.target,
        'xl/worksheets/my sheet.xml',
      );
    });

    test('keeps the literal name for an invalid percent-encoding', () {
      for (final String bad in <String>[
        '%FF.xml',
        'a%C3.xml',
        '%zz.xml',
        '%',
      ]) {
        final PackageReader p = _package(<String, String>{
          '_rels/.rels': _rels(<String, (String, String)>{
            'rId1': ('$_rel/officeDocument', 'xl/workbook.xml'),
            'rId2': ('$_rel/worksheet', bad),
          }),
          'xl/workbook.xml': '<workbook/>',
          'xl/_rels/workbook.xml.rels': _rels(<String, (String, String)>{
            'rId1': ('$_rel/worksheet', bad),
          }),
        });
        expect(p.workbookPart, 'xl/workbook.xml', reason: bad);
        expect(
          p.relationshipsOf('xl/workbook.xml').single.target,
          'xl/$bad',
          reason: bad,
        );
        expect(
          p.relationshipsOf('').map((r) => r.target),
          contains(bad),
          reason: bad,
        );
      }
    });

    test('falls back to the content type override', () {
      final PackageReader p = _package(<String, String>{
        '[Content_Types].xml': _types(workbookPart: 'xl/book.xml'),
        'xl/book.xml': '<workbook/>',
      });
      expect(p.workbookPart, 'xl/book.xml');
    });

    test('falls back when the root relationship points at nothing', () {
      final PackageReader p = _package(<String, String>{
        '[Content_Types].xml': _types(workbookPart: 'xl/book.xml'),
        '_rels/.rels': _rels(<String, (String, String)>{
          'rId1': ('$_rel/officeDocument', 'gone.xml'),
        }),
        'xl/book.xml': '<workbook/>',
      });
      expect(p.workbookPart, 'xl/book.xml');
    });

    test('macro-enabled and template workbooks are workbooks', () {
      for (final String type in <String>[
        'application/vnd.ms-excel.sheet.macroEnabled.main+xml',
        'application/vnd.openxmlformats-officedocument.spreadsheetml.template.main+xml',
      ]) {
        final PackageReader p = _package(<String, String>{
          '[Content_Types].xml': _types(
            workbookPart: 'xl/book.xml',
            type: type,
          ),
          'xl/book.xml': '<workbook/>',
        });
        expect(p.workbookPart, 'xl/book.xml', reason: type);
      }
    });

    test('no workbook is missingWorkbook', () {
      final XlsxReadException e = _failure(
        () => _package(<String, String>{
          '[Content_Types].xml': _types(),
          'docs/readme.txt': 'hi',
        }),
      );
      expect(e.reason, XlsxReadFailure.missingWorkbook);
    });

    test('refuses Strict and .xlsb as unsupportedFormat', () {
      final XlsxReadException strict = _failure(
        () => _package(<String, String>{
          '_rels/.rels': _rels(<String, (String, String)>{
            'rId1': ('$_strictRel/officeDocument', 'xl/workbook.xml'),
          }),
          'xl/workbook.xml': '<workbook/>',
        }),
      );
      expect(strict.reason, XlsxReadFailure.unsupportedFormat);
      expect(strict.message, contains('Strict'));

      final XlsxReadException xlsb = _failure(
        () => _package(<String, String>{
          '[Content_Types].xml': _types(
            workbookPart: 'xl/workbook.bin',
            type: 'application/vnd.ms-excel.sheet.binary.macroEnabled.main',
          ),
          '_rels/.rels': _rels(<String, (String, String)>{
            'rId1': ('$_rel/officeDocument', 'xl/workbook.bin'),
          }),
          'xl/workbook.bin': 'x',
        }),
      );
      expect(xlsb.reason, XlsxReadFailure.unsupportedFormat);
      expect(xlsb.message, contains('.xlsb'));
    });
  });

  group('errors', () {
    test('maps a DOCTYPE to malformedXml naming the part', () {
      final PackageReader p = _package(<String, String>{
        '_rels/.rels': _rels(<String, (String, String)>{
          'rId1': ('$_rel/officeDocument', 'xl/workbook.xml'),
        }),
        'xl/workbook.xml': '<!DOCTYPE x [<!ENTITY a "b">]><workbook/>',
      });
      final XlsxReadException e = _failure(
        () => p.guardXml<void>('xl/workbook.xml', () {
          final reader = p.openXml('xl/workbook.xml');
          while (reader.next()) {}
        }),
      );
      expect(e.reason, XlsxReadFailure.malformedXml);
      expect(e.part, 'xl/workbook.xml');
    });

    test('maps a deep document to limitExceeded naming maxDepth', () {
      final PackageReader p = _package(<String, String>{
        '_rels/.rels': _rels(<String, (String, String)>{
          'rId1': ('$_rel/officeDocument', 'wb.xml'),
        }),
        'wb.xml': '${'<a>' * 10}${'</a>' * 10}',
      }, limits: const XlsxReadLimits(maxDepth: 5));
      final XlsxReadException e = _failure(
        () => p.guardXml<void>('wb.xml', () {
          final reader = p.openXml('wb.xml');
          while (reader.next()) {}
        }),
      );
      expect(e.reason, XlsxReadFailure.limitExceeded);
      expect(e.message, contains('maxDepth'));
      expect(e.part, 'wb.xml');
    });

    test('guardXml maps errors that surface late, such as a bad entity', () {
      final PackageReader p = _package(<String, String>{
        '_rels/.rels': _rels(<String, (String, String)>{
          'rId1': ('$_rel/officeDocument', 'wb.xml'),
        }),
        'wb.xml': '<a>&bogus;</a>',
      });
      final reader = p.openXml('wb.xml');
      final XlsxReadException e = _failure(
        () => p.guardXml<int>('wb.xml', () {
          reader.nextTag();
          reader.next();
          return reader.text.length;
        }),
      );
      expect(e.reason, XlsxReadFailure.malformedXml);
      expect(e.part, 'wb.xml');
      expect(p.guardXml('x', () => 7), 7);
    });

    test('a malformed relationship file names the .rels part', () {
      final XlsxReadException e = _failure(
        () => _package(<String, String>{'_rels/.rels': '<Relationships>'}),
      );
      expect(e.reason, XlsxReadFailure.malformedXml);
      expect(e.part, '_rels/.rels');

      final PackageReader p = _package(<String, String>{
        '_rels/.rels': _rels(<String, (String, String)>{
          'rId1': ('$_rel/officeDocument', 'xl/workbook.xml'),
        }),
        'xl/workbook.xml': '<workbook/>',
        'xl/_rels/workbook.xml.rels': '<Relationships><Relationship',
      });
      final XlsxReadException e2 = _failure(
        () => p.relationshipsOf('xl/workbook.xml'),
      );
      expect(e2.reason, XlsxReadFailure.malformedXml);
      expect(e2.part, 'xl/_rels/workbook.xml.rels');
    });

    test('maps ZIP errors to XlsxReadException reasons', () {
      XlsxReadFailure reasonOf(Uint8List bytes, [XlsxReadLimits? l]) =>
          _failure(
            () => PackageReader(bytes, l ?? const XlsxReadLimits()),
          ).reason;

      expect(
        reasonOf(Uint8List.fromList(_utf8('not a zip at all'))),
        XlsxReadFailure.notZip,
      );

      final List<int> ole = <int>[
        0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1, //
        ...List<int>.filled(64, 0),
      ];
      expect(reasonOf(Uint8List.fromList(ole)), XlsxReadFailure.legacyXls);
      final List<int> enc = <int>[
        ...ole,
        for (final int u in 'EncryptedPackage'.codeUnits) ...<int>[u, 0],
      ];
      expect(reasonOf(Uint8List.fromList(enc)), XlsxReadFailure.encrypted);

      final Uint8List two = buildZip(<String, List<int>>{
        'a.xml': _utf8('<a/>'),
        'b.xml': _utf8('<b/>'),
      });
      expect(
        reasonOf(two, const XlsxReadLimits(maxEntries: 1)),
        XlsxReadFailure.limitExceeded,
      );
      expect(
        reasonOf(two, const XlsxReadLimits(maxEntryBytes: 1)),
        XlsxReadFailure.limitExceeded,
      );
      expect(
        reasonOf(two, const XlsxReadLimits(maxTotalBytes: 5)),
        XlsxReadFailure.limitExceeded,
      );
      expect(
        reasonOf(
          buildZip(<String, List<int>>{
            'a.xml': _utf8('<a/>'),
            'A.XML': _utf8('<a/>'),
          }),
        ),
        XlsxReadFailure.corruptZip,
      );
    });

    test('limitExceeded messages name the limit', () {
      final Uint8List two = buildZip(<String, List<int>>{
        'a.xml': _utf8('<a/>'),
        'b.xml': _utf8('<b/>'),
      });
      final XlsxReadException e = _failure(
        () => PackageReader(two, const XlsxReadLimits(maxEntries: 1)),
      );
      expect(e.message, contains('maxEntries'));
    });

    test('a ratio refusal is limitExceeded naming maxCompressionRatio', () {
      final Uint8List zip = buildZip(<String, List<int>>{
        'wb.xml': List<int>.filled(2 * 1024 * 1024, 65),
      });
      final XlsxReadException e = _failure(
        () =>
            PackageReader(zip, const XlsxReadLimits(maxCompressionRatio: 100)),
      );
      expect(e.reason, XlsxReadFailure.limitExceeded);
      expect(e.message, contains('maxCompressionRatio'));
    });

    test('a corrupt entry read through openXml is corruptZip', () {
      final Uint8List zip = buildZip(<String, List<int>>{
        '_rels/.rels': _utf8(
          _rels(<String, (String, String)>{
            'rId1': ('$_rel/officeDocument', 'wb.xml'),
          }),
        ),
        'wb.xml': _utf8('<workbook/>'),
      }, store: true);
      final PackageReader ok = PackageReader(zip, const XlsxReadLimits());
      expect(ok.openXml('wb.xml').next(), isTrue);
      final Uint8List bad = patchDeclaredSize(zip, 'wb.xml', 3);
      final XlsxReadException e = _failure(
        () => PackageReader(bad, const XlsxReadLimits()).openXml('wb.xml'),
      );
      expect(e.reason, XlsxReadFailure.corruptZip);
      expect(e.part, 'wb.xml');
    });
  });
}
