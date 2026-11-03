/// Collects the styles of a workbook and writes `xl/styles.xml`.
///
/// Ported from quds_office_engine `lib/src/builders/xlsx_io.dart` at commit 15c5d29.
/// Ported: `style` with the `_Font`, `_Fill` and `_Xf` dedupe, `_numFmtId`
/// and `_stylesXml`. What changed: a style is a value object with the full
/// SpreadsheetML vocabulary (fonts, pattern and gradient fills, borders,
/// alignment, protection) instead of loose parameters; fonts, fills, borders
/// and cell formats are deduplicated by their rendered XML, so styles that
/// look the same share one entry however they are spelled; every part is
/// validated, and registration is atomic; the font, custom number format and
/// cell format limits are enforced; custom codes are scrubbed; everything is
/// written through `XmlWriter`.
library;

import '../xml/xml_escape.dart';
import '../xml/xml_writer.dart';
import 'alignment.dart';
import 'border.dart';
import 'differential_style.dart';
import 'fill.dart';
import 'font.dart';
import 'format/builtin_formats.dart';
import 'limits.dart';
import 'number_format.dart';
import 'style.dart';

const String _mainNamespace =
    'http://schemas.openxmlformats.org/spreadsheetml/2006/main';

/// One cell format (`<xf>` of `cellXfs`): the ids of its parts and the
/// rendered `<alignment>` and `<protection>`, or null when they are Excel's
/// defaults. Records compare by value, so this is also the dedupe key.
typedef _Xf = ({
  int numFmtId,
  int fontId,
  int fillId,
  int borderId,
  String? alignment,
  String? protection,
});

const _Xf _defaultXf = (
  numFmtId: 0,
  fontId: 0,
  fillId: 0,
  borderId: 0,
  alignment: null,
  protection: null,
);

/// What a file's `styles.xml` already holds, for [StyleRegistry.seeded].
///
/// The registry keeps the file's entries at their indexes, so a new style
/// that looks like one of them reuses its id, and the entries it appends
/// come after them (read them back with the registry's `…From` methods).
///
/// An entry of [fonts], [fills] or [borders] is identified by its `key`: the
/// XML the registry itself renders for the value read from the file, which
/// is what the registry dedupes by. Build one with [StyleRegistry.fontKey],
/// [StyleRegistry.fillKey] or [StyleRegistry.borderKey] from the value that
/// was read, and only when that value is exact (nothing of the entry was
/// lost reading it); otherwise the key is `null`. A `null` key keeps the
/// entry's index and its place toward the limits, but it never matches a
/// new style.
///
/// [xfs] are the file's `cellXfs`, with the already rendered `alignment`
/// and `protection` (see `alignmentXml` and `protectionXml`) or `null` for
/// Excel's defaults. An xf whose `exact` is false is kept and counted but
/// never matches a new style. [customCodes] maps each `numFmt` id of the
/// file to its code; the registry numbers new codes from
/// `max(164, highest id + 1)`.
final class StyleSeed {
  /// Creates a seed. [fonts], [fills], [borders] and [xfs] must not be
  /// empty: id 0 of each must exist.
  const StyleSeed({
    required this.fonts,
    required this.fills,
    required this.borders,
    required this.xfs,
    this.customCodes = const <int, String>{},
  });

  /// The file's fonts, in order; see the class comment for `key`.
  final List<({String? key})> fonts;

  /// The file's fills, in order.
  final List<({String? key})> fills;

  /// The file's borders, in order.
  final List<({String? key})> borders;

  /// The file's `numFmt` ids and codes.
  final Map<int, String> customCodes;

  /// The file's cell formats, in order.
  final List<
    ({
      int numFmtId,
      int fontId,
      int fillId,
      int borderId,
      String? alignment,
      String? protection,
      bool exact,
    })
  >
  xfs;
}

String _render(void Function(XmlWriter w) write) {
  final StringBuffer out = StringBuffer();
  write(XmlWriter(out));
  return out.toString();
}

