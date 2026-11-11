# Equations (Office Math, OMML)

**Status: parked.** On 2026-11-10 the owner decided that equations will come
later. The level of support, an editor and the order are not decided, and need
not be yet. Until then equations stay opaque, kept byte for byte (decisions
`0009` and `0010`). Decision `0019` records that they are covered in the end.

This page keeps the analysis of 2026-11-10, so the next plan starts from it.

**How far the evidence goes.** No owner file holds an equation yet. Section 1
is taken from ECMA-376 and Microsoft's documentation, not from files. Sections
2 and 3 come from runs on hand-made files, my own XML, not Office output. Word
and Excel for Mac are the oracle, and only the owner's files count (section 7).

## 1. Where equations live (from the standard, unconfirmed)

The namespace `m` is `http://schemas.openxmlformats.org/officeDocument/2006/math`.

### DOCX

- **An inline equation** is an `m:oMath` that is a child of `w:p`, a sibling
  of `w:r`. It may also sit in `w:hyperlink`, `w:ins`, `w:del`, `w:smartTag`,
  `w:sdtContent` or `w:fldSimple`.
- **A display equation** is an `m:oMathPara` (with `m:oMathParaPr` and `m:jc`)
  holding one or more `m:oMath`. Word writes it inside its own `w:p`. The
  schema also allows it at block level, directly under `w:body` or `w:tc`.
- **Every story can hold equations:** the body, table cells, headers, footers,
  notes and comments.
- **Run properties.** A math run (`m:r`) carries Word's run properties `w:rPr`
  (usually `Cambria Math`) and `m:rPr`. Its text is in `m:t`, never `w:t`.
- **Math defaults.** `word/settings.xml` carries `m:mathPr`. The owner's
  `blank.docx` has it, with `mathFont Cambria Math`, `defJc centerGroup`,
  `intLim subSup` and `naryLim undOvr`. The library's own blank document
  (`blankSettings`) does not. Word uses defaults when it is missing.

### XLSX

- **Insert > Equation draws a text box** (`xdr:sp` with `cNvSpPr txBox="1"`)
  in `xl/drawings/drawingN.xml`.
- **Excel wraps the whole anchor** in `mc:AlternateContent`:
  - The choice, `mc:Choice Requires="a14"`, holds the anchor. Its `a:p` holds
    `a14:m`, then `m:oMathPara`, then `m:oMath`.
  - The fallback, `mc:Fallback`, holds a copy of the anchor whose `a:p` holds
    the linear form as plain `a:r` and `a:t` runs.
  - Both copies share the same `cNvPr` id.
- **Run properties.** A math run carries DrawingML's `a:rPr`, not `w:rPr`.
- **To confirm from the owner's file:**
  - whether the wrapper is around the anchor or only around the `a:p`;
  - whether the fallback is text or a picture;
  - what the linear form is.

### What follows for a design

The OMML tree is the same in both formats. **Only the run properties in
`m:r` and `m:ctrlPr` belong to the host.** A shared OMML layer must keep them
opaque, or hand them to the host. It must never type them itself.

## 2. What the models do today

### Byte-for-byte keeping

**DOCX.** `StoryReader` keeps an `m:oMath` or `m:oMathPara` in place:

- under `w:p`, as a `DocxOpaqueInline`;
- under `w:body` or `w:tc`, as a `DocxOpaqueBlock`.

`SaveIds` scans the raw bytes of every story part, so a bookmark inside an
equation still counts when new ids are chosen. `tool/edit_docx.dart` replaces
only paragraphs of plain runs, so it leaves an equation's paragraph alone.

The hand-made file was `features.docx` with four equations: an inline one, a
display one, one in a table cell and one in a header.

- `tool/round_trip_docx.dart`: exit 0.
- `tool/edit_docx.dart`: exit 0.
- Open XML SDK: no errors.

**XLSX.** `DrawingPart` keeps every child of `xdr:wsDr` as written. It collects
`cNvPr` ids from the whole subtree, so a new picture's id does not clash with
the fallback's. `pictures` does not list shapes. There is no text or shape API
for drawings, so an equation cannot be read at all.

