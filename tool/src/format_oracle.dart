/// The Excel oracle for the number format engine: its case list and the
/// workbooks `tool/write_format_oracle.dart` writes from it.
///
/// Moved from jet_office (milestone N3 of decision 0008), where it wrote
/// the workbooks with the library's XLSX writer. The case list is
/// `test/fixtures/owner/number_format/cases.json`; its format is described
/// in the README beside it and enforced by [parseOracleCases]. Each case is
/// one row of its workbook: the value in column A in the case's format, the
/// code as text in column B (`builtin <id>` for a built-in id), the case id
/// in column C and a note in column D. Cases Excel's CSV does not show as
/// the cell does ([OracleCase.eyeOnly]) go on a second sheet, `eye`, whose
/// column A keeps the default width; the rest go on the first sheet,
/// `cases`, the one Excel saves as CSV.
///
/// [buildOracleWorkbooks] writes the files itself, with a small XLSX writer
/// of its own (`archive`, a dev dependency): jet_core knows no file format
/// and depends on no package that writes one. It writes
/// `<workbookPr date1904="1"/>` in the workbook part for a 1904 workbook and
/// an [OracleWorkbook.numFmts] entry per overridden built-in id in the styles
/// part, so a file can carry its own code for id 14, as Excel's files do.
///
/// It throws a [FormatException] rather than write a file Excel would
/// repair: for a cell's text of more than 32,767 characters and for a format
/// code of more than 255.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Where the committed case list lives, relative to the repository root.
const String oracleCasesPath = 'test/fixtures/owner/number_format/cases.json';

/// The highest number of the "Settled by Excel" list (the Unknowns) in
/// `docs/number-format.md`.
const int _maxUnknown = 21;

/// The most characters Excel keeps in a cell's text.
const int _maxCellText = 32767;

/// The most characters Excel keeps in a number format code.
const int _maxFormatCode = 255;

final RegExp _idPattern = RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$');
final RegExp _checkPattern = RegExp(r'^C\d+[a-z]?$');
final RegExp _digitsPattern = RegExp(r'^-?\d+(\.\d+)?$');

/// The parsed case list: the workbooks by key and the cases in file order.
final class OracleCases {
  /// Creates a case list.
  const OracleCases(this.workbooks, this.cases);

  /// The workbooks by key (`main`, `date1904`, `invalid`), in file order.
  final Map<String, OracleWorkbook> workbooks;

  /// The cases in file order, which is their row order in each workbook.
  final List<OracleCase> cases;
}

/// One workbook of the oracle.
final class OracleWorkbook {
  /// Creates a workbook description.
  const OracleWorkbook(this.key, this.file, this.date1904, this.numFmts);

  /// The key cases name it by.
  final String key;

  /// The file name, such as `format_oracle.xlsx`.
  final String file;

  /// Whether the workbook uses the 1904 date system.
  final bool date1904;

  /// Codes the file gives built-in ids (id to code), such as
  /// `14: yyyy-mm-dd`.
  final Map<int, String> numFmts;
}

/// A case's value in column A.
sealed class OracleValue {
  const OracleValue();
}

/// A number, as decimal digits (`{"n": "-1234.5"}`).
final class OracleNumber extends OracleValue {
  /// Creates a number value.
  const OracleNumber(this.digits);

  /// The digits, as `FormatDecimal` accepts them.
  final String digits;
}

/// A boolean (`{"b": true}`).
final class OracleBool extends OracleValue {
  /// Creates a boolean value.
  const OracleBool(this.value);

  /// The boolean.
  final bool value;
}

/// A text (`{"s": "abc"}`).
final class OracleText extends OracleValue {
  /// Creates a text value.
  const OracleText(this.text);

  /// The text.
  final String text;
}

/// A formula the owner types into column A by hand, for a value the writer
/// cannot produce, such as a spill error
/// (`{"manual": "=SEQUENCE(1,2)", "error": "#SPILL!"}`).
final class OracleManual extends OracleValue {
  /// Creates a manual value.
  const OracleManual(this.formula, this.error);

  /// The formula in English; the owner types it in Excel's language.
  final String formula;

