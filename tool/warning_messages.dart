/// Prints every warning message in every language as a Markdown table, the
/// sheet a native speaker reads.
///
/// ```bash
/// dart run tool/warning_messages.dart > docs/warning-messages.md
/// ```
///
/// New in jet_office. Each message is built for a sample warning through the
/// same `WarningCollector` path as the architecture guard
/// `test/architecture/warning_messages_test.dart`: sheet `Daten`, cells
/// `A1, B2`, count 2 (a sheet-name code names one sheet, asked for as
/// `Daten:1` or `daten`, so its count is 1 and it names no cell;
/// `sheetPartMissing` is also one sheet and no cell). `unresolvedNumberFormat`
/// has a second row for the warning without a format id, the one that
/// gathers every format id after the first ten of a sheet.
/// `styleEntryInvalid` names no cell: its sample is one entry with a
/// detail, and its second row the warning without one, which counts the
/// entries after the first ten (2 here). `layoutInvalid` is likewise one
/// setting of sheet `Daten` with a detail, and a second row without one.
/// `test/tool/warning_messages_test.dart` compares the output with the
/// committed `docs/warning-messages.md`, so the file cannot drift.
library;

import 'dart:io';

import 'package:jet_office/src/common/locale.dart';
import 'package:jet_office/src/docx/warnings.dart';
import 'package:jet_office/src/xlsx/warnings.dart';

/// The sample warning of [code]: sheet `Daten`, cells `A1, B2`, count 2.
///
/// [detail] is the format id of `unresolvedNumberFormat`; null gives the
/// warning without one.
XlsxWarning _sample(XlsxWarningCode code, {String? detail = '27'}) {
  const String entry = 'font 3: The font size "abc" is not a finite number.';
  const String layoutEntry = 'row 3: ht "abc" is not a row height.';
  const String featureEntry = 'dataValidation: sqref "abc" is not a range.';
  final WarningCollector collector = WarningCollector();
  switch (code) {
    case XlsxWarningCode.sheetNameChanged:
      collector.add(code, sheet: 'Daten', originalName: 'Daten:1');
    case XlsxWarningCode.sheetNameDuplicated:
      collector.add(code, sheet: 'Daten', originalName: 'daten');
    case XlsxWarningCode.sheetPartMissing:
      collector.add(code, sheet: 'Daten');
    case XlsxWarningCode.mergeRangeInvalid:
      collector.add(code, sheet: 'Daten');
      collector.add(code, sheet: 'Daten');
    case XlsxWarningCode.layoutInvalid:
      if (detail == null) {
        for (var i = 0; i < 12; i++) {
          collector.add(code, sheet: 'Daten', detail: 'row $i');
        }
        return collector.warnings.last;
      }
      collector.add(code, sheet: 'Daten', detail: layoutEntry);
    case XlsxWarningCode.featureEntryInvalid:
      if (detail == null) {
        for (var i = 0; i < 12; i++) {
          collector.add(code, sheet: 'Daten', detail: 'dataValidation $i');
        }
        return collector.warnings.last;
      }
      collector.add(code, sheet: 'Daten', detail: featureEntry);
    case XlsxWarningCode.styleEntryInvalid:
      if (detail == null) {
        for (var i = 0; i < 12; i++) {
          collector.add(code, sheet: 'Daten', detail: 'font $i');
        }
        return collector.warnings.last;
      }
      collector.add(code, sheet: 'Daten', detail: entry);
    case XlsxWarningCode.unresolvedNumberFormat:
      collector
        ..add(code, sheet: 'Daten', cell: 'A1', detail: detail)
        ..add(code, sheet: 'Daten', cell: 'B2', detail: detail);
    case XlsxWarningCode.invalidCharactersRemoved:
    case XlsxWarningCode.textTruncated:
    case XlsxWarningCode.intPrecisionLost:
    case XlsxWarningCode.dateOutsideExcelRange:
    case XlsxWarningCode.dateInNonDateFormat:
    case XlsxWarningCode.tableColumnRenamed:
    case XlsxWarningCode.tableHeaderAdjusted:
    case XlsxWarningCode.sharedStringInvalid:
    case XlsxWarningCode.numberInvalid:
    case XlsxWarningCode.booleanInvalid:
    case XlsxWarningCode.cellTypeUnsupported:
    case XlsxWarningCode.formulaWithoutValue:
    case XlsxWarningCode.cellReferenceInvalid:
    case XlsxWarningCode.cellDuplicated:
    case XlsxWarningCode.rowOutOfOrder:
    case XlsxWarningCode.cellOutsideSheet:
    case XlsxWarningCode.styleInvalid:
    case XlsxWarningCode.serialOutOfRange:
    case XlsxWarningCode.phantomLeapDay:
    case XlsxWarningCode.dateTextInvalid:
    case XlsxWarningCode.errorValueInvalid:
    case XlsxWarningCode.formulaGroupInvalid:
    case XlsxWarningCode.numberFormatInvalid:
    case XlsxWarningCode.numberFormatUnsupported:
    case XlsxWarningCode.numberFormatLocaleDependent:
      collector
        ..add(code, sheet: 'Daten', cell: 'A1')
        ..add(code, sheet: 'Daten', cell: 'B2');
  }
  return collector.warnings.single;
}

