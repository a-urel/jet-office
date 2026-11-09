/// The Excel 2010 conditional formats of a worksheet: reading the
/// `x14:conditionalFormattings` of its `extLst`, joining them with the
/// Excel 2007 elements of its [CfBlock], and editing them.
///
/// Not ported from Quds; written for jet_office.
///
/// The `extLst` stays an [XmlNode] whose `ext`s are typed and whose
/// `x14:conditionalFormattings` is an [OpaqueXml], so a save writes what was
/// read. [X14Block] is a reading of it: [X14Element]s and their [X14Rule]s,
/// each keeping its source. Edits write a new [OpaqueXml] from the sources
/// and a new `extLst`, so `swapLayout` undoes them, and only the element
/// edited is written anew.
///
/// Elements are matched by namespace, not by prefix. A rule reads from
/// `dataBar`, `iconSet` without `x14:cfIcon`, `expression` or `cellIs`; any
/// other is kept and listed nowhere, unreported. A rule with no `id`, or a
/// value the writer would refuse, is kept too and reported as `x14:cfRule`,
/// an element with no usable `xm:sqref` as `x14:conditionalFormatting`.
///
/// [joinConditionalFormats] says which rules make a format. A 2007 rule's
/// `x14:id` names its half; the fields of a data bar's half lie over the 2007
/// rule ([X14BarFields.over]), which reads as `barAsWritten`, so what the
/// writer fills for none reads as none. A rule no 2007 rule names joins the
/// format with an equal `sqref`, by priority, or makes one of its own.
library;

import '../../opc/ooxml.dart';
import '../../opc/opaque_xml.dart';
import '../../xml/xml_escape.dart';
import '../../xml/xml_pull_reader.dart';
import '../../xml/xml_writer.dart';
import '../color.dart';
import '../conditional_format.dart';
import '../conditional_format_x14.dart';
import '../formula/formula_rewrite.dart';
import '../range.dart';
import 'conditional_elements.dart';
import 'element_node.dart';
import 'item_group.dart' show GroupItem, readerOf;
import 'reference_holders.dart';
import 'style_elements.dart'
    show
        ReadDifferentialStyle,
        ReadStyleValue,
        readColor,
        readDifferentialEntry;
import 'validation_elements.dart' show childText, parseSqref;

/// The name of the group element in the `ext`.
const String _groupName = 'conditionalFormattings';

/// The fields of an `x14:dataBar`; `null` where the element says nothing.
final class X14BarFields {
  /// The fields of one element, all of them read.
  const X14BarFields({
    this.min,
    this.max,
    this.minLength,
    this.maxLength,
    this.showValue,
    required this.gradient,
    required this.border,
    required this.axis,
    this.fillColor,
    this.borderColor,
    this.negativeFillColor,
    this.negativeBorderColor,
    this.axisColor,
  });

  /// The `x14:cfvo` of the shortest bar.
  final XlsxCfValue? min;

  /// The `x14:cfvo` of the longest bar.
  final XlsxCfValue? max;

  /// The `minLength`, as written.
  final int? minLength;

  /// The `maxLength`, as written.
  final int? maxLength;

  /// The `showValue`, which the writer leaves to the 2007 rule.
  final bool? showValue;

  /// Whether the bar fades out.
  final bool gradient;

  /// Whether the bar has a border.
  final bool border;

  /// Where the axis lies.
  final XlsxDataBarAxis axis;

  /// The `x14:fillColor`, which a bar with a 2007 rule usually leaves out.
  final XlsxColor? fillColor;

  /// The `x14:borderColor`, with a border only.
  final XlsxColor? borderColor;

  /// The `x14:negativeFillColor`.
  final XlsxColor? negativeFillColor;

  /// The `x14:negativeBorderColor`, when Excel uses it: with a border, and
  /// `negativeBarBorderColorSameAsPositive` false.
  final XlsxColor? negativeBorderColor;

  /// The `x14:axisColor`.
  final XlsxColor? axisColor;

  /// [base], the 2007 rule, with these fields over it.
  ///
  /// The writer writes the lengths 10 and 90 as 0 and 100, so those say
  /// nothing new. Lengths that would cross stay the 2007 rule's.
  XlsxDataBar over(XlsxDataBar base) {
    int shortest = _length(minLength, base.minLength, 10, 0);
    int longest = _length(maxLength, base.maxLength, 90, 100);
    if (shortest > longest) {
      shortest = base.minLength;
      longest = base.maxLength;
    }
    return _bar(
      _point(min, base.min),
      _point(max, base.max),
      fillColor ?? base.color,
      showValue ?? base.showValue,
      shortest,
      longest,
      base.stopIfTrue,
    );
  }

