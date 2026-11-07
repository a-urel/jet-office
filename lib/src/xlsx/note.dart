/// Notes, the classic cell comments: [XlsxNote], the checks a note passes
/// when it is added to a sheet, and the two parts that hold a sheet's
/// notes, the comments part (`xl/comments{n}.xml`, the text and authors)
/// and the VML drawing (`xl/drawings/vmlDrawing{n}.vml`, the boxes Excel
/// shows).
///
/// New in jet_office. quds_office_engine's comments writer
/// (`_writeSheetExtras` in `lib/src/sheet/serial/sheet_serial.dart` at
/// commit 15c5d29) is broken, so nothing of it is ported. It writes
/// `<comments>` without the SpreadsheetML namespace, puts an `author`
/// attribute on each `comment` instead of an `authors` list and an
/// `authorId`, leaves out `commentList`, and writes the text straight into
/// `<text>` with no `<t>` or `<r>` run. It registers the part with the
/// shared strings content type, gives the sheet no relationship to it, and
/// writes no VML drawing and no `legacyDrawing`, so Excel shows no note.
library;

import '../opc/ooxml.dart';
import '../xml/xml_escape.dart';
import '../xml/xml_writer.dart';
import 'cell_ref.dart';
import 'font.dart';
import 'limits.dart';
import 'rich_text.dart';
import 'warnings.dart';

/// A note on a cell: the text Excel shows in a yellow box when the cell is
/// hovered, or all the time when the note is [visible].
///
/// Excel calls these notes; older versions and the file format call them
/// comments. A threaded comment, the newer kind, is not written.
///
/// The text is data, like cell text: characters XML forbids are removed and
/// text past 32,767 UTF-16 code units is cut, with warnings at the note's
/// cell. A run's font is written as given, not merged over a cell font, and
/// a run without a font shows Excel's note font. The author and the runs
/// are a programmer's choice: a text without runs, an invalid run font and
/// an author longer than 255 UTF-16 code units or holding a character XML
/// forbids are refused. The `const` constructor cannot check anything; the
/// sheet writer does when the note is added (see `XlsxSheetWriter.note`).
///
/// ```dart
/// sheet.note(1, 2, XlsxNote.plain('Checked by finance.', author: 'Ayşe'));
/// ```
final class XlsxNote {
  /// Creates a note of [text] by [author], shown only on hover unless
  /// [visible].
  const XlsxNote(this.text, {this.author = '', this.visible = false});

  /// Creates a note of the plain [text], one run without a font.
  factory XlsxNote.plain(
    String text, {
    String author = '',
    bool visible = false,
  }) => XlsxNote(
    XlsxRichText(<XlsxTextRun>[XlsxTextRun(text)]),
    author: author,
    visible: visible,
  );

  /// The text of the note, in runs that may have their own fonts.
  final XlsxRichText text;

  /// The name of the note's author, kept with the note; empty for none.
  /// It is not part of the text: a bold author line, as Excel starts a new
  /// note with, belongs in [text].
  final String author;

  /// Whether the note is shown all the time, not only on hover.
  final bool visible;

  @override
  bool operator ==(Object other) =>
      other is XlsxNote &&
      other.text == text &&
      other.author == author &&
      other.visible == visible;

  @override
  int get hashCode => Object.hash(text, author, visible);

  @override
  String toString() => 'XlsxNote($text, author: $author, visible: $visible)';
}

/// Checks what a programmer chose for a note on the zero-based cell
/// ([row], [column]) of the sheet [sheet]: the cell, the author and the
/// runs of the text. The text itself is data, cleaned later with
/// [cleanRichText].
///
/// Throws [ArgumentError] named `row` or `column` for a cell outside the
/// sheet; named `author` for an author longer than
/// [XlsxLimits.maxNoteAuthorLength] UTF-16 code units or holding a
/// character XML forbids; named `runs` for a text without runs; and named
/// `runs[i].font.<field>` for a run whose font fails [validateFont], with
/// the value and stack of that check. A run's font is checked as given:
/// a note's run fonts are written as given, not merged over a cell font.
void checkNote(String sheet, int row, int column, XlsxNote note) {
  if (row < 0 || row >= XlsxLimits.maxRows) {
    throw ArgumentError.value(
      row,
      'row',
      'A note must be on a row within 0..${XlsxLimits.maxRows - 1}.',
    );
  }
  if (column < 0 || column >= XlsxLimits.maxColumns) {
    throw ArgumentError.value(
      column,
      'column',
      'A note must be on a column within 0..${XlsxLimits.maxColumns - 1}.',
    );
  }
  final String ref = cellRef(row, column);
  final String author = note.author;
  if (author.length > XlsxLimits.maxNoteAuthorLength) {
    throw ArgumentError.value(
      '${author.length} characters',
      'author',
      'The author of the note on cell $ref on sheet "$sheet" has at most '
          '${XlsxLimits.maxNoteAuthorLength} characters.',
    );
  }
  if (scrubXmlText(author).removed > 0) {
    throw ArgumentError.value(
      author,
      'author',
      'The author of the note on cell $ref on sheet "$sheet" must not '
          'contain characters XML forbids.',
    );
  }
  final List<XlsxTextRun> runs = note.text.runs;
  if (runs.isEmpty) {
    throw ArgumentError.value(
      runs,
      'runs',
      'The note on cell $ref on sheet "$sheet" has no runs.',
    );
  }
  for (int i = 0; i < runs.length; i++) {
    final XlsxFont? font = runs[i].font;
    if (font == null) continue;
    try {
      validateFont(font);
    } on ArgumentError catch (error, stack) {
      final String? field = error.name;
      Error.throwWithStackTrace(
        ArgumentError.value(
          error.invalidValue,
          field == null ? 'runs[$i].font' : 'runs[$i].font.$field',
          'The font of run $i of the note on cell $ref on sheet "$sheet" is '
          'invalid: ${error.message}',
        ),
        stack,
      );
    }
  }
}