  /// The error the formula results in, as its English code (`#SPILL!`).
  final String error;
}

/// One case: a value, a format and what it settles.
final class OracleCase {
  /// Creates a case.
  const OracleCase({
    required this.id,
    required this.checks,
    required this.unknown,
    required this.workbook,
    required this.date1904,
    required this.value,
    required this.code,
    required this.builtinId,
    required this.eyeOnly,
    required this.note,
  });

  /// The case id, unique, such as `c4-01`; column C of its row.
  final String id;

  /// The owner checklist items it settles (`C4a`), possibly none.
  final List<String> checks;

  /// The number in the "Settled by Excel" list (the Unknowns) of
  /// `docs/number-format.md`, or `null`.
  final int? unknown;

  /// The key of its workbook.
  final String workbook;

  /// Whether its workbook uses the 1904 date system.
  final bool date1904;

  /// The value in column A.
  final OracleValue value;

  /// The format code, or `null` when [builtinId] is set.
  final String? code;

  /// The built-in format id, or `null` when [code] is set.
  final int? builtinId;

  /// Whether the cell must be checked by eye: Excel's CSV does not show
  /// what the cell shows.
  final bool eyeOnly;

  /// What to look at, for the owner.
  final String note;
}

/// Parses the case list [text]. Throws a [FormatException] whose message
/// starts with the path of the first problem, such as `cases[3].code:`.
OracleCases parseOracleCases(String text) {
  final Object? root;
  try {
    root = jsonDecode(text);
  } on FormatException catch (e) {
    throw FormatException(r'$: not JSON: ' + e.message);
  }
  final Map<String, Object?> doc = _object(root, r'$', const <String>{
    'version',
    'workbooks',
    'cases',
  });
  if (doc['version'] != 1) _fail('version', 'expected 1');
  final Map<String, Object?> rawBooks = _object(doc['workbooks'], 'workbooks');
  final Map<String, OracleWorkbook> books = <String, OracleWorkbook>{
    for (final MapEntry<String, Object?> e in rawBooks.entries)
      e.key: _workbook(e.key, e.value),
  };
  final Object? rawCases = doc['cases'];
  if (rawCases is! List<Object?>) _fail('cases', 'expected a list');
  final Set<String> ids = <String>{};
  final List<OracleCase> cases = <OracleCase>[
    for (int i = 0; i < rawCases.length; i++)
      _case(rawCases[i], 'cases[$i]', books, ids),
  ];
  return OracleCases(books, cases);
}

OracleWorkbook _workbook(String key, Object? raw) {
  final String path = 'workbooks.$key';
  final Map<String, Object?> book = _object(raw, path, const <String>{
    'file',
    'dateSystem',
    'numFmts',
  });
  final Object? file = book['file'];
  if (file is! String || !file.endsWith('.xlsx') || file.contains('/')) {
    _fail('$path.file', 'expected a file name ending in .xlsx');
  }
  final bool date1904 = _dateSystem(book['dateSystem'], '$path.dateSystem');
  final Map<String, Object?> rawFmts = _object(
    book['numFmts'],
    '$path.numFmts',
  );
  final Map<int, String> numFmts = <int, String>{};
  for (final MapEntry<String, Object?> e in rawFmts.entries) {
    final int? id = int.tryParse(e.key);
    if (id == null || id < 0 || id > 163 || '$id' != e.key) {
      _fail('$path.numFmts.${e.key}', 'expected a built-in id, 0 to 163');
    }
    final Object? code = e.value;
    if (code is! String || code.isEmpty) {
      _fail('$path.numFmts.${e.key}', 'expected a non-empty code');
    }
    numFmts[id] = code;
  }
  return OracleWorkbook(key, file, date1904, numFmts);
}

