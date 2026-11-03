# DOCX document model

`DocxDocument` opens a DOCX file from bytes, or starts a new document, lets a
caller read and edit the body's paragraphs, and saves the file again. Saving
keeps everything the caller did not change: the model is the single source of
every save. Decision
[`0010`](decisions/0010-phase-4-docx-document-model.md) sets the scope and the
fidelity standard; it applies decision
[`0009`](decisions/0009-phase-3-workbook-model.md)'s preservation layers to
WordprocessingML.

This page covers milestone D1, the foundation. **The DOCX API is in progress
and may change before D6**; the names are fixed at D6 (decision 0010).

```dart
final DocxDocument doc = DocxDocument.open(bytes);
doc.body.addParagraph('Toplam: 1.234,50 ₺');
final Uint8List saved = doc.save().bytes;
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
- **Not in D1.** Formatting, styles and lists (D2), tables (D3), sections,
  headers, footers and fields (D4), pictures, hyperlinks, bookmarks and
  document properties (D5), `DocxListExport` (D6). Headers, footers, notes
  and comments are saved as they were, not read.

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
| A paragraph or run whose style element is not typed | its `style` reads `null`, although the file names a style element; setting `style` (or `null`) replaces every `pStyle` or `rStyle` of the container | one style per container | `test/docx/document_part_write_test.dart` ("kept styles"), `test/docx/properties_test.dart` |
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

| Case | Behaviour | Why | Test |
|---|---|---|---|
| The order of `w:pPr` and `w:rPr` children | the schema's (ECMA-376 transitional `wml.xsd`), with no name twice | Word repairs a document whose property children are out of order | `test/docx/schema_order_test.dart` |
| A typed child that is set (the style) | written at its slot in schema order, in place of every child of its name; a kept child out of order is written in schema order | one writer per container | `test/docx/properties_test.dart`, `test/docx/container_order_test.dart` |
| A kept child (`w14:`, `w15:` and others) | stays after its predecessor in the file; with no typed predecessor it follows the one before it, and with none it is written first | its place survives an edit | `test/docx/properties_test.dart` |
| Replacing a style | the old `pStyle` or `rStyle` is dropped, every one of them | one style per container | `test/docx/properties_test.dart` |
| A `w:pPr` or `w:rPr` holding only whitespace or comments | written back as it was, until a child is set | a read file saves as it was | `test/docx/properties_test.dart` |
| A `w:pPr` or `w:rPr` that rebinds the `w` prefix | children set are written with a prefix bound to WordprocessingML (one the container has, or a new `w1`) | the output means what was set | `test/docx/properties_test.dart` |
| A kept child, matched | by namespace URI, not by prefix | a producer may choose any prefix | `test/docx/properties_test.dart` |
| A kept child that needs a namespace the new parent lacks | the declaration is written on it | the output is well-formed | `test/docx/properties_test.dart` |
| A container's own attributes; an empty container | kept; written back empty | nothing is lost | `test/docx/properties_test.dart` |
| A typed child outside the order list | a programmer error | the list is the contract | `test/docx/properties_test.dart` |

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

- `test/docx/` runs the rules above on the VM and in Chrome.
- CI's `validate` job validates the fixtures, the model's round trips and the
  owner's Word files with the Open XML SDK, compares LibreOffice's text
  export and re-save of every fixture with the expected texts, and proves
  each check rejects the deliberately broken `d1_corrupt.docx` (AGENTS.md,
  "Validation").
- Neither is Word. The owner opens each D milestone's fixtures and round
  trips in Word for Mac and records the result in
  [`word-checks.md`](word-checks.md).
