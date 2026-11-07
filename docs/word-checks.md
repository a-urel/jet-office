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
document that ends in a table. The D4 section has commands of its own, which
write to `build/d4/`.)

`build/fixtures` also holds the workbooks of the Excel checks; open the
`d1_*.docx` files (D1), the `d2_*.docx` files (D2), the `d3_*.docx` files
(D3) and the `d4_*.docx` files (D4).
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
    for a page break. Both footers now read `Page 1 of 2, section pages: 2` and
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