  /// The bar these fields make with no 2007 rule, or `null` with no
  /// `x14:fillColor`, which is then the only source of its color.
  XlsxDataBar? alone(bool stopIfTrue) {
    final XlsxColor? color = fillColor;
    if (color == null) return null;
    return _bar(
      min ?? const XlsxCfValue.min(),
      max ?? const XlsxCfValue.max(),
      color,
      showValue ?? true,
      minLength ?? 10,
      maxLength ?? 90,
      stopIfTrue,
    );
  }

  XlsxDataBar _bar(
    XlsxCfValue min,
    XlsxCfValue max,
    XlsxColor color,
    bool showValue,
    int minLength,
    int maxLength,
    bool stopIfTrue,
  ) => barAsWritten(
    XlsxDataBar(
      min: min,
      max: max,
      color: color,
      showValue: showValue,
      minLength: minLength,
      maxLength: maxLength,
      gradient: gradient,
      border: border,
      borderColor: borderColor,
      negativeFillColor: negativeFillColor,
      negativeBorderColor: negativeBorderColor,
      axis: axis,
      axisColor: axisColor,
      stopIfTrue: stopIfTrue,
    ),
  );

  static int _length(int? x14, int base, int plain, int written) {
    if (x14 == null) return base;
    return x14 == (base == plain ? written : base) ? base : x14;
  }

  /// The writer gives a `min` or `max` no value here, whatever its 2007 rule
  /// holds, so a point of the 2007 rule's type with none keeps that value.
  static XlsxCfValue _point(XlsxCfValue? x14, XlsxCfValue base) {
    if (x14 == null) return base;
    if (x14.value != null || x14.type != base.type) return x14;
    return XlsxCfValue(
      base.type,
      value: base.value,
      greaterOrEqual: x14.greaterOrEqual,
    );
  }
}

/// One `x14:cfRule`, as the model reads it.
final class X14Rule {
  /// A rule of [id] reading as [rule], kept as [source].
  const X14Rule(
    this.id,
    this.rule,
    this.priority,
    this.source, {
    this.exact = true,
    this.bar,
  });

  /// The `id`, or `null` for none.
  final String? id;

  /// The rule, with its style, or `null` when it cannot stand as a rule of
  /// a format: it stays as written.
  final XlsxConditionalRule? rule;

  /// The `priority`, or `null` for none, as a data bar's half has.
  final int? priority;

  /// The element, as read or as the writer rendered it.
  final OpaqueXml source;

  /// Whether [rule]'s style is everything the `x14:dxf` holds, in the sense
  /// of `readDifferentialStyle`.
  final bool exact;

  /// What a readable `x14:dataBar` says, for the 2007 rule that names [id].
  final X14BarFields? bar;
}

/// One `x14:conditionalFormatting`.
final class X14Element {
  /// An element named [qualifiedName] holding [children], read from
  /// [source].
  const X14Element(
    this.qualifiedName,
    this.namespaces,
    this.attributes,
    this.children,
    this.ranges,
    this.source,
  );

  /// The element's name with its prefix, as written.
  final String qualifiedName;

  /// The namespace declarations of the start tag.
  final Map<String, String> namespaces;

  /// The attributes, as written.
  final List<KeptAttribute> attributes;

  /// The children in order: an [X14Rule] for each `x14:cfRule`, an
  /// [OpaqueXml] for everything else, `xm:sqref` included.
  final List<Object> children;

  /// The cells of `xm:sqref`, or `null` when it has none that can be used.
  final List<XlsxRange>? ranges;

  /// The element as a whole.
  final OpaqueXml source;

  /// The rules, in file order.
  Iterable<X14Rule> get rules => children.whereType<X14Rule>();
}

/// The `x14:conditionalFormattings` the model types: the first in the first
/// `ext` of Excel's `uri`. Any other stays as written.
final class X14Block {
  const X14Block._(
    this._extLst,
    this._ext,
    this._source,
    this._qualifiedName,
    this._namespaces,
    this._attributes,
    this.children,
  );

  final XmlNode _extLst;
  final XmlNode _ext;
  final OpaqueXml _source;
  final String _qualifiedName;
  final Map<String, String> _namespaces;
  final List<KeptAttribute> _attributes;

