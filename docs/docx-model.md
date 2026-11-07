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
styles and lists, milestone D3, tables, and milestone D4, sections, headers,
footers and fields. **The DOCX API is in progress and
may change before D6**; the names are fixed at D6 (decision 0010).

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
- **Editing.** `insertRowAt`, `removeRowAt`, `insertCellAt`, `removeCellAt`,
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

## Known gaps

- **Visible text of some opaque inlines.** `mc:AlternateContent` and the text
  of a text box give `''` for an opaque inline's visible text, so a paragraph
  whose words are only there reads as empty.
- **A new document has no `docProps`** until D5: no `core.xml`, no
  `app.xml`.
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
  `insertCellAt`, which can move a later cell off the columns of the merge
  above or below it, are allowed: removal and insertion must keep working on
  any table, and Word reads a continuation with nothing above as a new cell
  (tests: `test/docx/model/table_merge_test.dart`, "that is plain may go
  inside a vertical merge", "a removal that orphans a merge is allowed").
  `insertCellAt` does not check a continuation on the
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
  and the mark inside the opaque content pairs with nothing.
- **A field nested in an instruction begun in an earlier paragraph** is typed:
  the grouping pass looks at one paragraph, which cannot show that the field
  lies in an instruction. It reads and saves as read; only its meaning is the
  outer field's.
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
  as stray text in a `w:pPr` is. A file that is not edited keeps it.
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
| A content control, a bookmark or any other block | an opaque block, in place | typed later (D5) or never | `test/docx/document_part_read_test.dart`, `test/docx/model/body_model_test.dart` |
| The final `w:sectPr` of the body | held by the body as its last section (see "Sections"); a `w:sectPr` in a paragraph's `w:pPr` is that paragraph's break; one that is not the last child of the body is a block | the last section belongs to the body | `test/docx/document_part_read_test.dart`, `test/docx/model/sections_test.dart` |
| Any other child of a paragraph (tracked change, hyperlink, content control, smart tag, proofing mark) | an opaque inline, in place, with its visible text computed once | kept as written | `test/docx/document_part_read_test.dart`, `test/docx/model/body_model_test.dart` |
| Any other child of a run (drawing, `w:delInstrText`, a `w:fldChar` of no known type, `mc:AlternateContent`) | opaque run content, in place; it adds nothing to the run's text | kept as written | `test/docx/document_part_read_test.dart`, `test/docx/model/fields_read_test.dart` |
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
| `w:ins`, `w:moveTo`, `w:hyperlink`, `w:smartTag`, `w:customXml`, `w:fldSimple`, nested | contribute the text of their runs, in order | what a reader sees | `test/docx/model/body_model_test.dart` ("visible text of an opaque inline") |
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
| The fuzz | seeds 1 to 4 at 400 cases each over the fixtures (tables among them), a hand-made table and producer variants, with typed attributes replaced in the typed parts, access to `styles` and `numbering`, and a `DocxReadException` from a typed getter counted as a failure | the typed exception is the contract | `test/docx/fuzz_test.dart` ("typed attributes are replaced in the typed parts", "mutated files raise only DocxReadException") |

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
| A block or inline already in a body or paragraph (this one or another document) | `StateError`; nothing changes | phase 4 neither moves nor copies implicitly | `test/docx/docx_document_test.dart`, `test/docx/model/body_model_test.dart`, `test/docx/primitives_test.dart` |
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
| `addRow` on a table read | a row of the grid's width after the rows; a column without a usable width gives a cell without one; a grid past 63 columns gives a row of its width; a table with no grid, or an empty one, throws `ArgumentError` (use `insertRowAt`) | a row's width needs a grid (`insertRowAt` takes any row) | `test/docx/model/table_build_test.dart` ("on a table read takes the width of its grid, after its rows", "a column without a usable width gives a cell without one", "a grid past 63 columns gives a row of its width", "a table without a grid throws: it has no width") |
| A table with no rows | `addTable` returns one; a save of it throws `StateError` naming it (also one nested in a cell), writes nothing, and the first row, or removing the table, makes it saveable; a table read with no rows is kept, edited or not; the constructor refuses `rows` below 1 | Word repairs a table without rows | `test/docx/model/table_build_test.dart` ("a save names it, and writes nothing", "a save names one nested in a cell", "the first row, or removing the table, makes it saveable", "an undone first row leaves it unsaveable again", "a table read with no rows is kept, edited or not", "the constructor still refuses it") |
| `DocxTableCell.addTable` | behaves as the body's: the document's `Table Grid` style, one transaction, a bad argument changes nothing; in a cell of no document the table has no style, and one set resolves when the cell goes in a document; nesting past 80 throws `ArgumentError` | the same rules at every level | `test/docx/model/table_build_test.dart` ("in a document behaves as the body does", "in a document adds the style a document lacks", "finds the built-in by name, as the body does, past a squatter", "past the nesting the API builds throws and changes nothing") |
| The styles of what goes in | a table, a row or a cell put in a document has every style set on it and in its cells resolved as `insertBlock` does, an unreadable styles part changing nothing; inserted in no document the id is stored as given; a table moved within its document stays as read | D2's rules for blocks | `test/docx/model/table_build_test.dart` ("the styles of what goes in", "a style set on a table in a document resolves as it is set", "an insert in no document stores the id as given", "the styles a route adds undo with it", "a read table moved within its document stays as read") |
| A table, row or cell read in another document and inserted | its `w:tblStyle`, `w:pStyle`, `w:rStyle` and `w:numPr` count as set, a missing one is reported at save with its full path, a built-in it names resolves to this document's id, and undoing the insert takes the count back; a style read in a table of this document is not reported | the references of D2, in tables | `test/docx/model/table_build_test.dart` ("its w:tblStyle and the deep references count as set, and a missing", "a built-in it names resolves to this document's id", "a row or a cell read there joins the same way", "undoing the insert takes the count back", "a style read in a table of this document is not reported") |
| `styleNotFound` and `numberingNotFound` in a table | name the paragraph, the table and the nested table by their full paths | warnings keep their paths | `test/docx/warnings_test.dart` ("styleNotFound names a paragraph in a cell by its full path", "numberingNotFound names a paragraph in a cell by its full path", "styleNotFound names a table and a nested table by their paths"), `test/docx/document_part_write_test.dart` ("warnings name the path in the table", "the checks of a list and a style name the path in the table") |

#### Editing a table

| Case | Behaviour | Why | Test |
|---|---|---|---|
| A new `DocxTable`, `DocxTableRow`, `DocxTableCell` | a table of the rows and columns asked for, of empty cells, dividing 9062 twips (rounded down), one row by default; `w:tblPr` and `w:tblGrid` are written, each `w:tcW` in twips; a table read without a `w:tblPr` still writes none; a new cell holds one paragraph of its text | the constructors build what `addTable` builds, without a style | `test/docx/model/tables_edit_test.dart` ("has the rows and columns asked for, with empty cells", "divides 9062 twips among its columns, rounded down", "takes 1 to 63 columns and at least one row", "writes w:tblPr and w:tblGrid, and each w:tcW in twips", "a table read without w:tblPr still writes none", "a new cell holds one paragraph of its text") |
| `insertRowAt`, `removeRowAt`, `insertCellAt`, `removeCellAt` | the item is at its index counting the typed ones, and the edit undoes and redoes; a removed one can go in again; an index out of range throws `RangeError`; a row or cell in another table or row throws `StateError` | one way to change a list (D1) | `test/docx/model/tables_edit_test.dart` ("an inserted row is at its index, and undoes and redoes", "a removed row can go in again, and the removal undoes", "an index out of range throws RangeError", "a row in a table cannot go in another", "an inserted cell is at its index, and undoes and redoes", "a removed cell undoes, and can go in again", "a cell in a row cannot go in another") |
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

### Checks outside the unit tests

| Case | Behaviour | Why | Test |
|---|---|---|---|
| The five D1 fixtures (`d1_blank`, `d1_paragraphs`, `d1_text_rules`, `d1_unicode`, `d1_large`) | build the same bytes every time, with exactly their expected warnings, and round-trip | the CI validation starts from them | `test/docx/round_trip_test.dart` |
| The layering | `lib/src/docx/` never imports `lib/src/xlsx/`, `lib/src/common/` imports neither, and nothing under `lib/src/` imports the barrel | shared machinery stays shared | `test/architecture/layering_test.dart` |
| The fuzz corpus | the pinned bytes, the same on every run; every part name is mutated in some entry | a failing case is reproducible | `test/docx/fuzz_test.dart` |

## Port map

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
  "Validation"). The D2, D3 and D4 fixtures, the edits of `tool/edit_docx.dart`
  and the model's own encoding of the styles, numbering, header and footer
  parts go through the same checks; the LibreOffice re-save is validated with
  `--libreoffice-resave`, which ignores only `w:val="true"` on `w:tblHeader`,
  as LibreOffice writes it, and on `w:cantSplit`, of the same type: values the
  model keeps as read.
- Neither is Word. The owner opens each D milestone's fixtures and round
  trips in Word for Mac and records the result in
  [`word-checks.md`](word-checks.md); its D2, D3 and D4 sections say what to
  look for, D3 adds a document whose body ends in a table, and D4 one whose last
  block carries a section break.
