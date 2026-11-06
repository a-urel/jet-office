# Benchmark

`benchmark/format_benchmark_test.dart` times `NumberFormatter` (en-US, 1900
date system) on 100,000 values of each of three kinds. It moved from
jet_office's `benchmark/xlsx_format_benchmark_test.dart` (commit 632115d);
the run on every cell of a read workbook stayed there, since it needs the
reader.

The figures below are records, not thresholds: nothing fails when a later run
is slower, and they are not a promise.

## Run it

```bash
dart test benchmark
dart test -p chrome benchmark
```

The quality gate does not run it (`dart test` runs `test/` only; the test
carries the `benchmark` tag and a 10-minute timeout, set in `dart_test.yaml`).
`dart_test.yaml` also starts Chrome with `--enable-precise-memory-info`, for
benchmarks that read memory; this one does not.

## Method

- 100,000 values of each kind are made before the timing, then formatted with
  `format(value, numberFormat: code)`:
  - number: `FormatDecimal('$r.25')` with `#,##0.00`;
  - serial date: `FormatDecimal('${46000 + r % 3000}.${r % 86400}')` with
    `yyyy-mm-dd hh:mm:ss`, which takes the `BigInt` serial rounding of
    `lib/src/format/excel_date.dart`;
  - `DateTime(2026, 1, 1).add(Duration(seconds: r * 37))` with
    `yyyy-mm-dd hh:mm:ss`.

  One sample text per kind is asserted (`1,000.25`, `2025-12-10 02:24:00`,
  `2026-01-01 01:01:40`).
- Every case runs once as a warm-up (which also fills the formatter's code
  cache), then three timed runs (`Stopwatch`); the median is given. Each run
  sums the lengths of the texts it made, and the sum must equal the warm-up's,
  so the work is used. The ratio is a kind's median over the number run's.

## Figures

- Date: 2026-11-06.
- Machine: Mac15,7, Apple M3 Pro, 36 GiB RAM.
- Dart SDK 3.13.7 (stable); the VM runs the JIT, Chrome runs dart2js output.

| Case (median of 3, 100,000 values) | VM (ms) | VM (ns each) | Chrome (ms) | Chrome (ns each) |
|---|---|---|---|---|
| Number, `FormatDecimal`, `#,##0.00` | 90.1 | 901 | 171.6 | 1716 |
| Serial date, `FormatDecimal`, `yyyy-mm-dd hh:mm:ss` | 203.9 | 2039 | 283.0 | 2830 |
| `DateTime`, `yyyy-mm-dd hh:mm:ss` | 341.9 | 3419 | 656.0 | 6560 |

| Ratio to the number run | VM | Chrome |
|---|---|---|
| Serial date | 2.26 | 1.65 |
| `DateTime` | 3.80 | 3.82 |

Every line:

```text
vm | number | FormatDecimal #,##0.00 | median 90.1 ms | 901 ns/value | ratio 1.00
vm | serial date | FormatDecimal yyyy-mm-dd hh:mm:ss | median 203.9 ms | 2039 ns/value | ratio 2.26
vm | DateTime | yyyy-mm-dd hh:mm:ss | median 341.9 ms | 3419 ns/value | ratio 3.80
chrome | number | FormatDecimal #,##0.00 | median 171.6 ms | 1716 ns/value | ratio 1.00
chrome | serial date | FormatDecimal yyyy-mm-dd hh:mm:ss | median 283.0 ms | 2830 ns/value | ratio 1.65
chrome | DateTime | yyyy-mm-dd hh:mm:ss | median 656.0 ms | 6560 ns/value | ratio 3.82
```

## Reading the figures

- **The `BigInt` serial rounding is cheap.** A serial date given as a
  `FormatDecimal` costs 2.26 times a number on the VM and 1.65 times in Chrome,
  well under 5 times, the point at which this page would report it. Nothing
  is recommended.
- **A `DateTime` costs more than a serial.** The same code on a `DateTime`
  costs 3.8 times a number on both, about 1.7 and 2.3 times the serial date.
  The benchmark does not say why.
