/// The codecs of the properties of tables, rows and cells, and the schemas
/// that type them.
///
/// Not ported from Quds; written for jet_office.
///
/// [tablePropertiesSchema] types the table's `w:tblPr` (its style, width,
/// alignment, indent, borders, layout, cell margins and look),
/// [tableRowPropertiesSchema] the row's `w:trPr` (grid cells before and
/// after, `w:cantSplit`, height and header row) and
/// [tableCellPropertiesSchema] the cell's `w:tcPr` (width,
/// grid span, vertical merge, borders, shading, text direction and vertical
/// alignment). A child is typed under the rules of `property_codec.dart`;
/// every other child (`w:tblpPr`, `w:tcMar` and the like) is kept
/// as read.
///
/// The three elements with children (`w:tblBorders`, `w:tcBorders`,
/// `w:tblCellMar`) are typed only when every child is a side in `w:` that
/// occurs once, is one the model knows (`w:start` and `w:end` are not),
/// and parses, as for `w:pBdr`; a set writes the whole element anew.
library;

import '../opc/ooxml.dart' show Ns;
import '../xml/xml_writer.dart';
import 'model/formatting.dart';
import 'model/table_formatting.dart';
import 'paragraph_property_codecs.dart';
import 'properties.dart';
import 'property_codec.dart';
import 'run_property_codecs.dart';
import 'schema_order.dart';
import 'units.dart';
import 'value_codecs.dart';

bool _plain(PropertyElement e) => e.children.isEmpty && !e.hasText;

/// The codec of a width, `w:tblW` or `w:tcW`: the number `w:w` and its unit
/// `w:type`.
///
/// `auto` and `nil` hold no length, so their `w:w` is ignored when it is
/// a whole number or missing. A missing `w:type` is `dxa`. A `pct` number
/// must be whole, in fiftieths of a per cent; one with a `%` sign has no
/// view, nor has a number out of range.
final class TableWidthCodec extends PropertyCodec<DocxTableWidth> {
  /// The codec of the width element `w:<localName>`.
  const TableWidthCodec(super.localName);

  @override
  Set<String> get attributes => const <String>{'w', 'type'};

  @override
  DocxTableWidth? parse(PropertyElement e) {
    if (!_plain(e)) {
      return null;
    }
    final String? raw = e.w('w');
    switch (e.w('type')) {
      case 'auto':
        return raw == null || parseDecimal(raw, min: 0, max: maxTwips) != null
            ? const DocxTableWidth.auto()
            : null;
      case 'nil':
        return raw == null || parseDecimal(raw, min: 0, max: maxTwips) != null
            ? const DocxTableWidth.nil()
            : null;
      case null || 'dxa':
        final int? twips = parseDecimal(raw, min: 0, max: maxTwips);
        return twips == null ? null : DocxTableWidth.points(ptOfTwips(twips));
      case 'pct':
        final int? fiftieths = parseDecimal(
          raw,
          min: 0,
          max: maxTableWidthFiftieths,
        );
        return fiftieths == null
            ? null
            : DocxTableWidth.percent(fiftieths / 50);
      default:
        return null;
    }
  }

  @override
  void write(
    XmlWriter w,
    String prefix,
    DocxTableWidth value,
    PropertyElement? asRead,
  ) {
    w.start('$prefix:$localName');
    switch (value.kind) {
      case DocxTableWidthKind.auto:
        w.attribute('$prefix:w', '0');
        w.attribute('$prefix:type', 'auto');
      case DocxTableWidthKind.nil:
        w.attribute('$prefix:w', '0');
        w.attribute('$prefix:type', 'nil');
      case DocxTableWidthKind.points:
        w.attribute(
          '$prefix:w',
          '${twipsOf(value.widthPt!, 'widthPt', min: 0, max: maxTwips)}',
        );
        w.attribute('$prefix:type', 'dxa');
      case DocxTableWidthKind.percent:
        w.attribute('$prefix:w', '${(value.percent! * 50).round()}');
        w.attribute('$prefix:type', 'pct');
    }
    w.end();
  }
}

final Map<String, DocxTableLayout> _layouts = <String, DocxTableLayout>{
  for (final DocxTableLayout l in DocxTableLayout.values) l.name: l,
};

