/// Notes, the classic cell comments: [XlsxNote], the checks a note passes
/// when it is added to a sheet, and the two parts that hold a sheet's
/// notes, the comments part (`xl/comments{n}.xml`, the text and authors)
/// and the VML drawing (`xl/drawings/vmlDrawing{n}.vml`, the boxes Excel
/// shows).
///
/// New in jet_office; quds_office_engine has no comments writer.
library;

import '../opc/ooxml.dart';
import '../xml/xml_escape.dart';
import '../xml/xml_writer.dart';
import 'cell_ref.dart';
import 'font.dart';
import 'limits.dart';
import 'rich_text.dart';

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

/// How many VML id blocks a sheet of [noteCount] notes takes: one per
/// [vmlBlockSize] notes, rounded up.
int vmlBlockCount(int noteCount) =>
    (noteCount + vmlBlockSize - 1) ~/ vmlBlockSize;

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
    w.start('comment');
    w.attribute('ref', cellRef(note.row, note.column));
    w.attribute('authorId', '${authors[note.author]}');
    w.start('text');
    final List<XlsxTextRun> runs = note.text.runs;
    if (runs.isEmpty) {
      writeTextElement(w, '');
    } else if (runs.length == 1 && runs.single.font == null) {
      writeTextElement(w, runs.single.text);
    } else {
      writeTextRuns(w, note.text);
    }
    w.end();
    w.end();
  }
  w.end();
  w.end();
}

/// Writes the VML drawing of a sheet's [notes], XML declaration included,
/// to [w]: one note box per note, in the order given, hidden unless the
/// note is visible, in the markup Excel writes for a new note.
///
/// The sheet's id blocks are the [vmlBlockCount] blocks from [firstBlock]
/// on, which `o:idmap` lists. Shape `i`
/// (from 0) is `_x0000_s{1024 × firstBlock + i + 1}` with z-index `i + 1`.
/// Its `x:Anchor` is [noteAnchor] of its cell, and `x:Row` and `x:Column`
/// name the cell, zero-based. Every value written is a number or a
/// constant, so nothing needs escaping.
void writeVmlDrawing(XmlWriter w, List<WorksheetNote> notes, int firstBlock) {
  final int blocks = vmlBlockCount(notes.length);
  w.declaration();
  w.raw(
    '<xml xmlns:v="${Ns.vml}" xmlns:o="${Ns.vmlOffice}" '
    'xmlns:x="${Ns.vmlExcel}">'
    '<o:shapelayout v:ext="edit"><o:idmap v:ext="edit" data="'
    '${<int>[for (int b = 0; b < blocks; b++) firstBlock + b].join(',')}'
    '"/></o:shapelayout>'
    '<v:shapetype id="_x0000_t202" coordsize="21600,21600" o:spt="202" '
    'path="m,l,21600r21600,l21600,xe"><v:stroke joinstyle="miter"/>'
    '<v:path gradientshapeok="t" o:connecttype="rect"/></v:shapetype>',
  );
  for (int i = 0; i < notes.length; i++) {
    final WorksheetNote note = notes[i];
    final String visibility = note.visible ? 'visible' : 'hidden';
    w.raw(
      '<v:shape id="_x0000_s${vmlBlockSize * firstBlock + i + 1}" '
      'type="#_x0000_t202" style="position:absolute;margin-left:59.25pt;'
      'margin-top:1.5pt;width:108pt;height:59.25pt;z-index:${i + 1};'
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
      '${note.visible ? '<x:Visible/>' : ''}</x:ClientData></v:shape>',
    );
  }
  w.raw('</xml>');
}