/// The sample DOCX warning of [code]: part `/word/document.xml`, locations
/// `body/p[0]` and `body/p[1]`, count 2, and for the two content type codes
/// the detail they name; `numberingNotFound` names the list `7` and
/// `styleNotFound` the style `Foo`; `bookmarkNameRepaired` names `2 Totals!`.
/// With [one], `invalidCharactersRemoved`, `numberingNotFound`,
/// `styleNotFound` and `bookmarkNameRepaired` count 1 at `body/p[0]`, for their
/// singular text.
DocxWarning _docxSample(DocxWarningCode code, {bool one = false}) {
  final DocxWarningCollector collector = DocxWarningCollector();
  switch (code) {
    case DocxWarningCode.invalidCharactersRemoved:
      collector.add(code, part: '/word/document.xml', location: 'body/p[0]');
      if (!one) {
        collector.add(code, part: '/word/document.xml', location: 'body/p[1]');
      }
    case DocxWarningCode.contentTypeMissing:
      collector.add(
        code,
        part: '/word/document.xml',
        detail: 'application/xml',
      );
    case DocxWarningCode.mainPartContentTypeUnexpected:
      collector.add(code, part: '/word/document.xml', detail: 'text/plain');
    case DocxWarningCode.numberingNotFound:
      for (int i = 0; i < (one ? 1 : 2); i++) {
        collector.add(
          code,
          part: '/word/document.xml',
          location: 'body/p[$i]',
          detail: '7',
        );
      }
    case DocxWarningCode.styleNotFound:
      for (int i = 0; i < (one ? 1 : 2); i++) {
        collector.add(
          code,
          part: '/word/document.xml',
          location: 'body/p[$i]',
          detail: 'Foo',
        );
      }
    case DocxWarningCode.propertyValueInvalid:
      collector.add(code, part: '/docProps/core.xml', detail: 'cp:revision');
    case DocxWarningCode.bookmarkNameRepaired:
      for (int i = 0; i < (one ? 1 : 2); i++) {
        collector.add(
          code,
          part: '/word/document.xml',
          location: 'body/p[$i]',
          detail: '2 Totals!',
        );
      }
  }
  return collector.warnings.single;
}

/// A table cell: [text] with `|` escaped so it cannot end the cell.
String _cell(String text) => text.replaceAll('|', r'\|');