/// The codec of `w:tblLayout`, whose value is in `w:type`.
final class TableLayoutCodec extends PropertyCodec<DocxTableLayout> {
  /// The codec of `w:tblLayout`.
  const TableLayoutCodec() : super('tblLayout');

  @override
  Set<String> get attributes => const <String>{'type'};

  @override
  DocxTableLayout? parse(PropertyElement e) =>
      _plain(e) ? parseEnum(e.w('type'), _layouts) : null;

  @override
  void write(
    XmlWriter w,
    String prefix,
    DocxTableLayout value,
    PropertyElement? asRead,
  ) {
    w.start('$prefix:$localName');
    w.attribute('$prefix:type', value.name);
    w.end();
  }
}

final Map<String, DocxTableAlignment> _tableAlignments =
    <String, DocxTableAlignment>{
      for (final DocxTableAlignment a in DocxTableAlignment.values) a.name: a,
    };

/// The codec of a table's `w:jc`; `start`, `end` and every other spelling
/// have no view.
final class TableAlignmentCodec extends ValEnumCodec<DocxTableAlignment> {
  /// The codec of a table's `w:jc`.
  const TableAlignmentCodec() : super('jc');

  @override
  Map<String, DocxTableAlignment> get byXml => _tableAlignments;
}

/// The schema of a table's `w:tblBorders`: [tblBordersOrder], with a
/// [BorderCodec] for each side the model knows (not `start` and `end`).
const ContainerSchema tableBordersSchema = ContainerSchema(
  tblBordersOrder,
  codecs: <String, PropertyCodec<Object>>{
    'top': BorderCodec('top'),
    'left': BorderCodec('left'),
    'bottom': BorderCodec('bottom'),
    'right': BorderCodec('right'),
    'insideH': BorderCodec('insideH'),
    'insideV': BorderCodec('insideV'),
  },
);

/// The schema of a cell's `w:tcBorders`: [tcBordersOrder], with a
/// [BorderCodec] for each side and diagonal the model knows.
const ContainerSchema cellBordersSchema = ContainerSchema(
  tcBordersOrder,
  codecs: <String, PropertyCodec<Object>>{
    'top': BorderCodec('top'),
    'left': BorderCodec('left'),
    'bottom': BorderCodec('bottom'),
    'right': BorderCodec('right'),
    'insideH': BorderCodec('insideH'),
    'insideV': BorderCodec('insideV'),
    'tl2br': BorderCodec('tl2br'),
    'tr2bl': BorderCodec('tr2bl'),
  },
);

/// The codec of one side of `w:tblCellMar`: `w:w` in twips with
/// `w:type="dxa"` (or none).
final class TableMarginCodec extends PropertyCodec<double> {
  /// The codec of the side `w:<localName>`.
  const TableMarginCodec(super.localName);

  @override
  Set<String> get attributes => const <String>{'w', 'type'};

  @override
  double? parse(PropertyElement e) {
    final String? type = e.w('type');
    if (!_plain(e) || (type != null && type != 'dxa')) {
      return null;
    }
    final int? twips = parseDecimal(e.w('w'), min: 0, max: maxTwips);
    return twips == null ? null : ptOfTwips(twips);
  }

  @override
  void write(
    XmlWriter w,
    String prefix,
    double value,
    PropertyElement? asRead,
  ) {
    w.start('$prefix:$localName');
    w.attribute('$prefix:w', '${twipsOf(value, 'pt', min: 0, max: maxTwips)}');
    w.attribute('$prefix:type', 'dxa');
    w.end();
  }
}

/// The codec of `w:tblInd`, the indent of a table from the margin: `w:w` in
/// twips, from -1584 to 1584 points, with `w:type="dxa"` (or none).
///
/// An indent of another type (`auto`, `pct`, `nil`) has no view.
final class TableIndentCodec extends PropertyCodec<double> {
  /// The codec of `w:tblInd`.
  const TableIndentCodec() : super('tblInd');

  @override
  Set<String> get attributes => const <String>{'w', 'type'};

  @override
  double? parse(PropertyElement e) {
    final String? type = e.w('type');
    if (!_plain(e) || (type != null && type != 'dxa')) {
      return null;
    }
    final int? twips = parseDecimal(e.w('w'), min: -maxTwips, max: maxTwips);
    return twips == null ? null : ptOfTwips(twips);
  }

