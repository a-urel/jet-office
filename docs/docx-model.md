# DOCX document model

`DocxDocument` opens a DOCX file from bytes, or starts a new document, lets a
caller read and edit the body's paragraphs, and saves the file again. Saving
keeps everything the caller did not change: the model is the single source of
every save. Decision
[`0010`](decisions/0010-phase-4-docx-document-model.md) sets the scope and the
fidelity standard; it applies decision
[`0009`](decisions/0009-phase-3-workbook-model.md)'s preservation layers to
WordprocessingML.

This page covers milestone D1, the foundation, milestone D2, formatting,
styles and lists, milestone D3, tables, milestone D4, sections, headers,
footers and fields, milestone D5, pictures, hyperlinks, bookmarks and
document properties, milestone D6, the list export, and milestone T1, the
fill of a template's values (decision
[`0024`](decisions/0024-docx-template-fill.md)). **The names are fixed
as of D6** (decision 0010): the DOCX API is complete for phase 4, and a later
rename is a breaking change. D6 renamed three symbols that D1 to D5 had
published only inside the repository (see "What D6 does").

```dart
final DocxDocument doc = DocxDocument.open(bytes);
doc.body.addParagraph('Toplam: 1.234,50 ₺');
final Uint8List saved = doc.save().bytes;
```

Formatting, a heading and a list (D2):

```dart
final DocxDocument doc = DocxDocument();
doc.body.addParagraph('Quarterly report').style = 'Heading1';
doc.body.addParagraph().addRun('Total: ').properties.bold = true;
final DocxNumberingInstance list = doc.numbering.addBulletList();
doc.body.addListItem(list, 'First item');
doc.body.addListItem(list, 'Nested item', level: 1);
```

A table, a merge and a nested table (D3):

```dart
final DocxDocument doc = DocxDocument();
final DocxTable table = doc.body.addTable(columns: 3);
table.addRow(<String?>['Item', 'Quantity', 'Price'], header: true);
table.addRow(<String?>['Tea', '2', '3.50']);
table.addRow(<String?>['Total', null, '7.00']);
table.mergeCells(firstRow: 2, firstColumn: 0, lastRow: 2, lastColumn: 1);
table.rows[1].cells[0].addTable(columns: 2).addRow(<String?>['a', 'b']);
```

A landscape section with page numbers in its footer (D4):

```dart
final DocxDocument doc = DocxDocument();
doc.body.addParagraph('Cover');
final DocxSection report = doc.body.addSection();
report.pageSize = DocxPageSize.a4(landscape: true);
report.footer.addParagraph('Page ')
  ..addField(DocxField.page())
  ..addRun(' of ')
  ..addField(DocxField.numPages());
doc.body.addParagraph('The report.');
```

A picture, a bookmark, two hyperlinks and the document's title (D5):

```dart
final DocxDocument doc = DocxDocument();
final DocxParagraph heading = doc.body.addParagraph()..style = 'Heading1';
final DocxBookmarkStart top = heading.addBookmarkStart('Top');
heading
  ..addRun('Report')
  ..addBookmarkEnd(top);
doc.body.addParagraph().addPicture(OfficeImage(logoPng), widthPt: 72);
doc.body.addParagraph('See ')
  ..addHyperlink('the site', url: 'https://example.com/')
  ..addRun(' or go back to ')
  ..addHyperlink('the top', anchor: 'Top');
doc.properties = const OfficeProperties(title: 'Report');
```

A list under a page header and footer (D6):

```dart
final DocxResult out = DocxListExport(
  const <DocxListColumn>[
    DocxListColumn('Code', widthPt: 80),
    DocxListColumn('Amount', numberFormat: '#,##0.00'),
  ],
  title: 'Accounts',
  date: DateTime(2026, 11, 8),
).toDocx(<List<Object?>>[
  <Object?>['A-1', 1234.5],
  <Object?>['A-2', 99.5],
]);
```

## What D1 does and does not do

- **Typed.** The body's paragraphs (`DocxParagraph`), their runs
  (`DocxRun`), the paragraph and run style, and a run's text, tabs, breaks and
  carriage returns (`DocxRunContent`).
- **Opaque, kept as written.** Everything else: content controls, bookmarks,
  tracked changes, hyperlinks, drawings, `w:fldSimple` and
  `mc:AlternateContent` (`DocxOpaqueBlock`, `DocxOpaqueInline`,
  `DocxOpaqueRunContent`). An opaque node can be removed, not changed.
- **The final `w:sectPr`** of the body is held by the body, not by its
  blocks; D4 types it (`DocxDocument.sections`).
- **Edits.** `addParagraph`, `insertBlock`, `removeBlockAt`,
  `replaceBlockAt`, the same for inlines, a run's `text` and the two styles.
  Each edit is atomic (a transaction of the document's `ChangeLog`).
- **Not in D1.** Formatting, styles and lists (D2, below), tables (D3, below),
  sections, headers, footers and complex fields (D4, below), pictures,
  hyperlinks, bookmarks and document properties (D5), `DocxListExport` (D6).
  Notes and comments are saved as they were, not read.

## What D2 does

- **Run and paragraph properties, typed.** `DocxRun.properties`
  (`DocxRunProperties`: `style`, `fonts`, `bold`, `italic`, `caps`,
  `smallCaps`, `strike`, `doubleStrike`, `underline`, `color`, `highlight`,
  `shading`, `sizePt`, `verticalAlign`, `characterSpacingPt`, `language`)
  and `DocxParagraph.properties` (`DocxParagraphProperties`: `style`,
  `alignment`, `indentation`, `spacing`, `keepWithNext`, `keepLines`,
  `pageBreakBefore`, `widowControl`, `outlineLevel`, `borders`, `shading`,
  `tabs`, `numbering`). Each is a nullable get and set, `null` meaning "not
  set here". `DocxParagraph.style` and `DocxRun.style` stay, as shortcuts.
- **Styles.** `DocxDocument.styles` (`DocxStyles`): the document defaults,
  every style by id or by name, `add` for a custom style, and Word's
  built-in styles (`DocxBuiltInStyle`) added on demand, also in a document
  whose built-in style ids are localized.
- **Numbering.** `DocxDocument.numbering` (`DocxNumbering`): the
  definitions and instances of the numbering part, `addBulletList`,
  `addNumberedList`, `addInstance` (with start overrides) and
  `DocxBody.addListItem`.
- **Still opaque, kept as written:** everything D1 kept, plus whatever of a
  property container the model does not type (see the first rule of
  "Properties" below).

## What D3 does

- **Tables, typed.** A `w:tbl` in the body or in a cell is a `DocxTable`: its
  `rows` (`DocxTableRow`), each with its `cells` (`DocxTableCell`), each with
  its `blocks` again, so tables nest. `DocxTable.gridColumnsPt` is the
  `w:tblGrid` in points, and `DocxTableCell.text` the text of a cell. Only
  the typed `w:tr` and `w:tc` are listed; what lies between them is kept
  (see "Known gaps of D3").
- **Properties, typed.** `DocxTable.properties` (`DocxTableProperties`:
  `style`, `width`, `layout`, `alignment`, `indentationPt`, `borders`,
  `cellMargins`, `look`), `DocxTableRow.properties`
  (`DocxTableRowProperties`: `height`, `cantSplit`, `repeatAsHeader`, with
  `isHeader` as a shortcut on the row) and `DocxTableCell.properties`
  (`DocxTableCellProperties`: `width`, `gridSpan`, `verticalMerge`,
  `verticalAlignment`, `shading`, `borders`, `textDirection`), each a
  nullable get and set in the way of the paragraph's, over the values
  `DocxTableWidth`, `DocxTableBorders`, `DocxCellBorders`,
  `DocxTableMargins`, `DocxTableLook`, `DocxRowHeight` and the enumerations.
- **Building.** `DocxBody.addTable` writes what Word's Insert Table writes
  (the style `Table Grid`, an automatic width, the look `04A0`, equal column
  widths), `DocxTable.addRow` adds a row of text, `DocxTableCell.addTable`
  nests a table, and `DocxTable.new`, `DocxTableRow.new` and
  `DocxTableCell.new` build parts to insert later.
- **Editing.** `insertRow`, `removeRowAt`, `insertCell`, `removeCellAt`,
  the blocks of a cell (`addParagraph`, `insertBlock`, `removeBlockAt`,
  `replaceBlockAt`), `gridColumnsPt`, the properties, and
  `DocxTable.mergeCells`, which merges a range across and down as Word does.
  Each edit is atomic, in the document's `ChangeLog`; the styles of what goes
  in are resolved as for a paragraph (D2).
- **Kept as written, never typed:** `w:tblpPr`, `w:tblOverlap`,
  `w:bidiVisual`, the band sizes, `w:tblCellSpacing`, a table's `w:shd`,
  `w:tblCaption`, `w:tblDescription`, `w:cnfStyle`, `w:tcMar`, `w:noWrap`,
  `w:tcFitText`, `w:hideMark`, `w:hMerge`, `w:hidden`, `w:wBefore`,
  `w:wAfter`, a row's `w:jc` and the revision children (`w:tblPrChange` and
  the like). `w:gridBefore` and `w:gridAfter` are read for the grid check
  only. A cell written by the API carries no `w:cnfStyle`: Word recomputes
  it.

## What D4 does

- **Sections, typed.** `DocxDocument.sections` lists each `DocxSection`: one
  for each top-level paragraph of the body with a `w:sectPr`, in order, then
  the last, which every document has. A section gives `pageSize`
  (`DocxPageSize`), `margins` (`DocxPageMargins`), `columns` (`DocxColumns`,
  `DocxColumn`), `start` (`DocxSectionStart`), `titlePage`,
  `verticalAlignment` (`DocxSectionVerticalAlignment`), `pageNumbering`
  (`DocxPageNumbering`), `lineNumbering` (`DocxLineNumbering`), each a nullable
  get and set in the way of the paragraph's (`titlePage` a `bool`), and
  `textWidthPt`. `DocxBody.addSection` ends the last section and starts a new
  one, as Word's Insert Break does.
- **Headers and footers, typed.** A section's six getters (`header`,
  `firstHeader`, `evenHeader`, `footer`, `firstFooter`, `evenFooter`) give a
  `DocxHeaderFooter`: the section's own story, else the nearest previous
  section's (`isInherited`), else an empty one. It is a `DocxStory`, as the
  `DocxBody` is, so it holds the same blocks, tables and lists among them, and
  takes the same edits. `ownHeader`, `ownFooter`, `removeHeader` and
  `removeFooter` unlink and link a section again.
  `DocxDocument.evenAndOddHeaders` is the one typed child of `settings.xml`.
- **Complex fields, typed.** A plain field of one paragraph is one `DocxField`
  among its inlines: `instruction`, `name`, `result`, `resultText` and
  `properties`. `DocxField.new` builds any field, and `.page()`, `.numPages()`,
  `.sectionPages()`, `.date()` and `.time()` the common ones;
  `DocxParagraph.addField` adds one. In a run, `w:fldChar` and `w:instrText`
  are `DocxFieldMark` and `DocxFieldInstruction`, typed content that gives no
  text, also where the field around them is not plain. The model does not
  evaluate a field: its text is the result as cached.
- **Still kept as written, never typed:** `w:fldSimple` and `w:delInstrText`,
  which stay opaque (a `w:fldSimple` still gives its visible text); of a section
  `w:pgBorders`, `w:paperSrc`, `w:docGrid`, `w:footnotePr`, `w:endnotePr`,
  `w:formProt`, `w:noEndnote`, `w:textDirection`, `w:bidi`, `w:rtlGutter`,
  `w:printerSettings`, `w:sectPrChange` and the chapter attributes of
  `w:pgNumType`; every child of `settings.xml` but `w:evenAndOddHeaders`.
- **No new read limit and no new warning code.** Story parts are bounded by
  `maxEntries` and each part by the part limits, a broken reference is kept
  silently, and an instruction's forbidden characters report
  `invalidCharactersRemoved`. A warning in a story starts with the part's name:
  `word/header1.xml/p[0]/r[1]`.

## What D5 does

- **Document properties, typed.** `DocxDocument.properties` is an
  `OfficeProperties`, the type `XlsxWorkbook.properties` gives too (it was
  `XlsxProperties`; one value class, writers and change for both formats, in
  `lib/src/common/`): the core part's title, subject, creator, keywords,
  description, last modified by, `revision`, category, content status and the
  two dates, the extended part's `application`, company and manager, and the
  custom properties. The parts load on the first read, each found by its
  package relationship; a set is one change and re-encodes only the children
  it changes.
- **Pictures, typed.** A `w:drawing` holding one `wp:inline` that shows one
  `pic:pic` is a `DocxPicture`, run content that gives `widthPt`, `heightPt`,
  `name`, `description` and `image` (`OfficeImage?`). A read picture is written
  as read. `DocxParagraph.addPicture` adds a PNG or JPEG picture in the body, a
  cell, a header or a footer, at its pixel size or a size given.
- **Hyperlinks, typed.** A `w:hyperlink` that is a direct child of a paragraph
  is a `DocxHyperlink`, an inline holding inlines as `DocxField` does: `url`
  (the external target of its `r:id`), `anchor`, `tooltip`, `inlines` and
  `text`. Its runs are ordinary `DocxRun`s, whose text and properties can be
  set. `DocxParagraph.addHyperlink` adds an external or an internal link in
  the character style `Hyperlink`.
- **Bookmarks, typed.** `w:bookmarkStart` and `w:bookmarkEnd` in a paragraph
  or a typed hyperlink are `DocxBookmarkStart` (`id`, `name`) and
  `DocxBookmarkEnd` (`id`). `addBookmarkStart` and `addBookmarkEnd` add a
  pair, whose start and end may be in different paragraphs; a name breaking
  Word's rules is repaired (`repairBookmarkName`).
- **Allocated at save, never stored.** Every relationship, media part,
  `wp:docPr` id, bookmark id and default picture name a built picture, link or
  bookmark needs is given by each save and taken back once the file is
  written (Ruling A), as D4 creates story parts at save: the change log never
  touches the package, two saves of one model give the same file, and an undo
  leaves nothing behind.
- **Two new warning codes:** `propertyValueInvalid` (a property value that
  cannot be read; it reads `null` and stays) and `bookmarkNameRepaired`. No
  new read limit.
- **Still kept as written, never typed** (Ruling 15): floating pictures
  (`wp:anchor`), charts, shapes, groups and `mc:AlternateContent` in a
  drawing, `w:fldSimple`, a hyperlink's `w:tgtFrame`, `w:history` and
  `w:docLocation` (kept on a read link, as read), `w14:paraId`, and a
  bookmark between blocks or in a table row. A linked picture is typed, with
  `image` `null`.

## What D6 does

- **`DocxListExport`, a list as a Word document.** The Word counterpart of
  `XlsxListExport`: `DocxListExport(columns, ...)` with `writeTo(document,
  rows, {totals})`, which writes a list into the last section of a document
  that exists, and `toDocx(rows, {totals, properties})`, which returns a
  document of its own. It composes the public model's calls and writes no XML
  of its own (a guard test keeps `list_export.dart` to the barrel's files,
  `lib/src/common/` and `package:jet_core`).
- **The page, every page.** A header paragraph with the logo at the left, the
  report name centred in bold and the date at the right (a centre and a right
  tab stop at the text width); a footer with the caller's text around `PAGE`
  and `NUMPAGES` (`Page 2 of 3` by default, `Sayfa 2 / 3` with
  `footerBefore: 'Sayfa '` and `footerMiddle: ' / '`); an optional caption
  above the table. The size is A4 portrait and the margins are Word's blank
  document's (2.5 cm; header and footer 1.25 cm) unless the caller gives them.
- **The table.** `Table Grid`, one column per `DocxListColumn`, a header row
  that is bold, shaded `D9D9D9` (or the caller's `headerShading`, or none),
  repeated on every page and never split, then the data rows, then the totals
  row when the caller gives one. A column with a number format is aligned to
  the end of the line unless the column says otherwise.
- **Values as Excel shows them.** A cell's text comes from `jet_core`'s
  `NumberFormatter` with the column's Excel number format code and the
  export's `locale`: a number, a `FormatDecimal` (so an `XlsxDecimal`, and the
  rows of an Excel list export can be passed as they are), a `DateTime`, a
  `Duration` or a `bool`. A `String` is written as given, `null` is an empty
  cell, anything else throws.
- **Totals come from the caller.** Word has no formulas, so `totals` holds the
  values to show, formatted like the data; the helper adds nothing up.
