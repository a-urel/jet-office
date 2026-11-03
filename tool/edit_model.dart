/// Edits every workbook of a directory through `XlsxWorkbook`, and writes
/// one generated from nothing, so that CI can validate what the model saves
/// after a change.
///
/// ```bash
/// dart run tool/edit_model.dart build/fixtures build/model-edited
/// ```
///
/// For every `*.xlsx` in the first directory it opens the workbook with
/// `XlsxWorkbook.open` and, on the first sheet, sets four cells of the row
/// after its last row (the first free row when the last row is the grid's):
/// a `DateTime`, an `XlsxDate`, a formula (`SUM(1,2)`, cached 3) and a
/// string. It then adds a sheet `Model edit` (`Model edit 2` and so on when
/// the name is taken) holding one string, saves, and writes the bytes to
/// `<outDir>/<name>.xlsx`. The saved file is read back with `XlsxReader`,
/// and the edits must be there. Last it writes the workbook
/// `tool/write_model_sample.dart` makes, `w1_generated.xlsx`, to the same
/// directory.
///
/// Each problem is printed as `<file>: <problem>`. The exit code is 1 on any
/// problem, 2 when the arguments are unusable or the input directory holds
/// no `.xlsx`, and 0 otherwise. The model's warnings are not problems: an
/// edit may be reported (a date in a cell of a number format, say).
///
/// CI runs it on the writer fixtures and validates the output directory with
/// `tool/ooxml_validate`, so an edited or generated workbook is held to the
/// same standard as the writer's output (spec section 9).
///
/// Not ported from Quds; written for jet_office.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';

import 'write_model_sample.dart' as sample;

void main(List<String> args) {
  exitCode = editModel(args, out: stdout, err: stderr);
}

/// The string the tool sets, and the one on the added sheet.
const String _text = 'edited by the model';
const String _addedText = 'added sheet';

/// Runs the tool on [args] (`<inDir> <outDir>`), writing problems to [out]
/// and usage problems to [err], and returns the exit code.
int editModel(
  List<String> args, {
  required StringSink out,
  required StringSink err,
}) {
  if (args.length != 2) {
    err.writeln('Usage: dart run tool/edit_model.dart <inDir> <outDir>');
    return 2;
  }
  final Directory input = Directory(args[0]);
  if (!input.existsSync()) {
    err.writeln('No such directory: ${input.path}');
    return 2;
  }
  final List<File> files =
      input
          .listSync()
          .whereType<File>()
          .where((File f) => f.path.endsWith('.xlsx'))
          .toList()
        ..sort((File a, File b) => a.path.compareTo(b.path));
  if (files.isEmpty) {
    err.writeln('Nothing to edit: no .xlsx in ${input.path}.');
    return 2;
  }
  final Directory output = Directory(args[1])..createSync(recursive: true);
  int failed = 0;
  for (final File file in files) {
    final String name = file.uri.pathSegments.last;
    final List<String> problems = _edit(file, output, name);
    for (final String line in problems) {
      out.writeln('$name: $line');
    }
    if (problems.isNotEmpty) failed++;
  }
  try {
    sample.writeModelSample(output.path);
  } on Object catch (e) {
    out.writeln('w1_generated.xlsx: generating failed: $e');
    failed++;
  }
  out.writeln(
    failed == 0
        ? 'All ${files.length} workbooks edited, and w1_generated.xlsx '
              'written.'
        : '$failed failed.',
  );
  return failed == 0 ? 0 : 1;
}

/// Edits [file], writes the result to [output], and returns the problems.
List<String> _edit(File file, Directory output, String name) {
  final Uint8List saved;
  final int row;
  final String added;
  try {
    final XlsxWorkbook book = XlsxWorkbook.open(file.readAsBytesSync());
    final XlsxSheet sheet = book.sheets.first;
    row = _freeRow(sheet);
    sheet
      ..setCell(row, 0, DateTime.utc(2026, 11, 2, 13, 45))
      ..setCell(row, 1, const XlsxDate(2026, 11, 2))
      ..setCell(row, 2, const XlsxFormula('SUM(1,2)', cached: 3))
      ..setCell(row, 3, _text);
    added = _freeName(book, 'Model edit');
    book.addSheet(added).setCell(0, 0, _addedText);
    saved = book.save().bytes;
  } on Object catch (e) {
    return <String>['the edit failed: $e'];
  }
  File('${output.path}/$name').writeAsBytesSync(saved);
  return _check(saved, row, added);
}

/// The row after the last row [sheet] lists, or the first row it does not
/// list when its last row is the grid's.
int _freeRow(XlsxSheet sheet) {
  final List<int> rows = <int>[for (final XlsxReadRow r in sheet.rows) r.index];
  if (rows.isEmpty) return 0;
  if (rows.last + 1 < XlsxLimits.maxRows) return rows.last + 1;
  int free = 0;
  for (final int r in rows) {
    if (r != free) break;
    free++;
  }
  return free;
}

/// [base], or [base] with the first number from 2 that makes it a name no
/// sheet of [book] has (compared as Excel does, ignoring case).
String _freeName(XlsxWorkbook book, String base) {
  final Set<String> taken = <String>{
    for (final XlsxSheet s in book.sheets) s.name.toLowerCase(),
  };
  String name = base;
  for (int n = 2; taken.contains(name.toLowerCase()); n++) {
    name = '$base $n';
  }
  return name;
}

/// The edits [saved] lacks when read back with `XlsxReader`.
List<String> _check(Uint8List saved, int row, String added) {
  final List<String> problems = <String>[];
  try {
    final XlsxReader reader = XlsxReader(saved);
    final List<XlsxReadCell> cells = <XlsxReadCell>[
      for (final XlsxReadRow r in reader.rowsAt(0))
        if (r.index == row) ...r.cells,
    ];
    Object? valueAt(int column) {
      for (final XlsxReadCell c in cells) {
        if (c.column == column) return c.value;
      }
      return null;
    }

    if (valueAt(0) is! DateTime) problems.add('the DateTime is missing');
    if (valueAt(1) is! DateTime) problems.add('the XlsxDate is missing');
    if (!cells.any((XlsxReadCell c) => c.column == 2 && c.formula != null)) {
      problems.add('the formula is missing');
    }
    if (valueAt(3) != _text) problems.add('the string is missing');
    final int last = reader.sheets.length - 1;
    if (reader.sheets[last].name != added ||
        reader.rowsAt(last).first.cells.first.value != _addedText) {
      problems.add('the added sheet is missing');
    }
  } on Object catch (e) {
    problems.add('reading the saved workbook failed: $e');
  }
  return problems;
}