  @override
  void write(
    XmlWriter w,
    String prefix,
    double value,
    PropertyElement? asRead,
  ) {
    w.start('$prefix:$localName');
    w.attribute(
      '$prefix:w',
      '${twipsOf(value, 'indentationPt', min: -maxTwips, max: maxTwips)}',
    );
    w.attribute('$prefix:type', 'dxa');
    w.end();
  }
}

/// The schema of a table's `w:tblCellMar`: [tblCellMarOrder], with a
/// [TableMarginCodec] for each side the model knows (not `start` and `end`).
const ContainerSchema tableMarginsSchema = ContainerSchema(
  tblCellMarOrder,
  codecs: <String, PropertyCodec<Object>>{
    'top': TableMarginCodec('top'),
    'left': TableMarginCodec('left'),
    'bottom': TableMarginCodec('bottom'),
    'right': TableMarginCodec('right'),
  },
);

/// The sides of [e] by [schema], or `null` when [e] has text or an
/// attribute, or a child is not a side of the schema in `w:`, occurs twice,
/// or does not parse.
Map<String, Object>? _sidesOf(PropertyElement e, ContainerSchema schema) {
  if (e.hasText || e.wAttributeNames.isNotEmpty) {
    return null;
  }
  final Map<String, Object> sides = <String, Object>{};
  for (final PropertyElement child in e.children) {
    final PropertyCodec<Object>? codec = schema.codecs[child.localName];
    if (child.namespaceUri != Ns.w ||
        codec == null ||
        sides.containsKey(child.localName) ||
        !codec.attributes.containsAll(child.wAttributeNames)) {
      return null;
    }
    final Object? value = codec.parse(child);
    if (value == null) {
      return null;
    }
    sides[child.localName] = value;
  }
  return sides;
}

/// Writes `<prefix:localName>` with the [sides] by [schema], in order.
void _writeSides(
  XmlWriter w,
  String prefix,
  String localName,
  ContainerSchema schema,
  Map<String, Object?> sides,
) {
  w.start('$prefix:$localName');
  for (final String name in schema.order) {
    final Object? value = sides[name];
    if (value != null) {
      schema.codecs[name]!.write(w, prefix, value, null);
    }
  }
  w.end();
}

/// The codec of `w:tblBorders`: the sides of [DocxTableBorders].
final class TableBordersCodec extends PropertyCodec<DocxTableBorders> {
  /// The codec of `w:tblBorders`.
  const TableBordersCodec() : super('tblBorders');

  @override
  Set<String> get attributes => const <String>{};

  @override
  DocxTableBorders? parse(PropertyElement e) {
    final Map<String, Object>? s = _sidesOf(e, tableBordersSchema);
    if (s == null) {
      return null;
    }
    return DocxTableBorders(
      top: s['top'] as DocxBorder?,
      left: s['left'] as DocxBorder?,
      bottom: s['bottom'] as DocxBorder?,
      right: s['right'] as DocxBorder?,
      insideHorizontal: s['insideH'] as DocxBorder?,
      insideVertical: s['insideV'] as DocxBorder?,
    );
  }

  @override
  void write(
    XmlWriter w,
    String prefix,
    DocxTableBorders value,
    PropertyElement? asRead,
  ) => _writeSides(w, prefix, localName, tableBordersSchema, <String, Object?>{
    'top': value.top,
    'left': value.left,
    'bottom': value.bottom,
    'right': value.right,
    'insideH': value.insideHorizontal,
    'insideV': value.insideVertical,
  });
}

/// The codec of `w:tcBorders`: the sides and diagonals of
/// [DocxCellBorders].
final class CellBordersCodec extends PropertyCodec<DocxCellBorders> {
  /// The codec of `w:tcBorders`.
  const CellBordersCodec() : super('tcBorders');

  @override
  Set<String> get attributes => const <String>{};

  @override
  DocxCellBorders? parse(PropertyElement e) {
    final Map<String, Object>? s = _sidesOf(e, cellBordersSchema);
    if (s == null) {
      return null;
    }
    return DocxCellBorders(
      top: s['top'] as DocxBorder?,
      left: s['left'] as DocxBorder?,
      bottom: s['bottom'] as DocxBorder?,
      right: s['right'] as DocxBorder?,
      insideHorizontal: s['insideH'] as DocxBorder?,
      insideVertical: s['insideV'] as DocxBorder?,
      topLeftToBottomRight: s['tl2br'] as DocxBorder?,
      topRightToBottomLeft: s['tr2bl'] as DocxBorder?,
    );
  }

