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
| VM | `XlsxWriter` | 1461 | 6,958,908 | 365,199,360 (RSS) |
| VM | `XlsxStreamWriter` | 1454 | 6,958,908 | 352,321,536 (RSS) |
| Chrome | `XlsxWriter` | 3115 | 6,981,844 | 234,896,373 (heap) |
| Chrome | `XlsxStreamWriter` | 3151 | 6,981,844 | 197,466,174 (heap) |

Peak memory is the largest figure of the four runs of a case, warm-up
included for the VM (see above). Every run:

```text
vm | XlsxStreamWriter | warm-up | 1593 ms | 6958908 bytes | peak RSS 322781184 bytes
vm | XlsxStreamWriter | run 1 | 1474 ms | 6958908 bytes | peak RSS 325664768 bytes
vm | XlsxStreamWriter | run 2 | 1452 ms | 6958908 bytes | peak RSS 352321536 bytes
vm | XlsxStreamWriter | run 3 | 1454 ms | 6958908 bytes | peak RSS 352321536 bytes
vm | XlsxWriter | warm-up | 1470 ms | 6958908 bytes | peak RSS 358416384 bytes
vm | XlsxWriter | run 1 | 1470 ms | 6958908 bytes | peak RSS 358416384 bytes
vm | XlsxWriter | run 2 | 1450 ms | 6958908 bytes | peak RSS 364707840 bytes
vm | XlsxWriter | run 3 | 1461 ms | 6958908 bytes | peak RSS 365199360 bytes
chrome | XlsxStreamWriter | warm-up | 3589 ms | 6981844 bytes | peak JS heap 131397573 bytes
chrome | XlsxStreamWriter | run 1 | 3547 ms | 6981844 bytes | peak JS heap 197466174 bytes
chrome | XlsxStreamWriter | run 2 | 3151 ms | 6981844 bytes | peak JS heap 113423801 bytes
chrome | XlsxStreamWriter | run 3 | 3147 ms | 6981844 bytes | peak JS heap 97624753 bytes
chrome | XlsxWriter | warm-up | 3130 ms | 6981844 bytes | peak JS heap 113844504 bytes
chrome | XlsxWriter | run 1 | 3115 ms | 6981844 bytes | peak JS heap 163212349 bytes
chrome | XlsxWriter | run 2 | 3115 ms | 6981844 bytes | peak JS heap 200964511 bytes
chrome | XlsxWriter | run 3 | 3116 ms | 6981844 bytes | peak JS heap 234896373 bytes
```

## Reading the figures

- The streaming writer holds the open sheet in memory until the sheet is
  finished, and this workload is one sheet, so streaming saves little here.
  It saves memory across sheets: a finished sheet goes to the sink at once.
- The VM and Chrome files differ in size by 22,936 bytes. The compressed
  bytes depend on the platform's number formatting and on the deflate output;
  this was not investigated.
- The memory figures of the two platforms measure different things (process
  RSS against the used JS heap) and must not be compared with each other.
