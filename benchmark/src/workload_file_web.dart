/// The workload's file in the browser: written in the page.
///
/// New in jet_office.
library;

import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';

import 'workload.dart';

/// Writes the workload of [rows] data rows with [XlsxWriter] and returns
/// the file's bytes.
Uint8List workloadFile(int rows) {
  final XlsxWriter book = XlsxWriter();
  writeWorkload(book.addSheet('Data'), rows, (int _) {});
  return book.close().bytes;
}