/// How many note shapes one VML id block numbers.
const int vmlBlockSize = 1024;

/// How many VML id blocks a sheet of [noteCount] notes (at least one)
/// takes: `noteCount ~/ 1024 + 1`.
///
/// The shape ids of a sheet whose first block is b run from
/// `1024 × b + 1` to `1024 × b + noteCount`, and id n lies in block
/// `n ~/ 1024`, so the last one lies in block `b + noteCount ~/ 1024`.
/// 1,023 notes take one block; 1,024 and 1,025 take two, as `_x0000_s2048`
/// lies in block 2 of a sheet whose first block is 1.
int vmlBlockCount(int noteCount) => noteCount ~/ vmlBlockSize + 1;

/// The `x:Anchor` of the box of a note on the zero-based cell ([row],
/// [column]): left column, left offset, top row, top offset, right column,
/// right offset, bottom row and bottom offset, as Excel writes a new note.
///
/// The box starts in the column right of the cell and ends two columns
/// further (left = column + 1, right = column + 3); when that would pass
/// the last column it lies left of the cell instead (left = column − 3,
/// right = column − 1). It starts in the row above the cell (row 0 for the
/// first row), offset 2 in the first row and 10 otherwise, and ends four
/// rows lower, offset 16 in the first row and 4 otherwise; when that would
/// pass the last row it moves up to end there. The column offsets are 15.
/// So the box always lies inside the sheet.
String noteAnchor(int row, int column) {
  const int lastRow = XlsxLimits.maxRows - 1;
  const int lastColumn = XlsxLimits.maxColumns - 1;
  int left = column + 1;
  int right = column + 3;
  if (right > lastColumn) {
    left = column - 3;
    right = column - 1;
  }
  int top = row == 0 ? 0 : row - 1;
  int bottom = top + 4;
  if (bottom > lastRow) {
    bottom = lastRow;
    top = bottom - 4;
  }
  final int topOffset = row == 0 ? 2 : 10;
  final int bottomOffset = row == 0 ? 16 : 4;
  return '$left, 15, $top, $topOffset, $right, 15, $bottom, $bottomOffset';
}

/// A note as a sheet holds it until the sheet finishes: its zero-based
/// cell, its text cleaned with [cleanRichText], its author and whether it
/// is shown all the time.
typedef WorksheetNote = ({
  int row,
  int column,
  XlsxRichText text,
  String author,
  bool visible,
});

/// [note] on the zero-based cell ([row], [column]) as a sheet holds it, its
/// text cleaned with [cleanRichText]. [warn] hears
/// `invalidCharactersRemoved` when characters were removed and
/// `textTruncated` when the text was cut.
///
/// The note must have passed [checkNote].
WorksheetNote cleanNote(
  int row,
  int column,
  XlsxNote note,
  void Function(XlsxWarningCode code) warn,
) {
  final ({XlsxRichText text, int removed, bool truncated}) clean =
      cleanRichText(note.text);
  if (clean.removed > 0) warn(XlsxWarningCode.invalidCharactersRemoved);
  if (clean.truncated) warn(XlsxWarningCode.textTruncated);
  return (
    row: row,
    column: column,
    text: clean.text,
    author: note.author,
    visible: note.visible,
  );
}

/// Writes the comments part of a sheet's [notes], XML declaration
/// included, to [w].
///
/// [notes] come sorted by row, then column, and are written in that order.
/// `authors` lists each distinct author once, in the order the notes use
/// them first; each `comment` names its author by index (`authorId`).
/// Authors and text are `ST_Xstring`, so they go through [escapeXstring].
/// A note whose text is one run without a font is written as one `<t>`,
/// like a plain shared string; a note left with no runs as an empty
/// `<t>`; any other as `<r>` runs (see [writeTextRuns]), each run's font
/// as given.
void writeComments(XmlWriter w, List<WorksheetNote> notes) {
  final Map<String, int> authors = <String, int>{};
  for (final WorksheetNote note in notes) {
    authors.putIfAbsent(note.author, () => authors.length);
  }
  w.declaration();
  w.start('comments');
  w.attribute('xmlns', Ns.main);
  w.start('authors');
  for (final String author in authors.keys) {
    w.start('author');
    w.text(escapeXstring(author));
    w.end();
  }
  w.end();
  w.start('commentList');
  for (final WorksheetNote note in notes) {
    writeCommentEntry(w, note, authors[note.author]!);
  }
  w.end();
  w.end();
}

