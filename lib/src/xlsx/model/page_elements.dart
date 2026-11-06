/// Reading and editing the `printOptions`, `pageMargins`, `pageSetup` and
/// `headerFooter` elements, and `sheetPr/pageSetUpPr`, as
/// [XlsxPageSetup] and [XlsxHeaderFooter] values.
///
/// Not ported from Quds; written for jet_office.
///
/// A page setup is spread over four elements: `printOptions` (centering,
/// headings, gridlines), `pageMargins`, `pageSetup` and the `fitToPage` flag
/// of `sheetPr/pageSetUpPr`. Reading gives a field the value its element
/// states. A field with a bad value (`orientation="sideways"`,
/// `left="abc"`, a scale of 900) reads as its default and is reported once
/// per element; the element stays as written. `fitToWidth` and
/// `fitToHeight` are read only under `fitToPage`, a `firstPageNumber` only
/// under `useFirstPageNumber`, and a `scale` not under fitting, as Excel
/// uses them, so a value read is one the writer accepts.
///
/// A new element is the one the writer writes for the value
/// ([writePageSetup], [writeHeaderFooter]). An existing one keeps what the
/// value does not cover (`r:id`, `horizontalDpi`, `copies`, `errors`,
/// `gridLinesSet`, other children) and changes an attribute only when its
/// meaning changes: an attribute whose effective value is already the wanted
/// one keeps its spelling (`paperSize="1"`, `headings="true"`). An element
/// the new value does not need goes, when nothing is left in it.
///
/// A header or footer text is stored as an `ST_Xstring`: `_xHHHH_` is
/// decoded when it is read. A text the writer would refuse (too long, a
/// character XML forbids after decoding, a lone `&` at its end) reads as
/// absent and is reported.
library;

import '../../opc/ooxml.dart';
import '../../opc/opaque_xml.dart';
import '../../xml/xml_escape.dart';
import '../../xml/xml_number.dart';
import '../../xml/xml_pull_reader.dart';
import '../header_footer.dart';
import '../limits.dart';
import '../page_setup.dart';
import 'element_node.dart';
import 'item_group.dart';
import 'worksheet_part.dart' show worksheetNodeShape;

/// Reports that [element] holds a value that could not be read.
typedef ProblemReporter = void Function(String element);

/// The four typed elements a page setup is spread over, each `null` when
/// the sheet has none.
typedef PageSetupNodes = ({
  XmlNode? options,
  XmlNode? margins,
  XmlNode? setup,
  XmlNode? sheetPr,
});

// -- Parsing the attributes -------------------------------------------------

final RegExp _wholeNumber = RegExp(r'^\+?\d+$');
final RegExp _decimalNumber = RegExp(r'^\+?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$');

/// `1`, `true`, `0` or `false` as a boolean; `null` for anything else,
/// absent included.
bool? _parseBool(String? text) => switch (text) {
  '1' || 'true' => true,
  '0' || 'false' => false,
  _ => null,
};

/// A whole number from [min] to [max], or `null`.
int? _parseInt(String? text, int min, int max) {
  if (text == null || !_wholeNumber.hasMatch(text)) return null;
  final int? v = int.tryParse(text);
  return v == null || v < min || v > max ? null : v;
}

/// A finite margin of at least 0, or `null`.
double? _parseMargin(String? text) {
  if (text == null || !_decimalNumber.hasMatch(text)) return null;
  final double? v = double.tryParse(text);
  return v == null || !v.isFinite ? null : v;
}

XlsxOrientation? _parseOrientation(String? text) => switch (text) {
  'portrait' => XlsxOrientation.portrait,
  'landscape' => XlsxOrientation.landscape,
  _ => null,
};

bool _flag(XmlNode? node, String name) =>
    _parseBool(node?.attribute(name)) ?? false;

/// Whether [sheetPr] says the sheet is fitted to pages.
bool _fitToPage(XmlNode? sheetPr) =>
    _flag(sheetPr?.child('pageSetUpPr'), 'fitToPage');

/// The first page number [node] states: `null` unless `useFirstPageNumber`
/// is on, and then `firstPageNumber` (1 when absent), or `null` when that
/// is not a valid number.
int? _storedFirst(XmlNode? node) {
  if (!_flag(node, 'useFirstPageNumber')) return null;
  final String? text = node?.attribute('firstPageNumber');
  return text == null ? 1 : _parseInt(text, 1, XlsxLimits.maxFirstPageNumber);
}

// -- Reading a page setup ---------------------------------------------------