/// Hands out cell format ids (`s` attribute values) for styles and writes
/// the `styles.xml` part.
///
/// Id 0 is the default style: General, Calibri 11, no fill, no border.
/// Fonts, fills and borders are deduplicated by the XML they write, and cell
/// formats by their parts, so styles that look the same share one id however
/// they are spelled. Fill 0 is `none` and fill 1 is `gray125`, as Excel
/// requires. Custom number format codes are numbered from 164 and
/// deduplicated by code. Differential styles ([dxfIdFor]) are deduplicated
/// by their rendered XML and share the number format table.
final class StyleRegistry {
  /// Creates a registry holding only the default style.
  StyleRegistry() : _seedNextId = _firstCustomId {
    _addPart(
      _fonts,
      _fontIds,
      _render((XmlWriter w) {
        writeFontXml(w, resolveFont(null));
      }),
    );
    _addPart(_fills, _fillIds, _fillXml(_noFill));
    _addPart(_fills, _fillIds, _fillXml(_gray125));
    _addPart(_borders, _borderIds, _borderXml(const XlsxBorder()));
  }

  /// Creates a registry that holds [seed]'s entries at their indexes.
  ///
  /// New styles reuse a seeded entry whose key or parts they match and
  /// otherwise append after it. The limits count the seed's entries.
  /// Throws [ArgumentError] when a list of [seed] other than its custom
  /// codes is empty, and [XlsxLimitError] when it holds more fonts, custom
  /// codes or cell formats than the limits allow.
  StyleRegistry.seeded(StyleSeed seed)
    : _seedNextId = _nextIdAfter(seed.customCodes) {
    for (final (String name, int length) in <(String, int)>[
      ('fonts', seed.fonts.length),
      ('fills', seed.fills.length),
      ('borders', seed.borders.length),
      ('xfs', seed.xfs.length),
    ]) {
      if (length == 0) {
        throw ArgumentError.value(length, name, 'A seed needs an entry 0.');
      }
    }
    if (seed.fonts.length > XlsxLimits.maxFonts) {
      throw XlsxLimitError('fonts', XlsxLimits.maxFonts);
    }
    if (seed.customCodes.length > XlsxLimits.maxNumberFormats) {
      throw XlsxLimitError('number formats', XlsxLimits.maxNumberFormats);
    }
    if (seed.xfs.length > XlsxLimits.maxCellFormats) {
      throw XlsxLimitError('cell formats', XlsxLimits.maxCellFormats);
    }
    void seedParts(
      List<String> parts,
      Map<String, int> ids,
      List<({String? key})> entries,
    ) {
      for (final ({String? key}) entry in entries) {
        final String? key = entry.key;
        // An inexact entry holds a placeholder and no key to match.
        if (key != null) ids.putIfAbsent(key, () => parts.length);
        parts.add(key ?? '');
      }
    }

    seedParts(_fonts, _fontIds, seed.fonts);
    seedParts(_fills, _fillIds, seed.fills);
    seedParts(_borders, _borderIds, seed.borders);
    seed.customCodes.forEach((int id, String code) {
      _customCodes.add((id: id, code: code));
      _customIds.putIfAbsent(code, () => id);
    });
    _xfs.clear();
    _xfIds.clear();
    for (final xf in seed.xfs) {
      final _Xf value = (
        numFmtId: xf.numFmtId,
        fontId: xf.fontId,
        fillId: xf.fillId,
        borderId: xf.borderId,
        alignment: xf.alignment,
        protection: xf.protection,
      );
      if (xf.exact) _xfIds.putIfAbsent(value, () => _xfs.length);
      _xfs.add(value);
    }
    _seedCodeCount = _customCodes.length;
  }

  static const int _firstCustomId = 164;

  static int _nextIdAfter(Map<int, String> codes) {
    int next = _firstCustomId;
    for (final int id in codes.keys) {
      if (id >= next) next = id + 1;
    }
    return next;
  }

  /// The key of [font] as the registry dedupes fonts: the `<font>` XML of
  /// [resolveFont] of it. Use it for a [StyleSeed] font read exactly.
  static String fontKey(XlsxFont? font) =>
      _render((XmlWriter w) => writeFontXml(w, resolveFont(font)));

  /// The key of [fill] as the registry dedupes fills: its `<fill>` XML.
  static String fillKey(XlsxFill fill) => _fillXml(fill);

  /// The key of [border] as the registry dedupes borders: its `<border>`
  /// XML.
  static String borderKey(XlsxBorder border) => _borderXml(border);

  /// The first id a new custom number format takes.
  final int _seedNextId;

