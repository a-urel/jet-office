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
/// sets a tab colour. Before all of that it edits the structure: it sets a
/// probe in the row after the last row, the string `moved by the model` in
/// C and the formula `C<n>&"!"` pointing at it in A, inserts two rows above
/// the sheet's last row (row 1 when it has none) and one column at B, and
/// renames the sheet `Model edit` (`Model edit 2` and so on when the name
/// is taken); `XlsxReader` must find the probe two rows lower, the string in
/// D and the formula pointing at its new cell. Between the probe and the
/// structural edits it writes, with `writeChartData`, the data of a column
/// chart of two series over three categories two rows below the probe from
/// column N, and adds the chart over it (`Model column chart`, a two-cell
/// anchor of 8 columns by 15 rows from column R), left out when a row from
/// the one below the probe is taken. The model must list it typed after the
/// save, moved by the structural edits with its cells and its series bound
/// to them on the renamed sheet. After the structural edits, when the first
/// sheet had a chart that listed typed, the first one takes the title
/// `Model chart` (`replaceChartAt`) and moves one row down (`moveChartAt`),
/// both read back through the model. The new row is the one after the
/// probe. It then adds a sheet named as the first one would be (so
/// `Model edit 2`, or the next free number) holding one string, saves, and writes the
/// bytes to `<outDir>/<name>.xlsx`. The saved file is read back with
/// `XlsxReader` (values, number formats, merges) and with `XlsxWorkbook`
/// (styles, width, height, merges, pane, tab colour), and the edits must be
/// there. The features come next, on the same sheet: the workbook name
/// `Model_edit` (`Model_edit2` and so on when the name is taken), a link on
/// the new string cell, a list validation on column G of the new row, a
/// cell-value rule with a fill on column H and a data bar on column I, a
/// landscape A4 page setup that fits one page wide, a footer, an auto filter
/// over the new row (left out when the sheet has a filter or a table in the
/// way) and the workbook's title. Each is read back through the model. No
/// protection is set, as it would lock the owner's review. The objects follow,
/// in the same row: a rich text cell in J (`Rich ` bold, `text` plain), a note
/// on K by `jet_office`, a 4 by 2 pixel PNG at L as a one-cell picture, and a
/// table `Model_table` (`Model_table2` and so on when the name is taken, by a
/// table or a defined name) of two columns over the two rows below the new
/// row, a header and a data row (left out when a cell there is not free). Each
/// is read back through the model. Last it writes the workbooks
/// `tool/write_model_sample.dart` makes, `w1_generated.xlsx`,
/// `w2_generated.xlsx`, `w3_generated.xlsx`, `w4_generated.xlsx` and
/// `w5_generated.xlsx`, to the same directory.
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

import '../test/fixtures/m4_fixtures.dart' show png4x2;
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

/// The link the tool sets on the string cell of the new row: its text is the
/// string.
const XlsxHyperlink _link = XlsxHyperlink(
  address: 'https://example.com/jet-office',
  text: _text,
  tooltip: 'set by the model',
);

/// The workbook name's base, the title and the footer the tool sets, and the
/// first free columns of the new row, for the validation, the rule and the
/// data bar.
const String _nameBase = 'Model_edit';
const String _title = 'Edited by jet_office';
const String _footer = '&CPage &P of &N';
const int _validationColumn = 6;
const int _ruleColumn = 7;
const int _barColumn = 8;