  @override
  void write(
    XmlWriter w,
    String prefix,
    DocxCellBorders value,
    PropertyElement? asRead,
  ) => _writeSides(w, prefix, localName, cellBordersSchema, <String, Object?>{
    'top': value.top,
    'left': value.left,
    'bottom': value.bottom,
    'right': value.right,
    'insideH': value.insideHorizontal,
    'insideV': value.insideVertical,
    'tl2br': value.topLeftToBottomRight,
    'tr2bl': value.topRightToBottomLeft,
  });
}

/// The codec of `w:tblCellMar`: the sides of [DocxTableMargins].
final class TableMarginsCodec extends PropertyCodec<DocxTableMargins> {
  /// The codec of `w:tblCellMar`.
  const TableMarginsCodec() : super('tblCellMar');

  @override
  Set<String> get attributes => const <String>{};

  @override
  DocxTableMargins? parse(PropertyElement e) {
    final Map<String, Object>? s = _sidesOf(e, tableMarginsSchema);
    if (s == null) {
      return null;
    }
    return DocxTableMargins(
      topPt: s['top'] as double?,
      leftPt: s['left'] as double?,
      bottomPt: s['bottom'] as double?,
      rightPt: s['right'] as double?,
    );
  }

  @override
  void write(
    XmlWriter w,
    String prefix,
    DocxTableMargins value,
    PropertyElement? asRead,
  ) => _writeSides(w, prefix, localName, tableMarginsSchema, <String, Object?>{
    'top': value.topPt,
    'left': value.leftPt,
    'bottom': value.bottomPt,
    'right': value.rightPt,
  });
}

/// The bit of each flag of `w:tblLook/@w:val`.
const int _firstRowBit = 0x20;
const int _lastRowBit = 0x40;
const int _firstColumnBit = 0x80;
const int _lastColumnBit = 0x100;
const int _noHBandBit = 0x200;
const int _noVBandBit = 0x400;
const int _knownBits =
    _firstRowBit |
    _lastRowBit |
    _firstColumnBit |
    _lastColumnBit |
    _noHBandBit |
    _noVBandBit;

final RegExp _hex4 = RegExp(r'^[0-9A-Fa-f]{4}$');

/// The codec of `w:tblLook`: the six flags, from the attributes
/// `w:firstRow`, `w:lastRow`, `w:firstColumn`, `w:lastColumn`, `w:noHBand`
/// and `w:noVBand` when the element has one, else from the bits of `w:val`.
///
/// `w:val` must be four hex digits when present and holds no bit but the
/// six flags'; an attribute that is not an on/off value has no view. The
/// writer writes `w:val` and the six attributes, as Word does.
final class TableLookCodec extends PropertyCodec<DocxTableLook> {
  /// The codec of `w:tblLook`.
  const TableLookCodec() : super('tblLook');

  static const List<String> _flagAttributes = <String>[
    'firstRow',
    'lastRow',
    'firstColumn',
    'lastColumn',
    'noHBand',
    'noVBand',
  ];

  @override
  Set<String> get attributes => const <String>{
    'val',
    'firstRow',
    'lastRow',
    'firstColumn',
    'lastColumn',
    'noHBand',
    'noVBand',
  };

  @override
  DocxTableLook? parse(PropertyElement e) {
    if (!_plain(e)) {
      return null;
    }
    final String? valRaw = e.w('val');
    int bits = 0;
    if (valRaw != null) {
      if (!_hex4.hasMatch(valRaw)) {
        return null;
      }
      bits = int.parse(valRaw, radix: 16);
      if (bits & ~_knownBits != 0) {
        return null;
      }
    }
    if (_flagAttributes.any((String a) => e.w(a) != null)) {
      bool? flag(String name) => parseOnOff(e.w(name) ?? 'false');
      final List<bool?> f = <bool?>[
        for (final String a in _flagAttributes) flag(a),
      ];
      if (f.contains(null)) {
        return null;
      }
      return DocxTableLook(
        firstRow: f[0]!,
        lastRow: f[1]!,
        firstColumn: f[2]!,
        lastColumn: f[3]!,
        noHorizontalBands: f[4]!,
        noVerticalBands: f[5]!,
      );
    }
    return DocxTableLook(
      firstRow: bits & _firstRowBit != 0,
      lastRow: bits & _lastRowBit != 0,
      firstColumn: bits & _firstColumnBit != 0,
      lastColumn: bits & _lastColumnBit != 0,
      noHorizontalBands: bits & _noHBandBit != 0,
      noVerticalBands: bits & _noVBandBit != 0,
    );
  }

