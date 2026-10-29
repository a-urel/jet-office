# Benchmark

The benchmark writes one sheet of 100,000 data rows and a header row, 12 mixed
columns (text, integers, doubles, `XlsxDecimal`, `DateTime`, `XlsxDate`,
booleans, formulas, empty cells and a styled cell), with column widths and
money and date formats. The workload is `benchmark/src/workload.dart`.
Two benchmarks use it: `benchmark/xlsx_benchmark_test.dart` times the two
writers, and `benchmark/xlsx_read_benchmark_test.dart` times `XlsxReader`
reading the file the workload makes ("Read figures" below). A third,
`benchmark/xlsx_read_worst_case_test.dart`, reads the largest sheet the
reader's default limits let through ("Worst case" below). A fourth,
`benchmark/xlsx_format_benchmark_test.dart`, times `XlsxNumberFormatter` on
every cell of the read workload ("Format figures" below).

The figures below are records, not thresholds (spec section 5): nothing fails
when a later run is slower, and they are not a promise.

## Run it

```bash
dart test benchmark
dart test -p chrome benchmark
```

One of them alone:

```bash
dart test benchmark/xlsx_benchmark_test.dart
dart test -p chrome benchmark/xlsx_benchmark_test.dart
dart test benchmark/xlsx_read_benchmark_test.dart
dart test -p chrome benchmark/xlsx_read_benchmark_test.dart
dart test benchmark/xlsx_read_worst_case_test.dart
dart test -p chrome benchmark/xlsx_read_worst_case_test.dart
dart test benchmark/xlsx_format_benchmark_test.dart
dart test -p chrome benchmark/xlsx_format_benchmark_test.dart
```

The quality gate does not run it. `dart_test.yaml` starts Chrome with
`--enable-precise-memory-info`, which makes `performance.memory` exact.

## Method

The write benchmark:

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
after the change that spells doubles the same on both platforms; the VM file
shrank from 6,958,908 to 6,958,087 bytes because whole doubles lost their
`.0`, and the Chrome file is unchanged. Every run:

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
  the web as `<v>5</v>`, because `5.0 is int` is true in dart2js. The
  writer now has one spelling (`formatXmlDouble`; test
  `test/xlsx/cell_encoder_double_test.dart` on both platforms). Unzipping the
  VM and Chrome files of a 3,000-row run of this workload after the fix gives
  byte-identical parts. What remains is the deflate stream: `package:archive`
  compresses with the native zlib on the VM and with its own pure-Dart
  deflate in the browser, and the two give different (equally valid) bytes
  for the same input. Equal uncompressed parts, unequal ZIP bytes: decision
  [`0006`](decisions/0006-zip-bytes-may-differ-by-platform.md) accepts
  this, and `test/xlsx/cross_platform_parts_test.dart` proves the
  parts equal.
- The memory figures of the two platforms measure different things (process
  RSS against the used JS heap) and must not be compared with each other.
- The memory figures are lower bounds: the Chrome heap peak inside
  `close()` is not sampled, so a higher peak may have happened between two
  samples.

## Read figures

The read benchmark (`benchmark/xlsx_read_benchmark_test.dart`) reads the
file the workload above makes: one sheet, 100,000 data rows and a header,
1,166,679 cells (12 per row, but for the `Note` column, which is empty in
every third row and so not written).

### Method

- The file is written with `XlsxWriter` once, before anything is timed, and
  each platform reads its own bytes (decision
  [`0006`](decisions/0006-zip-bytes-may-differ-by-platform.md)): the ZIP
  bytes differ by platform, the parts do not. On the VM a child `dart`
  process writes it (`benchmark/src/workload_file.dart`), so the reader's
  process has never run the writer; a last test writes the workload in the
  process and asserts the bytes equal the child's. In Chrome the file is
  written in the page. Before the memory runs the benchmark reads only the
  ZIP directory (with `package:archive`, for the deflated entry and its
  size N); nothing inflates the sheet in the process until the warm-up.