/// The columns of the new row that take the rich text, the note and the
/// picture, and the table's base name.
const int _richColumn = 9;
const int _noteColumn = 10;
const int _pictureColumn = 11;
const String _tableBase = 'Model_table';
const String _noteAuthor = 'jet_office';

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
        ? 'All ${files.length} workbooks edited, and w1_generated.xlsx, '
              'w2_generated.xlsx, w3_generated.xlsx, w4_generated.xlsx and '
              'w5_generated.xlsx written.'
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
  final _Features features;
  final String? table;
  final _Structure structure;
  final _Retitled? retitled;
  try {
    final XlsxWorkbook book = XlsxWorkbook.open(file.readAsBytesSync());
    final XlsxSheet sheet = book.sheets.first;
    final int typed = sheet.charts.indexWhere(
      (XlsxSheetChart c) => c.typed != null,
    );
    structure = _editStructure(book, sheet);
    retitled = typed < 0 ? null : _retitleChart(sheet, typed);
    // The row after the probe, which the chart's data skips.
    row = structure.chartData == null ? _freeRow(sheet) : structure.row + 1;
    formatted = <int>{
      for (final int column in <int>[0, 1])
        if (showsNoDate(sheet.styleAt(row, column))) column,
    };
    sheet
      ..setCell(row, 0, DateTime.utc(2026, 11, 2, 13, 45))
      ..setCell(row, 1, const XlsxDate(2026, 11, 2))
      ..setCell(row, 2, const XlsxFormula('SUM(1,2)', cached: 3))
      ..setCell(row, 3, _link);
    _styleAndLayOut(sheet, row);
    features = _addFeatures(book, sheet, row);
    table = _addObjects(book, sheet, row);
    added = _freeName(book, 'Model edit');
    book.addSheet(added).setCell(0, 0, _addedText);
    saved = book.save().bytes;
  } on Object catch (e) {
    return <String>['the edit failed: $e'];
  }
  File('${output.path}/$name').writeAsBytesSync(saved);
  return <String>[
    ..._checkStructure(saved, structure),
    ..._checkCharts(saved, structure, retitled),
    ..._check(saved, row, added, formatted, features, table),
  ];
}

/// The probe's row after the structural edits, the first sheet's new name,
/// and where the chart's data went before them (`null` when its cells were
/// not free).
typedef _Structure = ({int row, String name, XlsxAnchorPoint? chartData});

/// The probe string and the structural edits' sheet name.
const String _probeText = 'moved by the model';
const String _renamed = 'Model edit';

/// Sets the probe on [sheet], writes the chart's data two rows below it and
/// adds the chart ([_addChart]), inserts two rows above its last row and a
/// column at B, and renames it.
_Structure _editStructure(XlsxWorkbook book, XlsxSheet sheet) {
  final int probe = _freeRow(sheet);
  final List<int> rows = <int>[for (final XlsxReadRow r in sheet.rows) r.index];
  sheet
    ..setCell(probe, 2, _probeText)
    ..setCell(
      probe,
      0,
      XlsxFormula('C${probe + 1}&"!"', cached: '$_probeText!'),
    );
  final XlsxAnchorPoint? chartData = _addChart(sheet, probe + 2);
  sheet
    ..insertRows(rows.isEmpty || rows.last > probe ? 0 : rows.last, 2)
    ..insertColumns(1);
  final String name = _freeName(book, _renamed);
  book.renameSheet(sheet, name);
  return (row: probe + 2, name: name, chartData: chartData);
}

/// The column chart the tool adds: two series over three categories, its
/// data written to the sheet.
final Chart _chart = Chart(
  kind: ChartKind.column,
  title: const ChartTitle(text: 'Edited by the model'),
  series: <ChartSeries>[
    for (final (String name, List<double> values) in <(String, List<double>)>[
      ('Plan', <double>[12, 18, 9.5]),
      ('Actual', <double>[14, 16.25, 11]),
    ])
      ChartSeries(
        name: ChartData<String>(values: <String?>[name]),
        categories: ChartData<Object>(values: <Object?>['A', 'B', 'C']),
        values: ChartData<double>(values: values),
      ),
  ],
);

/// The added chart frame's name, the first column of its data, and the
/// title the tool gives a typed chart of the file.
const String _chartName = 'Model column chart';
const int _chartColumn = 13;
const String _chartTitle = 'Model chart';

