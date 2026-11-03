/// The codecs of the children of a paragraph's `w:pPr`, and the schema that
/// types them.
///
/// Not ported from Quds; written for jet_office.
///
/// [paragraphPropertiesSchema] types the thirteen properties of
/// `DocxParagraphProperties`. A child is typed only when it is in `w:`,
/// occurs once, has no `w:` attribute its codec does not list, and parses
/// (plan Ruling 2); `w:jc w:val="lowKashida"`, `w:ind w:left="1in"` or
/// `w:ind w:leftChars="100"` read `null` and are written back as read.
///
/// Three properties are elements with children: `w:pBdr` (the sides, by
/// [paragraphBordersSchema]), `w:tabs` and `w:numPr`. Their codecs type the
/// element only when every child is in `w:`, is one the model knows, is
/// plain and parses; a set writes the whole element anew. The paragraph
/// mark's `w:rPr` is not typed (it is kept as read).
library;

import '../opc/ooxml.dart' show Ns;
import '../xml/xml_writer.dart';
import 'model/formatting.dart';
import 'properties.dart';
import 'property_codec.dart';
import 'run_property_codecs.dart';
import 'schema_order.dart';
import 'units.dart';
import 'value_codecs.dart';

bool _plain(PropertyElement e) => e.children.isEmpty && !e.hasText;

final Map<String, DocxAlignment> _alignments = <String, DocxAlignment>{
  for (final DocxAlignment a in DocxAlignment.values)
    if (a != DocxAlignment.justify) a.name: a,
  'both': DocxAlignment.justify,
};

/// The codec of `w:jc`. `justify` is `both` in the file; the kashida values,
/// `numTab` and `thaiDistribute` have no view.
final class AlignmentCodec extends ValEnumCodec<DocxAlignment> {
  /// The codec of `w:jc`.
  const AlignmentCodec() : super('jc');

  @override
  Map<String, DocxAlignment> get byXml => _alignments;

  @override
  void write(
    XmlWriter w,
    String prefix,
    DocxAlignment value,
    PropertyElement? asRead,
  ) {
    w.start('$prefix:$localName');
    w.attribute(
      '$prefix:val',
      value == DocxAlignment.justify ? 'both' : value.name,
    );
    w.end();
  }
}

/// The codec of a property whose `w:val` is a whole number from a smallest
/// to a largest: `w:outlineLvl`.
final class IntValCodec extends PropertyCodec<int> {
  /// The codec of `w:<localName>` with a `w:val` from [_min] to [_max].
  const IntValCodec(super.localName, this._min, this._max);

  final int _min;
  final int _max;

  @override
  Set<String> get attributes => const <String>{'val'};

  @override
  int? parse(PropertyElement e) =>
      _plain(e) ? parseDecimal(e.w('val'), min: _min, max: _max) : null;

  @override
  void write(XmlWriter w, String prefix, int value, PropertyElement? asRead) {
    w.start('$prefix:$localName');
    w.attribute('$prefix:val', '$value');
    w.end();
  }
}

/// The codec of `w:ind`: left, right, first line and hanging, in twips.
///
/// `w:start`, `w:end` and the `…Chars` attributes are not understood, so an
/// indentation with one has no view; so has one with both `w:firstLine` and
/// `w:hanging`.
final class IndentationCodec extends PropertyCodec<DocxIndentation> {
  /// The codec of `w:ind`.
  const IndentationCodec() : super('ind');

  @override
  Set<String> get attributes => const <String>{
    'left',
    'right',
    'firstLine',
    'hanging',
  };

  @override
  DocxIndentation? parse(PropertyElement e) {
    if (!_plain(e)) {
      return null;
    }
    bool bad = false;
    double? twips(String name, int min) {
      final String? raw = e.w(name);
      if (raw == null) {
        return null;
      }
      final int? n = parseDecimal(raw, min: min, max: maxTwips);
      if (n == null) {
        bad = true;
        return null;
      }
      return ptOfTwips(n);
    }

    final double? left = twips('left', -maxTwips);
    final double? right = twips('right', -maxTwips);
    final double? firstLine = twips('firstLine', 0);
    final double? hanging = twips('hanging', 0);
    if (bad || (firstLine != null && hanging != null)) {
      return null;
    }
    return DocxIndentation(
      leftPt: left,
      rightPt: right,
      firstLinePt: firstLine,
      hangingPt: hanging,
    );
  }

