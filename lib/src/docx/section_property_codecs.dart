/// The codecs of the properties of a section, and the schema that types
/// them.
///
/// Not ported from Quds; written for jet_office.
///
/// [sectionPropertiesSchema] types the children of a `w:sectPr` the model
/// knows: the section's start (`w:type`), page size, margins, line and page
/// numbering, columns, vertical alignment and title page, and, as repeated
/// children, its header and footer references. Every other child
/// (`w:pgBorders`, `w:docGrid`, `w:footnotePr` and the like) is kept as read
/// (plan Ruling 15). A child is typed under the rules of
/// `property_codec.dart`, and a value out of range, a missing required
/// attribute or a spelling the model has no name for gives no view, so the
/// child is written as read.
library;

import '../opc/ooxml.dart' show Ns;
import '../opc/opaque_xml.dart';
import '../xml/xml_escape.dart';
import '../xml/xml_writer.dart';
import 'model/numbering_formats.dart';
import 'model/section_formatting.dart';
import 'properties.dart';
import 'property_codec.dart';
import 'run_property_codecs.dart';
import 'schema_order.dart';
import 'units.dart';

bool _plain(PropertyElement e) => e.children.isEmpty && !e.hasText;

/// Writes the attributes of [asRead] in `w:` whose local name is one of
/// [names], with [prefix], as read.
void _writeKept(
  XmlWriter w,
  String prefix,
  PropertyElement? asRead,
  Set<String> names,
) {
  if (asRead == null) {
    return;
  }
  for (final KeptAttribute a in asRead.attributes) {
    if (a.namespaceUri != Ns.w) {
      continue;
    }
    final String local = a.qualifiedName.substring(
      a.qualifiedName.indexOf(':') + 1,
    );
    if (names.contains(local)) {
      w.attribute('$prefix:$local', scrubXmlText(a.value).text);
    }
  }
}

bool _hasKept(PropertyElement e, Set<String> names) =>
    e.wAttributeNames.any(names.contains);

/// A twips attribute from `min` to `max`, or `null` for a bad or missing one.
int? _twips(PropertyElement e, String name, {int min = 0}) =>
    parseDecimal(e.w(name), min: min, max: maxTwips);

/// The codec of `w:pgSz`: width and height in twips and the orientation.
///
/// `w:w` and `w:h` are required. `w:orient` is `portrait` when missing; any
/// other spelling gives no view. `w:code` (the paper code) is understood and
/// kept as read when a value is set.
final class PageSizeCodec extends PropertyCodec<DocxPageSize> {
  /// The codec of `w:pgSz`.
  const PageSizeCodec() : super('pgSz');

  @override
  Set<String> get attributes => const <String>{'w', 'h', 'orient', 'code'};

  @override
  DocxPageSize? parse(PropertyElement e) {
    final int? width = _twips(e, 'w');
    final int? height = _twips(e, 'h');
    final DocxPageOrientation? orientation = switch (e.w('orient')) {
      null || 'portrait' => DocxPageOrientation.portrait,
      'landscape' => DocxPageOrientation.landscape,
      _ => null,
    };
    if (!_plain(e) || width == null || height == null || orientation == null) {
      return null;
    }
    return DocxPageSize(
      ptOfTwips(width),
      ptOfTwips(height),
      orientation: orientation,
    );
  }

  @override
  void write(
    XmlWriter w,
    String prefix,
    DocxPageSize value,
    PropertyElement? asRead,
  ) {
    w.start('$prefix:$localName');
    w.attribute(
      '$prefix:w',
      '${twipsOf(value.widthPt, 'widthPt', min: 0, max: maxTwips)}',
    );
    w.attribute(
      '$prefix:h',
      '${twipsOf(value.heightPt, 'heightPt', min: 0, max: maxTwips)}',
    );
    if (value.orientation == DocxPageOrientation.landscape) {
      w.attribute('$prefix:orient', 'landscape');
    }
    _writeKept(w, prefix, asRead, const <String>{'code'});
    w.end();
  }
}

/// The codec of `w:pgMar`: the seven distances in twips, all required.
///
/// `w:top` and `w:bottom` are signed; a missing or out of range one gives
/// no view.
final class PageMarginsCodec extends PropertyCodec<DocxPageMargins> {
  /// The codec of `w:pgMar`.
  const PageMarginsCodec() : super('pgMar');

