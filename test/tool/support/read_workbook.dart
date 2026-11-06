/// A small reader of the oracle workbooks, for the tests of
/// `tool/src/format_oracle.dart`.
///
/// It reads the parts `buildOracleWorkbooks` writes with `package:archive`
/// and `package:xml`, both dev dependencies, so the tests do not depend on
/// any library that reads XLSX. It knows only what the tests ask: the sheet
/// names, the date system, each sheet's rows and column widths, each cell's
/// value and number format, and [ReadWorkbook.problems], the structural
/// defects of the package (a part that is not well-formed XML, a relationship
/// or content type pointing nowhere, a style index out of range).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:jet_core/jet_core.dart';
import 'package:xml/xml.dart';

/// A number cell's value as written: the digits of its `<v>`.
final class ReadNumber {
  /// Creates a number value.
  const ReadNumber(this.digits);

  /// The digits as written in the file.
  final String digits;

  @override
  bool operator ==(Object other) =>
      other is ReadNumber && other.digits == digits;

  @override
  int get hashCode => digits.hashCode;

  @override
  String toString() => 'ReadNumber($digits)';
}

/// One cell of a sheet.
final class ReadCell {
  /// Creates a cell.
  const ReadCell({
    required this.column,
    required this.value,
    required this.numberFormatId,
    required this.numberFormat,
  });

  /// The zero-based column.
  final int column;

  /// A [String], a [bool], a [ReadNumber], or `null` for a cell with no
  /// value.
  final Object? value;

  /// The id of the number format of the cell's style (0 without a style).
  final int numberFormatId;

  /// The code of that id: the styles part's own code, else the built-in
  /// code of the id, else `null`.
  final String? numberFormat;

  /// Whether the cell's code shows a date or a time.
  bool get isDate =>
      numberFormat != null &&
      classifyFormatCode(numberFormat!) != FormatKind.number;
}

/// One row of a sheet.
final class ReadRow {
  /// Creates a row.
  const ReadRow(this.index, this.cells);

  /// The zero-based row number (the header row is 0).
  final int index;

  /// The cells in column order.
  final List<ReadCell> cells;
}

/// One sheet of a workbook.
final class ReadSheet {
  /// Creates a sheet.
  const ReadSheet(this.name, this.rows, this.columnWidths);

  /// The sheet's name.
  final String name;

  /// The rows in file order.
  final List<ReadRow> rows;

  /// The width of each column that has one, by zero-based column.
  final Map<int, double> columnWidths;
}

/// An oracle workbook read back.
final class ReadWorkbook {
  /// Reads [bytes].
  factory ReadWorkbook(Uint8List bytes) {
    final Archive archive = ZipDecoder().decodeBytes(bytes);
    final Map<String, XmlDocument> parts = <String, XmlDocument>{};
    final List<String> problems = <String>[];
    for (final ArchiveFile file in archive.files) {
      if (!file.isFile) continue;
      try {
        parts[file.name] = XmlDocument.parse(utf8.decode(file.content));
      } on Object catch (e) {
        problems.add('${file.name}: not well-formed XML ($e)');
      }
    }
    XmlElement? root(String name) => parts[name]?.rootElement;

    final XmlElement? workbook = root('xl/workbook.xml');
    final XmlElement? styles = root('xl/styles.xml');
    if (workbook == null) problems.add('xl/workbook.xml is missing');
    if (styles == null) problems.add('xl/styles.xml is missing');

    // Content types: every override names a part, every part is typed.
    final XmlElement? types = root('[Content_Types].xml');
    final Set<String> defaults = <String>{
      if (types != null)
        for (final XmlElement d in types.findElements('Default'))
          d.getAttribute('Extension')!,
    };
    final Set<String> overrides = <String>{
      if (types != null)
        for (final XmlElement o in types.findElements('Override'))
          o.getAttribute('PartName')!.substring(1),
    };
    for (final String name in overrides) {
      if (!parts.containsKey(name)) problems.add('$name: typed but missing');
    }
    for (final String name in parts.keys) {
      if (name != '[Content_Types].xml' &&
          !overrides.contains(name) &&
          !defaults.contains(name.split('.').last)) {
        problems.add('$name: has no content type');
      }
    }

    // Relationships: every target is a part.
    final Map<String, String> sheetTargets = <String, String>{};
    for (final String relsName in parts.keys.where(
      (String n) => n.endsWith('.rels'),
    )) {
      final String base = relsName == '_rels/.rels'
          ? ''
          : relsName
                .replaceFirst('_rels/', '')
                .replaceFirst(RegExp(r'\.rels$'), '');
      final String dir = base.contains('/')
          ? base.substring(0, base.lastIndexOf('/') + 1)
          : '';
      for (final XmlElement r in parts[relsName]!.rootElement.findElements(
        'Relationship',
      )) {
        final String target = '$dir${r.getAttribute('Target')}';
        if (!parts.containsKey(target)) {
          problems.add(
            '$relsName: ${r.getAttribute('Id')} points at missing '
            '$target',
          );
        }
        sheetTargets['$relsName#${r.getAttribute('Id')}'] = target;
      }
    }

    // Styles: the codes by id, and each cell format's number format id.
    final Map<int, String> codes = <int, String>{
      if (styles != null)
        for (final XmlElement n in styles.descendantElements.where(
          (XmlElement e) => e.name.local == 'numFmt',
        ))
          int.parse(n.getAttribute('numFmtId')!): n.getAttribute('formatCode')!,
    };
    final List<int> xfIds = <int>[
      if (styles != null)
        for (final XmlElement xf
            in styles
                .findElements('cellXfs')
                .expand((XmlElement e) => e.findElements('xf')))
          int.parse(xf.getAttribute('numFmtId')!),
    ];

    final List<ReadSheet> sheets = <ReadSheet>[];
    if (workbook != null) {
      for (final XmlElement s
          in workbook
              .findElements('sheets')
              .expand((XmlElement e) => e.findElements('sheet'))) {
        final String? rid = s.attributes
            .where((XmlAttribute a) => a.name.local == 'id')
            .map((XmlAttribute a) => a.value)
            .firstOrNull;
        final String? target = sheetTargets['xl/_rels/workbook.xml.rels#$rid'];
        final XmlElement? sheet = target == null ? null : root(target);
        if (sheet == null) {
          problems.add('sheet ${s.getAttribute('name')}: no part');
          continue;
        }
        sheets.add(
          _readSheet(s.getAttribute('name')!, sheet, codes, xfIds, problems),
        );
      }
    }
    final String? date1904 = workbook
        ?.findElements('workbookPr')
        .firstOrNull
        ?.getAttribute('date1904');
    return ReadWorkbook._(
      sheets,
      date1904 == '1' || date1904 == 'true',
      problems,
    );
  }

