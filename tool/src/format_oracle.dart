/// The Excel oracle for the number format engine: its case list and the
/// workbooks `tool/write_format_oracle.dart` writes from it.
///
/// New in jet_office (milestone N3 of decision 0008). The case list is
/// `test/fixtures/owner/number_format/cases.json`; its format is described
/// in the README beside it and enforced by [parseOracleCases]. Each case is
/// one row of its workbook: the value in column A in the case's format, the
/// code as text in column B (`builtin <id>` for a built-in id), the case id
/// in column C and a note in column D. Cases Excel's CSV does not show as
/// the cell does ([OracleCase.eyeOnly]) go on a second sheet, `eye`, whose
/// column A keeps the default width; the rest go on the first sheet,
/// `cases`, the one Excel saves as CSV.
///
/// The library's writer has no 1904 date system and never writes a code for
/// a built-in id, so [buildOracleWorkbooks] adds both to the finished file:
/// `<workbookPr date1904="1"/>` in the workbook part and an
/// [OracleWorkbook.numFmts] entry per overridden id in the styles part.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/zip/archive_adapter.dart';

/// Where the committed case list lives, relative to the repository root.
const String oracleCasesPath = 'test/fixtures/owner/number_format/cases.json';

/// The highest number of the Unknowns list in `docs/number-format.md`.
const int _maxUnknown = 21;

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

  /// The digits, as `XlsxDecimal` accepts them.
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

/// A formula the owner types into column A by hand (`{"manual": "=..."}`),
/// for a value the writer cannot produce, such as a spill error.
final class OracleManual extends OracleValue {
  /// Creates a manual value.
  const OracleManual(this.formula);

  /// The formula in English, as the owner types it.
  final String formula;
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

  /// The number in the Unknowns list of `docs/number-format.md`, or `null`.
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
  if (raw is! Map<String, Object?> || raw.length != 1) {
    _fail(path, 'expected an object with one of n, b, s, manual');
  }
  final MapEntry<String, Object?> e = raw.entries.single;
  return switch (e) {
    MapEntry(key: 'n', value: final String d) when _digitsPattern.hasMatch(d) =>
      OracleNumber(d),
    MapEntry(key: 'b', value: final bool b) => OracleBool(b),
    MapEntry(key: 's', value: final String s) => OracleText(s),
    MapEntry(key: 'manual', value: final String f) when f.startsWith('=') =>
      OracleManual(f),
    _ => _fail(
      path,
      'expected n (decimal digits as a string), b (a boolean), s (a '
      'string) or manual (a formula starting with =)',
    ),
  };
}

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

Uint8List _build(OracleWorkbook book, List<OracleCase> cases) {
  final XlsxWriter writer = XlsxWriter();
  final List<OracleCase> csv = <OracleCase>[
    for (final OracleCase c in cases)
      if (!c.eyeOnly) c,
  ];
  final List<OracleCase> eye = <OracleCase>[
    for (final OracleCase c in cases)
      if (c.eyeOnly) c,
  ];
  if (csv.isNotEmpty) _sheet(writer, 'cases', csv, valueWidth: 50);
  if (eye.isNotEmpty) _sheet(writer, 'eye', eye, valueWidth: null);
  final Uint8List bytes = writer.close().bytes;
  return book.date1904 || book.numFmts.isNotEmpty ? _patch(bytes, book) : bytes;
}

/// Writes a sheet of [cases]. A `null` [valueWidth] keeps column A at the
/// default width, which `General` adapts to.
void _sheet(
  XlsxWriter writer,
  String name,
  List<OracleCase> cases, {
  required double? valueWidth,
}) {
  final XlsxSheetWriter sheet = writer.addSheet(name)
    ..columns(<XlsxColumn?>[
      if (valueWidth == null) null else XlsxColumn(width: valueWidth),
      const XlsxColumn(width: 40),
      const XlsxColumn(width: 12),
      const XlsxColumn(width: 60),
    ])
    ..row(_header);
  for (int i = 0; i < cases.length; i++) {
    final OracleCase c = cases[i];
    final XlsxNumFmt format = c.builtinId != null
        ? XlsxNumFmt.builtin(c.builtinId!)
        : c.code == 'General'
        ? XlsxNumFmt.general
        : XlsxNumFmt.custom(c.code!);
    final OracleValue value = c.value;
    final Object? shown = switch (value) {
      OracleNumber(:final String digits) => XlsxDecimal(digits),
      OracleBool(value: final bool b) => b,
      OracleText(:final String text) => text,
      OracleManual() => null,
    };
    final String note = value is OracleManual
        ? 'type ${value.formula} in A${i + 2}; ${c.note}'
        : c.note;
    sheet.row(<Object?>[
      XlsxCell(shown, style: XlsxStyle(numFmt: format)),
      c.builtinId != null ? 'builtin ${c.builtinId}' : c.code,
      c.id,
      note,
    ]);
  }
}

/// [bytes] with the 1904 date system and the built-in codes of [book].
Uint8List _patch(Uint8List bytes, OracleWorkbook book) {
  final Archive archive = ZipDecoder().decodeBytes(bytes);
  final ZipWriter zip = ZipWriter();
  for (final ArchiveFile file in archive.files) {
    if (!file.isFile) continue;
    List<int> content = file.content;
    if (file.name == 'xl/workbook.xml' && book.date1904) {
      content = utf8.encode(
        _insertBefore(
          utf8.decode(content),
          '<bookViews>',
          '<workbookPr date1904="1"/>',
        ),
      );
    } else if (file.name == 'xl/styles.xml' && book.numFmts.isNotEmpty) {
      content = utf8.encode(_withNumFmts(utf8.decode(content), book.numFmts));
    }
    zip.add(file.name, content);
  }
  return zip.close()!;
}

String _withNumFmts(String styles, Map<int, String> numFmts) {
  final String added = <String>[
    for (final MapEntry<int, String> e in numFmts.entries)
      '<numFmt numFmtId="${e.key}" formatCode="${_attribute(e.value)}"/>',
  ].join();
  final RegExpMatch? open = RegExp(
    r'<numFmts count="(\d+)">',
  ).firstMatch(styles);
  if (open == null) {
    final int at = styles.indexOf('>', styles.indexOf('<styleSheet')) + 1;
    return styles.replaceRange(
      at,
      at,
      '<numFmts count="${numFmts.length}">$added</numFmts>',
    );
  }
  final int count = int.parse(open[1]!) + numFmts.length;
  return styles.replaceRange(
    open.start,
    open.end,
    '<numFmts count="$count">$added',
  );
}

String _insertBefore(String text, String marker, String insert) {
  final int at = text.indexOf(marker);
  if (at < 0) throw StateError('No $marker in the workbook part.');
  return text.replaceRange(at, at, insert);
}

String _attribute(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
