/// Test helper: seeded mutation fuzzing of `XlsxReader`.
///
/// [fuzzCorpus] is the set of valid packages the fuzzer starts from,
/// [fuzzCases] derives mutated copies of them from a seed, and
/// [exerciseReader] drives the whole public reader surface over one file,
/// then the workbook model's with [exerciseModel].
/// `test/xlsx/read/fuzz_test.dart` runs a fixed range of seeds in the
/// quality gate; `tool/fuzz_reader.dart` runs any range by hand.
///
/// A seed gives the same cases on the VM and in a browser: [Xorshift32]
/// stays within 32 bits, and the corpus is stored, not deflated, so its
/// bytes do not depend on the platform's deflater. Two deflated corpus
/// entries fuzz inflation; their cases may differ by platform (decision
/// 0006).
///
/// The 5 s hang bound is checked after a case returns, so a real infinite
/// loop is not reported as a hang: the test's 4-minute timeout stops it and
/// names no case. `tool/fuzz_reader.dart --verbose` writes each case to
/// stderr before it runs, so the last line names it. In the gate's fuzz
/// tests a case over the bound runs up to twice more and is a hang only
/// when every run is over it (`confirmedHang`, `test/support/timing.dart`).
library;

import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';

import '../../../fixtures/fixtures.dart';
import '../../../fixtures/m4_fixtures.dart' show png4x2;
import '../../../support/fuzz_mutations.dart';
import '../../../support/read_xlsx.dart';
import 'producers.dart';
import 'zip_builder.dart';

export '../../../support/fuzz_mutations.dart'
    show FuzzCase, Xorshift32, mutatedPart;

/// The fixtures of `allFixtures()` in the corpus: `m1_values`, the smallest
/// fixture with a formula, the smallest with a date format, the smallest
/// whose styles reach columns, rows and cells, `c1_kinds`, a drawing of
/// twelve chart parts (C1), which the reader and the model keep as they are,
/// and `c2_kinds`, seven charts of the C2 kinds the model added over data it
/// wrote.
const List<String> _corpusFixtures = <String>[
  'm1_values',
  'm1_formulas',
  'm1_dates',
  'm2_style_precedence',
  'c1_kinds',
  'c2_kinds',
];

/// The corpus entries also added deflated, to fuzz inflation.
const List<String> _deflated = <String>['m1_values', 'libreoffice'];

/// The valid packages the fuzzer mutates, in a fixed order.
///
/// The fixtures named in `_corpusFixtures` and every `producerFiles()`
/// entry, each rebuilt with stored entries and a fixed timestamp, so the
/// bytes are equal on every platform; then `m1_values` and `libreoffice`
/// deflated, named with a `_deflated` suffix.
List<({String name, Uint8List bytes})> fuzzCorpus() {
  final Map<String, Uint8List> sources = <String, Uint8List>{
    for (final Fixture f in allFixtures())
      if (_corpusFixtures.contains(f.name)) f.name: f.build(),
    for (final ProducerFile p in producerFiles()) p.name: p.bytes,
  };
  return <({String name, Uint8List bytes})>[
    for (final MapEntry<String, Uint8List> source in sources.entries)
      (name: source.key, bytes: _rebuild(source.value, store: true)),
    for (final String name in _deflated)
      (name: '${name}_deflated', bytes: _rebuild(sources[name]!, store: false)),
  ];
}

/// [zip] with the same entries in the same order, written again.
Uint8List _rebuild(Uint8List zip, {required bool store}) =>
    buildZipOrdered(<(String, List<int>)>[
      for (final MapEntry<String, Uint8List> e in readXlsxBytes(zip).entries)
        (e.key, e.value),
    ], store: store);

/// The entry names of the corpus package [zip], in archive order.
List<String> corpusPartNames(Uint8List zip) => readXlsxBytes(zip).keys.toList();

/// The tokens the insert mutation puts into a part: markup, references,
/// escapes and numbers that the reader's parsers treat specially.
final List<String> _tokens = <String>[
  '<',
  '>',
  '&',
  '"',
  '</c>',
  '<c r="A1">',
  '<v>',
  ' t="s"',
  ' t="d"',
  ' t="e"',
  ' r="XFD1048577"',
  '<f t="shared" si="0"/>',
  '<f t="array" ref="A1:B2">1</f>',
  '<!DOCTYPE a>',
  '_x0000_',
  '&#0;',
  'E999999999',
  '-',
  '99999999999999999999',
  '<a>' * 300,
];

