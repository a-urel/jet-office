# Number format oracle

What Excel for Mac shows for each case of the number format engine
(`XlsxNumberFormatter`, decision 0008), saved by the owner as CSV in each
region. A test renders every case with the matching `XlsxFormatLocale` and
date system and requires the CSV's text; where they differ, Excel wins and
the rule changes, with a test. The cases settle the Unknowns and the owner
checklist of `docs/number-format.md`.

Files here:

- `cases.json`: the cases (format below). Edit it to add a case; never to
  make a committed CSV agree.
- `manifest.json`: one entry per region the owner ran (format below); `[]`
  until the first run.
- `<workbook>.<region>.csv`: Excel's CSV of a workbook in a region, such as
  `format_oracle.de-DE.csv`, committed exactly as Excel saved it.

Never edit a committed CSV or manifest entry without the owner. If
`cases.json` changes after a run, the affected regions are run again.

## The workbooks

```bash
dart run tool/write_format_oracle.dart build/format_oracle
```

writes, with this library's writer:

| File | Date system | What is in it | Regions |
|---|---|---|---|
| `format_oracle.xlsx` | 1900 | almost every case | all |
| `format_oracle_1904.xlsx` | 1904 | negative times (C10), serial 0, and the file's own codes for built-in ids 14 and 4 (C20) | all |
| `format_oracle_invalid.xlsx` | 1900 | codes Excel may refuse (more than four sections, three conditions, `h:mm:ss.0000`) | `en-US`; others optional |

Each has a sheet `cases`, row 1 a header and then one case per row:
column A the value in the case's format, B the code as text (`builtin 14`
for a built-in id without a code), C the case id, D what to look at.
`format_oracle.xlsx` has a second sheet, `eye`, with the eye-only cases
(below); its column A has the default width.

## Running a region

For each region you can produce (`en-US`, `de-DE`, `tr-TR`):

1. Quit Excel (Excel → Quit Excel, ⌘Q).
2. System Settings → General → Language & Region:
   - **Region**: United States, Germany or Türkiye.
   - **Applications** (the list at the bottom): `+`, Microsoft Excel, and
     the region's language: English, Deutsch or Türkçe. This makes Excel
     run as a user in that country does; without it macOS combines your
     first preferred language with the region (`en_DE`), and month names
     may stay English.
   - Leave the region's number, date and time formats at their defaults
     (no custom separators).
   - In Terminal, `defaults read -g AppleLocale` prints the system locale
     (such as `de_DE`); note it for the manifest.
3. Start Excel and open `build/format_oracle/format_oracle.xlsx`. It opens
   on the `cases` sheet. Do not change anything. If Excel reports a
   problem with the file, write down its message and stop: that is a
   writer defect.
4. File → Save As…, File Format **CSV UTF-8 (Comma delimited) (.csv)**,
   name `format_oracle.<region>.csv` (`format_oracle.de-DE.csv`), save to
   `build/format_oracle/`. Excel says only the active sheet is saved: OK.
   In `de-DE` and `tr-TR` Excel separates fields with `;`; keep it.
5. Do the eye checks (below) on the `eye` sheet, then close the workbook
   **without saving**.
6. Do the same for `format_oracle_1904.xlsx` (`format_oracle_1904.<region>.csv`)
   and, in `en-US` at least, `format_oracle_invalid.xlsx`
   (`format_oracle_invalid.<region>.csv`). If Excel offers to repair the
   invalid workbook, let it, save the CSV of what it shows and note the
   message in the manifest's `notes`.
7. Copy the CSVs here unopened (opening a CSV in Excel parses it again),
   add the manifest entry, run the quality gate, commit.

When all regions are done, set the region and Excel's language back.

## Eye-only checks

A case is `eyeOnly` when Excel's CSV does not show what the cell shows.
They are on the `eye` sheet of `format_oracle.xlsx`; type into the
manifest's `eye` exactly what column A shows, by case id:

- `u14-*`: `General` at the default column width. Do not widen column A:
  `General` shows fewer digits in a narrower column, and the CSV need not
  show what the narrow cell does.
