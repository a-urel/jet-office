# DOCX document model

`DocxDocument` opens a DOCX file from bytes, or starts a new document, lets a
caller read and edit the body's paragraphs, and saves the file again. Saving
keeps everything the caller did not change: the model is the single source of
every save. Decision
[`0010`](decisions/0010-phase-4-docx-document-model.md) sets the scope and the
fidelity standard; it applies decision
[`0009`](decisions/0009-phase-3-workbook-model.md)'s preservation layers to
WordprocessingML.

This page covers milestone D1, the foundation, and milestone D2, formatting,
styles and lists. **The DOCX API is in progress and may change before D6**;
the names are fixed at D6 (decision 0010).

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

## What D1 does and does not do

- **Typed.** The body's paragraphs (`DocxParagraph`), their runs
  (`DocxRun`), the paragraph and run style, and a run's text, tabs, breaks and
  carriage returns (`DocxRunContent`).
- **Opaque, kept as written.** Everything else: tables (typed in D3),
  content controls, bookmarks, tracked changes, hyperlinks, drawings, fields
  and `mc:AlternateContent` (`DocxOpaqueBlock`, `DocxOpaqueInline`,
  `DocxOpaqueRunContent`). An opaque node can be removed, not changed.
- **The final `w:sectPr`** of the body is held by the body and kept as
  written until D4.