  /// The children in order: an [X14Element] for each
  /// `x14:conditionalFormatting`, an [OpaqueXml] for everything else.
  final List<Object> children;

  /// The elements, in file order.
  Iterable<X14Element> get elements => children.whereType<X14Element>();

  /// The `extLst` without the rules [gone], and without an element left with
  /// no rule, a group left with nothing, an `ext` left with nothing, or, for
  /// the last of those, `null`. Everything else stays as written.
  XmlNode? withoutRules(Set<OpaqueXml> gone) {
    final List<OpaqueXml> kept = <OpaqueXml>[];
    for (final Object child in children) {
      if (child is! X14Element) {
        kept.add(child as OpaqueXml);
        continue;
      }
      if (!child.rules.any((X14Rule r) => gone.contains(r.source))) {
        kept.add(child.source);
      } else if (child.rules.any((X14Rule r) => !gone.contains(r.source))) {
        kept.add(
          _rewritten(
            child.source,
            child.qualifiedName,
            child.namespaces,
            child.attributes,
            <OpaqueXml>[
              for (final Object c in child.children)
                if (c is OpaqueXml)
                  c
                else if (!gone.contains((c as X14Rule).source))
                  c.source,
            ],
          ),
        );
      }
    }
    return _withKept(kept);
  }

  /// The `extLst` with each element's source mapped by [map]: kept, replaced,
  /// or removed (`null`), as [withoutRules] removes an element; the `extLst`'s
  /// own node when nothing changes.
  XmlNode? withElements(OpaqueXml? Function(X14Element element) map) {
    bool changed = false;
    final List<OpaqueXml> kept = <OpaqueXml>[];
    for (final Object child in children) {
      if (child is! X14Element) {
        kept.add(child as OpaqueXml);
        continue;
      }
      final OpaqueXml? next = map(child);
      changed |= !identical(next, child.source);
      if (next != null) kept.add(next);
    }
    return changed ? _withKept(kept) : _extLst;
  }

  XmlNode? _withKept(List<OpaqueXml> kept) {
    final List<Object> rest = <Object>[
      for (final Object c in _ext.children)
        if (!identical(c, _source))
          c
        else if (kept.isNotEmpty)
          _withChildren(kept),
    ];
    final XmlNode next = _extLst.replacingChild(
      _ext,
      rest.isEmpty ? null : _ext.withChildren(rest),
    );
    return next.children.isEmpty ? null : next;
  }

  OpaqueXml _withChildren(List<OpaqueXml> next) =>
      _rewritten(_source, _qualifiedName, _namespaces, _attributes, next);
}

/// The [X14Block] of [extLst], or `null` when it holds none. Each problem
/// goes to [warn], named `x14:cfRule` or `x14:conditionalFormatting`.
///
/// [checkRoom] is called with the number kept so far before each child of
/// the group is kept, and with its own count, across the elements, before
/// each child of an element but its first `xm:sqref`; it throws when the
/// file holds too many.
X14Block? readX14Block(
  XmlNode extLst, {
  void Function(String problem)? warn,
  void Function(int count)? checkRoom,
}) {
  final XmlNode? ext = _conditionalExt(extLst);
  final OpaqueXml? group = ext == null ? null : _groupOf(ext);
  if (ext == null || group == null) return null;
  final XmlPullReader r = readerOf(group);
  final String qualifiedName = r.qualifiedName;
  final Map<String, String> namespaces = Map<String, String>.of(
    r.declaredNamespaces,
  );
  final List<KeptAttribute> attributes = keepAttributes(r);
  final List<Object> children = <Object>[];
  int rules = 0;
  _eachChild(r, () {
    checkRoom?.call(children.length);
    final bool element =
        r.namespaceUri == Ns.x14 && r.localName == 'conditionalFormatting';
    final OpaqueXml source = OpaqueXml.capture(r);
    children.add(
      element
          ? _readElement(source, warn, () => checkRoom?.call(rules++))
          : source,
    );
  });
  return X14Block._(
    extLst,
    ext,
    group,
    qualifiedName,
    namespaces,
    attributes,
    children,
  );
}