- `XlsxReader reads 100000 rows`: one warm-up run, then three timed runs. A
  run opens a fresh `XlsxReader` and takes every row of the sheet and every
  cell's `value`; it is timed from the constructor to the last row. Each run
  asserts the cell count (1,166,679, computed from the workload's shape),
  the row count and the number of non-null values (the formulas have no
  cached value and read as `null`). The median of the three is given.
- Memory is sampled after the first row (the sheet part has just been
  inflated and decoded), every 10,000 rows and after the last; a baseline is
  taken just before `XlsxReader(bytes)`. The figure is the largest sampled
  peak above its baseline over the four runs. Samples are lower bounds: a
  peak between two samples is missed.
  - VM: `ProcessInfo.currentRss`. The VM also prints `ProcessInfo.maxRss`
    after each run. The benchmark reports whether `maxRss` rose during the
    warm-up; if it did, `maxRss` after it is the warm-up's own peak RSS, not
    sampled, and "`maxRss` above the warm-up's baseline" bounds the read's
    peak from above (it counts anything else the process allocated then).
  - Chrome: `performance.memory.usedJSHeapSize`, as for the writers.
- `phases`, the median of three each, after the memory runs: opening the
  reader; `ZipReader.read` of the sheet part alone, the package's pure-Dart
  `Inflate.stream`; `dart:io`'s `ZLibCodec(raw: true)` on the same deflated
  entry (VM only; its output is checked equal to `ZipReader.read`'s; the
  browser's `DecompressionStream` is asynchronous and cannot serve a
  synchronous reader, so Chrome records `n/a`); a first full rows pass on a
  fresh reader; a second rows pass on the same reader, with the shared
  strings already read; and `mergesAt(0)` on a reader whose rows were read,
  which is the second inflate and parse merges need. The phase figures
  import the private `ZipReader` (`lib/src/zip/archive_adapter.dart`), so
  the benchmark breaks on an internal rename.
- The `memory/N` line is the largest sampled peak above baseline divided by
  N, the sheet XML's uncompressed bytes: the figure spec §4.4 budgets at
  about 2 to 3. The VM adds a `memory/N (peak RSS)` line from `maxRss`.

### Figures

- Date: 2026-10-29.
- Machine: Mac15,7, Apple M3 Pro, 36 GiB RAM (38,654,705,664 bytes).
- OS: macOS 27.2 (26B123).
- Dart SDK 3.13.7 (stable); the VM runs the JIT, Chrome runs dart2js output.
- Chrome 156.0.8078.48.

| Platform | Median (ms) | File (bytes) | Sheet XML N (bytes) | Sampled peak above baseline (bytes) | memory/N |
|---|---|---|---|---|---|
| VM | 2677 | 6,958,087 | 43,580,479 | 63,913,984 (RSS, warm-up) | 1.47 |
| Chrome | 3349 | 6,981,844 | 43,580,479 | 107,275,426 (heap, warm-up) | 2.46 |

Both memory figures come from the warm-up, the largest of the four runs.
On the VM, `maxRss` rose during the warm-up to 105,234,432 bytes above the
warm-up's baseline: 2.41 N.

| Phase (median of 3) | VM (ms) | Chrome (ms) |
|---|---|---|
| Open (`XlsxReader(bytes)`) | 0.4 | 0.4 |
| `ZipReader.read` of the sheet part (pure-Dart inflate) | 241.3 | 685.7 |
| Platform inflate of the same entry | 38.7 | n/a |
| First rows pass | 2683.8 | 3338.1 |
| Second rows pass (shared strings cached) | 2633.1 | 3291.0 |
| `mergesAt(0)` after the rows | 656.9 | 1618.4 |

The writers, run the same day on the same machine for comparison (the
"First figures" above are from 2026-10-27):

| Platform | Writer | Median (ms) | File (bytes) | Peak memory (bytes) |
|---|---|---|---|---|
| VM | `XlsxWriter` | 1466 | 6,958,087 | 363,020,288 (RSS) |
| VM | `XlsxStreamWriter` | 1465 | 6,958,087 | 352,288,768 (RSS) |
| Chrome | `XlsxWriter` | 3143 | 6,981,844 | 239,230,157 (heap) |
| Chrome | `XlsxStreamWriter` | 3150 | 6,981,844 | 200,257,501 (heap) |

Every read line:

```text
vm | input | 6958087 bytes | xl/worksheets/sheet1.xml 6688565 bytes deflated, 43580479 bytes XML
vm | XlsxReader | warm-up | 2800 ms | 6958087 bytes | RSS peak 257753088 bytes | baseline 193839104 bytes | above 63913984 bytes | cells 1166679 | warnings 1 (formulaWithoutValue) | peak RSS 299073536 bytes
vm | XlsxReader | run 1 | 2703 ms | 6958087 bytes | RSS peak 303955968 bytes | baseline 257720320 bytes | above 46235648 bytes | cells 1166679 | warnings 1 (formulaWithoutValue) | peak RSS 303955968 bytes
vm | XlsxReader | run 2 | 2677 ms | 6958087 bytes | RSS peak 303955968 bytes | baseline 260374528 bytes | above 43581440 bytes | cells 1166679 | warnings 1 (formulaWithoutValue) | peak RSS 303955968 bytes
vm | XlsxReader | run 3 | 2676 ms | 6958087 bytes | RSS peak 304480256 bytes | baseline 260358144 bytes | above 44122112 bytes | cells 1166679 | warnings 1 (formulaWithoutValue) | peak RSS 304480256 bytes
vm | XlsxReader | median 2677 ms
vm | phase | open | 0.4 ms
vm | phase | ZipReader.read (pure-Dart inflate) | 241.3 ms | N 43580479 bytes
vm | phase | platform inflate | 38.7 ms
vm | phase | first rows pass | 2683.8 ms
vm | phase | second rows pass (shared strings cached) | 2633.1 ms
vm | phase | mergesAt(0) after rows | 656.9 ms
vm | memory/N | 1.47 | largest sampled peak above baseline 63913984 bytes | N 43580479 bytes
vm | memory/N (peak RSS) | 2.41 | peak RSS after the warm-up above its baseline 105234432 bytes | reached in the warm-up: yes (before: 193822720 bytes)
vm | input | equals an in-process XlsxWriter write
chrome | input | 6981844 bytes | xl/worksheets/sheet1.xml 6712845 bytes deflated, 43580479 bytes XML
chrome | XlsxReader | warm-up | 3380 ms | 6981844 bytes | peak JS heap peak 258163162 bytes | baseline 150887736 bytes | above 107275426 bytes | cells 1166679 | warnings 1 (formulaWithoutValue)
chrome | XlsxReader | run 1 | 3345 ms | 6981844 bytes | peak JS heap peak 145826335 bytes | baseline 252820599 bytes | above -106994264 bytes | cells 1166679 | warnings 1 (formulaWithoutValue)
chrome | XlsxReader | run 2 | 3356 ms | 6981844 bytes | peak JS heap peak 146353927 bytes | baseline 145832595 bytes | above 521332 bytes | cells 1166679 | warnings 1 (formulaWithoutValue)
chrome | XlsxReader | run 3 | 3349 ms | 6981844 bytes | peak JS heap peak 169740246 bytes | baseline 146362203 bytes | above 23378043 bytes | cells 1166679 | warnings 1 (formulaWithoutValue)
chrome | XlsxReader | median 3349 ms
chrome | phase | open | 0.4 ms
chrome | phase | ZipReader.read (pure-Dart inflate) | 685.7 ms | N 43580479 bytes
chrome | phase | platform inflate | n/a
chrome | phase | first rows pass | 3338.1 ms
chrome | phase | second rows pass (shared strings cached) | 3291.0 ms
chrome | phase | mergesAt(0) after rows | 1618.4 ms
chrome | memory/N | 2.46 | largest sampled peak above baseline 107275426 bytes | N 43580479 bytes
```

Every write line of the same day:

```text
vm | XlsxStreamWriter | warm-up | 1562 ms | 6958087 bytes | peak RSS 322191360 bytes
vm | XlsxStreamWriter | run 1 | 1484 ms | 6958087 bytes | peak RSS 352288768 bytes
vm | XlsxStreamWriter | run 2 | 1465 ms | 6958087 bytes | peak RSS 352288768 bytes
vm | XlsxStreamWriter | run 3 | 1456 ms | 6958087 bytes | peak RSS 352288768 bytes
vm | XlsxStreamWriter | median 1465 ms
vm | XlsxWriter | warm-up | 1460 ms | 6958087 bytes | peak RSS 353189888 bytes
vm | XlsxWriter | run 1 | 1483 ms | 6958087 bytes | peak RSS 353189888 bytes
vm | XlsxWriter | run 2 | 1457 ms | 6958087 bytes | peak RSS 363020288 bytes
vm | XlsxWriter | run 3 | 1466 ms | 6958087 bytes | peak RSS 363020288 bytes
vm | XlsxWriter | median 1466 ms
chrome | XlsxStreamWriter | warm-up | 3571 ms | 6981844 bytes | peak JS heap 131521343 bytes
chrome | XlsxStreamWriter | run 1 | 3527 ms | 6981844 bytes | peak JS heap 200257501 bytes
chrome | XlsxStreamWriter | run 2 | 3150 ms | 6981844 bytes | peak JS heap 113316013 bytes
chrome | XlsxStreamWriter | run 3 | 3150 ms | 6981844 bytes | peak JS heap 181415930 bytes
chrome | XlsxStreamWriter | median 3150 ms
chrome | XlsxWriter | warm-up | 3131 ms | 6981844 bytes | peak JS heap 194212511 bytes
chrome | XlsxWriter | run 1 | 3139 ms | 6981844 bytes | peak JS heap 222396771 bytes
chrome | XlsxWriter | run 2 | 3143 ms | 6981844 bytes | peak JS heap 239230157 bytes
chrome | XlsxWriter | run 3 | 3146 ms | 6981844 bytes | peak JS heap 235826566 bytes
chrome | XlsxWriter | median 3143 ms
```

### Reading the figures

- **Reading is slower than writing on the VM, and about as fast in
  Chrome.** The read median is 2677 ms against the writers' 1466 ms on the
  VM (1.8 times), and 3349 ms against 3143 ms in Chrome (1.07 times). The
  spec's "reading should not be slower than writing the same file" (§4.4)
  does not hold on the VM. The benchmark records this and fails on nothing.
- **Inflate is a small share; the pure-Dart inflate costs about 200 ms on
  the VM.** `ZipReader.read` takes 241 ms against `dart:io`'s 39 ms on the
  same entry, 6.2 times slower, but that is 9 % of a 2677 ms read. The R1
  ruling (bounded pure-Dart `Inflate.stream` on every platform, for bomb
  safety) therefore costs about 0.2 s per 43 MB of sheet XML on the VM. In
  Chrome the inflate is 686 ms, 20 % of a read, with no platform figure to
  compare (`DecompressionStream` is asynchronous). `package:archive` itself
  already uses the native zlib on the VM, in `ZipFile.decompress` (through
  `ZLibDecoder`); the reader does not use that path, because it inflates
  the whole entry before any bound applies.
- **Parsing is the cost.** The first rows pass less the inflate is 2443 ms
  on the VM (91 % of the pass) and 2652 ms in Chrome (79 %): UTF-8
  decoding, the pull parser and the cell decoder together; the benchmark
  does not split them. The shared strings cost little here: the second
  pass, with them cached, is only 51 ms (VM) and 47 ms (Chrome) faster. So
  the parse share decides the deferred `_NsScope` allocation (R1 Task 2,
  plan ruling 10): parsing dominates, and a lazy namespace scope per start
  element is the first candidate for a later speed-up. Nothing changes in
  R4.
- **Merges cost a second inflate and parse.** `mergesAt(0)` after the rows
  takes 657 ms on the VM (24 % of a rows pass) and 1618 ms in Chrome
  (48.5 %), for a sheet with no merges: the second inflation and scan of
  the part that plan ruling 2 of R2 accepted. A consumer that needs merges
  pays this once per sheet.
- **Memory is within the budget.** The VM's unsampled peak, `maxRss` above
  the warm-up's baseline, is at most 2.41 N, inside the spec's "about two
  to three times": while the part is decoded the reader holds its inflated
  bytes (N) and the decoded string at once, and the VM keeps an ASCII
  string at one byte per character (about N, not the 2N of UTF-16). The
  sampled figure, 1.47 N, misses that moment. Chrome's sampled peak is
  2.46 N in the warm-up; the later runs read lower, because the collector
  ran at other points (one run's peak was below its baseline). Both sampled
  figures are lower bounds.
- **Why the VM's input comes from a child process.** A first version wrote
  the file in the benchmark's own process, as plan ruling 1 said. Its
  `currentRss` baseline was then about 280 MB, the writer's freed heap that
  the VM keeps mapped; the reader reused that heap, its RSS barely rose, and
  `memory/N` came out as 0.05 (one run's peak was below its baseline). A
  second version still inflated the sheet once in the process before the
  warm-up, to learn N, and the warm-up reused that freed heap in turn
  (`maxRss` showed 1.11 N). The child process writes the same bytes (the
  last test asserts it), and N now comes from the ZIP directory.

## Worst case

`benchmark/xlsx_read_worst_case_test.dart` reads the largest single sheet
the default `XlsxReadLimits` accept: one part of about 250 MiB of XML, under
`maxEntryBytes` (256 MiB), whose deflated entry stays under
`maxCompressionRatio` (1,000). It is a bound for one sheet, not for a
workbook ("What it means for an upload" below). It runs in its own file, so
that a browser tab running out of memory cannot hide the other read figures
(plan ruling 5 of R4); a crash would be a recorded figure, not a failure.

### Method

- The sheet (`benchmark/src/worst_case.dart`) is 1,372,481 rows of twelve
  `<c><v>1</v></c>` cells without `r`, as many as fit in 250 MiB with the
  worksheet's own elements: N = 262,143,983 bytes. The package around it is
  the minimal one the reader tests build
  (`test/xlsx/read/support/workbook_builder.dart`), deflated by
  `package:archive` at its default level (1, best speed).
- The plan said to vary every k-th row if the ratio reached 1,000. It does
  not: the ratio is 127.8 (VM, `dart:io` zlib) and 133.5 (Chrome, the
  pure-Dart deflate), so no row is varied and k is `n/a`. Even at level 9 a
  32 MiB sample of the same rows deflates only 257.7 to 1 (both deflates).
  That figure comes from a one-off calibration script, not committed: the
  sample (33,554,498 bytes) zipped with `package:archive`'s
  `ZipEncoder(level: 9)`, on the VM and in the pure-Dart deflate.
  Deflate's best case is about 1,032 to 1, a 258-byte match per two bits;
  these rows repeat every 191 bytes, a distance whose code carries six extra
  bits, which caps the ratio near 258. So for row-shaped XML
  `maxEntryBytes`, not the ratio, bounds the read.
- On the VM a child `dart` process builds the package
  (`benchmark/src/write_worst_case.dart`, through `worstCaseFile()` in
  `benchmark/src/workload_file.dart`), so the reader's process never held
  the XML. In Chrome the package is built in the page and the sheet's XML is
  dropped before the baseline; it is garbage the collector had not yet
  freed, so **Chrome's baseline includes that garbage** (about 1.3 GB), and
  its "above baseline" figure is only an estimate: a collection during the
  read could hide part of the reader's own heap.
- One run: a baseline, `XlsxReader(bytes)` with the default limits, every
  row and every cell's `value`; memory is sampled after the first row (the
  part has just been inflated and decoded), every 100,000 rows and after
  the last. The VM also reads `maxRss` before and after. The run asserts
  1,048,576 rows, 12 cells each, every one `XlsxDecimal('1')`, and the one
  warning below with its count.
- Rows past 1,048,576 follow the existing rule: the row is not yielded and
  each of its cells adds to one aggregated `cellOutsideSheet` warning.

### Figures

Same machine, SDK and Chrome as "Read figures", 2026-10-29. Two runs per
platform. The table gives the second VM run, from the committed code: the
first failed its value assertion before a fix in the test (its figures did
not depend on the fix and are within 0.4 % of the second's). For Chrome it
gives the first run.

| Platform | File (bytes) | Ratio | Read (ms) | Peak above baseline (bytes) | Per N | Absolute peak (bytes) |
|---|---|---|---|---|---|---|
| VM | 2,052,039 | 127.8 | 18,460 | 531,300,352 (RSS) | 2.03 | 713,736,192 (RSS) |
| Chrome | 1,965,092 | 133.5 | 19,269 | 994,413,675 (heap) | 3.79 | 2,328,197,079 (heap) |

Both platforms passed: 1,048,576 rows, 12,582,912 cells, one warning,
`cellOutsideSheet` with a count of 3,886,860 (the 323,905 rows past the
last, twelve cells each). On the VM the unsampled `maxRss` rose during the
read to 532,873,216 bytes above the baseline, also 2.03 N; the sampled peak
is about 1.6 MB below it and was already reached after the first row: the
inflated bytes and the decoded string held at once.

Every line:

```text
vm | input | built in 2130 ms | 2052039 bytes | xl/worksheets/sheet1.xml 2050864 bytes deflated, 262143983 bytes XML | ratio 127.8 | k n/a (no row varied) | rows 1372481
vm | XlsxReader | 18476 ms | 2052039 bytes | RSS peak 716029952 bytes | baseline 183484416 bytes | above 532545536 bytes (2.03 N) | after the first row above 532545536 bytes (2.03 N) | rows 1048576 | cells 12582912 | warnings 1 (cellOutsideSheet ×3886860)
vm | peak RSS | before 183484416 bytes | after 716029952 bytes | above the baseline 532545536 bytes (2.03 N) | rose during the read: yes
vm | input | built in 2199 ms | 2052039 bytes | xl/worksheets/sheet1.xml 2050864 bytes deflated, 262143983 bytes XML | ratio 127.8 | k n/a (no row varied) | rows 1372481
vm | XlsxReader | 18460 ms | 2052039 bytes | RSS peak 713736192 bytes | baseline 182435840 bytes | above 531300352 bytes (2.03 N) | after the first row above 531300352 bytes (2.03 N) | rows 1048576 | cells 12582912 | warnings 1 (cellOutsideSheet ×3886860)
vm | peak RSS | before 182435840 bytes | after 715309056 bytes | above the baseline 532873216 bytes (2.03 N) | rose during the read: yes
chrome | input | built in 2529 ms | 1965092 bytes | xl/worksheets/sheet1.xml 1963917 bytes deflated, 262143983 bytes XML | ratio 133.5 | k n/a (no row varied) | rows 1372481
chrome | XlsxReader | 19269 ms | 1965092 bytes | peak JS heap peak 2328197079 bytes | baseline 1333783404 bytes | above 994413675 bytes (3.79 N) | after the first row above 987389113 bytes (3.77 N) | rows 1048576 | cells 12582912 | warnings 1 (cellOutsideSheet ×3886860)
chrome | input | built in 2530 ms | 1965092 bytes | xl/worksheets/sheet1.xml 1963917 bytes deflated, 262143983 bytes XML | ratio 133.5 | k n/a (no row varied) | rows 1372481
chrome | XlsxReader | 19582 ms | 1965092 bytes | peak JS heap peak 2331909207 bytes | baseline 1334044348 bytes | above 997864859 bytes (3.81 N) | after the first row above 986942313 bytes (3.76 N) | rows 1048576 | cells 12582912 | warnings 1 (cellOutsideSheet ×3886860)
```

### What it means for an upload

- **A 2 MB upload can hold a browser tab for about 20 seconds and add about
  1 GB to its heap, for one sheet.** The default limits let a file of under
  2 MB expand to 250 MiB of XML in its largest single sheet; reading it
  took 19.3 s in Chrome, synchronously, on the thread that called the
  reader, and lifted the used JS heap by about 1 GB (3.8 N) to 2.3 GB in
  all (with the page's garbage). The tab did not crash on this machine; a
  device with less memory, or a tab already holding more, may. On the VM
  the same read took 18.5 s and 531 MB above its baseline (2.03 N).
- **A workbook can cost more than its largest sheet.** Under the default
  limits the shared strings part may also inflate to 256 MiB, and the
  reader holds its strings (a `List<String>`) while a sheet is read, so a
  sheet read can hold both at once. And a workbook of four sheets of about
  250 MiB each passes every limit, `maxTotalBytes` (1 GiB) included:
  reading every sheet then costs up to `maxTotalBytes` of XML, each sheet
  about as much as the one measured. Neither case was measured; the figures
  above are for one sheet without shared strings.
- **The size on the wire says little.** A file of 2 MB passes every limit;
  the bounds that hold are `maxEntryBytes` on each inflated part and
  `maxTotalBytes` on all of them. A consumer
  that accepts uploads in a browser should run the reader off the UI thread
  (a web worker) and, if it wants a smaller worst case, pass a lower
  `maxEntryBytes` and a lower `maxTotalBytes`: memory and time scale with
  the XML read.
- **A smaller file is possible.** Rows of this shape cap the ratio near
  258 (above), about 1 MB on the wire. Content with a shorter period (long
  runs of whitespace between elements, for instance) can approach the
  1,000 limit, about 256 KB for the same entry; memory follows N, not the
  file size, so the peak would be about the same.
- The default limits stay as they are (plan ruling 6); any proposal to
  change them is the owner's to rule on, with the measured 100,000 × 12
  sheet's N (43,580,479 bytes) times four, 174,321,916 bytes, as the floor.

## Format figures

The format benchmark (`benchmark/xlsx_format_benchmark_test.dart`) times
`XlsxNumberFormatter` (en-US, 1900 date system) on the read workload's
values, and on three kinds of value alone.

### Method

- Untimed: the workload file is made as for the read benchmark
  (`benchmark/src/workload_file.dart`), read with `XlsxReader`, and every
  `XlsxReadCell` of the sheet is collected into a list; the count is
  asserted (1,166,679).
- `formatCell on every cell of the workload`: one formatter calls
  `formatCell` on every cell. The cells are text, `General` numbers,
  `#,##0.00`, `yyyy-mm-dd hh:mm`, `yyyy-mm-dd`, booleans and the formulas'
  `null` values. The test asserts that no result carries a warning.
- `per kind`: 100,000 values each, made before the timing, formatted with
  `format(value, numberFormat: code)`:
  - number: `XlsxDecimal('$r.25')` with `#,##0.00`;
  - serial date: `XlsxDecimal('${46000 + r % 3000}.${r % 86400}')` with
    `yyyy-mm-dd hh:mm:ss`, which takes the `BigInt` serial rounding of
    `lib/src/xlsx/format/excel_date.dart`;
  - `DateTime(2026, 1, 1).add(Duration(seconds: r * 37))` with
    `yyyy-mm-dd hh:mm:ss`.

  One sample text per kind is asserted (`1,000.25`, `2025-12-10 02:24:00`,
  `2026-01-01 01:01:40`).
- Every case runs once as a warm-up (which also fills the formatter's code
  cache), then three timed runs (`Stopwatch`); the median is given. Each
  run sums the lengths of the texts it made, and the sum must equal the
  warm-up's, so the work is used. The ratio is a kind's median over the
  number run's.

### Figures

- Date: 2026-10-30.
- Machine: Mac15,7, Apple M3 Pro, 36 GiB RAM (38,654,705,664 bytes).
- OS: macOS 27.2 (26B123).
- Dart SDK 3.13.7 (stable); the VM runs the JIT, Chrome runs dart2js output.
- Chrome 156.0.8078.74.

| Case (median of 3) | VM (ms) | VM (ns each) | Chrome (ms) | Chrome (ns each) |
|---|---|---|---|---|
| `formatCell`, every cell (1,166,679) | 1599.0 | 1371 | 2726.9 | 2337 |
| Number, `XlsxDecimal`, `#,##0.00` (100,000) | 145.4 | 1454 | 245.0 | 2450 |
| Serial date, `XlsxDecimal`, `yyyy-mm-dd hh:mm:ss` (100,000) | 312.5 | 3125 | 384.1 | 3841 |
| `DateTime`, `yyyy-mm-dd hh:mm:ss` (100,000) | 546.9 | 5469 | 901.9 | 9019 |

| Ratio to the number run | VM | Chrome |
|---|---|---|
| Serial date | 2.15 | 1.57 |
| `DateTime` | 3.76 | 3.68 |

Every line:

```text
vm | input | 6958087 bytes | 1166679 cells
vm | formatCell | median 1599.0 ms | 1166679 cells | 1371 ns/cell | warnings 0
vm | number | XlsxDecimal #,##0.00 | median 145.4 ms | 1454 ns/value | ratio 1.00
vm | serial date | XlsxDecimal yyyy-mm-dd hh:mm:ss | median 312.5 ms | 3125 ns/value | ratio 2.15
vm | DateTime | yyyy-mm-dd hh:mm:ss | median 546.9 ms | 5469 ns/value | ratio 3.76
chrome | input | 6981844 bytes | 1166679 cells
chrome | formatCell | median 2726.9 ms | 1166679 cells | 2337 ns/cell | warnings 0
chrome | number | XlsxDecimal #,##0.00 | median 245.0 ms | 2450 ns/value | ratio 1.00
chrome | serial date | XlsxDecimal yyyy-mm-dd hh:mm:ss | median 384.1 ms | 3841 ns/value | ratio 1.57
chrome | DateTime | yyyy-mm-dd hh:mm:ss | median 901.9 ms | 9019 ns/value | ratio 3.68
```

### Reading the figures

- **Formatting a sheet costs about 0.6 of reading it on the VM and 0.8
  in Chrome.** Formatting the 1,166,679 cells takes 1.6 s on the VM
  (1.4 µs a cell) and 2.7 s in Chrome (2.3 µs a cell), against a read of
  2.7 s and 3.3 s ("Read figures"). A consumer that shows every cell of a
  read pays roughly 1.6 times the read on the VM and 1.8 times in Chrome.
- **The `BigInt` serial rounding is cheap in Chrome.** A serial date given
  as an `XlsxDecimal` costs 2.15 times a number on the VM and 1.57 times
  in Chrome, well under 5 times, the point at which this page would report it.
  Nothing is recommended.
- **A `DateTime` costs more than a serial.** The same code on a `DateTime`
  costs 3.76 times a number on the VM and 3.68 times in Chrome, about 1.75
  and 2.35 times the serial date. The benchmark does not say why. It is
  the path a read takes: the reader gives a date-formatted cell as a
  `DateTime`, so the workload's two date columns are formatted this way.
