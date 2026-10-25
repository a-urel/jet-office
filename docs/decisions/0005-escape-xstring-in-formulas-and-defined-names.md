# 0005 — Formulas and defined names escape `_xHHHH_` like cell text

**Status:** Accepted — 2026-10-25

## Context

Excel and LibreOffice read `_xHHHH_` in cell text and sheet names
(ST_Xstring) as the character U+HHHH. Since M1 the writer escapes every `_`
that starts such a sequence as `_x005F_`, so the text `_x0041_` is stored as
`_x005F_x0041_` and shows as typed (R22 for sheet names).

Ruling R10 (the auto filter row of "Rules the writer enforces" in
`docs/xlsx-writer.md`) left formula text (ST_Formula) out of that escaping.
`escapeFormulaText` in `lib/src/xml/xml_escape.dart` did XML escaping only,
for a cell's `<f>` and for the text of the hidden `_xlnm._FilterDatabase`
defined name. R10's premise was that readers do not decode `_xHHHH_` inside
a formula. CI showed that for LibreOffice: `<f>"_x0041_"</f>` computes
`_x0041_` there.

The M2 Excel check on 2026-10-25 (Excel for the web, `m2_formula_xstring`)
showed the premise is false for Excel, the reference reader
([`0003`](0003-phase-1-scope-output-and-diagnostics.md)):

- `Probe!A1`, stored as `<f>"_x0041_"</f>`, shows `A`, and the formula bar
  reads `="A"`. Excel decodes inside `<f>`.
- The `_x0041_` sheet's filter name, stored as `'_x0041_'!$A$1:$B$3`, is
  decoded too. The filter still works, because the sheet's `<autoFilter ref>`
  holds the range as well, but a copy saved by Excel turned the name into
  `[1]A!$A$1:$B$3` with a new `xl/externalLinks/externalLink1.xml` pointing
  at a workbook `A`. Excel read a sheet `A`, found none, and made it an
  external link, without the owner touching the name.
- In the same copy, a hand-typed `="_x0041_"` was saved as
  `<f>"_x005F_x0041_"</f>` with the cached value `_x005F_x0041_`. Excel
  itself escapes `_x` in `<f>` as `_x005F_x`, exactly as in cell text.

The details are in `docs/excel-checks.md`, under "Excel decodes `_xHHHH_` in
formulas".

## Decision

**A formula's `<f>` text and a defined name's text escape `_xHHHH_` exactly
like cell text, as Excel writes them itself. This supersedes ruling R10 for
formulas and defined names.**

- **One escape, applied in one place.** `escapeFormulaText` applies
  `escapeXstring` and then `escapeXmlText`, the same two steps as shared
  strings and cached formula text. No new encoder is added; the cell encoder
  stays the only writer of `<c ` and `<v>`
  ([`0002`](0002-two-xlsx-paths-stream-and-model.md)), and the workbook part
  keeps calling the same helper for its defined names.
- **A filter name spells its sheet like the sheet's own name.** The sheet
  `_x0041_` is `<sheet name="_x005F_x0041_">` and its filter name is
  `'_x005F_x0041_'!$A$1:$B$3`, so Excel reads both as `_x0041_`.
- **Limits apply to the decoded text.** The 8,192-unit formula limit is
  checked on the text the caller passed, as for cell text and sheet names.
  The test checker decodes `<f>` before it measures.

## Consequences

**LibreOffice shows the escaped text inside a formula.** It does not decode
`_xHHHH_` in `<f>`, so `="_x0041_"` written as `"_x005F_x0041_"` computes
`_x005F_x0041_` there, while Excel shows `_x0041_`. LibreOffice shows the
same for a file Excel saved, so this matches Excel's own output. LibreOffice
was not installed where this record was written, so the value is not
measured locally: it follows from CI's M2 run, where `<f>"_x0041_"</f>`
computed `_x0041_`. `m2_formula_xstring` expects `_x005F_x0041_` for
`Probe!A1`, and CI's `validate` job measures it. If LibreOffice shows
anything else, the fixture's expectation is corrected; this decision is not.

**LibreOffice may not find the sheet a filter name points at.** It decodes
sheet names but not defined names, so it reads the filter name as the sheet
`_x005F_x0041_`. The filter itself comes from `<autoFilter ref>`. This only
affects a sheet whose name contains `_xHHHH_` text, and it is not measured.

**`m2_formula_xstring` changes.** Its file stores the escaped formula and
filter name, and its Excel checklist in `docs/excel-checks.md` now expects
`_x0041_` in `Probe!A1` and a saved copy without external links.

## What this does not decide

- **Formula text the caller already escaped.** A caller who writes
  `"_x005F_x0041_"` has it escaped again, so Excel shows `_x005F_x0041_`,
  as for cell text. A formula is the text Excel shows in its formula bar,
  never pre-escaped file content.
- **Defined names other than `_xlnm._FilterDatabase`.** Phase 1 writes no
  others. When a later milestone adds them, they use `escapeFormulaText`.