- **The date is text.** `date` is the report's date as the caller gives it,
  written with `dateFormat` (the locale's short date by default), not a `DATE`
  field, which would show the day the file is opened.
- **Programmer errors throw, data problems warn, as everywhere.** A bad column
  list, header, width, number or date format code, logo height, header
  shading or totals value, or a row too long or with a value that cannot be
  shown, throws `ArgumentError` naming the field, before the document changes;
  a control character in a text still warns `invalidCharactersRemoved`. No new
  warning code.
- **`OfficeProperties.copyWith`** replaces the fields it is given and keeps
  the others (it closes the gap of D5 that `tool/edit_docx.dart` had called
  `_withTitle`; it works for `XlsxWorkbook.properties` too).
- **Names are fixed.** The dartdoc review of the whole DOCX surface renamed
  `DocxTable.insertRowAt` to `insertRow` and `DocxTableRow.insertCellAt` to
  `insertCell` (the other containers' inserts are `insertBlock` and
  `insertInline`), and `DocxCellAlignment` to `DocxCellVerticalAlignment` (it
  is the vertical alignment of a cell and, beside `DocxAlignment` and
  `DocxVerticalAlign`, the old name read as the paragraph's). None had been
  released, so the old names are gone. Three names that were questioned stay,
  each with its reason: `DocxVerticalAlign` mirrors `w:vertAlign` and the
  member `verticalAlign`, and its values `superscript` and `subscript` cannot
  be confused with a cell's or a section's alignment; the `DocxTextDirection`
  values `lrTbV`, `tbRlV` and `tbLrV` mirror `ST_TextDirection`; and
  `DocxAlignment` keeps the bare name, since a paragraph's `w:jc` is the common
  alignment.
- **A benchmark of a large Word document**
  (`benchmark/docx_model_benchmark_test.dart`, figures in
  [`benchmark.md`](benchmark.md)): the owner's `long.docx` repeated to about
  40,000 paragraphs is opened, loaded, changed and saved. The scaling is
  `scaledLongDocx` (`test/docx/support/large_document.dart`), and
  `tool/write_large_docx.dart` writes the same document, with one paragraph
  edited, for the owner's Word check.
- **The fuzz** runs 900 cases a seed instead of 750, the D6 fixtures joining
  the corpus.

## What T1 does

T1 adds `DocxTemplate`, the fill of values into a Word template (decision
[`0024`](decisions/0024-docx-template-fill.md)): the owner writes `{{name}}`
tags, or Word merge fields, in Word, and the library puts the values in. The
rulings the plan made are recorded here; the spec left them to it or was
silent.

```dart
final DocxResult result = DocxTemplate(bytes).fill(
  <String, Object?>{
    'firma': <String, Object?>{'unvan': 'Acme A.Ş.'},
    'tarih': DateTime(2026, 11, 14),
    'tutar': FormatDecimal('1234.56'),
  },
  options: const DocxTemplateOptions(locale: FormatLocale.trTR),
);
```

- **What is filled.** A value tag `{{name}}`, `{{a.b}}` (a path through maps)
  or `{{name:format}}` (a format code the number format engine reads, as in a
  cell), and a `MERGEFIELD` (a complex field or a `w:fldSimple`) by its whole
  name, as a key of the data, with `\@` date and `\#` number pictures
  translated to format codes, and `\* Upper`, `Lower`, `FirstCap` and `Caps`
  casing in the locale. A `\* MERGEFORMAT` or `\* CHARFORMAT` is ignored
  silently, as Word adds one to every field.
- **Where.** The body, table cells (nested ones too), every header and footer
  part, once each even when sections share it. Tags in a text box, a block
  content control, a footnote, an endnote or a comments part are found and
  warned, not changed.
- **Tags Word split.** A tag spread over runs (Word writes the first brace in
  its own run, or splits at a spell-check mark) is replaced as one: the value
  takes the run properties of the tag's first character, bookmarks, comment
  ranges, `w:proofErr` and the like between the runs stay, and the runs wholly
  inside the tag go. Text around a tag stays as it was, in its own run.
- **Values.** A string, number, `bool`, `DateTime`, `Duration` or `FormatDecimal`
  is text; `Duration` without a code shows as `[h]:mm:ss`, a `DateTime` as
  format 14. A line break or tab in the text becomes a `w:br` or `w:tab`;
  characters XML cannot hold are removed and warned. The value is never
  scanned for tags again. A list, a map or a picture in a value tag leaves the
  tag as written and warns `templateValueNotText`. The data is checked before
  anything changes: an unsupported type, a key that is not a string or a cycle
  throws an `ArgumentError` naming the path, and the document is as it was.
- **A missing name.** The tag stays as written and the fill warns
  `templateValueMissing` with the tag as detail; `removeMissing` removes it and
  still warns.
- **Warnings.** Every template warning has the tag, or the field instruction,
  as written as its detail (cut by `displayText`) and the paragraph's path
  (`body/p[3]`, `header1.xml/p[0]`) as its location. `fill` returns a
  `DocxResult` holding the fill's warnings, then the save's; `fillDocument`
  returns the fill's alone, and neither adds them to `DocxDocument.warnings`.
  A tag found in a footnotes, endnotes or comments part has no location
  (`null`): the fill does not walk those parts' paragraphs. A tab, break or
  carriage return in a detail shows as a space, and no detail or listed tag
  holds U+FFFC, the stand-in the scan uses for content without text.
- **Within a paragraph, text tags first.** The `{{}}` tags of a paragraph are
  filled before its merge fields (Ruling 7a), so a merge field's value that
  holds `{{x}}` is not filled again, as a tag's value is not.
- **Listing.** `DocxTemplate.tags` and `tagsOf(document)` list every tag, each
  with its kind (value, section, inverted section, end, current, merge field,
  malformed), name, format, depth and whether it can be filled, in reading
  order, changing nothing.
- **One transaction.** A fill is one change set: it is undone whole, and a data
  error records nothing. `fillDocument` fills a document the caller holds in
  place; `fill` opens the stored bytes again each time (no clone), so two fills
  of one template are two documents with their own values and the caller
  changing the bytes it gave afterwards changes nothing (the template copies
  them).
- **Section tags stay.** `{{#x}}`, `{{^x}}` and `{{/x}}` stay as text in T1;
  each warns `templateSectionMalformed` with the tag as detail, and the
  message says sections are not filled yet. T2 fills them.
- **The tools.** `tool/fill_docx.dart` runs the fill on a directory and checks
  what it changed (CI runs it on the fixtures and the owner's Word files),
  `tool/write_t1_check.dart` writes the owner's Word check, and the fuzz
  (`tool/fuzz_docx.dart --template`) fills mutated templates.

## Known gaps

- **Visible text of some opaque inlines.** `mc:AlternateContent` and the text
  of a text box give `''` for an opaque inline's visible text, so a paragraph
  whose words are only there reads as empty.
- **A new document has no `docProps`** until a property is set (Ruling 4 of
  D5): `DocxDocument()` saves no `core.xml` and no `app.xml`, and the library
  has no clock to fill `created` or `modified`.
- **A new document's theme is plainer than Word's** (decision 0011): no
  per-script font list, a plain format scheme, and fewer latent styles
  named, so Word's Styles pane recommends fewer built-in styles until they
  are used.
- **Fields show their cached result** until Word lays the document out; this
  library does not paginate.

### Known gaps of D2

- **The paragraph mark's `w:rPr`** (the run properties inside the
  paragraph's `w:pPr`, which style the paragraph mark) is kept and never
  typed, so it reads as nothing and a setter never changes it (test:
  `test/docx/model/paragraph_properties_test.dart`, "the paragraph mark rPr
  is never typed").
- **Style parts the model does not type.** A style's `w:tblPr`, `w:trPr`,
  `w:tcPr` and `w:tblStylePr` (the definition of a table style) are kept as
  written: D3 types a table's reference to a style, not the style's own table
  properties.
- **Measures the model reads as `null`.** The `…Chars` attributes
  (`w:leftChars`, `w:firstLineChars`), universal measures (`1in`, `2.5cm`),
  a `+` sign, and numbers of ten digits or more give no view; so does
  `w:ind` with `w:start` or `w:end`. The file is kept as written (tests: the
  "save unchanged" cases of `test/docx/model/paragraph_properties_test.dart`
  and `test/docx/model/run_properties_test.dart`).
- **Complex-script formatting is not typed.** Setting `bold` writes `w:b`
  and never `w:bCs`, `sizePt` writes `w:sz` and never `w:szCs`; setting
  `fonts` or `language` keeps the other scripts' attributes as read.
- **Art borders** (`w:val` naming a picture border) give no border view and
  are kept.
- **A dangling reference read from a file** is neither resolved nor
  reported; `styleNotFound` and `numberingNotFound` cover only references
  set through the API or moved in from another document (see "Warnings of
  D2"), and `numberingNotFound` does not check the `w:numPr` of a style's
  `w:pPr`.
- **Moving content between documents carries only the references' ids.**
  The source style's `w:name` stays behind, so a built-in under a localized
  id (`Balk1`) does not map to the target's by name and warns instead; a
  `numId` the target has too joins that list, unreported; a read opaque
  inline or block with an `r:id` keeps an id the target may lack (see
  "Styles").
- **`DocxStyles.idOf` ignores the style type.** It finds the style by the
  built-in's name whatever that style's type; a reference that has the
  wrong type is reported at save as `styleNotFound`.

### Known gaps of D3

- **Rows and cells the model does not show.** `rows` lists only the `w:tr`
  children of `w:tbl`, and `cells` the `w:tc` children of `w:tr`. A row inside
  a `w:sdt` or a `w:customXml` is not in `rows`, and a cell there is not in
  `cells`; it is kept in place, and an insert or a removal leaves it where it
  was (tests: `test/docx/model/tables_read_test.dart` "a w:tbl inside a
  w:sdt stays opaque", `test/docx/model/tables_edit_test.dart` "the rows in
  a content control are not counted"). A merge refuses a range with a
  `w:sdt` or `w:customXml` between its rows.
- **A style's table properties** (`w:tblPr`, `w:trPr`, `w:tcPr`,
  `w:tblStylePr`) are kept, as the D2 gap says; so is every child of a table,
  row and cell listed under "What D3 does" as never typed, and what the
  model cannot read of a typed one (a width in an unusual unit, a border of
  art): it reads `null` and is written back as read (test:
  `test/docx/model/table_properties_test.dart`, "a child in schema order
  among kept ones").
- **`w:hMerge` on a kept cell** is not typed, so `gridSpan` and
  `verticalMerge` do not account for a horizontal merge made that way; the
  merge checks treat such a cell as one cell.
- **A merge can be split without a warning.** A plain row inserted between a
  cell that restarts a vertical merge and the one that continues it, a row or
  a cell removed that holds one end of a merge, and `removeCellAt` and
  `insertCell`, which can move a later cell off the columns of the merge
  above or below it, are allowed: removal and insertion must keep working on
  any table, and Word reads a continuation with nothing above as a new cell
  (tests: `test/docx/model/table_merge_test.dart`, "that is plain may go
  inside a vertical merge", "a removal that orphans a merge is allowed").
  `insertCell` does not check a continuation on the
  inserted cell.
- **Two tables can end up adjacent after a merge.** `mergeCells` keeps one
  empty paragraph between two tables it brings into one cell; when the merged
  cells held none between them (a cell whose last block is a table and that
  was read without its closing paragraph, say), the tables are adjacent and
  Word joins them into one.
- **An orphan continuation read from a file** (a `w:vMerge` continue with no
  cell above, or one out of line with it) opens, reads and saves as it was;
  but a change of the span of a cell earlier in its row throws
  `ArgumentError`, because the cells it would move no longer fit what is
  above. Bring the continuation into line first (test:
  `test/docx/model/table_merge_test.dart`, "a continuation read out of line
  can be brought into line").
- **The API nests tables at most 80 deep, the reader 256.** A table takes
  three XML levels, so the default `maxDepth` of 256 stops near 84 tables, and
  what the API builds must open again under the default limits; the reader's
  own limit (`maxTableNesting`, 256, which `DocxReadLimits.maxDepth` cannot
  raise) only keeps recursion bounded. A table read nested deeper than 80 and
  then removed cannot be inserted again through the API (`ArgumentError`); its
  removal still undoes (test: `test/docx/model/tables_edit_test.dart`, "a
  table read that deep cannot go back in the API").
- **`addTable`'s default widths are the last section's text width less 10
  twips** (`textWidthPt`), shared among the columns: 9062 twips on a blank A4
  page, the width `builtins.docx` pins. The 10 twips are Word's on that page;
  on another page they are this library's reading, and the Word check of
  `d4_sections` looks at a Letter page. A section whose page or margins do not
  read, or a width that gives a column no twip, shares 9062 twips, and then a
  document needs `columnWidthsPt`, or Word's autofit corrects the widths when
  it opens the file (tests: `test/docx/model/sections_test.dart`, group
  "addTable"; `test/docx/model/table_build_test.dart`, "shares the width of a
  blank A4 page, in whole twips"). A table added to a cell shares the cell's
  own `w:tcW` when it has one in twips (tests: same file, "default widths"),
  and `DocxTable.new` stays at 9062 twips.
- **No paragraph is added** between two tables or after a last table, so two
  tables added one after the other join in Word unless the caller puts a
  paragraph between them. A body that ends in a table is saved so, and the Open
  XML SDK accepts it; whether Word opens it without a repair is for the owner's
  check (`docs/word-checks.md`), as LibreOffice's text export of one never
  ends.
- **A table with no rows** (what `addTable` returns before the first
  `addRow`) cannot be saved: `StateError` names it. A file's own empty table
  is kept as read.

### Known gaps of D4

- **A section break in a cell or a `w:sdt`** stays as read and starts no
  section, and neither does a `w:sectPr` between the body's blocks (test:
  `test/docx/model/sections_test.dart`, "a sectPr in a cell or a content control
  starts no section", "a mid-body sectPr stays an opaque block and starts no
  section"). Its references are still kept, and a new part's id avoids them.
- **Fields across paragraphs stay runs**, as the `TOC` of `long.docx` does:
  their marks are typed run content, and `resultText` and the rest of
  `DocxField` are out of reach (test: `test/docx/owner_files_test.dart`, "long.docx
  keeps its TOC as runs, its PAGEREFs in hyperlinks").
- **`w:fldSimple` is opaque.** It gives its visible text, and can be removed,
  not changed (test: `test/docx/model/body_model_test.dart`, "fldSimple
  contributes its runs").
- **A `w:fldChar` inside `mc:AlternateContent`** in a result run is not seen:
  the model takes that run for plain content, so the field around it is typed
  and the mark inside the opaque content pairs with nothing (test:
  `test/docx/model/fields_read_test.dart`, "a w:fldChar in mc:AlternateContent
  of a result run is not seen").
- **A field nested in an instruction begun in an earlier paragraph** is typed:
  the grouping pass looks at one paragraph, which cannot show that the field
  lies in an instruction. It reads and saves as read; only its meaning is the
  outer field's (test: `test/docx/model/fields_read_test.dart`, "a field in an
  instruction begun earlier is typed, as read").
- **`DocxField.resultText` drops what the old result held**, bookmark and
  comment marks too, so a mark whose partner lies outside the result is left
  alone in the file (test: `test/docx/model/fields_edit_test.dart`, "a nested
  field in the result goes with the old result").
- **A read `r:id` moved between parts of one document** stays as read,
  unreported. Ids are per part, so a hyperlink or a picture moved from the body
  to a header, or the other way, can name nothing there or something else, and
  Word may repair the file. The same holds between documents (`insertBlock`'s
  dartdoc). A section break cannot go in a story at all (test:
  `test/docx/model/header_footer_read_test.dart`, "a paragraph with a section
  break cannot go in a story").
- **Text directly in a final `w:sectPr`** is dropped on an edit of that section,
  as stray text in a `w:pPr` is. A file that is not edited keeps it (test:
  `test/docx/model/sections_test.dart`, "stray text in a final w:sectPr is
  dropped when it is edited").
- **A settings root that binds WordprocessingML only as the default namespace**
  cannot take `w:evenAndOddHeaders`: setting it, or adding an even story,
  throws `DocxReadException` naming the part, and the part stays as read (test:
  `test/docx/settings_part_test.dart`, "a root that binds WordprocessingML only
  by default cannot take it").
- **`addSection` does not copy a page numbering the model cannot type**: a
  `w:pgNumType` of a format it lacks is left out whole, not only its start (test:
  `test/docx/model/sections_test.dart`, "a page numbering the model cannot type
  is not copied").
- **Filling a first or even story's empty paragraph in place turns nothing
  on.** Only a block added to the story does, or `ownHeader` and `ownFooter`;
  otherwise set `titlePage` or `evenAndOddHeaders` yourself (test:
  `test/docx/model/header_footer_edit_test.dart`, "a story of empty paragraphs
  has no content yet").
- **A first story shows only with a title page of its own.** A later section
  that inherits one does not get `titlePage`, as it is per section (test: same
  file, "a section that inherits the story keeps its own titlePage").
- **The model does not lay out.** `DATE` and `TIME` built with no `result` have
  an empty result until Word opens the file, and a document read by anything
  that does not compute fields shows nothing there.

### Known gaps of D5

- **A round trip of a file with a parsed relationships part may change the
  ZIP entry order, not the parts.** Loading the body parses the main part's
  relationships, and the package writes a relationships part the load parsed
  after those it never parsed, such as a header's or footer's (the order of
  `writeTo`, older than D5). So the round trips of `d5_pictures` and
  `d5_links` hold the same parts with the same bytes in another ZIP order;
  `docs/word-checks.md` says so. Two saves of one model still give the same
  bytes.
- **`OfficeProperties.copyWith` (added in D6, closing this gap).** Setting
  `properties` to a value built from scratch removes every field it leaves null
  (the creator, the dates, the revision, the application of a Word file), as
  "sets to value" says; a caller changing one field uses
  `properties.copyWith(...)`, which keeps every field it is not given. A
  `null` argument keeps the field, so clearing one stays the constructor's job.
- **A read hyperlink or picture moved to another part or document keeps its
  `r:id` as read** (Ruling 13), as an opaque one did. Its `url` or `image`
  still reads the target in the relationships of the part it was read from
  (ledger Ruling G), and the resolver it holds keeps the source document
  alive. A built one, not yet saved, works anywhere, since its relationship is
  made at save (test: `test/docx/model/hyperlinks_read_test.dart`, "a link
  moved to another document edits and resolves there";
  `test/docx/model/hyperlinks_edit_test.dart`, "a built link works in a second
  document after a save"; `test/docx/model/pictures_edit_test.dart`, "a built
  picture works in a second document").
- **The style of a link built in a paragraph of no document** is the id
  `Hyperlink` until the paragraph goes in; then it resolves by id first, where
  a link built in a document finds the style by name through `ensureStyle`.
  The two differ only in a file whose style of id `Hyperlink` has another
  name (test: `test/docx/model/hyperlinks_edit_test.dart`, group "a link built
  in a paragraph of no document").
- **An empty styles part stays after save, undo, save.** In a document with
  no styles part, a link added and saved creates the part and its
  relationship; an undo and a second save keep that part, as D4's created
  parts stay (D4 Ruling 7; a pre-existing behaviour of D2 and D4).
- **One unreadable media part blocks every new picture.** The media index
  reads every media part of the package on the first new picture, to share
  equal bytes, so a media part that cannot be read makes each save with a new
  picture throw `DocxReadException` naming the main part. The index keeps the
  bytes it read in memory while the document lives.
- **A `pic:pic` whose `pic:cNvPr` id is missing or not a number** makes the
  drawing opaque, not a typed picture (ledger Ruling K): one reader serves
  pictures (test: `test/docx/model/pictures_read_test.dart`, "anchors, charts
  and several graphics stay opaque").
- **Setting a property held by a part whose root is not a properties part**
  throws `DocxReadException` (`malformedXml`) naming the part in a document,
  where a workbook throws `StateError`, as its dartdoc said before D5 (ledger
  Ruling P; tests: `test/docx/document_properties_test.dart`, "a part whose
  root is not a properties part throws a read exception naming it when a
  value of it is set"; `test/xlsx/model/properties_test.dart`, "a part with
  another root reads as nothing and is kept").
- **Built ids are not stored back.** Bookmark ids, `wp:docPr` ids, default
  picture names and relationship ids are allocated per save (ledger Ruling
  A): a built bookmark's `id` reads `null`, a built picture's `name` reads
  `''` without one given, and two saves may number them differently only when
  the model changed between them (test: `test/docx/model/bookmarks_test.dart`,
  "a start and an end in the next paragraph share one id";
  `test/docx/model/hyperlinks_edit_test.dart`, "saving twice gives the same
  file and stores no id").
- **Not typed (Ruling 15):** floating pictures, `w:fldSimple`, a hyperlink's
  `w:tgtFrame`, `w:history` and `w:docLocation` (kept as read), charts and
  `w14:paraId`. A read picture or a read link's target cannot be changed in
  D5; a read picture is removed with its run.

### Known gaps of D6

- **The helper adds nothing up and measures nothing.** `totals` are the
  caller's values; a column without a `widthPt` takes an equal share of the
  width that is left, since a pure-Dart library has no font metrics, so a long
  text wraps rather than widening its column.
- **The header's date is fixed text.** It shows the day the caller gave, not
  the day the file is opened (a deliberate choice, owner decision O2); a caller
  who wants Word's own date changes the header's paragraph after the export.
- **A list goes in the last section only and replaces what it shows.**
  `writeTo` sets the last section's page, header and footer (the even ones too
  with odd and even headers), and one column. A cover or a letter before the
  list is the caller's, through `addSection`. The first-page stories are left
  alone. A section with a title page has it turned off, so that its first page
  shows the list's header (test: `test/docx/list_export_test.dart`, "a title
  page is turned off so page 1 shows the header").
- **No header written leaves an inherited one.** With no logo, title or date,
  the section's own default header is removed and none is made, so the section
  may still show an earlier section's header (test: "with nothing for the
  header the section's own is dropped").
- **The rows are held as text for the call.** `writeTo` reads `rows` once and
  turns every row into its cell texts before the document changes, so a row
  longer than the columns or with a value of an unsupported type throws with
  the document as it was (test: "a bad row is named and the document does not
  change"). The price is that a very long list is held as strings for the
  time of the call, as well as in the document afterwards. The one error that
  can still come after the document changed is the `DocxReadException` of a
  header or footer part of an opened file that cannot be read.
- **Widths given in full are not held to the page.** When every column has a
  `widthPt`, they are written as given, even past the margins (test: "every
  width given is written as given, even past the page").
- **The benchmark document is scaled, not a real large file.** The owner had no
  Word file of 100 pages or more, so `docx_model_benchmark_test.dart` repeats
  the markup of `long.docx` (bookmark ids and `_Toc` names made unique per copy;
  `wp:docPr` ids and `_Ref` names repeat, which the model does not check). Its
  figures show the order of magnitude of a long document's cost, not of a
  particular one.

### Known gaps of T1

- **Sections, repeats and conditions come in T2.** `{{#x}}`, `{{^x}}`, `{{/x}}`
  are warned and left, and a table row is not repeated. There is no limit
  option in T1 (the copy limit belongs to T2's repeats); a fill is linear in
  the document.
- **Pictures come in T3.** An `OfficeImage` in a value tag is accepted by the
  validation, leaves the tag and warns `templateValueNotText`. An anchored
  (floating) picture is no placeholder either.
- **Content controls, tracked changes, text boxes, notes are not filled.** A
  tag in a block or inline content control, in a tracked insertion (the fill
  cannot put a value in a `w:ins` run without writing a revision), across a tab,
  in a `PAGE` result, in a text box (also one inside a `w:ins` or an inline
  `w:sdt`), a footnote, an endnote or a comments part is found, warned
  (`templatePlaceholderInRevision`, `templatePlaceholderInContentControl`,
  `templatePlaceholderNotTyped`) and left. A `MERGEFIELD` inside another field
  (an `IF`) is not filled (`templateFieldNotTyped`).
- **`\@` minutes and months share a letter in the Excel code.** Word's `M` is
  a month and its `m` a minute, but both become `m` in the Excel code the
  number format engine reads, and the engine tells them apart by their
  neighbours, as Excel does (after an hour or before a second, a minute). A
  picture that puts a Word minute or month where Excel would read the other
  (an `m` apart from `h` and `s`) shows the other. A meridiem inside quoted text
  is counted when the picture is checked, and `am/pm` loses its case. A picture
  that cannot be translated warns `templateSwitchUnsupported` and fills with the
  value's default form. `\* FirstCap` upper-cases the first character, not the
  first letter after leading punctuation. A surrogate pair in a `\#` picture may
  be split.
- **Very deep data.** Data nested deeper than the Dart stack allows throws a
  `StackOverflowError`, not an `ArgumentError`.
- **A `w:ins` holding a `w:p` directly** (Word never writes it) may report a
  tag twice; no test covers that edge.
- **A relationship with no `Id` is dropped silently when stories load.** This
  predates T1: it is in the model's loading of headers and footers, found by
  the T1 fuzz, and is not changed here; it is reported to the owner.
- **The tag's formatting is the first character's.** A value takes the
  formatting of the first run of its tag, not of its last or of the text
  before it; a tag whose first run is bold gives a bold value.

## Rules the model enforces

A file the model cannot read at all throws a `DocxReadException` with a
`reason`. Data that had to be repaired is a `DocxWarning`. A programmer error
(a limit below 1, an index out of range, a block put in two bodies, an empty
style id) throws `ArgumentError`, `RangeError` or `StateError`. Nothing is
dropped silently.

### The file and the package

| Case | Behaviour | Why | Test |
|---|---|---|---|
| A limit in `DocxReadLimits` below 1 | `ArgumentError` naming the field, when the document opens | a zero limit is a bug in the caller | `test/docx/docx_package_test.dart`, `test/docx/docx_document_test.dart` |
| Default limits | the XLSX reader's: `maxEntries` 10,000; `maxEntryBytes` 256 MiB; `maxTotalBytes` 1 GiB; `maxCompressionRatio` 1,000; `maxDepth` 256; `maxTextLength` 1,048,576 characters | both formats refuse the same archive the same way | `test/docx/docx_package_test.dart` |
| More entries than `maxEntries`; an entry past `maxEntryBytes`; entries past `maxTotalBytes`; a ratio past `maxCompressionRatio` | `limitExceeded` naming the limit, before anything is inflated | ZIP bomb | `test/docx/docx_package_test.dart` ("limits") |
| XML nested past `maxDepth` | `limitExceeded` naming `maxDepth` and the part | stack and memory | `test/docx/docx_package_test.dart` ("limits") |
| A `w:t` longer than `maxTextLength`, or an opaque inline whose visible text is | `limitExceeded` naming the limit and the paragraph as `body/p[i]`, `i` its zero-based index among the body's paragraphs (as in a warning's location: a table or content control before it does not count), or, in a table, as `body/tbl[i]/tr[j]/tc[k]/p[m]` (see "Tables"), on the first access to `body`; deleted text does not count | one text must not be as large as the file | `test/docx/docx_package_test.dart`, `test/docx/document_part_read_test.dart` ("maxTextLength"), `test/docx/docx_document_test.dart` |
| Bytes that are not a ZIP; a ZIP with a damaged directory | `notZip`; `corruptZip` | tell a wrong upload from a damaged one | `test/docx/docx_package_test.dart`, `test/docx/docx_document_test.dart` |
| An entry whose CRC-32 does not match, or a damaged entry of a part never loaded | `corruptZip` naming the entry, at `open`, so a save cannot meet it | every entry is inflated once and checked when the document opens | `test/docx/docx_package_test.dart`, `test/docx/docx_document_test.dart` |
| An encrypted ZIP entry, or an OLE file holding `EncryptedPackage` | `encrypted` | the model has no password | `test/docx/docx_package_test.dart` |
| Any other OLE compound file | `legacyDoc` | the binary `.doc` format | `test/docx/docx_package_test.dart` |
| A Strict OOXML document | `unsupportedFormat` | Strict uses other namespaces; reading it as empty would be silent | `test/docx/docx_package_test.dart` |
| A package whose main part is a workbook, or a presentation | `unsupportedFormat` naming XLSX, or PPTX | a wrong upload, said so | `test/docx/docx_package_test.dart` |
| No main document part, or a root relationship whose target is missing | `missingDocument` (naming the part in the second case) | nothing to read | `test/docx/docx_package_test.dart`, `test/docx/docx_document_test.dart` |
| Finding the main part | through the root relationship, wherever it lives; the four Word types (`.docx`, `.docm`, `.dotx`, `.dotm`) are read, and a macro-enabled kind keeps its content type | real producers do not always write `word/document.xml` | `test/docx/docx_package_test.dart` |
| A main part with no content type | read as a Word document, with a `contentTypeMissing` warning | Google Docs and other tools omit it | `test/docx/docx_package_test.dart`, `test/docx/producer_variants_test.dart` |
| A main part with another content type that is not a workbook or presentation | read as a Word document, with a `mainPartContentTypeUnexpected` warning naming the type | the file may still be a document | `test/docx/docx_package_test.dart` |
| A `DOCTYPE` | `malformedXml` naming the part | entity expansion and external entities | `test/docx/docx_package_test.dart` |
| Malformed XML in the main part or its relationships, found when the body first loads | `DocxReadException` (never `OpcFormatException`); nothing is loaded, so a save copies the part as it was | the typed exception is the contract | `test/docx/docx_package_test.dart`, `test/docx/docx_document_test.dart` ("failures"), `test/docx/document_part_read_test.dart` |
| A root that is not `w:document` | `malformedXml` | a wrong root must not read as an empty document | `test/docx/document_part_read_test.dart` |
| A part name or an XML detail quoted in a message | cut, cleaned of control and bidi characters, and rooted with `/` | a hostile file must not spread a message over a log | `test/docx/docx_package_test.dart` |
| A failure message | never advises `.xls`, `.xlsx` or Excel | the user is opening a Word document | `test/docx/docx_package_test.dart` |
| Mutated and random files | only `DocxReadException`, never another exception | the typed exception is the contract | `test/docx/fuzz_test.dart` |

### Reading the body

| Case | Behaviour | Why | Test |
|---|---|---|---|
| Elements | matched by namespace URI and local name, never by prefix: `ns0:`, a default namespace and `w:` read the same; an element in another namespace with a `w` local name is not typed | a producer may choose any prefix | `test/docx/document_part_read_test.dart`, `test/docx/producer_variants_test.dart` |
| `w:p`, its runs, text, tabs, breaks and carriage returns | typed in place | the model's job in D1 | `test/docx/document_part_read_test.dart` |
| A `w:br` of type `textWrapping` | read as a line break, and its type is kept | the type is the file's | `test/docx/document_part_read_test.dart` |
| A table | a `DocxTable`, in place, typed (see "Tables") | D3 | `test/docx/document_part_read_test.dart` ("tables are typed and sdt blocks are opaque blocks, in place") |
| A content control, a bookmark or any other block | an opaque block, in place (a bookmark between blocks too: D5 types those in a paragraph) | never typed as a block | `test/docx/document_part_read_test.dart`, `test/docx/model/body_model_test.dart` |
| The final `w:sectPr` of the body | held by the body as its last section (see "Sections"); a `w:sectPr` in a paragraph's `w:pPr` is that paragraph's break; one that is not the last child of the body is a block | the last section belongs to the body | `test/docx/document_part_read_test.dart`, `test/docx/model/sections_test.dart` |
| A `w:hyperlink`, `w:bookmarkStart` or `w:bookmarkEnd` child of a paragraph | `DocxHyperlink`, `DocxBookmarkStart`, `DocxBookmarkEnd` (see "Hyperlinks" and "Bookmarks") | D5 Rulings 8 and 10 | `test/docx/model/hyperlinks_read_test.dart`, `test/docx/model/bookmarks_test.dart` |
| Any other child of a paragraph (tracked change, content control, smart tag, proofing mark) | an opaque inline, in place, with its visible text computed once | kept as written | `test/docx/document_part_read_test.dart`, `test/docx/model/body_model_test.dart` |
| A `w:drawing` of one inline picture | `DocxPicture` (see "Pictures") | D5 Ruling 5 | `test/docx/model/pictures_read_test.dart` |
| Any other child of a run (another drawing, `w:delInstrText`, a `w:fldChar` of no known type, `mc:AlternateContent`) | opaque run content, in place; it adds nothing to the run's text | kept as written | `test/docx/document_part_read_test.dart`, `test/docx/model/fields_read_test.dart` |
| `w:fldChar` and `w:instrText` in a run | `DocxFieldMark` and `DocxFieldInstruction`, keeping the element as read; no text | D4 Ruling 3 | `test/docx/model/fields_read_test.dart` |
| A complex field of one paragraph's direct runs, each mark alone in its run, only `w:instrText` runs and inlines holding no run in the instruction | one `DocxField`; a field in a result is a `DocxField` of it; a run keeps the location it had when read, and a field writes its inlines in order, as read | D4 Ruling 2 | `test/docx/model/fields_read_test.dart` |
| A `w:fldSimple` | an opaque inline; its visible text counts | D4 Ruling 1: an opaque inline already gives its text | `test/docx/model/body_model_test.dart` ("fldSimple contributes its runs") |
| Any other field: a mark with no partner or in an inline of its own, a field across paragraphs or in an instruction, two `separate`s, `w:instrText` in a result, two marks or more than a mark in a run, an unknown `w:fldChar` | stays runs, with the paragraph's text as before, and saves as read; a mark inside a run breaks every field open around it | D4 Ruling 2 | `test/docx/model/fields_read_test.dart`, `test/docx/owner_files_test.dart` |
| Fields nested past `maxFieldNesting` (32) in a result | the deeper ones stay runs in the result | a paragraph's fields nest without nesting in the XML, so `maxDepth` does not bound them and the model recurses | `test/docx/model/fields_read_test.dart` |
| A `w:instrText` past `maxTextLength` | `limitExceeded`, as a `w:t` | the same bound for all text; entities in it are decoded, also inside opaque inlines | `test/docx/model/fields_read_test.dart` ("an instruction past maxTextLength is refused") |
| `DocxField.name` | the first word of the instruction in upper case, stopping at a backslash; `null` without one | what Word shows as the field's kind | `test/docx/model/fields_read_test.dart`, `test/docx/model/fields_edit_test.dart` ("name stops at a backslash") |
| `DocxField(instruction, {result})` and `.page()`, `.numPages()`, `.sectionPages()`, `.date()`, `.time()` | a field of real runs, written `begin`, `w:instrText xml:space="preserve"`, `separate`, the result run (`1` for the page fields; `date` and `time` write the `result` argument, empty by default), `end`; no `w:dirty`, no `w:updateFields` | D4 Ruling 4: the library has no clock, and Word computes the fields | `test/docx/model/fields_edit_test.dart` |
| An empty or blank instruction (once forbidden characters are removed), a `date` or `time` format holding `"` | `ArgumentError`, before anything changes | programmer error | `test/docx/model/fields_edit_test.dart` |
| Forbidden characters in an instruction or a result | removed, counted on the run, and reported at save with `invalidCharactersRemoved` at that run | as a run's text | `test/docx/model/fields_edit_test.dart` |
| `DocxField.instruction` set | the first instruction run keeps its `w:rPr` and takes the text, the other instruction runs go, inlines between them stay; a field with none gets a run after `begin`; one change | keeps what the file formatted | `test/docx/model/fields_edit_test.dart` |
| `DocxField.resultText` set | the first result run keeps its `w:rPr` and takes the text, every other inline of the old result goes (a nested field with it); a field with no `separate` gets one; one change | as above | `test/docx/model/fields_edit_test.dart` |
| `DocxField.properties` set | applied to every run of the field, nested fields' included, in one transaction; a read reads the first run's | a field is formatted as a whole | `test/docx/model/fields_edit_test.dart` |
| A `DocxField` inserted while it is in a paragraph | `StateError`, as an inline | one parent | `test/docx/model/fields_edit_test.dart` |
| Every child of `w:pPr` and `w:rPr` | kept as written; a typed one (in D1 the style) also gives a view, its value, and is written as read until it is set | a read file saves as it was (plan Ruling 2) | `test/docx/properties_test.dart` |
| `pStyle` or `rStyle` that is not one non-empty `w:val` with no other `w:` attribute, no child element and no text, or that occurs twice | not typed (the style reads as `null`); written back as it was | not a style id the model can set without losing something | `test/docx/document_part_write_test.dart` ("kept styles"), `test/docx/property_codec_test.dart` |
| A paragraph or run whose style element is not typed | its `style` reads `null`, although the file names a style element; setting `style` to another id replaces every `pStyle` or `rStyle` of the container, while setting it to what it reads (`null` included) changes nothing, so `x.style = x.style` never deletes a child the model does not type; `clear` removes them | one style per container | `test/docx/document_part_write_test.dart` ("kept styles"), `test/docx/properties_test.dart` |
| `pStyle` or `rStyle` with an attribute in another namespace (`w14:`) | typed; written as read, attribute included, until the style is set | attributes in other namespaces are ignored for typing (plan Ruling 2) | `test/docx/document_part_write_test.dart` ("kept styles") |
| Unknown attributes on `w:body`, `w:p`, `w:r`, `w:t`, `w:tab`, `w:br`, `w:cr` (`w14:paraId`, rsids) | kept | Word's identifiers survive a save | `test/docx/document_part_read_test.dart` |
| A `w:t` whose text is split by entities or CDATA | one text | the XML parser's job, not the file's | `test/docx/document_part_read_test.dart`, `test/docx/model/body_model_test.dart` |
| A whitespace-only `w:t` with `xml:space="preserve"` | kept | the space is text | `test/docx/document_part_read_test.dart` |
| Content before and after `w:body`, and a document with no body | kept in order; no body gives no blocks and none is written | nothing is invented | `test/docx/document_part_read_test.dart`, `test/docx/document_part_write_test.dart` |

### The visible text of an opaque inline

The text of a paragraph is the text of its runs and the visible text of its
opaque inlines, in order.

| Case | Behaviour | Why | Test |
|---|---|---|---|
| `w:ins`, `w:moveTo`, `w:hyperlink` (one inside an opaque inline; a typed one gives its inlines' text), `w:smartTag`, `w:customXml`, `w:fldSimple`, nested | contribute the text of their runs, in order | what a reader sees | `test/docx/model/body_model_test.dart` ("visible text of an opaque inline") |
| `w:sdt` | contributes `w:sdtContent` only, never the placeholder in `w:sdtPr` | the properties are not content | `test/docx/model/body_model_test.dart` |
| `w:del`, `w:moveFrom`, and anything inside them (also within `w:ins` or `w:hyperlink`); `w:delText` and `w:delInstrText` outside a deletion | contribute nothing | deleted text is not shown | `test/docx/model/body_model_test.dart` |
| `w:instrText`, drawings, and elements in another namespace | contribute nothing | not text | `test/docx/model/body_model_test.dart` |
| `mc:AlternateContent` and text-box text | contribute `''` (a known gap) | not read in D1 | `test/docx/document_part_read_test.dart` |
| The slice's depth | parsed under the part's own `maxDepth`, once, when the inline is built; a bad entity or too deep a slice is a `DocxReadException` | an opaque node is bounded before it is kept | `test/docx/document_part_read_test.dart` ("through DocxPackage.guard") |

### Text set through the API

| Case | Behaviour | Why | Test |
|---|---|---|---|
| `\t` in a run's text | a tab | Word has a tab element | `test/docx/model/body_model_test.dart` ("run text"), `test/docx/document_part_write_test.dart` |
| `\n`, a lone `\r`, `\r\n` | one line break each (`\r\n` is one) | the three spellings of a line end | `test/docx/model/body_model_test.dart`, `test/docx/document_part_write_test.dart` |
| Characters XML forbids (control characters, `U+FFFE`, `U+FFFF`, lone surrogates) | removed when the text is set and counted; a supplementary character is kept | the one XML escaper (decision 0010) | `test/docx/model/body_model_test.dart` |
| Removed characters | one `invalidCharactersRemoved` warning per part, reported at save with a location such as `body/p[5]/r[0]` (`p[i]` counts paragraphs only, `r[j]` runs only; a path to another block would be `body/<localName>[i]`, indexed among blocks of that local name, and one inside a table is the path given under "Tables"); the count is the characters removed, and the location list ends with `…` only when more than ten runs lost characters; a run removed before the save, or a second save, does not add to it | the warning describes the file saved, not the edits made | `test/docx/document_part_write_test.dart` ("warnings at save"), `test/docx/warnings_test.dart` |
| `xml:space="preserve"` | computed only for text set through the API: when it starts or ends with whitespace or holds two spaces in a row; a text read from a file keeps its own attribute | a reader must not collapse what the caller set, and a file's attribute is its own | `test/docx/document_part_write_test.dart` |
| A run's text set to the text it has | nothing is recorded and a read run keeps its read content | an unchanged value is not a change | `test/docx/model/body_model_test.dart` ("edit sink") |
| `text` of a paragraph | the texts of its inlines joined | what Word shows | `test/docx/model/body_model_test.dart` |
| A style id that is empty, or has characters XML forbids | `ArgumentError` | a programmer error | `test/docx/model/body_model_test.dart` ("style") |
| A warning | one per part and code, with a count and at most ten locations, and a message in `en`, `de` and `tr` | 100,000 dirty runs are one warning | `test/docx/warnings_test.dart`, `test/architecture/warning_messages_test.dart` |

### Properties

Typing and writing. The container (`w:pPr`, `w:rPr`, and the property
containers of styles, defaults and numbering levels) keeps every child as
read; a typed property is a view of a child.

| Case | Behaviour | Why | Test |
|---|---|---|---|
| The order of the children of `w:pPr`, `w:rPr` and of every container the model writes (`w:style`, `w:docDefaults`, `w:lvl`, `w:abstractNum`, `w:num`, `w:lvlOverride`, `w:numPr`, `w:pBdr`, `w:numbering`, `w:styles`) | the schema's (ECMA-376 transitional `wml.xsd`), with no name twice | Word repairs a document whose property children are out of order | `test/docx/schema_order_test.dart` ("styleOrder matches the transitional schema" and its siblings), `test/docx/container_order_test.dart` ("values set in reverse order are written in table order") |
| A child is typed (its view is not `null`) | only when it is in `w:`, occurs once, and every `w:` attribute on it is one the model understands and parses in range; attributes in other namespaces are ignored for typing | a view must be exactly what Word would read | `test/docx/properties_test.dart` ("a typed child with an unknown w attribute has no view", "a typed child with a w14 attribute has its view", "a child occurring twice has no view and both are written", "a child of another namespace is never typed") |
| A child that is not typed | its view is `null` and it is written as read: no warning, since nothing was repaired. `w:b w:val="on"` reads `true`; `w:sz w:val="1in"`, `w:sz w:val="abc"`, a twenty-digit number, `w:b w:val="maybe"`, `w:color w:val="red"`, `w:jc w:val="lowKashida"` read `null` | a read file saves as it was; the reading API is narrower than Word, the file is never wrong | `test/docx/model/run_properties_test.dart` ("sz abc, sz of twenty digits, b maybe and two w:b read null and save unchanged", "b on reads true and survives until bold is set"), `test/docx/model/paragraph_properties_test.dart` ("jc start reads start, jc lowKashida reads null and saves unchanged", "ind left 1in and leftChars read null and save unchanged") |
| Setting a property | replaces every child of that name with the canonical element, at its slot in schema order; setting `null` removes them (when the view is not `null`), but for what the row on other scripts keeps | one element per name | `test/docx/properties_test.dart` ("setting replaces every child of that name at its slot", "setting null removes them"), `test/docx/model/run_properties_test.dart` ("a member set to null is removed") |
| Setting the value the view already has, `null` included | nothing: no change is recorded and an untyped child stays, so `x.style = x.style` never deletes what Word accepts | copying formatting must not lose a child the model does not type | `test/docx/model/run_properties_test.dart` and `test/docx/model/paragraph_properties_test.dart` ("setting a value equal to the current one records nothing") |
| Removing an untyped child | `clear` on the properties object (`clear<Property>()` or `clear(name)`) removes the child, typed or not | the explicit way to drop what setting `null` keeps | `test/docx/model/run_properties_test.dart` ("clear removes an untyped child that setting null keeps", "clear removes a typed child too"), `test/docx/model/paragraph_properties_test.dart` |
| What a set keeps of Word's other scripts | `fonts` replaces `@ascii`, `@hAnsi`, `@eastAsia` and their theme attributes and keeps `@cs`, `@cstheme`, `@hint` and others; `language` replaces `w:lang/@w:val` and keeps `@eastAsia` and `@bidi`; `bold` writes `w:b` only, `sizePt` `w:sz` only. `fonts = null`, `language = null` and a level's `bulletFont = null` remove what they type and keep the element while another attribute remains (`clear` removes it); the three are the only typed attribute groups a set keeps part of | complex-script formatting is a non-goal (spec §2); its attributes must survive | `test/docx/model/run_properties_test.dart` ("setting fonts keeps cs, cstheme and hint and drops asciiTheme", "setting language keeps eastAsia and bidi", "setting bold keeps bCs, setting sizePt keeps szCs", group "removing a typed attribute group"), `test/docx/model/numbering_test.dart` ("bulletFont = null keeps the other attributes of w:rFonts, and clear removes the element") |
| One set on a Word file's run or paragraph | every other child (`w14:ligatures`, `w:kern`, `w:szCs`, `w:lang/@eastAsia`, a `w:rPr` of the paragraph mark, `w:sectPr`) stays in place and in schema order | only the property set changes | `test/docx/model/run_properties_test.dart` ("a w14:ligatures child stays after kern when bold is set"), `test/docx/model/paragraph_properties_test.dart` ("setting alignment keeps pPr/rPr and sectPr in place", "w14 and kept children stay in place when one is set", "typed tabs and pBdr a neighbour set leaves stay byte for byte") |
| A kept child (`w14:`, `w15:` and others) | stays after its predecessor in the file; with no typed predecessor it follows the one before it, and with none it is written first; matched by namespace URI, not prefix; a declaration it needs is written on it | its place survives an edit | `test/docx/properties_test.dart` ("a kept w14 child stays after its predecessor", "a kept child whose typed predecessor is gone follows the one before it", "a kept child with no predecessor is written first", "a kept child declares a namespace the new parent lacks") |
| A `w:pPr` or `w:rPr` holding only whitespace, an empty one, or its own attributes | written back as it was until a child is set | a read file saves as it was | `test/docx/properties_test.dart` ("an empty container element reads and writes", "attributes of the container are kept") |
| A `w:pPr` or `w:rPr` that rebinds the `w` prefix | children set are written with a prefix bound to WordprocessingML (one the container has, or a new `w1`) | the output means what was set | `test/docx/properties_test.dart` ("a pPr that redeclares the w prefix writes typed children with a bound prefix") |
| Comments between the children of a properties container that has children | kept while the part goes out as read (a main part with no edit in the document, a styles or numbering part that writes what it wrote when read); dropped once the part is written from the model, in every container of it | the model keeps children, not comments | `test/docx/model/run_properties_test.dart` ("a comment between the children of a w:rPr stays while the part has no edit", "a comment between the children of a w:rPr is dropped by an edit of the part", on the raw bytes, because `comparePackages` ignores comments) |
| Known limit: children out of schema order in a part with an edit | once a part is written from the model, every container in it goes to schema order, not only the one edited: a `w:pPr` of `w:jc` then `w:keepNext` elsewhere in the part comes out `w:keepNext` then `w:jc`. No child is lost. "A part with an edit" is, for the main part, a document with any edit (one change log serves all parts, so a style edit counts); for a styles or numbering part, one whose model writes something new. Not fixed in D2 | D1 made schema order deliberate, and Word never writes such a file; the cost is diff noise | `test/docx/docx_document_test.dart` ("a real edit writes the part from the model", "an edit of the styles counts too: the log is the document's") |
| A typed child outside the order list | a programmer error | the list is the contract | `test/docx/properties_test.dart` ("a typed child outside the order is a programmer error") |
| The exported properties classes | have only the typed members: no `setValue`, `restore` or `source` | a setter must check before anything changes | `test/docx/public_surface_test.dart` |

Values and units.

| Case | Behaviour | Why | Test |
|---|---|---|---|
| Lengths | points at the API (`sizePt`, border `widthPt` and `spacePt`, `leftPt`, `beforePt`, …), the file's unit in the file: half-points for the size, eighths of a point for a border width, twips for the rest | the spec's `…Pt` naming | `test/docx/model/run_properties_test.dart` ("sizePt sets and reads back"), `test/docx/model/paragraph_properties_test.dart` ("indentation sets and reads back") |
| Rounding | a set value is rounded to the file's unit (half away from zero) and reads back rounded; values compare equal by stored units, so `DocxLineSpacing.multiple(1.16)` equals one read as `w:line="278"` | one value, one spelling | `test/docx/model/formatting_test.dart` ("round half away from zero to the file unit", "values are equal by their stored units"), `test/docx/model/run_properties_test.dart` ("sizePt 11.3 reads back 11.5"), `test/docx/model/paragraph_properties_test.dart` ("values compare by stored units") |
| A value that is not finite | `ArgumentError`; one out of range after rounding `RangeError`. Ranges: size 1 to 1638 pt; indentation left and right −1584 to 1584 pt, first line and hanging 0 to 1584 pt; spacing before and after 0 to 1584 pt; line exactly or at least 0 to 1584 pt, multiple over 0 to 132 lines; tab position and character spacing −1584 to 1584 pt; border width 0.25 to 12 pt, space 0 to 31 pt; outline level 0 to 9; list level 0 to 8; theme tint and shade 0 to 255; RGB six hex digits | a programmer error throws before anything changes | `test/docx/model/formatting_test.dart` ("NaN and infinity throw ArgumentError, out of range RangeError"), `test/docx/model/run_properties_test.dart` ("sizePt 0.5 and 1638.5 throw RangeError"), `test/docx/model/paragraph_properties_test.dart` ("line multiple 133 throws RangeError", "level 9 throws RangeError"), `test/docx/model/formatting_test.dart` ("theme tint 256 throws RangeError") |
| A number read from a file | typed only with at most nine digits after an optional `-`, so the VM and Chrome agree: `024` reads 24, `+24`, `1in`, `12.5` and ten digits read `null` | `int.tryParse` must agree on every platform | `test/docx/property_codec_test.dart` ("parseDecimal refuses ten digits, a sign alone, a plus sign, 1in and 12.5", "parseDecimal of -999999999 and 999999999 is exact") |
| Colour | `DocxColor.rgb` (six hex digits, upper-cased), `.theme` with `tint` and `shade`, `DocxColor.auto`; a theme colour read from a file gives its theme and tint, not its fallback hex, which stays in the file | the theme part is not resolved | `test/docx/value_codecs_test.dart` ("color reads rgb, auto and theme with tint", "color FF00 and red have no view"), `test/docx/model/formatting_test.dart` ("rgb is upper-cased and FF00 throws ArgumentError") |
| A theme colour written | `w:val="auto"` beside `w:themeColor`, `w:themeTint` and `w:themeShade`. `w:val` is required by the schema and the Open XML SDK accepts `auto` there. A reader that ignores `themeColor` shows the colour as automatic | the resolved hex would need the theme part | `test/docx/value_codecs_test.dart` ("a color writes its attributes"), `test/docx/round_trip_test.dart` ("d2_run_formatting writes a theme colour with w:val="auto""); the SDK result is the `validate` job on `d2_run_formatting` |
| A border that is not drawn (`w:val` `nil` or `none`) | reads with the default width only when `w:sz` is absent or exactly `0` (Word writes `sz="0"` for nil lines); any other `sz` gives no view | Ruling: out-of-range stays untyped | `test/docx/value_codecs_test.dart` ("a border that is not drawn reads with the default width only when sz is absent or 0", "a border that is not drawn with another sz has no view") |
| An art border | no view; kept | a picture border has no typed spelling | `test/docx/value_codecs_test.dart` ("an art border has no view") |
| `w:u` without `w:val` | no underline view (`underline` reads `null`); the child is kept as written, and setting `underline` replaces it | the model needs a line style to give a view | `test/docx/model/run_properties_test.dart` ("w:u without w:val reads null, saves unchanged and is replaced by setting underline") |
| `numPr` without `w:ilvl` | reads level 0 | Word's default | `test/docx/model/paragraph_properties_test.dart` ("numPr without ilvl reads level 0") |
| An empty `tabs` list | removes `w:tabs` | no empty container is written | `test/docx/model/paragraph_properties_test.dart` ("an empty tabs list removes w:tabs and tab values range") |

### Styles

| Case | Behaviour | Why | Test |
|---|---|---|---|
| Recognizing a built-in | by `w:name` (English canonical name, ASCII case-insensitive), never by `w:styleId` and never by `w:outlineLvl`: Word derives the id from the localized name (`Başlık 1` is `Balk1`, German `Überschrift 1` is `berschrift1`) while the name stays `heading 1` | owner's `blank.docx` | `test/docx/model/style_resolution_test.dart` ("idOf finds Balk1 by its name heading 1", "idOf heading1 and heading2 are berschrift1 and berschrift2", "the style with outlineLvl 0 named Chapter is not heading 1", "idOf never matches by id"), `test/docx/style_resolution_owner_test.dart` |
| Two styles of one name | the first in document order | Word's own matching | `test/docx/model/style_resolution_test.dart` ("idOf takes the first style of the name in document order") |
| Setting a style id through the API (`p.style`, `r.style`, `properties.style`, `basedOn`, `next`, `link`) on content in a document, or inserting content whose style was set so | resolved against the document: (a) an id the document defines is kept; (b) otherwise the English id of a built-in of the right type becomes the id of the style the document has under that name, so `p.style = 'Heading1'` stores `Balk1` and no `Heading1` is added; (c) otherwise the built-in is added with Word's definition under its English id, its dependencies with it; (d) any other id is kept and reported at save | an English-writing caller works in a localized document | `test/docx/model/style_resolution_test.dart` ("p.style = Heading1 on an attached paragraph stores and reads Balk1", "a detached paragraph with style Title inserted gets KonuBal", "p.style = Heading2 keeps the defined custom Heading2", "an unknown id is kept and warns styleNotFound at its path on save") |
| An id of the wrong type | not a built-in of that use: kept as given, reported at save | a character style is not a paragraph style | `test/docx/model/style_resolution_test.dart` ("an id of the wrong type is not a built-in", "a character style set as a paragraph style warns styleNotFound") |
| Content read from a file | never resolved: a read `Heading3` stays `Heading3`, and a document that sets nothing does not load `styles.xml` | open and save changes nothing | `test/docx/model/style_resolution_test.dart` ("a read pStyle Heading3 is not resolved", "a read document that sets nothing does not load styles") |
| Content read in one document and put in another (`insertBlock`, `replaceBlockAt`, `insertInline`) | its typed `w:pStyle`, `w:numPr` and each run's `w:rStyle` count as set: resolved by id, and reported at save when the target lacks them. Moved within one document they stay unresolved. Nothing else is carried: the source style's `w:name` stays behind, so a built-in under a localized id does not map by name (it warns); a `numId` the target has too joins that list, unreported; a read opaque inline or block with an `r:id` keeps an id the target may lack; a reference the model does not type, or one in the paragraph mark's `w:rPr`, stays as read, unreported | a silent loss of a style is worse than a warning; carrying names and remapping ids are out of D2 | `test/docx/model/style_resolution_test.dart`, group "content read in one document and put in another" |
| Setting the id already in the view | returns before resolving or recording, so a dangling id read from a file set back stays dangling and unreported | Ruling 5: read values are never resolved | `test/docx/model/style_resolution_test.dart` ("setting the id a paragraph reads records nothing", "setting back a read id the document lacks adds nothing") |
| `DocxStyles.idOf` and `ensure` | by name (the rule above); `idOf` gives the existing id without adding, `ensure` adds when absent. `idOf` ignores the style type | one lookup by name | `test/docx/model/style_resolution_test.dart` ("ensure(heading1) returns Balk1 and adds nothing", "idOf gives null for a built-in the document lacks", "a character style named heading 1 is the id of the built-in, and a paragraph given it warns styleNotFound") |
| A built-in added | its `basedOn`, `next` and `link` map to the document's styles: `Normal`, `DefaultParagraphFont` and `TableNormal` to the default style of that type (`w:default="1"`), others by name; a missing dependency is added the same way (a linked `…Char` style included); the default style of a type is never replaced | no duplicate or parallel style | `test/docx/model/style_resolution_test.dart` ("ensure(header) adds Header basedOn Normal and HeaderChar linked both ways, and no name twice", "adding a built-in keeps the default of the file", "a dependency on Normal takes the default of the file") |
| An English id already taken by a style of another name | the smallest free suffix: `Heading2_1`, `Heading2_2`, … | no id or name is ever duplicated | `test/docx/model/style_resolution_test.dart` ("ensure(heading2) adds Heading2_1 named heading 2 beside My heading", "the suffix is the smallest one free") |
| The catalog | built by `default_styles.dart` with the values of `blank.docx` and `builtins.docx`, under the English ids and names, no rsids, no Turkish id or name | the definitions have Word's values (decision 0011) | `test/docx/builtin_styles_test.dart` ("every built-in has a definition of its type and name", "no definition carries an rsid or a Turkish id or name", "catalog entries in the blank document equal its styles"), `test/docx/builtin_styles_oracle_test.dart` ("definitions equal builtins.docx after mapping ids and names") |
| `DocxStyles.add` | applies the same rules to `basedOn`, `next` and `link` before validating; rejects a used id, a used name, an unknown `basedOn`, a `basedOn` of another type and a cycle; a `link` must name a style of the other type; writes `w:customStyle` and the children in schema order, appended after the last style | one style per id and name | `test/docx/model/styles_test.dart` ("add rejects a used id, a used name, an unknown basedOn, a basedOn of another type and a cycle", "add writes customStyle and the children in styleOrder", "a style is appended after the last w:style"), `test/docx/model/style_resolution_test.dart` ("a link takes a built-in of the other type", "a link to a style of the same type throws") |
| `DocxStyle.type`, `id` and `name` | read nullable: a file's style may lack them; a style without `w:type` is a paragraph style; the `name` setter throws `ArgumentError` on `null`, an empty name or a forbidden character | a file is never wrong | `test/docx/model/styles_test.dart` ("a style without w:type is a paragraph style, one of another type has none", "the constructor checks its arguments") |
| The styles part | loaded on first access; found through the main part's relationship wherever it lives; a document without one reads as having none | the package, not the name, says where a part is | `test/docx/styles_part_test.dart` ("the styles part is found by relationship wherever it lives", "accessing the empty styles and saving changes nothing") |
| A styles relationship | reused only when its target holds a styles part (the expected content type, or the generic XML type with no other relationship targeting it) and is not the main part; otherwise it stays as read and a new part is created at `/word/styles.xml`; an external relationship is ignored | a hostile file must not make the model overwrite its body | `test/docx/styles_part_test.dart` ("a styles relationship to $target, which holds no styles, is kept and a new styles part is created", "a missing target "$target" that is no legal part name is kept and the part goes to /word/styles.xml", "a generic XML part another relationship targets is not the styles part", "an external styles relationship is ignored") |
| A part is created at save, and only if it holds something | a document without `styles.xml` that now holds a style or document defaults gains `/word/styles.xml` with its content type override and one relationship from the main part; a second save adds nothing; a rolled-back edit leaves nothing | creating at save keeps package edits out of the change log | `test/docx/styles_part_test.dart` ("a document without styles.xml that gets a style gains the part, its override and one relationship", "a second save adds no second part", "document defaults alone create the part", "a style added then rolled back leaves no styles part") |
| A styles part loaded with no recorded change | saved with its original bytes (a CRLF or a comment survives), also after reading, after a set that adds nothing and after an edit rolled back or reverted | the fidelity standard (decision 0010) outranks "a loaded part is written from the model" | `test/docx/model/style_resolution_test.dart` ("a set that adds nothing keeps a comment under w:styles", "reading the styles keeps them", "an edit rolled back keeps them", "a set that changes nothing keeps them") |
| A styles part with a change | written from the model; only then are comments directly under `w:styles` dropped (and, in a container that has children, the comments between them) | the model does not keep comments of a part it rewrites | `test/docx/model/style_resolution_test.dart` ("a change is written from the model, and its revert is as read", "a default set is a change") |
| A broken `styles.xml` | a style set or insertion throws `DocxReadException` and is rolled back, naming the part; a save copies the part as it was | the set needs the part, and `DocxReadException` is the one exception file content may cause | `test/docx/model/style_resolution_test.dart` ("a set or an insertion throws, changes nothing, and the part is copied"), `test/docx/styles_part_test.dart` ("a malformed styles.xml throws DocxReadException naming the part on access") |
| Every style edit | one change in the change log that reverts and reapplies, `ensure` as one transaction; a style in no document records nothing | atomic edits | `test/docx/model/styles_test.dart` ("setting a style property is one change that reverts", "a style not in a document records nothing"), `test/docx/model/style_resolution_test.dart` ("ensure is one transaction: revert and reapply it whole") |
| Open, access the styles, save | semantically equal, for every fixture and for the owner's files | layer 2 of decision 0009 | `test/docx/styles_part_test.dart` ("open, access styles, save is semantically equal ($name)"), `test/docx/owner_files_test.dart` ("every owner file round-trips with its styles loaded") |

### Numbering

| Case | Behaviour | Why | Test |
|---|---|---|---|
| The numbering part | loaded on first access; found, created at save only when it holds a definition or an instance, and reused or kept by the same rules as the styles part; a document without one reads as empty | as for styles | `test/docx/numbering_part_test.dart` ("a document without numbering.xml that gets an instance gains the part, its override with ContentType.wmlNumbering and one relationship", "a second save adds nothing", "a rolled-back instance leaves no part", "a numbering relationship to "$target" is kept and a new /word/numbering.xml gets its own relationship", "styles and numbering relationships to the same missing target both survive a save and reopen") |
| A numbering part loaded with no recorded change | saved with its original bytes; a part with a change is written from the model, and only then are comments directly under `w:numbering`, `w:abstractNum` and `w:num` dropped | as for styles | `test/docx/numbering_part_test.dart` ("reading the numbering keeps it", "a list set that the check loads the part for keeps it", "a change is written from the model, and its revert is as read"); comments under `w:abstractNum` and `w:num` are not pinned separately |
| `addBulletList`, `addNumberedList` | add the `abstractNum` Word for Mac wrote for its Bullets and Numbering buttons (`builtins.docx`: nine levels, each indented 360 twips further, level 0 of the bullet list `Symbol` U+F0B7 at 720 hanging 360), without `w:nsid`, `w:tmpl`, `w:lvl/@w:tplc`, `@w15:restartNumberingAfterBreak` and `w:num/@w16cid:durableId`; each call is one new definition and one new instance | the optional identifiers, and the template codes carry the owner's locale | `test/docx/model/list_helpers_test.dart` ("bullet level 0 is Symbol U+F0B7 at 720 hanging 360", "every level of both lists is there, indented 360 further", "no new definition has nsid, tmpl or tplc"), `test/docx/builtin_numbering_oracle_test.dart` ("the definitions equal builtins.docx without the identifiers") |
| New ids | the lowest unused: `abstractNumId` from 0, `numId` from 1 (`numId` 0 means "no list" and is never given); a definition with an id that is not a number is kept and ignored; an opened document's definitions are kept | no id is reused or overflows | `test/docx/model/numbering_test.dart` ("new ids are the lowest unused", "numId 0 is never given", "an opaque num with a numeric id still takes its id"), `test/docx/model/list_helpers_test.dart` ("an opened document keeps its definitions and gains the lowest unused ids", "a second addNumberedList takes abstract 1 and num 2") |
| Where a new definition goes | before the first `w:num`, or after the picture bullets, or after the last `w:abstractNum`, with the instance before any `w:numIdMacAtCleanup` | schema order | `test/docx/model/numbering_test.dart` ("a new abstract goes before the first num", "a new abstract goes after the picture bullets when there is none"), `test/docx/model/list_helpers_test.dart` ("duplicate ids, an opaque id and a trailing numIdMacAtCleanup: the new definition follows the last abstractNum, the new instance the last num, and both take the lowest unused ids") |
| `addListItem(list, text, {level})` | adds a paragraph with the `ListParagraph` style (the document's own id for it, or the built-in added) and `w:numPr`; the text has no label; a list of another document throws `ArgumentError`, a level outside 0 to 8 `RangeError`, each leaving nothing changed | one rule for every document | `test/docx/model/list_helpers_test.dart` ("addListItem sets ListParagraph and numPr", "in localizedWordDocx() addListItem uses ListeParagraf", "paragraph text of a list item has no label", "an instance of another document throws ArgumentError and changes nothing", "a level outside 0 to 8 throws RangeError and changes nothing") |
| `addInstance(definition, {startOverrides})` | a new instance of an existing definition with `w:lvlOverride/w:startOverride`; a start out of range throws `RangeError`, a definition of another document `ArgumentError` | a restarted list | `test/docx/model/numbering_test.dart` ("startOverrides write lvlOverride with startOverride", "startOverrides out of range throw RangeError and change nothing", "an abstract of another document throws ArgumentError"), `test/docx/round_trip_test.dart` ("d2_lists restarts a numbered list with a start override") |
| A level's format | `DocxNumberFormat` for decimal, bullet and the formats it names (zero-padded decimal, roman, letters, ordinal); any other format reads `null` and is kept | no format is invented | `test/docx/model/numbering_test.dart` ("other formats and a custom format read null", "a read level text that breaks the rule reads null and stays") |
| A dangling `abstractNumId` | the instance reads `abstractNumbering` as `null`; kept | a file is never wrong | `test/docx/model/numbering_test.dart` ("a dangling abstractNumId reads abstractNumbering null") |
| Open, access the numbering, save | semantically equal, for every fixture and for the owner's files | layer 2 | `test/docx/numbering_part_test.dart` ("open, access numbering, save is semantically equal"), `test/docx/owner_files_test.dart` ("every owner file round-trips with its numbering loaded") |

### Warnings of D2

Two codes, for references set through the API only, each with a message in
`en`, `de` and `tr`, aggregated per part as `invalidCharactersRemoved` is.

| Case | Behaviour | Why | Test |
|---|---|---|---|
| `styleNotFound` | a `w:pStyle` or `w:rStyle` set through the API, or read in another document and put in this one, names no style of that type at save; the detail is the id, the location the path of the paragraph or run | a dangling style is silently the default style in Word | `test/docx/model/style_resolution_test.dart` ("an unknown id is kept and warns styleNotFound at its path on save", "a character style set as a paragraph style warns styleNotFound", "a style that resolves does not warn", "a block taken out is not reported"), `test/docx/warnings_test.dart` ("styleNotFound has en, de and tr text naming count, part and id") |
| `numberingNotFound` | a `w:numPr` set through the API, or read in another document and put in this one, names a `numId` other than 0 that the document does not define at save; the detail is the id; a broken numbering part reports nothing and the file saves | a paragraph in no list | `test/docx/numbering_part_test.dart` ("a numId set through the API that the document lacks warns at the paragraph", "numId 0, a defined numId and a read dangling numPr do not warn", "a list set in a document without numbering.xml warns", "an instance added before the save is defined", "a broken numbering part reports nothing and saves"), `test/docx/model/list_helpers_test.dart` ("a numId set to 7 that the document lacks warns numberingNotFound on save") |
| A dangling reference read from a file | kept, not reported: open and save reports nothing new | the file is the file's | `test/docx/model/style_resolution_test.dart` ("a read dangling pStyle does not warn"), `test/docx/numbering_part_test.dart` ("numId 0, a defined numId and a read dangling numPr do not warn") |
| The limits of the two checks | they cover only references set through the API or moved in from another document; `numberingNotFound` does not check the `w:numPr` of a style's `w:pPr` | the checks are about what the caller did | none: a known gap |
| Messages | every code has `en`, `de` and `tr` text, listed in `docs/warning-messages.md` | decision 0010 | `test/architecture/warning_messages_test.dart`, `test/tool/warning_messages_test.dart` |

### D2 fixtures and tools

| Case | Behaviour | Why | Test |
|---|---|---|---|
| The four D2 fixtures (`d2_run_formatting`, `d2_paragraph_formatting`, `d2_styles`, `d2_lists`) | build the same bytes every time with no warning, hold the parts they use, and round-trip with styles and numbering loaded | the CI validation starts from them | `test/docx/round_trip_test.dart` ("the D2 fixtures are the four the plan names, each named once", "every D2 fixture builds the same bytes and no warnings", "every D2 fixture round-trips with styles and numbering loaded", "the D2 fixtures hold the styles and numbering parts they use") |
| What the fixtures read back | every property set reads back; LibreOffice shows list labels apart from the model's text | the text compare ignores the labels | `test/docx/round_trip_test.dart` ("d2_run_formatting reads back its properties", "d2_paragraph_formatting reads back its properties", "d2_lists lists LibreOffice's labels apart from the model's text") |
| The owner's `builtins.docx` | round-trips with no warning and no difference, also with styles and numbering loaded; every typed property of the owner files reads without throwing | Word's own toolbar lists and built-in styles are the fidelity input | `test/docx/owner_files_test.dart` ("every owner file round-trips", "every owner file round-trips with styles and numbering loaded", "reading every typed property of the owner files throws nothing") |
| `tool/edit_docx.dart` | edits the first run (bold, accent 1), replaces a paragraph, edits the first cell of the first table and appends a row to it, appends a table with a header row and a merged row, adds a `Heading1`-style paragraph and a two-item bullet list, and checks the edits read back and that only the allowed parts differ | CI validates the edited files with the Open XML SDK | `test/tool/edit_docx_test.dart` ("a Word-like document gets the edits, and only the allowed parts change", "edits a document with Turkish style ids using Balk1", "creates numbering.xml in a document without one") |
| Styles and numbering in `tool/round_trip_docx.dart` | the model's own encoding of each part is compared, not a copy of the input | a part left as read would hide a writer bug | `test/tool/docx_serialize_test.dart` ("is the model's own writing, not a copy of the input", "finds none in the D2 fixtures") |
| The fuzz | seeds 1 to 4 at 600 cases each over the fixtures (tables among them), a hand-made table and producer variants, with typed attributes replaced in the typed parts, access to `styles` and `numbering`, and a `DocxReadException` from a typed getter counted as a failure | the typed exception is the contract | `test/docx/fuzz_test.dart` ("typed attributes are replaced in the typed parts", "mutated files raise only DocxReadException") |

### Writing and saving

| Case | Behaviour | Why | Test |
|---|---|---|---|
| Open, save, never access the body | `word/document.xml` is copied byte for byte | layer 1 of decision 0009: a part never loaded is its bytes | `test/docx/docx_document_test.dart` ("open and save") |
| Open, read the body, save | `word/document.xml` is saved with its original bytes, comments and out-of-order properties included, while the document's change log has no changes (an edit that failed leaves none; one undone by the log's `revertSet` still counts) | the same standard as the styles and numbering parts: no edit, no change | `test/docx/docx_document_test.dart` ("a main part with no edit keeps its bytes"), `test/docx/document_part_write_test.dart` |
| What the model writes for a main part read and not edited | means the same as the part by `comparePackages`, with `w:pPr` and `w:rPr` children in schema order; `tool/round_trip_docx.dart` encodes every main part to check it, since a save no longer does (`encodedMainDifferences`) | layer 2: a part with an edit is written from the model | `test/tool/docx_serialize_test.dart` ("encodedMainDifferences"), `test/docx/round_trip_test.dart`, `test/docx/owner_files_test.dart` |
| Very many children the schema lacks in a property container | read and written without recursion: 200,000 in a `w:rPr`, a `w:pPr`, a style and a `w:lvl` load, save and take an edit. A part's encode when it loads leaves only as a `DocxReadException` naming the part | a 2 KB ZIP can hold them | `test/docx/many_children_test.dart` |
| Open, set one run's text, save | only that `w:t` differs | a change touches only what it changes | `test/docx/docx_document_test.dart` |
| What the model does not type, inside a loaded part | written back as it was, declaring only the namespaces it needs and never redeclaring `w` | layer 3 | `test/docx/document_part_write_test.dart` |
| The root | written as read, with every namespace declaration and `mc:Ignorable`; a new document declares only `w` | `mc:Ignorable` names prefixes that must stay declared | `test/docx/document_part_write_test.dart` |
| A document with another prefix or a default namespace | round-trips | prefixes are the producer's | `test/docx/document_part_write_test.dart`, `test/docx/producer_variants_test.dart` |
| An edited `.docm` | every part but the body as it was; the macro content type is kept | macros are never run, created or edited | `test/docx/producer_variants_test.dart` |
| `saveTo` | the same bytes as `save`, sent to the sink | one writer | `test/docx/docx_document_test.dart` |
| `save().warnings` | what opening, loading and that save repaired, in first-occurrence order; `warnings` holds the same afterwards | the list reflects the document as last saved | `test/docx/docx_document_test.dart` |
| A relationship to a missing header | kept as written, with no throw; a reference through it counts as none | a broken reference is not an error (see "Headers and footers") | `test/docx/docx_document_test.dart`, `test/docx/model/header_footer_read_test.dart` |
| The body | loads once, on first access; a failed load changes nothing, so the next access throws again | the failure is the file's | `test/docx/docx_document_test.dart` |
| Owner files saved by Word for Mac | open, read the body and save with no warning and no difference; a confirmed file reads its confirmed text | the fidelity claim rests on Word's files | `test/docx/owner_files_test.dart` |
| Six packaging variants of `d1_paragraphs` (`ns0:` prefix, default namespace, no content type override, LibreOffice's, Google Docs' and a `.docm`) | open as `d1_paragraphs` and save equal | files from other producers are held to the same bar | `test/docx/producer_variants_test.dart` |

### Editing

| Case | Behaviour | Why | Test |
|---|---|---|---|
| `insertBlock`, `removeBlockAt`, `replaceBlockAt`; `insertInline`, `removeInlineAt`, `replaceInlineAt` | edit in place; the `blocks` and `inlines` lists are views that cannot be modified | one way to change a list | `test/docx/docx_document_test.dart` ("body edits"), `test/docx/model/body_model_test.dart` ("inline edits") |
| A block or inline already in a story, a cell or paragraph (this one or another document) | `StateError`; nothing changes | phase 4 neither moves nor copies implicitly | `test/docx/docx_document_test.dart`, `test/docx/model/body_model_test.dart`, `test/docx/primitives_test.dart` |
| An index out of range | `RangeError`; nothing changes and nothing is recorded | a programmer error | `test/docx/docx_document_test.dart`, `test/docx/model/body_model_test.dart`, `test/docx/primitives_test.dart` |
| A removed block or inline | belongs to nothing and can be inserted again | removal is not destruction | `test/docx/primitives_test.dart` |
| Each edit | a change in the document's `ChangeLog` that reverts and reapplies; an edit that fails, or a transaction of several that throws, undoes all of them | each edit is atomic | `test/docx/primitives_test.dart` ("rollback") |
| An edit alone | runs in a transaction of its own | the same guarantee | `test/docx/primitives_test.dart` |
| An edit of a paragraph outside a body | not recorded | there is nothing to undo | `test/docx/primitives_test.dart` |
| `addParagraph(text)` | appends a paragraph holding the text, split and scrubbed as a run's text; the empty text gives a paragraph with no run | the same rules everywhere | `test/docx/docx_document_test.dart` |

### A new document

| Case | Behaviour | Why | Test |
|---|---|---|---|
| `DocxDocument()` | one empty paragraph and this library's parts, with the values of Word for Mac 16.114.1's blank document, without `docProps`; it opens and saves unchanged | like Word's blank document (decisions 0010, 0011) | `test/docx/blank_document_test.dart` |
| Page | A4 portrait | decision 0010 | `test/docx/blank_document_test.dart`, `test/docx/blank_document_oracle_test.dart` |
| Fonts | Aptos through the theme, at 12 pt | Word's current default | `test/docx/blank_document_test.dart` |
| Locale | none of the reference file's: every language is `en-US`, and the decimal symbol and list separator are left to the reader | a generated file must not carry its author's region | `test/docx/blank_document_test.dart`, `test/docx/blank_document_oracle_test.dart` |
| Style ids and names | Word's en-US ones (`Normal`, `Heading1`), not the Turkish ones of the reference file | a library caller writes `style = 'Heading1'` | `test/docx/blank_document_test.dart` |
| Revision ids, document id, proof state, attached template | none | they identify the reference file | `test/docx/blank_document_test.dart` |
| `compatibilityMode` 15 and the web settings | kept | Word opens the file in the current mode | `test/docx/blank_document_test.dart` |
| The parts | the same part names as the reference file apart from `docProps`; its styles, document defaults, theme colours and fonts, font table and compatibility settings have equal values after removing ids and locale; none of the owner's document properties is written | the reference is a file the owner saved from Word | `test/docx/blank_document_oracle_test.dart` |

### Tables

Reading, writing and the limits. Every table in this part follows the fidelity
standard of the rest: a table read and not edited is written as read, and
what the model does not type is kept in place. Paths in warnings and in the
`maxTextLength` failure name the tree: `body/tbl[i]/tr[j]/tc[k]/p[m]/r[n]`,
each index counting that kind of element among its siblings, only the typed
ones (`tbl` among the blocks of its container, `tr` among rows, `tc` among
cells, `p` among paragraphs); `body/p[i]` keeps counting the body's own
paragraphs, so a table does not shift it. A nested table is `tc[k]/tbl[i]/…`.

| Case | Behaviour | Why | Test |
|---|---|---|---|
| A table, row and cell | `w:tbl`, `w:tr` and `w:tc` are matched by namespace and local name; a table, a row and a cell read as `DocxTable`, `DocxTableRow` and `DocxTableCell`, a cell's blocks as paragraphs, tables and opaque blocks, and a nested table is a block of its cell | the model's job in D3 | `test/docx/model/tables_read_test.dart` ("a table reads rows, cells and paragraphs", "a nested table is a block of its cell") |
| A `w:tbl` inside a `w:sdt`; a `w:tr` or `w:tc` where its parent does not allow one; an element of another namespace named `tbl`, `tr` or `tc` | not typed: kept as an opaque block (or kept child) in place | nothing is guessed | `test/docx/model/tables_read_test.dart` ("a w:tbl inside a w:sdt stays opaque", "w:tr and w:tc out of place are opaque", "an element of another namespace named tbl, tr or tc is not typed") |
| A `w:sectPr` in a cell; a table last in the body | a block of the cell; the table comes before the body's final `w:sectPr` | the final section is the body's | `test/docx/model/tables_read_test.dart` ("a w:sectPr in a cell is a block of the cell", "a table last in the body comes before the final sectPr") |
| Bookmarks, `w:sdt` and `w:tblPrEx` between rows and cells; the attributes of `w:tbl`, `w:tr` and `w:tc` | kept in a private child list, in place; not shown by `rows` and `cells` | what the model does not show stays where it was | `test/docx/model/tables_read_test.dart` ("bookmarks, sdt and tblPrEx stay in place", "attributes of w:tbl, w:tr and w:tc are kept") |
| `gridColumnsPt` | `null` with no `w:tblGrid`, empty for an empty one, `null` for an entry that is not a whole number of twips; only the direct `w:gridCol` children count, and a second `w:tblGrid` or one after a row is not read | a grid in a file may be anything | `test/docx/model/tables_read_test.dart` ("is null with no w:tblGrid", "is empty for an empty grid", "an entry that does not parse is null", "only the direct w:gridCol children count", "a second w:tblGrid, or one after a row, is not read") |
| A `w:tblPr`, `w:trPr` or `w:tcPr` that is second, or after a row, a cell or a block | the first is typed and the second kept; one in the wrong place is not typed | one properties element per container | `test/docx/model/tables_read_test.dart` ("a second one is kept and the first is typed", "one after a row, a cell or a block is not typed") |
| Tables nested deeper than `maxTableNesting` (256) | `limitExceeded` naming the limit and the part, whatever `DocxReadLimits.maxDepth` is; the deepest nesting the default `maxDepth` allows reads and saves | the reader, the writer and the walks recurse once per table | `test/docx/model/tables_read_test.dart` ("a table at maxDepth reads or fails as limitExceeded", "the deepest tables the default limit allows save", "tables past the nesting a raised limit allows fail as") |
| A `w:t` or an opaque inline too long in a cell | `limitExceeded` naming the paragraph's full path | the path says where | `test/docx/model/tables_read_test.dart` ("text past maxTextLength in a cell names", "indexes count typed rows, cells, tables and paragraphs", "the visible text of an opaque inline in a cell names its path", "paragraphs in a cell do not shift body/p[i]") |
| A table read, no edit, save | the part's bytes; edited elsewhere, the table means the same by `comparePackages` | layers 1 and 2 | `test/docx/model/tables_read_test.dart` ("a document with no edit saves its bytes"), `test/docx/document_part_write_test.dart` ("a table saves semantically equal", "a table saves semantically equal with odd prefixes"), `test/docx/owner_files_test.dart` ("a table saves semantically equal") |
| The owner's tables (`builtins.docx`) | read their rows, cells and paragraphs; the cell text is checked against constants in the test, since the confirmed expected texts stay paragraphs only; the table style resolves in the document | the confirmed texts may not change | `test/docx/owner_files_test.dart` ("a table reads rows, cells and paragraphs: builtins.docx", "owner tables read their cells", "a table style resolves in the document: builtins.docx") |
| The lists `rows`, `cells`, `blocks` and `gridColumnsPt` | cannot be modified | one way to change them | `test/docx/model/tables_read_test.dart` ("the lists of a table, a row and a cell cannot be modified", "cannot be modified") |
| Visiting the tree | `visitBlocks` reaches a block and everything in its cells, in order; a block read into a cell that is already in another container throws `StateError` | one walk for the reader, the sink and the writer | `test/docx/model/tables_read_test.dart` ("visits a block and everything in its cell", "markBlockReadIn marks what a table holds", "a block already in a container cannot be read into a cell") |

#### Table values and properties

| Case | Behaviour | Why | Test |
|---|---|---|---|
| The schema order of `w:tblPr`, `w:trPr`, `w:tcPr`, `w:tblBorders`, `w:tcBorders` and `w:tblCellMar` | the order lists equal the transitional schema's sequences, and name no element twice | a set writes in the place the schema gives (D2's rule for containers) | `test/docx/schema_order_test.dart` ("tblPrOrder matches the transitional schema", "trPrOrder matches the transitional schema", "tcPrOrder matches the transitional schema", "tblBordersOrder matches the transitional schema", "tcBordersOrder matches the transitional schema", "tblCellMarOrder matches the transitional schema", "no list names an element twice") |
| A width (`w:tblW`, `w:tcW`) | reads `auto`, `nil`, `dxa` (also with no type) and `pct`; points are rounded to twips; a percent written with a sign, a bad type or a bad number has no view; a table's and a cell's width codecs are distinct | the values are the file's | `test/docx/table_property_codecs_test.dart` ("TableWidthCodec") |
| Layout, alignment, indentation, borders, margins, look, row height, vertical merge, cell alignment and text direction | each reads what the file holds and writes its own spelling; a value the model cannot type (`start` and `end` sides, a border not in `dxa`, a bad number) has no view and is kept; `w:tblLook` writes the six flags and the bits of `w:val`, and the attributes win when both are read | read what is there, write what Word writes | `test/docx/table_property_codecs_test.dart` ("TableLayoutCodec", "TableAlignmentCodec", "TableBordersCodec", "CellBordersCodec", "TableIndentCodec", "TableMarginsCodec", "TableLookCodec", "RowHeightCodec", "VerticalMergeCodec", "CellAlignmentCodec", "TextDirectionCodec") |
| The three schemas | type the properties named above, and an attribute a codec does not know gives the child no view; `gridSpan` below 1 and `gridBefore` below 0 have no view | no value is invented | `test/docx/table_property_codecs_test.dart` ("tablePropertiesSchema types the seven properties and tblStyle", "tableRowPropertiesSchema types five properties", "tableCellPropertiesSchema types seven properties", "gridSpan below 1 and gridBefore below 0 have no view", "an attribute a codec does not know gives the child no view") |
| A member of `DocxTableProperties`, `DocxTableRowProperties` or `DocxTableCellProperties` | a nullable get and set, written in place among the children the model does not type, `w:tblPr` before the grid and the rows, `w:trPr` after any `w:tblPrEx` and before the cells, `w:tcPr` first in the cell; one read in another place stays there and the new one is written in the schema's place | the paragraph's rule, for tables | `test/docx/model/table_properties_test.dart` ("every member sets, writes in place and reads back", "a w:tblPr is written before the grid and the rows", "a w:trPr is written after a w:tblPrEx and before the cells", "a w:tcPr is first in the cell, before a kept child", "a misplaced w:tblPr stays where it was") |
| `cantSplit` or `repeatAsHeader` set `false` | writes `w:val="off"`: the schema takes only `on` and `off` on these two, and the SDK refuses `0`; a value read, `true` among them, stays as read until set | what is written must validate | `test/docx/model/table_properties_test.dart` ("false is written w:val="off", the only word w:trPr takes", "a read w:val stays as read until it is set") |
| Setting what a member reads; a set; `null`; `clear` | setting the value read changes nothing and records nothing; a set is one change that undoes; `null` removes the child, and `clear` removes what the getter cannot read; bad values throw before anything changes; a row with nothing set writes no `w:trPr` | the same as the paragraph's | `test/docx/model/table_properties_test.dart` ("setting what it reads changes nothing", "a set is one change and undoes", "a null removes the child and clear removes what it cannot read", "bad values throw before anything changes", "a row with nothing set writes no w:trPr") |
| `DocxTableProperties.style` | resolved as a table style in the document (`TableGrid` becomes the document's id for it, and is added with `Normal Table` when the document lacks it); a set is one change with the style it adds | D2's style rules, for the table type; a table style of another type counts as not found | `test/docx/model/table_properties_test.dart` ("style resolves as a table style in the document", "a style set is one change with the style it adds"), `test/docx/warnings_test.dart` ("a table style of another type counts as not found") |
| `DocxTableRow.isHeader` | `repeatAsHeader == true`; setting `true` sets `w:tblHeader`, `false` removes it | the shortcut | `test/docx/model/table_properties_test.dart` ("isHeader is repeatAsHeader == true") |
| `gridSpan` | a set outside 1 to 63 throws `RangeError`; a file may hold more and it reads | 63 is Word's limit | `test/docx/model/table_properties_test.dart` ("gridSpan checks 1 to 63", "a file may hold a gridSpan past 63 and it reads") |
| `gridColumnsPt` set | replaces the grid in one change, writes a grid before the rows for a table with none, rounds to twips; a list of another length once the table has rows, an empty one, and one of fewer columns than the widest row of a table with no grid throw `ArgumentError`; setting what it reads changes nothing, a `null` or a `null` entry too; each `w:tcW` stays | a row's cells must fit the grid | `test/docx/model/table_properties_test.dart` ("a set replaces the grid in one change and undoes", "a list of another length throws once the table has rows", "a table with no grid takes one before its rows", "the grid is written after a w:tblPr that was set", "setting what it reads changes nothing, whatever it reads", "a table with no grid takes no fewer columns than its widest row", "an empty list throws, with or without rows and a grid") |
| A cell edited in a nested table | reports to the document | the change log sees every table | `test/docx/model/table_properties_test.dart` ("a cell edited in a nested table reports to the document") |
| The public surface | `DocxTable`, `DocxTableRow`, `DocxTableCell`, the values and the properties are exported, and expose no internals | the barrel is the API | `test/docx/public_surface_test.dart` |

#### Building a table

| Case | Behaviour | Why | Test |
|---|---|---|---|
| `DocxBody.addTable` | writes what Word's Insert Table writes: the style `Table Grid` (the document's own, or Word's definition added with `Normal Table`), `w:tblW` of `w:w="0"` and `w:type="auto"`, `w:tblLook` of `04A0` with its six flags, equal `w:gridCol` and `w:tcW` of the last section's text width less 10 twips (9062 on a blank A4 page) divided by the columns, rounded down, in schema order; `columnWidthsPt` sets the grid and the cells instead | the owner's `builtins.docx` is the oracle | `test/docx/table_build_oracle_test.dart` ("addTable writes what Word's Insert Table writes"), `test/docx/model/table_build_test.dart` ("writes the properties of Insert Table, in schema order", "shares the width of a blank A4 page, in whole twips", "columnWidthsPt sets the grid and the cells of each row") |
| The style of a new table | a Turkish document gets `TabloKlavuzu`; a document with the normal table style only gets `TableGrid` on it; a blank one gets `TableGrid` and `TableNormal` | the built-in is found by name (D2) | `test/docx/model/table_build_test.dart` ("a Turkish document gets TabloKlavuzu", "a document with the normal table only gets TableGrid on it", "a blank document gets TableGrid and TableNormal") |
| A bad `addTable` argument | `columns` outside 1 to 63 or a width out of range throw `RangeError`; `columnWidthsPt` of another length or a width that is not finite throws `ArgumentError`; an unreadable styles part throws `DocxReadException`; nothing changes | programmer errors throw (Global Constraints) | `test/docx/model/table_build_test.dart` ("a bad argument throws and changes nothing", "on an unreadable styles part throws and changes nothing") |
| `addTable` | one transaction with the style it adds; a failure after the insert takes all back; adds no paragraph between two tables or after the last | the model never adds a block | `test/docx/model/table_build_test.dart` ("is one transaction, with the style it adds", "a failure after the insert takes it all back", "adds no paragraph between two tables or after the last") |
| `DocxTable.addRow` | takes `List<String?>`: `null` is an empty cell, fewer values leave empty cells, more throw `ArgumentError`; text is split and scrubbed as a run's; a cell takes the width of its column; `header: true` sets `repeatAsHeader` and `cantSplit` | formatting numbers belongs to the caller | `test/docx/model/table_build_test.dart` ("null is an empty cell, and fewer values leave empty cells", "more values than columns throw and change nothing", "text is scrubbed and split as a run does it", "is one change that undoes and redoes", "works on a table in no document") |
| `addRow` on a table read | a row of the grid's width after the rows; a column without a usable width gives a cell without one; a grid past 63 columns gives a row of its width; a table with no grid, or an empty one, throws `ArgumentError` (use `insertRow`) | a row's width needs a grid (`insertRow` takes any row) | `test/docx/model/table_build_test.dart` ("on a table read takes the width of its grid, after its rows", "a column without a usable width gives a cell without one", "a grid past 63 columns gives a row of its width", "a table without a grid throws: it has no width") |
| A table with no rows | `addTable` returns one; a save of it throws `StateError` naming it (also one nested in a cell), writes nothing, and the first row, or removing the table, makes it saveable; a table read with no rows is kept, edited or not; the constructor refuses `rows` below 1 | Word repairs a table without rows | `test/docx/model/table_build_test.dart` ("a save names it, and writes nothing", "a save names one nested in a cell", "the first row, or removing the table, makes it saveable", "an undone first row leaves it unsaveable again", "a table read with no rows is kept, edited or not", "the constructor still refuses it") |
| `DocxTableCell.addTable` | behaves as the body's: the document's `Table Grid` style, one transaction, a bad argument changes nothing; in a cell of no document the table has no style, and one set resolves when the cell goes in a document; nesting past 80 throws `ArgumentError` | the same rules at every level | `test/docx/model/table_build_test.dart` ("in a document behaves as the body does", "in a document adds the style a document lacks", "finds the built-in by name, as the body does, past a squatter", "past the nesting the API builds throws and changes nothing") |
| The styles of what goes in | a table, a row or a cell put in a document has every style set on it and in its cells resolved as `insertBlock` does, an unreadable styles part changing nothing; inserted in no document the id is stored as given; a table moved within its document stays as read | D2's rules for blocks | `test/docx/model/table_build_test.dart` ("the styles of what goes in", "a style set on a table in a document resolves as it is set", "an insert in no document stores the id as given", "the styles a route adds undo with it", "a read table moved within its document stays as read") |
| A table, row or cell read in another document and inserted | its `w:tblStyle`, `w:pStyle`, `w:rStyle` and `w:numPr` count as set, a missing one is reported at save with its full path, a built-in it names resolves to this document's id, and undoing the insert takes the count back; a style read in a table of this document is not reported | the references of D2, in tables | `test/docx/model/table_build_test.dart` ("its w:tblStyle and the deep references count as set, and a missing", "a built-in it names resolves to this document's id", "a row or a cell read there joins the same way", "undoing the insert takes the count back", "a style read in a table of this document is not reported") |
| `styleNotFound` and `numberingNotFound` in a table | name the paragraph, the table and the nested table by their full paths | warnings keep their paths | `test/docx/warnings_test.dart` ("styleNotFound names a paragraph in a cell by its full path", "numberingNotFound names a paragraph in a cell by its full path", "styleNotFound names a table and a nested table by their paths"), `test/docx/document_part_write_test.dart` ("warnings name the path in the table", "the checks of a list and a style name the path in the table") |

#### Editing a table

| Case | Behaviour | Why | Test |
|---|---|---|---|
| A new `DocxTable`, `DocxTableRow`, `DocxTableCell` | a table of the rows and columns asked for, of empty cells, dividing 9062 twips (rounded down), one row by default; `w:tblPr` and `w:tblGrid` are written, each `w:tcW` in twips; a table read without a `w:tblPr` still writes none; a new cell holds one paragraph of its text | the constructors build what `addTable` builds, without a style | `test/docx/model/tables_edit_test.dart` ("has the rows and columns asked for, with empty cells", "divides 9062 twips among its columns, rounded down", "takes 1 to 63 columns and at least one row", "writes w:tblPr and w:tblGrid, and each w:tcW in twips", "a table read without w:tblPr still writes none", "a new cell holds one paragraph of its text") |
| `insertRow`, `removeRowAt`, `insertCell`, `removeCellAt` | the item is at its index counting the typed ones, and the edit undoes and redoes; a removed one can go in again; an index out of range throws `RangeError`; a row or cell in another table or row throws `StateError` | one way to change a list (D1) | `test/docx/model/tables_edit_test.dart` ("an inserted row is at its index, and undoes and redoes", "a removed row can go in again, and the removal undoes", "an index out of range throws RangeError", "a row in a table cannot go in another", "an inserted cell is at its index, and undoes and redoes", "a removed cell undoes, and can go in again", "a cell in a row cannot go in another") |
| The last row of a table and the last cell of a row | removing it throws `StateError` and changes nothing; a file's empty table or row is kept as read and takes a row | Word repairs them | `test/docx/model/tables_edit_test.dart` ("removing the last row throws StateError and changes nothing", "a file's empty table is kept as read and takes a row", "removing the last cell throws StateError and changes nothing") |
| A row or a cell inserted into a table of a document | reports to the document until it is out | the change log sees what is in the document | `test/docx/model/tables_edit_test.dart` ("a row in a table reports to its document until it is out", "a cell in a row reports to its document until it is out") |
| The blocks of a cell | outside a document an edit records nothing; in a document each is one change that undoes; `addParagraph` is one change; a bad index or a block already in a container changes nothing; a style set on a paragraph resolves as it goes in | the body's rules, for a cell | `test/docx/model/tables_edit_test.dart` ("outside a document they change and record nothing", "in a document each edit is one change that undoes", "addParagraph is one change", "a bad index or a block in a container changes nothing", "a style set on a paragraph resolves as it goes in a cell") |
| A failed edit | rolls back: inserting or removing a row or a cell, inserting, removing or replacing a block | each edit is atomic | `test/docx/model/tables_edit_test.dart` ("a failed edit rolls back") |
| A table inside itself | a table cannot go in a cell of itself or of a nested table, nor a row in a table it holds, nor a cell | no cycle | `test/docx/model/tables_edit_test.dart` ("in a cell of the table", "in a cell of a nested table", "nor a row in a table it holds, nor a cell") |
| The nesting of tables | the API builds at most 80 deep, counting what goes in and where, a row and a cell that go in; at its deepest, what saves opens under the default limits; in a file nested past 80, a plain row or cell still goes in, a nested table throws and changes nothing, and a table read that deep cannot go back in the API (undo restores it) | what is saved must reopen; the reader's limit is 256 | `test/docx/model/tables_edit_test.dart` ("reaches the limit of the API and goes no further", "counts what goes in, and where it goes", "counts a row and a cell that go in", "at its deepest, what saves opens under the default limits", "a plain row goes in, as it deepens nothing", "a table read that deep cannot go back in the API"), `test/docx/model/table_merge_test.dart` ("a table that would nest past 80 deep throws ArgumentError") |
| A saved cell | ends in a paragraph, trailing range markers (`w:bookmarkStart` and the like) aside: a table last in a cell, a cell whose only block was removed, and a new cell whose only block was removed all save with an empty `w:p` after them, which `blocks` does not show until the file is read again | Word repairs a cell without one | `test/docx/model/tables_edit_test.dart` ("a table last in a cell", "a table last in the body", "a cell whose only block was removed", "a new cell whose only block was removed", "a cell whose paragraph was replaced by a table, in a table") |
| A trailing range marker in a cell (`w:bookmarkStart`, `w:bookmarkEnd`, `w:commentRangeStart`, `w:commentRangeEnd`, `w:permStart`, `w:permEnd`, and the `w:moveFromRange` and `w:moveToRange` marks) | a paragraph before it still closes the cell, so an edit adds no blank `w:p`; a table before it does not, and a cell with no paragraph at all gets one | such a marker shows nothing | `test/docx/document_part_write_test.dart` ("a paragraph before a trailing bookmarkEnd closes an edited cell", "a table before a trailing marker does not close a cell") |
| A cell read without a closing paragraph | written as read while its blocks are the ones read; the exception is by identity, so an undo restores it; a block put before the last read one closes the cell, and a cell read empty is empty again once a block added goes | the fidelity standard | `test/docx/document_part_write_test.dart` ("a read cell without a closing paragraph is written as read", "a block put before the one read last closes the cell", "a cell read empty is empty again once a block added goes", "a cell emptied of its only block gets one", "a cell read empty stays empty until a block goes in", "a paragraph that closes the cell needs no other", "a table last in a cell gets one when it is not the one read") |
| What the model does not show | an inserted row goes directly before the row at its index, the last after the last child; a removed row leaves what lay between, and its undo puts it back; between cells it is the same; an undone insert leaves the file as it read | what the model does not show stays where it was | `test/docx/model/tables_edit_test.dart` ("an inserted row goes directly before the row at its index", "a row inserted first goes before the first row", "a row inserted last goes after the last child", "a removed row leaves them, and the undo puts it back", "between cells it is the same", "an undone insert leaves the file as it read", "the rows in a content control are not counted") |
| A prebuilt nested table | records an edit only while it is in the document; a row and a cell of it follow; a table moved between cells keeps reporting | the sink follows the tree | `test/docx/model/tables_edit_test.dart` ("records an edit only while it is in the document", "a row and a cell of it follow too", "a table moved between cells keeps reporting") |
| 200,000 kept children | a row and a table with that many insert in time | a 2 KB ZIP can hold them | `test/docx/model/tables_edit_test.dart` ("a row with 200,000 kept children inserts in time", "a table with as many inserts in time") |
| The edit sink | an edit outside a transaction is a transaction of its own; one that fails once recorded is taken out again; on the sink of no document edits apply and record nothing | one path for every container | `test/docx/primitives_test.dart` ("outside a transaction an edit is a transaction of its own", "an edit that fails once recorded is taken out again", "on the sink of no document they apply and record nothing", "a block change is applied by the sink, once") |

#### Merging cells and spans

`mergeCells` takes the rows of `rows` and the columns of the grid, all
inclusive. Everything below is one edit that throws `ArgumentError` before it
changes anything.

| Case | Behaviour | Why | Test |
|---|---|---|---|
| A merge in a 3 x 3 table | a whole row leaves one cell; part of a row spans what it covers; a column restarts, continues and removes no cell; a block spans in each row and continues below the first; the whole table keeps every row with its one cell; it saves and reads back the same, and the same on a table in no document | Word's merges | `test/docx/model/table_merge_test.dart` ("of a whole row leaves one cell, with the text in order", "of part of a row spans what it covers", "of a column restarts, continues and removes no cell", "of a block spans in each row and continues below the first", "of the whole table keeps every row, with its one cell", "saves and reads back the same", "works the same on a table in no document") |
| The blocks of a merge | move to the top-left cell in reading order without empty paragraphs, in the first cell too; a run without text counts as empty, a paragraph holding a tab or a bookmark does not; a merge of empty cells, or of cells without blocks, leaves one empty paragraph; tables and opaque blocks move in order, and a table moved last leaves a cell that saves with a paragraph; an edit of a moved paragraph is recorded | Word drops the empty paragraphs of a merge | `test/docx/model/table_merge_test.dart` ("lose their empty paragraphs, in the first cell too", "count a run without text as empty", "keep a paragraph that holds a tab or a bookmark", "a merge of empty cells leaves one empty paragraph", "a merge of cells without blocks leaves one empty paragraph", "tables and opaque blocks move in reading order", "a table moved last leaves a cell that saves with a paragraph", "an edit of a moved paragraph is recorded by the document") |
| Two tables brought into one cell | an empty paragraph stays between them, so Word does not join them; one of several | an adjacent pair is one table in Word | `test/docx/model/table_merge_test.dart` ("an empty paragraph stays, so Word does not join them", "one empty paragraph stays of several") |
| The width of a merged cell | the sum of the merged columns, in each row of the merge; the cell keeps its own width when a merged column has none, when a cell merged in that row has no width in twips, when the sum is more than a width holds, or when no cell of the row goes | a width must be one a cell can hold | `test/docx/model/table_merge_test.dart` ("is the sum of the merged columns, in each row of the merge", "stays when a merged column has no width", "stays when the sum is more than a width holds", "stays when the merged columns have no width between them", "stays when no cell of the row goes", "stays when the merged cells are not in twips") |
| A merge over what is merged | a cell spanning columns, or a vertical merge, wholly inside the range joins it; rows around a bookmark keep the bookmark, and rows next to a `w:sdt` outside the range go; a range of one cell changes nothing; `w:gridBefore` and `w:gridAfter` shift the columns | Word's behaviour | `test/docx/model/table_merge_test.dart` ("holds a cell spanning columns inside the range", "holds a vertical merge inside the range", "of rows of different cells goes by the grid", "of rows around a bookmark keeps the bookmark", "of rows next to a w:sdt that is outside the range goes", "of a range that is one cell changes nothing", "w:gridBefore and w:gridAfter shift the columns") |
| A merge that does not fit | a range past the grid, backwards, cutting a merged cell, on the columns of `w:gridBefore` or `w:gridAfter`, around a `w:sdt` or a `w:customXml`, spanning more than 63 columns, or whose tables would nest past 80 deep throws `ArgumentError`, as does a table with no grid | what a merge cannot do is refused | `test/docx/model/table_merge_test.dart` ("a merge past the grid throws ArgumentError", "a range that runs backwards throws ArgumentError", "a merge that splits a merged cell throws ArgumentError", "a range on the columns of w:gridBefore throws ArgumentError", "a range on the columns of w:gridAfter throws ArgumentError", "a span past 63 columns throws ArgumentError", "a table that would nest past 80 deep throws ArgumentError", "an empty w:tblGrid throws ArgumentError") |
| An irregular file | rows of unequal cell counts, a `w:gridSpan` past the grid, a `w:vMerge` continue with no restart and no `w:tblGrid` open, read and round-trip, and `mergeCells` over one throws `ArgumentError`; one irregular row outside the range does not matter | a file is never refused for its grid | `test/docx/model/table_merge_test.dart` ("an irregular file", "a continue with no restart inside the range throws too", "a continue under another span inside the range throws too", "a row with fewer cells throws even in the columns it has", "an irregular row outside the range does not matter") |
| A merge | undoes in one step, and one that fails half way rolls back | each edit is atomic | `test/docx/model/table_merge_test.dart` ("a merge undoes in one step", "a merge that fails half way rolls back") |
| `gridSpan` of a cell of a row in a table | a span that does not fit the grid with `w:gridBefore` and `w:gridAfter` throws, and nothing changes; one that fits once a cell is removed first goes in; a row in no table, or a table with no grid, is not checked; a file that does not fit reads and can be narrowed | the API checks the fit, a file is kept | `test/docx/model/table_merge_test.dart` ("past the grid throws ArgumentError, and nothing changes", "fits once a cell is removed first", "counts w:gridBefore and w:gridAfter", "is not checked in a row in no table, or in no row", "is not checked in a table without a grid", "a file that does not fit reads, and can be narrowed") |
| `gridSpan` and `verticalMerge` in a vertical merge | a continuation widened or narrowed against the cell above, a cell widened or narrowed against the continuation below, and a span that moves a merged cell along the row throw; a span that changes nothing is no change; a cell away from the merge takes a span; a continuation read out of line can be brought into line; spans first and then `verticalMerge` build a merge by hand | merges stay aligned through every set | `test/docx/model/table_merge_test.dart` ("a continuation widened past the cell above throws", "a cell widened past the continuation below throws", "a continuation narrowed under the cell above throws", "a cell narrowed over the continuation below throws", "a span that moves a merged cell along the row throws", "a span that changes nothing is no change", "a cell away from the merge still takes a span", "a continuation read out of line can be brought into line", "spans first, then verticalMerge, builds a merge by hand", "a merge widens merged cells past its own transient states") |
| `verticalMerge` continuation | in the first row, under another span, or with nothing above throws; under a cell of the same span it sets; restart and `null` are not checked, nor is a cell in no table; a continue read with no restart can be set to what it reads | a continuation needs a cell above | `test/docx/model/table_merge_test.dart` ("continuation in the first row throws ArgumentError", "continuation under another span throws ArgumentError", "continuation with nothing above throws ArgumentError", "continuation under a cell of the same span sets", "restart and null are not checked", "is not checked in a row in no table", "a continue read with no restart can be set to what it reads") |
| A row or a cell inserted | one whose spans, with `w:gridBefore` and `w:gridAfter`, exceed the grid throws, as does one with a continuation first in the table or under another span; a row with fewer columns goes in; an index out of range is `RangeError`; in a table without a grid a row is not checked, and a continuation is | the fit is checked where the row lands | `test/docx/model/table_merge_test.dart` ("whose spans exceed the grid throws, and nothing changes", "counts the spans of its cells", "that fits, with fewer columns, goes in", "with a continuation first in the table throws", "with a continuation under another span throws", "with a continuation is judged by the row above its index", "in a table without a grid is not checked", "past the grid throws, and nothing changes", "counts its span and what the row skips") |
| `cellAtGrid` | counts `w:gridBefore` and each span, and reads a span set since | the merge's reading of the grid | `test/docx/model/table_merge_test.dart` ("counts w:gridBefore and each span", "reads a span set since") |
| A plain row between a restart and its continuation; a removal that orphans a merge | allowed (a known gap) | removal and insertion must keep working on any table | `test/docx/model/table_merge_test.dart` ("that is plain may go inside a vertical merge", "a removal that orphans a merge is allowed") |

### D3 fixtures and tools

| Case | Behaviour | Why | Test |
|---|---|---|---|
| The five D3 fixtures (`d3_basic`, `d3_header_row`, `d3_merges`, `d3_formatting`, `d3_nested`) | build the same bytes every time with no warning, read their text and round-trip; none ends in a table | the CI validation starts from them | `test/docx/round_trip_test.dart` ("the D3 fixtures are the five the plan names", "every D3 fixture builds the same bytes and no warnings", "every D3 fixture reads its text and round-trips") |
| What the fixtures hold | `d3_header_row` repeats its header over 120 rows, keeps its rows whole and has one row of an exact height; `d3_merges` holds each merge shape; `d3_nested` holds a table in a cell, a list in a cell and a table last in a cell | the Word check looks for these (`word-checks.md`) | `test/docx/round_trip_test.dart` ("d3_header_row repeats its header over 120 rows", "d3_merges reads each merge shape", "d3_nested holds a table in a cell, a list and a last table") |
| A body that ends in a table | saves, reads back and round-trips; no fixture is one, because LibreOffice's text export of such a document never ends, so `tool/write_table_last.dart` writes `d3_table_last.docx` for the owner's Word check | the case must be checked somewhere | `test/docx/round_trip_test.dart` ("a body that ends in a table saves and reads back"), `test/tool/docx_tools_test.dart` ("writes a document whose body ends in a table, and nothing else") |
| The expected text of a table fixture | `d3_basic` and `d3_merges` have text written by hand (a line for each row, the cells joined by a tab, a merged cell's paragraphs as lines of their own); the others take the model's reading. The owner's expected texts stay paragraphs only: `docxBodyText` keeps its meaning and `docxFullText` adds the tables | a bug in cell text must not hide in its own expectation | `test/tool/text_compare_test.dart` ("a table is a line for each row, its cells joined by a tab", "paragraphs of a cell are lines, as LibreOffice writes them", "a nested table adds the lines of its rows in place", "a new document reads as the empty text") |
| `d3_nested` and LibreOffice's text | left out of the text comparison, with its reason printed (`DocxFixture.libreOfficeTextSkip`): LibreOffice repeats a paragraph in the text of nested tables, and differs by version; its re-save is still compared | a second opinion that disagrees with itself decides nothing | `test/tool/docx_tools_test.dart` ("writes the reason of a skipped LibreOffice text, only for those", "a skipped fixture is not compared and the output says so") |
| `tool/edit_docx.dart` on tables | edits the first cell of the first table and appends a row `New row` when the table has a grid, appends a table of a header row, a body row and a merged row to every document, and checks the edits read back | CI validates the edited files with the Open XML SDK | `test/tool/edit_docx_test.dart` ("every fixture is edited, and the appended table is as built", "a table of a document takes the cell text and a new row", "reports a cell edit that does not read back") |
| Tables in `tool/round_trip_docx.dart` | the children of `w:tblPr`, `w:trPr` and `w:tcPr` compare in any order, and the typed properties of every paragraph and run of a cell and of every table, row and cell are read | the model writes them in schema order | `test/tool/docx_serialize_test.dart` ("the children of tblPr, trPr and tcPr compare in any order", "readTypedProperties reads the paragraphs and runs of a cell", "readTypedProperties reads the properties of tables, rows and") |
| The fuzz | seeds 1 to 4 at more cases than 150 (600 since D4): the fixed seeds must mutate every part name of the corpus, and the corpus grew by the D3 fixtures and `tables_by_hand`, so raise it again if a new part name joins; each loaded table's and cell's properties and grid are read, a row is added to each table and ranges of its cells are merged (only `ArgumentError` may come out of those two), and a save never throws `StateError`, even for a table the file left without rows | the typed exception is the contract | `test/docx/fuzz_test.dart` ("every part name is mutated in some corpus entry", "mutated files raise only DocxReadException") |

### Sections

| Case | Behaviour | Why | Test |
|---|---|---|---|
| `DocxDocument.sections` | the top-level paragraphs of the body with a `w:sectPr`, in order, then the last; each the same object every time; the list is a snapshot that cannot be modified; it loads the body and throws what the body throws | Ruling 9: what Word calls a section | `test/docx/model/sections_test.dart` ("a body of two breaks gives three sections, in order", "a section is the same object every time", "the list cannot be changed and is a snapshot", "it loads the body and throws what the body throws") |
| A `w:sectPr` between the body's blocks, in a cell or in a `w:sdt` | stays as read and starts no section; the first stays an opaque block | Ruling 9, a known gap | `test/docx/model/sections_test.dart` ("a mid-body sectPr stays an opaque block and starts no section", "a sectPr in a cell or a content control starts no section") |
| A body with no final `w:sectPr` | has a last section of no values, written only once something is set; a document with no body gains one for a value set | every document has a last section, and nothing is invented | `test/docx/model/sections_test.dart` ("a body without a final sectPr has a last section of no values", "that section is written only once something is set", "a document without a body gains one for a value set") |
| A paragraph with a break removed, or moved out of a cell | removing it removes that section, and its text joins the next; moved to the body it starts one | the paragraph is the break | `test/docx/model/sections_test.dart` ("removing a paragraph with a break removes its section", "a break moved out of a cell starts a section") |
| A section's values | a nullable get and set, in points; a child the model cannot type reads `null` and stays; `titlePage` is a `bool` and `false` removes the child | D2 Ruling 2, Ruling 15 | `test/docx/model/sections_test.dart` ("reads every value", "every value is set and reads back", "a child the model cannot type reads null and stays", "titlePage set to false removes the child"), `test/docx/section_property_codecs_test.dart` |
| A value out of range | `DocxPageSize`, `DocxPageMargins`, `DocxColumns`, `DocxPageNumbering` and `DocxLineNumbering` throw `RangeError` or `ArgumentError` when built; top and bottom margins are signed, the rest are not | a programmer error, and `w:pgMar` allows it | `test/docx/section_property_codecs_test.dart` ("a page size out of range throws RangeError", "margins: top and bottom are signed, the rest are not", "columns", "page and line numbering") |
| A value the file holds and the model cannot read (`w:pgSz w:w="abc"`, a `w:pgMar` without a side, `w:pgNumType w:fmt="chicago"`) | reads `null`, stays as read; a paper code and the chapter attributes of `w:pgNumType` stay beside a value that reads | data problems do not throw | `test/docx/section_property_codecs_test.dart` ("refuses what it cannot type", "keeps the paper code as read", "refuses what it cannot type, keeps the chapter attributes") |
| A set | writes one element, at its place in `sectPrOrder`, among the children the model does not type; every other child stays as read; setting what a member reads records nothing; a set on a section of a break is written in its paragraph; one change, whose undo restores the part's bytes | a change touches only what it changes | `test/docx/model/sections_test.dart` ("setting pageSize changes only w:pgSz", "a set on a section of a break is written in its paragraph", "titlePage set to what it reads records nothing", "a set is one change, and the save writes the model", "undoing a set restores the bytes of the part", "a failed edit leaves the section as it was") |
| What repeats in a `w:sectPr` | `w:headerReference` and `w:footerReference` are repeated children of `ContainerSchema`, read in the order of the file, not grouped by name; adding one writes the others byte for byte, and undo restores them | Ruling 7; Word mixes the two | `test/docx/container_order_test.dart`, `test/docx/model/sections_test.dart` ("references keep the order of the file, as Word mixes them", "references survive an edit, and any other child too") |
| `textWidthPt` | the page's width less the side margins and the gutter; `null` when the page or a margin does not read | `addTable` needs it | `test/docx/model/sections_test.dart` ("textWidthPt takes the side margins and the gutter off the page", "textWidthPt is null when the page or a margin is unread") |
| `addSection({start})` | ends the last section after the last block: a last paragraph with no break takes it; otherwise, after a table, a break, an opaque block or in an empty body, an empty paragraph is added for it; no block is added after the break | Ruling 8: as Word does | `test/docx/model/sections_test.dart` ("the last paragraph takes the break", "a body ending in a table gets an empty paragraph for the break", "a last paragraph that has a break gets one after it", "an empty body or an opaque block gets an empty paragraph") |
| A held section | the `DocxSection` that was last moves to the paragraph, stays that section and stays editable; a new one becomes last | a caller's handle means what it meant | `test/docx/model/sections_test.dart` ("a held section keeps its values and stays editable", "a set on the held section is recorded after the swap", "two sections add up, each section held") |
| The new last section | copies the page size, margins, columns, line and page numbering, vertical alignment and the kept `w:docGrid` as they stand, without references (it inherits), `titlePage` and the numbering's `start`; `start` is its type, by default `nextPage`; a page numbering of only a start, or one the model cannot type, is not copied | Ruling 8: as Word does | `test/docx/model/sections_test.dart` ("the new section copies what Ruling 8 lists, and nothing else", "a page numbering of only a start is not copied", "a page numbering the model cannot type is not copied", "the copy takes the values set since the file was read") |
| A last section of no values | still writes its break in the paragraph | a section in a paragraph is the break | `test/docx/model/sections_test.dart` ("a last section of no values still writes its break") |
| `addSection` undone, or failing | undo restores the part's bytes and redo the sections; a failure takes everything back | one transaction | `test/docx/model/sections_test.dart` ("undo restores the bytes of the part, and redo the sections", "a failure takes everything back") |
| A paragraph with a break of another document | `insertBlock` and `replaceBlockAt` throw `ArgumentError`, whoever made the break; in its own body it goes back; in a cell it stays as read and starts no section; a block still in a body throws `StateError` first | Ruling 10: its `r:id`s mean nothing here | `test/docx/model/sections_test.dart`, group "a section break between documents" |
| `addTable` on a body or a story | shares the last section's `textWidthPt` less 10 twips; 9062 twips when that does not read or gives a column no twip; `columnWidthsPt` still wins; a table made by hand or nested stays as it was | Ruling 12, as a ledger ruling corrects it: Word's Insert Table on A4 pins 4531 a column of two, not 4536 | `test/docx/model/sections_test.dart`, group "addTable", `test/docx/model/header_footer_read_test.dart` ("addTable shares the width of the last section") |
| A new document's section | read as typed from the same bytes; `blankDocumentBytes` does not change | Ruling 16 | `test/docx/blank_document_oracle_test.dart` ("the section equals the section of blank.docx"), `test/docx/model/sections_test.dart` ("a new document has one A4 section with the margins of the file") |

### Headers and footers

| Case | Behaviour | Why | Test |
|---|---|---|---|
| The six getters | give the section's own story, else the nearest previous section's by type (`isInherited`), else an empty one; the same getter gives the same story; a read creates nothing | Ruling 5: reading never changes a file | `test/docx/model/header_footer_read_test.dart` ("read the story of each type", "the same getter gives the same story, also for no reference", "the nearest previous section wins, by type"), `test/docx/model/header_footer_edit_test.dart` ("a read of the getters creates nothing") |
| Section 2 of 3 gets a footer | section 1 has none, section 3 inherits it; a section added later inherits it too; an edit of an inherited story reaches every section using it | Word's "Link to Previous" | `test/docx/model/header_footer_edit_test.dart`, group "sections around a footer (Review Focus 1)" |
| A section that left the document | keeps only its own story | it has no previous section | `test/docx/model/header_footer_read_test.dart` ("a section that left the document keeps only its own story") |
| A story's part | loads on the first access to `blocks` or an edit; reading saves the bytes of the part, and leaves its relationships part unread; a story keeps its own relationships; a damaged relationships part opens, reads and saves | layer 1 of decision 0009 | `test/docx/model/header_footer_read_test.dart`, group "reading" |
| A story that cannot be read | `blocks` throws `DocxReadException` naming the part, as for a root that is not `w:hdr` or `w:ftr`; nothing is loaded, the others read, and a save copies it | as the styles part | `test/docx/model/header_footer_read_test.dart` ("a broken story leaves the others readable", "a root that is not w:hdr throws as styles does", "a root that is not w:ftr throws for a footer") |
| What a story holds | the blocks of the body, tables and lists too, matched by namespace; a `w:sectPr` in a story starts no section; an empty root reads no blocks and saves as read | one story layer | `test/docx/model/header_footer_read_test.dart` ("tables, lists and other blocks type as in the body", "a break in a story starts no section", "an empty root reads no blocks and saves as read", "elements match by namespace, not by prefix") |
| References that count | only `default`, `first` and `even`; the first of a type that names a story is the section's; one of an unknown type, with no `r:id`, or whose id names no internal relationship of the header or footer type to a part in the package counts as none and is kept; a broken first leaves the next of its type | Ruling 7, Review Focus 2; a file's broken reference is not an error | `test/docx/model/header_footer_read_test.dart`, group "references that name nothing" |
| The part's type | must match the kind in relationship type and content type, or be generic XML; a generic part named as a header and as a footer counts as none for both | a tighter reading of Ruling 7, deterministic | `test/docx/model/header_footer_read_test.dart` ("a part of the generic XML type is read", "a generic part named as a header and as a footer") |
| One part named by several references | one story object; an edit reaches every reference | they are one part | `test/docx/model/header_footer_read_test.dart`, group "one part named by several references" |
| The first block of an empty story | gives the section a reference in the same transaction; the part and relationship come at save, with the first number `n` no part or target has, in the order of the sections, under an id no relationship or reference has, a reference of a `w:sectPr` in a cell included; two saves give the same names | Ruling 5; a part is created at save, as the styles part | `test/docx/model/header_footer_edit_test.dart`, group "a new story" |
| A new reference's prefix | `r` where it binds relationships, else the one the part binds, else one declared on the element; what the `w:sectPr` or a paragraph around it binds counts | a kept `r` may mean something else | `test/docx/model/header_footer_edit_test.dart`, group "the prefix of a new reference" |
| A section with no `w:sectPr` of its own | gets one when a reference goes in, and has none after an undo | Ruling 9 | `test/docx/model/header_footer_edit_test.dart`, group "a section with no w:sectPr of its own" |
| `ownHeader` and `ownFooter` | give the section a new empty story in place of an inherited one, its own when it has one; replace a reference that names nothing, of its type, as an edit does; keep one of an unknown type; left empty, the story is written as one empty paragraph | Ruling 5, Ruling 7 | `test/docx/model/header_footer_edit_test.dart`, group "ownHeader and ownFooter" |
| `removeHeader` and `removeFooter` | drop the references of the type that name a story, so the section inherits again; a broken reference stays; the part and its relationship stay in the package; with no own reference nothing is recorded; a story not yet made is not created; nothing is turned off | Ruling 5; §4.2 keeps parts | `test/docx/model/header_footer_edit_test.dart`, group "removeHeader and removeFooter" |
| A first story's first content, or `own…` of one | sets `titlePage`, in the same transaction, on every section owning the story (`own…` only on its section), never on one that inherits it; a story of only empty paragraphs has no content yet, as Word writes one; more content sets nothing | Ruling 6 | `test/docx/model/header_footer_edit_test.dart`, group "a first story turns itself on (Ruling 6)" |
| A story's last block | written with `<w:p/>` after it when the last is not a paragraph, an empty story too, except a story whose blocks are all as read; undo keeps it as read | Ruling 11: Word requires a paragraph last | `test/docx/model/header_footer_edit_test.dart`, group "a story ends in a paragraph (Ruling 11)" |
| A paragraph with a break going in a story | `ArgumentError`, wherever it comes from | a story has no sections | `test/docx/model/header_footer_read_test.dart` ("a paragraph with a section break cannot go in a story", "a break of another document cannot go in a story either") |
| A save with a story left without table rows, or a section out of the document | the empty table stops the save by location and creates nothing; a section that left creates no part; a break moved to a cell writes no reference without a part | a save is all or nothing | `test/docx/model/header_footer_edit_test.dart` ("a table left without rows stops the save, and creates nothing", "a section that left the body creates no part", "a break moved to a cell writes no reference without a part") |
| Undo and failure | a failed first header and `addSection` leave no part, relationship or `titlePage`; a save after an undo means what the input did; a redo gives the story and its reference back; an undo after a save leaves the part, with no reference | Review Focus 4 | `test/docx/model/header_footer_edit_test.dart`, group "undo and failure (Review Focus 4)" |
| A story's warnings | forbidden characters, a missing style and a missing list are reported at save, at a location starting with the part's name; a list added in a story is saved | Ruling 14 | `test/docx/model/header_footer_read_test.dart`, group "the save warnings of a story" |
| The owner's Word files | `features.docx` reads its header and saves it as read; reading every section and story of the owner files saves as read | the fidelity claim rests on Word's files | `test/docx/owner_files_test.dart` |

### Even and odd pages

| Case | Behaviour | Why | Test |
|---|---|---|---|
| `evenAndOddHeaders` read | `false` when the part or the child is absent; the bare child, `1`, `true` and `on` read `true`; `0`, `off`, `false`, a value it cannot parse and a child twice read `false`, and stay | Ruling 13; §4.8 | `test/docx/settings_part_test.dart`, group "reading" |
| `evenAndOddHeaders` set | `true` writes `<w:evenAndOddHeaders/>` at its schema position, replacing what was read; `false` removes the child; every other child stays as read and in order; a value it already reads changes nothing; one undoable edit | Review Focus 5 | `test/docx/settings_part_test.dart`, group "setting" |
| `settings.xml` in the package | a read that changes nothing saves the bytes; a document without the part gains one holding only the child; set then unset adds none; a broken part or a wrong root throws naming the part and is saved as read | through `RelatedPart`, as styles | `test/docx/settings_part_test.dart`, group "the part in the package", `test/docx/settings_owner_test.dart` |
| An even story's first content, or `own…` of one | sets `evenAndOddHeaders` in the same transaction; removing the story turns nothing off; a broken settings part makes the edit throw, and nothing changes | Ruling 6 | `test/docx/settings_part_test.dart`, group "an even story turns it on" |

### D4 fixtures and tools

| Case | Behaviour | Why | Test |
|---|---|---|---|
| The three D4 fixtures (`d4_sections`, `d4_headers`, `d4_fields`) | build the same bytes every time with no warnings, round-trip with everything read and encoded, and hold what the plan says: four sections with a Letter one last, six stories in section one with one section inheriting and one with its own, and five fields | the validation starts from them | `test/docx/round_trip_test.dart`, group "D4" |
| No fixture ends in a table or a section break | a fixture's last block is a plain paragraph | LibreOffice's text export of a table last never ends, and the model adds no block after a break; `tool/write_table_last.dart` writes `d4_break_last.docx` for the Word check alone | `test/docx/round_trip_test.dart` ("no fixture ends in a table or a section break"), `test/tool/docx_tools_test.dart` ("writes a document whose last block carries the section break") |
| `<name>.stories.txt` | written for a fixture with a `DocxFixture.headerFooterText`: per section the stories it shows, by `docxStoriesText`, each field as `{NAME}`; `tool/compare_resaved_docx.dart` compares it with LibreOffice's re-save | a re-save keeps what a page shows, not the stories | `test/tool/text_compare_test.dart`, group "docxStoriesText", `test/tool/docx_tools_test.dart` ("writes the text of the stories, only for those that have it") |
| LibreOffice's re-save | `docxResavedText` leaves out the empty paragraph that only carries a break and a page break at the edge of a paragraph, as LibreOffice adds them; so a section's values in the re-save are not compared, and the round trip and the SDK cover the model | the text and the stories are what a re-save keeps | `test/tool/text_compare_test.dart`, group "docxResavedText" |
| Sections and stories in `tool/round_trip_docx.dart` | every section value and story is read, `w:sectPr`'s children compare in any order, and the header and footer parts are encoded from the model (`encodedStoryDifferences`) | a story nothing changed is saved as read, so the encoder needs its own check | `test/tool/docx_serialize_test.dart`, group "sections and stories", `test/tool/docx_tools_test.dart` ("round-trips the D4 fixtures: exit 0, and encodes their stories") |
| `tool/edit_docx.dart` on sections | adds a footer paragraph `Page ` + `PAGE` + ` of ` + `NUMPAGES` to the last section's story, adds a next page section, landscape A4, with the table, heading and list in it, and checks them read back | CI validates the edited files with the Open XML SDK | `test/tool/edit_docx_test.dart`, group "sections" |
| The fuzz | seeds 1 to 4 at 600 cases each: `sections_by_hand` (every section child, six stories, broken references and fields) and the D4 fixtures join the corpus; each section's values, its stories with their fields and `evenAndOddHeaders` are read, every field's `resultText` is set, a footer paragraph and a section are added, and only a `DocxReadException` from a part that cannot be read may come out | the typed exception is the contract | `test/docx/fuzz_test.dart` ("every part name is mutated in some corpus entry", "mutated files raise only DocxReadException") |

### Document properties

The numbers are the plan's Rulings (`2026-11-08-phase-4-d5-pictures`); the
letters are rulings its ledger made while the tasks ran.

| Case | Behaviour | Why | Test |
|---|---|---|---|
| One type for both formats | `OfficeProperties` (it was `XlsxProperties`), with `revision` (`cp:revision`) and `application` (`Application`); its value class, writers and state live in `lib/src/common/`, and a small `PropertiesSource` gives each format its package, bounds and failures; the workbook's behaviour is unchanged but the name | Ruling 1; §4.12: never two copies | `test/common/properties_test.dart`, `test/common/properties_parts_test.dart`, `test/xlsx/model/properties_test.dart` |
| `revision` and `application` | written in Excel's order; a negative revision throws `ArgumentError`; set to `null` they remove their child, as every other field does; a new workbook and `XlsxWriter` still write `application ?? 'jet_office'`, the model only what the caller sets | Ruling 1, ledger Ruling C | `test/common/properties_test.dart`, group "revision and application"; `test/xlsx/model/properties_test.dart`, group "revision and application" |
| Custom properties | read and set in a document too, by the workbook's rules | Ruling 2: a DOCX-only subset would be a second copy | `test/docx/document_properties_test.dart` ("custom properties are read and set") |
| Finding the parts | core, app and custom each through its package relationship, never by name; they load on the first read of `properties` | Ruling 3 | `test/docx/document_properties_test.dart` ("a part is found by its root relationship, not its name", "reads the typed values of core and app") |
| A part that is not XML | `properties` throws `DocxReadException`; `open` does not | a part breaks when it first loads | `test/docx/document_properties_test.dart` ("a part that is not XML throws from properties, not from open") |
| A value the model cannot read (a `cp:revision` that is not a number, a bad date) | reads `null`, stays in the file as read, and is reported once per save as `propertyValueInvalid`, the element's name as detail | Ruling 3; data problems warn | `test/docx/document_properties_test.dart` ("a value that cannot be read reads null, is kept and warns once"), `test/docx/warnings_test.dart` ("propertyValueInvalid names the part and the element in every language") |
| An unchanged save | every properties part saved as read, byte for byte, also after a read; a loaded part is not re-encoded until a set changes it | Ruling 3, layer 1 of decision 0009 | `test/docx/document_properties_test.dart` ("an opened file saved unchanged after reading is byte equal"), `test/common/properties_parts_test.dart` ("encodeOnLoad: false keeps a loaded part as read until a swap", "a swap that changes core leaves app and custom as stored") |
| A set | one change of the log, re-encoding only the children that differ; every other child of the part stays as read; a value equal to what is read sets nothing | Ruling 3 | `test/docx/document_properties_test.dart` ("setting title changes only that child of core.xml") |
| A new document | reads `OfficeProperties()` and saves no `docProps/`, so `DocxDocument()`'s bytes stay; once a property is set, core and app are added at save with their root relationships and content types; no clock: `created` and `modified` only when given | Ruling 4 | `test/docx/document_properties_test.dart` ("a new document reads empty properties and saves no docProps", "a new document with properties set gets core and app"), `test/docx/blank_document_oracle_test.dart` |
| A value XML cannot hold | `ArgumentError` before anything changes | programmer error | `test/docx/document_properties_test.dart` ("a bad value throws and changes nothing") |
| A part whose root is not a properties part | reads no values and is kept; a set that would change a value it holds throws `DocxReadException` (`malformedXml`) naming it, and nothing changes (a workbook throws `StateError`) | ledger Ruling P: in a document it is the file's content | `test/docx/document_properties_test.dart` ("a part whose root is not a properties part throws a read exception naming it when a value of it is set") |
| Undo and failure | a transaction that throws leaves no part and no relationship; an undo leaves none and a redo brings them; the undo of a change to an opened file restores its bytes | Review Focus 3 | `test/docx/document_properties_test.dart` ("a transaction that throws leaves no part and no relationship", "an undo leaves no part and no relationship, a redo brings them", "the undo of a change to an opened file restores its bytes") |
| The owner's Word file | `blank.docx` reads the properties Word wrote | the reading rests on Word's files | `test/docx/document_properties_owner_test.dart` |

### Pictures

| Case | Behaviour | Why | Test |
|---|---|---|---|
| What is a picture | a `w:drawing` holding one `wp:inline` whose one `a:graphicData` holds one `pic:pic` with a numeric `pic:cNvPr` id; an anchor, a chart, a shape, a group, `mc:AlternateContent`, a second graphic and a `pic:cNvPr` id that is missing or not a number stay `DocxOpaqueRunContent` | Ruling 5, ledger Ruling K | `test/docx/model/pictures_read_test.dart` ("the Word-like sample: inline typed, anchored stays opaque", "anchors, charts and several graphics stay opaque", "a second a:graphic or a:graphicData makes the drawing opaque") |
| A read picture's values | `widthPt` and `heightPt` from `wp:extent` (12,700 EMU to the point; `null` when not a non-negative whole number), `name` and `description` from `wp:docPr`; text `''`; written as read | Ruling 5 | `test/docx/model/pictures_read_test.dart` ("size, name, description and image of a hand-built picture", "a size that is not a non-negative whole number reads null", "a picture has no text and a GIF reads with no format") |
| `image` | the media part its `r:embed` names in the relationships of its own part; `null` for no `r:embed` (a linked picture), a missing, external or wrongly typed relationship, a missing part, or relationships that cannot be read; a GIF reads with no format; pictures of one media part share one `OfficeImage` | Ruling 5, Review Focus 2 | `test/docx/model/pictures_read_test.dart` ("no r:embed, a missing part, a link, a wrong type, external", "two pictures of one media part give the same image") |
| A picture in a header or footer | reads its image through the story's relationships, peeked and never marked for rewriting, so the part's bytes stay; a damaged relationships part reads `image` `null` | Ruling 12 | `test/docx/model/pictures_read_test.dart` ("a picture in a header reads through the header rels, untouched", "a damaged rels part of a header reads image null") |
| A read picture edited | not in D5: setting its run's text removes it, and an undo restores it | Ruling 5 | `test/docx/model/pictures_read_test.dart` ("setting the text of its run removes a picture; undo restores") |
| `addPicture` | a run holding a new picture, in the body, a cell, a header or a footer; PNG and JPEG only (`checkImage`, `ArgumentError` otherwise); a `name` or `description` XML cannot hold throws `ArgumentError`; both are written on `wp:docPr` and the name on `pic:cNvPr` | Ruling 6 | `test/docx/model/pictures_edit_test.dart` ("adds a media part, a png default, a relationship and an inline", "a name and a description are written on docPr and cNvPr", group "bad arguments throw and change nothing") |
| A built picture's size | its pixels at 96 dpi (0.75 pt each); one side given scales the other by the image's ratio; both given are used as given; a side given must be finite, above 0 and at most 1584 pt (`RangeError`), and so must a side computed from one given; with no size, a side over 1584 pt scales the picture down by its ratio | Ruling 6, ledger Ruling L: Word scales a large picture too | `test/docx/model/pictures_edit_test.dart` ("one side given scales the other; both are used as given", "a large image with no size is scaled to fit 1584 pt", group "bad arguments throw and change nothing") |
| The media part | shared with any part of the package holding the same image (identity, then equal bytes), the file's own media included; else `word/media/image<n>.png` or `.jpeg` with the next free number, past every name a relationship targets (a dangling one too) and with a `Default` content type for its extension | Ruling 7, ledger Ruling M: a dangling reference must not come to show the new image | `test/docx/model/pictures_edit_test.dart` ("equal bytes in another OfficeImage share the media part", "the image a file holds is shared, through its relationship", "a file whose media has image3.png gets image4.png", "a name a dangling relationship targets is skipped", "a JPEG takes .jpeg and its own default", "an unreadable relationships part does not block a picture") |
| The image relationship | one per part and media part, reused by every picture of that part; the body and a body cell share one | Ruling 7, ledger Ruling N | `test/docx/model/pictures_edit_test.dart` ("body, a header cell and a footer: one media part, three rels", "the body and a body cell share one relationship") |
| The `wp:inline` written | `writeInlineDrawing`, ported from Quds (see "Port map"): `wp:docPr` and `pic:cNvPr` share the id, `descr` only when given, `r:embed` only with an id, and `wp`, `a`, `pic` and `r` declared only where the bindings above lack them or bind them elsewhere; what it writes reads back as a picture | Ruling 6 | `test/docx/drawing_test.dart`, `test/docx/model/pictures_edit_test.dart` ("a, pic and wp are declared where the root does not") |
| Saves | a picture in a header saved twice gives the same file; save, picture, save, undo, save gives the first file again; a removed picture leaves no media part at the next save; a transaction that throws leaves no media, type or relationship | Ruling A, Review Focus 1 and 3 | `test/docx/model/pictures_edit_test.dart` ("a picture in a header saved twice gives the same file", group "undo and saves") |
| A picture built in a paragraph of no document | saves once it goes in one, and then in a second document as well; it reads back typed with its image | Ruling 13 | `test/docx/model/pictures_edit_test.dart` ("a picture built in a paragraph of no document saves once in one", "a picture reads back typed, with its image", "a built picture works in a second document") |

### Hyperlinks

| Case | Behaviour | Why | Test |
|---|---|---|---|
| What is a hyperlink | every `w:hyperlink` that is a direct child of a paragraph; it writes its start tag as read and its inlines; a link inside another inline stays inside that opaque inline, and a link in a link stays opaque in it | Ruling 8 | `test/docx/model/hyperlinks_read_test.dart` ("the Word-like sample reads its external link", "bookmarks in a link are typed; a nested link stays opaque") |
| Its inlines | read by a paragraph's rules: runs, bookmarks, opaque inlines and fields grouped inside it alone; a field crossing its edge stays runs; a link in a field's result is one inline of that result | Ruling 8 | `test/docx/model/hyperlinks_read_test.dart`, group "fields" |
| `url`, `anchor`, `tooltip`, `text` | `url` is the external target of its `r:id` in its part's relationships, else `null` (an id naming nothing, an internal target or another type); `anchor` and `tooltip` are its attributes; `text` its inlines' text | Ruling 8, Review Focus 2 | `test/docx/model/hyperlinks_read_test.dart` ("an anchor link reads its anchor and tooltip, and no url", "an r:id naming nothing, an internal or another type reads null"), `test/docx/owner_files_test.dart` ("builtins.docx reads the url of its external link") |
| A link in a header or footer | reads its url through the story's relationships, which stay as read; a damaged relationships part reads `url` `null` | Ruling 12 | `test/docx/model/hyperlinks_read_test.dart` ("a link in a footer reads its url; the footer rels stay as read", "a damaged relationships part of a story reads url null") |
| The runs of a link | ordinary runs: setting one's text or properties saves only that run changed, one edit that undoes; a warning location `r[j]` counts the runs inside links | Ruling 9, ledger Ruling F, as D4 counts runs inside fields | `test/docx/model/hyperlinks_read_test.dart`, group "editing the runs of a link" |
| The owner's Word files | `long.docx` keeps its `PAGEREF` fields typed in its hyperlinks and its `TOC` as runs | the reading rests on Word's files | `test/docx/owner_files_test.dart` ("long.docx keeps its TOC as runs, its PAGEREFs typed in hyperlinks") |
| `addHyperlink` | exactly one of `url` and `anchor`; one run in the character style `Hyperlink` through `ensureStyle` (Word's definition added on demand, `Kpr` in a Turkish file); `w:tooltip` when given; `w:history="1"` as Word writes it | Ruling 9, ledger Ruling I | `test/docx/model/hyperlinks_edit_test.dart` ("saves a relationship of the main part and the Hyperlink style", "a tooltip is written as w:tooltip", "in a Turkish file the run takes Kpr and no style is added", "links to a built bookmark with w:anchor and no relationship") |
| Bad arguments | both targets or neither, a `url` that is not an absolute URI (`Uri.tryParse`, a scheme), or holds whitespace, a control character or one XML forbids, an empty `anchor`, an `anchor` or `tooltip` XML cannot hold: `ArgumentError`, nothing changes | Ruling 9, ledger Ruling J | `test/docx/model/hyperlinks_edit_test.dart`, group "bad arguments" |
| An external link's relationship | added at save from the part the link is in (`TargetMode="External"`), one per link even for one URL, as Word writes them; under an id no reference of the file names; a link in a cell or a nested cell is related from the main part, one in a header or footer from its own relationships | Ruling 9, Ruling 12 | `test/docx/model/hyperlinks_edit_test.dart` ("two links to one URL make two relationships, as Word does", "a new id takes none a reference of the file names", "a link in a table cell is related from the main part", "a link in a nested table cell is related from the main part", group "a link in a header or footer") |
| Saves | two saves give the same file and store no id; a removed link leaves no relationship at the next save; save, link, save, undo, save gives the first file; relationships a save adds are taken back after it | Ruling A | `test/docx/model/hyperlinks_edit_test.dart` ("saving twice gives the same file and stores no id", "a removed link leaves no relationship at the next save", group "saves that add and take back relationships") |
| A link built in a story whose relationships part cannot be read | the save throws `DocxReadException` naming that part and adds nothing | ledger Ruling H: a call that first loads a broken part throws it | `test/docx/model/hyperlinks_edit_test.dart` ("a save that fails on a broken footer rels part adds nothing") |
| Undo and failure | a transaction that throws, or an undo, leaves no relationship and no style | Review Focus 3 | `test/docx/model/hyperlinks_edit_test.dart`, group "undo" |
| A link built in a paragraph of no document | keeps `Hyperlink` until it goes in, then resolves there (adding Word's definition when the document has none); works in a second document after a save; a read link moved keeps its `r:id` (a known gap) | Ruling 13, ledger Ruling G | `test/docx/model/hyperlinks_edit_test.dart`, group "a link built in a paragraph of no document"; `test/docx/model/hyperlinks_read_test.dart` ("a link moved to another document edits and resolves there") |

### Bookmarks

| Case | Behaviour | Why | Test |
|---|---|---|---|
| What is a bookmark | `w:bookmarkStart` and `w:bookmarkEnd` that are direct children of a paragraph or of a typed hyperlink: `DocxBookmarkStart` (`id`, `name`) and `DocxBookmarkEnd` (`id`), with no text; elsewhere (between blocks, in a table row) they stay opaque, in place; nothing pairs them at read | Ruling 10 | `test/docx/model/bookmarks_test.dart` ("a start and an end read typed, the text unchanged", "a block-level bookmark stays an opaque block", "a bookmark inside a field is kept in place") |
| A read mark's values | an id that is not a number reads `null`, an absent name reads `''`; both written as read | data problems do not throw | `test/docx/model/bookmarks_test.dart` ("a bad id reads null, an absent name reads empty, both as read") |
| `addBookmarkStart` and `addBookmarkEnd` | the end takes its start's id at save, in the same paragraph or another, also when it comes first in the document; an end of a read start takes that start's id; two bookmarks take two ids; an end whose start is in no part is written | Ruling 11 | `test/docx/model/bookmarks_test.dart` ("a start and an end in the next paragraph share one id", "an end written before its start in the document pairs with it", "two bookmarks get two ids, an end of a read start its id") |
| A name breaking Word's rules | repaired when added (`repairBookmarkName`): every character but a letter, digit or `_` becomes `_`, a first character that is not a letter gets `B` in front (`_` too, so a built name is never one of Word's hidden ones), the result is cut to 40; every save reports `bookmarkNameRepaired` with the name given; a name that follows them is not reported; a name already used is not repaired | Ruling 11, ledger Ruling E | `test/docx/model/bookmarks_test.dart` ("a name is repaired, cut, and reported by every save", "a name that follows the rules is not reported", "repairBookmarkName") |
| Undo and placement | an undo removes both marks and a redo puts them back; a mark sits in one paragraph once and goes with `removeInlineAt` | one transaction, one parent | `test/docx/model/bookmarks_test.dart` ("undo removes both marks, redo puts them back", "a mark sits in one paragraph once, and goes with removeInlineAt") |

### Ids, relationships and media at save

| Case | Behaviour | Why | Test |
|---|---|---|---|
| A new `wp:docPr` id | one more than the highest found in the original bytes of every story part (document, headers, footers, footnotes, endnotes, comments, and a part of the generic XML type the main part names as a header or footer) and in pictures built before it; 1 with none | Ruling 7, Review Focus 4 | `test/docx/save_ids_test.dart`, group "drawing and bookmark ids"; `test/docx/model/pictures_edit_test.dart` ("a new docPr id goes past one held in a footer of the file") |
| A new bookmark id | the same rule, from 0 with none; an id of eleven digits is still reserved; a story that breaks keeps the ids found before the break; the scan stops at the end of the root and loads no part as a model | Ruling 11, §4.5 | `test/docx/save_ids_test.dart`, group "drawing and bookmark ids"; `test/docx/model/bookmarks_test.dart` ("a built mark belongs to a document that holds its id elsewhere") |
| A new relationship id | avoids every `r:id`, `r:embed` and `r:link` of the part's original bytes, so a dangling reference stays dangling; a story part gets its own, avoiding its own references | Ruling 12 | `test/docx/save_ids_test.dart`, group "relationship ids" |
| What a save adds | taken back once the file is written: relationships (an entry never parsed is copied as read again, in its place), media parts and content types, so the model is unchanged and a second save adds none twice | Ruling A | `test/docx/save_ids_test.dart` ("restoreRelationships takes back every one added, as read"), `test/opc/package_test.dart`, group "markRelationships" |
| Peeking at a story's relationships | reads them without marking the part for rewriting, so the bytes stay; sees what was parsed or added since; a malformed part throws and stays as read | Ruling 12 | `test/opc/package_test.dart`, group "peekRelationships" |

### D5 fixtures and tools

| Case | Behaviour | Why | Test |
|---|---|---|---|
| The three D5 fixtures (`d5_pictures`, `d5_links`, `d5_properties`) | build the same bytes every time with no warnings and round-trip with everything read and encoded; `d5_pictures` holds the PNG at its pixel size, the JPEG 144 pt wide in a cell and the PNG as a header logo sharing the body's media part; `d5_links` a heading in the bookmark `Overview`, an external link with a tooltip, an internal link to it and a footer link; `d5_properties` every core field, the company and the application | the validation starts from them; the Word check looks for these | `test/docx/round_trip_test.dart`, group "D5" |
| `<name>.stories.txt` of `d5_pictures` and `d5_links` | the header text beside the logo and the footer link's text, compared with LibreOffice's re-save | a re-save keeps what a page shows | `test/docx/round_trip_test.dart` ("every D5 fixture builds the same bytes and no warnings, and round-trips with everything read and encoded"), `test/tool/docx_tools_test.dart` ("writes the text of the stories, only for those that have it", "round-trips the D5 fixtures: exit 0") |
| Pictures, links, bookmarks and properties in `tool/round_trip_docx.dart` | every picture's size, name, description and image, every link's target and inlines, every bookmark and every property field are read, and the properties parts are encoded from the model (`encodedPropertiesDifferences`); a part that is not a properties part is not encoded, and a broken one is one line naming it | a part nothing changed is saved as read, so the encoder needs its own check | `test/tool/docx_serialize_test.dart`, group "D5"; `test/tool/docx_tools_test.dart` ("encodes the properties parts: what the model drops is named") |
| `tool/edit_docx.dart` on D5 | adds, in the new section, a paragraph with a 4 by 2 pixel PNG (3 by 1.5 pt), an external link and an internal link to the bookmark `Model_edit` around the heading, sets the title and keeps every other property; checks each reads back; the allowed changed parts grow by the core part (and `_rels/.rels` and the extended part when the file lacks a core part), at most one new media part, and relationships of the main part of the hyperlink and image types only | CI validates the edited files with the Open XML SDK | `test/tool/edit_docx_test.dart`, group "pictures, links, bookmarks and properties" |
| The fuzz | seeds 1 to 4 at 750 cases each: the D5 fixtures and `drawings_by_hand` (inline, anchored, linked and broken pictures, broken links, bookmarks with bad ids, a header with a picture and a link, properties that cannot be read) join the corpus, and the values of the properties parts are mutated as element text as much as attributes; every picture, link, bookmark and property is read, the properties are set, a picture, a bookmark pair and two links are added to a body paragraph and to the last footer, and the saved file must hold them | the fixed seeds must mutate every part name of the corpus: 600 left one footer part of `d4_headers` unmutated | `test/docx/fuzz_test.dart` ("drawings_by_hand reads its pictures, links, bookmarks and properties", "values of the core, app and custom properties parts are replaced", "every part name is mutated in some corpus entry") |

### The list export

A list written by `DocxListExport` follows these rules. Tests are in
`test/docx/list_export_test.dart` unless named otherwise.

| Case | Behaviour | Why | Test |
|---|---|---|---|
| A list's columns and fields | `DocxListColumn` and `DocxListExport` compare by value over every field, print every field in `toString`, keep the documented defaults and copy the columns into an unmodifiable list; the constructors check nothing | the checks belong to `writeTo` and `toDocx`, where the page is known | groups "DocxListColumn" and "DocxListExport" ("== and hashCode cover every field", "toString names every field", "has the documented defaults", "the columns are unmodifiable and copied") |
| No columns, more than `maxTableColumns`, an empty header, a header repeated ignoring case (Turkish case included), a width not finite or not above 0 | `ArgumentError` named `columns`, `columns[i].header` or `columns[i].widthPt`, before the document changes | a programmer error in the caller's own call | group "checks" ("no columns", "too many columns", "an empty header", "a header that repeats an earlier one ignoring case", "headers that differ only in Turkish case clash", "an infinite width", "a width of $width") |
| A number format or a date format the formatter cannot read | `ArgumentError` named `columns[i].numberFormat` or `dateFormat`, found by formatting `0` and looking for `FormatWarning.invalidCode`; a readable code passes. Without the check an unreadable date code would show the serial number | a code is the caller's, and a cell that shows the wrong thing silently is worse than a throw; no warning code is added | group "checks" ("a number format that cannot be read", "a date format that cannot be read", "a date format that can be read passes the checks") |
| A logo height not finite or not above 0, a header shading that is not six hex digits (either case passes) | `ArgumentError` named `logoHeightPt` or `headerShading` | as above | group "checks" ("a logo height of 0", "a logo height that is not finite", "a header shading that is not six hex digits", "a header shading in either case passes the checks") |
| The page | A4 portrait and Word's blank-document margins (70.85 pt; header and footer 35.4 pt) when none is given; a given page size and margins are set as given, on the last section | the model's defaults are Word's | group "page" ("the defaults are A4 portrait and Word's blank margins", "a given page size and margins are set as given") |
| The page header | One paragraph: the logo `logoHeightPt` high, a tab, the title in bold, a tab, the date as text, with a centre tab stop at half and a right one at the whole text width of the page set; a missing piece leaves its tab; the date without a code shows as the locale's short date | one line with the three pieces in their places | group "page" ("the header holds the logo, a tab, the title, a tab and the date", "the tab stops follow the text width of the page", "absent pieces leave their tabs", "the date shows in the locale's short date without a code") |
| No logo, title or date | the section's own default header is removed and none is made (an earlier section's, if any, is then inherited); the footer is always written | an empty header part would only take room | group "page" ("with no logo, title or date there is no own header") and "in an opened document" ("with nothing for the header the section's own is dropped") |
| The footer | One centred paragraph: `footerBefore`, a `PAGE` field, `footerMiddle`, a `NUMPAGES` field and `footerAfter`, each text left out when empty | `Page 2 of 3` and `Sayfa 2 / 3` | group "page" ("the footer is centred: Page, PAGE, of, NUMPAGES", "footer texts are replaced and empty ones left out") |
| Writing into an opened document | The last section's header and footer are replaced; a title page is turned off whether or not a header is written, so page 1 shows the list's header and footer; the first-page stories are left alone | a first-page header would hide the list's header on page 1 | group "in an opened document" ("the last section's header and footer are replaced", "a title page is turned off so page 1 shows the header", "a title page is turned off with no header to write too") |
| Columns | A last section of more than one text column (equal or unequal) is set to one, keeping the space between columns; a section of one column, or none, is left as it is | a table in a narrow column of a newspaper section would be squeezed | group "in an opened document" ("a section of several columns is set to one", "a section of unequal columns is set to one", "one column, or none, stays as it is") |
| Even pages | With `DocxDocument.evenAndOddHeaders` on, the section's own even header and footer are written as the default ones (the own even header is dropped when the default one is); with it off the even stories are left alone | Word shows the even stories on even pages only then, and an old even header would sit over the list | group "in an opened document" ("with odd and even headers the even stories are replaced too", "with nothing for the header the own even header is dropped", "without odd and even headers the even stories stay") |
| Cell values | A header row, the data rows and the totals row; a short row leaves its last cells empty; `null` is an empty cell; a string with a tab holds a `DocxTab`; a number, decimal, date, duration or boolean shows through `NumberFormatter` in the export's locale (`General` without a code; a boolean in `tr-TR`; a date without a code as the locale's short date) | the text is what Excel would show | group "values" ("a header row, the data rows and a totals row", "a short row leaves its last cells empty", "a number with a code in tr-TR", "the same decimal in en-US reads as the formatter gives it", "General without a code, and a boolean in tr-TR", "a date without a code is the locale short date", "a date with a code", "a duration with a code", "a string with a tab holds a DocxTab", "null is an empty cell") |
| A value of another type, a row or totals longer than the columns | `ArgumentError` named `rows[i][j]`, `rows[i]`, `totals[j]` or `totals`; the totals and every row are checked before anything is written, so the document is unchanged; `rows` is read once | a value that cannot be shown is the caller's mistake, and a half-written table would be worse | group "values" ("a value of another type is named", "a bad row is named and the document does not change", "rows are read once", "totals are checked before anything is written") |
| The body | A caption (one bold 14 pt run), the table and one empty paragraph; no empty paragraph before the list in a new document; a last empty paragraph that ends a section or follows a table is kept; two lists written one after the other are two tables with a paragraph between; a letter before the list stays | Word wants a paragraph after a table, and two tables with none join | group "body" ("a caption, the table and one empty paragraph, no leading one", "without a caption the table comes first", "a body ending in a paragraph with a section break keeps it", "writing twice gives two tables with a paragraph between", "a second caption stands after the separating paragraph", "a letter before the list stays") |
| Widths | A column's `widthPt` as given; columns without one share what is left of the text width of the page the list sets, equally, and the shares must exceed 1 pt each or `columns` throws before the document changes; every width given is written as given | nothing is measured | group "body" ("the grid has the given widths and shares the rest equally", "all widths null share the text width", "the widths follow the page the list sets", "widths that leave nothing throw before the document changes", "the check uses the page the list sets", "every width given is written as given, even past the page") |
| The look | The header row repeats, never splits, holds bold runs and is shaded `headerShading` (none for `null`; lower case is stored as RGB); the totals row is bold and unshaded; a column with a number format is aligned `end`, header and totals too, and a column's `alignment` wins; an empty cell has no run to make bold | Table Grid with a grey header, as owner decision O5 | group "body" ("the header row repeats, holds bold runs and is shaded", "headerShading null leaves the header unshaded", "headerShading in lower case is stored as RGB", "a number format aligns to the end, header and cells", "a column alignment wins, header and totals too", "the totals row is last and bold, without shading", "no rows: the header and totals rows only", "an empty cell has no run to make bold") |
| The saved file | opens without warnings and round-trips; a control character in a text warns `invalidCharactersRemoved`; `toDocx` sets the given properties and, with the default ones, saves no `docProps` part | the list is an ordinary document | group "body" ("the saved bytes open without warnings and round trip", "a control character warns", "toDocx sets the title") and group "values" ("toDocx saves a document that reads back, with its properties", "toDocx with default properties saves no docProps part") |
| The layering | `lib/src/docx/list_export.dart` imports only `package:jet_core`, `lib/src/common/` and the docx files the barrel exports | the helper is a composition of the public model | `test/architecture/layering_test.dart` ("lib/src/docx/list_export.dart imports only exported docx files", "the list export guard flags an import") |
| `OfficeProperties.copyWith` | replaces the fields given and keeps the others; `null` keeps; no argument equals the original; each field alone changes only itself | closes the `_withTitle` gap of D5 | `test/common/properties_test.dart`, group "copyWith" |

### D6 fixtures and tools

| Case | Behaviour | Why | Test |
|---|---|---|---|
| The two D6 fixtures (`d6_list`, `d6_list_landscape`) | build the same bytes every time with no warnings, read their text, round-trip, and none ends in a table: each ends in the helper's empty paragraph | the validation starts from them | `test/docx/round_trip_test.dart` (the fixture count and "no fixture ends in a table or a section break"), `test/tool/docx_tools_test.dart` and `test/tool/docx_serialize_test.dart` (every fixture of `docxFixtures()`) |
| What the fixtures hold | `d6_list`: a 4 by 2 pixel PNG logo 20 pt high, the title `Müşteri listesi`, the date `08.11.2026`, a caption, five columns (a code, a name with the letters ç ğ ı İ ö ş ü among them, a date, an amount as `#,##0.00 ₺`, a share as `0%`), 120 rows over three A4 portrait pages, a totals row `Toplam` and the footer `Sayfa 1 / 3`; `d6_list_landscape`: English, no logo, twelve columns (four with a width), 40 rows on landscape A4 with 36 pt margins, no totals | the Word check looks for these (`word-checks.md`) | `test/docx/list_export_test.dart`, group "the D6 fixtures, by hand" ("d6_list: 122 rows, the totals last", "d6_list: the header shows the date, the footer the page", "d6_list_landscape: 41 rows of 12 cells") |
| `<name>.stories.txt` of both | the header (a tab, `Müşteri listesi`, a tab and `08.11.2026`; for the landscape one `Monthly figures` and `11/8/26`) and the footer as `Sayfa {PAGE} / {NUMPAGES}` (`Page {PAGE} of {NUMPAGES}`), compared with LibreOffice's re-save | a re-save keeps what a page shows | `test/tool/docx_tools_test.dart` ("writes the text of the stories, only for those that have it"), `test/tool/text_compare_test.dart`, group "docxStoriesText" |
| `tool/edit_docx.dart` and `tool/edit_model.dart` | set the title with `properties.copyWith(title: ...)`, so every other property of the file is kept | the owner's files keep their authors and dates | `test/tool/edit_docx_test.dart`, group "pictures, links, bookmarks and properties" |
| The fuzz | seeds 1 to 4 at 900 cases each (750 before): the D6 fixtures join the corpus, so the fixed seeds still mutate every part name | the corpus grew by two fixtures and their header and footer parts | `test/docx/fuzz_test.dart` ("every part name is mutated in some corpus entry", "mutated files raise only DocxReadException") |
| The benchmark and the large document | `benchmark/docx_model_benchmark_test.dart` repeats the body of `long.docx` (`scaledLongDocx`) to about 40,000 paragraphs, opens it, loads the body, changes a paragraph, saves and reopens; it records figures and judges none. `tool/write_large_docx.dart <dir>` writes the same document with the first paragraph after the middle set to `Edited by the model`, as `large.docx`, for the Word check | the fidelity standard says nothing of speed; a large document must still open | the benchmark by hand (`AGENTS.md`, "Benchmark"; `benchmark.md`, "DOCX document figures"); the tool: `test/tool/write_large_docx_test.dart` ("scales long.docx, with bookmark ids and _Toc names per copy", "a paragraph count below 1 throws", "editedLargeDocx changes one paragraph and reopens", "bad arguments exit 2") |

### Template fill

| Case | Behaviour | Why | Test |
|---|---|---|---|
| A value tag, a dotted path, a tag with spaces (also no-break ones) after `{{` | filled from the data; spaces after a sigil are allowed (`{{# kalemler }}`); an empty format (`{{a:}}`) is malformed | Word autocorrects a space after `{{` to a no-break one | `test/docx/template/tag_scanner_test.dart` ("no-break spaces count as spaces", "spaces around a body", "section with a space after the sigil"), `test/docx/template/fill_test.dart` ("a dotted path walks maps") |
| An unclosed or nested `{{` | the tag ends at the first `}}`; when another `{{` comes first the outer one is malformed and scanning resumes at the inner | a stray `{{` loses no later tag | `test/docx/template/tag_scanner_test.dart` ("an outer tag broken by an inner one", "an unclosed tag", "triple braces"); linear time: "a long run of open braces scans in linear time" |
| A tag Word split over runs | one replacement: value in the tag's first run, runs inside removed, text around kept | Word splits tags at autocorrect and spell-check marks | `test/docx/template/replace_test.dart` ("split tag in a header keeps bold and marks", "text around the tag in one run") |
| Two tags, one run shared | both filled, text between and after kept | the second tag's start run may be the first one's end run | `test/docx/template/replace_test.dart` ("adjacent tags sharing a run") |
| Marks and other inlines | bookmarks, comment ranges, `w:proofErr`, `w:del`, move and permission marks are transparent; every other inline is a boundary a tag cannot cross | the fill must not eat a field, a drawing or a tab | `test/docx/template/paragraph_text_test.dart` ("bookmarks and proofErr are transparent", "a tab is a nonText that ends the segment", "a run holding only an instruction cuts the segment"); `replace_test.dart` ("every other inline untouched") |
| A tag in a hyperlink | filled there; runs wholly inside the tag are removed in the hyperlink too, leaving none empty | the link stays a link | `test/docx/template/replace_test.dart` ("tag in a hyperlink"); `test/docx/model/template_primitives_test.dart` ("removes a run of a hyperlink, and the set undoes it") |
| A line break, a tab, a forbidden character in a value | `w:br`, `w:tab`; the character removed and `invalidCharactersRemoved` warned, also when two tags touch one run | no invalid XML | `test/docx/template/replace_test.dart` ("value with line break and tab", "forbidden characters removed", "forbidden characters of two spans in one run are all counted") |
| A value that holds `{{` | not filled again | a customer name must not become a tag | `test/docx/template/fill_test.dart` ("a value with {{ is not filled again") |
| Number, date, duration, boolean, text values | shown by the number format engine in the fill's locale; `Duration` without a code with `[h]:mm:ss`, `DateTime` with format 14; a flagged code still fills and warns | as `DocxListExport` | `test/docx/template/values_test.dart` ("numbers, dates, durations, booleans and text", "a format code reaches text through the formatter", "a code the engine flags yields its warning"), `fill_test.dart` ("a format warning still fills") |
| A list, a map or a picture in a value tag | the tag stays, `templateValueNotText` | pictures come in T3 | `test/docx/template/values_test.dart` ("lists, maps and images are not text"), `fill_test.dart` ("a list is not text", "{{.}} at the root is the root map, not text") |
| The data tree | checked first: an unsupported type, a non-String key or a cycle throws naming the path; a shared sub-map is accepted and checked once | a fill that fails halfway is worse than one that fails first | `test/docx/template/values_test.dart` ("throws for an unsupported type, naming the path", "throws for a non-String key", "throws for a cycle, accepts a shared sub-map", "a shared structure is checked once, not once per path"); `fill_test.dart` ("a data error changes nothing and records nothing") |
| A name the data lacks | the tag stays, `templateValueMissing`; `removeMissing` removes it and still warns | a placeholder is never lost silently | `test/docx/template/fill_test.dart` ("a missing value stays and warns", "removeMissing removes it and still warns", "a missing merge field stays, or goes with removeMissing") |
| Where it fills | body, cells, nested cells, headers, footers | the owner's templates have tags in all of them | `test/docx/template/fill_test.dart` ("fills the body, a cell, a nested cell, a header and a footer"); `test/docx/template/template_test.dart` ("t1_values: the fixed data fills the split, formatted, coloured, header, footer and table tags, and leaves {{yok}}") |
| Section tags | stay as text, each warned `templateSectionMalformed` with the tag; the value inside a section is filled | sections are T2 | `test/docx/template/fill_test.dart` ("section tags stay, each warned, the value inside filled") |
| A tag in a tracked insertion, a content control, across a tab, in a `PAGE` result, malformed | not filled, warned, left | filling would change a revision or a field the fill does not understand | `test/docx/template/fill_test.dart`, group "fillTemplate: tags that cannot be filled" ("inside w:ins", "inside an inline w:sdt", "across a tab", "in a PAGE result", "an unclosed tag") |
| A merge field | complex field or `w:fldSimple`, filled by its whole name with the first result run's properties; text before and after kept; `\* MERGEFORMAT` silent; casing in the locale; an unsupported switch fills and warns | Word's own forms | `test/docx/template/fill_test.dart`, group "fillTemplate: merge fields" ("MERGEFORMAT is silent", "a date picture", "casing with the locale", "an unsupported switch fills and warns", "a w:fldSimple takes its inner run properties", "a merge field in a hyperlink is filled there"); `test/docx/template/merge_field_test.dart` (every group) |
| A `\#` picture in the locale's separators | read with the fill locale's separators: with a decimal comma (`FormatLocale.trTR`), `.` and `,` swap outside quoted text before the picture becomes a format code, so Turkish Word's `#.##0,00` shows `1.234,56`; `#,##0.00` in `enUS` shows `1,234.56`. The listing reads pictures with `enUS` separators | Word writes the picture in its own language's separators | `test/docx/template/merge_field_test.dart` ("a number picture is read with the locale's separators"), `fill_test.dart` ("a number picture in the fill locale's separators"); the `t1_merge_fields` fixture's `Tutar` line |
| A switch with no space before its argument | `\#0.00`, `\*Upper`, `\b"x"` take the rest of the word as the argument; any other word starting with `\` is unsupported and warned | Word reads them so | `test/docx/template/merge_field_test.dart` ("a switch written without a space takes its argument", "another word starting with a backslash is unsupported") |
| Marks inside a merge field | copies of the bookmark marks, comment range, `w:proofErr`, permission and move range marks a field holds (in its instruction, its result, or inside a `w:fldSimple`) go right after its value, in a hyperlink too, and stay when the field is removed; `w:del` and `w:moveFrom` hold the old result and go with it. An undo puts the field back with its own marks | half a bookmark or comment range is a broken file to Word | `test/docx/template/fill_test.dart`, group "marks inside a field result stay" |
| A tag over a page boundary | `w:lastRenderedPageBreak` adds no position and no cut, so the tag fills; one outside the tag stays, one inside goes with the replaced text (Word computes it again) | Word writes one at every page start | `test/docx/template/paragraph_text_test.dart` ("a last rendered page break adds no position and no cut"), `fill_test.dart` ("a tag over a page boundary fills") |
| `\#` and `%` | a `%` in a number picture is a literal, as Word does not multiply | Excel's `%` would | `test/docx/template/merge_field_test.dart` ("a percent sign is a literal, not Excel percent"); `values_test.dart` ("a percent literal shows as text") |
| A `MERGEFIELD` in another field, or loose instruction runs | not typed, `templateFieldNotTyped` | a nested field's value is not ours to set | `test/docx/template/fill_test.dart` ("a MERGEFIELD inside an IF instruction is not typed", "loose instruction runs are not typed") |
| Text boxes, content controls, footnotes, endnotes, comments | found (per paragraph, `MERGEFIELD` instructions too) and warned, never changed; a part that cannot be read is skipped without a warning, as the fill never writes it | an untrusted file's opaque content must not make the fill throw or lose a tag silently | `test/docx/template/opaque_scan_test.dart`; `fill_test.dart`, groups "fillTemplate: opaque content and parts" and "fillTemplate: untrusted opaque content" |
| Listing | `tags` lists every tag in reading order with kind, name, format, depth, changing nothing, in a list that cannot be modified; a malformed tag has no name; opaque and part placeholders are listed as not typed | the caller sees what a template asks for | `test/docx/template/template_test.dart` ("tags list kinds, names, formats and depth in reading order", "a malformed tag has the kind malformed and no name", "tags cannot be modified"); `fill_test.dart`, group "listTemplateTags" |
| One transaction | a fill is one change set, undone whole; a data error records nothing; a header or footer that cannot be read throws `DocxReadException` and changes nothing; the library keeps no change set (tests take it from `fillTemplateWithChanges`) | the library keeps no undo stack, only the set's id | `test/docx/template/fill_test.dart` ("one fill is one change set, undone whole"); `template_test.dart` ("a header that cannot be read throws and changes nothing"); `test/docx/model/template_primitives_test.dart` ("documentTransaction", "a body that throws leaves the document as it was") |
| Reopen per fill, bytes copied | two fills of one template are two documents; mutating the caller's list changes nothing | no state leaks between fills | `test/docx/template/template_test.dart` ("fill twice gives two documents with their own values", "template bytes are copied") |
| `fillDocument` | fills a document the caller holds, in place; it still edits afterwards | a caller may fill, then add what a template cannot | `test/docx/template/template_test.dart` ("fillDocument fills in place and the document still edits") |
| Fill warnings | the fill's own collector, then the save's, in a `DocxResult`; not added to `DocxDocument.warnings` | the fill is a call of its own | `test/docx/template/template_test.dart` ("fill warnings are the fill's, then the save's") |
| An unreadable file | `DocxReadException`, as `DocxDocument.open` | one error type | `test/docx/template/template_test.dart` ("an unreadable file throws DocxReadException") |
| The model's primitives | `setRunContent`, `copyRunWithText`, `removeHeldInline`, `replaceHeldInline`, `spliceHeldInline`, `runOfSimpleField` change a held run and record in the change log; a replacement that is held throws before anything changes | the fill is built on the public model's own change log | `test/docx/model/template_primitives_test.dart` |
| Data that names nothing | gives the template back: `comparePackages` finds no difference | a fill preserves what it does not touch (decision 0010) | `test/docx/template/template_test.dart` ("data naming nothing gives every fixture back"); `test/docx/template/template_owner_test.dart` (VM; the owner's Word files) |

### T1 fixtures and tools

| Case | Behaviour | Why | Test |
|---|---|---|---|
| The four T1 fixtures (`t1_values`, `t1_merge_fields`, `t1_template`, `t1_merge_fields_template`) | `t1_values` and `t1_merge_fields` are the templates filled with `fillDocxData()` (`tool/src/fill_data.dart`) in `FormatLocale.trTR`, `t1_values` leaving `{{yok}}` and warning once; the other two are the templates unfilled, so CI fills them | the validation starts from them | `test/docx/template/template_test.dart` ("t1_values: ...", "t1_template lists its tags; t1_merge_fields fills every field"); `test/docx/round_trip_test.dart` and `test/tool/docx_tools_test.dart` (every fixture of `docxFixtures()`) |
| What they hold | `t1_values`: `{{firma.unvan}}` split over runs with its first brace bold, a date `{{tarih:dd.mm.yyyy}}` and an amount `{{tutar:#,##0.00 ₺}}` split after their names, a red `{{musteri.ad}}` split at its dot, a table of six tags, a tag in the header and the footer, `{{yok}}`; `t1_merge_fields`: complex fields with text before and after (`\b`, `\f`), upper casing, a `\@ "dd.MM.yyyy"` date picture, a `\# "#.##0,00"` number picture in Turkish separators, a `w:fldSimple` and a header and a footer | the Word check looks for these (`word-checks.md`, "T1") | `test/docx/template/template_test.dart` |
| `tool/fill_docx.dart` | fills every document of a directory with `fillDocxData()` and checks no fillable tag with data is left, every missing one still is and warned, no merge field with data is left, only the main part and the parts of filled tags changed, and `fill({})` gives the input back | CI validates what the fill saves | `test/tool/fill_docx_test.dart` (every "reports ..." case, "bad arguments: exit 2", "a truncated copy: exit 1, named") |
| `tool/write_t1_check.dart <dir>` | writes the four fixtures and `owner/`, each `template_*.docx` of `test/fixtures/owner/docx/` filled with `fillDocxData()` (none yet: it says so and exits 0); exit 2 on bad arguments, 1 on an error | the owner's Word check | `test/tool/write_t1_check_test.dart` |
| The fuzz | `tool/fuzz_docx.dart --template` and `test/docx/template/template_fuzz_test.dart` insert tags and switches into the story parts of the four templates and fill them; only `DocxReadException` may come out, and the fill of `{}` gives back the template opened, loaded and saved; the DOCX fuzz runs 1,400 cases a seed (900 before) so every part name is still mutated | the fill reads untrusted files | `test/docx/template/template_fuzz_test.dart`, `test/docx/fuzz_test.dart` ("every part name is mutated in some corpus entry") |
| The AM/PM guard | `test/architecture/format_code_test.dart` allows `lib/src/docx/template/merge_field.dart` to hold the AM/PM marker: it translates Word's date pictures and writes the marker the number format engine reads, and scans no Excel format code. The allowlist is one path, narrow | the guard keeps Excel code scanning out of `lib/`; this file does not scan any | `test/architecture/format_code_test.dart` ("no file under lib/ holds the AM/PM markers", "the guard flags an AM/PM marker") |

### Checks outside the unit tests

| Case | Behaviour | Why | Test |
|---|---|---|---|
| The five D1 fixtures (`d1_blank`, `d1_paragraphs`, `d1_text_rules`, `d1_unicode`, `d1_large`) | build the same bytes every time, with exactly their expected warnings, and round-trip | the CI validation starts from them | `test/docx/round_trip_test.dart` |
| The layering | `lib/src/docx/` never imports `lib/src/xlsx/`, `lib/src/common/` imports neither, and nothing under `lib/src/` imports the barrel | shared machinery stays shared | `test/architecture/layering_test.dart` |
| The fuzz corpus | the pinned bytes, the same on every run; every part name is mutated in some entry | a failing case is reproducible | `test/docx/fuzz_test.dart` |

## Port map

D5 ports one writer (D6 none). The file below names its Quds source path and
commit in its library doc comment (AGENTS.md). Quds paths are relative to
`../quds_office_suite/packages/quds_office_engine/lib/src/`, at commit
`15c5d29`.

| jet_office file (`lib/src/`) | Ported from Quds | Changes |
|---|---|---|
| `docx/drawing.dart` (`writeInlineDrawing`) | `word/serial/word_drawing_io.dart` (`WordDrawingIo.writeInline`, the inline branch of `_writeAnchorOrInline`) | Writes the `wp:inline` alone (the story writer wraps it in `w:drawing` and a run, not a paragraph); no anchor, wrapping, shadow, outline, cropping or aspect switch (a built picture is inline with its aspect locked); `descr` only when given; `pic:cNvPr` repeats the `wp:docPr` id; `pic:pic` comes from the shared `drawingml/picture.dart`; `wp`, `a`, `pic` and `r` are declared only where the bindings above lack them. The reader in the same file is jet_office's own. |

D6 ports nothing: `DocxListExport` is new in jet_office (Quds has no list
export) and says so in its library doc comment.

D2 read Quds' `wml_properties.dart` and `word_styles.dart` and ported
neither: the enumerations are transcribed from ECMA-376 (Part 1, §17.18),
and the built-in style and list definitions take their values from Word's
own files (`blank.docx`, `builtins.docx`), not from Quds (decision 0011).

D1 ports nothing from Quds (`quds_office_suite` at `15c5d29`). Its Word code
is a good reader and a lossy writer (decision 0010), so the model, the
property writer, the text rules and the new document are written for
jet_office. A later milestone may port Quds' property vocabulary and built-in
style definitions under the usual rules ("Port, don't copy", `AGENTS.md`);
its serializer, mail merge and other DOCX writers are not ported.

What D1 reuses from earlier phases: the package layer (`lib/src/opc/`), the
ZIP reader and writer, the XML pull reader and writer, the warning
aggregator and the read guard (`lib/src/common/`), and the change log.

## Verification

- `test/docx/` runs the rules above on the VM and in Chrome, except the
  owner-file and oracle tests (VM only).
- CI's `validate` job validates the fixtures, the model's round trips and the
  owner's Word files with the Open XML SDK, compares LibreOffice's text
  export and re-save of every fixture with the expected texts, and proves
  each check rejects the deliberately broken `d1_corrupt.docx` (AGENTS.md,
  "Validation"). The D2 to D6 fixtures, the edits of
  `tool/edit_docx.dart` and the model's own encoding of the styles, numbering,
  header, footer and properties parts go through the same checks; the
  LibreOffice re-save is validated with `--libreoffice-resave`, which ignores
  only `w:val="true"` on `w:tblHeader`, as LibreOffice writes it, and on
  `w:cantSplit`, of the same type: values the model keeps as read.
- Neither is Word. The owner opens each D milestone's fixtures and round
  trips in Word for Mac and records the result in
  [`word-checks.md`](word-checks.md); its D2 to D6 sections say what
  to look for, D3 adds a document whose body ends in a table, D4 one whose
  last block carries a section break, and D6 the benchmark's large document.