/// Writes the data of [_chart] at [row] of [sheet] from column N, a block of
/// four rows and three columns, and adds the chart over it, bound to the
/// cells, as a two-cell anchor of 8 columns by 15 rows right of the block.
/// Returns where the block starts, or `null`, adding nothing, unless every
/// row from the one above it is free (so the row between the probe and the
/// block stays the new row) and the chart fits on the sheet.
XlsxAnchorPoint? _addChart(XlsxSheet sheet, int row) {
  if (row + 15 >= XlsxLimits.maxRows) return null;
  final int last = sheet.rows.isEmpty ? -1 : sheet.rows.last.index;
  if (last >= row - 1) return null;
  final Chart bound = sheet.writeChartData(_chart, row, _chartColumn);
  const int right = _chartColumn + 4;
  sheet.addChart(
    XlsxChart(
      bound,
      XlsxTwoCellAnchor(
        XlsxAnchorPoint(row, right),
        XlsxAnchorPoint(row + 15, right + 8),
      ),
      name: _chartName,
    ),
  );
  return XlsxAnchorPoint(row, _chartColumn);
}

/// Where [_retitleChart] moved the chart at `index`.
typedef _Retitled = ({int index, XlsxAnchor anchor});

/// Gives the typed chart at [index] of [sheet]'s charts the title
/// [_chartTitle] and moves it one row down, and returns where it went, or
/// `null` when it lists typed no more or one row down is off the sheet.
_Retitled? _retitleChart(XlsxSheet sheet, int index) {
  final XlsxSheetChart chart = sheet.charts[index];
  final XlsxChart? typed = chart.typed;
  if (typed == null) return null;
  XlsxAnchorPoint down(XlsxAnchorPoint p) => XlsxAnchorPoint(
    p.row + 1,
    p.column,
    offsetX: p.offsetX,
    offsetY: p.offsetY,
  );
  final XlsxAnchor? moved = switch (chart.anchor) {
    final XlsxTwoCellAnchor a when a.to.row + 1 < XlsxLimits.maxRows =>
      XlsxTwoCellAnchor(down(a.from), down(a.to), resize: a.resize),
    final XlsxOneCellAnchor a when a.from.row + 1 < XlsxLimits.maxRows =>
      XlsxOneCellAnchor(down(a.from), width: a.width, height: a.height),
    _ => null,
  };
  if (moved == null) return null;
  sheet
    ..replaceChartAt(
      index,
      typed.chart.copyWith(title: const ChartTitle(text: _chartTitle)),
      theme: typed.theme,
    )
    ..moveChartAt(index, moved);
  return (index: index, anchor: moved);
}

/// The chart edits [saved] lacks when read back with the model: the added
/// chart typed and bound to its data where the structural edits moved it,
/// on the renamed sheet, and the retitled chart's title and anchor.
List<String> _checkCharts(
  Uint8List saved,
  _Structure structure,
  _Retitled? retitled,
) {
  final List<String> problems = <String>[];
  try {
    final List<XlsxSheetChart> charts = XlsxWorkbook.open(
      saved,
    ).sheets.first.charts;
    final XlsxAnchorPoint? data = structure.chartData;
    if (data != null) {
      // Two rows inserted above the block and a column at B.
      final int row = data.row + 2;
      final int column = data.column + 1;
      final String sheet = "'${structure.name.replaceAll("'", "''")}'!";
      String cell(int r, int c) => '\$${_letters(c)}\$${r + 1}';
      String cells(int c) => '$sheet${cell(row + 1, c)}:${cell(row + 3, c)}';
      final List<XlsxSheetChart> added = <XlsxSheetChart>[
        for (final XlsxSheetChart c in charts)
          if (c.name == _chartName) c,
      ];
      final List<ChartSeries>? series = added.length == 1
          ? added.single.typed?.chart.series
          : null;
      if (series == null || series.length != 2) {
        problems.add('the added chart is missing or not typed');
      } else {
        if (added.single.anchor.from != XlsxAnchorPoint(row, column + 4)) {
          problems.add('the added chart did not move with its cells');
        }
        for (int i = 0; i < 2; i++) {
          final ChartSeries s = series[i];
          if (s.name.reference != '$sheet${cell(row, column + 1 + i)}' ||
              s.categories.reference != cells(column) ||
              s.values.reference != cells(column + 1 + i)) {
            problems.add(
              'series ${i + 1} of the added chart is bound to '
              '${s.name.reference}, ${s.categories.reference} and '
              '${s.values.reference}',
            );
          }
        }
      }
    }
    if (retitled != null) {
      final XlsxSheetChart? chart = retitled.index < charts.length
          ? charts[retitled.index]
          : null;
      if (chart?.view?.title?.text != _chartTitle) {
        problems.add('the replaced chart lacks its title');
      }
      if (chart?.anchor != retitled.anchor) {
        problems.add('the replaced chart did not move one row down');
      }
    }
  } on Object catch (e) {
    problems.add('reading the charts failed: $e');
  }
  return problems;
}