/// The page setup the four elements state, or `null` when the sheet has no
/// `printOptions`, `pageMargins` or `pageSetup`.
///
/// [bad] is told the element name (`printOptions`, `pageMargins`,
/// `pageSetup`) of each field that could not be read.
XlsxPageSetup? readPageSetup(PageSetupNodes nodes, ProblemReporter bad) {
  final XmlNode? options = nodes.options;
  final XmlNode? margins = nodes.margins;
  final XmlNode? setup = nodes.setup;
  if (options == null && margins == null && setup == null) return null;

  bool flag(XmlNode? node, String element, String name) {
    final String? text = node?.attribute(name);
    if (text == null) return false;
    final bool? v = _parseBool(text);
    if (v == null) bad(element);
    return v ?? false;
  }

  double margin(String name, double fallback) {
    final String? text = margins?.attribute(name);
    if (text == null) return fallback;
    final double? v = _parseMargin(text);
    if (v == null) {
      bad('pageMargins');
      return fallback;
    }
    return v;
  }

  int? number(String name, int min, int max) {
    final String? text = setup?.attribute(name);
    if (text == null) return null;
    final int? v = _parseInt(text, min, max);
    if (v == null) bad('pageSetup');
    return v;
  }

  final String? fitText = nodes.sheetPr
      ?.child('pageSetUpPr')
      ?.attribute('fitToPage');
  final bool fit = _parseBool(fitText) ?? false;
  if (fitText != null && _parseBool(fitText) == null) bad('pageSetup');
  int? axis(String name) {
    if (!fit) return null;
    final String? text = setup?.attribute(name);
    if (text == null) return 1;
    final int? v = _parseInt(text, 0, XlsxLimits.maxFitToPages);
    if (v == null) {
      bad('pageSetup');
      return 1;
    }
    return v == 0 ? null : v;
  }

  final int? fitToWidth = axis('fitToWidth');
  final int? fitToHeight = axis('fitToHeight');
  final bool fitting = fitToWidth != null || fitToHeight != null;

  int? first;
  if (flag(setup, 'pageSetup', 'useFirstPageNumber')) {
    final String? text = setup?.attribute('firstPageNumber');
    first = text == null
        ? 1
        : number('firstPageNumber', 1, XlsxLimits.maxFirstPageNumber);
  }

  final String? orderText = setup?.attribute('pageOrder');
  XlsxPageOrder? order;
  if (orderText == 'overThenDown') {
    order = XlsxPageOrder.overThenDown;
  } else if (orderText != null && orderText != 'downThenOver') {
    bad('pageSetup');
  }

  final String? orientationText = setup?.attribute('orientation');
  final XlsxOrientation? orientation = _parseOrientation(orientationText);
  if (orientationText != null && orientation == null) bad('pageSetup');

  final int? paper = number('paperSize', 1, XlsxLimits.maxPaperSize);
  final int? scale = number(
    'scale',
    XlsxLimits.minPageScale,
    XlsxLimits.maxPageScale,
  );

  const XlsxPageMargins d = XlsxPageMargins();
  return XlsxPageSetup(
    orientation: orientation,
    paperSize: paper == null ? null : XlsxPaperSize(paper),
    scale: fitting ? null : scale,
    fitToWidth: fitToWidth,
    fitToHeight: fitToHeight,
    firstPageNumber: first,
    pageOrder: order,
    blackAndWhite: flag(setup, 'pageSetup', 'blackAndWhite'),
    draft: flag(setup, 'pageSetup', 'draft'),
    margins: XlsxPageMargins(
      left: margin('left', d.left),
      right: margin('right', d.right),
      top: margin('top', d.top),
      bottom: margin('bottom', d.bottom),
      header: margin('header', d.header),
      footer: margin('footer', d.footer),
    ),
    centerHorizontally: flag(options, 'printOptions', 'horizontalCentered'),
    centerVertically: flag(options, 'printOptions', 'verticalCentered'),
    printGridLines: flag(options, 'printOptions', 'gridLines'),
    printHeadings: flag(options, 'printOptions', 'headings'),
  );
}

// -- Editing a page setup ---------------------------------------------------

/// The attributes of each element the writer writes for [value], by
/// element name.
Map<String, Map<String, String>> _written(XlsxPageSetup value) {
  final Map<String, Map<String, String>> out = <String, Map<String, String>>{};
  for (final OpaqueXml e in renderElements((w) => writePageSetup(w, value))) {
    out[e.localName] = <String, String>{
      for (final KeptAttribute a in keepAttributes(readerOf(e)))
        a.qualifiedName: a.value,
    };
  }
  return out;
}

