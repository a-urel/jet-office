# Shapes, text boxes and icons

**Status: analysis only, nothing planned.** On 2026-11-10 the owner looked at
Excel for Mac's Insert > Shapes gallery and the Icons pane, and asked whether
`jet_office` supports them. This page answers that, and says what supporting
them would take. No level is chosen. Until one is, shapes, text boxes and
icons stay as `0009` and `0010` keep everything the models do not type:
byte for byte.

**How far the evidence goes.**

- No owner file holds a shape or an icon yet. Section 1 comes from ECMA-376
  and Microsoft's documentation, not from files.
- Section 2 comes from tests on hand-made XML, my own, not Office output:
  `test/xlsx/model/object_shift_test.dart` (group "shapes and icons") and
  `test/docx/shapes_test.dart`.
- Word and Excel for Mac are the oracle, and only the owner's files count
  (section 6).

## 1. Where they live (from the standard, unconfirmed)

Namespaces: `xdr` spreadsheet drawing, `a` DrawingML main, `wp` Word drawing,
`wps` Word 2010 shape, `wpg` Word 2010 group, `mc` markup compatibility,
`v` VML, `asvg` `http://schemas.microsoft.com/office/drawing/2016/SVG/main`.

### XLSX

Everything is in the sheet's drawing part, `xl/drawings/drawingN.xml`, the
part pictures and charts already use. Each object is one anchor
(`xdr:twoCellAnchor`, `xdr:oneCellAnchor` or `xdr:absoluteAnchor`) holding:

- **A shape**, `xdr:sp`:
  - `xdr:nvSpPr`: `xdr:cNvPr` (id, name, `descr`) and `xdr:cNvSpPr`;
  - `xdr:spPr`: `a:xfrm` (offset, size, `rot`, `flipH`, `flipV`), then the
    geometry, then fill, line and effects;
  - the geometry is a preset, `a:prstGeom prst="…"` with adjust values in
    `a:avLst` (187 names in `ST_ShapeType`: `rect`, `ellipse`, `roundRect`,
    `rightArrow`, `star5`, …), or a freeform, `a:custGeom` with its own paths;
  - fill: `a:noFill`, `a:solidFill`, `a:gradFill`, `a:blipFill`,
    `a:pattFill`; line: `a:ln` with width, dash, ends;
  - `xdr:style`: references into the theme (`a:lnRef`, `a:fillRef`,
    `a:effectRef`, `a:fontRef`). Excel's default look comes from here, not
    from `spPr`;
  - `xdr:txBody`: DrawingML text, `a:bodyPr`, `a:lstStyle`, then `a:p` with
    `a:r` (`a:rPr` and `a:t`);
  - attributes `macro` and `textlink`. **`textlink` is a formula**: a shape
    whose text shows a cell (select it, type `=A1` in the formula bar) holds
    `textlink="$A$1"`.
- **A connector**, `xdr:cxnSp`: like a shape without text; `a:stCxn` and
  `a:endCxn` name the ids of the shapes it joins and the connection site.
  Its geometry is stored; Excel reroutes it only when a joined shape moves in
  Excel.
- **A group**, `xdr:grpSp`: `xdr:grpSpPr` with `a:xfrm` holding `a:chOff`
  and `a:chExt`, the child coordinate space, then shapes, connectors,
  pictures and groups. Only the group has an anchor; children are placed in
  the group's coordinates.
- **A text box** is a shape with `xdr:cNvSpPr txBox="1"`, usually `rect`.
- **An icon** (Insert > Icons, and any SVG picture) is a picture, `xdr:pic`,
  whose `a:blip r:embed` names a PNG, with one `a:ext` of uri
  `{96DAC541-7B7A-43D3-8B79-37D633B846F1}` holding `asvg:svgBlip r:embed`
  naming the SVG part (`image/svg+xml`). The PNG is the fallback for readers
  without SVG. The extension sits in `a:extLst`, which every reader may
  ignore, so the anchor itself is not wrapped.