  const ReadWorkbook._(this.sheets, this.date1904, this.problems);

  /// The sheets in workbook order.
  final List<ReadSheet> sheets;

  /// Whether the workbook uses the 1904 date system.
  final bool date1904;

  /// The structural defects found while reading; empty for a sound package.
  final List<String> problems;

  /// The sheet named [name].
  ReadSheet sheet(String name) =>
      sheets.singleWhere((ReadSheet s) => s.name == name);
}

ReadSheet _readSheet(
  String name,
  XmlElement sheet,
  Map<int, String> codes,
  List<int> xfIds,
  List<String> problems,
) {
  final Map<int, double> widths = <int, double>{
    for (final XmlElement c
        in sheet
            .findElements('cols')
            .expand((XmlElement e) => e.findElements('col')))
      for (
        int i = int.parse(c.getAttribute('min')!);
        i <= int.parse(c.getAttribute('max')!);
        i++
      )
        i - 1: double.parse(c.getAttribute('width')!),
  };
  final List<ReadRow> rows = <ReadRow>[];
  for (final XmlElement r
      in sheet
          .findElements('sheetData')
          .expand((XmlElement e) => e.findElements('row'))) {
    final List<ReadCell> cells = <ReadCell>[];
    for (final XmlElement c in r.findElements('c')) {
      final int style = int.parse(c.getAttribute('s') ?? '0');
      if (style >= xfIds.length) {
        problems.add('$name ${c.getAttribute('r')}: style $style out of range');
      }
      final int id = style < xfIds.length ? xfIds[style] : 0;
      final String? type = c.getAttribute('t');
      final String? v = c.findElements('v').firstOrNull?.innerText;
      final Object? value = switch (type) {
        'inlineStr' =>
          c
              .findElements('is')
              .expand((XmlElement e) => e.findAllElements('t'))
              .map((XmlElement t) => t.innerText)
              .join(),
        'b' => v == '1',
        _ => v == null ? null : ReadNumber(v),
      };
      cells.add(
        ReadCell(
          column: _column(c.getAttribute('r')!),
          value: value,
          numberFormatId: id,
          numberFormat:
              codes[id] ?? (id == 0 ? 'General' : builtinNumberFormatCode(id)),
        ),
      );
    }
    rows.add(ReadRow(int.parse(r.getAttribute('r')!) - 1, cells));
  }
  return ReadSheet(name, rows, widths);
}

/// The zero-based column of a reference such as `B12`.
int _column(String ref) {
  int column = 0;
  for (final int unit in ref.codeUnits) {
    if (unit < 0x41 || unit > 0x5A) break;
    column = column * 26 + unit - 0x40;
  }
  return column - 1;
}
