/// Reads the number formats and cell formats of an XLSX styles part.
///
/// Ported from quds_office_engine `lib/src/sheet/styles/sml_styles.dart` at
/// commit 15c5d29: `SmlStyleSheet.parse`, the `numFmt` and `cellXfs` read
/// side only. Fonts, fills, alignment and theme colors are not ported.
///
/// What changed: the `int.parse` that threw on a bad `numFmtId` is replaced
/// by checks (a bad `<numFmt>` is ignored, a bad `<xf>` is a broken format);
/// the hard-coded built-in `164` (a currency code that Excel never fixes) is
/// dropped, so an id without a `<numFmt>` has a code only when it is a
/// built-in of `builtinNumberFormatCode` (`format/builtin_formats.dart`);
/// locale-dependent ids are left unresolved; each format has a kind
/// (`classifyFormatCode`) and one shared [CellFormat] per id; `<numFmt>` and `<xf>` are matched by depth, local
/// name and SpreadsheetML namespace under `<numFmts>` and `<cellXfs>`
/// (Quds also counted `<xf>` of other parents); the root must be a
/// `<styleSheet>`; and the number of formats and the length of a code are
/// limited.
library;

import '../../opc/ooxml.dart';
import '../../xml/xml_escape.dart';
import '../../xml/xml_pull_reader.dart';
import '../format/builtin_formats.dart';
import '../format/format_kind.dart';
import 'package_reader.dart';
import 'read_exception.dart';
import 'read_limits.dart';

/// A number format as a cell's style gives it.
final class CellFormat {
  /// Creates a format.
  const CellFormat(this.id, this.code, this.kind, {this.invalid = false});

  /// The `General` format.
  static const CellFormat general = CellFormat(0, 'General', FormatKind.number);

  /// The format of a style index that points nowhere, or at an `<xf>` with
  /// an unreadable `numFmtId`. It shows like `General` but is [invalid].
  static const CellFormat broken = CellFormat(
    0,
    'General',
    FormatKind.number,
    invalid: true,
  );

  /// The number format id (`numFmtId`).
  final int id;

  /// The format code, or `null` for an id that is neither in the file nor a
  /// built-in with a fixed code (a locale-dependent one).
  final String? code;

  /// What the format makes a value show; [FormatKind.number] when [code] is
  /// `null`.
  final FormatKind kind;

  /// Whether the style index was bad and this stands in for it.
  final bool invalid;
}

/// The cell formats of a styles part, by style index (`s` of a `<c>`).
final class StyleTable {
  StyleTable._(this._formats);

  /// The table of a workbook without a styles part.
  static final StyleTable empty = StyleTable._(const <CellFormat>[]);

  final List<CellFormat> _formats;

  /// The format of the style index [s], the raw `s` attribute of a cell.
  ///
  /// `null` is [CellFormat.general]. An [s] that is not a non-negative
  /// integer of at most 9 digits, or is past the table, is
  /// [CellFormat.broken]; the exception is `'0'` on an empty table, which is
  /// [CellFormat.general] (a workbook may omit its styles part).
  CellFormat formatOf(String? s) {
    if (s == null) return CellFormat.general;
    if (s.isEmpty || s.length > 9 || !_digits.hasMatch(s)) {
      return CellFormat.broken;
    }
    final int index = int.parse(s);
    if (index < _formats.length) return _formats[index];
    return index == 0 && _formats.isEmpty
        ? CellFormat.general
        : CellFormat.broken;
  }
}

final RegExp _digits = RegExp(r'^[0-9]+$');

