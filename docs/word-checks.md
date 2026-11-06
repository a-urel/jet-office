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

(The D2 section below uses the same commands; its folders hold the `d2_*`
documents as well.)

`build/fixtures` also holds the workbooks of the Excel checks; open the
`d1_*.docx` files (D1) and the `d2_*.docx` files (D2).
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

## Results

One row per file or check. `Result` is `ok`, `sorun` (a problem) or `not
checked`; `Notes` says what was seen, and a repair prompt names the part from
its recovery log.

| Date | Word | File | Result | Notes |
|---|---|---|---|---|
