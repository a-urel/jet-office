# 0006 — ZIP bytes may differ by platform; part contents may not

**Status:** Proposed — awaiting the owner (2026-10-27)

## Context

The phase 1 spec, section 4.6, requires byte-identical output: the same input
gives the same bytes. The writer is pure Dart and runs on the VM and on the
web, so the requirement reads as "the same bytes on every platform".

## Finding

`package:archive` deflates with the native zlib on the VM and with its own
pure-Dart deflate on the web. For the same workbook the two give different,
equally valid streams, so the ZIP bytes differ (about 23 KB apart on the
benchmark file, see `docs/benchmark.md`). Every part's contents, the bytes of
each part after unzipping, are identical on both platforms.
`test/xlsx/cross_platform_parts_test.dart` proves that: it checks FNV-1a
sums of each part of a 300-row workload against the same constants on the VM
and in Chrome.

The first run of the benchmark also found a real difference in the parts: a
`double` with a whole value was written as `5.0` on the VM and as `5` on the
web, because `5.0 is int` is true in dart2js. Doubles are now spelled the same
on both platforms (`formatXmlDouble`, tested on both).

## Decision

**The contents of every part are byte-identical on every platform. The ZIP
bytes are identical only within one platform. The writer keeps archive's
deflate.**

- The guarantee of section 4.6 holds per platform for the container and
  across platforms for the parts.
- The cross-platform test stays the proof for the parts; a change that makes
  a part differ between the VM and Chrome fails it.

## Consequences

**A reader sees no difference.** Excel, LibreOffice and every unzip tool
read both streams; the parts they get are equal. Only a byte comparison of
two files written on different platforms differs.

**Caching and diffing by file hash work per platform only.** A caller that
needs one hash everywhere should hash the unzipped parts.

**The alternative is one pure-Dart deflate everywhere.** It would make the ZIP
bytes identical on every platform, but it is slower on the VM, where the
native zlib is much faster, and the file size would depend on that
implementation instead of zlib. The owner can choose it later; it is a change
inside `lib/src/zip/archive_adapter.dart` and would supersede this record.
