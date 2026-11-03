import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

import 'support/workbook_builder.dart';
import 'support/zip_builder.dart';

/// Where [XlsxWorkbook] meets a hostile file that [XlsxReader] refuses.
enum _Model {
  /// [XlsxWorkbook.open] throws: the package skeleton or the workbook part
  /// is hostile, a limit read from the central directory is exceeded, or an
  /// entry does not inflate to its declared size and CRC-32 (`open` checks
  /// every entry, where the reader checks a part when it reads it).
  open,

  /// `open` succeeds and the first sheet access throws: the hostility is in
  /// the XML of a part the model, like the reader, parses only then (a
  /// worksheet, the shared strings or the styles). Saving still works: the
  /// part is copied from its bytes.
  sheet,

  /// The model opens, reads and saves the file: the hostility is in
  /// something the model keeps opaque in W1. Only `maxMerges`: the merges
  /// stay opaque until W2, so the model does not apply that limit; their XML
  /// stays bounded by the size, depth and text limits.
  accepts,
}

/// Drives the whole public surface over [bytes] (open, every sheet's rows
/// and merges) and requires an [XlsxReadException] of [reason], whose
/// message names [limit] when given.
///
/// Then opens [bytes] with [XlsxWorkbook] and requires what [model] says:
/// an [XlsxReadException] of the same [reason] (naming [limit]) from `open`
/// or from the first sheet's rows, or no exception; either way past `open`,
/// the workbook saves.
void _expectRefused(
  Uint8List bytes,
  XlsxReadFailure reason, {
  required _Model model,
  String? limit,
  XlsxReadLimits limits = const XlsxReadLimits(),
}) {
  Object? caught;
  try {
    final XlsxReader reader = XlsxReader(bytes, limits: limits);
    for (int i = 0; i < reader.sheets.length; i++) {
      reader.rowsAt(i).toList();
      reader.mergesAt(i);
    }
  } on Object catch (error) {
    caught = error;
  }
  expect(caught, isA<XlsxReadException>(), reason: 'threw $caught');
  final XlsxReadException e = caught! as XlsxReadException;
  expect(e.reason, reason, reason: e.message);
  if (limit != null) expect(e.message, contains(limit));
  _expectModel(bytes, reason, model, limit, limits);
}

void _expectModel(
  Uint8List bytes,
  XlsxReadFailure reason,
  _Model model,
  String? limit,
  XlsxReadLimits limits,
) {
  void expectReason(Object? error, String where) {
    expect(error, isA<XlsxReadException>(), reason: '$where threw $error');
    final XlsxReadException e = error! as XlsxReadException;
    expect(e.reason, reason, reason: '$where: ${e.message}');
    if (limit != null) expect(e.message, contains(limit));
  }

  final XlsxWorkbook workbook;
  try {
    workbook = XlsxWorkbook.open(bytes, limits: limits);
  } on Object catch (error) {
    expect(model, _Model.open, reason: 'open threw $error');
    expectReason(error, 'open');
    return;
  }
  expect(model, isNot(_Model.open), reason: 'open did not throw');
  Object? caught;
  try {
    workbook.sheets.first.rows.toList();
  } on Object catch (error) {
    caught = error;
  }
  if (model == _Model.sheet) {
    expectReason(caught, 'the first sheet');
  } else {
    expect(caught, isNull, reason: 'the first sheet threw $caught');
    for (final XlsxSheet sheet in workbook.sheets) {
      sheet.rows.toList();
    }
  }
  expect(workbook.save().bytes, isNotEmpty);
}

const String _rel =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const String _pkgRel =
    'http://schemas.openxmlformats.org/package/2006/relationships';
const String _wbType =
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml';

