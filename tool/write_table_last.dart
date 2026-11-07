/// Writes `d3_table_last.docx`, a document whose body ends in a table, for the
/// owner's Word check.
///
/// ```bash
/// dart run tool/write_table_last.dart <dir>
/// ```
///
/// LibreOffice's text export of such a document never ends, so no fixture of
/// `tool/write_fixtures.dart` is one and this file is written apart: open it in
/// Word for Mac (`docs/word-checks.md`, section D3). Word writes a paragraph
/// after every table it saves, so the owner cannot make this file in Word. The
/// exit code is 64 on bad arguments. Not ported from Quds.
library;

import 'dart:io';

import 'package:jet_office/jet_office.dart';

void main(List<String> args) {
  if (args.length != 1 || args.single.startsWith('-')) {
    stderr.writeln('Usage: dart run tool/write_table_last.dart <dir>');
    exitCode = 64;
    return;
  }
  final Directory dir = Directory(args.single)..createSync(recursive: true);
  final DocxDocument doc = DocxDocument();
  doc.body.addParagraph('The table is the last block of the body.');
  final DocxTable table = doc.body.addTable(columns: 2);
  table.addRow(<String?>['Name', 'Value'], header: true);
  table.addRow(<String?>['Last', 'row']);
  File('${dir.path}/d3_table_last.docx').writeAsBytesSync(doc.save().bytes);
  stdout.writeln('Wrote d3_table_last.docx to ${dir.path}.');
}