The hand-made file was `chart_reference_j4.xlsx` with an equation box added.

- `tool/round_trip_model.dart`: exit 0.
- Open XML SDK: no errors. It accepts `a14:m`.

### The missing equation text in DOCX

`VisibleTextCollector` counts only `w:t` inside `w:r`, and gives `''` for
anything in another namespace. So an equation adds nothing to
`DocxParagraph.text`, nor to the text tools and the expected texts:

- a paragraph `Inline ` + equation + ` end` reads `Inline  end`;
- a display equation's paragraph reads `''`.

### A shape inside `mc:AlternateContent` moves (unconfirmed)

`DrawingEntry.shiftedBy` moves every `xdr:oneCellAnchor` or
`xdr:twoCellAnchor` that is a direct child of the drawing's root, or of an
`mc:Choice` or the `mc:Fallback` of an `mc:AlternateContent` there, by the
same rules, so the equation's two anchors move together on a row or column
insert or delete, as their cells move. An `mc:AlternateContent` whose branches
hold anything else, or no anchor, stays as written and warns
`referenceNotShifted`.

- Until W6, on the hand-made workbook, `tool/edit_model.dart` inserted a
  column at B: every chart moved, and the equation's two anchors stayed at
  col 4. That gap is fixed.
- **It is wider than equations.** It covers any object Excel wraps that way,
  likely including other objects that need Office 2010 and possibly ink.
- **Unconfirmed.** The behaviour follows the standard (Excel moves the box, as
  it moves a bare two-cell shape); Excel's behaviour is to be confirmed by the
  owner's `equations_shifted.xlsx` (W6 check, section 7).
- `test/xlsx/model/object_shift_test.dart` pins it, in the group "anchors
  inside mc:AlternateContent" ("an anchor inside mc:AlternateContent moves
  like a bare one" and four more).
- `docs/xlsx-model.md`, "Structural edits (W5)", lists it.

### LibreOffice in the validation chain (risk, untested)

LibreOffice turns OMML into its own Math objects. Three checks may disagree
with the model on an equation fixture:

- its text export (`compare_text`);
- its DOCX re-save (`compare_resaved_docx`);
- its XLSX re-save, which may keep only the fallback.

An equation fixture will probably need `DocxFixture.libreOfficeText` or
`libreOfficeTextSkip`.

## 3. Levels of support

Sizes are rough. One milestone is about D3 (tables).

**(a) Keep, plus plain text.**

- A `DocxEquation` (inline and block): typed, but kept opaque, with a `text`
  that `DocxParagraph.text` includes.
- Optionally, a read-only list of a sheet's equations: anchor and text.
- **The text rule.** Joining the `m:t` texts turns `y=a/b` into `yab`, which
  misleads. A linear form close to UnicodeMath (`y=a/b`, `x^2`, `√(x)`) needs a
  walk over the common object kinds.
- **Cost:** half to two thirds of a milestone.
- **Risk:** low for fidelity. The expected texts change for files with
  equations.

**(b) A typed read-only OMML tree.**

- Sealed classes for the 22 object kinds: `acc`, `bar`, `box`, `borderBox`,
  `d`, `eqArr`, `f`, `func`, `groupChr`, `limLow`, `limUpp`, `m`, `nary`,
  `phant`, `rad`, `sPre`, `sSub`, `sSubSup`, `sSup`, `r`, plus `oMathPara`.
  Each comes with its properties.
- Unknown content is kept.
- Nesting is bounded by `maxDepth`.
- A fuzz corpus entry.
- **Cost:** about one milestone.
- **Risk:** low, as it only reads. The work is in matching Word's property
  defaults.

**(c) Writing equations.**

- A builder API (`OmmlFraction`, `OmmlScript`, `OmmlRadical`, `OmmlNary`,
  `OmmlMatrix`, …) and the DOCX host (`addEquation`), with `Cambria Math` in
  `w:rPr`.