OracleCase _case(
  Object? raw,
  String path,
  Map<String, OracleWorkbook> books,
  Set<String> ids,
) {
  final Map<String, Object?> c = _object(raw, path, const <String>{
    'id',
    'checks',
    'unknown',
    'workbook',
    'dateSystem',
    'value',
    'code',
    'builtinId',
    'eyeOnly',
    'note',
  });
  final Object? id = c['id'];
  if (id is! String || !_idPattern.hasMatch(id)) {
    _fail('$path.id', 'expected lower-case letters, digits and -');
  }
  if (!ids.add(id)) _fail('$path.id', 'duplicate id $id');

  final Object? rawChecks = c['checks'];
  if (rawChecks is! List<Object?>) _fail('$path.checks', 'expected a list');
  final List<String> checks = <String>[];
  for (int i = 0; i < rawChecks.length; i++) {
    final Object? check = rawChecks[i];
    if (check is! String || !_checkPattern.hasMatch(check)) {
      _fail('$path.checks[$i]', 'expected C<n> with an optional letter');
    }
    checks.add(check);
  }

  final Object? unknown = c['unknown'];
  if (unknown != null &&
      (unknown is! int || unknown < 1 || unknown > _maxUnknown)) {
    _fail('$path.unknown', 'expected null or 1 to $_maxUnknown');
  }

  final Object? workbook = c['workbook'];
  final OracleWorkbook? book = books[workbook];
  if (workbook is! String || book == null) {
    _fail('$path.workbook', 'expected one of ${books.keys.join(', ')}');
  }
  final bool date1904 = _dateSystem(c['dateSystem'], '$path.dateSystem');
  if (date1904 != book.date1904) {
    _fail('$path.dateSystem', "differs from workbook ${book.key}'s");
  }

  final OracleValue value = _value(c['value'], '$path.value');

  final Object? code = c['code'];
  final Object? builtinId = c['builtinId'];
  if ((code == null) == (builtinId == null)) {
    _fail(path, 'expected exactly one of code and builtinId');
  }
  if (code != null && (code is! String || code.isEmpty)) {
    _fail('$path.code', 'expected a non-empty string');
  }
  if (builtinId != null &&
      (builtinId is! int || builtinId < 0 || builtinId > 163)) {
    _fail('$path.builtinId', 'expected 0 to 163');
  }

  final Object? eyeOnly = c['eyeOnly'];
  if (eyeOnly is! bool) _fail('$path.eyeOnly', 'expected a boolean');
  if (value is OracleManual && !eyeOnly) {
    _fail('$path.eyeOnly', 'a manual value is checked by eye');
  }
  final Object? note = c['note'];
  if (note is! String) _fail('$path.note', 'expected a string');

  return OracleCase(
    id: id,
    checks: checks,
    unknown: unknown as int?,
    workbook: workbook,
    date1904: date1904,
    value: value,
    code: code as String?,
    builtinId: builtinId as int?,
    eyeOnly: eyeOnly,
    note: note,
  );
}

OracleValue _value(Object? raw, String path) {
  if (raw is! Map<String, Object?>) {
    _fail(path, 'expected an object with one of n, b, s, manual');
  }
  if (raw.length == 2 && raw.containsKey('manual')) {
    final Object? formula = raw['manual'];
    final Object? error = raw['error'];
    if (formula is String &&
        formula.startsWith('=') &&
        error is String &&
        error.startsWith('#')) {
      return OracleManual(formula, error);
    }
  }
  if (raw.length != 1) _fail(path, _valueProblem);
  final MapEntry<String, Object?> e = raw.entries.single;
  return switch (e) {
    MapEntry(key: 'n', value: final String d) when _digitsPattern.hasMatch(d) =>
      OracleNumber(d),
    MapEntry(key: 'b', value: final bool b) => OracleBool(b),
    MapEntry(key: 's', value: final String s) => OracleText(s),
    _ => _fail(path, _valueProblem),
  };
}

const String _valueProblem =
    'expected n (decimal digits as a string), b (a boolean), s (a string), '
    'or manual (a formula starting with =) with error (an error code '
    'starting with #)';

bool _dateSystem(Object? raw, String path) => switch (raw) {
  '1900' => false,
  '1904' => true,
  _ => _fail(path, 'expected "1900" or "1904"'),
};

Map<String, Object?> _object(Object? raw, String path, [Set<String>? keys]) {
  if (raw is! Map<String, Object?>) _fail(path, 'expected an object');
  if (keys != null) {
    for (final String key in raw.keys) {
      if (!keys.contains(key)) {
        _fail(path == r'$' ? key : '$path.$key', 'unknown key');
      }
    }
  }
  return raw;
}