/// The elements of [nodes] made to state [value] (already checked);
/// [prefix] is the worksheet's element prefix, with its colon, or empty.
///
/// A slot whose element needs no change is returned as it is, so the caller
/// finds out by identity what to edit.
PageSetupNodes applyPageSetup(
  PageSetupNodes nodes,
  XlsxPageSetup value,
  String prefix,
) {
  final Map<String, Map<String, String>> written = _written(value);
  return (
    options: _applyOptions(
      nodes.options,
      value,
      written['printOptions'],
      prefix,
    ),
    margins: _applyMargins(
      nodes.margins,
      value,
      written['pageMargins']!,
      prefix,
    ),
    setup: _applySetup(nodes, value, written['pageSetup'], prefix),
    sheetPr: nodes.sheetPr,
  );
}

/// [nodes] with the page setup removed: no `printOptions`, `pageMargins`
/// or `pageSetup`. The `sheetPr` is not changed here; see [sheetPrFit].
PageSetupNodes removePageSetup(PageSetupNodes nodes) =>
    (options: null, margins: null, setup: null, sheetPr: nodes.sheetPr);

XmlNode? _applyOptions(
  XmlNode? node,
  XlsxPageSetup value,
  Map<String, String>? written,
  String prefix,
) {
  if (node == null) {
    return written == null
        ? null
        : XmlNode.made(prefix, 'printOptions', attributes: written);
  }
  final XmlNode next = node.withChanges(<String, String?>{
    for (final MapEntry<String, bool> f in <String, bool>{
      'horizontalCentered': value.centerHorizontally,
      'verticalCentered': value.centerVertically,
      'headings': value.printHeadings,
      'gridLines': value.printGridLines,
    }.entries)
      if (_flag(node, f.key) != f.value) f.key: f.value ? '1' : null,
  });
  return !identical(next, node) && next.isBare ? null : next;
}

XmlNode _applyMargins(
  XmlNode? node,
  XlsxPageSetup value,
  Map<String, String> written,
  String prefix,
) {
  if (node == null) {
    return XmlNode.made(prefix, 'pageMargins', attributes: written);
  }
  const XlsxPageMargins d = XlsxPageMargins();
  final XlsxPageMargins m = value.margins;
  final List<(String, double, double)> fields = <(String, double, double)>[
    ('left', m.left, d.left),
    ('right', m.right, d.right),
    ('top', m.top, d.top),
    ('bottom', m.bottom, d.bottom),
    ('header', m.header, d.header),
    ('footer', m.footer, d.footer),
  ];
  return node.withChanges(<String, String?>{
    for (final (String, double, double) f in fields)
      if ((_parseMargin(node.attribute(f.$1)) ?? f.$3) != f.$2)
        f.$1: formatXmlDouble(f.$2),
  });
}

XmlNode? _applySetup(
  PageSetupNodes nodes,
  XlsxPageSetup value,
  Map<String, String>? written,
  String prefix,
) {
  final XmlNode? node = nodes.setup;
  if (node == null) {
    return written == null
        ? null
        : XmlNode.made(prefix, 'pageSetup', attributes: written);
  }
  final Map<String, String?> changes = <String, String?>{};
  final int paper = value.paperSize?.id ?? 1;
  if ((_parseInt(node.attribute('paperSize'), 1, XlsxLimits.maxPaperSize) ??
          1) !=
      paper) {
    changes['paperSize'] = paper == 1 ? null : '$paper';
  }
  if (_parseOrientation(node.attribute('orientation')) != value.orientation) {
    changes['orientation'] = value.orientation?.name;
  }
  final bool over = value.pageOrder == XlsxPageOrder.overThenDown;
  if ((node.attribute('pageOrder') == 'overThenDown') != over) {
    changes['pageOrder'] = over ? 'overThenDown' : null;
  }
  if (_flag(node, 'blackAndWhite') != value.blackAndWhite) {
    changes['blackAndWhite'] = value.blackAndWhite ? '1' : null;
  }
  if (_flag(node, 'draft') != value.draft) {
    changes['draft'] = value.draft ? '1' : null;
  }
  final int? first = value.firstPageNumber;
  if (_storedFirst(node) != first) {
    changes['useFirstPageNumber'] = first == null ? null : '1';
    changes['firstPageNumber'] = first == null ? null : '$first';
  }
  if (pageSetupFitsToPage(value)) {
    for (final (String, int?) axis in <(String, int?)>[
      ('fitToWidth', value.fitToWidth),
      ('fitToHeight', value.fitToHeight),
    ]) {
      final int wanted = axis.$2 ?? 0;
      final int stored =
          _parseInt(node.attribute(axis.$1), 0, XlsxLimits.maxFitToPages) ?? 1;
      if (stored != wanted) changes[axis.$1] = '$wanted';
    }
  } else {
    final int scale = value.scale ?? 100;
    final int stored =
        _parseInt(
          node.attribute('scale'),
          XlsxLimits.minPageScale,
          XlsxLimits.maxPageScale,
        ) ??
        100;
    if (stored != scale) changes['scale'] = scale == 100 ? null : '$scale';
    if (_fitToPage(nodes.sheetPr)) {
      changes['fitToWidth'] = null;
      changes['fitToHeight'] = null;
    }
  }
  final XmlNode next = node.withChanges(changes);
  return !identical(next, node) && next.isBare ? null : next;
}