/// The column letters of the 0-based [column].
String _letters(int column) {
  String letters = '';
  for (int c = column + 1; c > 0; c = (c - 1) ~/ 26) {
    letters = String.fromCharCode(0x41 + (c - 1) % 26) + letters;
  }
  return letters;
}

/// The structural edits [saved] lacks when read back with `XlsxReader`.
List<String> _checkStructure(Uint8List saved, _Structure structure) {
  final List<String> problems = <String>[];
  try {
    final XlsxReader reader = XlsxReader(saved);
    if (reader.sheets.first.name != structure.name) {
      problems.add('the first sheet is not renamed ${structure.name}');
    }
    final List<XlsxReadCell> cells = <XlsxReadCell>[
      for (final XlsxReadRow r in reader.rowsAt(0))
        if (r.index == structure.row) ...r.cells,
    ];
    XlsxReadCell? at(int column) {
      for (final XlsxReadCell c in cells) {
        if (c.column == column) return c;
      }
      return null;
    }

    if (at(3)?.value != _probeText) {
      problems.add('the probe string did not move to D${structure.row + 1}');
    }
    final String follows = 'D${structure.row + 1}&"!"';
    if (at(0)?.formula != follows) {
      problems.add('the probe formula is ${at(0)?.formula}, not $follows');
    }
  } on Object catch (e) {
    problems.add('reading the structural edits failed: $e');
  }
  return problems;
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
  _Features features,
  String? table,
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
    final XlsxWorkbook model = XlsxWorkbook.open(saved);
    problems
      ..addAll(_checkModel(model.sheets.first, row))
      ..addAll(_checkFeatures(model, row, features))
      ..addAll(_checkObjects(model.sheets.first, row, table));
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

/// What [_addFeatures] set, for [_checkFeatures] to look for.
typedef _Features = ({String name, bool filtered});

/// Sets the features on [sheet] and the workbook: the name, a validation, two
/// conditional formats, the page setup, a footer, an auto filter over [row]
/// when none is in the way, and the title.
_Features _addFeatures(XlsxWorkbook book, XlsxSheet sheet, int row) {
  final Set<String> taken = <String>{
    for (final XlsxDefinedName n in book.definedNames) n.name.toLowerCase(),
  };
  String name = _nameBase;
  for (int n = 2; taken.contains(name.toLowerCase()); n++) {
    name = '$_nameBase$n';
  }
  final String quoted = sheet.name.replaceAll("'", "''");
  book.defineName(XlsxDefinedName(name, "'$quoted'!\$A\$1"));
  sheet
    ..addDataValidation(
      XlsxDataValidation(
        <XlsxRange>[XlsxRange(row, _validationColumn)],
        XlsxValidationType.list,
        formula1: '"yes,no"',
      ),
    )
    ..addConditionalFormat(
      XlsxConditionalFormat(
        <XlsxRange>[XlsxRange(row, _ruleColumn)],
        <XlsxConditionalRule>[
          const XlsxCellValueRule(
            XlsxComparison.greaterThan,
            '0',
            style: XlsxStyle(fill: XlsxFill.solid(XlsxColor.rgb(0xFFFF00))),
          ),
        ],
      ),
    )
    ..addConditionalFormat(
      XlsxConditionalFormat(
        <XlsxRange>[XlsxRange(row, _barColumn)],
        <XlsxConditionalRule>[
          const XlsxDataBar(color: XlsxColor.rgb(0x638EC6)),
        ],
      ),
    );
  final XlsxPageSetup? setup = sheet.pageSetup;
  sheet.pageSetup = XlsxPageSetup(
    orientation: XlsxOrientation.landscape,
    paperSize: XlsxPaperSize.a4,
    fitToWidth: 1,
    firstPageNumber: setup?.firstPageNumber,
    pageOrder: setup?.pageOrder,
    blackAndWhite: setup?.blackAndWhite ?? false,
    draft: setup?.draft ?? false,
    margins: setup?.margins ?? const XlsxPageMargins(),
    centerHorizontally: setup?.centerHorizontally ?? false,
    centerVertically: setup?.centerVertically ?? false,
    printGridLines: setup?.printGridLines ?? false,
    printHeadings: setup?.printHeadings ?? false,
  );
  final XlsxHeaderFooter? own = sheet.headerFooter;
  sheet.headerFooter = XlsxHeaderFooter(
    oddHeader: own?.oddHeader,
    oddFooter: _footer,
    evenHeader: own?.evenHeader,
    evenFooter: own?.evenFooter,
    firstHeader: own?.firstHeader,
    firstFooter: own?.firstFooter,
    differentOddEven: own?.differentOddEven,
    differentFirst: own?.differentFirst,
    scaleWithDocument: own?.scaleWithDocument ?? true,
    alignWithMargins: own?.alignWithMargins ?? true,
  );
  final bool filtered = _filter(sheet, row);
  final OfficeProperties props = book.properties;
  book.properties = props.copyWith(title: _title);
  return (name: name, filtered: filtered);
}

/// Sets an auto filter over [row] when [sheet] has none, and returns whether
/// it did. A table in the way (the setter refuses with an [ArgumentError],
/// changing nothing) leaves the sheet as it is.
bool _filter(XlsxSheet sheet, int row) {
  if (sheet.autoFilter != null) return false;
  try {
    sheet.autoFilter = XlsxRange(row, 0, row, _cells - 1);
    return true;
  } on ArgumentError {
    return false;
  }
}

/// The features [model] lacks, read back through the model.
List<String> _checkFeatures(XlsxWorkbook model, int row, _Features features) {
  final XlsxSheet sheet = model.sheets.first;
  final List<XlsxConditionalFormat> formats = sheet.conditionalFormats;
  XlsxConditionalFormat? formatAt(int column) {
    for (final XlsxConditionalFormat f in formats) {
      if (f.ranges.contains(XlsxRange(row, column))) return f;
    }
    return null;
  }

  final XlsxHyperlink? link = sheet.hyperlinkAt(row, 3);
  final XlsxPageSetup? setup = sheet.pageSetup;
  return <String>[
    if (!model.definedNames.any((XlsxDefinedName n) => n.name == features.name))
      'the defined name is missing',
    if (link?.address != _link.address ||
        link?.text != _text ||
        sheet.cellAt(row, 3)?.value != _text)
      'the link is missing',
    if (!sheet.dataValidations.any(
      (XlsxDataValidation v) =>
          v.type == XlsxValidationType.list &&
          v.ranges.contains(XlsxRange(row, _validationColumn)),
    ))
      'the list validation is missing',
    if (formatAt(_ruleColumn)?.rules.single is! XlsxCellValueRule)
      'the cell-value rule is missing',
    if (formatAt(_barColumn)?.rules.single is! XlsxDataBar)
      'the data bar is missing',
    if (setup?.orientation != XlsxOrientation.landscape ||
        setup?.paperSize != XlsxPaperSize.a4 ||
        setup?.fitToWidth != 1 ||
        setup?.fitToHeight != null)
      'the page setup is missing',
    if (sheet.headerFooter?.oddFooter != _footer) 'the footer is missing',
    if (features.filtered && sheet.autoFilter != XlsxRange(row, 0, row, 3))
      'the auto filter is missing',
    if (model.properties.title != _title) 'the title is missing',
  ];
}

/// The rich text of the new row's column J: a bold run, then a plain one.
final XlsxRichText _rich = XlsxRichText(<XlsxTextRun>[
  const XlsxTextRun('Rich ', font: XlsxFont(bold: true)),
  const XlsxTextRun('text'),
]);

/// The note of the new row's column K.
final XlsxNote _note = XlsxNote.plain(
  'A note set by the model.',
  author: _noteAuthor,
);

/// Sets the rich text, the note, the picture and the table on [sheet] in and
/// below [row], and returns the table's name, or `null` when a cell the table
/// needs is not free or a table or the sheet's layout is in the way (the
/// setter refuses with an [ArgumentError], changing nothing).
String? _addObjects(XlsxWorkbook book, XlsxSheet sheet, int row) {
  sheet
    ..setCell(row, _richColumn, _rich)
    ..setNote(row, _noteColumn, _note)
    ..addPicture(
      XlsxPicture(
        OfficeImage(png4x2),
        XlsxOneCellAnchor(XlsxAnchorPoint(row, _pictureColumn)),
        name: 'Model picture',
      ),
    );
  if (row + 2 >= XlsxLimits.maxRows) return null;
  final XlsxRange range = XlsxRange(row + 1, 0, row + 2, 1);
  for (int r = range.firstRow; r <= range.lastRow; r++) {
    for (int c = range.firstColumn; c <= range.lastColumn; c++) {
      if (sheet.cellAt(r, c) != null) return null;
    }
  }
  final Set<String> taken = <String>{
    for (final XlsxDefinedName n in book.definedNames) n.name.toLowerCase(),
    for (final XlsxSheet s in book.sheets)
      for (final XlsxTable t in s.tables) t.name.toLowerCase(),
  };
  String name = _tableBase;
  for (int n = 2; taken.contains(name.toLowerCase()); n++) {
    name = '$_tableBase$n';
  }
  try {
    sheet.addTable(
      XlsxTable(name, range, const <XlsxTableColumn>[
        XlsxTableColumn('Item'),
        XlsxTableColumn('Count'),
      ]),
    );
  } on ArgumentError {
    return null;
  }
  return name;
}

/// The objects [sheet] lacks, read back through the model. [table] is the
/// name [_addObjects] gave the table, or `null` for none.
List<String> _checkObjects(XlsxSheet sheet, int row, String? table) {
  final XlsxRichText? rich = sheet.richTextAt(row, _richColumn);
  final XlsxNote? note = sheet.noteAt(row, _noteColumn);
  final List<XlsxPicture> pictures = sheet.pictures;
  final XlsxPicture? picture = pictures.isEmpty ? null : pictures.last;
  XlsxTable? found;
  for (final XlsxTable t in sheet.tables) {
    if (t.name == table) found = t;
  }
  return <String>[
    if (rich?.text != _rich.text ||
        rich?.runs.first.font?.bold != true ||
        rich?.runs.last.font?.bold == true)
      'the rich text is missing',
    if (note?.author != _noteAuthor || note?.text.text != _note.text.text)
      'the note is missing',
    if (picture?.image != OfficeImage(png4x2) ||
        picture?.anchor.from != XlsxAnchorPoint(row, _pictureColumn))
      'the picture is missing',
    if (table != null &&
        (found == null ||
            found.range != XlsxRange(row + 1, 0, row + 2, 1) ||
            found.columns.length != 2 ||
            !found.headerRow))
      'the table is missing',
  ];
}
