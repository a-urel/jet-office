/// The DOCX table benchmark: build a 10,000 x 12 table of text with
/// `DocxBody.addTable` and `DocxTable.addRow`, save it, open the bytes and
/// read every cell.
///
/// Not ported from Quds; written for jet_office. It records figures, it does
/// not judge them (docs/benchmark.md). The text is deterministic and mixed in
/// length (3 to about 60 characters, some with an accent or an entity
/// character). Each platform opens its own bytes (decision 0006). Run it with
/// `dart test benchmark` and `dart test -p chrome benchmark`; the quality gate
/// does not.
@Tags(<String>['benchmark'])
@Timeout(Duration(minutes: 20))
library;

import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

import 'src/memory_probe.dart';

const int _rows = 10000;
const int _columns = 12;

const List<String> _words = <String>[
  'alpha',
  'Beta & co',
  'gamma',
  'delta <x>',
  'epsilon',
  'zeta',
  'eta',
  'theta',
  'Çay',
  'kappa',
  'lambda',
  'mu',
];

/// The text of the cell at [row] and [column]: one to eight words, chosen by
/// a fixed arithmetic, so every run and platform writes the same document.
String _text(int row, int column) {
  final int count = 1 + (row * 7 + column * 3) % 8;
  final StringBuffer b = StringBuffer();
  for (int i = 0; i < count; i++) {
    if (i > 0) b.write(' ');
    b.write(_words[(row * 31 + column * 17 + i * 5) % _words.length]);
  }
  return b.toString();
}

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

  test('build, save, open and read a $_rows x $_columns table', () {
    final DocxDocument doc = DocxDocument();
    final DocxTable table = phase('build ($_rows rows)', () {
      final DocxTable t = doc.body.addTable(columns: _columns);
      t.addRow(<String?>[
        for (int c = 0; c < _columns; c++) 'Column ${c + 1}',
      ], header: true);
      for (int r = 0; r < _rows; r++) {
        t.addRow(<String?>[
          for (int c = 0; c < _columns; c++)
            if ((r + c) % 25 == 0) null else _text(r, c),
        ]);
      }
      return t;
    });
    expect(table.rows, hasLength(_rows + 1));

    final Uint8List bytes = phase('save', () => doc.save().bytes);
    line('file | ${bytes.length} bytes');

    final DocxDocument opened = phase(
      'open (and load the body)',
      () => DocxDocument.open(bytes)..body,
    );
    final DocxTable read = opened.body.blocks.whereType<DocxTable>().single;

    int cells = 0;
    int characters = 0;
    phase('read every cell', () {
      for (final DocxTableRow row in read.rows) {
        for (final DocxTableCell cell in row.cells) {
          cells++;
          characters += cell.text.length;
        }
      }
    });
    expect(cells, (_rows + 1) * _columns);
    expect(read.rows[1].cells[1].text, _text(0, 1));
    expect(read.rows[_rows].cells[5].text, _text(_rows - 1, 5));
    line('cells | $cells | $characters characters');
  });
}