/// [extLst] (`null` for none) with the `x14:conditionalFormatting` of
/// [rendered], the `extLst` the writer wrote for one format, after the
/// others: the `ext` and its group are made when absent, with [prefix] (with
/// its colon, or empty) in front of the names of SpreadsheetML.
XmlNode withX14Format(XmlNode? extLst, OpaqueXml rendered, String prefix) {
  final XmlNode made = XmlNode.read(
    readerOf(rendered),
    const <String, Set<String>>{
      'extLst': <String>{'ext'},
    },
  );
  final XmlNode madeExt = made.children.single as XmlNode;
  final XmlNode newExt = XmlNode(
    '${prefix}ext',
    'ext',
    madeExt.namespaces,
    madeExt.attributes,
    madeExt.children,
  );
  if (extLst == null) {
    return XmlNode.made(prefix, 'extLst', children: <Object>[newExt]);
  }
  final XmlNode? ext = _conditionalExt(extLst);
  if (ext == null) {
    return extLst.withChildren(<Object>[...extLst.children, newExt]);
  }
  final X14Block? block = readX14Block(extLst);
  if (block == null) {
    return extLst.replacingChild(
      ext,
      ext.withChildren(<Object>[...ext.children, madeExt.children.single]),
    );
  }
  final OpaqueXml group = block._withChildren(<OpaqueXml>[
    for (final Object c in block.children)
      c is X14Element ? c.source : c as OpaqueXml,
    readX14Block(made)!.elements.single.source,
  ]);
  return extLst.replacingChild(
    ext,
    ext.withChildren(<Object>[
      for (final Object c in ext.children)
        identical(c, block._source) ? group : c,
    ]),
  );
}

/// The first `ext` of [extLst] with the `uri` of conditional formats, in any
/// case, as a GUID is.
XmlNode? _conditionalExt(XmlNode extLst) {
  for (final Object c in extLst.children) {
    if (c is XmlNode &&
        c.localName == 'ext' &&
        c.attribute('uri')?.toUpperCase() == x14SheetExtUri.toUpperCase()) {
      return c;
    }
  }
  return null;
}

OpaqueXml? _groupOf(XmlNode ext) {
  for (final Object c in ext.children) {
    if (c is OpaqueXml &&
        c.namespaceUri == Ns.x14 &&
        c.localName == _groupName) {
      return c;
    }
  }
  return null;
}

/// [old], which keeps the bindings it inherited, as a start tag of
/// [qualifiedName] holding [children].
OpaqueXml _rewritten(
  OpaqueXml old,
  String qualifiedName,
  Map<String, String> namespaces,
  List<KeptAttribute> attributes,
  List<OpaqueXml> children,
) {
  final StringBuffer out = StringBuffer();
  final XmlWriter w = XmlWriter(out)..start('wrapper');
  writeNamespaceDeclarations(w, old.inheritedNamespaces);
  w.start(qualifiedName);
  writeNamespaceDeclarations(w, namespaces);
  final Map<String, String> inner = mergeNamespaces(
    old.inheritedNamespaces,
    namespaces,
  );
  writeKeptAttributes(w, attributes, declaredAbove: inner);
  for (final OpaqueXml child in children) {
    child.writeTo(w, declaredAbove: inner);
  }
  w
    ..end()
    ..end();
  // The elements were read under the file's depth limit, as in `readerOf`.
  final XmlPullReader r = XmlPullReader(out.toString(), maxDepth: 0x7FFFFFFF)
    ..next()
    ..next();
  return OpaqueXml.capture(r);
}

/// Calls [onChild], which consumes it, for each child of the element [r] is
/// on.
void _eachChild(XmlPullReader r, void Function() onChild) {
  final int depth = r.depth;
  while (r.next()) {
    if (r.eventType == XmlEventType.endElement && r.depth < depth) break;
    if (r.eventType == XmlEventType.startElement) onChild();
  }
}

X14Element _readElement(
  OpaqueXml source,
  void Function(String problem)? warn,
  void Function() onChild,
) {
  final XmlPullReader r = readerOf(source);
  final String qualifiedName = r.qualifiedName;
  final Map<String, String> namespaces = Map<String, String>.of(
    r.declaredNamespaces,
  );
  final List<KeptAttribute> attributes = keepAttributes(r);
  final List<Object> children = <Object>[];
  List<XlsxRange>? ranges;
  bool hasSqref = false;
  _eachChild(r, () {
    final bool rule = r.namespaceUri == Ns.x14 && r.localName == 'cfRule';
    final bool sqref = r.namespaceUri == Ns.xm && r.localName == 'sqref';
    if (!sqref || hasSqref) onChild();
    hasSqref = hasSqref || sqref;
    final OpaqueXml child = OpaqueXml.capture(r);
    if (rule) {
      final ({X14Rule rule, bool bad}) read = _readRule(child);
      if (read.bad) warn?.call('x14:cfRule');
      children.add(read.rule);
      return;
    }
    if (sqref && ranges == null) ranges = _readSqref(child);
    children.add(child);
  });
  if (ranges == null) warn?.call('x14:conditionalFormatting');
  return X14Element(
    qualifiedName,
    namespaces,
    attributes,
    children,
    ranges,
    source,
  );
}

