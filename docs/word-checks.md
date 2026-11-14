# Word checks

CI validates every DOCX fixture with the Open XML SDK and compares
LibreOffice's reading of it with the expected text (AGENTS.md, "Validation").
Neither is Word, so the owner opens each D milestone's documents in Word for
Mac as well. A milestone is done only when no document shows a repair prompt
or wrong text (decision
[`0010`](decisions/0010-phase-4-docx-document-model.md)). The format of this
page follows [`excel-checks.md`](excel-checks.md); the model's rules are in
[`docx-model.md`](docx-model.md).

The reference reader is Word for Mac (Microsoft 365). A document Word repairs
is a bug in the library.

Write the documents with:

```bash
dart run tool/write_fixtures.dart build/fixtures
dart run tool/round_trip_docx.dart build/fixtures build/model-docx
dart run tool/round_trip_docx.dart test/fixtures/owner/docx build/model-docx-owner
dart run tool/edit_docx.dart test/fixtures/owner/docx build/edited-docx-owner
```

(The D2 and D3 sections below use the same commands; their folders hold the
`d2_*` and `d3_*` documents as well. The D3 section adds one command, for a
document that ends in a table. The D4, D5 and D6 sections have commands of
their own, which write to `build/d4/`, `build/d5/` and `build/d6/`.)

`build/fixtures` also holds the workbooks of the Excel checks; open the
`d1_*.docx` files (D1), the `d2_*.docx` files (D2) and the `d3_*.docx` files
(D3); the `d4_*.docx` (D4), `d5_*.docx` (D5) and `d6_*.docx` (D6) files are
under `build/d4/`, `build/d5/` and `build/d6/`.
`tool/round_trip_docx.dart` prints each difference between an input and the
model's output and exits 1 on any, so run it first and expect none;
`tool/edit_docx.dart` likewise prints each problem with an edited document
and exits 1 on any. (CI uses other folder names: its
`build/model-docx` is the round trip of LibreOffice's re-save of the
fixtures, and its `build/edited-docx` the edit of that re-save.)