/// The Markdown of `docs/warning-messages.md`.
String warningMessagesMarkdown() {
  final StringBuffer out = StringBuffer()
    ..writeln('# Warning messages')
    ..writeln()
    ..writeln('Generated by `tool/warning_messages.dart`. Do not edit it by')
    ..writeln('hand; regenerate it with:')
    ..writeln()
    ..writeln('```bash')
    ..writeln('dart run tool/warning_messages.dart > docs/warning-messages.md')
    ..writeln('```')
    ..writeln()
    ..writeln('`test/tool/warning_messages_test.dart` fails when this file')
    ..writeln('differs from the tool output.')
    ..writeln()
    ..writeln('Every message is built for a sample warning: sheet `Daten`,')
    ..writeln('cells `A1, B2`, count 2. The two sheet-name codes name one')
    ..writeln('sheet instead, asked for as `Daten:1` (changed) or `daten`')
    ..writeln('(duplicated). `sheetPartMissing` names one sheet and no cell;')
    ..writeln('`mergeRangeInvalid` counts 2 and names no cell, and')
    ..writeln('`unresolvedNumberFormat` uses format 27; its second row is the')
    ..writeln('warning without a format id, which gathers the format ids after')
    ..writeln('the first ten of a sheet. `styleEntryInvalid` names no')
    ..writeln('cell: its first row is one entry, its second the warning')
    ..writeln('without a detail, which counts the entries after the first')
    ..writeln('ten. `layoutInvalid` names no cell either: its first row is one')
    ..writeln('setting of sheet `Daten`, its second the warning without a')
    ..writeln('detail, which counts the settings after the first ten.')
    ..writeln('`featureEntryInvalid` names no cell: its first row is one entry')
    ..writeln('of sheet `Daten`, its second the warning without a detail,')
    ..writeln('which counts the entries after the first ten. A workbook\'s')
    ..writeln('entry says "the workbook" instead of the sheet.')
    ..writeln()
    ..writeln('The native-speaker check of the German and Turkish text is')
    ..writeln('recorded under "Native-speaker check" in')
    ..writeln('[`excel-checks.md`](excel-checks.md), not here.')
    ..writeln()
    ..writeln('| Code | en | de | tr |')
    ..writeln('|---|---|---|---|');
  void row(String name, XlsxWarning w) => out.writeln(
    '| $name | ${_cell(w.message(OfficeLocale.en))} '
    '| ${_cell(w.message(OfficeLocale.de))} '
    '| ${_cell(w.message(OfficeLocale.tr))} |',
  );
  for (final XlsxWarningCode code in XlsxWarningCode.values) {
    row('`${code.name}`', _sample(code));
    if (code == XlsxWarningCode.unresolvedNumberFormat) {
      row('`${code.name}` (no id)', _sample(code, detail: null));
    }
    if (code == XlsxWarningCode.styleEntryInvalid ||
        code == XlsxWarningCode.layoutInvalid ||
        code == XlsxWarningCode.featureEntryInvalid) {
      row('`${code.name}` (no detail)', _sample(code, detail: null));
    }
  }
  out
    ..writeln()
    ..writeln('## DOCX')
    ..writeln()
    ..writeln('Every DOCX message is built for a sample warning: part')
    ..writeln('`/word/document.xml`. `invalidCharactersRemoved` counts 2 and')
    ..writeln('names `body/p[0]` and `body/p[1]`; `contentTypeMissing` names')
    ..writeln('`application/xml` and `mainPartContentTypeUnexpected` names')
    ..writeln('`text/plain`; `numberingNotFound` counts 2, names `body/p[0]`')
    ..writeln('and `body/p[1]` and the list `7`; `styleNotFound` counts 2,')
    ..writeln('names `body/p[0]` and `body/p[1]` and the style `Foo`;')
    ..writeln('`propertyValueInvalid` names `/docProps/core.xml` and')
    ..writeln('`cp:revision`; `bookmarkNameRepaired` counts 2 and names')
    ..writeln('`2 Totals!`. The second `invalidCharactersRemoved`,')
    ..writeln('`numberingNotFound`, `styleNotFound` and')
    ..writeln('`bookmarkNameRepaired` rows count 1 and name `body/p[0]`, for')
    ..writeln('the singular.')
    ..writeln()
    ..writeln('| Code | en | de | tr |')
    ..writeln('|---|---|---|---|');
  void docxRow(String name, DocxWarning w) => out.writeln(
    '| $name | ${_cell(w.message(OfficeLocale.en))} '
    '| ${_cell(w.message(OfficeLocale.de))} '
    '| ${_cell(w.message(OfficeLocale.tr))} |',
  );
  for (final DocxWarningCode code in DocxWarningCode.values) {
    docxRow('`docx: ${code.name}`', _docxSample(code));
    if (code == DocxWarningCode.invalidCharactersRemoved ||
        code == DocxWarningCode.numberingNotFound ||
        code == DocxWarningCode.styleNotFound ||
        code == DocxWarningCode.bookmarkNameRepaired) {
      docxRow('`docx: ${code.name}` (one)', _docxSample(code, one: true));
    }
  }
  return out.toString();
}

void main() {
  stdout.write(warningMessagesMarkdown());
}