  @override
  void write(
    XmlWriter w,
    String prefix,
    DocxTableLook value,
    PropertyElement? asRead,
  ) {
    final int bits =
        (value.firstRow ? _firstRowBit : 0) |
        (value.lastRow ? _lastRowBit : 0) |
        (value.firstColumn ? _firstColumnBit : 0) |
        (value.lastColumn ? _lastColumnBit : 0) |
        (value.noHorizontalBands ? _noHBandBit : 0) |
        (value.noVerticalBands ? _noVBandBit : 0);
    String flag(bool on) => on ? '1' : '0';
    w.start('$prefix:$localName');
    w.attribute(
      '$prefix:val',
      bits.toRadixString(16).toUpperCase().padLeft(4, '0'),
    );
    w.attribute('$prefix:firstRow', flag(value.firstRow));
    w.attribute('$prefix:lastRow', flag(value.lastRow));
    w.attribute('$prefix:firstColumn', flag(value.firstColumn));
    w.attribute('$prefix:lastColumn', flag(value.lastColumn));
    w.attribute('$prefix:noHBand', flag(value.noHorizontalBands));
    w.attribute('$prefix:noVBand', flag(value.noVerticalBands));
    w.end();
  }
}

/// The codec of `w:trHeight`: `w:val` in twips (required) and `w:hRule`.
///
/// A missing `w:hRule` and `auto` read as [DocxRowHeightRule.atLeast]; the
/// writer writes `atLeast` or `exact`.
final class RowHeightCodec extends PropertyCodec<DocxRowHeight> {
  /// The codec of `w:trHeight`.
  const RowHeightCodec() : super('trHeight');

  @override
  Set<String> get attributes => const <String>{'val', 'hRule'};

  @override
  DocxRowHeight? parse(PropertyElement e) {
    if (!_plain(e)) {
      return null;
    }
    final int? twips = parseDecimal(e.w('val'), min: 0, max: maxTwips);
    final DocxRowHeightRule? rule = switch (e.w('hRule')) {
      null || 'auto' || 'atLeast' => DocxRowHeightRule.atLeast,
      'exact' => DocxRowHeightRule.exact,
      _ => null,
    };
    if (twips == null || rule == null) {
      return null;
    }
    return DocxRowHeight(ptOfTwips(twips), rule: rule);
  }

  @override
  void write(
    XmlWriter w,
    String prefix,
    DocxRowHeight value,
    PropertyElement? asRead,
  ) {
    w.start('$prefix:$localName');
    w.attribute(
      '$prefix:val',
      '${twipsOf(value.heightPt, 'heightPt', min: 0, max: maxTwips)}',
    );
    w.attribute('$prefix:hRule', value.rule.name);
    w.end();
  }
}

/// The codec of `w:vMerge`: no `w:val` and `continue` are a continuation.
final class VerticalMergeCodec extends PropertyCodec<DocxVerticalMerge> {
  /// The codec of `w:vMerge`.
  const VerticalMergeCodec() : super('vMerge');

  @override
  Set<String> get attributes => const <String>{'val'};

  @override
  DocxVerticalMerge? parse(PropertyElement e) {
    if (!_plain(e)) {
      return null;
    }
    return switch (e.w('val')) {
      null || 'continue' => DocxVerticalMerge.continuation,
      'restart' => DocxVerticalMerge.restart,
      _ => null,
    };
  }

  @override
  void write(
    XmlWriter w,
    String prefix,
    DocxVerticalMerge value,
    PropertyElement? asRead,
  ) {
    w.start('$prefix:$localName');
    if (value == DocxVerticalMerge.restart) {
      w.attribute('$prefix:val', 'restart');
    }
    w.end();
  }
}

