/// The main document part, `word/document.xml`, read into the body model.
///
/// Not ported from Quds; written for jet_office.
///
/// [DocumentPart.read] walks the part once with the pull reader. It types
/// `w:p`, its `w:pPr` (the style) and its runs; a run's `w:rPr` (the
/// style), text, tabs, breaks and carriage returns. Everything else is kept
/// as written, in place: blocks other than paragraphs (tables, content
/// controls, bookmarks) as opaque blocks, other paragraph children (tracked
/// changes, hyperlinks, proofing marks) as opaque inlines, other run
/// children (drawings, fields, `mc:AlternateContent`) as opaque run
/// content, and unknown attributes on `w:body`, `w:p`, `w:r`, `w:t`,
/// `w:tab`, `w:br` and `w:cr` as kept attributes. The visible text of an
/// opaque inline is collected while it is captured, so its slice is parsed
/// once, under the part's own depth limit.
///
/// Elements match by namespace URI and local name, never by prefix: a
/// document written with `ns0:` or a default namespace reads the same.
/// Strict WordprocessingML never gets here; the package refuses it.
library;

import '../opc/ooxml.dart' show Ns;
import '../opc/opaque_xml.dart';
import '../xml/xml_pull_reader.dart';
import 'model/blocks.dart';
import 'model/inlines.dart';
import 'model/run_content.dart';
import 'properties.dart';
import 'read_exception.dart';
import 'read_limits.dart';
import 'warnings.dart';

/// The paragraph properties the reader types: the style.
const Set<String> _pPrTyped = <String>{'pStyle'};

/// The run properties the reader types: the style.
const Set<String> _rPrTyped = <String>{'rStyle'};

/// The main document part: the root's start tag, what surrounds the body,
/// and the body's blocks.
final class DocumentPart {
  DocumentPart._(
    this.root,
    this.beforeBody,
    this.bodyAttributes,
    this.blocks,
    this.finalSectPr,
    this.afterBody,
  );

  /// Reads the part from [r], which must not have been advanced, and
  /// consumes it to the end of the root element.
  ///
  /// [partName] is the part's absolute name, for errors. [limits] bounds
  /// every text: a `w:t`, or the visible text of an opaque inline, longer
  /// than [DocxReadLimits.maxTextLength] throws a [DocxReadException] of
  /// [DocxReadFailure.limitExceeded]. A root that is not `w:document`
  /// throws one of [DocxReadFailure.malformedXml]. [warnings] receives the
  /// problems the reader repairs; D1 repairs none in this part.
  ///
  /// XML that is not well-formed, nested deeper than the reader allows or
  /// holds an entity that cannot be decoded throws [XmlParseException]:
  /// call this inside `DocxPackage.guard`, which turns it into a
  /// [DocxReadException].
  static DocumentPart read(
    XmlPullReader r,
    DocxWarningCollector warnings,
    String partName, {
    required DocxReadLimits limits,
  }) => _PartReader(r, partName, limits.maxTextLength).read();

  /// The root element's start tag: its name, namespace declarations and
  /// attributes (`mc:Ignorable` among them), so the part is written back
  /// with every binding its kept content uses.
  final XmlRoot root;

  /// The children of `w:document` before `w:body`, such as `w:background`,
  /// in order.
  final List<OpaqueXml> beforeBody;

  /// The attributes of `w:body`, in source order; empty without a body.
  final List<KeptAttribute> bodyAttributes;

  /// The body's blocks in order: paragraphs and opaque blocks. The final
  /// `w:sectPr` is not one of them; see [finalSectPr].
  final List<DocxBlock> blocks;

  /// The body's last child when it is a `w:sectPr`: the section properties
  /// of the last section. A `w:sectPr` anywhere else in the body is an
  /// opaque block, and one in a paragraph's `w:pPr` stays there.
  final OpaqueXml? finalSectPr;

  /// The children of `w:document` after `w:body`, in order. A second
  /// `w:body` is one of them.
  final List<OpaqueXml> afterBody;
}

/// One read of a document part.
final class _PartReader {
  _PartReader(this._r, this._partName, this._maxTextLength);

