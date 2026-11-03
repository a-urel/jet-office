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

`build/fixtures` also holds the workbooks of the Excel checks; open the
`d1_*.docx` files. `tool/round_trip_docx.dart` prints each difference between
an input and the model's output and exits 1 on any, so run it first and
expect none; `tool/edit_docx.dart` likewise prints each problem with an
edited document and exits 1 on any. (CI uses other folder names: its
`build/model-docx` is the round trip of LibreOffice's re-save of the
fixtures, and its `build/edited-docx` the edit of that re-save.)

For every file, first check that Word opens it without a repair prompt ("Word
found unreadable content", "Word experienced an error trying to open the
file"). The lists below say what to see. The owner's own Word files are the
three in `test/fixtures/owner/docx/`; their expected texts are
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
  owner's originals: `features.docx` keeps its heading, bullet list, table,
  header, footer and comment; `long.docx` keeps its table of contents, two
  tables and lists, and its 15 pages.

### Edited owner files: `build/edited-docx-owner/*.docx`

The model opened each of the owner's Word files, set the text of the first
run that has text to `Edited by the model`, replaced the last paragraph that
holds runs only (no bookmark, field, hyperlink or drawing) with
`Replaced by the model`, and added `Added by the model` at the end of the
body. The owner's files define their heading style as `Balk1` (Turkish
Word), not `Heading1`, so the added paragraph has the style `Normal`. Open
`blank.docx`, `features.docx` and `long.docx`. No repair prompt, the edits
visible, and everything else as in the original:

- `blank.docx`: it has no text, so no run is edited; its one empty
  paragraph reads `Replaced by the model`, and `Added by the model` follows.
- `features.docx`: the heading `Quarterly report` reads `Edited by the
  model` and is still a Heading 1 (`Başlık 1`); `End of report.` reads
  `Replaced by the model`; `Added by the model` is the last paragraph, in
  the Normal style. The bullet list, table, header, footer and comment are
  as in the original.
- `long.docx`: the title `DENEME BELGESİ` reads `Edited by the model` in
  its Title style; the empty last paragraph reads `Replaced by the model`;
  `Added by the model` follows it. The table of contents, the two tables,
  the lists and the 15 pages are as in the original (the added line may
  start a sixteenth page).

### Save in Word

For `d1_blank`, `d1_text_rules` and one round-tripped owner file, change one
word, save in Word, close and reopen: no repair prompt, and the edit is there.

## Results

One row per file or check. `Result` is `ok`, `sorun` (a problem) or `not
checked`; `Notes` says what was seen, and a repair prompt names the part from
its recovery log.

| Date | Word | File | Result | Notes |
|---|---|---|---|---|