/// Reads the styles of [part] in [package].
///
/// `<numFmt>` entries are read from `<numFmts>` and `<xf>` entries from
/// `<cellXfs>` (never `<cellStyleXfs>`), both children of the root
/// `<styleSheet>`; other elements and elements of other namespaces are
/// skipped with their contents. A `<numFmt>` whose `numFmtId` is not a
/// non-negative integer, or that has no `formatCode`, is ignored; of two
/// with the same id the later wins. An `<xf>` without `numFmtId` has id 0;
/// with an unreadable one it is [CellFormat.broken]. The code of an id is
/// the file's `<numFmt>`, else the built-in's, else `null`. Every `<xf>`
/// with the same id shares one [CellFormat]. Only the first `<numFmts>` and
/// the first `<cellXfs>` of the part are read, so the limit holds for the
/// whole part and style indexes cannot shift; a repeated group is skipped
/// unread, and cells pointing past the first table are
/// [CellFormat.broken]. An id of more than 9 digits (after leading zeros)
/// is not an id, whatever the platform. A root that is not a
/// `<styleSheet>` gives [StyleTable.empty].
///
/// Throws an [XlsxReadException] of reason `unsupportedFormat` for a root in
/// the Strict namespace, `limitExceeded` when more than
/// [XlsxReadLimits.maxCellFormats] `<numFmt>` or `<xf>` entries are listed
/// or a `formatCode` is longer than [XlsxReadLimits.maxTextLength]
/// characters after decoding, and `malformedXml` when the XML cannot be
/// read.
StyleTable readStyles(
  PackageReader package,
  String part,
  XlsxReadLimits limits,
) {
  return package.guardXml(part, () {
    final XmlPullReader reader = package.openXml(part);
    while (reader.next()) {
      if (reader.eventType == XmlEventType.startElement) break;
    }
    if (reader.eventType != XmlEventType.startElement) return StyleTable.empty;
    if (reader.namespaceUri == strictSpreadsheetNs) {
      throw strictUnsupported(part: part);
    }
    if (reader.localName != 'styleSheet' || reader.namespaceUri != Ns.main) {
      return StyleTable.empty;
    }
    final Map<int, String> codes = <int, String>{};
    final List<int?> xfIds = <int?>[];
    var sawNumFmts = false;
    var sawCellXfs = false;
    while (reader.next()) {
      if (reader.eventType != XmlEventType.startElement) continue;
      if (reader.depth != 2 || reader.namespaceUri != Ns.main) {
        reader.skip();
      } else if (reader.localName == 'numFmts' && !sawNumFmts) {
        sawNumFmts = true;
        _readGroup(reader, part, limits, 'numFmt', () {
          _readNumFmt(reader, part, limits, codes);
        });
      } else if (reader.localName == 'cellXfs' && !sawCellXfs) {
        sawCellXfs = true;
        _readGroup(reader, part, limits, 'xf', () {
          xfIds.add(_readId(reader.getAttribute('numFmtId'), orElse: 0));
          reader.skip();
        });
      } else {
        reader.skip();
      }
    }
    final Map<int, CellFormat> shared = <int, CellFormat>{};
    final List<CellFormat> formats = <CellFormat>[
      for (final int? id in xfIds)
        if (id == null)
          CellFormat.broken
        else
          shared.putIfAbsent(id, () {
            final String? code = codes[id] ?? builtinNumberFormatCode(id);
            return CellFormat(
              id,
              code,
              code == null ? FormatKind.number : classifyFormatCode(code),
            );
          }),
    ];
    return StyleTable._(List<CellFormat>.unmodifiable(formats));
  });
}

/// Calls [onItem] for each [name] child of the group element the reader is
/// on, counting them against [XlsxReadLimits.maxCellFormats], and leaves the
/// reader on the group's end. [onItem] must leave the reader on its
/// element's start or end.
void _readGroup(
  XmlPullReader reader,
  String part,
  XlsxReadLimits limits,
  String name,
  void Function() onItem,
) {
  if (reader.isEmptyElement) return;
  final int groupDepth = reader.depth;
  int count = 0;
  while (reader.next()) {
    if (reader.eventType == XmlEventType.endElement &&
        reader.depth < groupDepth) {
      return;
    }
    if (reader.eventType != XmlEventType.startElement) continue;
    if (reader.depth == groupDepth + 1 &&
        reader.localName == name &&
        reader.namespaceUri == Ns.main) {
      if (count >= limits.maxCellFormats) {
        throw XlsxReadException(
          XlsxReadFailure.limitExceeded,
          'Limit maxCellFormats (${limits.maxCellFormats}) exceeded.',
          part: part,
        );
      }
      onItem();
      count++;
    } else {
      reader.skip();
    }
  }
}

/// Records the `<numFmt>` the reader is on in [codes], when it has a usable
/// id and a `formatCode`, and leaves the reader on its end.
void _readNumFmt(
  XmlPullReader reader,
  String part,
  XlsxReadLimits limits,
  Map<int, String> codes,
) {
  final int? id = _readId(reader.getAttribute('numFmtId'));
  final String? raw = reader.getAttribute('formatCode');
  reader.skip();
  if (id == null || raw == null) return;
  final String code = decodeXstring(raw);
  if (code.length > limits.maxTextLength) {
    throw XlsxReadException(
      XlsxReadFailure.limitExceeded,
      'Limit maxTextLength (${limits.maxTextLength}) exceeded by the '
      'format code of number format $id.',
      part: part,
    );
  }
  codes[id] = code;
}

/// [value] as a non-negative integer; [orElse] when it is absent, `null`
/// when it is present and not one.
int? _readId(String? value, {int? orElse}) {
  if (value == null) return orElse;
  if (!_digits.hasMatch(value)) return null;
  final String significant = value.replaceFirst(RegExp('^0+'), '');
  return significant.length > 9 ? null : int.parse('0$significant');
}