  @override
  void write(
    XmlWriter w,
    String prefix,
    DocxIndentation value,
    PropertyElement? asRead,
  ) {
    w.start('$prefix:$localName');
    void attr(String name, double? pt) {
      if (pt != null) {
        w.attribute(
          '$prefix:$name',
          '${twipsOf(pt, name, min: -maxTwips, max: maxTwips)}',
        );
      }
    }

    attr('left', value.leftPt);
    attr('right', value.rightPt);
    attr('firstLine', value.firstLinePt);
    attr('hanging', value.hangingPt);
    w.end();
  }
}

/// The codec of `w:spacing` of a paragraph: before, after, their automatic
/// variants, and the line with its rule.
///
/// `w:beforeLines` and `w:afterLines` are not understood. A `w:lineRule`
/// without `w:line`, or one that is not `auto`, `exact` or `atLeast`, has
/// no view; a `w:line` without a rule is `auto`.
final class SpacingCodec extends PropertyCodec<DocxSpacing> {
  /// The codec of `w:spacing`.
  const SpacingCodec() : super('spacing');

  @override
  Set<String> get attributes => const <String>{
    'before',
    'after',
    'beforeAutospacing',
    'afterAutospacing',
    'line',
    'lineRule',
  };

  @override
  DocxSpacing? parse(PropertyElement e) {
    if (!_plain(e)) {
      return null;
    }
    bool bad = false;
    double? space(String name) {
      final String? raw = e.w(name);
      if (raw == null) {
        return null;
      }
      final int? n = parseDecimal(raw, min: 0, max: maxTwips);
      if (n == null) {
        bad = true;
        return null;
      }
      return ptOfTwips(n);
    }

    bool auto(String name) {
      final bool? v = parseOnOff(e.w(name) ?? 'false');
      if (v == null) {
        bad = true;
      }
      return v ?? false;
    }

    final double? before = space('before');
    final double? after = space('after');
    final bool beforeAuto = auto('beforeAutospacing');
    final bool afterAuto = auto('afterAutospacing');
    DocxLineSpacing? line;
    final String? lineRaw = e.w('line');
    final String? rule = e.w('lineRule');
    if (lineRaw == null) {
      bad = bad || rule != null;
    } else {
      final int? n = parseDecimal(lineRaw, min: 0, max: maxTwips);
      if (n == null) {
        bad = true;
      } else {
        switch (rule) {
          case null || 'auto':
            if (n < 1) {
              bad = true;
            } else {
              line = DocxLineSpacing.multiple(linesOfLineUnits(n));
            }
          case 'exact':
            line = DocxLineSpacing.exactly(ptOfTwips(n));
          case 'atLeast':
            line = DocxLineSpacing.atLeast(ptOfTwips(n));
          default:
            bad = true;
        }
      }
    }
    if (bad) {
      return null;
    }
    return DocxSpacing(
      beforePt: before,
      afterPt: after,
      beforeAuto: beforeAuto,
      afterAuto: afterAuto,
      line: line,
    );
  }

  @override
  void write(
    XmlWriter w,
    String prefix,
    DocxSpacing value,
    PropertyElement? asRead,
  ) {
    w.start('$prefix:$localName');
    String twips(double pt) => '${twipsOf(pt, 'pt', min: 0, max: maxTwips)}';
    final double? before = value.beforePt;
    if (before != null) {
      w.attribute('$prefix:before', twips(before));
    }
    if (value.beforeAuto) {
      w.attribute('$prefix:beforeAutospacing', '1');
    }
    final double? after = value.afterPt;
    if (after != null) {
      w.attribute('$prefix:after', twips(after));
    }
    if (value.afterAuto) {
      w.attribute('$prefix:afterAutospacing', '1');
    }
    final DocxLineSpacing? line = value.line;
    if (line != null) {
      switch (line.rule) {
        case DocxLineRule.auto:
          w.attribute(
            '$prefix:line',
            '${lineUnitsOf(line.value, 'lines', min: 1, max: maxTwips)}',
          );
          w.attribute('$prefix:lineRule', 'auto');
        case DocxLineRule.exact:
          w.attribute('$prefix:line', twips(line.value));
          w.attribute('$prefix:lineRule', 'exact');
        case DocxLineRule.atLeast:
          w.attribute('$prefix:line', twips(line.value));
          w.attribute('$prefix:lineRule', 'atLeast');
      }
    }
    w.end();
  }
}