  /// How many of [_customCodes] came from a seed.
  int _seedCodeCount = 0;

  int get _nextCodeId => _seedNextId + (_customCodes.length - _seedCodeCount);

  /// The number of fonts, the seed's included.
  int get fontCount => _fonts.length;

  /// The number of fills, the seed's included.
  int get fillCount => _fills.length;

  /// The number of borders, the seed's included.
  int get borderCount => _borders.length;

  /// The number of cell formats, the seed's included.
  int get xfCount => _xfs.length;

  /// The rendered `<font>` of every font from index [start] on.
  /// A seeded inexact entry renders as an empty string: it was never
  /// rendered, and a caller appends only what comes after the seed.
  List<String> fontsFrom(int start) => _fonts.sublist(start);

  /// The rendered `<fill>` of every fill from index [start] on.
  List<String> fillsFrom(int start) => _fills.sublist(start);

  /// The rendered `<border>` of every border from index [start] on.
  List<String> bordersFrom(int start) => _borders.sublist(start);

  /// The rendered `<xf>` of every cell format from index [start] on.
  List<String> xfsFrom(int start) => <String>[
    for (final _Xf xf in _xfs.sublist(start))
      _render((XmlWriter w) => _writeXf(w, xf)),
  ];

  /// The custom number formats from index [start] of the code list on (the
  /// seed's codes come first, in the order of its map).
  List<({int id, String code})> customCodesFrom(int start) =>
      _customCodes.sublist(start);

  /// Drops everything registered after the given counts (each a value read
  /// from the matching getter earlier), and the styles that mapped to it.
  /// A caller rolls back a failed edit this way.
  void truncate({
    required int fonts,
    required int fills,
    required int borders,
    required int codes,
    required int xfs,
  }) {
    _truncate(_fonts, _fontIds, fonts);
    _truncate(_fills, _fillIds, fills);
    _truncate(_borders, _borderIds, borders);
    _truncateCodes(codes);
    _truncate(_xfs, _xfIds, xfs);
    _ids.removeWhere((XlsxStyle _, int id) => id >= xfs);
  }

  void _truncateCodes(int length) {
    for (final ({int id, String code}) entry in _customCodes.sublist(length)) {
      if (_customIds[entry.code] == entry.id) _customIds.remove(entry.code);
    }
    _customCodes.removeRange(length, _customCodes.length);
  }

  static const XlsxFill _noFill = XlsxFill.pattern(XlsxPatternType.none);
  static const XlsxFill _gray125 = XlsxFill.pattern(XlsxPatternType.gray125);

  final Map<XlsxStyle, int> _ids = <XlsxStyle, int>{const XlsxStyle(): 0};
  final List<_Xf> _xfs = <_Xf>[_defaultXf];
  final Map<_Xf, int> _xfIds = <_Xf, int>{_defaultXf: 0};
  final List<String> _fonts = <String>[];
  final Map<String, int> _fontIds = <String, int>{};
  final List<String> _fills = <String>[];
  final Map<String, int> _fillIds = <String, int>{};
  final List<String> _borders = <String>[];
  final Map<String, int> _borderIds = <String, int>{};
  final List<({int id, String code})> _customCodes =
      <({int id, String code})>[];
  final Map<String, int> _customIds = <String, int>{};
  final List<String> _dxfs = <String>[];
  final Map<String, int> _dxfIds = <String, int>{};

  static void _addPart(List<String> parts, Map<String, int> ids, String xml) {
    ids[xml] = parts.length;
    parts.add(xml);
  }

  static String _fillXml(XlsxFill fill) =>
      _render((XmlWriter w) => writeFillXml(w, fill));

  static String _borderXml(XlsxBorder border) =>
      _render((XmlWriter w) => writeBorderXml(w, border));