/// The ranges of the `xm:sqref` [element], or `null` when the writer would
/// refuse them.
List<XlsxRange>? _readSqref(OpaqueXml element) {
  final List<XlsxRange>? ranges = parseSqref(childText(readerOf(element)));
  if (ranges == null) return null;
  return _writable(ranges, const XlsxDuplicateRule()) ? ranges : null;
}

/// Whether the writer takes [rule] on [ranges].
bool _writable(List<XlsxRange> ranges, XlsxConditionalRule rule) {
  try {
    checkConditionalFormat(
      XlsxConditionalFormat(ranges, <XlsxConditionalRule>[rule]),
    );
    return true;
  } on ArgumentError {
    return false;
  }
}

/// Whether the writer takes [rule] on any cell.
bool _writableRule(XlsxConditionalRule rule) =>
    _writable(<XlsxRange>[const XlsxRange(0, 0, 0, 0)], rule);

/// The [X14Rule] of [source], and whether it is a problem: no `id`, or a rule
/// of a kind the model reads that holds what cannot be read.
({X14Rule rule, bool bad}) _readRule(OpaqueXml source) {
  final XmlPullReader r = readerOf(source);
  String? attribute(String name) => r.getAttribute(name, namespaceUri: '');
  final String? idText = attribute('id');
  final String? id = idText == null || idText.isEmpty ? null : idText;
  final String? type = attribute('type');
  final String? operator = attribute('operator');
  final int? priority = readPriority(attribute('priority'));
  final bool stopIfTrue = readFlag(attribute('stopIfTrue'));

  final List<String> formulas = <String>[];
  bool hasBar = false;
  X14BarFields? fields;
  ({XlsxIconSet? set, bool custom})? icons;
  ReadDifferentialStyle? dxf;
  _eachChild(r, () {
    final bool x14 = r.namespaceUri == Ns.x14;
    if (r.namespaceUri == Ns.xm && r.localName == 'f') {
      formulas.add(childText(r));
    } else if (x14 && r.localName == 'dataBar' && !hasBar) {
      hasBar = true;
      fields = _readBar(r);
    } else if (x14 && r.localName == 'iconSet' && icons == null) {
      icons = _readIcons(r, stopIfTrue);
    } else if (x14 && r.localName == 'dxf' && dxf == null) {
      dxf = readDifferentialEntry(r);
    } else {
      r.skip();
    }
  });
  final ReadDifferentialStyle? read = dxf;
  final bool badStyle = read?.problem != null;
  XlsxConditionalRule? styled(XlsxConditionalRule? rule) =>
      rule == null || badStyle ? null : withRuleStyle(rule, read?.value);
  final X14BarFields? barFields = fields;
  final ({XlsxIconSet? set, bool custom})? iconRead = icons;
  XlsxConditionalRule? rule = switch (type) {
    'dataBar' => barFields?.alone(stopIfTrue),
    'iconSet' => iconRead?.set,
    'expression' =>
      formulas.isEmpty
          ? null
          : styled(XlsxExpressionRule(formulas.first, stopIfTrue: stopIfTrue)),
    'cellIs' => styled(cellValueRule(operator, formulas, stopIfTrue)),
    _ => null,
  };
  if (rule != null && !_writableRule(rule)) rule = null;
  final bool bad =
      id == null ||
      switch (type) {
        'dataBar' =>
          barFields == null || barFields.fillColor != null && rule == null,
        'iconSet' => iconRead == null || !iconRead.custom && rule == null,
        'expression' || 'cellIs' => rule == null,
        _ => false,
      };
  return (
    rule: X14Rule(
      id,
      id == null ? null : rule,
      priority,
      source,
      exact: read == null || read.exact,
      bar: id == null ? null : barFields,
    ),
    bad: bad,
  );
}