  @override
  Set<String> get attributes => const <String>{
    'top',
    'right',
    'bottom',
    'left',
    'header',
    'footer',
    'gutter',
  };

  @override
  DocxPageMargins? parse(PropertyElement e) {
    final int? top = _twips(e, 'top', min: -maxTwips);
    final int? right = _twips(e, 'right');
    final int? bottom = _twips(e, 'bottom', min: -maxTwips);
    final int? left = _twips(e, 'left');
    final int? header = _twips(e, 'header');
    final int? footer = _twips(e, 'footer');
    final int? gutter = _twips(e, 'gutter');
    if (!_plain(e) ||
        top == null ||
        right == null ||
        bottom == null ||
        left == null ||
        header == null ||
        footer == null ||
        gutter == null) {
      return null;
    }
    return DocxPageMargins(
      top: ptOfTwips(top),
      right: ptOfTwips(right),
      bottom: ptOfTwips(bottom),
      left: ptOfTwips(left),
      header: ptOfTwips(header),
      footer: ptOfTwips(footer),
      gutter: ptOfTwips(gutter),
    );
  }

  @override
  void write(
    XmlWriter w,
    String prefix,
    DocxPageMargins value,
    PropertyElement? asRead,
  ) {
    String twips(double pt, String name, {int min = 0}) =>
        '${twipsOf(pt, name, min: min, max: maxTwips)}';
    w.start('$prefix:$localName');
    w.attribute('$prefix:top', twips(value.topPt, 'top', min: -maxTwips));
    w.attribute('$prefix:right', twips(value.rightPt, 'right'));
    w.attribute(
      '$prefix:bottom',
      twips(value.bottomPt, 'bottom', min: -maxTwips),
    );
    w.attribute('$prefix:left', twips(value.leftPt, 'left'));
    w.attribute('$prefix:header', twips(value.headerPt, 'header'));
    w.attribute('$prefix:footer', twips(value.footerPt, 'footer'));
    w.attribute('$prefix:gutter', twips(value.gutterPt, 'gutter'));
    w.end();
  }
}

/// The default `w:space` of `w:cols`, in twips (`ST_TwipsMeasure` default).
const int _defaultColumnSpace = 720;

/// The codec of `w:cols`: the column count, the space between, the
/// separator line and, for unequal columns, the `w:col` children.
///
/// With equal widths (`w:equalWidth` missing or on) the element must have no
/// `w:col`; with unequal ones it must have at least one, and `w:num`, when
/// present, must be their number. Anything else gives no view.
final class ColumnsCodec extends PropertyCodec<DocxColumns> {
  /// The codec of `w:cols`.
  const ColumnsCodec() : super('cols');

  @override
  Set<String> get attributes => const <String>{
    'num',
    'space',
    'sep',
    'equalWidth',
  };

  @override
  DocxColumns? parse(PropertyElement e) {
    if (e.hasText) {
      return null;
    }
    final String? equalRaw = e.w('equalWidth');
    final bool? equal = equalRaw == null ? true : parseOnOff(equalRaw);
    final String? sepRaw = e.w('sep');
    final bool? separator = sepRaw == null ? false : parseOnOff(sepRaw);
    final String? numRaw = e.w('num');
    final int? num = numRaw == null
        ? null
        : parseDecimal(numRaw, min: 1, max: maxColumns);
    final String? spaceRaw = e.w('space');
    final int? space = spaceRaw == null
        ? _defaultColumnSpace
        : parseDecimal(spaceRaw, min: 0, max: maxTwips);
    if (equal == null ||
        separator == null ||
        space == null ||
        (numRaw != null && num == null)) {
      return null;
    }
    if (equal) {
      return e.children.isEmpty
          ? DocxColumns(
              count: num,
              spacingPt: ptOfTwips(space),
              separator: separator,
            )
          : null;
    }
    if (e.children.isEmpty || e.children.length > maxColumns) {
      return null;
    }
    final List<DocxColumn> widths = <DocxColumn>[];
    for (final PropertyElement c in e.children) {
      final int? width = _twips(c, 'w');
      final String? spaceRaw = c.w('space');
      final int? gap = spaceRaw == null ? 0 : _twips(c, 'space');
      if (c.localName != 'col' ||
          c.namespaceUri != Ns.w ||
          !_plain(c) ||
          !const <String>{'w', 'space'}.containsAll(c.wAttributeNames) ||
          width == null ||
          gap == null) {
        return null;
      }
      widths.add(DocxColumn(ptOfTwips(width), spacingPt: ptOfTwips(gap)));
    }
    if (num != null && num != widths.length) {
      return null;
    }
    return DocxColumns(
      spacingPt: ptOfTwips(space),
      separator: separator,
      widths: widths,
    );
  }