  /// The id of [style], registering it on first use. `null` and every style
  /// that looks like the default give 0.
  ///
  /// Throws [ArgumentError] naming the field for an invalid part: a
  /// built-in number format id outside `0..163`, a custom code that is
  /// empty or holds characters XML cannot carry, or a font, fill, border or
  /// alignment that fails its checks (named `<part>.<field>`, such as
  /// `font.name` or `border.left`). Throws [XlsxLimitError] when the
  /// workbook would hold more than [XlsxLimits.maxFonts] fonts, more than
  /// [XlsxLimits.maxNumberFormats] custom number format codes or more than
  /// [XlsxLimits.maxCellFormats] cell formats (the defaults count as one
  /// each). Everything is checked before anything is recorded, so a throw
  /// registers nothing.
  int idFor(XlsxStyle? style) {
    if (style == null) return 0;
    final int? known = _ids[style];
    if (known != null) return known;

    // Validate and render every part before anything is recorded.
    final XlsxNumFmt? fmt = style.numFmt;
    if (fmt != null) _validateNumFmt(fmt);
    final String? fontXml = _fontXmlOf(style.font);
    final String? fillXml = _fillXmlOf(style.fill);
    final XlsxBorder? border = style.border;
    if (border != null) checkStylePart('border', () => validateBorder(border));
    final String? borderXml = border == null ? null : _borderXml(border);
    final XlsxAlignment? alignment = style.alignment;
    if (alignment != null) {
      checkStylePart('alignment', () => validateAlignment(alignment));
    }

    final int? fontId = fontXml == null ? 0 : _fontIds[fontXml];
    final int? fillId = fillXml == null ? 0 : _fillIds[fillXml];
    final int? borderId = borderXml == null ? 0 : _borderIds[borderXml];
    final String? code = fmt?.code;
    final bool newCode = code != null && !_customIds.containsKey(code);
    final _Xf xf = (
      numFmtId: fmt == null
          ? 0
          : fmt.builtinId ?? _customIds[code] ?? _nextCodeId,
      fontId: fontId ?? _fonts.length,
      fillId: fillId ?? _fills.length,
      borderId: borderId ?? _borders.length,
      alignment: alignmentXml(alignment),
      protection: protectionXml(style.protection),
    );
    final int? existing = _xfIds[xf];
    if (existing != null) {
      _ids[style] = existing;
      return existing;
    }

    if (fontId == null && _fonts.length >= XlsxLimits.maxFonts) {
      throw XlsxLimitError('fonts', XlsxLimits.maxFonts);
    }
    if (newCode && _customCodes.length >= XlsxLimits.maxNumberFormats) {
      throw XlsxLimitError('number formats', XlsxLimits.maxNumberFormats);
    }
    if (_xfs.length >= XlsxLimits.maxCellFormats) {
      throw XlsxLimitError('cell formats', XlsxLimits.maxCellFormats);
    }

    // Nothing below throws.
    if (fontId == null) _addPart(_fonts, _fontIds, fontXml!);
    if (fillId == null) _addPart(_fills, _fillIds, fillXml!);
    if (borderId == null) _addPart(_borders, _borderIds, borderXml!);
    if (newCode) {
      _customIds[code] = _nextCodeId;
      _customCodes.add((id: _nextCodeId, code: code));
    }
    final int id = _xfs.length;
    _xfs.add(xf);
    _xfIds[xf] = id;
    _ids[style] = id;
    return id;
  }

  /// The ids of [styles], in order, each as [idFor] gives it.
  ///
  /// All or nothing: when one style throws (for the reasons [idFor] lists),
  /// the styles before it are unregistered again, so the registry is as it
  /// was before the call. A column list registers its styles this way.
  ///
  /// With [fieldName], an [ArgumentError] from `styles[i]` is rethrown named
  /// `${fieldName(i)}.<field>`, such as `columns[2].style.numFmt`, or
  /// `fieldName(i)` when it names no field, with its value, message and
  /// stack kept, so the caller can say which entry was invalid; other
  /// errors pass through unchanged.
  List<int> idsFor(
    List<XlsxStyle?> styles, {
    String Function(int index)? fieldName,
  }) {
    final int fonts = _fonts.length;
    final int fills = _fills.length;
    final int borders = _borders.length;
    final int codes = _customCodes.length;
    final int xfs = _xfs.length;
    final List<int> ids = <int>[];
    try {
      for (final XlsxStyle? style in styles) {
        ids.add(idFor(style));
      }
    } on Object catch (error, stack) {
      truncate(
        fonts: fonts,
        fills: fills,
        borders: borders,
        codes: codes,
        xfs: xfs,
      );
      if (fieldName != null && error is ArgumentError) {
        // ids holds one entry per style before the failing one.
        final String entry = fieldName(ids.length);
        final String? field = error.name;
        Error.throwWithStackTrace(
          ArgumentError.value(
            error.invalidValue,
            field == null ? entry : '$entry.$field',
            error.message,
          ),
          stack,
        );
      }
      rethrow;
    }
    return ids;
  }