- **Wrapped anchors.** Excel wraps an anchor in `mc:AlternateContent` when
  the object needs Office 2010 or later: an equation's text box
  (`docs/equations.md`), ink (decision `0020`), 3D models. Whether any item of
  the Shapes gallery is wrapped is to be confirmed from the owner's file.

### DOCX

A drawing is a run's `w:drawing`, holding `wp:inline` (in the line of text) or
`wp:anchor` (floating: position, wrapping, z-order, `wp:docPr`).

- **A shape** is `a:graphicData uri="…/wordprocessingShape"` holding
  `wps:wsp`: `wps:cNvSpPr`, `wps:spPr` (the same DrawingML as Excel's
  `spPr`), `wps:style`, and `wps:bodyPr`.
- **Its text** is `wps:txbx` holding `w:txbxContent`: ordinary
  WordprocessingML paragraphs and tables, not DrawingML text. A text box is a
  shape with `txBox="1"`.
- **A group** is `wpg:wgp` (`…/wordprocessingGroup`), with `wps:wsp`,
  `pic:pic` and `wpg:grpSp` inside.
- **Word wraps both** in `mc:AlternateContent`: `mc:Choice Requires="wps"`
  (or `wpg`) holds the `w:drawing`, and `mc:Fallback` holds a `w:pict` with
  VML (`v:shape`, `v:rect`, `v:line`, `v:group`), whose `v:textbox` holds a
  **second copy** of the `w:txbxContent`.
- **An icon** is a `pic:pic` with the same `asvg:svgBlip` extension, inline or
  anchored. Which of the two Word uses by default is to be confirmed.

### What both share

`spPr` (geometry, fill, line, transform), `style`, preset names, colours
(`a:srgbClr`, `a:schemeClr` with `lumMod` and the like) and the SVG
extension are the same DrawingML in both formats. The anchor and the text
differ: Excel anchors to cells and writes DrawingML text; Word anchors to the
page or paragraph and writes WordprocessingML text with a VML fallback.

## 2. What the models do today

### Kept byte for byte

**XLSX.** `DrawingPart` (`lib/src/xlsx/model/drawing_part.dart`) captures each
child of `xdr:wsDr` as `OpaqueXml` and writes it as read. It types only an
anchor that directly holds a `pic`. It collects every `cNvPr` id of the
subtree (groups and wrapped anchors included), so a new picture's id clashes
with none of them. `relationshipIdsIn` collects every relationship attribute
of an entry, so an icon's SVG relationship counts as used.

**DOCX.** `StoryReader` reads a `w:drawing` as `DocxPicture` only when it is
one `wp:inline` with one `pic:pic`; any other drawing, and every
`mc:AlternateContent`, is `DocxOpaqueRunContent`, written as read. `SaveIds`
scans every `wp:docPr` of every story part, inside `mc:Choice` too.

Pinned by tests (hand-made XML):

| What | Result | Test |
|---|---|---|
| XLSX: a preset shape with text, a connector, a group and an icon | move with a row insert; everything else of the part as written | `object_shift_test.dart`, "a shape, a connector, a group and an icon move on an insert" |
| XLSX: an icon | `pictures` lists it as a PNG picture (its fallback); `removePicture` takes both the PNG and the SVG part out | "an icon is listed as its PNG fallback, and removing it drops both media parts" |
| DOCX: a floating text box (`wps` with VML fallback) and an inline icon | `word/document.xml` and the SVG part saved byte for byte | `test/docx/shapes_test.dart`, "a text box and an icon round-trip byte for byte" |
| DOCX: the text box's paragraph | its text is `Before  after`: the box's text is not in it; the box is one `DocxOpaqueRunContent` | "a text box's text is not in its paragraph's text" |
| DOCX: an inline icon | reads as `DocxPicture`, image the PNG fallback, the description kept | "an inline icon reads as a picture of its PNG fallback" |
| DOCX: a new picture beside a text box | takes `wp:docPr id` 8, past the box's 7 | "a new picture's id passes the text box's docPr id" |