/// The fields of the `x14:dataBar` [r] is on, consuming it; `null` when one
/// cannot be read or the writer would refuse it.
X14BarFields? _readBar(XmlPullReader r) {
  String? attribute(String name) => r.getAttribute(name, namespaceUri: '');
  final String? minText = attribute('minLength');
  final String? maxText = attribute('maxLength');
  final int? minLength = minText == null ? null : readInt(minText, 0, 100);
  final int? maxLength = maxText == null ? null : readInt(maxText, 0, 100);
  final String? showText = attribute('showValue');
  final bool gradient = readFlag(attribute('gradient'), fallback: true);
  final bool border = readFlag(attribute('border'));
  final bool sameNegativeBorder = readFlag(
    attribute('negativeBarBorderColorSameAsPositive'),
    fallback: true,
  );
  final String? axisText = attribute('axisPosition');
  XlsxDataBarAxis? axis = axisText == null ? XlsxDataBarAxis.automatic : null;
  for (final XlsxDataBarAxis a in XlsxDataBarAxis.values) {
    if (a.name == axisText) axis = a;
  }
  bool bad =
      minText != null && minLength == null ||
      maxText != null && maxLength == null ||
      axis == null;
  final List<XlsxCfValue> points = <XlsxCfValue>[];
  final Map<String, XlsxColor> colors = <String, XlsxColor>{};
  _eachChild(r, () {
    final String? name = r.namespaceUri == Ns.x14 ? r.localName : null;
    if (name == 'cfvo') {
      final XlsxCfValue? point = _readPoint(r);
      if (point == null) {
        bad = true;
      } else {
        points.add(point);
      }
    } else if (name != null && name.endsWith('Color')) {
      final ReadStyleValue<XlsxColor?> color = readColor(r);
      final XlsxColor? value = color.value;
      if (value == null) {
        bad = true;
      } else {
        colors.putIfAbsent(name, () => value);
      }
    } else {
      r.skip();
    }
  });
  if (bad || points.length > 2) return null;
  final X14BarFields fields = X14BarFields(
    min: points.isEmpty ? null : points[0],
    max: points.length < 2 ? null : points[1],
    minLength: minLength,
    maxLength: maxLength,
    showValue: showText == null ? null : readFlag(showText, fallback: true),
    gradient: gradient,
    border: border,
    axis: axis!,
    fillColor: colors['fillColor'],
    borderColor: border ? colors['borderColor'] : null,
    negativeFillColor: colors['negativeFillColor'],
    negativeBorderColor: border && !sameNegativeBorder
        ? colors['negativeBorderColor']
        : null,
    axisColor: colors['axisColor'],
  );
  final bool crossing = (minLength ?? 0) > (maxLength ?? 100);
  final bool writable =
      !crossing &&
      _writableRule(
        XlsxDataBar(
          min: fields.min ?? const XlsxCfValue.min(),
          max: fields.max ?? const XlsxCfValue.max(),
          color: fields.fillColor ?? defaultBarAxisColor,
          borderColor: fields.borderColor,
          negativeFillColor: fields.negativeFillColor,
          negativeBorderColor: fields.negativeBorderColor,
          axisColor: fields.axisColor,
        ),
      );
  return writable ? fields : null;
}

/// The `x14:iconSet` [r] is on, consuming it: `custom` for one with its own
/// icons, which stays as written, and no `set` when it cannot be read.
({XlsxIconSet? set, bool custom}) _readIcons(XmlPullReader r, bool stopIfTrue) {
  String? attribute(String name) => r.getAttribute(name, namespaceUri: '');
  final String name = attribute('iconSet') ?? '3TrafficLights1';
  bool custom = readFlag(attribute('custom'));
  final bool reverse = readFlag(attribute('reverse'));
  final bool showValue = readFlag(attribute('showValue'), fallback: true);
  XlsxIconSetType? type;
  for (final XlsxIconSetType t in XlsxIconSetType.values) {
    if (t.xmlName == name) type = t;
  }
  bool bad = type == null;
  final List<XlsxCfValue> points = <XlsxCfValue>[];
  _eachChild(r, () {
    final String? child = r.namespaceUri == Ns.x14 ? r.localName : null;
    if (child == 'cfvo') {
      final XlsxCfValue? point = _readPoint(r);
      if (point == null) {
        bad = true;
      } else {
        points.add(point);
      }
    } else {
      if (child == 'cfIcon') custom = true;
      r.skip();
    }
  });
  if (custom) return (set: null, custom: true);
  if (bad) return (set: null, custom: false);
  return (
    set: XlsxIconSet(
      type!,
      thresholds: iconThresholds(type, points),
      reverse: reverse,
      showValue: showValue,
      stopIfTrue: stopIfTrue,
    ),
    custom: false,
  );
}

