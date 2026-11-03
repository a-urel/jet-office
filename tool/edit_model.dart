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
/// string. The cells take the style of their row or column, and a date in
/// a column of a number format that shows no date keeps that format and so
/// reads back as a number. On the same sheet it gives those cells a bold
/// style with a red fill over the style they have, so the dates keep their
/// format, sets column B's width to 30 and the new row's height to 24,
/// merges the two cells right of the new values, freezes the first row and
/// sets a tab colour. It then adds a sheet `Model edit` (`Model edit 2` and
/// so on when the name is taken) holding one string, saves, and writes the
/// bytes to `<outDir>/<name>.xlsx`. The saved file is read back with
/// `XlsxReader` (values, number formats, merges) and with `XlsxWorkbook`
/// (styles, width, height, merges, pane, tab colour), and the edits must be
/// there. Last it writes the workbooks `tool/write_model_sample.dart` makes,
/// `w1_generated.xlsx` and `w2_generated.xlsx`, to the same directory.
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
import 'package:jet_office/src/xlsx/number_format.dart' show isDateFormat;

import 'write_model_sample.dart' as sample;

void main(List<String> args) {
  exitCode = editModel(args, out: stdout, err: stderr);
}

/// The string the tool sets, and the one on the added sheet.
const String _text = 'edited by the model';
const String _addedText = 'added sheet';

/// The style the tool sets on the new row's cells, over the style they have.
const XlsxStyle _style = XlsxStyle(
  font: XlsxFont(bold: true),
  fill: XlsxFill.solid(_red),
);
const XlsxColor _red = XlsxColor.rgb(0xFF0000);

/// The number of cells the tool sets in the new row.
const int _cells = 4;

/// The width of column B, the height of the new row, and the tab colour.
const double _width = 30;
const double _height = 24;
const XlsxColor _tabColor = XlsxColor.rgb(0x00B050);

/// The pane that freezes the first row.
const XlsxPane _frozen = XlsxPane.frozen(rows: 1);

/// The two cells right of the new values in [row].
XlsxRange _mergedIn(int row) => XlsxRange(row, _cells, row, _cells + 1);

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
    out.writeln('generated workbooks: generating failed: $e');
    failed++;
  }
  out.writeln(
    failed == 0
        ? 'All ${files.length} workbooks edited, and w1_generated.xlsx and '
              'w2_generated.xlsx written.'
        : '$failed failed.',
  );
  return failed == 0 ? 0 : 1;
}

/// Edits [file], writes the result to [output], and returns the problems.
List<String> _edit(File file, Directory output, String name) {
  final Uint8List saved;
  final int row;
  final Set<int> formatted;
  final String added;
  try {
    final XlsxWorkbook book = XlsxWorkbook.open(file.readAsBytesSync());
    final XlsxSheet sheet = book.sheets.first;
    row = _freeRow(sheet);
    formatted = <int>{
      for (final int column in <int>[0, 1])
        if (showsNoDate(sheet.styleAt(row, column))) column,
    };
    sheet
      ..setCell(row, 0, DateTime.utc(2026, 11, 2, 13, 45))
      ..setCell(row, 1, const XlsxDate(2026, 11, 2))
      ..setCell(row, 2, const XlsxFormula('SUM(1,2)', cached: 3))
      ..setCell(row, 3, _text);
    _styleAndLayOut(sheet, row);
    added = _freeName(book, 'Model edit');
    book.addSheet(added).setCell(0, 0, _addedText);
    saved = book.save().bytes;
  } on Object catch (e) {
    return <String>['the edit failed: $e'];
  }
  File('${output.path}/$name').writeAsBytesSync(saved);
  return _check(saved, row, added, formatted);
}

/// Whether [style] sets a number format that shows no date: not General,
/// which a date replaces, and not a date format. A date set in such a cell
/// keeps the format and reads back as a number.
bool showsNoDate(XlsxStyle? style) {
  final XlsxNumFmt? format = style?.numFmt;
  return format != null &&
      format != XlsxNumFmt.general &&
      !isDateFormat(format);
}

/// Sets the style of the new cells of [row] and the layout edits on [sheet].
void _styleAndLayOut(XlsxSheet sheet, int row) {
  for (int column = 0; column < _cells; column++) {
    final XlsxStyle own = sheet.styleAt(row, column) ?? const XlsxStyle();
    sheet.setStyle(row, column, own.merge(_style));
  }
  final XlsxColumn? b = sheet.column(1);
  sheet
    ..setColumn(
      1,
      XlsxColumn(
        width: _width,
        style: b?.style,
        hidden: b?.hidden ?? false,
        outlineLevel: b?.outlineLevel ?? 0,
        collapsed: b?.collapsed ?? false,
      ),
    )
    ..setRowFormat(row, const XlsxRowFormat(height: _height))
    ..merge(_mergedIn(row))
    ..view = sheet.view.copyWith(pane: _frozen)
    ..tabColor = _tabColor;
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

/// The edits [saved] lacks when read back with `XlsxReader`. A date in one
/// of the columns [formatted] may read as the number its format shows.
List<String> _check(
  Uint8List saved,
  int row,
  String added,
  Set<int> formatted,
) {
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

    bool holdsDate(int column) {
      final Object? value = valueAt(column);
      return value is DateTime ||
          (formatted.contains(column) &&
              (value is num || value is XlsxDecimal));
    }

    if (!holdsDate(0)) problems.add('the DateTime is missing');
    if (!holdsDate(1)) problems.add('the XlsxDate is missing');
    if (!cells.any((XlsxReadCell c) => c.column == 2 && c.formula != null)) {
      problems.add('the formula is missing');
    }
    if (valueAt(3) != _text) problems.add('the string is missing');
    final int last = reader.sheets.length - 1;
    if (reader.sheets[last].name != added ||
        reader.rowsAt(last).first.cells.first.value != _addedText) {
      problems.add('the added sheet is missing');
    }
    bool isDate(int column) =>
        formatted.contains(column) ||
        cells.any((XlsxReadCell c) => c.column == column && c.isDate);
    if (!isDate(0) || !isDate(1)) problems.add('a date lost its format');
    if (!reader.mergesAt(0).contains(_mergedIn(row))) {
      problems.add('the merge is missing from the reader');
    }
    problems.addAll(_checkModel(XlsxWorkbook.open(saved).sheets.first, row));
  } on Object catch (e) {
    problems.add('reading the saved workbook failed: $e');
  }
  return problems;
}

/// The style and layout edits [sheet] lacks.
List<String> _checkModel(XlsxSheet sheet, int row) => <String>[
  for (int column = 0; column < _cells; column++)
    if (sheet.styleAt(row, column)?.font?.bold != true ||
        sheet.styleAt(row, column)?.fill != _style.fill)
      'the style of column $column is missing',
  if (sheet.column(1)?.width != _width) 'the width is missing',
  if (sheet.rowFormat(row).height != _height) 'the height is missing',
  if (!sheet.merges.contains(_mergedIn(row))) 'the merge is missing',
  if (sheet.view.pane != _frozen) 'the frozen row is missing',
  if (sheet.tabColor != _tabColor) 'the tab colour is missing',
];