/// [sheetPr] (`null` for none) with `pageSetUpPr fitToPage` on when
/// [fit], else off: the element is created when it is wanted, an attribute
/// goes when it is not, and `pageSetUpPr` and `sheetPr` go when nothing is
/// left in them. Returns [sheetPr] itself when the flag already says [fit].
/// [order] is the schema order of the children of `sheetPr`.
XmlNode? sheetPrFit(
  XmlNode? sheetPr,
  bool fit,
  String prefix,
  List<String> order,
) {
  if (_fitToPage(sheetPr) == fit) return sheetPr;
  final XmlNode? old = sheetPr?.child('pageSetUpPr');
  final XmlNode? pageSetUpPr = fit
      ? (old ?? XmlNode.made(prefix, 'pageSetUpPr')).withChanges(
          const <String, String?>{'fitToPage': '1'},
        )
      : old?.withChanges(const <String, String?>{'fitToPage': null});
  return sheetPrWith(
    sheetPr,
    prefix,
    'pageSetUpPr',
    pageSetUpPr == null || pageSetUpPr.isBare ? null : pageSetUpPr,
    order,
  );
}

/// [sheetPr] (`null` for none) with its child named [name] made [child]
/// (`null` removes it): `sheetPr` is created in a new element when it is
/// missing and `child` is wanted, a new child goes in [order] position, and
/// the element goes when nothing is left in it. Returns [sheetPr] itself
/// when there is nothing to do.
XmlNode? sheetPrWith(
  XmlNode? sheetPr,
  String prefix,
  String name,
  XmlNode? child,
  List<String> order,
) {
  final XmlNode? old = sheetPr?.child(name);
  XmlNode next;
  if (sheetPr == null) {
    if (child == null) return null;
    next = XmlNode.made(prefix, 'sheetPr', children: <Object>[child]);
  } else if (old != null) {
    next = sheetPr.replacingChild(old, child);
  } else if (child != null) {
    next = sheetPr.withChildInOrder(child, order);
  } else {
    return sheetPr;
  }
  return next.isBare ? null : next;
}

// -- Headers and footers ----------------------------------------------------

/// The six text elements of `headerFooter`, in schema order.
const List<String> _textNames = <String>[
  'oddHeader',
  'oddFooter',
  'evenHeader',
  'evenFooter',
  'firstHeader',
  'firstFooter',
];

bool _isTextChild(Object child) =>
    child is OpaqueXml &&
    child.namespaceUri == Ns.main &&
    _textNames.contains(child.localName);

/// The character data directly inside [element], not decoded.
String _rawText(OpaqueXml element) {
  final XmlPullReader r = readerOf(element);
  final StringBuffer out = StringBuffer();
  int level = 0;
  while (r.next()) {
    switch (r.eventType) {
      case XmlEventType.startElement:
        level++;
      case XmlEventType.endElement:
        if (level == 0) return out.toString();
        level--;
      case XmlEventType.characters || XmlEventType.cdata:
        if (level == 0) out.write(r.text);
      default:
    }
  }
  return out.toString();
}

/// The text of the first child named [name] of [node], decoded, or `null`
/// when there is none or the writer would refuse it (reported through
/// [bad]).
String? _textOf(XmlNode node, String name, ProblemReporter? bad) {
  for (final Object c in node.children) {
    if (c is OpaqueXml && c.namespaceUri == Ns.main && c.localName == name) {
      try {
        final String text = decodeXstring(_rawText(c));
        checkHeaderFooter(XlsxHeaderFooter(oddHeader: text));
        return text;
      } on ArgumentError {
        bad?.call('headerFooter');
      } on XmlParseException {
        bad?.call('headerFooter');
      }
      return null;
    }
  }
  return null;
}