/// The value of the `x14:cfvo` [r] is on, consuming it; `null` for an unknown
/// `type`. `autoMin` and `autoMax` are the `min` and `max` the writer writes
/// as those.
XlsxCfValue? _readPoint(XmlPullReader r) {
  final String? type = r.getAttribute('type', namespaceUri: '');
  final bool gte = readFlag(
    r.getAttribute('gte', namespaceUri: ''),
    fallback: true,
  );
  String? value;
  _eachChild(r, () {
    if (r.namespaceUri == Ns.xm && r.localName == 'f') {
      final String text = childText(r);
      value ??= text;
    } else {
      r.skip();
    }
  });
  final String? name = switch (type) {
    'autoMin' => 'min',
    'autoMax' => 'max',
    _ => type,
  };
  for (final XlsxCfValueType t in XlsxCfValueType.values) {
    if (t.xmlName == name) {
      return XlsxCfValue(t, value: value, greaterOrEqual: gte);
    }
  }
  return null;
}

/// Adds to [rules] the `id` of each `x14:cfRule` in [element], and to
/// [links] the text of each `x14:id`. Never throws.
void collectX14Ids(OpaqueXml element, Set<String> rules, Set<String> links) {
  final XmlPullReader r = readerOf(element);
  final int depth = r.depth;
  do {
    if (r.eventType == XmlEventType.endElement && r.depth < depth) break;
    if (r.eventType != XmlEventType.startElement || r.namespaceUri != Ns.x14) {
      continue;
    }
    if (r.localName == 'cfRule') {
      final String? id = r.getAttribute('id', namespaceUri: '');
      if (id != null) rules.add(id);
    } else if (r.localName == 'id') {
      links.add(childText(r));
    }
  } while (r.next());
}

/// One rule of a [JoinedFormat].
final class JoinedRule {
  /// A rule of [entry], the 2007 rule if it has one, and of [halves].
  const JoinedRule(this.entry, this.halves);

  /// The 2007 rule, or `null` for a rule of the `extLst` alone.
  final CfRuleEntry? entry;

  /// The Excel 2010 rules: those the 2007 rule names, or the rule itself.
  final List<X14Rule> halves;

  /// The rule's priority, or `null` for none.
  int? get priority => entry?.priority ?? halves.first.priority;

  /// The value of the rule, given [plain], the 2007 rule with its style.
  XlsxConditionalRule value(XlsxConditionalRule? plain) {
    if (plain == null) return halves.single.rule!;
    if (plain is! XlsxDataBar) return plain;
    for (final X14Rule half in halves) {
      final X14BarFields? bar = half.bar;
      if (bar != null) return bar.over(plain);
    }
    return plain;
  }
}

/// One format of the sheet, as `conditionalFormats` lists it.
final class JoinedFormat {
  /// A format on [ranges], of the 2007 element [item] if it has one.
  JoinedFormat(this.item, this.ranges, this.rules);

  /// The 2007 element, or `null` for a format of the `extLst` alone.
  final GroupItem<CfEntry>? item;

  /// The cells.
  final List<XlsxRange> ranges;

  /// The rules, in the order the format lists them.
  final List<JoinedRule> rules;

  /// The rules of the `extLst` alone waiting for [_placePending].
  final List<X14Rule> _pending = <X14Rule>[];

  /// Puts each rule of [_pending] before the first rule of a higher priority,
  /// else last, and one with no priority after all of them, in one pass: a
  /// file may hold any number, on one `sqref`.
  void _placePending() {
    if (_pending.isEmpty) return;
    final List<(int, int, X14Rule)> ordered = <(int, int, X14Rule)>[
      for (int i = 0; i < _pending.length; i++)
        if (_pending[i].priority != null)
          (_pending[i].priority!, i, _pending[i]),
    ];
    // The index keeps equal priorities in file order.
    ordered.sort(
      ((int, int, X14Rule) a, (int, int, X14Rule) b) =>
          a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2),
    );
    JoinedRule alone(X14Rule rule) => JoinedRule(null, <X14Rule>[rule]);
    final List<JoinedRule> placed = <JoinedRule>[];
    int next = 0;
    for (final JoinedRule rule in rules) {
      final int priority = rule.priority!;
      while (next < ordered.length && ordered[next].$1 < priority) {
        placed.add(alone(ordered[next++].$3));
      }
      placed.add(rule);
    }
    while (next < ordered.length) {
      placed.add(alone(ordered[next++].$3));
    }
    placed.addAll(_pending.where((X14Rule r) => r.priority == null).map(alone));
    rules
      ..clear()
      ..addAll(placed);
    _pending.clear();
  }
}

