/// Lists where LibreOffice shows the number format oracle's cases
/// differently from `XlsxNumberFormatter`.
///
/// LibreOffice is a second opinion, not Excel (decision 0008: Excel wins):
/// the tool reports each difference and exits 0 with any number of them.
/// It exits 2 when the input is unusable (the directory is missing, it
/// holds no CSV of an oracle workbook, the case list or a CSV cannot be
/// read, or a CSV has no case rows) and 64 on a usage error.
///
/// ```bash
/// dart run tool/write_format_oracle.dart build/format_oracle
/// LC_ALL=C.UTF-8 soffice --headless \
///   --convert-to 'csv:Text - txt - csv (StarCalc):44,34,UTF8,1,,0,false,true,true,false,false,1' \
///   --outdir build/format_oracle build/format_oracle/*.xlsx
/// dart run tool/compare_format_libreoffice.dart build/format_oracle
/// ```
///
/// The filter options are those `tool/compare_csv.dart`'s doc comment
/// explains, with two changes: token 9 is `true`, **save cell contents as
/// shown**, so column A is the text LibreOffice displays; token 12 is `1`,
/// the first sheet only, `cases`, written as `<stem>-cases.csv` (the eye
/// sheet holds cases a CSV cannot show). Without token 12 LibreOffice also
/// writes the first sheet only, as `<stem>.csv`, which is read when there
/// is no `<stem>-cases.csv`. Token 6, `0`, takes the language from the
/// system locale, so `LC_ALL=C.UTF-8` gives en-US text.
///
/// It reads the case list (`test/fixtures/owner/number_format/cases.json`),
/// and for each workbook whose CSV is in the directory compares every case
/// with `compareOracle` in the locale of `--locale` (`en-US`, the default,
/// `de-DE` or `tr-TR`; LibreOffice must have run in the same locale), and
/// prints its `oracleReport`, then a total line. Eye-only cases count as by
/// eye.
library;

import 'dart:io';

import 'src/format_libreoffice.dart';
import 'src/format_oracle.dart';
import 'src/format_oracle_compare.dart';

const String _usage =
    'Usage: dart run tool/compare_format_libreoffice.dart <csv dir> '
    '[--locale en-US|de-DE|tr-TR]';

void main(List<String> args) {
  String? dirPath;
  String region = 'en-US';
  for (int i = 0; i < args.length; i++) {
    final String arg = args[i];
    if (arg == '--locale' && i + 1 < args.length) {
      region = args[++i];
    } else if (!arg.startsWith('-') && dirPath == null) {
      dirPath = arg;
    } else {
      dirPath = null;
      break;
    }
  }
  if (dirPath == null || !oracleRegions.contains(region)) {
    stderr.writeln(_usage);
    exitCode = 64;
    return;
  }
  final Directory dir = Directory(dirPath);
  if (!dir.existsSync()) {
    stderr.writeln('No such directory: $dirPath');
    exitCode = 2;
    return;
  }
  final OracleCases cases;
  try {
    cases = parseOracleCases(File(oracleCasesPath).readAsStringSync());
  } on FormatException catch (e) {
    stderr.writeln('$oracleCasesPath: ${e.message}');
    exitCode = 2;
    return;
  }
  final Set<String> names = <String>{
    for (final File f in dir.listSync().whereType<File>())
      f.uri.pathSegments.last,
  };
  final Map<String, String> csv = <String, String>{};
  for (final OracleWorkbook book in cases.workbooks.values) {
    final String? name = libreOfficeCsvName(book.file, names);
    if (name == null) continue;
    try {
      csv[book.key] = File('${dir.path}/$name').readAsStringSync();
    } on FileSystemException catch (e) {
      stderr.writeln('$name: ${e.message}');
      exitCode = 2;
      return;
    }
  }
  if (csv.isEmpty) {
    stderr.writeln(
      'No LibreOffice CSV of an oracle workbook in $dirPath '
      '(expected such as format_oracle-cases.csv).',
    );
    exitCode = 2;
    return;
  }
  try {
    stdout.writeln(libreOfficeReport(cases, region, csv));
  } on FormatException catch (e) {
    stderr.writeln(e.message);
    exitCode = 2;
  }
}
