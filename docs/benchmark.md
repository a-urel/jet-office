# Benchmark

The benchmark writes one sheet of 100,000 data rows and a header row, 12 mixed
columns (text, integers, doubles, `XlsxDecimal`, `DateTime`, `XlsxDate`,
booleans, formulas, empty cells and a styled cell), with column widths and
money and date formats. The workload is `benchmark/src/workload.dart`.

The figures below are records, not thresholds (spec section 5): nothing fails
when a later run is slower, and they are not a promise.

## Run it

```bash
dart test benchmark
dart test -p chrome benchmark
```

The quality gate does not run it. `dart_test.yaml` starts Chrome with
`--enable-precise-memory-info`, which makes `performance.memory` exact.

## Method

- Two cases: `XlsxWriter` (the file stays in memory) and `XlsxStreamWriter`
  (to a sink that counts bytes and keeps none).
- Each case runs one warm-up run, then three timed runs (`Stopwatch`, from the
  first sheet call to the end of `close()`). The median of the three is given.
- Memory is the maximum of samples taken every 10,000 rows and at `close()`.
  - VM: `ProcessInfo.maxRss`, the peak resident set of the whole process. It
    never falls, so it also holds everything the earlier runs used. The
    streaming case runs first so its figure is not lifted by the in-memory
    case.
  - Chrome: `performance.memory.usedJSHeapSize`, the used JavaScript heap at
    each sample. It falls when the collector runs, so it is a sampled peak.
- The in-memory file of the last run is checked with `checkXlsx` (no
  violations), so the measured file is a valid one.

## First figures

- Date: 2026-10-27.
- Machine: Mac15,7, Apple M3 Pro, 36 GiB RAM (38,654,705,664 bytes).
- OS: macOS 27.0.1 (26A434).
- Dart SDK 3.13.5 (stable); the VM runs the JIT, Chrome runs dart2js output
  (`dart test -p chrome` compiles with dart2js).
- Chrome 156.0.8078.48.

| Platform | Writer | Median (ms) | File (bytes) | Peak memory (bytes) |
|---|---|---|---|---|
| VM | `XlsxWriter` | 1449 | 6,958,087 | 363,462,656 (RSS) |
| VM | `XlsxStreamWriter` | 1445 | 6,958,087 | 350,224,384 (RSS) |
| Chrome | `XlsxWriter` | 3092 | 6,981,844 | 236,559,675 (heap) |
| Chrome | `XlsxStreamWriter` | 3119 | 6,981,844 | 199,444,733 (heap) |

Peak memory is the largest figure of the four runs of a case, warm-up
included for the VM (see above). The figures were taken again on 2026-10-27
after Task 5b (doubles spelled the same on both platforms); the VM file shrank
from 6,958,908 to 6,958,087 bytes because whole doubles lost their `.0`, and
the Chrome file is unchanged. Every run:

```text
vm | XlsxStreamWriter | warm-up | 1547 ms | 6958087 bytes | peak RSS 320061440 bytes
vm | XlsxStreamWriter | run 1 | 1451 ms | 6958087 bytes | peak RSS 324354048 bytes
vm | XlsxStreamWriter | run 2 | 1445 ms | 6958087 bytes | peak RSS 324354048 bytes
vm | XlsxStreamWriter | run 3 | 1442 ms | 6958087 bytes | peak RSS 350224384 bytes
vm | XlsxWriter | warm-up | 1446 ms | 6958087 bytes | peak RSS 350224384 bytes
vm | XlsxWriter | run 1 | 1448 ms | 6958087 bytes | peak RSS 356270080 bytes
vm | XlsxWriter | run 2 | 1469 ms | 6958087 bytes | peak RSS 363298816 bytes
vm | XlsxWriter | run 3 | 1449 ms | 6958087 bytes | peak RSS 363462656 bytes
chrome | XlsxStreamWriter | warm-up | 3526 ms | 6981844 bytes | peak JS heap 131429007 bytes
chrome | XlsxStreamWriter | run 1 | 3524 ms | 6981844 bytes | peak JS heap 199444733 bytes
chrome | XlsxStreamWriter | run 2 | 3119 ms | 6981844 bytes | peak JS heap 113830386 bytes
chrome | XlsxStreamWriter | run 3 | 3095 ms | 6981844 bytes | peak JS heap 113465453 bytes
chrome | XlsxWriter | warm-up | 3099 ms | 6981844 bytes | peak JS heap 187600763 bytes
chrome | XlsxWriter | run 1 | 3093 ms | 6981844 bytes | peak JS heap 219208270 bytes
chrome | XlsxWriter | run 2 | 3092 ms | 6981844 bytes | peak JS heap 236559675 bytes
chrome | XlsxWriter | run 3 | 3083 ms | 6981844 bytes | peak JS heap 236140222 bytes
```

## Reading the figures

- The streaming writer holds the open sheet in memory until the sheet is
  finished, and this workload is one sheet, so streaming saves little here.
  It saves memory across sheets: a finished sheet goes to the sink at once.
- The VM and Chrome files still differ in size, by 23,757 bytes, but the
  XML inside them does not. The first run of this benchmark also exposed a
  real difference: the VM wrote an integer-valued `double` as `<v>5.0</v>` and
  the web as `<v>5</v>`, because `5.0 is int` is true in dart2js. Task 5b
  fixed it (one spelling, `formatXmlDouble`, ruling R9; test
  `test/xlsx/cell_encoder_double_test.dart` on both platforms). Unzipping the
  VM and Chrome files of a 3,000-row run of this workload after the fix gives
  byte-identical parts. What remains is the deflate stream: `package:archive`
  compresses with the native zlib on the VM and with its own pure-Dart
  deflate in the browser, and the two give different (equally valid) bytes
  for the same input. Equal uncompressed parts, unequal ZIP bytes.
- The memory figures of the two platforms measure different things (process
  RSS against the used JS heap) and must not be compared with each other.