  @override
  void write(
    XmlWriter w,
    String prefix,
    DocxColumns value,
    PropertyElement? asRead,
  ) {
    w.start('$prefix:$localName');
    w.attribute('$prefix:num', '${value.count}');
    w.attribute(
      '$prefix:space',
      '${twipsOf(value.spacingPt, 'spacingPt', min: 0, max: maxTwips)}',
    );
    if (value.separator) {
      w.attribute('$prefix:sep', '1');
    }
    final List<DocxColumn>? widths = value.widths;
    if (widths != null) {
      w.attribute('$prefix:equalWidth', '0');
      for (final DocxColumn c in widths) {
        w.start('$prefix:col');
        w.attribute(
          '$prefix:w',
          '${twipsOf(c.widthPt, 'widthPt', min: 0, max: maxTwips)}',
        );
        final int gap = twipsOf(
          c.spacingPt,
          'spacingPt',
          min: 0,
          max: maxTwips,
        );
        if (gap != 0) {
          w.attribute('$prefix:space', '$gap');
        }
        w.end();
      }
    }
    w.end();
  }
}

final Map<String, DocxSectionStart> _starts = <String, DocxSectionStart>{
  for (final DocxSectionStart s in DocxSectionStart.values) s.name: s,
};

/// The codec of `w:type`, how the section starts.
final class SectionStartCodec extends ValEnumCodec<DocxSectionStart> {
  /// The codec of `w:type`.
  const SectionStartCodec() : super('type');

  @override
  Map<String, DocxSectionStart> get byXml => _starts;
}

final Map<String, DocxSectionVerticalAlignment> _verticalAlignments =
    <String, DocxSectionVerticalAlignment>{
      for (final DocxSectionVerticalAlignment a
          in DocxSectionVerticalAlignment.values)
        a.name: a,
    };

/// The codec of a section's `w:vAlign`.
final class SectionVerticalAlignmentCodec
    extends ValEnumCodec<DocxSectionVerticalAlignment> {
  /// The codec of a section's `w:vAlign`.
  const SectionVerticalAlignmentCodec() : super('vAlign');

  @override
  Map<String, DocxSectionVerticalAlignment> get byXml => _verticalAlignments;
}

final Map<String, DocxNumberFormat> _numberFormats = <String, DocxNumberFormat>{
  for (final DocxNumberFormat f in DocxNumberFormat.values) f.name: f,
};

/// The chapter attributes of `w:pgNumType`, which the model does not type
/// (plan Ruling 15): kept as read ([PropertyCodec.keepsRest]).
const Set<String> _chapterAttributes = <String>{'chapStyle', 'chapSep'};

/// The codec of `w:pgNumType`: the number format (`w:fmt`) and the first
/// number (`w:start`).
///
/// A format the model has no name for (`chicago`, the East Asian ones) or
/// a start out of range gives no view. `w:chapStyle` and `w:chapSep` stay
/// as read, also when the value is removed.
final class PageNumberingCodec extends PropertyCodec<DocxPageNumbering> {
  /// The codec of `w:pgNumType`.
  const PageNumberingCodec() : super('pgNumType');

  @override
  Set<String> get attributes => const <String>{
    'fmt',
    'start',
    ..._chapterAttributes,
  };

  @override
  DocxPageNumbering? parse(PropertyElement e) {
    final String? fmtRaw = e.w('fmt');
    final DocxNumberFormat? format = parseEnum(fmtRaw, _numberFormats);
    final String? startRaw = e.w('start');
    final int? start = parseDecimal(startRaw, min: 0, max: maxSectionNumber);
    if (!_plain(e) ||
        (fmtRaw != null && format == null) ||
        (startRaw != null && start == null)) {
      return null;
    }
    return DocxPageNumbering(format: format, start: start);
  }

