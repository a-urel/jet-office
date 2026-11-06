# Changelog

## 0.1.0-dev.1

- The number format engine, extracted from `jet_office`: `NumberFormatter`,
  `FormatLocale` (`enUS`, `deDE`, `trTR`), `FormattedValue` with its parts,
  `FormatDecimal`, `FormatErrorValue`, `FormatColor`, `FormatWarning`,
  `FormatKind` and `classifyFormatCode`, and `builtinNumberFormatCode`.
- The Excel for Mac oracle: the owner's CSVs per region, the oracle test and the
  tools that write the oracle workbooks and compare with LibreOffice.
- Seeded fuzzing of the formatter (seeds 1 to 4 in the gate,
  `tool/fuzz_formatter.dart` for longer runs) and a benchmark.
- `docs/number-format.md`, `docs/benchmark.md` and decision 0001.
- Set up the package: no dependencies, architecture guards, quality gate.