Never _fail(String path, String problem) =>
    throw FormatException('$path: $problem');

/// The oracle workbooks of [cases], file name to bytes, in workbook order.
/// A workbook no case names is left out.
Map<String, Uint8List> buildOracleWorkbooks(OracleCases cases) =>
    <String, Uint8List>{
      for (final OracleWorkbook book in cases.workbooks.values)
        if (cases.cases.any((OracleCase c) => c.workbook == book.key))
          book.file: _build(book, <OracleCase>[
            for (final OracleCase c in cases.cases)
              if (c.workbook == book.key) c,
          ]),
    };

const List<String> _header = <String>['value', 'code', 'case', 'note'];

const String _mainNs =
    'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
const String _relNs =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const String _pkgRelNs =
    'http://schemas.openxmlformats.org/package/2006/relationships';
const String _xmlDecl =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>';

/// One sheet of a workbook: its name, its cases and the width of column A
/// (`null` keeps the default, which `General` adapts to).
final class _Sheet {
  const _Sheet(this.name, this.cases, this.valueWidth);

  final String name;
  final List<OracleCase> cases;
  final int? valueWidth;
}

/// The cell formats of one workbook: each distinct number format of a
/// column A cell gets one `cellXfs` entry, in order of first use. Entry 0 is
/// the default (`General`). A custom code gets the next id from 164.
final class _Styles {
  _Styles(this.book);

  final OracleWorkbook book;
  final List<int> _xfFormatIds = <int>[0];
  final Map<int, int> _xfOfId = <int, int>{0: 0};
  final Map<String, int> _idOfCode = <String, int>{};

  /// The `cellXfs` index of [c]'s column A format.
  int xfOf(OracleCase c) {
    final int id;
    if (c.builtinId != null) {
      id = c.builtinId!;
    } else if (c.code == 'General') {
      id = 0;
    } else {
      final String code = c.code!;
      if (code.length > _maxFormatCode) {
        throw FormatException(
          'case ${c.id}: the format code has ${code.length} characters, '
          'Excel keeps $_maxFormatCode',
        );
      }
      id = _idOfCode.putIfAbsent(code, () => 164 + _idOfCode.length);
    }
    return _xfOfId.putIfAbsent(id, () {
      _xfFormatIds.add(id);
      return _xfFormatIds.length - 1;
    });
  }

  /// The styles part, written after every cell asked for its format.
  String toXml() {
    final List<String> fmts = <String>[
      for (final MapEntry<int, String> e in book.numFmts.entries)
        '<numFmt numFmtId="${e.key}" formatCode="${_attribute(e.value)}"/>',
      for (final MapEntry<String, int> e in _idOfCode.entries)
        '<numFmt numFmtId="${e.value}" formatCode="${_attribute(e.key)}"/>',
    ];
    final StringBuffer b = StringBuffer(_xmlDecl)
      ..write('<styleSheet xmlns="$_mainNs">');
    if (fmts.isNotEmpty) {
      b.write('<numFmts count="${fmts.length}">${fmts.join()}</numFmts>');
    }
    b
      ..write(
        '<fonts count="1"><font><sz val="11"/><name val="Calibri"/></font></fonts>',
      )
      ..write(
        '<fills count="2"><fill><patternFill patternType="none"/></fill>'
        '<fill><patternFill patternType="gray125"/></fill></fills>',
      )
      ..write(
        '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/>'
        '</border></borders>',
      )
      ..write(
        '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" '
        'borderId="0"/></cellStyleXfs>',
      )
      ..write('<cellXfs count="${_xfFormatIds.length}">');
    for (final int id in _xfFormatIds) {
      b.write(
        '<xf numFmtId="$id" fontId="0" fillId="0" borderId="0" xfId="0"'
        '${id == 0 ? '' : ' applyNumberFormat="1"'}/>',
      );
    }
    b
      ..write('</cellXfs>')
      ..write(
        '<cellStyles count="1"><cellStyle name="Normal" xfId="0" '
        'builtinId="0"/></cellStyles>',
      )
      ..write('<dxfs count="0"/><tableStyles count="0"/></styleSheet>');
    return b.toString();
  }
}