  final XmlPullReader _r;
  final String _partName;
  final int _maxTextLength;

  /// The index in the body of the block being read, for errors.
  int _blockIndex = 0;

  DocumentPart read() {
    final XmlPullReader r = _r;
    while (r.next()) {
      if (r.eventType == XmlEventType.startElement) break;
    }
    if (r.eventType != XmlEventType.startElement || !_isW(r, 'document')) {
      throw DocxReadException(
        DocxReadFailure.malformedXml,
        'The main document part has no w:document root element.',
        part: _partName,
      );
    }
    final XmlRoot root = XmlRoot.capture(r);
    final List<OpaqueXml> before = <OpaqueXml>[];
    final List<OpaqueXml> after = <OpaqueXml>[];
    List<KeptAttribute> bodyAttributes = const <KeptAttribute>[];
    final List<DocxBlock> blocks = <DocxBlock>[];
    OpaqueXml? finalSectPr;
    bool bodySeen = false;
    _children(r, () {
      if (!bodySeen && _isW(r, 'body')) {
        bodySeen = true;
        bodyAttributes = List<KeptAttribute>.unmodifiable(keepAttributes(r));
        finalSectPr = _readBody(blocks);
      } else {
        (bodySeen ? after : before).add(OpaqueXml.capture(r));
      }
    });
    return DocumentPart._(
      root,
      List<OpaqueXml>.unmodifiable(before),
      bodyAttributes,
      blocks,
      finalSectPr,
      List<OpaqueXml>.unmodifiable(after),
    );
  }

  /// Reads the children of `w:body` into [blocks] and returns the final
  /// `w:sectPr`, if the last child is one.
  OpaqueXml? _readBody(List<DocxBlock> blocks) {
    final XmlPullReader r = _r;
    // A sectPr is final only if nothing follows it.
    OpaqueXml? sectPr;
    _children(r, () {
      if (sectPr != null) {
        blocks.add(opaqueBlock(sectPr!));
        sectPr = null;
      }
      _blockIndex = blocks.length;
      if (_isW(r, 'p')) {
        blocks.add(_readParagraph());
      } else if (_isW(r, 'sectPr')) {
        sectPr = OpaqueXml.capture(r);
      } else {
        blocks.add(opaqueBlock(OpaqueXml.capture(r)));
      }
    });
    return sectPr;
  }

  /// Reads the `w:p` the reader is on.
  DocxParagraph _readParagraph() {
    final XmlPullReader r = _r;
    final List<KeptAttribute> attributes = List<KeptAttribute>.unmodifiable(
      keepAttributes(r),
    );
    PropertyContainer? properties;
    String? style;
    final List<DocxInline> inlines = <DocxInline>[];
    _children(r, () {
      if (properties == null && _isW(r, 'pPr')) {
        properties = PropertyContainer.read(
          r,
          typed: _pPrTyped,
          onTyped: (String _, XmlPullReader r) {
            style = _styleValue(r);
            r.skip();
          },
        );
      } else if (_isW(r, 'r')) {
        inlines.add(_readRun());
      } else {
        inlines.add(_readOpaqueInline());
      }
    });
    return readParagraph(
      properties: properties ?? const PropertyContainer.empty(),
      style: style,
      attributes: attributes,
      inlines: inlines,
    );
  }

  /// Captures the inline the reader is on, collecting its visible text in
  /// the same walk.
  DocxOpaqueInline _readOpaqueInline() {
    final VisibleTextCollector text = VisibleTextCollector();
    final OpaqueXml xml = OpaqueXml.capture(
      _r,
      onEvent: (XmlPullReader r) {
        text.add(r);
        if (text.length > _maxTextLength) throw _tooLong();
      },
    );
    return opaqueInline(xml, text: text.text);
  }