  /// The id of [style] as a differential style (`dxfId`), registering it on
  /// first use.
  ///
  /// A differential style writes only what [style] sets, so it is not
  /// resolved like a cell format; see [validateDifferentialStyle] for what
  /// it refuses. Its number format is numbered like a cell format's, from the
  /// same table, and counts toward [XlsxLimits.maxNumberFormats]. Styles
  /// that render the same share an id.
  ///
  /// Throws [ArgumentError] naming the field for a style that cannot be a
  /// differential style, for an invalid part, or for a built-in number
  /// format id without a known code; throws [XlsxLimitError] when the
  /// number format table is full. A throw registers nothing.
  int dxfIdFor(XlsxStyle style) {
    validateDifferentialStyle(style);
    final XlsxNumFmt? fmt = style.numFmt;
    String? newCode;
    DifferentialNumFmt? numFmt;
    if (fmt != null) {
      _validateNumFmt(fmt);
      final String? code = fmt.code;
      if (code == null) {
        final String? builtin = builtinNumberFormatCode(fmt.builtinId!);
        if (builtin == null) {
          throw ArgumentError.value(
            fmt.builtinId,
            'numFmt',
            'A differential style needs a built-in number format with a '
                'known code (ids 0-22 and 37-49).',
          );
        }
        numFmt = (id: fmt.builtinId!, code: builtin);
      } else {
        final int? known = _customIds[code];
        if (known == null) newCode = code;
        // A new code takes the next free id before the limit check below:
        // the dxf is rendered with its id, and the rendered XML is the
        // dedupe key. Nothing is recorded until that check passes, so a
        // full table throws without taking the id.
        numFmt = (id: known ?? _nextCodeId, code: code);
      }
    }
    final String xml = _render(
      (XmlWriter w) => writeDifferentialStyleXml(w, style, numFmt),
    );
    final int? existing = _dxfIds[xml];
    if (existing != null) return existing;
    if (newCode != null && _customCodes.length >= XlsxLimits.maxNumberFormats) {
      throw XlsxLimitError('number formats', XlsxLimits.maxNumberFormats);
    }

    // Nothing below throws.
    if (newCode != null) {
      _customIds[newCode] = _nextCodeId;
      _customCodes.add((id: _nextCodeId, code: newCode));
    }
    _addPart(_dxfs, _dxfIds, xml);
    return _dxfs.length - 1;
  }

  /// The differential style ids of [styles], in order, each as [dxfIdFor]
  /// gives it.
  ///
  /// All or nothing: when one style throws, the styles before it are
  /// unregistered again, with any number format code they added. A
  /// conditional format registers its rules' styles this way, after
  /// checking the rules, so a bad rule leaves no dxf behind.
  ///
  /// [fields], when given, names each style as the caller knows it (one per
  /// style): an [ArgumentError] of `styles[i]` naming a field, such as
  /// `numFmt`, is rethrown naming `${fields[i]}.numFmt`, with the same
  /// value, message and stack.
  List<int> dxfIdsFor(List<XlsxStyle> styles, {List<String>? fields}) {
    assert(fields == null || fields.length == styles.length);
    final int dxfs = _dxfs.length;
    final int codes = _customCodes.length;
    int i = 0;
    try {
      final List<int> ids = <int>[];
      for (; i < styles.length; i++) {
        ids.add(dxfIdFor(styles[i]));
      }
      return ids;
    } on Object catch (e, stack) {
      _truncate(_dxfs, _dxfIds, dxfs);
      _truncateCodes(codes);
      if (e is ArgumentError && fields != null) {
        Error.throwWithStackTrace(
          ArgumentError.value(
            e.invalidValue,
            '${fields[i]}.${e.name}',
            e.message,
          ),
          stack,
        );
      }
      rethrow;
    }
  }

  /// Drops the entries of [list] from index [length] on, and their [ids].
  static void _truncate<T>(List<T> list, Map<T, int> ids, int length) {
    list.sublist(length).forEach(ids.remove);
    list.removeRange(length, list.length);
  }