  @override
  void write(
    XmlWriter w,
    String prefix,
    DocxPageNumbering value,
    PropertyElement? asRead,
  ) {
    w.start('$prefix:$localName');
    if (value.format != null) {
      w.attribute('$prefix:fmt', value.format!.name);
    }
    if (value.start != null) {
      w.attribute('$prefix:start', '${value.start}');
    }
    _writeKept(w, prefix, asRead, _chapterAttributes);
    w.end();
  }

  @override
  bool keepsRest(PropertyElement e) => _hasKept(e, _chapterAttributes);

  @override
  void writeRest(XmlWriter w, String prefix, PropertyElement asRead) {
    w.start('$prefix:$localName');
    _writeKept(w, prefix, asRead, _chapterAttributes);
    w.end();
  }
}

final Map<String, DocxLineNumberRestart> _restarts =
    <String, DocxLineNumberRestart>{
      for (final DocxLineNumberRestart r in DocxLineNumberRestart.values)
        r.name: r,
    };

/// The codec of `w:lnNumType`: `w:countBy`, `w:start`, `w:distance` and
/// `w:restart`, each optional.
///
/// A value out of range or a restart the model has no name for gives no
/// view.
final class LineNumberingCodec extends PropertyCodec<DocxLineNumbering> {
  /// The codec of `w:lnNumType`.
  const LineNumberingCodec() : super('lnNumType');

  @override
  Set<String> get attributes => const <String>{
    'countBy',
    'start',
    'distance',
    'restart',
  };

  @override
  DocxLineNumbering? parse(PropertyElement e) {
    final String? countRaw = e.w('countBy');
    final int? countBy = parseDecimal(countRaw, min: 1, max: maxSectionNumber);
    final String? startRaw = e.w('start');
    final int? start = parseDecimal(startRaw, min: 0, max: maxSectionNumber);
    final String? distanceRaw = e.w('distance');
    final int? distance = _twips(e, 'distance');
    final String? restartRaw = e.w('restart');
    final DocxLineNumberRestart? restart = parseEnum(restartRaw, _restarts);
    if (!_plain(e) ||
        (countRaw != null && countBy == null) ||
        (startRaw != null && start == null) ||
        (distanceRaw != null && distance == null) ||
        (restartRaw != null && restart == null)) {
      return null;
    }
    return DocxLineNumbering(
      countBy: countBy,
      start: start,
      distancePt: distance == null ? null : ptOfTwips(distance),
      restart: restart,
    );
  }

  @override
  void write(
    XmlWriter w,
    String prefix,
    DocxLineNumbering value,
    PropertyElement? asRead,
  ) {
    w.start('$prefix:$localName');
    if (value.countBy != null) {
      w.attribute('$prefix:countBy', '${value.countBy}');
    }
    if (value.start != null) {
      w.attribute('$prefix:start', '${value.start}');
    }
    if (value.distancePt != null) {
      w.attribute(
        '$prefix:distance',
        '${twipsOf(value.distancePt!, 'distancePt', min: 0, max: maxTwips)}',
      );
    }
    if (value.restart != null) {
      w.attribute('$prefix:restart', value.restart!.name);
    }
    w.end();
  }
}

/// Which page a header or footer reference is for (`w:type` of
/// `w:headerReference` and `w:footerReference`).
enum SectionReferenceType {
  /// The page no other reference covers (`default`).
  defaultPage('default'),

  /// The section's first page (`first`), when it has a title page.
  first('first'),

  /// The even pages (`even`), when the document has odd and even headers.
  even('even');

  const SectionReferenceType(this.xml);

  /// The value of `w:type`.
  final String xml;
}

final Map<String, SectionReferenceType> _referenceTypes =
    <String, SectionReferenceType>{
      for (final SectionReferenceType t in SectionReferenceType.values)
        t.xml: t,
    };

/// A header or footer reference of a section: the page it is for and the id
/// of the relationship that names the part (`r:id`).
final class SectionReference {
  /// A reference of [type] through the relationship [relId].
  const SectionReference(this.type, this.relId);

  /// The pages the reference is for.
  final SectionReferenceType type;

  /// The relationship id, as the file spells it.
  final String relId;