`addPicture` takes PNG and JPEG only (`OfficeImageFormat` in
`lib/src/common/image.dart`), in both formats. `movePicture` on an icon
rewrites only the markers, so the SVG extension stays.

### Not typed

- No shape, connector, group or text box can be listed, read or written.
- A DOCX text box's paragraphs are not in `DocxParagraph.text`, nor in
  `DocxDocument`'s blocks. A template filler that walks the body does not see
  a placeholder typed inside a text box. This matters for Monépro's document
  templates.
- A floating (anchored) picture or icon in DOCX is opaque (`0010` left it
  out).
- The DrawingML layer (`lib/src/drawingml/`) has `DrawingPic`, media naming,
  chart colours (`color.dart`, in `ChartColor` terms) and chart text
  properties (`text.dart`). Nothing there reads `spPr`, a preset geometry, a
  fill, a line or a general text body.

### A defect: a shape's `textlink` does not move (W5)

`textlink` is a formula kept inside an opaque entry, and no reference holder
covers it. A row inserted above the linked cell moves the shape and the cell,
and leaves `textlink="$A$1"` naming the old cell. Excel, by the standard,
writes `$A$2`. The same cause should leave it naming the old sheet after a
rename (`Veri!$B$2`); that case is not tested.

- `object_shift_test.dart`, "a shape's textlink moves with the cell it names",
  pins it, skipped with its reason. It fails when unskipped.
- `docs/xlsx-model.md`, "Structural edits (W5)", lists it as a known gap.
- The fix is a W5 matter: a holder for drawing `textlink` (and, when a shape
  reader exists, for its typed form). Excel's behaviour waits for the owner's
  `shapes_shifted.xlsx` (section 6).
- The architecture test "every reference is held" did not catch it, because
  it looks at model files that store a formula, and this one is inside opaque
  XML.

### Wrapped anchors (the equations gap)