/// The first [count] cases of [seed], each one mutation of one corpus
/// entry.
///
/// The entry is chosen uniformly, then one of eight operations. On the
/// archive's bytes: truncate; flip 1 to 8 bits; overwrite 4 bytes with
/// `FF FF FF FF` or `00 00 00 00`. On one part, chosen uniformly among the
/// entry's parts, after which the archive is rebuilt stored with correct
/// CRCs: truncate; delete a span of 1 to 16 bytes; duplicate such a span;
/// insert a token of `_tokens`; replace a digit with another (a part
/// without digits gets a token instead).
///
/// Lazy, and the same for the same arguments every time.
Iterable<FuzzCase> fuzzCases(int seed, int count) {
  final List<({String name, Uint8List bytes})> corpus = fuzzCorpus();
  final List<List<(String, Uint8List)>> parts = <List<(String, Uint8List)>>[
    for (final ({String name, Uint8List bytes}) entry in corpus)
      <(String, Uint8List)>[
        for (final MapEntry<String, Uint8List> e in readXlsxBytes(
          entry.bytes,
        ).entries)
          (e.key, e.value),
      ],
  ];
  return mutationCases(
    seed: seed,
    count: count,
    corpus: corpus,
    parts: parts,
    tokens: _tokens,
  );
}

/// Opens [bytes], reads every sheet's rows and merges, and renders every
/// row, every warning in English, German and Turkish, and the exception.
///
/// Then runs [exerciseModel] over the same bytes, whatever the reader did.
///
/// Returns normally or throws [XlsxReadException]. A sheet whose rows or
/// merges throw one does not stop the others: the first exception is
/// rethrown after every sheet has been read, every warning rendered and the
/// model exercised; the reader's comes before the model's. Anything else
/// thrown is a reader or model defect and propagates at once.
void exerciseReader(Uint8List bytes) {
  XlsxReadException? first;
  try {
    _exercise(bytes);
  } on XlsxReadException catch (e) {
    e.toString();
    first = e;
  }
  try {
    exerciseModel(bytes);
  } on XlsxReadException catch (e) {
    first ??= e;
  }
  if (first != null) throw first;
}