  @override
  bool operator ==(Object other) =>
      other is SectionReference && other.type == type && other.relId == relId;

  @override
  int get hashCode => Object.hash(type, relId);

  @override
  String toString() => 'SectionReference(${type.name}, $relId)';
}

/// A reference the API put in a section: it names its [story] directly, as
/// the story's part and relationship are created at save, which fills
/// [relId]. Until then [relId] is empty, and such a reference is not written.
final class AddedSectionReference extends SectionReference {
  /// A reference of [type] to [story], with no relationship yet.
  AddedSectionReference(SectionReferenceType type, this.story)
    : super(type, '');

  /// The story, which only the document knows the type of.
  final Object story;

  String _id = '';

  @override
  String get relId => _id;

  /// Fills [relId], once the save added the relationship.
  set relId(String value) => _id = value;

  @override
  bool operator ==(Object other) => identical(this, other);

  @override
  int get hashCode => identityHashCode(this);
}

/// The codec of one `w:headerReference` or `w:footerReference`, which
/// repeat in a `w:sectPr`: a [SectionReference].
///
/// A reference with no `w:type` or an unknown one, or no `r:id` (or an empty
/// one), gives no view. A reference is written with a prefix the bindings in
/// scope give the relationships namespace: `r` first, then any other. With
/// none, it declares one on the element: `r`, or `r1` (`r2`, ...) when `r`
/// means something else there.
final class SectionReferenceCodec extends PropertyCodec<SectionReference> {
  /// The codec of `w:headerReference` or `w:footerReference`.
  const SectionReferenceCodec(super.localName);

  @override
  Set<String> get attributes => const <String>{'type'};

  @override
  SectionReference? parse(PropertyElement e) {
    final SectionReferenceType? type = parseEnum(e.w('type'), _referenceTypes);
    String? id;
    for (final KeptAttribute a in e.attributes) {
      if (a.namespaceUri == Ns.rel &&
          a.qualifiedName.substring(a.qualifiedName.indexOf(':') + 1) == 'id') {
        id = a.value;
      }
    }
    if (!_plain(e) || type == null || id == null || id.isEmpty) {
      return null;
    }
    return SectionReference(type, id);
  }

  @override
  void write(
    XmlWriter w,
    String prefix,
    SectionReference value,
    PropertyElement? asRead,
  ) => writeRepeated(w, prefix, value, const <String, String>{'r': Ns.rel});

  @override
  void writeRepeated(
    XmlWriter w,
    String prefix,
    SectionReference value,
    Map<String, String> scope,
  ) {
    // A break taken to a table cell leaves the sections, so its story has no
    // part, and there is nothing for the reference to name.
    if (value.relId.isEmpty) return;
    w.start('$prefix:$localName');
    w.attribute('$prefix:type', value.type.xml);
    String? rel = scope['r'] == Ns.rel ? 'r' : null;
    for (final MapEntry<String, String> e in scope.entries) {
      if (rel != null) break;
      if (e.key.isNotEmpty && e.value == Ns.rel) rel = e.key;
    }
    if (rel == null) {
      rel = 'r';
      for (int i = 1; scope.containsKey(rel); i++) {
        rel = 'r$i';
      }
      w.attribute('xmlns:$rel', Ns.rel);
    }
    w.attribute('$rel:id', scrubXmlText(value.relId).text);
    w.end();
  }
}

/// The schema of a section's `w:sectPr`: [sectPrOrder], typing the
/// section's start, page size, margins, line and page numbering, columns,
/// vertical alignment and title page, with the header and footer
/// references as repeated children.
const ContainerSchema sectionPropertiesSchema = ContainerSchema(
  sectPrOrder,
  codecs: <String, PropertyCodec<Object>>{
    'type': SectionStartCodec(),
    'pgSz': PageSizeCodec(),
    'pgMar': PageMarginsCodec(),
    'lnNumType': LineNumberingCodec(),
    'pgNumType': PageNumberingCodec(),
    'cols': ColumnsCodec(),
    'vAlign': SectionVerticalAlignmentCodec(),
    'titlePg': OnOffCodec('titlePg'),
  },
  repeated: <String, PropertyCodec<Object>>{
    'headerReference': SectionReferenceCodec('headerReference'),
    'footerReference': SectionReferenceCodec('footerReference'),
  },
);
