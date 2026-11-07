/// The DOCX table benchmark: build a table of text with `DocxBody.addTable`
/// and `DocxTable.addRow`, save it, open the bytes and read every cell, at
/// 2,500 and at 10,000 rows of 12 columns.
///
/// Not ported from Quds; written for jet_office. It records figures, it does
/// not judge them (docs/benchmark.md). The text is deterministic and does not
/// repeat in a way deflate can exploit: each cell is one to eight words drawn
/// by a hash of its row and column from a vocabulary of 4,096 made-up words
/// (each 8 to 12 letters), and about one cell in three also ends in a token
/// unique to the cell (`#` and the cell's number in base 36), so a cell is 8 to
/// about 105 characters. About one cell in 25 is empty. Each platform opens its own bytes (decision 0006). Run it with
/// `dart test benchmark` and `dart test -p chrome benchmark`; the quality gate
/// does not.
@Tags(<String>['benchmark'])
@Timeout(Duration(minutes: 20))
library;

import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

import 'src/memory_probe.dart';

const int _columns = 12;

/// The table sizes, in data rows: a smaller one beside the larger, to show how
/// the phases grow.
const List<int> _sizes = <int>[2500, 10000];

const int _vocabularySize = 4096;

/// A 31-bit hash of [a] and [b]: a linear congruential step (multiplier
/// 48271, modulus 2^31 - 1) kept below 2^53, so it gives the same value on
/// the VM and in dart2js, mixed twice so near inputs give far outputs.
int _hash(int a, int b) {
  int h = (a * 7919 + b * 104729 + 12345) % 2147483647;
  for (int i = 0; i < 3; i++) {
    h = (h * 48271 + 1) % 2147483647;
    h = (h ^ (h >> 13)) % 2147483647;
  }
  return h;
}

const List<String> _syllables = <String>[
  'ba',
  'ko',
  'ri',
  'tu',
  'sen',
  'mo',
  'la',
  'dre',
  'vi',
  'xan',
  'pe',
  'ju',
];

/// The vocabulary word at [index]: four syllables read off [index] in base 12,
/// so every word differs; each has 8 to 12 letters.
String _word(int index) {
  final StringBuffer b = StringBuffer();
  int n = index;
  for (int i = 0; i < 4; i++) {
    b.write(_syllables[n % _syllables.length]);
    n ~/= _syllables.length;
  }
  return b.toString();
}

final List<String> _vocabulary = <String>[
  for (int i = 0; i < _vocabularySize; i++) _word(i),
];

/// The text of the cell at [row] and [column].
String _text(int row, int column) {
  final int h = _hash(row, column);
  final int count = 1 + h % 8;
  final StringBuffer b = StringBuffer();
  for (int i = 0; i < count; i++) {
    if (i > 0) b.write(' ');
    b.write(_vocabulary[_hash(h, i) % _vocabularySize]);
  }
  if (h % 3 == 0) b.write(' #${(row * _columns + column).toRadixString(36)}');
  return b.toString();
}

/// The cell as the table gets it: `null` for about one in 25.
String? _cell(int row, int column) =>
    _hash(column, row) % 25 == 0 ? null : _text(row, column);

const bool _isWeb = identical(0, 0.0);

void main() {
  final MemoryProbe memory = currentProbe();
  final MemoryProbe peakProbe = probe();
  const String platform = _isWeb ? 'chrome' : 'vm';

  void line(String text) {
    // ignore: avoid_print
    print('$platform | $text');
  }

  /// Runs [body] once, timed, and prints its time and memory: the process
  /// memory ([MemoryProbe.unit]) before and after, and the peak where the
  /// platform has one.
  T phase<T>(String name, T Function() body) {
    final int? before = memory.sample();
    final int? peakBefore = peakProbe.sample();
    final Stopwatch watch = Stopwatch()..start();
    final T result = body();
    watch.stop();
    final int? after = memory.sample();
    final int? peak = peakProbe.sample();
    line(
      'phase | $name | ${(watch.elapsedMicroseconds / 1000).toStringAsFixed(1)}'
      ' ms | ${memory.unit} before ${before ?? 'n/a'} | after '
      '${after ?? 'n/a'} | ${peakProbe.unit} ${peak ?? 'n/a'} (was '
      '${peakBefore ?? 'n/a'})',
    );
    return result;
  }

  for (final int rows in _sizes) {
    test('build, save, open and read a $rows x $_columns table', () {
      final DocxDocument doc = DocxDocument();
      final DocxTable table = phase('$rows rows | build', () {
        final DocxTable t = doc.body.addTable(columns: _columns);
        t.addRow(<String?>[
          for (int c = 0; c < _columns; c++) 'Column ${c + 1}',
        ], header: true);
        for (int r = 0; r < rows; r++) {
          t.addRow(<String?>[for (int c = 0; c < _columns; c++) _cell(r, c)]);
        }
        return t;
      });
      expect(table.rows, hasLength(rows + 1));

      final Uint8List bytes = phase(
        '$rows rows | save',
        () => doc.save().bytes,
      );
      line('$rows rows | file | ${bytes.length} bytes');

      final DocxDocument opened = phase(
        '$rows rows | open (and load the body)',
        () => DocxDocument.open(bytes)..body,
      );
      final DocxTable read = opened.body.blocks.whereType<DocxTable>().single;

      int cells = 0;
      int characters = 0;
      phase('$rows rows | read every cell', () {
        for (final DocxTableRow row in read.rows) {
          for (final DocxTableCell cell in row.cells) {
            cells++;
            characters += cell.text.length;
          }
        }
      });
      expect(cells, (rows + 1) * _columns);
      expect(read.rows[1].cells[2].text, _cell(0, 2) ?? '');
      expect(read.rows[rows].cells[5].text, _cell(rows - 1, 5) ?? '');
      int shortest = 1 << 30;
      int longest = 0;
      for (final DocxTableCell cell in read.rows[1].cells) {
        final int n = cell.text.length;
        if (n > 0 && n < shortest) shortest = n;
        if (n > longest) longest = n;
      }
      final Set<String> distinct = <String>{};
      for (final DocxTableRow row in read.rows) {
        for (final DocxTableCell cell in row.cells) {
          distinct.add(cell.text);
        }
      }
      line(
        '$rows rows | cells | $cells | $characters characters | '
        '${distinct.length} distinct texts | first data row $shortest to '
        '$longest characters',
      );
    });
  }
}
