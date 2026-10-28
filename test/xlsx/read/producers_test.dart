import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

import 'support/producers.dart';
import 'support/workbook_builder.dart';
import 'support/zip_builder.dart';

/// The DOS date of the first local header of [zip].
int _firstLocalDate(Uint8List zip) =>
    ByteData.sublistView(zip).getUint16(12, Endian.little);

/// A writer-made file: one sheet `P` with a string, a decimal and a date in
/// row 1 and a merge `A2:B2`; [expected] is its first row as expected.
ProducerFile _writerFile(List<Object?> expected) {
  final XlsxWriter w = XlsxWriter();
  w.addSheet('P')
    ..row(<Object?>['Ürün', XlsxDecimal('1.50'), const XlsxDate(2026, 10, 28)])
    ..merge(XlsxRange.parse('A2:B2'));
  return ProducerFile('writer', w.close().bytes, <ProducerSheet>[
    ProducerSheet(
      'P',
      <List<Object?>>[expected],
      merges: <XlsxRange>[XlsxRange.parse('A2:B2')],
    ),
  ]);
}

void main() {
  group('buildZip', () {
    final Map<String, List<int>> parts = <String, List<int>>{
      'a.xml': utf8.encode('<a/>'),
      'b/c.xml': utf8.encode('<c>${'x' * 300}</c>'),
    };

    test('buildZip is deterministic', () async {
      for (final bool store in <bool>[true, false]) {
        final Uint8List first = buildZip(parts, store: store);
        // A second apart, so a clock-based timestamp would differ.
        await Future<void>.delayed(const Duration(milliseconds: 1100));
        expect(buildZip(parts, store: store), first, reason: 'store: $store');
      }
    });

    test('buildZip stamps every entry 1980-01-01', () {
      // DOS date: day 1, month 1, year 0 (1980).
      expect(_firstLocalDate(buildZip(parts)), 0x21);
      expect(
        _firstLocalDate(
          buildZipOrdered(<(String, List<int>)>[
            ('z.xml', utf8.encode('<z/>')),
          ]),
        ),
        0x21,
      );
    });

    test('buildZipOrdered keeps the given entry order', () {
      final Uint8List zip = buildZipOrdered(<(String, List<int>)>[
        ('z.xml', utf8.encode('<z/>')),
        ('a.xml', utf8.encode('<a/>')),
      ], store: true);
      final String text = latin1.decode(zip);
      expect(text.indexOf('z.xml'), lessThan(text.indexOf('a.xml')));
      expect(
        buildZipOrdered(<(String, List<int>)>[
          ('z.xml', utf8.encode('<z/>')),
          ('a.xml', utf8.encode('<a/>')),
        ], store: true),
        zip,
      );
    });
  });

  group('expectProducerFile', () {
    final List<Object?> right = <Object?>[
      'Ürün',
      XlsxDecimal('1.50'),
      DateTime.utc(2026, 10, 28),
    ];

    test('expectProducerFile compares values, warnings and merges', () {
      expectProducerFile(_writerFile(right));
      expect(
        () => expectProducerFile(
          _writerFile(<Object?>['Ürün', XlsxDecimal('1.5'), right[2]]),
        ),
        throwsA(isA<TestFailure>()),
      );
    });

    test('a cell beyond the expected width fails', () {
      expect(
        () => expectProducerFile(_writerFile(right.sublist(0, 2))),
        throwsA(isA<TestFailure>()),
      );
    });

    test('a different merge list fails', () {
      final ProducerFile good = _writerFile(right);
      expect(
        () => expectProducerFile(
          ProducerFile(good.name, good.bytes, <ProducerSheet>[
            ProducerSheet('P', good.sheets.single.rows),
          ]),
        ),
        throwsA(isA<TestFailure>()),
      );
    });

    test('a warning count that differs fails', () {
      final ProducerFile good = _writerFile(right);
      expect(
        () => expectProducerFile(
          ProducerFile(
            good.name,
            good.bytes,
            good.sheets,
            warnings: const <XlsxWarningCode, int>{
              XlsxWarningCode.cellDuplicated: 1,
            },
          ),
        ),
        throwsA(isA<TestFailure>()),
      );
    });

    test('hidden rows must match both ways', () {
      final ProducerFile good = _writerFile(right);
      expect(
        () => expectProducerFile(
          ProducerFile(good.name, good.bytes, <ProducerSheet>[
            ProducerSheet(
              'P',
              good.sheets.single.rows,
              merges: good.sheets.single.merges,
              hiddenRows: const <int>{0},
            ),
          ]),
        ),
        throwsA(isA<TestFailure>()),
      );
      // A hidden empty row the expectation does not list.
      final Uint8List hidden = buildWorkbook(<String, String?>{
        'H': worksheet(
          '<row r="1"><c r="A1"><v>1</v></c></row><row r="2" hidden="1"/>',
        ),
      });
      final List<List<Object?>> rows = <List<Object?>>[
        <Object?>[XlsxDecimal('1')],
      ];
      expectProducerFile(
        ProducerFile('h', hidden, <ProducerSheet>[
          ProducerSheet('H', rows, hiddenRows: const <int>{1}),
        ]),
      );
      expect(
        () => expectProducerFile(
          ProducerFile('h', hidden, <ProducerSheet>[ProducerSheet('H', rows)]),
        ),
        throwsA(isA<TestFailure>()),
      );
    });

    test('date1904, sheet names and visibility are compared', () {
      final ProducerFile good = _writerFile(right);
      for (final ProducerFile bad in <ProducerFile>[
        ProducerFile(good.name, good.bytes, good.sheets, date1904: true),
        ProducerFile(good.name, good.bytes, <ProducerSheet>[
          ProducerSheet(
            'Q',
            good.sheets.single.rows,
            merges: good.sheets.single.merges,
          ),
        ]),
        ProducerFile(good.name, good.bytes, <ProducerSheet>[
          ProducerSheet(
            'P',
            good.sheets.single.rows,
            merges: good.sheets.single.merges,
            visibility: XlsxSheetVisibility.hidden,
          ),
        ]),
      ]) {
        expect(() => expectProducerFile(bad), throwsA(isA<TestFailure>()));
      }
    });
  });

  for (final ProducerFile f in producerFiles()) {
    test('reads ${f.name} exactly', () => expectProducerFile(f));
  }
}