- **Edits.** `addParagraph`, `insertBlock`, `removeBlockAt`,
  `replaceBlockAt`, the same for inlines, a run's `text` and the two styles.
  Each edit is atomic (a transaction of the document's `ChangeLog`).
- **Not in D1.** Formatting, styles and lists (D2, below), tables (D3),
  sections, headers, footers and fields (D4), pictures, hyperlinks,
  bookmarks and document properties (D5), `DocxListExport` (D6). Headers,
  footers, notes and comments are saved as they were, not read.

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

## Known gaps

- **Visible text of some opaque inlines.** `mc:AlternateContent` and the text
  of a text box give `''` for an opaque inline's visible text, so a paragraph
  whose words are only there reads as empty.
- **Tables are opaque** until D3, so their cells are not part of any text the
  model gives.
- **A new document has no `docProps`** until D5: no `core.xml`, no
  `app.xml`.
- **The Word XML shipped in a new document** (theme, styles, font table,
  settings) is taken from a blank document saved by Word for Mac. Whether it
  may ship under this package's licence is an open question for the owner
  (see `NOTICE`).
- **Fields show their cached result** until Word lays the document out; this
  library does not paginate.

### Known gaps of D2

- **The paragraph mark's `w:rPr`** (the run properties inside the
  paragraph's `w:pPr`, which style the paragraph mark) is kept and never
  typed, so it reads as nothing and a setter never changes it (test:
  `test/docx/model/paragraph_properties_test.dart`, "the paragraph mark rPr
  is never typed").
- **Style parts the model does not type.** A style's `w:tblPr`, `w:trPr`,
  `w:tcPr` and `w:tblStylePr` (table styles, typed in D3) are kept as
  written.
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
| A `w:t` longer than `maxTextLength`, or an opaque inline whose visible text is | `limitExceeded` naming the limit and the paragraph as `body/p[i]`, `i` its zero-based index among the body's paragraphs (as in a warning's location: a table or content control before it does not count), on the first access to `body`; deleted text does not count | one text must not be as large as the file | `test/docx/docx_package_test.dart`, `test/docx/document_part_read_test.dart` ("maxTextLength"), `test/docx/docx_document_test.dart` |
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
| A table, a content control, a bookmark or any other block | an opaque block, in place | typed later (D3, D5) or never | `test/docx/document_part_read_test.dart`, `test/docx/model/body_model_test.dart` |
| The final `w:sectPr` of the body | held by the body; a `w:sectPr` in a paragraph's `w:pPr` stays there; one that is not the last child of the body is a block | the last section belongs to the body (typed in D4) | `test/docx/document_part_read_test.dart` |
| Any other child of a paragraph (tracked change, hyperlink, content control, smart tag, proofing mark) | an opaque inline, in place, with its visible text computed once | kept as written | `test/docx/document_part_read_test.dart`, `test/docx/model/body_model_test.dart` |
| Any other child of a run (drawing, field, `mc:AlternateContent`) | opaque run content, in place; it adds nothing to the run's text | kept as written | `test/docx/document_part_read_test.dart` |
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
| Removed characters | one `invalidCharactersRemoved` warning per part, reported at save with a location such as `body/p[5]/r[0]` (`p[i]` counts paragraphs only, `r[j]` runs only; a path to another block would be `body/<localName>[i]`, indexed among blocks of that local name); the count is the characters removed, and the location list ends with `…` only when more than ten runs lost characters; a run removed before the save, or a second save, does not add to it | the warning describes the file saved, not the edits made | `test/docx/document_part_write_test.dart` ("warnings at save"), `test/docx/warnings_test.dart` |
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
| Setting a property | replaces every child of that name with the canonical element, at its slot in schema order; setting `null` removes them (when the view is not `null`) | one element per name | `test/docx/properties_test.dart` ("setting replaces every child of that name at its slot", "setting null removes them"), `test/docx/model/run_properties_test.dart` ("a member set to null is removed") |
| Setting the value the view already has, `null` included | nothing: no change is recorded and an untyped child stays, so `x.style = x.style` never deletes what Word accepts | copying formatting must not lose a child the model does not type | `test/docx/model/run_properties_test.dart` and `test/docx/model/paragraph_properties_test.dart` ("setting a value equal to the current one records nothing") |
| Removing an untyped child | `clear` on the properties object (`clear<Property>()` or `clear(name)`) removes the child, typed or not | the explicit way to drop what setting `null` keeps | `test/docx/model/run_properties_test.dart` ("clear removes an untyped child that setting null keeps", "clear removes a typed child too"), `test/docx/model/paragraph_properties_test.dart` |
| What a set keeps of Word's other scripts | `fonts` replaces `@ascii`, `@hAnsi`, `@eastAsia` and their theme attributes and keeps `@cs`, `@cstheme`, `@hint` and others; `language` replaces `w:lang/@w:val` and keeps `@eastAsia` and `@bidi`; `bold` writes `w:b` only, `sizePt` `w:sz` only | complex-script formatting is a non-goal (spec §2); its attributes must survive | `test/docx/model/run_properties_test.dart` ("setting fonts keeps cs, cstheme and hint and drops asciiTheme", "setting language keeps eastAsia and bidi", "setting bold keeps bCs, setting sizePt keeps szCs") |
| One set on a Word file's run or paragraph | every other child (`w14:ligatures`, `w:kern`, `w:szCs`, `w:lang/@eastAsia`, a `w:rPr` of the paragraph mark, `w:sectPr`) stays in place and in schema order | only the property set changes | `test/docx/model/run_properties_test.dart` ("a w14:ligatures child stays after kern when bold is set"), `test/docx/model/paragraph_properties_test.dart` ("setting alignment keeps pPr/rPr and sectPr in place", "w14 and kept children stay in place when one is set", "typed tabs and pBdr a neighbour set leaves stay byte for byte") |
| A kept child (`w14:`, `w15:` and others) | stays after its predecessor in the file; with no typed predecessor it follows the one before it, and with none it is written first; matched by namespace URI, not prefix; a declaration it needs is written on it | its place survives an edit | `test/docx/properties_test.dart` ("a kept w14 child stays after its predecessor", "a kept child whose typed predecessor is gone follows the one before it", "a kept child with no predecessor is written first", "a kept child declares a namespace the new parent lacks") |
| A `w:pPr` or `w:rPr` holding only whitespace, an empty one, or its own attributes | written back as it was until a child is set | a read file saves as it was | `test/docx/properties_test.dart` ("an empty container element reads and writes", "attributes of the container are kept") |
| A `w:pPr` or `w:rPr` that rebinds the `w` prefix | children set are written with a prefix bound to WordprocessingML (one the container has, or a new `w1`) | the output means what was set | `test/docx/properties_test.dart` ("a pPr that redeclares the w prefix writes typed children with a bound prefix") |
| Comments between the children of a properties container that has children | dropped once the body is loaded and saved, whether or not a property is set; the other children and their order are kept | the model keeps children, not comments | `test/docx/model/run_properties_test.dart` ("a comment between the children of a w:rPr is dropped once the body is loaded and saved", on the raw bytes, because `comparePackages` ignores comments) |
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
| The catalog | Word's definitions, from `blank.docx` and `builtins.docx` with ids and names mapped to the English ones, no rsids, no Turkish id or name | the definitions are Word's | `test/docx/builtin_styles_test.dart` ("every built-in has a definition of its type and name", "no definition carries an rsid or a Turkish id or name", "catalog entries in the blank document equal its styles"), `test/docx/builtin_styles_oracle_test.dart` ("definitions equal builtins.docx after mapping ids and names") |
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
| `tool/edit_docx.dart` | edits the first run (bold, accent 1), replaces a paragraph, adds a `Heading1`-style paragraph and a two-item bullet list, and checks the edits read back and that only the allowed parts differ | CI validates the edited files with the Open XML SDK | `test/tool/edit_docx_test.dart` ("a Word-like document gets the edits, and only the allowed parts change", "edits a document with Turkish style ids using Balk1", "creates numbering.xml in a document without one") |
| Styles and numbering in `tool/round_trip_docx.dart` | the model's own encoding of each part is compared, not a copy of the input | a part left as read would hide a writer bug | `test/tool/docx_serialize_test.dart` ("is the model's own writing, not a copy of the input", "finds none in the D2 fixtures") |
| The fuzz | seeds 1 to 4 at 150 cases each over the fixtures and producer variants, with typed attributes replaced in the typed parts, access to `styles` and `numbering`, and a `DocxReadException` from a typed getter counted as a failure | the typed exception is the contract | `test/docx/fuzz_test.dart` ("typed attributes are replaced in the typed parts", "mutated files raise only DocxReadException") |

### Writing and saving

| Case | Behaviour | Why | Test |
|---|---|---|---|
| Open, save, never access the body | `word/document.xml` is copied byte for byte | layer 1 of decision 0009: a part never loaded is its bytes | `test/docx/docx_document_test.dart` ("open and save") |
| Open, read the body, save | semantically equal by `comparePackages` (elements by namespace and local name, attributes as a map, text exactly) | layer 2: a loaded part is written from the model | `test/docx/document_part_write_test.dart`, `test/docx/docx_document_test.dart`, `test/docx/round_trip_test.dart` |
| Open, set one run's text, save | only that `w:t` differs | a change touches only what it changes | `test/docx/docx_document_test.dart` |
| What the model does not type, inside a loaded part | written back as it was, declaring only the namespaces it needs and never redeclaring `w` | layer 3 | `test/docx/document_part_write_test.dart` |
| The root | written as read, with every namespace declaration and `mc:Ignorable`; a new document declares only `w` | `mc:Ignorable` names prefixes that must stay declared | `test/docx/document_part_write_test.dart` |
| A document with another prefix or a default namespace | round-trips | prefixes are the producer's | `test/docx/document_part_write_test.dart`, `test/docx/producer_variants_test.dart` |
| An edited `.docm` | every part but the body as it was; the macro content type is kept | macros are never run, created or edited | `test/docx/producer_variants_test.dart` |
| `saveTo` | the same bytes as `save`, sent to the sink | one writer | `test/docx/docx_document_test.dart` |
| `save().warnings` | what opening, loading and that save repaired, in first-occurrence order; `warnings` holds the same afterwards | the list reflects the document as last saved | `test/docx/docx_document_test.dart` |
| A relationship to a missing header | kept as written; no throw in D1 | headers arrive in D4 | `test/docx/docx_document_test.dart` |
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
| `DocxDocument()` | one empty paragraph and the parts of Word for Mac 16.114.1's blank document, without `docProps`; it opens and saves unchanged | like Word's blank document | `test/docx/blank_document_test.dart` |
| Page | A4 portrait | decision 0010 | `test/docx/blank_document_test.dart`, `test/docx/blank_document_oracle_test.dart` |
| Fonts | Aptos through the theme, at 12 pt | Word's current default | `test/docx/blank_document_test.dart` |
| Locale | none of the reference file's: every language is `en-US`, and the decimal symbol and list separator are left to the reader | a generated file must not carry its author's region | `test/docx/blank_document_test.dart`, `test/docx/blank_document_oracle_test.dart` |
| Style ids and names | Word's en-US ones (`Normal`, `Heading1`), not the Turkish ones of the reference file | a library caller writes `style = 'Heading1'` | `test/docx/blank_document_test.dart` |
| Revision ids, document id, proof state, attached template | none | they identify the reference file | `test/docx/blank_document_test.dart` |
| `compatibilityMode` 15 and the web settings | kept | Word opens the file in the current mode | `test/docx/blank_document_test.dart` |
| The parts | equal to the reference file's apart from `docProps`, after removing ids and locale; none of the owner's document properties is written | the reference is a file the owner saved from Word | `test/docx/blank_document_oracle_test.dart` |

### Checks outside the unit tests

| Case | Behaviour | Why | Test |
|---|---|---|---|
| The five D1 fixtures (`d1_blank`, `d1_paragraphs`, `d1_text_rules`, `d1_unicode`, `d1_large`) | build the same bytes every time, with exactly their expected warnings, and round-trip | the CI validation starts from them | `test/docx/round_trip_test.dart` |
| The layering | `lib/src/docx/` never imports `lib/src/xlsx/` (except `xlsx/format`), `lib/src/common/` imports neither, and nothing under `lib/src/` imports the barrel | shared machinery stays shared | `test/architecture/layering_test.dart` |
| The fuzz corpus | the pinned bytes, the same on every run; every part name is mutated in some entry | a failing case is reproducible | `test/docx/fuzz_test.dart` |

## Port map

D2 read Quds' `wml_properties.dart` and `word_styles.dart` and ported
neither: the enumerations are transcribed from ECMA-376 (Part 1, §17.18),
and the built-in style and list definitions come from Word's own files
(`blank.docx`, `builtins.docx`), not from Quds.

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
  "Validation"). The D2 fixtures, the edits of `tool/edit_docx.dart` and
  the model's own encoding of the styles and numbering parts go through the
  same checks.
- Neither is Word. The owner opens each D milestone's fixtures and round
  trips in Word for Mac and records the result in
  [`word-checks.md`](word-checks.md); the D2 section says what to look for.
