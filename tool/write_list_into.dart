/// Writes a fixed Turkish list into every Word document of a directory, for
/// the owner's Word check of `DocxListExport.writeTo` on real files
/// (`docs/word-checks.md`, section D6).
///
/// ```bash
/// dart run tool/write_list_into.dart test/fixtures/owner/docx \
///   build/d6/list-into-owner
/// ```
///
/// For every `*.docx` in the first directory (a Word lock file `~$name.docx`
/// is skipped) it opens the document with `DocxDocument.open`, writes
/// `turkishList` into it with `DocxListExport.writeTo` (a logo, a title, a
/// date, a caption, three rows and a totals row; the document's last section
/// gets the page, header and footer, and its even ones too when the document
/// has odd and even headers), saves it and writes the bytes to
/// `<outDir>/<name>.docx`. Each file is reported as `<name>: written` or, when
/// the model refuses or fails on it, `<name>: <error>`. The exit code is 1 on
/// any error, 2 when the arguments are unusable or the input directory holds
/// no `.docx`, and 0 otherwise. It is not part of the CI chain;
/// `dotnet run --project tool/ooxml_validate -- <outDir>` validates the output.
/// Not ported from Quds.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';

import '../test/fixtures/m4_fixtures.dart' show png4x2;

/// The rows `turkishList` is written with.
final List<List<Object?>> turkishRows = <List<Object?>>[
  <Object?>['M-1001', 'Çağlar Işık', DateTime(2026, 1, 1), 1234.5, 0.0],
  <Object?>['M-1002', 'İpek Özdemir', DateTime(2026, 2, 2), 1251.75, 0.05],
  <Object?>['M-1003', 'Şükrü Doğan', DateTime(2026, 3, 3), 1269.0, 0.1],
];

/// The totals row `turkishList` is written with.
const List<Object?> turkishTotals = <Object?>['Toplam', null, null, 3755.25];

/// The fixed Turkish list: five-column header, logo, title, date and caption,
/// with the footer `Sayfa 1 / 1`.
DocxListExport turkishList() => DocxListExport(
  const <DocxListColumn>[
    DocxListColumn('Kod', widthPt: 60),
    DocxListColumn('Müşteri'),
    DocxListColumn('Tarih', numberFormat: 'dd.mm.yyyy', widthPt: 70),
    DocxListColumn('Tutar', numberFormat: '#,##0.00 ₺', widthPt: 90),
    DocxListColumn('Pay', numberFormat: '0%', widthPt: 50),
  ],
  title: 'Müşteri listesi',
  logo: OfficeImage(png4x2),
  logoHeightPt: 20,
  date: DateTime(2026, 11, 8),
  caption: 'Kasım 2026 müşteri bakiyeleri',
  footerBefore: 'Sayfa ',
  footerMiddle: ' / ',
  locale: FormatLocale.trTR,
);

void main(List<String> args) {
  exitCode = writeListInto(args, out: stdout, err: stderr);
}

/// Runs the tool on [args] (`<inDir> <outDir>`), writing one line per file to
/// [out] and usage problems to [err], and returns the exit code.
int writeListInto(
  List<String> args, {
  required StringSink out,
  required StringSink err,
}) {
  if (args.length != 2) {
    err.writeln('Usage: dart run tool/write_list_into.dart <inDir> <outDir>');
    return 2;
  }
  final Directory input = Directory(args[0]);
  if (!input.existsSync()) {
    err.writeln('No such directory: ${input.path}');
    return 2;
  }
  final List<File> files = input.listSync().whereType<File>().where((File f) {
    final String name = f.uri.pathSegments.last;
    return name.endsWith('.docx') && !name.startsWith(r'~$');
  }).toList()..sort((File a, File b) => a.path.compareTo(b.path));
  if (files.isEmpty) {
    err.writeln('Nothing to write into: no .docx in ${input.path}.');
    return 2;
  }
  final Directory output = Directory(args[1])..createSync(recursive: true);
  int failed = 0;
  for (final File file in files) {
    final String name = file.uri.pathSegments.last;
    try {
      final DocxDocument doc = DocxDocument.open(file.readAsBytesSync());
      turkishList().writeTo(doc, turkishRows, totals: turkishTotals);
      final Uint8List saved = doc.save().bytes;
      File('${output.path}/$name').writeAsBytesSync(saved);
      out.writeln('$name: written');
    } on Object catch (e) {
      out.writeln('$name: $e');
      failed++;
    }
  }
  return failed == 0 ? 0 : 1;
}