/// The headers and footers [node], a `headerFooter`, states.
///
/// `differentOddEven` and `differentFirst` read `null` when the writer
/// derives the same value from the texts, so a value set reads back equal.
XlsxHeaderFooter readHeaderFooter(XmlNode node, ProblemReporter bad) {
  bool flag(String name, bool fallback) {
    final String? text = node.attribute(name);
    if (text == null) return fallback;
    final bool? v = _parseBool(text);
    if (v == null) bad('headerFooter');
    return v ?? fallback;
  }

  final String? oddHeader = _textOf(node, 'oddHeader', bad);
  final String? oddFooter = _textOf(node, 'oddFooter', bad);
  final String? evenHeader = _textOf(node, 'evenHeader', bad);
  final String? evenFooter = _textOf(node, 'evenFooter', bad);
  final String? firstHeader = _textOf(node, 'firstHeader', bad);
  final String? firstFooter = _textOf(node, 'firstFooter', bad);
  final bool oddEven = flag('differentOddEven', false);
  final bool first = flag('differentFirst', false);
  final bool derivedOddEven = evenHeader != null || evenFooter != null;
  final bool derivedFirst = firstHeader != null || firstFooter != null;
  return XlsxHeaderFooter(
    oddHeader: oddHeader,
    oddFooter: oddFooter,
    evenHeader: evenHeader,
    evenFooter: evenFooter,
    firstHeader: firstHeader,
    firstFooter: firstFooter,
    differentOddEven: oddEven == derivedOddEven ? null : oddEven,
    differentFirst: first == derivedFirst ? null : first,
    scaleWithDocument: flag('scaleWithDoc', true),
    alignWithMargins: flag('alignWithMargins', true),
  );
}

/// [node] (a `headerFooter`, or `null` for none) made to state [value]
/// (already checked), or `null` when no element is left.
///
/// A new element is the writer's, and none when the writer writes none. An
/// existing one has its text children replaced (a child already holding the
/// wanted text stays as written), its flags changed where their meaning
/// does, and keeps every other attribute and child. Returns [node] itself
/// when nothing changes.
XmlNode? applyHeaderFooter(
  XmlNode? node,
  XlsxHeaderFooter value,
  String prefix,
) {
  final List<OpaqueXml> rendered = renderElements(
    (w) => writeHeaderFooter(w, value),
  );
  final XmlNode? written = rendered.isEmpty
      ? null
      : XmlNode.read(readerOf(rendered.single), worksheetNodeShape);
  if (node == null) {
    return written == null
        ? null
        : XmlNode.made(
            prefix,
            'headerFooter',
            attributes: <String, String>{
              for (final KeptAttribute a in written.attributes)
                a.qualifiedName: a.value,
            },
            children: written.children,
          );
  }
  bool stored(String name, bool fallback) =>
      _parseBool(node.attribute(name)) ?? fallback;
  bool wanted(String name, bool fallback) =>
      _parseBool(written?.attribute(name)) ?? fallback;
  final Map<String, String?> changes = <String, String?>{
    for (final (String, bool) f in <(String, bool)>[
      ('differentOddEven', false),
      ('differentFirst', false),
      ('scaleWithDoc', true),
      ('alignWithMargins', true),
    ])
      if (stored(f.$1, f.$2) != wanted(f.$1, f.$2))
        f.$1: wanted(f.$1, f.$2) == f.$2
            ? null
            : '${wanted(f.$1, f.$2) ? 1 : 0}',
  };
  final List<Object> children = <Object>[
    for (final String name in _textNames) ?_textChild(node, written, name),
    for (final Object c in node.children)
      if (!_isTextChild(c)) c,
  ];
  bool sameChildren = children.length == node.children.length;
  for (int i = 0; sameChildren && i < children.length; i++) {
    sameChildren = identical(children[i], node.children[i]);
  }
  final XmlNode attributesChanged = node.withChanges(changes);
  if (sameChildren && identical(attributesChanged, node)) return node;
  final XmlNode next = attributesChanged.withChildren(children);
  return next.isBare ? null : next;
}

/// The child that states the text [name] of the new element [written]: the
/// existing one when it holds that very text, else the written one.
Object? _textChild(XmlNode node, XmlNode? written, String name) {
  Object? make;
  String? wantedText;
  if (written != null) {
    for (final Object c in written.children) {
      if (c is OpaqueXml && c.localName == name) {
        make = c;
        wantedText = decodeXstring(_rawText(c));
      }
    }
  }
  if (make == null) return null;
  for (final Object c in node.children) {
    if (c is OpaqueXml && c.namespaceUri == Ns.main && c.localName == name) {
      if (_textOf(node, name, null) == wantedText) return c;
      break;
    }
  }
  return make;
}
