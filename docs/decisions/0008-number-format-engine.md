# 0008 — A number format engine that shows values as Excel for Mac does

**Status:** Accepted — 2026-10-29

## Context

[`0007`](0007-phase-2-reader-scope-and-untrusted-input.md) planned, after
phase 2, a pure function that renders a cell value with its number format
code the way Excel shows it (`00123`, `1.234,50 ₺`, `28.10.2026`), and left
its scope to be settled when it started. Phase 2 is done: the reader hands
out each cell's raw value, its number format id and code, and whether the
code shows a date.

The owner's viewer application needs every cell as Excel shows it; import
benefits too (leading zeros of codes). The owner's measure of success is
maximum Excel compatibility, and they asked for the details to be settled
from Excel's documentation. Quds has no such engine.

Two classifiers already answer "does this code show a date": phase 1's
`isDateFormat` scans the whole code, phase 2's `classifyFormatCode` looks at
each section. They disagree on codes such as `yyyy-mm-dd;h:mm` and `[h]`, and
the R2 ledger deferred unifying them to this work.

The full design is in
`docs/superpowers/specs/2026-10-29-number-format-engine-design.md`. That
folder is git-ignored, so this record keeps what has to outlive it.

## Decision

**`jet_office` gets a number format engine: `XlsxNumberFormatter` renders a
value with its number format id and code into the text Excel for Mac shows,
in a locale given as data. It is new code under `lib/src/xlsx/format/`, and
its parser is the only place in `lib/` that tokenizes a format code.**

- **Scope: the whole format code grammar** Excel uses in `en-US`, `de-DE`
  and `tr-TR`: up to four sections, conditions, colors, `General`, digit
  placeholders, grouping and scaling, percent, scientific, fractions, text,
  literals, `_` and `*`, locale tags (`[$€-407]`, `[$-F800]`), every date
  and time token, elapsed time, both date systems. Milestones N1 (parser and
  numbers), N2 (dates and locales) and N3 (Excel as the oracle, release
  readiness), named N so they do not clash with M1–M5 and R1–R4.
- **The reference is Excel for Mac (Microsoft 365).** Where Excel takes text
  from the operating system (names, AM/PM, separators, the locale's version
  of a built-in id), the shipped locales follow Excel for Mac under macOS's
  region settings. Where Excel's behaviour is undocumented, the owner's
  Excel decides, and the rule follows it.
- **Locale is data.** `XlsxFormatLocale` holds separators, month and day
  names, AM/PM, `TRUE`/`FALSE` and error names, and the locale's codes for
  the locale-dependent built-in ids. `en-US`, `de-DE` and `tr-TR` ship;
  another locale, or a Windows variant of one, is one more value built by
  the caller. No `intl` or other runtime dependency. It is separate from
  `XlsxLocale`, which names the language of warning messages.
- **Built-in ids follow the renderer's locale, not the file.** For ids 5–8,
  14–22 and 37–44, a code equal to the invariant built-in code means the
  built-in, and the locale's version is shown (14 is `m/d/yyyy` in `en-US`,
  `dd.mm.yyyy` in `de-DE`); a code the file wrote itself is used as is.
- **Numbers are shown as Excel holds them.** The value is turned into a
  double and back into 15 significant digits, as Excel does on load; scaling
  and rounding to the format's places are then done in decimal, half away
  from zero, so `2.675` with `0.00` shows `2.68`. The reader's values stay
  exact; only the display follows Excel.
- **Fitting into a column is the viewer's job.** The engine returns the text,
  the section's color, the positions of `_` padding and the `*` fill, and an
  `overflow` flag for the cases Excel shows as `#` at any width (an
  out-of-range date, no matching condition). The exception is `General`,
  whose digits depend on the width: the engine takes the number of
  characters available, 11 by default.
- **Format codes are untrusted input.** The engine never throws on a code.
  A code it cannot read renders as `General`; one it cannot match exactly
  (another calendar, an unknown locale tag, a locale-dependent id without a
  code) is reported with a warning code, which has messages in `en`, `de`
  and `tr` like every other. Code length and output size are bounded, and a
  fuzz test runs in the gate.
- **One classifier.** `classifyFormatCode` and `isDateFormat` are computed
  from the engine's parser. The reader's results do not change. The writer's
  date warning follows the reader's per-section rule; that changes which
  codes warn, never a written byte.
- **Verification uses Excel itself.** A tool writes an oracle workbook, one
  case per row; the owner opens it in Excel for Mac in each locale they can
  set up and saves it as CSV, and a test requires the engine to produce the
  same text. LibreOffice's export is a second opinion in CI, reviewed but not
  failed on.

## Consequences

**Release does not wait for every locale.** A locale the owner could not
check in Excel ships marked unverified (`XlsxFormatLocale.verified` false and
a note in `docs/number-format.md`), and is corrected when its CSV arrives.

**Some cells will differ from Windows Excel.** Month abbreviations, AM/PM
and system date formats come from the operating system, and macOS and Windows
differ. A caller who needs Windows' text builds a Windows locale value.

**`[ColorN]` needs a palette the reader does not give.** The engine returns
the palette index; a viewer resolves it with the default palette, which is
right unless the file customises `<indexedColors>`. Exposing the palette
belongs to the model phase.

**The three new warning codes need a native-speaker check** of their German
and Turkish messages before release, as phase 1's and phase 2's did.

**The writer's date warning changes on a few codes.** Writing a date into
`yyyy-mm-dd;h:mm` now warns; writing one into `[h]` alone no longer does.
Each case is pinned by a test before the change.

## What this does not decide

- **The public API's exact names and signatures.** Settled milestone by
  milestone and fixed at N3.
- **Parsing text into numbers** (what Excel does when a user types
  `1.234,5`). The editor will need it; it is separate work.
- **Calendars other than Gregorian and CJK numerals.** Recognised and
  reported, not rendered.
- **Publishing.** Still the owner's decision.