/// Opens [bytes] with [XlsxWorkbook.open], reads every sheet's rows, sets a
/// cell of the first sheet to `'x'` and reads it back, renders every
/// warning in English, German and Turkish, saves, and opens the saved
/// bytes again, reading every sheet.
///
/// The cell set is column 0 of the row after the last row the sheet's
/// `rows` yields (row 0 when it yields none, the grid's last row when the
/// last row is already the grid's), so the edit does not depend on what
/// the file holds there. It is skipped when the first sheet could not be
/// read.
///
/// Returns normally or throws [XlsxReadException], and only from `open` or
/// a sheet's first read: a sheet that throws one does not stop the others,
/// and the first is rethrown after the workbook has been saved. Whatever
/// opens saves: an opened workbook with no sheet or only hidden ones saves
/// as it came, and `open` has checked every entry's size and CRC-32.
/// `setCell` may refuse the edit as a programmer error, a [StateError] for an
/// untyped sheet part (a chartsheet, say) or a cell inside an array or
/// data-table formula and an [UnsupportedError] for a shared formula's
/// master; those are caught and ignored, which keeps this helper on the
/// public API instead of predicting the refusal from the model's
/// internals. Any other throw from `setCell`, anything at all from the
/// `cellAt` that follows it or from `save()`, is a model defect: it is
/// rethrown as a [StateError] naming the step, so an [XlsxReadException]
/// from a later step cannot pass for a refused file.
///
/// Every sheet that reads also has its `styleAt`, `rowFormat`, `column`,
/// `view`, `tabColor`, `outlineSummary`, `defaultSizes` and `merges` read,
/// and the workbook its `indexedColors`; those may throw only an
/// [XlsxReadException], kept as a sheet's first read keeps one, but the
/// sheet still counts as readable below. Its objects are read too: the rich
/// text of every string cell, its `notes`, `pictures` and `tables`. The first
/// sheet then has one style, one column, one row format and a frozen pane
/// set, on the cell of the edit above. Each may refuse the edit as its API
/// documents, a [StateError] for an untyped sheet or styles part or a
/// `<cols>` that is not plain and an `XlsxLimitError` for a file already past
/// a writer limit; any other throw is a model defect, a [StateError] naming
/// the step.
///
/// The first sheet also gets a rich text, a note, a picture and a table, and
/// loses one of each when it has one; [_editObjects] says what those may
/// refuse.
///
/// The model makes nothing worse: the saved bytes must open, and each of
/// their sheets must read, unless the same sheet of the input could not;
/// a failure there is a [StateError] too.
void exerciseModel(Uint8List bytes) {
  final XlsxWorkbook workbook = XlsxWorkbook.open(bytes);
  XlsxReadException? first;
  int? nextRow;
  final Set<int> unreadable = <int>{};
  for (int i = 0; i < workbook.sheets.length; i++) {
    final XlsxSheet sheet = workbook.sheets[i];
    sheet.name;
    sheet.visibility;
    try {
      int last = -1;
      for (final XlsxReadRow row in sheet.rows) {
        row.toString();
        last = row.index;
      }
      if (identical(sheet, workbook.sheets.first)) {
        nextRow = last + 1 < XlsxLimits.maxRows ? last + 1 : last;
      }
    } on XlsxReadException catch (e) {
      e.toString();
      first ??= e;
      unreadable.add(i);
      continue;
    }
    try {
      _readLayout(workbook, sheet);
    } on XlsxReadException catch (e) {
      first ??= e;
    }
  }
  final int? row = nextRow;
  if (row != null) {
    final XlsxSheet sheet = workbook.sheets.first;
    try {
      sheet.setCell(row, 0, 'x');
    } on StateError {
      // An untyped part or an array member: refused by design.
    } on UnsupportedError {
      // A shared formula's master: refused by design until W5.
    } on Object catch (e) {
      throw StateError('setCell($row, 0) threw: $e');
    }
    try {
      sheet.cellAt(row, 0).toString();
    } on Object catch (e) {
      throw StateError('cellAt($row, 0) threw: $e');
    }
    _editLayout(sheet, row);
    final XlsxReadException? objects = _editObjects(sheet, row);
    first ??= objects;
  }
  try {
    workbook.indexedColors.toString();
  } on XlsxReadException catch (e) {
    first ??= e;
  }
  for (final XlsxWarning warning in workbook.warnings) {
    for (final OfficeLocale locale in OfficeLocale.values) {
      warning.message(locale);
    }
  }
  final Uint8List saved;
  try {
    saved = workbook.save().bytes;
  } on Object catch (e) {
    throw StateError('save() threw: $e');
  }
  _reopen(saved, unreadable);
  if (first != null) throw first;
}

/// Reads everything of [sheet]'s look: each row's format, the style of
/// each of its cells and the column of each, the rich text of each string,
/// then the sheet's settings, resolving its tab colour with [workbook], and
/// its objects.
void _readLayout(XlsxWorkbook workbook, XlsxSheet sheet) {
  for (final XlsxReadRow row in sheet.rows) {
    sheet.rowFormat(row.index).toString();
    for (final XlsxReadCell cell in row.cells) {
      sheet.styleAt(row.index, cell.column).toString();
      sheet.column(cell.column).toString();
      if (cell.value is String) {
        sheet.richTextAt(row.index, cell.column).toString();
      }
    }
  }
  sheet.view.toString();
  final XlsxColor? tab = sheet.tabColor;
  if (tab != null) workbook.resolveColor(tab);
  sheet.outlineSummary.toString();
  sheet.defaultSizes.toString();
  sheet.merges.toString();
  sheet.notes.toString();
  sheet.pictures.toString();
  sheet.tables.toString();
}

/// Sets a style on the cell at [row], column 0, of [sheet], a column, a row
/// format and a frozen pane, each its own step. See [exerciseModel] for
/// what each may refuse.
void _editLayout(XlsxSheet sheet, int row) {
  const XlsxStyle bold = XlsxStyle(font: XlsxFont(bold: true));
  final Map<String, void Function()> edits = <String, void Function()>{
    'setStyle': () => sheet.setStyle(row, 0, bold),
    'setColumn': () =>
        sheet.setColumn(1, const XlsxColumn(width: 20, style: bold)),
    'setRowFormat': () =>
        sheet.setRowFormat(row, const XlsxRowFormat(height: 30, style: bold)),
    'view': () => sheet.view = const XlsxSheetView(
      pane: XlsxPane.frozen(rows: 1, columns: 1),
    ),
  };
  for (final MapEntry<String, void Function()> edit in edits.entries) {
    try {
      edit.value();
    } on StateError {
      // An untyped part or a <cols> that is not plain: refused by design.
    } on XlsxLimitError {
      // A file already past a writer limit: refused by design.
    } on Object catch (e) {
      throw StateError('${edit.key} threw: $e');
    }
  }
}