- Perhaps Word's `m:mathPr` in new documents (decision `0011`'s values).
- A linear format is its own step. A LaTeX subset is smaller. UnicodeMath
  (Unicode TN #28) is large. Either is an untrusted-text parser, with limits
  and a fuzz test.
- **Cost:** about one milestone for the builder and DOCX, one more for a LaTeX
  subset, two or more for UnicodeMath.
- **Risk:** Word's rendering is the oracle. Valid XML can still look wrong.

**(d) The XLSX text box host.**

- Write the wrapped anchor: an `a14:m` choice and a fallback.
- Move, remove and list it.
- **Needs** (c)'s writer, an `a:rPr` writer for math runs, and the model's
  first shape writer.
- **Cost:** about one milestone.
- **Risk:** medium. Excel's text box defaults are unknown. It overlaps C2's
  drawing write path, so it comes after C2 or with it.

## 4. An equation editor (asked, not decided)

**An editor is not part of `jet_office`.** AGENTS.md: "no editors, no
rendering". It would be a separate Flutter package of the workspace, with its
own decision record. Its model would be the OMML tree, so what the user builds
goes to Word and Excel without loss.

**Ready packages on pub.dev** (2026-11-10, from their descriptions; none
tried):

| Package | What it offers | Notes |
|---|---|---|
| `flutter_math_fork` 0.7.4 | pure-Dart TeX rendering, with an AST and a parser | simpleclub, Apache-2.0, the most used |
| `math_keyboard` 0.4.0 | typeset input field with an on-screen keyboard; TeX out | simpleclub, BSD-3, narrow set of structures |
| `val_latex` / `val_latex_flutter` 0.1.4 | pure-Dart TeX parser and layout, OpenType math fonts | BSD-3, young |
| `katex` 1.0.0 | pure-Dart KaTeX box tree painted in Flutter | MIT, new |
| `flutter_tex` 5.3.0 | WebView and JavaScript | heavy; avoid |
| `latext` 0.5.1 | LaTeX inside text | EUPL-1.2, copyleft |

**None is an Office-level structured editor.** Such an editor needs a 2D
cursor, placeholders, a ribbon, and linear and built-up modes.

**The options:**

1. **LaTeX input with a live preview.** Levels (b) and (c) plus a LaTeX subset,
   about three milestones, and one to two weeks of UI.
2. **Visual input on `math_keyboard`.** Option 1 plus about one milestone,
   with a fork for the missing structures.
3. **An Office-level visual editor.** Its own layout engine. Roughly three to
   six months.

Option 1 comes first in any plan.

## 5. Where the code would sit

- **A shared `lib/src/omml/` layer.** OMML is not DrawingML.
  - It imports only `dart:`, its own files, `../xml/`, `../opc/` and
    `../common/`.
  - `docx` and `xlsx` import it.
  - An allow-list guard in `test/architecture/layering_test.dart` enforces
    this, as `0015` did for DrawingML.
- **Host run properties** reach the layer opaque on read, and through a
  host-supplied writer on write.
- **Public names** take the prefix `Omml`.
- **Level (a) needs no decision record.** Levels (b) to (d) need one, which
  names the layer's imports and the scope of any linear format.

## 6. Milestone name

The proposal is **Q** (from "eQuation"): Q1, Q2, …. M, R, N, W, D, C and J
are milestones. E is the Excel checks (E1 to E3). O looks like 0.

Proposed first milestone, when planned: **Q1, level (a).** Q2 is (b), Q3 is
(c), Q4 is (d) after C2. A linear-format parser is optional, as Q5.

## 7. The owner's reference files (Turkish steps, not run)

When equations are planned, these steps go in
`test/fixtures/owner/equations/TALIMATLAR.md`. Nothing here has been run, and
no result is invented.

```markdown
# Denklem referansı: Word ve Excel'de hazırlama

Bu adımlar, Word ve Excel for Mac'in denklemleri dosyaya nasıl yazdığını görmek
içindir. `jet_office` bu dosyalarla karşılaştırılır. Yalnızca senin çalıştırman
sonuç sayılır; hiçbir sonuç uydurulmaz. Menü adlarını Türkçe Office'e göre
yazdım; bir ad farklıysa yanındaki İngilizce adına bak. Her denklemde yalnızca
adı geçen şeyi yap; başka bir ayara dokunma.

## 1. Word: `equations.docx`

1. Word'de yeni boş bir belge aç.
2. Birinci paragrafa `Satır içi denklem: ` yaz (sonunda bir boşluk), sonra
   **Ekle > Denklem** (Insert > Equation) de ve kutuya `x^2+1` yaz, boşluk
   tuşuna bas (Word üssü kendisi kurar). Denklemden çık, paragrafın sonuna
   ` bitti.` yaz. Denklem cümlenin içinde kalsın.
3. Yeni bir paragrafta yalnızca **Ekle > Denklem** okunun yanındaki listeden
   (yerleşik denklemler) sırayla şunları ekle, her biri kendi paragrafında:
   1. İkinci Dereceden Formül (Quadratic Formula)
   2. Binom Teoremi (Binomial Theorem)
   3. Fourier Serisi (Fourier Series)
   4. Taylor Açılımı (Taylor Expansion)
   5. Trigonometrik Özdeşlik 1 (Trig Identity 1)
4. Yeni bir paragrafta boş bir denklem ekle ve **Denklem** sekmesinin
   düğmeleriyle tek tek şunları kur (her biri ayrı denklem, ayrı paragraf):
   1. **Matris**: 2×2 boş matris, hücrelere `a`, `b`, `c`, `d` yaz.
   2. **Ayraç**: köşeli ayraç `[ ]`, içine `x+y` yaz.
   3. **Aksan**: şapka (üstte ^) ile `a`.
   4. **Limit ve Logaritma**: `lim` altında `n→∞`, yanında `1/n`.
   5. **İntegral**: alt sınır `0`, üst sınır `1`, içine `x dx`.
   6. **Büyük İşleç**: toplam, altta `i=1`, üstte `n`, yanında `i`.
   7. **İşlev**: `sin θ`.
   8. **Kök**: küp kökü (derece 3) içinde `8`.
   9. **Denklem dizisi** (**Ayraç** menüsünün altındaki iki satırlı yığın;
      İngilizce Bracket > Cases and Stacks / Equation Array): iki satır
      `x+y=2` ve `x−y=0`. Adı bulamazsan hangi düğmeyi kullandığını not et.
   10. Denklem içinde düz metin: denklem kutusuna `alan = ` yaz, sonra
       **Denklem > Metin** (Normal Text) düğmesine basıp `Türkçe ğüşiöç`
       yaz.
5. Belgeye 2×2 bir tablo ekle (**Ekle > Tablo**). Sol üst hücreye `Hücre: `
   yaz ve yanına `a/b` denklemini ekle (yaz, boşluk tuşuna bas; kesir olsun).
   Tablonun altına bir paragraf `Son.` yaz (belge tabloyla bitmesin).
6. Üst bilgiye çift tıkla, oraya bir denklem ekle: `E=mc^2`. Alt bilgiye
   satır içi bir denklem ekle: `Sayfa ` yaz, sonra denklem `π r^2`.
7. LaTeX ile yazma: yeni bir paragrafta boş denklem ekle, **Denklem**
   sekmesinde **LaTeX** biçimini seç, `\frac{1}{2}\sqrt{x}` yaz, Enter'a bas.
   Sonra yine yeni bir denklemde **Unicode** (Profesyonel/Doğrusal düğmeleri
   yanındaki biçim) seçiliyken `(a+b)/(c+d)` yaz, boşluk tuşuna bas.
8. **Dosya > Farklı Kaydet** ile `equations.docx` adıyla, biçim **Word Belgesi
   (.docx)** olarak kaydet. Word'ün sürümünü not et (Word > Word Hakkında).

## 2. Excel: `equations.xlsx`

1. Excel'de yeni boş bir çalışma kitabı aç. İlk sayfanın adını `Denklem` yap.
2. `A1` hücresine `Veri`, `A2`'ye `1`, `A3`'e `2` yaz (sayfa boş kalmasın).
3. **Ekle > Denklem** (Insert > Equation) okunun yanındaki listeden **İkinci
   Dereceden Formül**'ü ekle. Kutuyu kabaca `E3:H6` hücrelerinin üstüne taşı.
4. İkinci denklem: **Ekle > Denklem** (düğmenin kendisi), boş kutuya `a/b`
   yaz ve boşluk tuşuna bas. Kutuyu kabaca `E9:G11` üstüne taşı.
5. Üçüncü denklem: boş denklem ekle ve **Denklem > Matris** ile 2×2 matris
   kur (`1`, `0`, `0`, `1`). Kutuyu kabaca `E14:G17` üstüne taşı.
6. Karışık kutu: **Ekle > Metin Kutusu** ile bir metin kutusu çiz, içine
   `Alan: ` yaz, imleç kutunun içindeyken **Ekle > Denklem** de ve `π r^2`
   yaz. Kutuyu kabaca `J3:M5` üstüne taşı.
7. İkinci denklemin (`a/b`) kutusuna sağ tıkla > **Şekli Biçimlendir > Boyut ve
   Özellikler > Özellikler**: **Taşı ama hücrelerle boyutlandırma** (Move but
   don't size with cells) seç. Diğerlerine dokunma.
8. **Dosya > Farklı Kaydet** ile `equations.xlsx` adıyla, biçim **Excel
   Çalışma Kitabı (.xlsx)** olarak kaydet.
9. Şimdi aynı dosyada: 2. satırın başlığına sağ tıkla > **Ekle** (bir satır
   eklenir), sonra B sütununun başlığına sağ tıkla > **Ekle** (bir sütun
   eklenir). Denklem kutularının hücrelerle birlikte kayıp kaymadığına bak ve
   not et. Sonra **Dosya > Farklı Kaydet** ile `equations_shifted.xlsx`
   adıyla kaydet.
10. Excel'in sürümünü not et (Excel > Excel Hakkında).

## 3. Gönder

Üç dosyayı (`equations.docx`, `equations.xlsx`, `equations_shifted.xlsx`) ve
notlarını Claude'a gönder: sürümler, 7. adımda LaTeX ve Unicode düğmelerinin
adları ne yazıyordu, 9. adımda kutular kaydı mı. İstersen kendin
`test/fixtures/owner/equations/` altına koyup commit edebilirsin; istemezsen
Claude yapar. Yalnızca senin çalıştırman sonuç sayılır; hiçbir sonuç
uydurulmaz.
```

What each step answers:

| Step | Question |
|---|---|
| Word 2 to 6 | where `m:oMath` and `m:oMathPara` sit in the body, cells, headers and footers; one sample of each object kind; Word's defaults |
| Word 4.10 | normal text in math, and non-ASCII letters |
| Word 7 | whether anything of the LaTeX or UnicodeMath input is stored. Expected: OMML only |
| Excel 3 to 6 | the place of the wrapper, the fallback, `a:rPr` in math runs, and mixed text and math |
| Excel 7 | `editAs="oneCell"` on an equation |
| Excel 9 | whether Excel moves equation boxes on insert: the oracle for the wrapped-anchor move in section 2 |

## 8. Open questions for the owner (when it is planned)

1. Which level: (a) only, (a) and (b), or up to (c) or (d)? Which consumer
   needs it: Monépro templates, or `jet_print` reports?
2. An equation's text: a linear form (`y=a/b`, `x^2`), or joined characters
   (`yab`)?
3. If writing comes: a builder API only, LaTeX, or UnicodeMath too?
4. ~~May the W5 shift gap be fixed once `equations_shifted.xlsx` exists?~~
   Answered: fixed in W6 to the standard's behaviour (section 2);
   `equations_shifted.xlsx` will confirm Excel's.
5. Should new documents get Word's `m:mathPr`?
6. Is the letter Q acceptable?
7. Is an editor a Monépro need or a general one, and should its preview be
   TeX's or Word's?