Uint8List _build(OracleWorkbook book, List<OracleCase> cases) {
  final List<OracleCase> csv = <OracleCase>[
    for (final OracleCase c in cases)
      if (!c.eyeOnly) c,
  ];
  final List<OracleCase> eye = <OracleCase>[
    for (final OracleCase c in cases)
      if (c.eyeOnly) c,
  ];
  final List<_Sheet> sheets = <_Sheet>[
    if (csv.isNotEmpty) _Sheet('cases', csv, 50),
    if (eye.isNotEmpty) _Sheet('eye', eye, null),
  ];
  final _Styles styles = _Styles(book);
  final List<String> sheetXml = <String>[
    for (final _Sheet sheet in sheets) _sheetXml(sheet, styles),
  ];

  final Archive archive = Archive();
  void add(String name, String text) =>
      archive.add(ArchiveFile.bytes(name, utf8.encode(text)));
  add('[Content_Types].xml', _contentTypes(sheets.length));
  add('_rels/.rels', _rootRels);
  add('xl/workbook.xml', _workbookXml(book, sheets));
  add('xl/_rels/workbook.xml.rels', _workbookRels(sheets.length));
  add('xl/styles.xml', styles.toXml());
  for (int i = 0; i < sheets.length; i++) {
    add('xl/worksheets/sheet${i + 1}.xml', sheetXml[i]);
  }
  return Uint8List.fromList(
    ZipEncoder().encodeBytes(archive, modified: DateTime.utc(2020)),
  );
}

String _contentTypes(int sheetCount) {
  const String sheetType =
      'application/vnd.openxmlformats-officedocument.spreadsheetml';
  return '$_xmlDecl<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/xl/workbook.xml" ContentType="$sheetType.sheet.main+xml"/>'
      '<Override PartName="/xl/styles.xml" ContentType="$sheetType.styles+xml"/>'
      '${<String>[for (int i = 1; i <= sheetCount; i++) '<Override PartName="/xl/worksheets/sheet$i.xml" ContentType="$sheetType.worksheet+xml"/>'].join()}'
      '</Types>';
}

const String _rootRels =
    '$_xmlDecl<Relationships xmlns="$_pkgRelNs">'
    '<Relationship Id="rId1" Type="$_relNs/officeDocument" Target="xl/workbook.xml"/>'
    '</Relationships>';

String _workbookXml(OracleWorkbook book, List<_Sheet> sheets) =>
    '$_xmlDecl<workbook xmlns="$_mainNs" xmlns:r="$_relNs">'
    '${book.date1904 ? '<workbookPr date1904="1"/>' : ''}'
    '<bookViews><workbookView activeTab="0"/></bookViews><sheets>'
    '${<String>[for (int i = 0; i < sheets.length; i++) '<sheet name="${_attribute(sheets[i].name)}" sheetId="${i + 1}" r:id="rId${i + 1}"/>'].join()}'
    '</sheets></workbook>';

String _workbookRels(int sheetCount) =>
    '$_xmlDecl<Relationships xmlns="$_pkgRelNs">'
    '${<String>[for (int i = 1; i <= sheetCount; i++) '<Relationship Id="rId$i" Type="$_relNs/worksheet" Target="worksheets/sheet$i.xml"/>'].join()}'
    '<Relationship Id="rId${sheetCount + 1}" Type="$_relNs/styles" Target="styles.xml"/>'
    '</Relationships>';