/// The entries of a one-sheet package, with [overrides] replacing or
/// adding entries by name.
Map<String, List<int>> _entries({
  String rows = '<row r="1"><c r="A1"><v>1</v></c></row>',
  Map<String, List<int>> overrides = const <String, List<int>>{},
}) => <String, List<int>>{
  '[Content_Types].xml': utf8.encode(
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/'
    'content-types"><Override PartName="/xl/workbook.xml" '
    'ContentType="$_wbType"/></Types>',
  ),
  '_rels/.rels': utf8.encode(
    '<Relationships xmlns="$_pkgRel"><Relationship Id="rId1" '
    'Type="$_rel/officeDocument" Target="xl/workbook.xml"/></Relationships>',
  ),
  'xl/workbook.xml': utf8.encode(
    '<workbook xmlns="$mainNs" xmlns:r="$_rel"><sheets>'
    '<sheet name="S" sheetId="1" r:id="rId1"/></sheets></workbook>',
  ),
  'xl/_rels/workbook.xml.rels': utf8.encode(
    '<Relationships xmlns="$_pkgRel"><Relationship Id="rId1" '
    'Type="$_rel/worksheet" Target="worksheets/sheet1.xml"/></Relationships>',
  ),
  'xl/worksheets/sheet1.xml': utf8.encode(worksheet(rows)),
  ...overrides,
};

String _styles(String numFmts, String xfs) =>
    '<styleSheet xmlns="$mainNs">$numFmts<cellXfs>$xfs</cellXfs></styleSheet>';

/// A little-endian UTF-16 encoding of [text] with a byte order mark.
List<int> _utf16le(String text) => <int>[
  0xFF,
  0xFE,
  for (final int u in text.codeUnits) ...<int>[u & 0xFF, u >> 8],
];

const List<int> _ole = <int>[0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1];

