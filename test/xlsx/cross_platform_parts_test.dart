// No @TestOn: this file runs on the VM and in Chrome against the same
// constants. Equal constants on both legs prove that the contents of every
// part are identical on the two platforms (decision 0006). The ZIP bytes are
// not compared: `package:archive` deflates with the native zlib on the VM and
// with pure Dart on the web, so they match only within one platform.
import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

import '../../benchmark/src/workload.dart';
import '../support/read_xlsx.dart';

/// FNV-1a (32 bit) over [bytes].
int _fnv1a(List<int> bytes) {
  int hash = 0x811c9dc5;
  for (final int b in bytes) {
    // hash * 0x01000193 = hash * 0x193 + (hash << 24), kept below 2^53 so the
    // web computes it exactly.
    final int x = hash ^ b;
    hash = (x * 0x193 + ((x << 24) & 0xffffffff)) & 0xffffffff;
  }
  return hash;
}

void main() {
  test('every part has the same contents on the VM and the web', () {
    final XlsxWriter book = XlsxWriter();
    writeWorkload(book.addSheet('Data'), 300, (int _) {});
    final Map<String, int> sums = <String, int>{
      for (final MapEntry<String, List<int>> e in readXlsxBytes(
        book.close().bytes,
      ).entries)
        e.key: _fnv1a(e.value),
    };
    expect(sums, <String, int>{
      'xl/worksheets/sheet1.xml': 2754264325,
      'xl/sharedStrings.xml': 1818965280,
      'xl/styles.xml': 1443871042,
      'xl/workbook.xml': 1551093133,
      'xl/_rels/workbook.xml.rels': 440818139,
      'docProps/core.xml': 3644369703,
      'docProps/app.xml': 2802199266,
      '_rels/.rels': 4244982426,
      '[Content_Types].xml': 1730488154,
    });
  });
}