- `c17-*`: the newer error names. Type the formula column D gives into
  column A (in Excel's language: German `=SEQUENZ(1;2)` and
  `=FILTER(1;FALSCH)`, Turkish `=SIRALI(1;2)` and `=FİLTRE(1;YANLIŞ)`; if
  Excel does not accept a name, use the Formula Builder). The first spills
  into column B, which is full, so it shows the spill error; the second
  filters nothing and shows the calc error. Record the error text, then
  close without saving.

## `manifest.json`

A list, one object per region run:

```json
[
  {
    "region": "de-DE",
    "appleLocale": "de_DE",
    "excelLanguage": "Deutsch",
    "excel": "Microsoft Excel for Mac 16.102 (25101918)",
    "macos": "26.1",
    "confirmedBy": "owner",
    "csv": {
      "format_oracle.xlsx": "format_oracle.de-DE.csv",
      "format_oracle_1904.xlsx": "format_oracle_1904.de-DE.csv"
    },
    "eye": {
      "u14-01": "1,23457E+11",
      "c17-01": "#ÜBERLAUF!"
    },
    "notes": ""
  }
]
```

- `region`: `en-US`, `de-DE` or `tr-TR`, the `XlsxFormatLocale` the CSVs
  are compared with.
- `appleLocale`: what `defaults read -g AppleLocale` printed.
- `excelLanguage`: Excel's language in that run.
- `excel`: Excel → About Excel, name, version and build.
- `macos`: Apple menu → About This Mac.
- `confirmedBy`: exactly `"owner"`.
- `csv`: workbook file to CSV file, for each workbook run in that region.
  The CSV is always named `<workbook stem>.<region>.csv`.
- `eye`: case id to the text column A shows, for every eye-only case of the
  workbooks run.
- `notes`: anything Excel said or did, or `""`.

## `cases.json`

```json
{
  "version": 1,
  "workbooks": {
    "main": {"file": "format_oracle.xlsx", "dateSystem": "1900", "numFmts": {}},
    "date1904": {"file": "format_oracle_1904.xlsx", "dateSystem": "1904",
                 "numFmts": {"4": "0.000", "14": "yyyy-mm-dd"}}
  },
  "cases": [
    {
      "id": "c4-01",
      "checks": ["C4a", "C4b"],
      "unknown": 4,
      "workbook": "main",
      "dateSystem": "1900",
      "value": {"n": "46037"},
      "code": "mmm",
      "eyeOnly": false,
      "note": "month 1 name; de/tr abbreviation with or without a dot"
    }
  ]
}
```

- `workbooks`: key to `file` (a `.xlsx` name), `dateSystem` (`"1900"` or
  `"1904"`) and `numFmts`, codes the file gives built-in ids (`"14":
  "yyyy-mm-dd"` writes `<numFmt numFmtId="14" formatCode="yyyy-mm-dd"/>`).
- `id`: unique; lower-case letters, digits and `-`. Column C of the row.
- `checks`: the owner checklist items of `docs/number-format.md` the case
  settles (`C4a`); empty for a case that only settles an Unknown or an own
  rule.
- `unknown`: the number in the Unknowns list of `docs/number-format.md`
  (1 to 21), or `null`.
- `workbook`: a key of `workbooks`. `dateSystem` repeats the workbook's,
  so a case says its date system by itself.
- `value`: exactly one of `{"n": "<digits>"}` (a number as decimal digits,
  `XlsxDecimal`'s form, a string), `{"b": true}`, `{"s": "text"}` or
  `{"manual": "=FORMULA()", "error": "#CODE!"}` (only for an eye-only
  case: nothing is written; `manual` is the formula in English, which the
  owner types in Excel's language, and `error` the English code of the
  error it results in, which the manifest's `eye` shows as Excel names
  it).
- `code` (a format code; `General` is built-in id 0) or `builtinId` (0 to
  163, no code): exactly one.
- `eyeOnly`: the case goes on the `eye` sheet and is checked by the
  manifest's `eye`, not by a CSV.
- `note`: what to look at; column D.

Rows follow the order of `cases`. A CSV's rows are matched to cases by
column C, never by position. `tool/src/format_oracle.dart`
(`parseOracleCases`) enforces this format; `test/tool/format_oracle_cases_test.dart`
requires a case for every checklist item, every skipped `Owner Excel check`
test and every Unknown.