/// Sets a rich text on the cell at [row], column 1, of [sheet], a note on it,
/// a picture and a table, then removes the first note, picture and table,
/// each its own step, and returns the first [XlsxReadException] met.
///
/// Each may refuse the edit as its API documents: a [StateError] for an
/// untyped sheet, part or a table or note it cannot change, an
/// [UnsupportedError] for a shared formula's master, an `XlsxLimitError`
/// past a writer limit, and an [ArgumentError] for a clash with what the file
/// holds. A [RangeError], and anything else, is a model defect, a
/// [StateError] naming the step.
XlsxReadException? _editObjects(XlsxSheet sheet, int row) {
  XlsxReadException? first;
  void step(String name, void Function() edit) {
    try {
      edit();
    } on XlsxReadException catch (e) {
      first ??= e;
    } on RangeError catch (e) {
      throw StateError('$name threw: $e');
    } on StateError {
      // An untyped part, or an object the model must not change.
    } on UnsupportedError {
      // A shared formula's master: refused by design until W5.
    } on XlsxLimitError {
      // A file already past a writer limit: refused by design.
    } on ArgumentError {
      // A clash with what the file holds: a name taken, a range in use.
    } on Object catch (e) {
      throw StateError('$name threw: $e');
    }
  }

  step('setCell rich text', () {
    sheet.setCell(
      row,
      1,
      XlsxRichText(const <XlsxTextRun>[
        XlsxTextRun('x', font: XlsxFont(bold: true)),
      ]),
    );
  });
  step('setNote', () => sheet.setNote(row, 1, XlsxNote.plain('x')));
  step('addPicture', () {
    sheet.addPicture(
      XlsxPicture(
        OfficeImage(png4x2),
        XlsxOneCellAnchor(XlsxAnchorPoint(row, 2)),
      ),
    );
  });
  step('addTable', () {
    sheet.addTable(
      XlsxTable(
        'FuzzTable',
        XlsxRange.parse('XFA1:XFB2'),
        const <XlsxTableColumn>[XlsxTableColumn('One'), XlsxTableColumn('Two')],
      ),
    );
  });
  step('remove a note', () {
    final List<XlsxCellNote> notes = sheet.notes;
    if (notes.isNotEmpty) sheet.setNote(notes[0].row, notes[0].column, null);
  });
  step('removePictureAt', () {
    if (sheet.pictures.isNotEmpty) sheet.removePictureAt(0);
  });
  step('removeTable', () {
    final List<XlsxTable> tables = sheet.tables;
    if (tables.isNotEmpty) sheet.removeTable(tables[0].name);
  });
  return first;
}

/// Opens [saved] and reads every sheet's rows; only the sheets at the
/// [unreadable] positions, which the input could not read either, may
/// throw an [XlsxReadException]. Anything else is a [StateError].
void _reopen(Uint8List saved, Set<int> unreadable) {
  final XlsxWorkbook again;
  try {
    again = XlsxWorkbook.open(saved);
  } on Object catch (e) {
    throw StateError('opening the saved workbook threw: $e');
  }
  for (int i = 0; i < again.sheets.length; i++) {
    try {
      for (final XlsxReadRow row in again.sheets[i].rows) {
        row.toString();
      }
    } on XlsxReadException catch (e) {
      if (!unreadable.contains(i)) {
        throw StateError('sheet $i of the saved workbook threw: $e');
      }
    } on Object catch (e) {
      throw StateError('sheet $i of the saved workbook threw: $e');
    }
  }
}

void _exercise(Uint8List bytes) {
  final XlsxReader reader = XlsxReader(bytes);
  XlsxReadException? first;
  for (final XlsxReadSheet sheet in reader.sheets) {
    sheet.toString();
    try {
      for (final XlsxReadRow row in reader.rowsAt(sheet.index)) {
        row.toString();
      }
    } on XlsxReadException catch (e) {
      first ??= e;
    }
    try {
      reader.mergesAt(sheet.index).toString();
    } on XlsxReadException catch (e) {
      first ??= e;
    }
  }
  for (final XlsxWarning warning in reader.warnings) {
    for (final OfficeLocale locale in OfficeLocale.values) {
      warning.message(locale);
    }
  }
  if (first != null) throw first;
}