/// The schema of a paragraph's `w:pBdr`: [pBdrOrder], with a [BorderCodec]
/// for each side. [ParagraphBordersCodec] reads and writes the sides by it.
const ContainerSchema paragraphBordersSchema = ContainerSchema(
  pBdrOrder,
  codecs: <String, PropertyCodec<Object>>{
    'top': BorderCodec('top'),
    'left': BorderCodec('left'),
    'bottom': BorderCodec('bottom'),
    'right': BorderCodec('right'),
    'between': BorderCodec('between'),
    'bar': BorderCodec('bar'),
  },
);

/// The codec of `w:pBdr`: the sides of [DocxParagraphBorders].
///
/// The element is typed only when every child is a side in `w:` that
/// occurs once and that [BorderCodec] types, and the element has no
/// attribute and no text.
final class ParagraphBordersCodec extends PropertyCodec<DocxParagraphBorders> {
  /// The codec of `w:pBdr`.
  const ParagraphBordersCodec() : super('pBdr');

  @override
  Set<String> get attributes => const <String>{};

  @override
  DocxParagraphBorders? parse(PropertyElement e) {
    if (e.hasText) {
      return null;
    }
    final Map<String, DocxBorder> sides = <String, DocxBorder>{};
    for (final PropertyElement child in e.children) {
      final PropertyCodec<Object>? codec =
          paragraphBordersSchema.codecs[child.localName];
      if (child.namespaceUri != Ns.w ||
          codec == null ||
          sides.containsKey(child.localName) ||
          !codec.attributes.containsAll(child.wAttributeNames)) {
        return null;
      }
      final Object? border = codec.parse(child);
      if (border is! DocxBorder) {
        return null;
      }
      sides[child.localName] = border;
    }
    return DocxParagraphBorders(
      top: sides['top'],
      left: sides['left'],
      bottom: sides['bottom'],
      right: sides['right'],
      between: sides['between'],
      bar: sides['bar'],
    );
  }

  @override
  void write(
    XmlWriter w,
    String prefix,
    DocxParagraphBorders value,
    PropertyElement? asRead,
  ) {
    final Map<String, DocxBorder?> sides = <String, DocxBorder?>{
      'top': value.top,
      'left': value.left,
      'bottom': value.bottom,
      'right': value.right,
      'between': value.between,
      'bar': value.bar,
    };
    w.start('$prefix:$localName');
    for (final String name in paragraphBordersSchema.order) {
      final DocxBorder? border = sides[name];
      if (border != null) {
        paragraphBordersSchema.codecs[name]!.write(w, prefix, border, null);
      }
    }
    w.end();
  }
}

final Map<String, DocxTabAlignment> _tabAlignments = <String, DocxTabAlignment>{
  for (final DocxTabAlignment a in DocxTabAlignment.values) a.name: a,
};

final Map<String, DocxTabLeader> _tabLeaders = <String, DocxTabLeader>{
  for (final DocxTabLeader l in DocxTabLeader.values) l.name: l,
};

/// The codec of `w:tabs`: a list of `w:tab` stops.
///
/// The element is typed only when it has at least one stop and every child
/// is a plain `w:tab` in `w:` with a known `w:val`, a position in range and,
/// when it has one, a known `w:leader`. The list read is unmodifiable.
final class TabsCodec extends PropertyCodec<List<DocxTabStop>> {
  /// The codec of `w:tabs`.
  const TabsCodec() : super('tabs');

  @override
  Set<String> get attributes => const <String>{};

  @override
  List<DocxTabStop>? parse(PropertyElement e) {
    if (e.hasText || e.children.isEmpty) {
      return null;
    }
    final List<DocxTabStop> stops = <DocxTabStop>[];
    for (final PropertyElement child in e.children) {
      if (child.namespaceUri != Ns.w ||
          child.localName != 'tab' ||
          !_plain(child) ||
          !const <String>{
            'val',
            'leader',
            'pos',
          }.containsAll(child.wAttributeNames)) {
        return null;
      }
      final DocxTabAlignment? alignment = parseEnum(
        child.w('val'),
        _tabAlignments,
      );
      final String? leaderRaw = child.w('leader');
      final DocxTabLeader? leader = leaderRaw == null
          ? DocxTabLeader.none
          : parseEnum(leaderRaw, _tabLeaders);
      final int? pos = parseDecimal(
        child.w('pos'),
        min: -maxTwips,
        max: maxTwips,
      );
      if (alignment == null || leader == null || pos == null) {
        return null;
      }
      stops.add(
        DocxTabStop(ptOfTwips(pos), alignment: alignment, leader: leader),
      );
    }
    return List<DocxTabStop>.unmodifiable(stops);
  }