/// The formats of [block] and [x14], as the library comment says. [links]
/// holds the ids the 2007 elements nobody lists name: their rules are halves
/// of a format that is not listed.
List<JoinedFormat> joinConditionalFormats(
  CfBlock? block,
  X14Block? x14,
  Set<String> links,
) {
  final Map<String, List<X14Rule>> byId = <String, List<X14Rule>>{};
  for (final X14Element element in x14?.elements ?? const <X14Element>[]) {
    for (final X14Rule rule in element.rules) {
      final String? id = rule.id?.toUpperCase();
      if (id != null) (byId[id] ??= <X14Rule>[]).add(rule);
    }
  }
  final Set<String> named = <String>{
    for (final String id in links) id.toUpperCase(),
  };
  final List<JoinedFormat> formats = <JoinedFormat>[];
  // The first format of each `sqref`, as a file may hold any number of them.
  final Map<String, JoinedFormat> bySqref = <String, JoinedFormat>{};
  for (final GroupItem<CfEntry> item
      in block?.items ?? const <GroupItem<CfEntry>>[]) {
    final CfEntry? entry = item.value;
    if (entry == null) continue;
    final List<JoinedRule> rules = <JoinedRule>[];
    for (final CfRuleEntry rule in entry.rules) {
      final String? id = rule.x14Id?.toUpperCase();
      if (id != null) named.add(id);
      rules.add(JoinedRule(rule, byId[id] ?? const <X14Rule>[]));
    }
    final JoinedFormat format = JoinedFormat(item, entry.ranges, rules);
    formats.add(format);
    bySqref.putIfAbsent(_sqrefKey(entry.ranges), () => format);
  }
  for (final X14Element element in x14?.elements ?? const <X14Element>[]) {
    final List<XlsxRange>? ranges = element.ranges;
    if (ranges == null) continue;
    for (final X14Rule rule in element.rules) {
      if (rule.rule == null || named.contains(rule.id?.toUpperCase())) {
        continue;
      }
      final JoinedFormat target = bySqref.putIfAbsent(_sqrefKey(ranges), () {
        final JoinedFormat own = JoinedFormat(null, ranges, <JoinedRule>[]);
        formats.add(own);
        return own;
      });
      target._pending.add(rule);
    }
  }
  for (final JoinedFormat format in formats) {
    format._placePending();
  }
  return formats;
}

/// The key of [ranges]: equal ranges in equal order have equal keys.
String _sqrefKey(List<XlsxRange> ranges) =>
    ranges.map((XlsxRange r) => r.ref).join(' ');

/// The `x14:conditionalFormatting` [source] after a structural edit, as
/// `shiftedValidation` shifts a validation: its `xm:sqref`, and every
/// `xm:f` of its rules relative to the first cell of the `xm:sqref`; `null`
/// when the edit empties the `xm:sqref`, [source] itself when nothing
/// changes (or it has no `xm:sqref`).
OpaqueXml? shiftedX14Element(
  OpaqueXml source,
  ReferenceMapper mapper,
  String host,
  void Function(String text) onUnlexable,
) {
  String? sqref;
  final XmlPullReader r = readerOf(source);
  _eachChild(r, () {
    if (sqref == null && r.namespaceUri == Ns.xm && r.localName == 'sqref') {
      sqref = childText(r);
    } else {
      r.skip();
    }
  });
  final String? read = sqref;
  if (read == null) return source;
  final String? nextSqref = rewriteSqref(
    read.trim(),
    mapper,
    host,
    onUnlexable: onUnlexable,
  );
  if (nextSqref != null && nextSqref.isEmpty) return null;
  final String after = nextSqref ?? read;
  String? formula(String text) => rewriteAnchoredFormula(
    text,
    mapper,
    host,
    read,
    after,
    onUnlexable: onUnlexable,
  );
  bool sqrefSeen = false;
  return spliceElement(source, (XmlPullReader r, int level) {
    if (r.namespaceUri != Ns.xm) return null;
    if (level == 1 && r.localName == 'sqref' && !sqrefSeen) {
      sqrefSeen = true;
      return nextSqref == null
          ? null
          : SpliceEdit(text: (String _) => escapeXmlText(nextSqref));
    }
    if (r.localName == 'f') {
      return SpliceEdit(
        text: (String text) => rewrittenFormulaMarkup(text, formula),
      );
    }
    return null;
  });
}