  /// The checked `<font>` of [font] after [resolveFont], or null for no
  /// font (the default font, id 0). An invalid font throws [ArgumentError]
  /// named `font.<field>`, such as `font.name`.
  static String? _fontXmlOf(XlsxFont? font) {
    if (font == null) return null;
    final XlsxFont resolved = resolveFont(font);
    checkStylePart('font', () => validateFont(resolved));
    return _render((XmlWriter w) => writeFontXml(w, resolved));
  }

  /// The checked `<fill>` of [fill], or null for fill 0: no fill. A `none`
  /// pattern, whose colors show nowhere, renders as the `none` fill. An
  /// invalid fill throws [ArgumentError] named `fill.<field>`, such as
  /// `fill.foreground`.
  static String? _fillXmlOf(XlsxFill? fill) {
    if (fill == null) return null;
    checkStylePart('fill', () => validateFill(fill));
    if (fill is XlsxPatternFill && fill.type == XlsxPatternType.none) {
      return _fillXml(_noFill);
    }
    return _fillXml(fill);
  }

  static void _validateNumFmt(XlsxNumFmt fmt) {
    final int? builtin = fmt.builtinId;
    if (builtin != null) {
      if (builtin < 0 || builtin > 163) {
        throw ArgumentError.value(
          builtin,
          'numFmt',
          'A built-in number format id must be in 0..163.',
        );
      }
      return;
    }
    final String code = fmt.code!;
    if (code.isEmpty) {
      throw ArgumentError.value(code, 'numFmt', 'A format code is empty.');
    }
    if (scrubXmlText(code).removed > 0) {
      throw ArgumentError.value(
        code,
        'numFmt',
        'A format code contains characters XML cannot carry.',
      );
    }
  }

  /// Writes the complete `styles.xml` document to [w], children in
  /// `CT_Stylesheet` order.
  void writeStylesXml(XmlWriter w) {
    w.declaration();
    w.start('styleSheet');
    w.attribute('xmlns', _mainNamespace);
    if (_customCodes.isNotEmpty) {
      w.start('numFmts');
      w.attribute('count', '${_customCodes.length}');
      for (final ({int id, String code}) entry in _customCodes) {
        w.empty('numFmt', <String, String>{
          'numFmtId': '${entry.id}',
          'formatCode': entry.code,
        });
      }
      w.end();
    }
    _writeTable(w, 'fonts', _fonts);
    _writeTable(w, 'fills', _fills);
    _writeTable(w, 'borders', _borders);
    w.raw(
      '<cellStyleXfs count="1">'
      '<xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>',
    );
    w.start('cellXfs');
    w.attribute('count', '${_xfs.length}');
    for (final _Xf xf in _xfs) {
      _writeXf(w, xf);
    }
    w.end();
    w.raw(
      '<cellStyles count="1">'
      '<cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>',
    );
    if (_dxfs.isEmpty) {
      w.raw('<dxfs count="0"/>');
    } else {
      _writeTable(w, 'dxfs', _dxfs);
    }
    w.raw('<tableStyles count="0"/>');
    w.end();
  }

  static void _writeTable(XmlWriter w, String name, List<String> parts) {
    w.start(name);
    w.attribute('count', '${parts.length}');
    parts.forEach(w.raw);
    w.end();
  }

  /// Writes [xf]. An `apply…` flag is written, as `1`, only for a part that
  /// differs from cell format 0.
  static void _writeXf(XmlWriter w, _Xf xf) {
    w.start('xf');
    w.attribute('numFmtId', '${xf.numFmtId}');
    w.attribute('fontId', '${xf.fontId}');
    w.attribute('fillId', '${xf.fillId}');
    w.attribute('borderId', '${xf.borderId}');
    w.attribute('xfId', '0');
    if (xf.numFmtId != 0) w.attribute('applyNumberFormat', '1');
    if (xf.fontId != 0) w.attribute('applyFont', '1');
    if (xf.fillId != 0) w.attribute('applyFill', '1');
    if (xf.borderId != 0) w.attribute('applyBorder', '1');
    final String? alignment = xf.alignment;
    final String? protection = xf.protection;
    if (alignment != null) w.attribute('applyAlignment', '1');
    if (protection != null) w.attribute('applyProtection', '1');
    if (alignment != null) w.raw(alignment);
    if (protection != null) w.raw(protection);
    w.end();
  }
}