`DrawingEntry.shiftedBy` moves only a bare anchor (`docs/equations.md`,
`object_shift_test.dart`, "an anchor inside mc:AlternateContent moves like a
bare one", skipped). **Shapes and icons, as the standard describes them, do
not hit it**: their anchors are bare, and the icon's SVG is an `a:extLst`
extension, not `mc:AlternateContent`. The test above shows them moving. If
the owner's file shows Excel wrapping a gallery shape, the same fix covers it.
DOCX has no structural edit, so the gap does not exist there.

### LibreOffice in the validation chain (risk, untested)

A fixture with shapes runs through LibreOffice's text export and re-saves.
Its text export may include or leave out text box text, and its re-save may
rewrite shapes (VML fallback, `wps` defaults). A shape fixture may need
`DocxFixture.libreOfficeText`, or entries in `resaveAllowedWarnings`.

## 3. Levels of support

Sizes are rough; one milestone is about D3 (tables).

**(a) A typed read of shapes.**

- A sheet's and a document's shapes: kind (shape, text box, connector, group,
  other), name, description, preset name or "freeform", adjust values,
  position and size (the anchor, plus `xfrm`), rotation and flips, fill
  (none, solid colour, other kept opaque), line (width, colour, dash, none),
  the theme style references, text (plain, plus paragraph and run properties
  read as far as a writer would need), `textlink`; a group's children; a
  connector's joined ids.
- DOCX: the text box's content as `DocxBlock`s, read by the story reader that
  already reads cells, headers and footers. Whether the body's text tools see
  it is a separate rule (open question 3).
- Unknown content stays opaque; nesting bounded by `maxDepth`; a fuzz corpus
  entry in each format (decision `0007`).
- **Cost:** about one milestone for both formats.
- **Risk:** low for fidelity, since it only reads. The work is in effective
  values: a shape with no `spPr` fill draws its theme style's fill, so "fill
  `null`" and "no fill" differ, and the reader must say which.

**(b) Adding shapes from a builder.**

- Preset geometries (an enum of the 187 names), solid fill, line, text with
  run properties (bold, italic, size, colour, font), alignment; connectors
  between two built shapes; groups.
- XLSX: one anchor per object in the drawing part. The part, its
  relationship, `nextId` and anchor writing exist from the picture work (W4);
  C2 adds the graphic frame next to them.
- DOCX: needs the first `wp:anchor` writer (position, wrapping, z-order),
  which C3 needs too for an anchored chart. Then `wps:wsp`, and the fallback
  question: Word writes a VML copy; whether a file with no fallback opens
  without repair in Word for Mac is an owner check.
- **Excel's and Word's defaults are the hard part.** A shape drawn in Excel
  carries `xdr:style` and a `txBody` of fixed values, and looks wrong without
  them. Decision `0011` sets the rule: a new part takes Office's own values,
  read from the owner's files.
- **Cost:** about one milestone per format, two in all. Connectors and groups
  add about half a milestone (group coordinate maths, connection sites per
  preset).
- **Risk:** medium. Valid XML can still look wrong; the owner's check decides.

**(c) SVG pictures and icons.**

- `OfficeImageFormat.svg`, and `addPicture` taking an SVG with a PNG
  fallback: the picture writer adds the `asvg:svgBlip` extension and a second
  media part. Reading lists an icon with both images.
- **The fallback.** Pure Dart cannot rasterise SVG, and `jet_office` has no
  rendering (AGENTS.md). The options:
  1. **The caller gives the PNG.** A Flutter app can draw the SVG with
     `flutter_svg` and `dart:ui` and pass the bytes. Exact, and keeps
     `jet_office` pure. Recommended.
  2. **A fixed placeholder PNG** (transparent, the picture's size). Office
     2016 and later draw the SVG and never show it; Office 2013 and older,
     and any reader without SVG, show nothing.
  3. **A pure-Dart rasteriser for a subset.** Office's icons are single
     filled paths, so a path filler is possible. A general SVG (text,
     gradients, CSS, filters) is not. About a milestone, and every SVG becomes
     untrusted input to parse, with limits and a fuzz test. Not recommended.
  4. **No fallback at all** (`a:blip` with only the extension). The schema
     allows a blip without `r:embed`; whether Excel and Word for Mac accept
     it is an owner check.
- The icons of Office's Icons pane are Microsoft's content, licensed for use
  in Office; `jet_office` ships none. The caller brings its own SVG (an app's
  icon set).
- An SVG is added as given, checked only for an `svg` root and a size bound;
  it is never parsed further.
- **Cost:** half a milestone for both formats with option 1, on top of the
  existing picture paths. DOCX floating icons need (b)'s anchor writer.
- **Risk:** low. Excel and Word decide which image they show.

**(d) Text boxes.**

- Read with (a), written with (b): a text box is a shape with
  `txBox="1"`.
- XLSX: DrawingML text only, with (b)'s run properties.
- DOCX: the content is WordprocessingML blocks, so the existing paragraph
  and table builders fill it. The VML fallback holds a second copy of the
  same content, which a writer must keep in step or leave out.
- **Cost:** about half a milestone beyond (a) and (b).
- **Risk:** medium in DOCX, because of the two copies.

**(e) Editing existing shapes.**

- Replace a shape's or text box's text, change fill and line, move, resize,
  remove. Each edit splices the part as `DrawingEntry.movedTo` does today,
  so everything not edited keeps its bytes.
- **The traps.**
  - DOCX: an edit must change the `mc:Choice` and the `mc:Fallback` copy
    alike, or drop the fallback. Its VML is a second format to write.
  - Connectors do not follow a moved shape; only Excel and Word reroute.
  - A group's child is placed in the group's coordinates, not the sheet's.
  - Removing a shape a connector names leaves a dangling `stCxn`.
- Replacing the text of a DOCX text box is what a template filler needs
  first; it is (e)'s smallest useful slice.
- **Cost:** about one milestone.
- **Risk:** medium to high for fidelity. Needs (a).

## 4. Where the code would sit

Under AGENTS.md's hard rules and decision `0015`:

- **Shared DrawingML, `lib/src/drawingml/`.** The `spPr` reader and writer
  (transform, preset and custom geometry, fill, line), the theme style
  references, the preset enum, the DrawingML text body (Excel's shape text),
  and the SVG blip extension next to `picture.dart`. `0015`'s imports suffice
  (`dart:`, `../opc/`, `../xml/`, `../common/`, `jet_charts_core`,
  `jet_core`); no new import, so `layering_test.dart` does not change.
  Internal types keep the prefix `Drawing`.
- **Colours.** `color.dart` speaks `ChartColor`. A shape's fill can reuse it
  (it already handles `schemeClr` with luminance) or get a colour type of its
  own. Open question 5.
- **Public value types** (a preset, a fill, a line, a text run) shared by
  both formats would sit in `lib/src/common/`, beside `OfficeImage`, since
  `common` imports neither format and both hosts may expose them.
- **Hosts.**
  - `lib/src/xlsx/`: listing and adding through `DrawingPart` and the sheet
    (`xlsx_sheet_pictures.dart` grows into a drawings part of the sheet), the
    `textlink` holder in `reference_holders.dart`.
  - `lib/src/docx/`: `wp:anchor` reading and writing in `drawing.dart`, the
    `mc:AlternateContent` choice, `w:txbxContent` through the story reader
    and writer, and the VML fallback, which is DOCX's own: `lib/src/docx/`
    may not import the workbook's `vml_part.dart`.
- **No rule changes.** One cell encoder and decoder: untouched. The OPC layer
  stays format-free. "Every reference is held" gains the `textlink` holder.

### Overlap with C2 and C3

- **C2** (`docs/drawingml-charts.md`, "Open for C2") adds the graphic frame
  anchor, `addChart` and the charts of a sheet. Pictures, charts and shapes
  share the drawing part, its ids, its anchors and its removal rules, so a
  sheet should list them through one design (for example one sealed list of
  drawing objects) rather than three getters that each skip the others. C2
  makes that design first; shapes extend it.
- **C3** ("Open for C3") needs inline and anchored drawings in the body. The
  `wp:anchor` model (position, wrapping, z-order) is the same for a chart, a
  floating picture and a shape. Whichever comes first builds it once.

### A decision record

**Needed once a level beyond reading is chosen, and better at the start.**

- `0010` puts text boxes and floating pictures among what "stay opaque" in
  phase 4. Typing them supersedes that part of its list, as `0019` did for
  equations; `0010` is not edited.
- `0009` does not name shapes. Its rule that milestones move content from
  opaque to typed covers an XLSX read, but the record should still name the
  scope.
- It should name the milestone letter, which levels are in, where the public
  value types sit, the fallback rules (VML, SVG's PNG) and the icon licence
  point.
- No import changes, so `0015` stands.

## 5. Recommendation

**Milestone letter S** (Shapes): S1, S2, …. M, R, N, W, D, C and J are
milestones, Q is reserved for equations, and E is the Excel checks.

**S1, the first milestone: (a), a typed read of shapes and text boxes in both
formats**, with the DOCX text box content as blocks and the SVG of an icon
readable beside its PNG. It is read-only, low-risk, needs no writer and no
VML, and it answers Monépro's template question (what text sits in a text
box). The W5 `textlink` fix goes in its own W5 follow-up, not in S1.

**Order relative to C2 and C3.**

1. C2 first, as Monépro's dashboards need it. It sets the sheet's drawing
   object listing.
2. S1 after C2, extending that listing with shapes. S1's DOCX half does not
   wait for anything.
3. S2: (c) icons and SVG pictures, inline in both formats (option 1, the
   caller's PNG).
4. S3: (b) and (d) in XLSX, on C2's write path.
5. S4: (b) and (d) in DOCX, with the `wp:anchor` writer, before or together
   with C3, which needs the same anchor.
6. S5: (e), editing, starting with replacing a text box's text.

If the owner's need is icons in exports rather than reading templates, S2
can come first: it stands on the picture paths that exist today.

## 6. The owner's reference files (Turkish steps, not run)

When shapes are planned, these steps go in
`test/fixtures/owner/shapes/TALIMATLAR.md`. Nothing here has been run, and no
result is invented.

```markdown
# Şekil ve simge referansı: Excel ve Word'de hazırlama

Bu adımlar, Excel ve Word for Mac'in şekilleri, metin kutularını ve simgeleri
dosyaya nasıl yazdığını görmek içindir. `jet_office` bu dosyalarla
karşılaştırılır. Yalnızca senin çalıştırman sonuç sayılır; hiçbir sonuç
uydurulmaz. Menü adlarını Türkçe Office'e göre yazdım; bir ad farklıysa
yanındaki İngilizce adına bak. Her şekilde yalnızca adı geçen şeyi yap; başka
bir ayara dokunma. Şekilleri üst üste gelmeyecek biçimde yerleştir; yerleri
kabaca yazdığım hücreler olsun.

## 1. Excel: `shapes.xlsx`

1. Excel'de yeni boş bir çalışma kitabı aç. İlk sayfanın adını `Şekil` yap.
   **+** ile ikinci bir sayfa ekle, adını `Veri` yap.
2. `Şekil` sayfasında `A1`'e `Bağlı metin` yaz. `Veri` sayfasında `B2`'ye
   `Öteki sayfa` yaz. `Şekil` sayfasına dön.
3. **Ekle > Şekiller** (Insert > Shapes) menüsünden sırayla şunları çiz:
   1. **Dikdörtgen** (Rectangle), kabaca `B3:D6`. İçine tıkla, `Merhaba`
      yaz. **Şekil Biçimi > Şekil Dolgusu** ile kırmızı yap.
   2. **Oval**, kabaca `F3:H6`. Hiçbir şeyini değiştirme.
   3. **Yuvarlatılmış Dikdörtgen** (Rounded Rectangle), kabaca `J3:L6`.
      Köşedeki sarı tutamağı biraz sürükle (köşeler daha yuvarlak olsun).
   4. **Sağ Ok** (Right Arrow), kabaca `B9:D11`.
   5. **5 Köşeli Yıldız** (Star: 5 Points), kabaca `F9:H12`.
   6. **Çizgi** (Line), `J9`'dan `L12`'ye. **Şekil Biçimi > Şekil Anahattı**
      ile kalınlığı 3 nk, çizgi türünü kesik çizgi yap.
   7. **Dirsek Bağlayıcı** (Connector: Elbow): dikdörtgenin sağ kenarındaki
      noktadan ovalin sol kenarındaki noktaya çiz (iki uç da şekillere
      yapışsın, uçlarda gri/yeşil nokta görünür).
   8. **Serbest Form: Şekil** (Freeform: Shape), kabaca `B15:D18`: birkaç
      noktaya tıklayarak kapalı bir şekil çiz, ilk noktaya tıklayıp kapat.
   9. **Dikdörtgen**, kabaca `F15:H17`. **Şekil Biçimi > Şekil Dolgusu > Dolgu
      Yok**, anahattı mavi yap. Sonra şekli 30° döndür (**Şekli Biçimlendir >
      Boyut ve Özellikler > Döndürme**, 30).
4. **Metin kutusu:** **Ekle > Metin Kutusu** (Text Box) ile kabaca `J15:L17`
   arasına bir kutu çiz, içine `Metin kutusu ğüşiöç` yaz. Metni seç, **Kalın**
   yap ve yazı boyutunu 14 yap.
5. **Hücreye bağlı metin:**
   1. **Dikdörtgen** çiz, kabaca `B21:D23`. Şekil seçiliyken (içine metin
      yazmadan) formül çubuğuna `=$A$1` yaz, Enter'a bas. Şekilde
      `Bağlı metin` görünmeli.
   2. Bir **Dikdörtgen** daha çiz, kabaca `F21:H23`. Formül çubuğuna
      `=Veri!$B$2` yaz, Enter'a bas. Şekilde `Öteki sayfa` görünmeli.
6. **Grup:** **Oval** çiz (kabaca `J21:K23`) ve yanına bir **Dikdörtgen**
   (kabaca `L21:M23`). İkisini Shift ile seç, sağ tıkla > **Gruplandır >
   Gruplandır** (Group).
7. **Simgeler:**
   1. **Ekle > Simgeler** (Insert > Icons). Herhangi bir simge seç ve ekle.
      Kabaca `B26:C28` üstüne taşı. Simgenin adını not et (bölmede üstüne
      gelince görünür; yoksa neye benzediğini yaz).
   2. Bir simge daha ekle, kabaca `F26:G28`. **Grafik Biçimi > Grafik
      Dolgusu** (Graphics Fill) ile turuncu yap.
   3. Bir simge daha ekle, kabaca `J26:K28`. Sağ tıkla > **Şekle Dönüştür**
      (Convert to Shape). Bu seçenek yoksa not et.
8. **Taşıma ayarları:** yıldıza sağ tıkla > **Şekli Biçimlendir > Boyut ve
   Özellikler > Özellikler**: **Taşı ama hücrelerle boyutlandırma** (Move but
   don't size with cells). Sağ oka aynı yerden **Hücrelerle taşıma veya
   boyutlandırma** (Don't move or size with cells). Diğerlerine dokunma.
9. **Dosya > Farklı Kaydet** ile `shapes.xlsx` adıyla, biçim **Excel Çalışma
   Kitabı (.xlsx)** olarak kaydet.
10. Şimdi aynı dosyada:
    1. `Şekil` sayfasında 1. satırın başlığına sağ tıkla > **Ekle** (bir satır
       eklenir), sonra B sütununun başlığına sağ tıkla > **Ekle** (bir sütun
       eklenir).
    2. `Veri` sayfasının adını `Veri 2` yap.
    3. Şekillerin, simgelerin, bağlayıcının ve grubun kayıp kaymadığına bak.
       5. adımdaki iki şekli tek tek seçip formül çubuğunda ne yazdığını not
       et (beklenen `=$A$2` ve `='Veri 2'!$B$2`, ama ne görüyorsan onu yaz).
    4. **Dosya > Farklı Kaydet** ile `shapes_shifted.xlsx` adıyla kaydet.
11. Excel'in sürümünü not et (Excel > Excel Hakkında).

## 2. Word: `shapes.docx`

1. Word'de yeni boş bir belge aç. Birinci paragrafa `Şekiller` yaz.
2. Yeni bir paragrafa `Önce ` yaz. **Ekle > Şekiller > Dikdörtgen** ile
   paragrafın yanına bir dikdörtgen çiz. Sağ tıkla > **Metin Ekle**, içine
   `Kutu içi` yaz. Kutunun dışına tıkla, paragrafın sonuna ` sonra` yaz.
3. **Metin kutusu:** **Ekle > Metin Kutusu > Metin Kutusu Çiz** (Draw Text
   Box) ile bir kutu çiz. İçine iki satır yaz: `Metin kutusu ğüşiöç` ve
   `{{musteri}}`. İlk satırı **Kalın** yap.
4. **Ekle > Şekiller** ile sırayla: bir **Çizgi**, bir **Sağ Ok**, bir **Oval**
   çiz. Ovali **Şekil Biçimi > Şekil Dolgusu** ile yeşil yap.
5. **Grup:** bir **Dikdörtgen** ve bir **Oval** daha çiz, ikisini Shift ile
   seç, sağ tıkla > **Gruplandır > Gruplandır**.
6. **Metinle aynı hizada şekil:** bir **5 Köşeli Yıldız** çiz, sağ tıkla >
   **Metni Kaydır > Metinle Aynı Hizada** (In Line with Text).
7. **Simgeler:**
   1. Yeni bir paragrafa `Simge: ` yaz, sonra **Ekle > Simgeler** ile bir
      simge ekle. Word onu metnin içine mi koydu, yoksa yüzen (metni
      kaydıran) bir resim olarak mı? Not et; ayarını değiştirme.
   2. Bir simge daha ekle, sağ tıkla > **Metni Kaydır > Kare** (Square).
   3. Bir simge daha ekle, sağ tıkla > **Şekle Dönüştür** (Convert to
      Shape). Bu seçenek yoksa not et.
8. **Üst bilgi:** üst bilgiye çift tıkla, oraya küçük bir **Dikdörtgen** çiz
   ve içine `Logo` yaz. Üst bilgiden çık.
9. Belgenin sonuna bir paragraf `Son.` yaz (belge bir şekille bitmesin).
10. **Dosya > Farklı Kaydet** ile `shapes.docx` adıyla, biçim **Word Belgesi
    (.docx)** olarak kaydet. Word'ün sürümünü not et (Word > Word Hakkında).

## 3. Gönder

İki Excel dosyasını (`shapes.xlsx`, `shapes_shifted.xlsx`), `shapes.docx`'i ve
notlarını Claude'a gönder: sürümler, simgelerin adları, Excel'de 10. adımda
şekiller kaydı mı ve formül çubuğunda ne yazdı, Word'de 7. adımda simge
metnin içinde mi yüzen mi geldi, **Şekle Dönüştür** var mıydı. İstersen kendin
`test/fixtures/owner/shapes/` altına koyup commit edebilirsin; istemezsen
Claude yapar. Yalnızca senin çalıştırman sonuç sayılır; hiçbir sonuç
uydurulmaz.
```

What each step answers:

| Step | Question |
|---|---|
| Excel 3 | preset names, adjust values, fill, line, dash, rotation, `custGeom`, a connector's `stCxn` and `endCxn`, Excel's `xdr:style` and `txBody` defaults; whether any gallery shape is wrapped in `mc:AlternateContent` |
| Excel 4 | a text box's `txBox="1"` and run properties |
| Excel 5 | `textlink` as Excel writes it, same sheet and another sheet |
| Excel 6 | `grpSp`, `chOff` and `chExt` |
| Excel 7 | the icon's `svgBlip`, the PNG fallback's size, a recoloured icon (is the SVG rewritten or a colour added?), what "Convert to Shape" writes |
| Excel 8 | `editAs` on shapes |
| Excel 10 | the oracle for the `textlink` gap (section 2) and for shapes moving on insert |
| Word 2 to 6 | `wps:wsp` in `wp:anchor` and `wp:inline`, the VML fallback, the two copies of a text box's text, `wpg:wgp` |
| Word 3 | a placeholder in a text box, as a template filler would meet it |
| Word 7 | whether Word inserts icons inline or floating; the same extension as Excel |
| Word 8 | a shape in a header |

## 7. Open questions for the owner

1. Which level first: (a) reading, (c) icons, or (b) writing shapes? Which
   consumer needs it: Monépro's templates (reading text boxes), its exports
   (icons), or `jet_print`'s reports (lines, boxes and text boxes)?
2. Is the order C2, then S1, acceptable, or is a shape level more urgent than
   C2?
3. Should a DOCX text box's text count in the body's text (`DocxParagraph.text`,
   the text tools, a template filler), or stay a separate story?
4. SVG fallback: the caller gives the PNG (recommended), a placeholder, or no
   fallback?
5. A shape's colour: reuse `ChartColor` from `jet_charts_core`, or a colour
   type of `jet_office`'s own?
6. When writing DOCX shapes: write Word's VML fallback, or leave it out if
   Word for Mac opens the file without it?
7. May the `textlink` gap be fixed as a W5 follow-up once
   `shapes_shifted.xlsx` exists?
8. Is the letter S acceptable?