void main() {
  group('limits', () {
    test('maxEntries', () {
      final Uint8List zip = buildZip(<String, List<int>>{
        for (int i = 0; i < 11; i++) 'e$i.xml': utf8.encode('<a/>'),
      });
      _expectRefused(
        zip,
        XlsxReadFailure.limitExceeded,
        model: _Model.open,
        limit: 'maxEntries',
        limits: const XlsxReadLimits(maxEntries: 10),
      );
    });

    test('maxEntryBytes', () {
      final Uint8List zip = patchDeclaredSize(
        buildZip(_entries()),
        'xl/worksheets/sheet1.xml',
        1 << 30,
      );
      _expectRefused(
        zip,
        XlsxReadFailure.limitExceeded,
        model: _Model.open,
        limit: 'maxEntryBytes',
      );
    });

    test('maxTotalBytes', () {
      final Uint8List zip = buildZip(
        _entries(
          overrides: <String, List<int>>{
            for (int i = 0; i < 3; i++)
              'xl/pad$i.bin': List<int>.generate(
                1000,
                (int k) => (k * 7) % 256,
              ),
          },
        ),
      );
      _expectRefused(
        zip,
        XlsxReadFailure.limitExceeded,
        model: _Model.open,
        limit: 'maxTotalBytes',
        limits: const XlsxReadLimits(maxTotalBytes: 2500),
      );
    });

    test('maxCompressionRatio', () {
      final Uint8List zip = buildZip(
        _entries(
          overrides: <String, List<int>>{
            'xl/pad.bin': List<int>.filled(2 * 1024 * 1024, 65),
          },
        ),
      );
      _expectRefused(
        zip,
        XlsxReadFailure.limitExceeded,
        model: _Model.open,
        limit: 'maxCompressionRatio',
        limits: const XlsxReadLimits(maxCompressionRatio: 100),
      );
    });

    test('maxSharedStrings', () {
      final Uint8List zip = buildWorkbook(<String, String?>{
        'S': worksheet('<row r="1"><c r="A1" t="s"><v>0</v></c></row>'),
      }, sharedStrings: '<sst xmlns="$mainNs">${'<si/>' * 6}</sst>');
      _expectRefused(
        zip,
        XlsxReadFailure.limitExceeded,
        model: _Model.sheet,
        limit: 'maxSharedStrings',
        limits: const XlsxReadLimits(maxSharedStrings: 5),
      );
    });

    test('maxDepth', () {
      final Uint8List zip = buildZip(
        _entries(
          overrides: <String, List<int>>{
            'xl/worksheets/sheet1.xml': utf8.encode(
              '<worksheet xmlns="$mainNs"><sheetData>'
              '${'<x>' * 300}${'</x>' * 300}</sheetData></worksheet>',
            ),
          },
        ),
      );
      _expectRefused(
        zip,
        XlsxReadFailure.limitExceeded,
        model: _Model.sheet,
        limit: 'maxDepth',
      );
    });

    test('maxTextLength', () {
      const XlsxReadLimits limits = XlsxReadLimits(maxTextLength: 1000);
      final String long = 'x' * 1001;
      // A <v>.
      _expectRefused(
        buildWorkbook(<String, String?>{
          'S': worksheet('<row r="1"><c r="A1" t="str"><v>$long</v></c></row>'),
        }),
        XlsxReadFailure.limitExceeded,
        model: _Model.sheet,
        limit: 'maxTextLength',
        limits: limits,
      );
      // An <f>.
      _expectRefused(
        buildWorkbook(<String, String?>{
          'S': worksheet('<row r="1"><c r="A1"><f>$long</f><v>1</v></c></row>'),
        }),
        XlsxReadFailure.limitExceeded,
        model: _Model.sheet,
        limit: 'maxTextLength',
        limits: limits,
      );
      // A shared string.
      _expectRefused(
        buildWorkbook(<String, String?>{
          'S': worksheet('<row r="1"><c r="A1" t="s"><v>0</v></c></row>'),
        }, sharedStrings: '<sst xmlns="$mainNs"><si><t>$long</t></si></sst>'),
        XlsxReadFailure.limitExceeded,
        model: _Model.sheet,
        limit: 'maxTextLength',
        limits: limits,
      );
      // A formatCode.
      _expectRefused(
        buildWorkbook(
          <String, String?>{
            'S': worksheet('<row r="1"><c r="A1"><v>1</v></c></row>'),
          },
          styles: _styles(
            '<numFmts count="1"><numFmt numFmtId="164" '
                'formatCode="$long"/></numFmts>',
            '<xf numFmtId="164"/>',
          ),
        ),
        XlsxReadFailure.limitExceeded,
        model: _Model.sheet,
        limit: 'maxTextLength',
        limits: limits,
      );
    });

    test('maxSheets', () {
      final Uint8List zip = buildWorkbook(<String, String?>{
        for (int i = 0; i < 6; i++) 'S$i': worksheet(''),
      });
      _expectRefused(
        zip,
        XlsxReadFailure.limitExceeded,
        model: _Model.open,
        limit: 'maxSheets',
        limits: const XlsxReadLimits(maxSheets: 5),
      );
    });

    test('maxCellFormats', () {
      final Uint8List zip = buildWorkbook(<String, String?>{
        'S': worksheet(''),
      }, styles: _styles('', '<xf/>' * 6));
      _expectRefused(
        zip,
        XlsxReadFailure.limitExceeded,
        model: _Model.sheet,
        limit: 'maxCellFormats',
        limits: const XlsxReadLimits(maxCellFormats: 5),
      );
    });

    test('maxMerges', () {
      // The reader refuses it; the workbook model in W1 keeps the merges
      // opaque and so does not apply maxMerges (W2 types them): it opens,
      // reads and saves the file (_Model.accepts).
      final Uint8List zip = buildWorkbook(<String, String?>{
        'S':
            '<worksheet xmlns="$mainNs"><sheetData/><mergeCells>'
            '${'<mergeCell ref="A1:B2"/>' * 6}</mergeCells></worksheet>',
      });
      _expectRefused(
        zip,
        XlsxReadFailure.limitExceeded,
        model: _Model.accepts,
        limit: 'maxMerges',
        limits: const XlsxReadLimits(maxMerges: 5),
      );
    });
  });

  group('hostile', () {
    test('a size that lies low is corruptZip and costs under 2 s', () {
      final Uint8List zip = patchDeclaredSize(
        buildZip(_entries(rows: '<!--${'a' * (1024 * 1024)}-->')),
        'xl/worksheets/sheet1.xml',
        1000,
      );
      final Stopwatch watch = Stopwatch()..start();
      _expectRefused(zip, XlsxReadFailure.corruptZip, model: _Model.open);
      expect(watch.elapsedMilliseconds, lessThan(2000));
    });

    test('a CRC mismatch is corruptZip', () {
      final Uint8List zip = buildZip(_entries(), store: true);
      final List<int> needle = utf8.encode('<c r="A1">');
      int at = -1;
      for (int i = 0; i + needle.length <= zip.length && at < 0; i++) {
        bool same = true;
        for (int k = 0; k < needle.length; k++) {
          if (zip[i + k] != needle[k]) {
            same = false;
            break;
          }
        }
        if (same) at = i;
      }
      expect(at, greaterThan(0));
      _expectRefused(
        Uint8List.fromList(zip)..[at + 1] = 0x5A,
        XlsxReadFailure.corruptZip,
        model: _Model.open,
      );
    });

    test('duplicate entry names are corruptZip', () {
      final Map<String, List<int>> entries = _entries(
        overrides: <String, List<int>>{
          'xl/Workbook.xml': utf8.encode('<workbook/>'),
        },
      );
      _expectRefused(
        buildZip(entries),
        XlsxReadFailure.corruptZip,
        model: _Model.open,
      );
    });

    test('a billion-laughs DOCTYPE in the shared strings is malformedXml', () {
      final Uint8List zip = buildWorkbook(
        <String, String?>{
          'S': worksheet('<row r="1"><c r="A1" t="s"><v>0</v></c></row>'),
        },
        sharedStrings:
            '<!DOCTYPE sst [<!ENTITY a "aaaaaaaaaa">'
            '<!ENTITY b "&a;&a;&a;&a;&a;&a;&a;&a;&a;&a;">'
            '<!ENTITY c "&b;&b;&b;&b;&b;&b;&b;&b;&b;&b;">]>'
            '<sst xmlns="$mainNs"><si><t>&c;</t></si></sst>',
      );
      _expectRefused(zip, XlsxReadFailure.malformedXml, model: _Model.sheet);
    });

    test('a UTF-16 workbook part is malformedXml', () {
      final Uint8List zip = buildZip(
        _entries(
          overrides: <String, List<int>>{
            'xl/workbook.xml': _utf16le(
              '<workbook xmlns="$mainNs"><sheets/></workbook>',
            ),
          },
        ),
      );
      _expectRefused(zip, XlsxReadFailure.malformedXml, model: _Model.open);
    });

    test('empty and random bytes are notZip', () {
      _expectRefused(Uint8List(0), XlsxReadFailure.notZip, model: _Model.open);
      final Uint8List random = Uint8List.fromList(
        List<int>.generate(4096, (int i) => (i * 2654435761 >> 7) & 0xFF),
      );
      _expectRefused(random, XlsxReadFailure.notZip, model: _Model.open);
    });

    test('a truncated ZIP is corruptZip', () {
      final Uint8List zip = buildZip(_entries());
      _expectRefused(
        Uint8List.sublistView(zip, 0, zip.length ~/ 2),
        XlsxReadFailure.corruptZip,
        model: _Model.open,
      );
    });

    test('an OLE file with EncryptedPackage is encrypted', () {
      _expectRefused(
        Uint8List.fromList(<int>[
          ..._ole,
          ...List<int>.filled(500, 0),
          for (final int u in 'EncryptedPackage'.codeUnits) ...<int>[u, 0],
          ...List<int>.filled(100, 0),
        ]),
        XlsxReadFailure.encrypted,
        model: _Model.open,
      );
    });

    test('another OLE file is legacyXls', () {
      _expectRefused(
        Uint8List.fromList(<int>[
          ..._ole,
          ...List<int>.filled(500, 0),
          ...utf8.encode('Workbook'),
        ]),
        XlsxReadFailure.legacyXls,
        model: _Model.open,
      );
    });

    test('a Strict workbook is unsupportedFormat', () {
      final Uint8List zip = buildZip(
        _entries(
          overrides: <String, List<int>>{
            '_rels/.rels': utf8.encode(
              '<Relationships xmlns="$_pkgRel"><Relationship Id="rId1" '
              'Type="http://purl.oclc.org/ooxml/officeDocument/relationships/'
              'officeDocument" Target="xl/workbook.xml"/></Relationships>',
            ),
          },
        ),
      );
      _expectRefused(
        zip,
        XlsxReadFailure.unsupportedFormat,
        model: _Model.open,
      );
    });

    test('an .xlsb content type is unsupportedFormat', () {
      final Uint8List zip = buildZip(
        _entries(
          overrides: <String, List<int>>{
            '[Content_Types].xml': utf8.encode(
              '<Types xmlns="http://schemas.openxmlformats.org/package/2006/'
              'content-types"><Override PartName="/xl/workbook.xml" '
              'ContentType="application/vnd.ms-excel.sheet.binary.macroEnabled'
              '.main"/></Types>',
            ),
          },
        ),
      );
      _expectRefused(
        zip,
        XlsxReadFailure.unsupportedFormat,
        model: _Model.open,
      );
    });

    test('a package without a workbook is missingWorkbook', () {
      _expectRefused(
        buildZip(<String, List<int>>{
          '[Content_Types].xml': utf8.encode(
            '<Types xmlns="http://schemas.openxmlformats.org/package/2006/'
            'content-types"/>',
          ),
          'docs/readme.txt': utf8.encode('hi'),
        }),
        XlsxReadFailure.missingWorkbook,
        model: _Model.open,
      );
    });
  });

  group('costs nothing', () {
    test('a huge dimension with 3 cells reads 3 cells in under 1 s', () {
      final Uint8List zip = buildWorkbook(<String, String?>{
        'S':
            '<worksheet xmlns="$mainNs"><dimension ref="A1:XFD1048576"/>'
            '<sheetData><row r="1"><c r="A1"><v>1</v></c>'
            '<c r="B1"><v>2</v></c><c r="C1"><v>3</v></c></row>'
            '</sheetData></worksheet>',
      });
      final Stopwatch watch = Stopwatch()..start();
      final XlsxReader reader = XlsxReader(zip);
      final List<XlsxReadRow> rows = reader.rowsAt(0).toList();
      expect(rows.single.cells, hasLength(3));
      expect(watch.elapsedMilliseconds, lessThan(1000));
    });

    test('the last row and the last column read', () {
      final Uint8List zip = buildWorkbook(<String, String?>{
        'S': worksheet('<row r="1048576"><c r="XFD1048576"><v>7</v></c></row>'),
      });
      final XlsxReader reader = XlsxReader(zip);
      final XlsxReadRow row = reader.rowsAt(0).single;
      expect(row.index, 1048575);
      expect(row.cells.single.column, 16383);
      expect(row.cells.single.value, XlsxDecimal('7'));
    });

    test('an sst claiming 4294967295 strings reads its one string', () {
      final Uint8List zip = buildWorkbook(
        <String, String?>{
          'S': worksheet('<row r="1"><c r="A1" t="s"><v>0</v></c></row>'),
        },
        sharedStrings:
            '<sst xmlns="$mainNs" count="4294967295" '
            'uniqueCount="4294967295"><si><t>a</t></si></sst>',
      );
      final Stopwatch watch = Stopwatch()..start();
      final XlsxReader reader = XlsxReader(zip);
      final XlsxReadRow row = reader.rowsAt(0).single;
      expect(row.cells.single.value, 'a');
      expect(reader.warnings, isEmpty);
      expect(watch.elapsedMilliseconds, lessThan(1000));
    });

    test('100,000 empty rows yield no rows', () {
      final Uint8List zip = buildWorkbook(<String, String?>{
        'S': worksheet('<row/>' * 100000),
      });
      expect(XlsxReader(zip).rowsAt(0).toList(), isEmpty);
    });
  });
}
