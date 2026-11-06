/// Pure-Dart building blocks shared by the jet_ packages.
///
/// jet_core knows no file format and has no dependencies. It holds what two
/// families of packages really use: today, the number format engine that
/// shows a value as Excel for Mac does (to be added). Bytes and values in,
/// text out: nothing here touches `dart:io`, `dart:ui`, `dart:html` or
/// Flutter, so it runs on the web, desktop, mobile and server alike.
///
/// The public API is exactly what this library exports; everything under
/// `lib/src/` is private.
library;