final Map<String, DocxCellAlignment> _cellAlignments =
    <String, DocxCellAlignment>{
      for (final DocxCellAlignment a in DocxCellAlignment.values) a.name: a,
    };

/// The codec of `w:vAlign`; `both` has no view.
final class CellAlignmentCodec extends ValEnumCodec<DocxCellAlignment> {
  /// The codec of `w:vAlign`.
  const CellAlignmentCodec() : super('vAlign');

  @override
  Map<String, DocxCellAlignment> get byXml => _cellAlignments;
}

const Map<String, DocxTextDirection> _textDirections =
    <String, DocxTextDirection>{
      'lrTb': DocxTextDirection.leftToRightTopToBottom,
      'tbRl': DocxTextDirection.topToBottomRightToLeft,
      'btLr': DocxTextDirection.bottomToTopLeftToRight,
      'lrTbV': DocxTextDirection.lrTbV,
      'tbRlV': DocxTextDirection.tbRlV,
      'tbLrV': DocxTextDirection.tbLrV,
    };

/// The codec of `w:textDirection`: six of the schema's spellings, by
/// [DocxTextDirection]; the others have no view.
final class TextDirectionCodec extends ValEnumCodec<DocxTextDirection> {
  /// The codec of `w:textDirection`.
  const TextDirectionCodec() : super('textDirection');

  @override
  Map<String, DocxTextDirection> get byXml => _textDirections;

  @override
  void write(
    XmlWriter w,
    String prefix,
    DocxTextDirection value,
    PropertyElement? asRead,
  ) {
    final String xml = _textDirections.entries
        .firstWhere((MapEntry<String, DocxTextDirection> m) => m.value == value)
        .key;
    w.start('$prefix:$localName');
    w.attribute('$prefix:val', xml);
    w.end();
  }
}

/// The schema of a table's `w:tblPr`: [tblPrOrder], typing the style, width,
/// alignment, indent, borders, layout, cell margins and look.
const ContainerSchema tablePropertiesSchema = ContainerSchema(
  tblPrOrder,
  codecs: <String, PropertyCodec<Object>>{
    'tblStyle': StyleIdCodec('tblStyle'),
    'tblW': TableWidthCodec('tblW'),
    'jc': TableAlignmentCodec(),
    'tblInd': TableIndentCodec(),
    'tblBorders': TableBordersCodec(),
    'tblLayout': TableLayoutCodec(),
    'tblCellMar': TableMarginsCodec(),
    'tblLook': TableLookCodec(),
  },
);

/// The schema of a row's `w:trPr`: [trPrOrder], typing the grid cells
/// before and after, `w:cantSplit`, the height and `w:tblHeader`. The schema
/// types those two as on or off only, so `false` is written `off`.
const ContainerSchema tableRowPropertiesSchema = ContainerSchema(
  trPrOrder,
  codecs: <String, PropertyCodec<Object>>{
    'gridBefore': IntValCodec('gridBefore', 0, maxGridColumns),
    'gridAfter': IntValCodec('gridAfter', 0, maxGridColumns),
    'cantSplit': OnOffCodec('cantSplit', falseValue: 'off'),
    'trHeight': RowHeightCodec(),
    'tblHeader': OnOffCodec('tblHeader', falseValue: 'off'),
  },
);

/// The schema of a cell's `w:tcPr`: [tcPrOrder], typing the width, grid
/// span, vertical merge, borders, shading, text direction and vertical
/// alignment.
const ContainerSchema tableCellPropertiesSchema = ContainerSchema(
  tcPrOrder,
  codecs: <String, PropertyCodec<Object>>{
    'tcW': TableWidthCodec('tcW'),
    'gridSpan': IntValCodec('gridSpan', 1, maxGridColumns),
    'vMerge': VerticalMergeCodec(),
    'tcBorders': CellBordersCodec(),
    'shd': ShadingCodec(),
    'textDirection': TextDirectionCodec(),
    'vAlign': CellAlignmentCodec(),
  },
);

/// The most grid columns a `w:gridSpan`, `w:gridBefore` or `w:gridAfter` is
/// typed with: 1000, far above the 63 Word allows, so a file that Word
/// wrote reads.
const int maxGridColumns = 1000;