/// Writes the `<comment>` of [note], whose author is entry [authorId] of
/// the part's `authors`, to [w].
void writeCommentEntry(XmlWriter w, WorksheetNote note, int authorId) {
  w.start('comment');
  w.attribute('ref', cellRef(note.row, note.column));
  w.attribute('authorId', '$authorId');
  writeCommentText(w, note.text);
  w.end();
}

/// Writes the `<text>` of a `<comment>` holding [text] to [w], as
/// [writeComments] says.
void writeCommentText(XmlWriter w, XlsxRichText text) {
  w.start('text');
  final List<XlsxTextRun> runs = text.runs;
  if (runs.isEmpty) {
    writeTextElement(w, '');
  } else if (runs.length == 1 && runs.single.font == null) {
    writeTextElement(w, runs.single.text);
  } else {
    writeTextRuns(w, text);
  }
  w.end();
}

/// Writes the VML drawing of a sheet's [notes], XML declaration included,
/// to [w]: one note box per note, in the order given, hidden unless the
/// note is visible, in the markup Excel writes for a new note.
///
/// The sheet's id blocks are the [vmlBlockCount] blocks from [firstBlock]
/// on, which `o:idmap` lists. Shape `i`
/// (from 0) is `_x0000_s{1024 × firstBlock + i + 1}` with z-index `i + 1`
/// (see [vmlShape]). Every value written is a number or a constant, so
/// nothing needs escaping.
void writeVmlDrawing(XmlWriter w, List<WorksheetNote> notes, int firstBlock) {
  final int blocks = vmlBlockCount(notes.length);
  w.declaration();
  w.raw(
    '<xml xmlns:v="${Ns.vml}" xmlns:o="${Ns.vmlOffice}" '
    'xmlns:x="${Ns.vmlExcel}">'
    '${vmlShapeLayout(<int>[for (int b = 0; b < blocks; b++) firstBlock + b])}'
    '${vmlNoteShapeType()}',
  );
  for (int i = 0; i < notes.length; i++) {
    w.raw(vmlShape(vmlBlockSize * firstBlock + i + 1, i + 1, notes[i]));
  }
  w.raw('</xml>');
}

/// The `<o:shapelayout>` listing the id [blocks] in its `o:idmap`.
/// [declarations] goes on its start tag, for a part whose root does not bind
/// the prefixes.
String vmlShapeLayout(List<int> blocks, {String declarations = ''}) =>
    '<o:shapelayout$declarations v:ext="edit"><o:idmap v:ext="edit" data="'
    '${blocks.join(',')}"/></o:shapelayout>';

/// The `<v:shapetype>` a note's box names. [declarations] goes on its start
/// tag, as for [vmlShapeLayout].
String vmlNoteShapeType({String declarations = ''}) =>
    '<v:shapetype$declarations id="_x0000_t202" coordsize="21600,21600" '
    'o:spt="202" path="m,l,21600r21600,l21600,xe">'
    '<v:stroke joinstyle="miter"/>'
    '<v:path gradientshapeok="t" o:connecttype="rect"/></v:shapetype>';

/// The `<v:shape>` of the box of [note], with the id `_x0000_s{id}` and
/// [zIndex]: hidden unless the note is visible. Its `x:Anchor` is
/// [noteAnchor] of its cell, and `x:Row` and `x:Column` name the cell,
/// zero-based. [declarations] goes on its start tag, as for
/// [vmlShapeLayout].
String vmlShape(
  int id,
  int zIndex,
  WorksheetNote note, {
  String declarations = '',
}) {
  final String visibility = note.visible ? 'visible' : 'hidden';
  return '<v:shape$declarations id="_x0000_s$id" '
      'type="#_x0000_t202" style="position:absolute;margin-left:59.25pt;'
      'margin-top:1.5pt;width:108pt;height:59.25pt;z-index:$zIndex;'
      'visibility:$visibility" fillcolor="#ffffe1" o:insetmode="auto">'
      '<v:fill color2="#ffffe1"/>'
      '<v:shadow on="t" color="black" obscured="t"/>'
      '<v:path o:connecttype="none"/>'
      '<v:textbox style="mso-direction-alt:auto">'
      '<div style="text-align:left"></div></v:textbox>'
      '<x:ClientData ObjectType="Note"><x:MoveWithCells/><x:SizeWithCells/>'
      '<x:Anchor>${noteAnchor(note.row, note.column)}</x:Anchor>'
      '<x:AutoFill>False</x:AutoFill><x:Row>${note.row}</x:Row>'
      '<x:Column>${note.column}</x:Column>'
      '${note.visible ? '<x:Visible/>' : ''}</x:ClientData></v:shape>';
}