  /// Reads the `w:r` the reader is on.
  DocxRun _readRun() {
    final XmlPullReader r = _r;
    final List<KeptAttribute> attributes = List<KeptAttribute>.unmodifiable(
      keepAttributes(r),
    );
    PropertyContainer? properties;
    String? style;
    final List<DocxRunContent> content = <DocxRunContent>[];
    _children(r, () {
      if (r.namespaceUri != Ns.w) {
        content.add(opaqueRunContent(OpaqueXml.capture(r)));
        return;
      }
      switch (r.localName) {
        case 'rPr' when properties == null:
          properties = PropertyContainer.read(
            r,
            typed: _rPrTyped,
            onTyped: (String _, XmlPullReader r) {
              style = _styleValue(r);
              r.skip();
            },
          );
        case 't':
          final List<KeptAttribute> kept = keepAttributes(r);
          content.add(readText(_readText(), kept));
        case 'tab':
          content.add(readTab(keepAttributes(r)));
          r.skip();
        case 'br':
          content.add(_readBreak());
          r.skip();
        case 'cr':
          content.add(readCarriageReturn(keepAttributes(r)));
          r.skip();
        default:
          content.add(opaqueRunContent(OpaqueXml.capture(r)));
      }
    });
    return readRun(
      properties: properties ?? const PropertyContainer.empty(),
      style: style,
      attributes: attributes,
      content: content,
    );
  }

  /// The `w:br` the reader is on; the reader stays on it.
  ///
  /// `w:type` `page` and `column` are typed and not kept. Any other value,
  /// such as `textWrapping`, reads as a line break and is kept as written.
  DocxBreak _readBreak() {
    final XmlPullReader r = _r;
    final DocxBreakType type = switch (r.getAttribute(
      'type',
      namespaceUri: Ns.w,
    )) {
      'page' => DocxBreakType.page,
      'column' => DocxBreakType.column,
      _ => DocxBreakType.line,
    };
    List<KeptAttribute> kept = keepAttributes(r);
    if (type != DocxBreakType.line) {
      kept = <KeptAttribute>[
        for (final KeptAttribute a in kept)
          if (a.namespaceUri != Ns.w || !a.qualifiedName.endsWith(':type')) a,
      ];
    }
    return readBreak(type, kept);
  }

  /// The character data of the `w:t` the reader is on, entities and CDATA
  /// decoded and joined, leaving the reader on its end event. Child
  /// elements, which the schema does not allow, are skipped.
  String _readText() {
    final XmlPullReader r = _r;
    if (r.isEmptyElement) {
      r.next();
      return '';
    }
    final StringBuffer buffer = StringBuffer();
    final int depth = r.depth;
    while (r.next()) {
      final XmlEventType type = r.eventType;
      if (type == XmlEventType.endElement && r.depth < depth) break;
      if (type == XmlEventType.characters || type == XmlEventType.cdata) {
        buffer.write(r.text);
        if (buffer.length > _maxTextLength) throw _tooLong();
      } else if (type == XmlEventType.startElement) {
        r.skip();
      }
    }
    return buffer.toString();
  }

  /// The `limitExceeded` failure of a text in the block being read.
  DocxReadException _tooLong() => DocxReadException(
    DocxReadFailure.limitExceeded,
    'Limit maxTextLength ($_maxTextLength) exceeded by body/p[$_blockIndex].',
    part: _partName,
  );
}

/// Whether the element [r] is on is `w:<localName>`.
bool _isW(XmlPullReader r, String localName) =>
    r.namespaceUri == Ns.w && r.localName == localName;

/// The `w:val` of the style element [r] is on, or `null` when it has none
/// or an empty one.
String? _styleValue(XmlPullReader r) {
  final String? value = r.getAttribute('val', namespaceUri: Ns.w);
  return value == null || value.isEmpty ? null : value;
}

/// Calls [onChild] with [r] on the start of each child element of the
/// element [r] is on; [onChild] must leave [r] on that child's end event.
/// Character data, comments and processing instructions between the
/// children are dropped. Leaves [r] on the element's end event.
void _children(XmlPullReader r, void Function() onChild) {
  if (r.isEmptyElement) {
    r.next();
    return;
  }
  final int depth = r.depth;
  while (r.next()) {
    final XmlEventType type = r.eventType;
    if (type == XmlEventType.endElement && r.depth < depth) return;
    if (type == XmlEventType.startElement) onChild();
  }
}