For every file, first check that Word opens it without a repair prompt ("Word
found unreadable content", "Word experienced an error trying to open the
file"). The lists below say what to see. The owner's own Word files are the
four in `test/fixtures/owner/docx/` (`blank.docx`, `features.docx`,
`long.docx` and, from D2, `builtins.docx`); their expected texts are
`<name>.expected.txt`.

## D1

### Fixtures: `build/fixtures/d1_*.docx`

Open each file in Word for Mac. No repair prompt; the text as listed.

- `d1_blank`: one empty paragraph. It looks like a new blank document: the
  font is Aptos at 12 pt (Home shows `Aptos (Body)` and `12`), the page is A4
  portrait (Layout > Size), and the Styles gallery lists Normal, Heading 1 and
  the other built-in styles in English. File > Properties shows no title,
  author or company.
- `d1_paragraphs`: five paragraphs (compare with
  `build/fixtures/d1_paragraphs.expected.txt`): `The first paragraph.` (style
  Normal), `A second paragraph, with a comma and a full stop.`, an empty
  paragraph, `The fourth paragraph follows an empty one.` and `Last.`.
- `d1_text_rules`: `Tab separated columns` with real tabs, a line starting
  with a tab, `Line one` and `Line two` on two lines of one paragraph (a line
  break, not a paragraph break), `Carriage return and line feed` and `are one
  break` on two lines, two lines with their leading and trailing or double
  spaces kept (turn on Show/Hide to count them), a paragraph of one space,
  `A control character was here: [].` with nothing inside the brackets, and
  `Two runs, one paragraph.` as one paragraph.
- `d1_unicode`: the Turkish line `Türkçe: İıĞğŞşÇçÖöÜü — Işık, iğne, şeker,
  çiçek.`, the German line with `ẞ`, the emoji line (an emoji, a thumbs up with
  a skin tone, a flag), the two supplementary-plane CJK characters, and
  `Toplam: 1.234,50 ₺ · Summe: 1.234,50 €`, none shown as a box or a question
  mark.
- `d1_large`: 2,000 paragraphs, `Paragraph 1 of 2000` to `Paragraph 2000 of
  2000`; it opens in a few seconds and the status bar counts the words.

### Round trips: `build/model-docx/*.docx` and `build/model-docx-owner/*.docx`

The model opened each document, read the body and saved it, changing nothing.
Open every file of both folders. No repair prompt, and each looks and reads as
the file it came from:

- `build/model-docx/d1_*.docx` as the list above.
- `build/model-docx-owner/blank.docx`, `features.docx` and `long.docx` as the
  owner's originals (`builtins.docx` is checked in D2): `features.docx`
  keeps its heading, bullet list, table, header, footer and comment;
  `long.docx` keeps its table of contents, two tables and lists, and its 15
  pages.

### Edited owner files: `build/edited-docx-owner/*.docx`

The model opened each of the owner's Word files and edited the body
(`tool/edit_docx.dart`, which lists the rules):

- it set the text of the first run that has text to `Edited by the model`,
  and made that run bold, in the theme colour accent 1;
- it replaced the last paragraph that holds plain runs only (no bookmark,
  field, hyperlink or drawing) with `Replaced by the model`;
- it added a paragraph `Added by the model` at the end, in the document's own
  Heading 1 style (the owner's files define it as `Balk1`, shown as
  `Başlık 1` in Turkish Word);
- it added a bullet list of two items after it: `First item`, and `Second
  item` at level 2.

Open `blank.docx`, `features.docx`, `long.docx` and `builtins.docx`. No repair
prompt, the edits visible, and everything else as in the original:

- `blank.docx`: it has no text, so no run is edited; its one empty
  paragraph reads `Replaced by the model`, then `Added by the model` as a
  Heading 1 and the two list items.
- `features.docx`: the heading `Quarterly report` reads `Edited by the model`,
  bold and in accent 1, and is still a Heading 1 (`Başlık 1`); `End of
  report.` reads `Replaced by the model`; the added heading and the list
  follow. The bullet list, table, header, footer and comment are as in the
  original.
- `long.docx`: the title `DENEME BELGESİ` reads `Edited by the model`, bold
  and in accent 1, in its Title style; the empty last paragraph reads
  `Replaced by the model`; the added heading and the list follow. The table
  of contents, the two tables, the lists and the 15 pages are as in the
  original (the added lines may start a sixteenth page).
- `builtins.docx`: `Bulleted one` reads `Edited by the model`, bold and in
  accent 1, still the first item of its list. `No spacing text` reads
  `Replaced by the model` (in the Normal style; `Example link` holds a
  hyperlink, so it is left alone); the table and `Example link` are as they
  were, and the added heading and the list follow.

### Save in Word

For `d1_blank`, `d1_text_rules` and one round-tripped owner file, change one
word, save in Word, close and reopen: no repair prompt, and the edit is there.

## D2

D2 types formatting, styles and lists. Open the D2 documents, their round
trips and the edited owner files in Word for Mac. Write them with the
commands at the top of this page. No repair prompt; then, per document, as
below. This section says what to look for; the result of the check is
recorded under "Results", and none is recorded here before the owner has
looked.

### Fixtures: `build/fixtures/d2_*.docx`

- `d2_run_formatting`: one paragraph per property, each run formatted as its
  text says: `Bold`, `Italic`, `Underline double red` (a double red line),
  `Underline words` (words underlined, spaces not), `Strike`, `Double
  strike`, `Caps`, `Small caps`, `Color 2E7D32` (green), `Color theme accent1
  shade` (a darker shade of the theme's accent 1, **not black or automatic**:
  the colour is written with `w:val="auto"` beside its theme attributes, see
  [`docx-model.md`](docx-model.md), "Properties"), `Color auto`, `Fonts
  Arial`, `Size 18`, `Size 9.5`, `Spacing expanded 2`, `Spacing condensed 1`,
  `Highlight yellow`, `Shading fill` (a pale green fill behind the text),
  `Subscript`, `Superscript` and `Language de-DE` (Review > Language shows
  German for that run).
- `d2_paragraph_formatting`: `Page break before` is first, so the break has
  no visible effect at the top of the page (Paragraph > Line and Page Breaks
  shows the box ticked); then each paragraph as its text says:
  alignment centre, right and justify; the indentations (the first-line
  indent and the hanging indent shown in the ruler); the three spacings
  (before 12 and after 6 at 1.5 lines, exactly 20, at least 16); `Keep with
  next`, `Keep lines together` and `Widow control off` (Paragraph > Line and
  Page Breaks show each box ticked or cleared); `Outline level 2` (Outline
  view shows it at level 2); `Borders: a red box and a rule between` (red
  top, left and right lines, a double bottom line in the automatic colour,
  and a dashed line between paragraphs); `Shading: a pale
  yellow fill`; and `Tab stops:` with a left stop at 1 in, a centre stop at
  3 in and a right stop at 6 in with a dot leader, so that `left`, `center`
  and `right` sit on them with dots before `right`.
- `d2_styles`: the Styles pane (Home > Styles Pane, "All styles") shows each
  built-in style once, under its Turkish name (`Başlık 1`, `Liste
  Paragrafı` and so on), and `Note` and `Code` besides them, with no style
  listed twice. The paragraphs read as their text says: `A title`
  in Title, `A subtitle` in Subtitle, three headings in Heading 1 to 3,
  `A quotation` in Quote, `A note in the custom style` in `Note` (indented,
  italic, grey, with a left border), `Code` in `Code` (Courier New 10 on grey)
  followed by plain text, and `Strong and emphasis` with the words in
  Strong and Emphasis. The default size is 11 pt.
- `d2_lists`: `Bullets:` and a bulleted list: a bullet (•) at level 1, a
  hollow bullet (◦) at level 2 for `Bullet one, nested`; `Numbers:` and a
  numbered list: `1.`, `a.` at level 2, `2.`; `Restarted numbers:` and a list
  that starts at `1.` again, not at 3.

### Round trips of the D2 documents

The model opened each document, read the body, loaded the styles and the
numbering and saved it, changing nothing. Open every file of both folders. No
repair prompt, and each looks and reads as the file it came from: the D2
fixtures as above, and `builtins.docx` as the original (two lists with two
levels, `Strong text`, `Emphasis text`, `No spacing text`, the table, the
header and footer, the link).

### Edited owner files

As under D1, "Edited owner files" (the edited run bold in accent 1, the added
heading, the two-item bullet list). Two more things to look at:

- the added heading shows as `Başlık 1` in the Styles pane, and the Styles
  pane of `features.docx` lists no second Heading 1 (the model reused
  `Balk1` and added no `Heading1`);
- the bullet list at the end uses the document's List Paragraph style
  (`Liste Paragrafı` in Turkish Word), bullets at level 1 and 2, and does
  not join an earlier list: Word may show them as the same list when two
  lists were pasted together; if it does, say so under Notes.

### Save in Word

For `d2_lists`, `d2_styles` and one edited owner file: change one word, save
in Word, close and reopen. No repair prompt, the edit is there, and the
lists and styles are as before.

## Own parts (decision 0011)

A new document's theme, styles, font table and settings are now written by
this library, so what a new document writes is checked again. The owner's
round trips and the edits keep the owner's own parts, but `styles.ensure`
and the list helpers add the rewritten definitions. Write the documents with
the commands at the top of this page and open:

- `d1_blank`: no repair prompt, Aptos at 12 pt (Home shows `Aptos (Body)`),
  the gallery offers Normal, Heading 1, Title, Subtitle, Strong, Emphasis and
  the other styles as before; Design > Colors shows the theme's colours.
- `d2_run_formatting`, `d2_styles` and `d2_lists`: as under D2.
- `build/edited-docx-owner/blank.docx` and `features.docx`: as under D2,
  "Edited owner files".
- Save `d1_blank` in Word, close and reopen: no repair prompt.

## D3

D3 types tables. Open the D3 fixtures, their round trips, the edited owner
files and the document that ends in a table in Word for Mac. Write them with
the commands at the top of this page, and with this one:

```bash
dart run tool/write_table_last.dart build/table-last
```

No repair prompt in any of them; then, per document, as below. This section
says what to look for: what each document should show comes from the code that
wrote it and from the SDK, not from Word, so read every statement here as what
to expect until the owner has looked. The result of the check is recorded under
"Results", and none is recorded here before then. Word repairs a table
with no row, a row with no cell and a cell with no paragraph, and the model
writes none of them; if a prompt appears anyway, read its recovery log and
name the part in "Notes".

A new document's root changed after the D1 check and the check of its own
parts: it now declares the real `w14` namespace, where it held a literal
placeholder. Open `build/fixtures/d1_blank.docx` again: no repair prompt, and
as under "Own parts (decision 0011)".

### Fixtures: `build/fixtures/d3_*.docx`

- `d3_basic`: `Before the table.`, a table of three columns and three rows,
  and `After the table.`. The table has the `Table Grid` style (thin black
  borders on every cell; the Table Design tab shows `Table Grid`, and the
  Styles pane lists it once, by its Turkish name in a Turkish Word), the
  look of Insert Table (Table Design > Header Row, First Column and Banded
  Rows are ticked, Banded Columns and the other two are not), the first row
  repeating as a header (Table Layout > Repeat Header Rows), the three
  columns of equal width that together fill the text width, and the cells
  `Name`, `Quantity`, `Price` / `Tea`, `2`, `3.50` / `Coffee`, `1`, `4.25`.
- `d3_header_row`: `A long table.`, then a table of 121 rows over several
  pages and `The end.`. The first row (`Number`, `Square`, `Text`) repeats at
  the top of every page (Table Layout > Repeat Header Rows is on for it, and
  for no other row); no row is split across a page break; the row `3`, `9`,
  `Row 3 of 120` is exactly 36 pt tall (Table Properties > Row shows
  `Exactly` and `36 pt`).
- `d3_merges`: a table of four columns and six rows, each cell reading
  `r<row>c<column>`, with five merges, so that the cells read as follows.
  Across: `r0c0` spans two columns in the first row (it holds `r0c0` and
  `r0c1`, one above the other). Down: `r1c0` spans the second and third rows
  (it holds `r1c0` and `r2c0`). A block: `r1c1`'s neighbours `r1c2`, `r1c3`,
  `r2c2`, `r2c3` are one cell, two columns wide and two rows tall, holding the
  four texts as four lines. Across three: in the fourth row `r3c1` spans three
  columns (`r3c1`, `r3c2`, `r3c3` as three lines) beside `r3c0`. A block at the
  edge: `r4c0`, `r4c1`, `r5c0`, `r5c1` are one cell two columns wide and two
  rows tall. Cells that were not merged (`r1c1`, `r2c1`, `r4c2`, `r4c3`,
  `r3c0`, `r5c2`, `r5c3`) are as they were. `After the merges.` follows.
- `d3_formatting`: a table of three columns whose widths are 100, 150 and 200 pt
  (Table Properties > Column shows them), with a fixed layout (Options >
  Automatically resize to fit contents is off), 450 pt wide, centred on the
  page (Table Properties > Table > Alignment is Center) with an indent of 12 pt
  set. The outer borders are dark blue lines 1 pt thick, the lines between rows are
  dashed and the lines between columns dotted; the cells have margins of 2 pt
  above and below and 6 pt at the sides. The header row reads `Top`, `Center`,
  `Bottom`, with the words at the top, in the middle and at the bottom of
  their cells (Table Properties > Cell > Vertical Alignment). The second row:
  `Shaded` on a pale yellow fill, `Vertical text` **rotated, reading from
  bottom to top** (Table Layout > Text Direction), and `Bordered` with a
  double line above it and a thick dark red line below. The third row
  (`High`, three times) is at least 48 pt tall (Table Properties > Row), with
  its text in the middle of each cell. The fourth row (`Splits`, three times)
  looks like any other: **Allow row to break across pages** is on and **Repeat
  as header row** is off (Table Properties > Row). `After the formatted table.`
  follows.
- `d3_nested`: `Tables in tables.`, then a table of two columns. Its second
  row holds, at the left, `Holds a table` followed by a table of two
  columns and two rows (`Inner a`, `Inner b` / `Inner c`, `Inner d`), and, at
  the right, `Holds a list` followed by a bulleted list of `First item` and
  `Second item`, with bullets. Its third row holds `Ends in a table` and
  then a one-cell table `Last in the cell`, at the left, and `Plain` at the
  right: Word shows a paragraph mark after the nested table (Show/Hide), as
  every cell must end in one. `After the tables.` follows.

### Round trips: `build/model-docx/d3_*.docx` and `build/model-docx-owner/*.docx`

The model opened each document, read the body and every property (the tables'
too), loaded the styles and the numbering and saved it, changing nothing;
`tool/round_trip_docx.dart` prints any difference from the input. Open the
`d3_*` documents of `build/model-docx` and every file of
`build/model-docx-owner`: no repair prompt, and each looks and reads as the
original. In the owner's files the tables are the ones to compare:
`features.docx` keeps its table, `long.docx` its two tables and
`builtins.docx` its table, with their borders, widths and text.

### Edited owner files: `build/edited-docx-owner/*.docx`

`tool/edit_docx.dart` edits tables as well as paragraphs now (its
rules are under D1, "Edited owner files", and in AGENTS.md). Besides the run,
the replaced paragraph, the heading and the list, it:

- set the text of the first paragraph of the first cell of the first table to
  `Edited cell`;
- appended a row to that table whose first cell reads `New row` and whose other
  cells are empty (left out when the table has no grid);
- appended a table of two columns before the added heading: a header row
  `Head one`, `Head two`, a row `Body one`, `Body two`, and a last row whose
  one cell, `Merged`, spans both columns.

Open `features.docx`, `long.docx` and `builtins.docx` (`blank.docx` has no
table to edit, but gets the appended one). No repair prompt, and:

- the first cell of the first table reads `Edited cell` and the table has a
  `New row` row at its end, in the table's own style and with the width of its
  columns; nothing else in the table changed;
- the appended table follows the original body, in the document's own `Table
  Grid` style if it has one, else in Word's definition, which the model adds
  (the Styles pane lists one `Table Grid`, by its Turkish name in a Turkish
  Word, never two), with `Head one` and `Head two` as a
  header row that repeats on a page break, and `Merged` across both columns of
  the last row (clicking in it selects one cell);
- the heading `Added by the model` and the two-item list follow the table, as
  under D2;
- `long.docx` may now run to a sixteenth page; its table of contents, two
  tables and lists are as in the original.

### A body that ends in a table: `build/table-last/d3_table_last.docx`

LibreOffice's text export never ends on a document whose body ends in a table,
so no fixture is one and CI cannot check this case; the owner is the check. The
body is an empty paragraph, `The table is the last block of the body.` and a
table of two columns that is the last block of the body: a header row `Name`,
`Value` and a row `Last`, `row`. Word writes a paragraph after every table it saves, so Word
cannot have made this file: it is the case where the model saves the table
last, before the document's final section properties.

Open it. No repair prompt, and the text and the table as above. Then add a
word to a cell, save in Word, close and reopen: no prompt appears, and Show/Hide
shows a paragraph mark after the table.

### Save in Word

For `d3_basic`, `d3_merges` and `d3_nested`, and one edited owner file: change
one word in a cell, save in Word, close and reopen. No repair prompt, the edit
is there, and the merges, the header and the nested table are as before. For
`d3_header_row`, also scroll to the third page: the header row is still there.

## D4

D4 types sections, headers, footers and complex fields. Open the D4 fixtures,
their round trips, the round trips and edits of the owner's files and the
document whose last block carries a section break in Word for Mac. All of them
are under `build/d4/`, the folder to open. Write them with:

```bash
dart run tool/write_fixtures.dart build/d4/fixtures
dart run tool/round_trip_docx.dart build/d4/fixtures build/d4/model
dart run tool/round_trip_docx.dart test/fixtures/owner/docx build/d4/model-owner
dart run tool/edit_docx.dart test/fixtures/owner/docx build/d4/edited-owner
dart run tool/write_table_last.dart build/d4/table-last
```

`tool/round_trip_docx.dart` and `tool/edit_docx.dart` print each problem and
exit 1 on any, so expect none. Never run `soffice` on `build/d4/table-last`.

No repair prompt in any of them; then, per document, as below. As under D3, this
section says what to look for: what each document should show comes from the
code that wrote it and from the SDK, not from Word, so read every statement here
as what to expect until the owner has looked. The result is recorded under
"Results", and none is recorded here before then. In the views below,
Show/Hide is the ¶ button on the Home tab; a section's values are read with the
cursor in that section. The menus are Word for Mac's: Layout > Margins > Custom
Margins (with its Margins and Layout tabs), Layout > Columns > More Columns,
Layout > Line Numbers, and Insert > Page Number > Format Page Numbers.

### Fixtures: `build/d4/fixtures/d4_*.docx`

- `d4_sections`: three pages and four sections; Show/Hide shows a section break
  at the end of each of the first three.
  - Section 1, page 1: A4 portrait (21 × 29.7 cm), margins of 3.81 cm on the
    four sides and a gutter of 0.64 cm, so the text sits a little further right
    than the margin alone. The text is in the middle of the page, top to bottom
    (Layout tab, Vertical alignment: Center). Its two paragraphs read
    `Portrait, with wide margins, its pages numbered from 5.` and `Its lines are
    numbered and it sits in the middle of the page.`. The lines carry numbers
    in the left margin, from 1 (Line Numbers: Restart Each Section). The pages
    have no visible number, so read it in Format Page Numbers: Start at 5.
  - Section 2, page 2: A4 landscape (Orientation: Landscape), margins of 2.54 cm
    and no gutter, two columns of equal width with a line between them (More
    Columns: Two, Line between ticked), no line numbers, the text at the top of
    the page, and Format Page Numbers on Continue from previous section. It
    holds `Landscape, in two columns with a line between them.` and `The second
    paragraph of the columns.`. Word balances columns before a continuous
    break, so each paragraph may sit in a column of its own.
  - Section 3, the same page: the break before it is continuous (Layout tab,
    Section start: Continuous). One column across the landscape page, below
    the two: `Continuous: this section starts on the same page, in one column.`.
  - Section 4, page 3: Letter portrait (21.59 × 27.94 cm, Size shows Letter) on
    a page of its own (Section start: New page), margins of 2.54 cm. It holds
    `Letter, on a page of its own.`, a table and `After the table.`. The table
    is the check of the 10 twips (`docx-model.md`, "Known gaps of D3"): `Name`,
    `Value` / `Width`, `The text width less 10 twips`, in `Table Grid`, with a
    repeating header row and two columns of equal width (Table Properties >
    Column: 8.25 cm each). **The table reaches both margins:** with the ruler
    on, its right edge sits on the right margin, as a table inserted by hand on
    that page does. A gap or an overhang that can be seen is the finding to
    report, with the widths Table Properties shows.
- `d4_headers`: five pages, three sections, and in Header & Footer (double click
  a header) Different Odd & Even Pages ticked everywhere. Each page shows:

  | Page | Section | Body | Header | Footer |
  |---|---|---|---|---|
  | 1 | 1 | `Page one of section one: the first page stories.` | `First header one` | `First footer one` |
  | 2 | 1 | `Page two of section one: the even stories.` | `Even header one` | `Even footer one` |
  | 3 | 1 | `Page three of section one: the default stories.` | `Header one` | `Footer one` |
  | 4 | 2 | `Section two inherits the stories of section one.` | `Even header one` | `Even footer one` |
  | 5 | 3 | `Section three has its own header and footer.` | `Header three` | `Footer three` |

  Different First Page is ticked in section 1 only, so pages 4 and 5 show no
  first story. In section 2 every header and footer has Link to Previous on
  (Word labels them `Same as Previous`). In section 3 the odd header and footer
  have it off, and the even ones on: type nothing, only look.
- `d4_fields`: one page. The body reads `This is page 1.` and `A field the model
  has no helper for: Custom text.`. The footer has two lines:
  `Page 1 of 1, section pages: 1` and `Printed on <date> at <time>`, the date
  as `dd.MM.yyyy` and the time as `HH:mm`, those of the moment Word opened the
  file. Each of the five, and `Custom text`, is a field: it turns grey when
  clicked, and Option-F9 (Fn as well on a Mac keyboard) shows its code: ` PAGE
  `, ` NUMPAGES `, ` SECTIONPAGES `, ` DATE \@ "dd.MM.yyyy" `, ` TIME \@ "HH:mm"
  ` and ` QUOTE "Custom text" `. Option-F9 again hides them.
  - **`DATE` and `TIME` have an empty result in the file**, so what shows is what
    Word computed. If the second line stays `Printed on  at `, that is the
    finding to report, with what Update Field (Control-click the place, or F9)
    does there: the model's rule for these two rests on this check.
  - **Page numbers move.** Click at the end of the body and press Cmd-Return
    for a page break. The footer on page 1 and on page 2 now read `Page 1 of 2, section pages: 2` and
    `Page 2 of 2, section pages: 2`. Undo the break, or close without saving.

### Round trips: `build/d4/model/d4_*.docx` and `build/d4/model-owner/*.docx`

The model opened each document, read the body, every property, every section
value and every header and footer, and saved it, changing nothing;
`tool/round_trip_docx.dart` prints any difference from the input. The three
`d4_*` documents of `build/d4/model` are byte for byte the fixtures, which
`cmp` shows, so opening the fixtures covers them. Open every file of
`build/d4/model-owner`: no repair prompt, and each looks and reads as the
original. In the owner's files the headers and footers are the ones to compare:
`features.docx` keeps `Jet Office test footer` and its header, `long.docx` its
`Sayfa <n>` footers on odd and even pages and its table of contents, and
`builtins.docx` its `Footer text`.

### Edited owner files: `build/d4/edited-owner/*.docx`

`tool/edit_docx.dart` adds a footer and a section to what it did under D1, D2
and D3 (AGENTS.md has its rules). The table, the heading and the list it appends
are now in a section of their own, on a landscape page. Open all four files.
No repair prompt, and:

- **Footer page numbers.** The last paragraph of the default footer reads
  `Page <n> of <m>`, with `<n>` the page and `<m>` the pages, both moving from
  page to page. In `blank.docx` it is the only text of a footer the file did not
  have. In `features.docx` it follows `Jet Office test footer`, and in
  `builtins.docx` `Footer text`. `long.docx` has even pages of their own and
  only its default footer changed, so `Page <n> of <m>` follows `Sayfa <n>` on odd
  pages, and even pages show `Sayfa <n>` alone.
- **The last section landscape.** The original body keeps its pages, and the
  document ends with one new landscape A4 page (Orientation: Landscape, Size: A4,
  Section start: New page; Show/Hide shows a `Section Break (Next Page)` after the
  original body). When the original body ended in a table or a break, an empty
  paragraph carries the break. The margins are those of the page before.
- That page holds the table of D3's list (`Head one`, `Head two`, `Body one`,
  `Body two`, `Merged`), whose two equal columns reach the margins of the wider
  page, then `Added by the model` and the two-item list, as under D2.
- The new section's header and footer have Link to Previous on, so its footer
  shows the same `Page <n> of <m>`.
- The edits to the original body (the first run, the replaced paragraph, the
  first cell and its `New row`) are as under D1 and D3; the headers and footers
  not named here are as in the original.

### A section break last: `build/d4/table-last/d4_break_last.docx`

The model adds no block after a section break, so the body's last block carries
the break and the last section holds nothing: Word cannot have made this file,
no fixture may be one, and CI does not open it in Word. The owner is the check.
The body is an empty paragraph and `This paragraph carries the last section
break.`.

Open it. No repair prompt, and the two paragraphs as above; Show/Hide shows a
`Section Break (Next Page)` after the second. Word may show a second, empty page
with a paragraph of its own: that is Word's to add, and is no problem. A repair
prompt here is the finding to report: the model's rule that it adds no block
after a break rests on this check. Then add a word to the second paragraph,
save in Word, close and reopen: no prompt, and the break and the word are there.

`build/d4/table-last/d3_table_last.docx` is the D3 document, written again by
the same command; its check is under D3.

### Save in Word

For `d4_sections`, `d4_headers`, `d4_fields` and one edited owner file: change
one word in the body and one in a footer, save in Word, close and reopen. No
repair prompt, the edits are there, and the sections, the stories on their
pages and the fields are as before: `d4_sections` still has its four sections,
`d4_headers` its five pages with the table above, `d4_fields` its five fields
(`DATE` and `TIME` now hold a result in the file), and the edited owner file its
last page landscape.

## D5

D5 types pictures, hyperlinks, bookmarks and the document properties. Open the
D5 fixtures, their round trips and the round trips and edits of the owner's
files in Word for Mac. All of them are under `build/d5/`, the folder to open.
Write them with:

```bash
dart run tool/write_fixtures.dart build/d5/fixtures
dart run tool/round_trip_docx.dart build/d5/fixtures build/d5/model
dart run tool/round_trip_docx.dart test/fixtures/owner/docx build/d5/model-owner
dart run tool/edit_docx.dart test/fixtures/owner/docx build/d5/edited-owner
```

`tool/round_trip_docx.dart` and `tool/edit_docx.dart` print each problem and
exit 1 on any, so expect none.

No repair prompt in any of them; then, per document, as below. As under D3 and
D4, this section says what to look for: what each document should show comes
from the code that wrote it and from the SDK, not from Word, so read every
statement here as what to expect until the owner has looked. The result is
recorded under "Results", and none is recorded here before then. A picture's
size is read in Picture Format > Size (or Format Picture > Size and Position),
its name in the Selection Pane (Picture Format > Selection Pane) and its
description with Control-click > View Alt Text. A link's address shows when
the pointer rests on it; Cmd-click follows it. File > Properties shows the
document properties (its Summary, Statistics and Custom tabs).

### Fixtures: `build/d5/fixtures/d5_*.docx`

- `d5_pictures`: one page.
  - The body reads `A PNG at its pixel size, 4 by 2 pixels, follows.`, then a
    paragraph holding only a picture, so small that it shows as a dot:
    0.11 cm wide and 0.05 cm high (3 × 1.5 pt, its 4 × 2 pixels at 96 dpi),
    named `PNG`, alt text `A PNG of 4 by 2 pixels`, inline with the text (Wrap
    Text: In Line with Text) and with its aspect locked.
  - A table in `Table Grid`, its first row a repeating header: `Kind`,
    `Picture` / `JPEG, 144 points wide` and, in the second cell, a picture
    5.08 cm wide and 8.47 cm high (144 × 240 pt, its 3 × 5 pixels scaled with
    their ratio), named `JPEG`, followed in the same paragraph by `The JPEG, 3
    by 5 pixels`.
  - Then `After the pictures.`.
  - **The header logo on every page.** The header holds the same 4 × 2 PNG, as
    small, named `Logo`, then `Logo beside the header text`. Click at the end
    of the body and press Cmd-Return: page 2 shows the logo and the text in
    its header too. Undo the break, or close without saving.
- `d5_links`: one page. The body reads:
  - `Overview` in Heading 1, inside the bookmark `Overview` (Insert >
    Bookmark lists it; Go To there selects the heading).
  - `Visit the project page for more.`: `the project page` is a link in the
    Hyperlink style (blue, underlined); resting on it shows the tooltip `The
    project page`, and Cmd-click opens `https://example.com/jet-office` in the
    browser.
  - `Back to the overview.`: `the overview` is a link in the same style;
    Cmd-click jumps to the heading `Overview`, and Edit Hyperlink shows it as a
    place in this document, the bookmark `Overview`.
  - `After the links.`.
  - **The footer link.** The footer reads `Footer link: example.com`;
    `example.com` is a link, and Cmd-click (or double click into the footer
    first) opens `https://example.com/`.
- `d5_properties`: one page, `This document has its properties set.`. File >
  Properties:
  - Summary: Title `The D5 properties`, Subject `Document properties`, Author
    `jet_office`, Company `Jet Office`, Category `Fixtures`, Keywords `docx;
    properties; d5`, Comments `Every core property, the company and the
    application.`; Manager empty.
  - Statistics: Created 8 November 2026 at 09:30 UTC and Modified 8 November
    2026 at 10:45 UTC (Word shows the local time: 12:30 and 13:45 in Türkiye),
    Last saved by `The fixture list`, Revision number `3`.
  - The content status `Final` and the application `jet_office` are in the
    file too; Word for Mac may not show them. Report where they show, if
    anywhere.

### Round trips: `build/d5/model/d5_*.docx` and `build/d5/model-owner/*.docx`

The model opened each document, read the body, every property, every picture,
link and bookmark, every section value and story and the document properties,
and saved it, changing nothing; `tool/round_trip_docx.dart` prints any
difference from the input. `build/d5/model/d5_properties.docx` is byte for
byte the fixture, which `cmp` shows. `d5_pictures` and `d5_links` hold the same
parts with the same bytes, but in another ZIP order: loading the body parses
the main part's relationships, and a parsed relationships part is written after
those never parsed, here the header's or footer's (as since D1; the D4 fixtures
had no such part). Open those two as well: they must look as the fixtures do.
Open every file of `build/d5/model-owner`: no repair prompt, and each
looks and reads as the original, with File > Properties as the original's. In
the owner's files the links are the ones to compare: `long.docx` keeps its
table of contents, whose entries jump to their headings, and `builtins.docx`
its external link.

### Edited owner files: `build/d5/edited-owner/*.docx`

`tool/edit_docx.dart` adds a picture, two links, a bookmark and a title to what
it did under D1 to D4 (AGENTS.md has its rules). Open all four files. No repair
prompt, and:

- **The new page.** The last, landscape page holds, after the table, the
  paragraph `A picture, links to jet_office and the added heading.`: after `A
  picture` sits the 4 × 2 PNG as a dot (0.11 × 0.05 cm), `jet_office` is a
  link to `https://example.com/jet-office` (Cmd-click opens it), and `the
  added heading` is a link that jumps to `Added by the model`, the heading
  below it.
- **The bookmark.** Insert > Bookmark lists `Model_edit`, and Go To selects the
  text of `Added by the model`. In `long.docx` it sits among the file's own
  `_Toc` bookmarks (tick Hidden bookmarks to see those).
- **The title.** File > Properties > Summary shows the title `Edited by the
  model`; every other property is the original's.
- The links take the document's own Hyperlink style: `long.docx` and
  `builtins.docx` have it under the id `Kpr`, as Turkish Word writes it, and in
  `blank.docx` and `features.docx`, which have none, Word's definition is
  added (blue, underlined).
- The rest is as under D4: the footer's `Page <n> of <m>`, the table, the
  heading and the list, and the edits of the original body.

### Save in Word

For `d5_pictures`, `d5_links`, `d5_properties` and one edited owner file:
change one word in the body, save in Word, close and reopen. No repair
prompt, the edit is there, and the pictures (sizes, names, the header logo),
the links (addresses, the jump to the bookmark, the footer link) and the
properties (Word now updates Modified, Last saved by and Revision number, the
rest stays) are as before.

## D6

D6 adds `DocxListExport`, a list as a Word document: a header with a logo, a
name and a date, a table whose header row repeats, a footer with the page
number and the number of pages. Open the two D6 fixtures, their round trips,
the round trips and edits of the owner's files and the benchmark's large
document in Word for Mac. All of them are under `build/d6/`, the folder to
open. Write them with:

```bash
dart run tool/write_fixtures.dart build/d6/fixtures
dart run tool/round_trip_docx.dart build/d6/fixtures build/d6/model
dart run tool/round_trip_docx.dart test/fixtures/owner/docx build/d6/model-owner
dart run tool/edit_docx.dart test/fixtures/owner/docx build/d6/edited-owner
dart run tool/write_list_into.dart test/fixtures/owner/docx \
  build/d6/list-into-owner
```

`tool/round_trip_docx.dart` and `tool/edit_docx.dart` print each problem and
exit 1 on any, so expect none. The benchmark's document is written by
`dart run tool/write_large_docx.dart build/d6/benchmark` to
`build/d6/benchmark/large.docx` (the Chrome benchmark cannot write files);
if that file is not there, skip its check and leave its row `not checked`.

No repair prompt in any of them; then, per document, as below. As under D3 to
D5, this section says what to look for: what each document should show comes
from the code that wrote it and from the SDK, not from Word, so read every
statement here as what to expect until the owner has looked. The result is
recorded under "Results", and none is recorded here before then. A page's
size and margins are in Layout > Size and Margins; a header or footer opens by
double clicking it; Option-F9 shows a field's code (Option-F9 again hides it).

### Fixtures: `build/d6/fixtures/d6_*.docx`

- `d6_list`: three A4 portrait pages (Layout > Size: A4) with margins of
  2.5 cm (Layout > Margins: Normal is 2.54 cm; here the top, bottom, left and
  right read 2.5 cm) and a header and footer of 1.25 cm from the edge.
  - **The header, on every page.** One line: a small picture at the left (a 4 ×
    2 pixel PNG scaled to 20 pt high, so a thin stripe: 0.71 cm high, 1.41 cm
    wide), `Müşteri listesi` in bold in the middle of the line and the date
    `08.11.2026` at the right edge. Click into the header and look at the ruler:
    a centre tab stop at the middle of the text and a right tab stop at its
    right edge. The date is plain text, not a field: it does not turn grey when
    clicked and Option-F9 shows no code. Scroll to page 2 and page 3: the same
    header.
  - **The footer, on every page.** `Sayfa 1 / 3`, `Sayfa 2 / 3` and
    `Sayfa 3 / 3`, centred. `1`, `2` and `3` are `PAGE` fields and `3` is a
    `NUMPAGES` field: each turns grey when clicked, and Option-F9 shows ` PAGE `
    and ` NUMPAGES `. If the total reads another number than the pages there
    are, press Cmd-A then F9 to update the fields and report both.
  - **The caption.** The first line of the body, `Kasım 2026 müşteri
    bakiyeleri`, is bold and 14 pt, above the table.
  - **The table.** Five columns, `Kod`, `Müşteri`, `Tarih`, `Tutar` and `Pay`,
    in `Table Grid` (thin black borders on every cell). Table Properties >
    Column shows `Kod` 2.12 cm, `Tarih` 2.47 cm, `Tutar` 3.17 cm and `Pay` 1.76
    cm (60, 70, 90 and 50 pt), and `Müşteri` taking what is left of the text
    width. The header row is bold on light grey (Table Properties, Borders and
    Shading: Fill `D9D9D9`, or Table Design > Shading: White, Background 1,
    Darker 15%).
  - **The header row repeats.** On page 2 and page 3 the first row of the table
    is the grey header `Kod`, `Müşteri`, `Tarih`, `Tutar`, `Pay` again (Table
    Properties > Row: Repeat as header row at the top of each page is ticked
    on the first row, and Allow row to break across pages is off). No row is
    split between two pages.
  - **The data.** 120 rows, `M-1001` to `M-1120`. The first reads `M-1001`,
    `Çağlar Işık`, `01.01.2026`, `1.234,50 ₺`, `0%`; the second `M-1002`,
    `İpek Özdemir`, `02.02.2026`, `1.251,75 ₺`, `5%`; the last `M-1120`,
    `Şükrü Doğan`, `08.12.2026`, `3.287,25 ₺`, `95%`. The Turkish letters ç ğ ı
    İ ö ş ü read right (names cycle through six, among them `Gülşen Şahin`,
    `Ümit Yıldız` and `Ömer Çelik`). The `Tarih`, `Tutar` and `Pay` columns, and
    their headers, are aligned to the right edge of their cells (Home >
    Align Right is highlighted in them), `Kod` and `Müşteri` to the left.
  - **The totals, on the last page.** The last row reads `Toplam` in the first
    cell, nothing in the next two and `271.305,00 ₺` in the `Tutar` column,
    in bold, right-aligned, not shaded. It is a value written by the caller, not
    a formula: a number written in a cell is not a field and Option-F9 shows
    nothing there.
  - **After the table.** Click at the end of the document: below the table is
    one empty paragraph, as Word needs after a table. It does not start a page
    of its own; if the last page holds only that paragraph, report it.
  - **Fonts.** The text is in the document's own font (Aptos, 12 pt), not a
    font of the helper's.
- `d6_list_landscape`: A4 landscape (Layout > Orientation: Landscape) with
  margins of 1.27 cm on all four sides and no gutter; the header and footer
  still 1.25 cm from the edge.
  - **The header, on every page.** No picture: a tab, `Monthly figures` in bold
    in the middle and `11/8/26` (the English short date of 8 November 2026) at
    the right edge. The footer reads `Page 1 of <n>`, centred, and `<n>` should
    be 2 (41 rows on landscape A4); report the count Word makes if it is not.
  - **The table.** Twelve columns, `Code`, `Name`, `Started`, `Amount` and
    `Month 1` to `Month 8`, in `Table Grid`, the header row bold on light grey
    and repeated at the top of every page. `Code`, `Name`, `Started` and
    `Amount` are 1.76, 3.18, 2.12 and 2.47 cm wide (50, 90, 60 and 70 pt); the
    eight month columns share the rest of the 27.16 cm text width equally, and
    the table reaches both margins (with the ruler on, its right edge sits on
    the right margin). **No column is cut off or wraps a number:** every month
    cell fits on one line.
  - **The data.** 40 rows, `C100` to `C139`. The first reads `C100`, `Item 1`,
    `2026-01-01`, `10.50`, then `0.3`, `0.5`, `0.8`, `1.0`, `1.3`, `1.5`, `1.8`,
    `2.0`; the second `C101`, `Item 2`, `2026-02-02`, `1,010.75`, `0.5`, `1.0`,
    and so on. The `Started`, `Amount` and month columns are right-aligned.
  - **No totals row:** the last row is `C139`.
  - **After the table.** One empty paragraph, as in `d6_list`.

### Round trips: `build/d6/model/d6_*.docx` and `build/d6/model-owner/*.docx`

The model opened each document, read the body, every property, every picture,
link and bookmark, every section value and story and the document properties,
and saved it, changing nothing; `tool/round_trip_docx.dart` prints any
difference from the input. `build/d6/model/d6_*.docx` should be byte for byte
the fixtures, or hold the same parts with the same bytes in another ZIP order
as D5's did (`cmp` says which): open both and compare them with the fixtures
above. Open every file of `build/d6/model-owner`: no repair prompt, and each
looks and reads as the original, with File > Properties as the original's.

### Edited owner files: `build/d6/edited-owner/*.docx`

`tool/edit_docx.dart` makes the same edits as under D5 (AGENTS.md has its
rules); since D6 it sets the title with `OfficeProperties.copyWith`, so every
other property is the original's. Open all four files. No repair prompt, and
as under D5: the footer's `Page <n> of <m>`, the landscape page with the
table, the picture, the two links, the heading `Added by the model` in the
bookmark `Model_edit`, the list, the title `Edited by the model` in File >
Properties > Summary, and in the other fields of File > Properties the
original's (author, company, dates, revision), none lost.

### A list in the owner's files: `build/d6/list-into-owner/*.docx`

`tool/write_list_into.dart` wrote the same Turkish list (`Müşteri listesi`,
three rows and the totals row `Toplam`) into the last section of each of the
four owner files, with `DocxListExport.writeTo`. Open all four: no repair
prompt, and in each:

- **The file's own content is as before**, from its first page to its last
  paragraph, and the list comes after it: the caption `Kasım 2026 müşteri
  bakiyeleri`, the table of four rows below the grey header row (`Kod`,
  `Müşteri`, `Tarih`, `Tutar`, `Pay`; the last row `Toplam`), one empty
  paragraph.
- **The header and footer, on every page of the last section.** The header
  shows the small logo at the left, `Müşteri listesi` in bold in the middle and
  `08.11.2026` at the right edge; the footer reads `Sayfa <n> / <m>`, centred.
  In a section before the last, the file's own header and footer are as they
  were. If the list's section had a different first page, that page now shows
  the list's header too: the list turns the title page off.
- **Even pages too, in `long.docx`**, which has different odd and even pages:
  scroll to an even page of the list's section and see the same header and
  footer as on an odd page. In `blank.docx`, `builtins.docx` and `features.docx`
  there is no even setting and nothing to see.
- The list sets A4 portrait and Word's blank margins (and one text column) on
  the last section, so its pages may differ in size or margins from the
  file's own.
- Save in Word and reopen one of them: the same.

### The benchmark's document: `build/d6/benchmark/large.docx`

About 40,000 paragraphs: the owner's `long.docx` repeated 385 times, the first
paragraph with text after the middle changed to `Edited by the model`, saved by
the model (`tool/write_large_docx.dart`). It is a stress test and not a design:
nobody reads it.

- Word opens it without a repair prompt. It is long (15 pages repeated 385
  times, so some 5,800 pages; the exact number is Word's): report how long it
  took to open and the page count the status bar gives.
- The table of contents of each copy jumps to its own copy's headings (Cmd-click
  a few entries): the bookmark ids and `_Toc` names were made unique per copy.
- Search for `Edited by the model` (Cmd-F): exactly one hit, near the
  middle of the document.
- Close without saving, or save in Word and reopen (see below).

### Save in Word

For `d6_list`, `d6_list_landscape` and one edited owner file: change one word
in the body, save in Word, close and reopen. No repair prompt, the edit is
there, and the header (logo, name, date), the footer (`Sayfa 2 / 3`), the
repeating header row, the right-aligned columns, the totals row and the page
sizes are as before. For `d6_list` also add a line to the
caption and see that the table moves down and its header row still repeats on
the next page.

## T1

T1 adds `DocxTemplate`, the fill of a template's values (decision
[`0024`](decisions/0024-docx-template-fill.md)). Open the filled and unfilled
T1 fixtures, and the owner's templates filled, in Word for Mac. All of them
are under `build/t1/`, the folder to open. Write them with:

```bash
dart run tool/write_t1_check.dart build/t1
dotnet run --project tool/ooxml_validate -- build/t1
```

`tool/write_t1_check.dart` writes `t1_values.docx`, `t1_merge_fields.docx`,
`t1_template.docx` and `t1_merge_fields_template.docx` (the last two are the
templates unfilled, to compare with) and `owner/`, each `template_*.docx` of
`test/fixtures/owner/docx/` filled with the fixed Turkish data
(`fillDocxData()`). It prints a problem and exits 1 on any, so expect none.

**The owner's templates.** The owner authors two templates in Word for Mac
(spec section 13) and puts them in `test/fixtures/owner/docx/` with manifest
entries and confirmed expected texts: `template_invoice.docx` (a company, a
customer, a date, amounts, a table, a header and a footer with page numbers, a
comment on a tag, a tracked change next to a field) and `template_letter.docx`
(merge fields, `{{}}` tags mixed with them, a header and a footer). Only the
owner edits those files and their expected texts; until they are there,
`build/t1/owner/` is not written and the rows for it stay `not checked`.

No repair prompt in any of them, and each saves in Word without a prompt; then,
per document, as below. As under D3 to D6, this section says what to look for:
what each document should show comes from the code that wrote it and from the
SDK, not from Word, so read every statement here as what to expect until the
owner has looked. The result is recorded in the table below, and none is
recorded before then. Option-F9 shows a field's code (Option-F9 again hides
it).

### Fixtures and owner templates: `build/t1/*.docx` and `build/t1/owner/*.docx`
- Every value is in place and in the formatting of its tag: where the tag's
  first brace was bold the value is bold; the red `{{musteri.ad}}` gives a red
  `Ayşe Yılmaz`. The text around a tag is unchanged.
- The amount reads `1.234,56 ₺`, the date `14.11.2026`, the quantity `2,5`.
- `t1_values.docx`: the missing value is visibly `{{yok}}`, and only that
  tag is left. The header and the footer show the company and the date.
- Section tags (`{{#x}}`, `{{/x}}`), if a template has them, are visible as
  written: T1 does not fill them.
- Page numbers in a header or footer still update (the field is untouched).
- `t1_merge_fields.docx`: no field is left (Option-F9 shows no code, and
  Cmd-A then F9 changes nothing), the date is in the switch's form
  (`14.11.2026`), the amount in Turkish separators (`Tutar: 1.234,56`), the
  name in capitals, and the text of `\b` and `\f` stands around a value.
- `owner/template_invoice.docx`: the comment on a tag is still anchored (it
  shows beside the same text); the tracked change next to a field is still in
  the Review pane's list.
- `t1_template.docx` and `t1_merge_fields_template.docx` are the unfilled
  templates: they must look as written and have no repair prompt either.

### Save in Word

For `t1_values`, `t1_merge_fields` and every owner file: change one word, save
in Word, close and reopen. No repair prompt, the edit is there, and every
filled value and field is as before.

### Results

One row per file or check. `Result` is `ok`, `sorun` (a problem) or `not
checked`; `Notes` says what was seen.

| Date | Word | File | Result | Notes |
|---|---|---|---|---|
|  |  | `build/t1/t1_values.docx` | not checked |  |
|  |  | `build/t1/t1_merge_fields.docx` | not checked |  |
|  |  | `build/t1/t1_template.docx` | not checked |  |
|  |  | `build/t1/t1_merge_fields_template.docx` | not checked |  |
|  |  | `build/t1/owner/template_invoice.docx` | not checked | Needs the owner's template. |
|  |  | `build/t1/owner/template_letter.docx` | not checked | Needs the owner's template. |
|  |  | Save in Word | not checked |  |

## Results

One row per file or check. `Result` is `ok`, `sorun` (a problem) or `not
checked`; `Notes` says what was seen, and a repair prompt names the part from
its recovery log.

| Date | Word | File | Result | Notes |
|---|---|---|---|---|
| 2026-11-06 | Word for Mac 16.114.4 | `build/fixtures/d1_blank.docx` | ok |  |
| 2026-11-06 | Word for Mac 16.114.4 | `build/fixtures/d1_paragraphs.docx` | ok |  |
| 2026-11-06 | Word for Mac 16.114.4 | `build/fixtures/d1_text_rules.docx` | ok |  |
| 2026-11-06 | Word for Mac 16.114.4 | `build/fixtures/d1_unicode.docx` | ok |  |
| 2026-11-06 | Word for Mac 16.114.4 | `build/fixtures/d1_large.docx` | ok |  |
| 2026-11-06 | Word for Mac 16.114.4 | `build/fixtures/d2_run_formatting.docx` | ok |  |
| 2026-11-06 | Word for Mac 16.114.4 | `build/fixtures/d2_paragraph_formatting.docx` | ok |  |
| 2026-11-06 | Word for Mac 16.114.4 | `build/fixtures/d2_styles.docx` | ok |  |
| 2026-11-06 | Word for Mac 16.114.4 | `build/fixtures/d2_lists.docx` | ok |  |
| 2026-11-06 | Word for Mac 16.114.4 | `build/model-docx/d1_*.docx`, `d2_*.docx` | ok | Not opened: all nine are byte for byte the fixtures above. |
| 2026-11-06 | Word for Mac 16.114.4 | `build/model-docx-owner/blank.docx` | ok | Compared with the original. |
| 2026-11-06 | Word for Mac 16.114.4 | `build/model-docx-owner/features.docx` | ok | Compared with the original. |
| 2026-11-06 | Word for Mac 16.114.4 | `build/model-docx-owner/long.docx` | ok | Compared with the original. |
| 2026-11-06 | Word for Mac 16.114.4 | `build/model-docx-owner/builtins.docx` | ok | Compared with the original. |
| 2026-11-06 | Word for Mac 16.114.4 | `build/edited-docx-owner/blank.docx` | ok |  |
| 2026-11-06 | Word for Mac 16.114.4 | `build/edited-docx-owner/features.docx` | ok |  |
| 2026-11-06 | Word for Mac 16.114.4 | `build/edited-docx-owner/long.docx` | ok |  |
| 2026-11-06 | Word for Mac 16.114.4 | `build/edited-docx-owner/builtins.docx` | ok |  |
| 2026-11-06 | Word for Mac 16.114.4 | Save in Word | ok | `d1_blank`, `d1_text_rules`, `d2_lists`, `d2_styles`, round-tripped and edited `features.docx`. |
| 2026-11-06 | Word for Mac 16.114.4 | Expected texts | ok | `features`, `builtins` and `long` compared with Word; `blank` has one empty paragraph. `confirmedBy` set. |
| 2026-11-06 | Word for Mac 16.114.4 | `build/fixtures/d1_blank.docx` | ok | Own parts (decision 0011): Aptos at 12 pt, gallery as before. |
| 2026-11-06 | Word for Mac 16.114.4 | `build/fixtures/d2_run_formatting.docx` | ok | Own parts (decision 0011). |
| 2026-11-06 | Word for Mac 16.114.4 | `build/fixtures/d2_styles.docx` | ok | Own parts (decision 0011). |
| 2026-11-06 | Word for Mac 16.114.4 | `build/fixtures/d2_lists.docx` | ok | Own parts (decision 0011). |
| 2026-11-06 | Word for Mac 16.114.4 | `build/edited-docx-owner/blank.docx` | ok | Own parts (decision 0011). |
| 2026-11-06 | Word for Mac 16.114.4 | `build/edited-docx-owner/features.docx` | ok | Own parts (decision 0011). |
| 2026-11-06 | Word for Mac 16.114.4 | Save in Word | ok | Own parts (decision 0011): `d1_blank` saved, closed and reopened. |
| 2026-11-07 | Word for Mac 16.114.4 | `build/fixtures/d1_blank.docx` | ok | Reopened after the `w14` fix: new root declares the real namespace. |
| 2026-11-07 | Word for Mac 16.114.4 | `build/fixtures/d3_basic.docx` | ok |  |
| 2026-11-07 | Word for Mac 16.114.4 | `build/fixtures/d3_header_row.docx` | ok |  |
| 2026-11-07 | Word for Mac 16.114.4 | `build/fixtures/d3_merges.docx` | ok |  |
| 2026-11-07 | Word for Mac 16.114.4 | `build/fixtures/d3_formatting.docx` | ok |  |
| 2026-11-07 | Word for Mac 16.114.4 | `build/fixtures/d3_nested.docx` | ok |  |
| 2026-11-07 | Word for Mac 16.114.4 | `build/model-docx/d3_*.docx` | ok | Compared with the fixtures. |
| 2026-11-07 | Word for Mac 16.114.4 | `build/model-docx-owner/blank.docx` | ok | Compared with the original. |
| 2026-11-07 | Word for Mac 16.114.4 | `build/model-docx-owner/features.docx` | ok | Compared with the original. |
| 2026-11-07 | Word for Mac 16.114.4 | `build/model-docx-owner/long.docx` | ok | Compared with the original. |
| 2026-11-07 | Word for Mac 16.114.4 | `build/model-docx-owner/builtins.docx` | ok | Compared with the original. |
| 2026-11-07 | Word for Mac 16.114.4 | `build/edited-docx-owner/blank.docx` | ok |  |
| 2026-11-07 | Word for Mac 16.114.4 | `build/edited-docx-owner/features.docx` | ok |  |
| 2026-11-07 | Word for Mac 16.114.4 | `build/edited-docx-owner/long.docx` | ok |  |
| 2026-11-07 | Word for Mac 16.114.4 | `build/edited-docx-owner/builtins.docx` | ok |  |
| 2026-11-07 | Word for Mac 16.114.4 | `build/table-last/d3_table_last.docx` | ok | Saved in Word, closed and reopened. |
| 2026-11-07 | Word for Mac 16.114.4 | Save in Word | ok | D3: `d3_basic`, `d3_merges`, `d3_nested`, `d3_header_row` and one edited owner file. |
| 2026-11-08 | Word for Mac 16.114.4 | `build/d4/fixtures/d4_sections.docx` | ok | Four sections, sizes, margins, columns, numbering as listed; the Letter table 10 twips short of the text width. Values read by Claude in Word as well. |
| 2026-11-08 | Word for Mac 16.114.4 | `build/d4/fixtures/d4_headers.docx` | ok | Stories on pages 1 to 5 as the table says; links as listed. Values read by Claude in Word as well. |
| 2026-11-08 | Word for Mac 16.114.4 | `build/d4/fixtures/d4_fields.docx` | ok | Six fields; DATE and TIME empty in the file, filled by Word at open; a page break gives Page 1 of 2 and Page 2 of 2. Values read by Claude in Word as well. |
| 2026-11-08 | Word for Mac 16.114.4 | `build/d4/table-last/d4_break_last.docx` | ok | No repair prompt; Word adds an empty paragraph to the last section. |
| 2026-11-08 | Word for Mac 16.114.4 | `build/d4/model/d4_*.docx` | ok | Not opened: byte for byte the fixtures above. |
| 2026-11-08 | Word for Mac 16.114.4 | `build/d4/model-owner/blank.docx` | ok | Compared with the original, headers and footers included. |
| 2026-11-08 | Word for Mac 16.114.4 | `build/d4/model-owner/features.docx` | ok | Compared with the original, headers and footers included. |
| 2026-11-08 | Word for Mac 16.114.4 | `build/d4/model-owner/long.docx` | ok | Compared with the original, headers and footers included. |
| 2026-11-08 | Word for Mac 16.114.4 | `build/d4/model-owner/builtins.docx` | ok | Compared with the original, headers and footers included. |
| 2026-11-08 | Word for Mac 16.114.4 | `build/d4/edited-owner/blank.docx` | ok | Footer page numbers, last section landscape A4 with the table, heading and list. Values read by Claude in Word as well. |
| 2026-11-08 | Word for Mac 16.114.4 | `build/d4/edited-owner/features.docx` | ok | Footer page numbers, last section landscape A4 with the table, heading and list. Values read by Claude in Word as well. |
| 2026-11-08 | Word for Mac 16.114.4 | `build/d4/edited-owner/long.docx` | ok | Footer page numbers, last section landscape A4 with the table, heading and list. Values read by Claude in Word as well. |
| 2026-11-08 | Word for Mac 16.114.4 | `build/d4/edited-owner/builtins.docx` | ok | Footer page numbers, last section landscape A4 with the table, heading and list. Values read by Claude in Word as well. |
| 2026-11-08 | Word for Mac 16.114.4 | Save in Word | ok | D4: `d4_sections`, `d4_headers`, `d4_fields`, `d4_break_last` and an edited owner file. |
| 2026-11-08 | Word for Mac 16.114.4 | `build/d5/fixtures/d5_pictures.docx` | ok | Body, cell and header pictures at 3 × 1.5, 144 × 240 and 3 × 1.5 pt with their names and alt text; repeating header row; the logo header on every page. Values read by Claude in Word as well. |
| 2026-11-08 | Word for Mac 16.114.4 | `build/d5/fixtures/d5_links.docx` | ok | Bookmark `Overview` over the heading; external link with its ScreenTip, internal link to the bookmark and the footer link, all in the Hyperlink style; links followed. Values read by Claude in Word as well. |
| 2026-11-08 | Word for Mac 16.114.4 | `build/d5/fixtures/d5_properties.docx` | ok | Every core property, company, revision 3 and both times as listed. Word shows its own application name and no content status; the file holds `jet_office` and `Final`. Values read by Claude in Word as well. |
| 2026-11-08 | Word for Mac 16.114.4 | `build/d5/model/d5_*.docx` | ok | All three opened: as the fixtures. Values read by Claude in Word as well. |
| 2026-11-08 | Word for Mac 16.114.4 | `build/d5/model-owner/blank.docx` | ok | As the original, properties included. Values read by Claude in Word as well. |
| 2026-11-08 | Word for Mac 16.114.4 | `build/d5/model-owner/features.docx` | ok | As the original, its comment and properties included. Values read by Claude in Word as well. |
| 2026-11-08 | Word for Mac 16.114.4 | `build/d5/model-owner/long.docx` | ok | As the original; the 13 table of contents links each reach a `_Toc` bookmark. Values read by Claude in Word as well. |
| 2026-11-08 | Word for Mac 16.114.4 | `build/d5/model-owner/builtins.docx` | ok | As the original; its external link to `https://example.com/`. Values read by Claude in Word as well. |
| 2026-11-08 | Word for Mac 16.114.4 | `build/d5/edited-owner/blank.docx` | ok | Picture, external link, internal link to `Model_edit`, title `Edited by the model`; Word's Hyperlink style added (Word shows it under its Turkish id `Kpr`). Values read by Claude in Word as well. |
| 2026-11-08 | Word for Mac 16.114.4 | `build/d5/edited-owner/features.docx` | ok | Picture, external link, internal link to `Model_edit`, title `Edited by the model`; Word's Hyperlink style added (Word shows it under its Turkish id `Kpr`). Values read by Claude in Word as well. |
| 2026-11-08 | Word for Mac 16.114.4 | `build/d5/edited-owner/long.docx` | ok | Picture, external link, internal link to `Model_edit`, title `Edited by the model`; links in the file's own `Kpr` style. Values read by Claude in Word as well. |
| 2026-11-08 | Word for Mac 16.114.4 | `build/d5/edited-owner/builtins.docx` | ok | Picture, external link, internal link to `Model_edit`, title `Edited by the model`; links in the file's own `Kpr` style. |
| 2026-11-08 | Word for Mac 16.114.4 | Save in Word | ok | D5: no repair prompt in any file, nor on reopening one changed and saved in Word. |
| 2026-11-08 | Word for Mac | `build/d6/fixtures/d6_list.docx` | ok | D6. Owner: "Hepsi sorunsuz" (all fine). |
| 2026-11-08 | Word for Mac | `build/d6/fixtures/d6_list_landscape.docx` | ok | D6. Owner: "Hepsi sorunsuz" (all fine). |
| 2026-11-08 | Word for Mac | `build/d6/model/d6_*.docx` | ok | D6. Owner: "Hepsi sorunsuz" (all fine). |
| 2026-11-08 | Word for Mac | `build/d6/model-owner/*.docx` | ok | D6. Owner: "Hepsi sorunsuz" (all fine). |
| 2026-11-08 | Word for Mac | `build/d6/edited-owner/*.docx` | ok | D6. Owner: "Hepsi sorunsuz" (all fine). |
| 2026-11-08 | Word for Mac | `build/d6/list-into-owner/*.docx` | ok | D6. Owner: "Hepsi sorunsuz" (all fine). |
| 2026-11-08 | Word for Mac | `build/d6/benchmark/large.docx` | ok | D6. Owner: "Hepsi sorunsuz" (all fine). |
| 2026-11-08 | Word for Mac | Save in Word | ok | D6. Owner: "Hepsi sorunsuz" (all fine). |

## Final checklist

One line per milestone: what the owner opened in Word for Mac, where the
result is recorded (the rows of "Results" above name each file) and whether
it is done. A milestone is done only when every file shows no repair prompt
and the text the section lists (decision
[`0010`](decisions/0010-phase-4-docx-document-model.md)).

| Milestone | What was opened | Recorded under "Results" | Result |
|---|---|---|---|
| D1 | the five `d1_*` fixtures, the round trips and edits of the owner's four files, save in Word, the expected texts | rows of 2026-11-06 (`d1_*`, `model-docx-owner`, `edited-docx-owner`, Save in Word, Expected texts) | ok |
| Own parts (decision 0011) | `d1_blank`, `d2_*` and the edited `blank` and `features` again, with the new document's own parts | rows of 2026-11-06 marked "Own parts", and 2026-11-07 (`d1_blank` after the `w14` fix) | ok |
| D2 | the four `d2_*` fixtures, their round trip, the edited owner files, save in Word | rows of 2026-11-06 (`d2_*`, `model-docx`, Save in Word) | ok |
| D3 | the five `d3_*` fixtures, their round trips, the edited owner files, `d3_table_last`, save in Word | rows of 2026-11-07 | ok |
| D4 | `d4_sections`, `d4_headers`, `d4_fields`, `d4_break_last`, the round trips and edited owner files, save in Word | rows of 2026-11-08 under `build/d4/` | ok |
| D5 | `d5_pictures`, `d5_links`, `d5_properties`, the round trips and edited owner files, save in Word | rows of 2026-11-08 under `build/d5/` | ok |
| D6 | `d6_list`, `d6_list_landscape`, their round trips, the round trips and edited owner files, the list written into the owner files, the benchmark's `large.docx`, save in Word | rows of 2026-11-08 under `build/d6/` | ok |

## Messages

`docs/warning-messages.md` lists every warning message in English, German and
Turkish, built for one sample warning and generated by
`tool/warning_messages.dart`. The table below is its DOCX section, the
messages of `DocxWarningCode` (see that file for the sample warning each row
is built for), with a column for each reader's verdict. The Turkish reader is
the owner; the German reader is a native speaker the owner names. Read the
column of your language only: write `ok`, or the correction you want, in your
verdict column, and fill the reviewers in the table after it. The XLSX
messages are checked in
[`excel-checks.md`](excel-checks.md), "Native-speaker check". After a message
changes, regenerate `docs/warning-messages.md` and copy its DOCX rows here;
the verdicts of a changed row are void.

| Code | en | de | tr | Verdict tr (owner) | Verdict de (reader) |
|---|---|---|---|---|---|
| `docx: invalidCharactersRemoved` | 2 characters that XML does not allow were removed from text in /word/document.xml (body/p[0], body/p[1]). | 2 Zeichen, die XML nicht erlaubt, wurden aus dem Text in /word/document.xml entfernt (body/p[0], body/p[1]). | /word/document.xml içindeki metinden XML'in izin vermediği 2 karakter çıkarıldı (body/p[0], body/p[1]). |  |  |
| `docx: invalidCharactersRemoved` (one) | 1 character that XML does not allow was removed from text in /word/document.xml (body/p[0]). | 1 Zeichen, das XML nicht erlaubt, wurde aus dem Text in /word/document.xml entfernt (body/p[0]). | /word/document.xml içindeki metinden XML'in izin vermediği 1 karakter çıkarıldı (body/p[0]). |  |  |
| `docx: contentTypeMissing` | /word/document.xml had no content type; it was read as application/xml. | Für /word/document.xml fehlte der Inhaltstyp; der Teil wurde als application/xml gelesen. | /word/document.xml için içerik türü yoktu; application/xml olarak okundu. |  |  |
| `docx: mainPartContentTypeUnexpected` | The main document /word/document.xml has the content type text/plain, which is not a Word document type; it was read as one. | Das Hauptdokument /word/document.xml hat den Inhaltstyp text/plain, der kein Word-Dokumenttyp ist; es wurde als Word-Dokument gelesen. | Ana belge /word/document.xml, Word belge türü olmayan text/plain içerik türüne sahip; Word belgesi olarak okundu. |  |  |
| `docx: numberingNotFound` | 2 paragraphs in /word/document.xml (body/p[0], body/p[1]) belong to the list 7, which the document does not define; Word shows them without a number. | 2 Absätze in /word/document.xml (body/p[0], body/p[1]) gehören zur Liste 7, die das Dokument nicht definiert; Word zeigt sie ohne Nummer. | /word/document.xml (body/p[0], body/p[1]) içindeki 2 paragraf, belgenin tanımlamadığı 7 listesine ait; Word bunları numarasız gösterir. |  |  |
| `docx: numberingNotFound` (one) | 1 paragraph in /word/document.xml (body/p[0]) belongs to the list 7, which the document does not define; Word shows it without a number. | 1 Absatz in /word/document.xml (body/p[0]) gehört zur Liste 7, die das Dokument nicht definiert; Word zeigt ihn ohne Nummer. | /word/document.xml (body/p[0]) içindeki 1 paragraf, belgenin tanımlamadığı 7 listesine ait; Word onu numarasız gösterir. |  |  |
| `docx: styleNotFound` | 2 references in /word/document.xml (body/p[0], body/p[1]) name the style Foo, which the document does not define; Word shows them in the default style. | 2 Verweise in /word/document.xml (body/p[0], body/p[1]) nennen die Formatvorlage Foo, die das Dokument nicht definiert; Word zeigt sie in der Standardformatvorlage. | /word/document.xml (body/p[0], body/p[1]) içindeki 2 başvuru, belgenin tanımlamadığı Foo stilini adlandırıyor; Word bunları varsayılan stilde gösterir. |  |  |
| `docx: styleNotFound` (one) | 1 reference in /word/document.xml (body/p[0]) names the style Foo, which the document does not define; Word shows it in the default style. | 1 Verweis in /word/document.xml (body/p[0]) nennt die Formatvorlage Foo, die das Dokument nicht definiert; Word zeigt ihn in der Standardformatvorlage. | /word/document.xml (body/p[0]) içindeki 1 başvuru, belgenin tanımlamadığı Foo stilini adlandırıyor; Word onu varsayılan stilde gösterir. |  |  |
| `docx: propertyValueInvalid` | Document property cp:revision in /docProps/core.xml could not be read; it was kept as it is. | Die Dokumenteigenschaft cp:revision in /docProps/core.xml konnte nicht gelesen werden; sie wurde unverändert beibehalten. | /docProps/core.xml içindeki cp:revision belge özelliği okunamadı; olduğu gibi korundu. |  |  |
| `docx: bookmarkNameRepaired` | 2 bookmark names in /word/document.xml did not follow Word's rules and were repaired: 2 Totals!. | 2 Textmarkennamen in /word/document.xml entsprachen nicht den Regeln von Word und wurden korrigiert: 2 Totals!. | /word/document.xml içindeki 2 yer işareti adı Word kurallarına uymuyordu ve düzeltildi: 2 Totals!. |  |  |
| `docx: bookmarkNameRepaired` (one) | A bookmark name in /word/document.xml did not follow Word's rules and was repaired: 2 Totals!. | Ein Textmarkenname in /word/document.xml entsprach nicht den Regeln von Word und wurde korrigiert: 2 Totals!. | /word/document.xml içindeki bir yer işareti adı Word kurallarına uymuyordu ve düzeltildi: 2 Totals!. |  |  |

| Language | Reviewer | Date | Corrections |
|---|---|---|---|
| tr | Ahmet Urel (owner) | not checked |  |
| de | not named yet | not checked |  |