/// The sheet part of [sheet]: a header row, then a row per case with the
/// value in column A in the case's format, the code as text in column B, the
/// case id in column C and the note in column D.
String _sheetXml(_Sheet sheet, _Styles styles) {
  final int? valueWidth = sheet.valueWidth;
  final StringBuffer b = StringBuffer(_xmlDecl)
    ..write('<worksheet xmlns="$_mainNs" xmlns:r="$_relNs">')
    ..write('<sheetViews><sheetView workbookViewId="0"/></sheetViews><cols>');
  void col(int index, int width) => b.write(
    '<col min="$index" max="$index" width="$width" customWidth="1"/>',
  );
  if (valueWidth != null) col(1, valueWidth);
  col(2, 40);
  col(3, 12);
  col(4, 60);
  b.write('</cols><sheetData>');
  b.write('<row r="1">');
  for (int i = 0; i < _header.length; i++) {
    b.write(_textCell('${'ABCD'[i]}1', _header[i]));
  }
  b.write('</row>');
  for (int i = 0; i < sheet.cases.length; i++) {
    final OracleCase c = sheet.cases[i];
    final int r = i + 2;
    final int xf = styles.xfOf(c);
    final String style = xf == 0 ? '' : ' s="$xf"';
    final OracleValue value = c.value;
    final String a = switch (value) {
      OracleNumber(:final String digits) =>
        '<c r="A$r"$style><v>$digits</v></c>',
      OracleBool(value: final bool v) =>
        '<c r="A$r"$style t="b"><v>${v ? 1 : 0}</v></c>',
      OracleText(:final String text) => _textCell('A$r', text, style: style),
      // An empty cell keeps the case's format for what the owner types; with
      // the default format it would carry nothing, so it is left out.
      OracleManual() => xf == 0 ? '' : '<c r="A$r"$style/>',
    };
    final String note = value is OracleManual
        ? 'type ${value.formula} in A$r; ${c.note}'
        : c.note;
    b
      ..write('<row r="$r">')
      ..write(a)
      ..write(
        _textCell(
          'B$r',
          c.builtinId != null ? 'builtin ${c.builtinId}' : c.code!,
        ),
      )
      ..write(_textCell('C$r', c.id))
      ..write(_textCell('D$r', note))
      ..write('</row>');
  }
  b.write('</sheetData></worksheet>');
  return b.toString();
}

/// An inline string cell. `xml:space="preserve"` keeps leading and trailing
/// spaces. Throws a [FormatException] for a text over 32,767 characters.
String _textCell(String ref, String text, {String style = ''}) {
  if (text.length > _maxCellText) {
    throw FormatException(
      '$ref: the text has ${text.length} characters, Excel keeps '
      '$_maxCellText',
    );
  }
  return '<c r="$ref"$style t="inlineStr"><is>'
      '<t xml:space="preserve">${_text(text)}</t></is></c>';
}

/// XML 1.0 forbids U+0000 to U+001F except tab, LF and CR, U+FFFE, U+FFFF
/// and lone surrogates; the writer drops them, as jet_office's does.
String _scrub(String raw) {
  final StringBuffer b = StringBuffer();
  final int length = raw.length;
  for (int i = 0; i < length; i++) {
    final int unit = raw.codeUnitAt(i);
    final bool high = unit >= 0xD800 && unit <= 0xDBFF;
    final bool low = unit >= 0xDC00 && unit <= 0xDFFF;
    if (high && i + 1 < length) {
      final int next = raw.codeUnitAt(i + 1);
      if (next >= 0xDC00 && next <= 0xDFFF) {
        b
          ..writeCharCode(unit)
          ..writeCharCode(next);
        i++;
        continue;
      }
    }
    if (high ||
        low ||
        (unit < 0x20 && unit != 0x09 && unit != 0x0A && unit != 0x0D) ||
        unit == 0xFFFE ||
        unit == 0xFFFF) {
      continue;
    }
    b.writeCharCode(unit);
  }
  return b.toString();
}

/// [text] as XML character data: scrubbed, an `_` that starts an `_xHHHH_`
/// sequence written as `_x005F_` so a reader shows the text as given, `&`,
/// `<`, `>` escaped and CR as `&#13;`.
String _text(String text) => _scrub(text)
    .replaceAll(RegExp(r'_(?=x[0-9A-Fa-f]{4}_)'), '_x005F_')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('\r', '&#13;');

/// [text] as a double-quoted XML attribute value.
String _attribute(String text) => _scrub(text)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll('\t', '&#9;')
    .replaceAll('\n', '&#10;')
    .replaceAll('\r', '&#13;');