  @override
  void write(
    XmlWriter w,
    String prefix,
    List<DocxTabStop> value,
    PropertyElement? asRead,
  ) {
    w.start('$prefix:$localName');
    for (final DocxTabStop stop in value) {
      w.start('$prefix:tab');
      w.attribute('$prefix:val', stop.alignment.name);
      if (stop.leader != DocxTabLeader.none) {
        w.attribute('$prefix:leader', stop.leader.name);
      }
      final int pos = twipsOf(
        stop.positionPt,
        'positionPt',
        min: -maxTwips,
        max: maxTwips,
      );
      w.attribute('$prefix:pos', '$pos');
      w.end();
    }
    w.end();
  }
}

/// The codec of `w:numPr`: the level (`w:ilvl`) and the list number
/// (`w:numId`).
///
/// The element is typed only when it has a `w:numId` and no other child
/// but one `w:ilvl`; a `w:numPr` with `w:numberingChange` or `w:ins` has no
/// view. A missing `w:ilvl` reads as level 0, and a set always writes it.
final class NumberingCodec extends PropertyCodec<DocxNumberingRef> {
  /// The codec of `w:numPr`.
  const NumberingCodec() : super('numPr');

  @override
  Set<String> get attributes => const <String>{};

  @override
  DocxNumberingRef? parse(PropertyElement e) {
    if (e.hasText) {
      return null;
    }
    int? numId;
    int? level;
    for (final PropertyElement child in e.children) {
      if (child.namespaceUri != Ns.w ||
          !_plain(child) ||
          !const <String>{'val'}.containsAll(child.wAttributeNames)) {
        return null;
      }
      switch (child.localName) {
        case 'ilvl':
          if (level != null) {
            return null;
          }
          level = parseDecimal(child.w('val'), min: 0, max: 8);
          if (level == null) {
            return null;
          }
        case 'numId':
          if (numId != null) {
            return null;
          }
          numId = parseDecimal(child.w('val'), min: 0, max: maxNumId);
          if (numId == null) {
            return null;
          }
        default:
          return null;
      }
    }
    return numId == null ? null : DocxNumberingRef(numId, level: level ?? 0);
  }

  @override
  void write(
    XmlWriter w,
    String prefix,
    DocxNumberingRef value,
    PropertyElement? asRead,
  ) {
    w.start('$prefix:$localName');
    for (final String name in numPrOrder) {
      if (name == 'ilvl') {
        writeValElement(w, '$prefix:ilvl', '${value.level}', prefix: prefix);
      } else if (name == 'numId') {
        writeValElement(w, '$prefix:numId', '${value.numId}', prefix: prefix);
      }
    }
    w.end();
  }
}

/// The codecs of the thirteen properties of `DocxParagraphProperties`, by
/// local name; every name is in [pPrOrder] and [pPrGeneralOrder].
const Map<String, PropertyCodec<Object>> _paragraphCodecs =
    <String, PropertyCodec<Object>>{
      'pStyle': StyleIdCodec('pStyle'),
      'keepNext': OnOffCodec('keepNext'),
      'keepLines': OnOffCodec('keepLines'),
      'pageBreakBefore': OnOffCodec('pageBreakBefore'),
      'widowControl': OnOffCodec('widowControl'),
      'numPr': NumberingCodec(),
      'pBdr': ParagraphBordersCodec(),
      'shd': ShadingCodec(),
      'tabs': TabsCodec(),
      'spacing': SpacingCodec(),
      'ind': IndentationCodec(),
      'jc': AlignmentCodec(),
      'outlineLvl': IntValCodec('outlineLvl', 0, 9),
    };

/// The schema of a paragraph's `w:pPr`: [pPrOrder], typing the thirteen
/// properties of `DocxParagraphProperties`.
const ContainerSchema paragraphPropertiesSchema = ContainerSchema(
  pPrOrder,
  codecs: _paragraphCodecs,
);

/// The schema of the `w:pPr` of a style, a numbering level or the
/// paragraph-properties default (`CT_PPrGeneral`): [pPrGeneralOrder], typing
/// the same properties as [paragraphPropertiesSchema]. It has no paragraph
/// mark `w:rPr` and no `w:sectPr`.
const ContainerSchema paragraphPropertiesGeneralSchema = ContainerSchema(
  pPrGeneralOrder,
  codecs: _paragraphCodecs,
);
