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
///
/// [DocumentPart.encode] writes the part back from the model. The root is
/// written as read, with every namespace declaration and `mc:Ignorable`, and
/// every kept element and attribute is written with the root's bindings as
/// the ones in scope, so it declares only what it needs and never redeclares
/// `w`. Typed elements use the root's own prefix for WordprocessingML. An
/// unchanged read writes the same document (by meaning; see
/// `tool/src/part_compare.dart`).
library;

import 'dart:typed_data';

import '../opc/ooxml.dart' show Ns;
import '../opc/opaque_xml.dart';
import '../opc/package.dart' show PartContent;
import '../xml/utf8_buffer.dart';
import '../xml/xml_escape.dart';
import '../xml/xml_pull_reader.dart';
import '../xml/xml_writer.dart';
import 'model/blocks.dart';
import 'model/formatting.dart' show DocxNumberingRef;
import 'model/inlines.dart';
import 'model/property_set.dart';
import 'model/run_content.dart';
import 'paragraph_property_codecs.dart' show paragraphPropertiesSchema;
import 'part_root.dart';
import 'properties.dart';
import 'read_exception.dart';
import 'read_limits.dart';
import 'run_property_codecs.dart' show runPropertiesSchema;
import 'warnings.dart';

/// The list [paragraph] was put in through the API: the value of a
/// `w:numPr` set on it that names a list other than 0, or `null` (nothing
/// set, removed, or read from the file).
DocxNumberingRef? listSetOf(DocxParagraph paragraph) {
  final PropertySet pPr = paragraphPropertySetOf(paragraph);
  if (!pPr.isSet('numPr')) {
    return null;
  }
  final Object? value = pPr.valueOf('numPr');
  return value is DocxNumberingRef && value.numId != 0 ? value : null;
}

/// The main document part: the root's start tag, what surrounds the body,
/// and the body's blocks.
final class DocumentPart implements PartContent {
  DocumentPart._(
    this.partName,
    this.root,
    this.beforeBody,
    this.bodyAttributes,
    this.blocks,
    this.finalSectPr,
    this.afterBody, {
    required bool hasBody,
  }) : _hasBody = hasBody;

  /// The main document part of a new document: a `w:document` that declares
  /// only `w`, with an empty body. Add paragraphs to [blocks].
  DocumentPart.create({String partName = '/word/document.xml'})
    : this._(
        partName,
        const XmlRoot.of('w:document', <String, String>{'w': Ns.w}),
        const <OpaqueXml>[],
        const <KeptAttribute>[],
        <DocxBlock>[],
        null,
        const <OpaqueXml>[],
        hasBody: true,
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

  /// The part's absolute name, such as `/word/document.xml`: the part of
  /// the warnings [encode] raises.
  final String partName;

  /// Whether the part has a `w:body`. A document read without one is
  /// written without one, unless blocks were added.
  final bool _hasBody;

  DocxWarningCollector _encodeWarnings = DocxWarningCollector();

  /// Whether the document defines the list instance a numId names, so a
  /// `w:numPr` set through the API that names another is reported at
  /// [encode] (plan Ruling 8); `null` reports none. The save sets it
  /// before it writes the part.
  bool Function(int numId)? listDefined;

  /// The warnings the last [encode] raised; empty before the first.
  ///
  /// Each [encode] starts a new collector, so encoding twice reports each
  /// problem once: the save reads this after it encoded the part. The
  /// characters a run lost when its text was set are reported here, with
  /// [DocxWarningCode.invalidCharactersRemoved] at the run's location at
  /// that time, `body/p[i]/r[j]`, where `i` counts only the paragraphs of
  /// the body and `j` only the runs of the paragraph. A run that is no
  /// longer in the body is not reported. A paragraph whose `w:numPr` was
  /// set through the API to a list other than 0 that [listDefined] denies
  /// is reported with [DocxWarningCode.numberingNotFound] at `body/p[i]`,
  /// with the list's id as the detail.
  DocxWarningCollector get encodeWarnings => _encodeWarnings;

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

  /// Writes the part, and replaces [encodeWarnings] with the warnings of
  /// this write.
  @override
  List<Uint8List> encode() {
    final DocxWarningCollector warnings = DocxWarningCollector();
    final Utf8Buffer buffer = Utf8Buffer();
    final XmlWriter w = XmlWriter(buffer)..declaration();
    final (:String prefix, :Map<String, String> scope) = openWordRoot(w, root);
    _Writer(
      w,
      '$prefix:',
      prefix,
      scope,
      partName,
      warnings,
      listDefined,
    ).write(this);
    w.end();
    _encodeWarnings = warnings;
    return buffer.takeChunks();
  }
}

/// One write of a document part's content, inside the open root.
final class _Writer {
  _Writer(
    this._w,
    this._p,
    this._prefix,
    this._scope,
    this._partName,
    this._warnings,
    this._listDefined,
  );

  final XmlWriter _w;

  /// The WordprocessingML prefix with its colon, such as `w:`.
  final String _p;

  /// The WordprocessingML prefix, such as `w`.
  final String _prefix;

  /// The bindings in scope inside the root.
  final Map<String, String> _scope;

  final String _partName;
  final DocxWarningCollector _warnings;
  final bool Function(int numId)? _listDefined;

  void write(DocumentPart part) {
    for (final OpaqueXml x in part.beforeBody) {
      x.writeTo(_w, declaredAbove: _scope);
    }
    if (part._hasBody ||
        part.blocks.isNotEmpty ||
        part.bodyAttributes.isNotEmpty) {
      _w.start('${_p}body');
      writeKeptAttributes(_w, part.bodyAttributes, declaredAbove: _scope);
      int paragraphs = 0;
      for (final DocxBlock block in part.blocks) {
        switch (block) {
          case DocxParagraph():
            _paragraph(block, 'body/p[${paragraphs++}]');
          case DocxOpaqueBlock():
            opaqueBlockXml(block).writeTo(_w, declaredAbove: _scope);
        }
      }
      part.finalSectPr?.writeTo(_w, declaredAbove: _scope);
      _w.end();
    }
    for (final OpaqueXml x in part.afterBody) {
      x.writeTo(_w, declaredAbove: _scope);
    }
  }

  /// Writes the paragraph [p] at the location [path].
  void _paragraph(DocxParagraph p, String path) {
    final XmlWriter w = _w;
    w.start('${_p}p');
    writeKeptAttributes(w, paragraphAttributesOf(p), declaredAbove: _scope);
    final PropertySet pPr = paragraphPropertySetOf(p);
    final bool Function(int)? listDefined = _listDefined;
    final DocxNumberingRef? list = listDefined == null ? null : listSetOf(p);
    if (list != null && !listDefined!(list.numId)) {
      _warnings.add(
        DocxWarningCode.numberingNotFound,
        part: _partName,
        location: path,
        detail: '${list.numId}',
      );
    }
    if (!pPr.writesNothing) {
      pPr.writeTo(w, '${_p}pPr', prefix: _prefix, declaredAbove: _scope);
    }
    int runs = 0;
    for (final DocxInline inline in p.inlines) {
      switch (inline) {
        case DocxRun():
          _run(inline, '$path/r[${runs++}]');
        case DocxOpaqueInline():
          opaqueInlineXml(inline).writeTo(w, declaredAbove: _scope);
      }
    }
    w.end();
  }

  /// Writes the run [r] at the location [path], and reports the characters
  /// removed from its text there.
  void _run(DocxRun r, String path) {
    final int removed = removedCharactersOf(r);
    if (removed > 0) {
      _warnings.add(
        DocxWarningCode.invalidCharactersRemoved,
        part: _partName,
        location: path,
        count: removed,
      );
    }
    final XmlWriter w = _w;
    w.start('${_p}r');
    writeKeptAttributes(w, runAttributesOf(r), declaredAbove: _scope);
    final PropertySet rPr = runPropertySetOf(r);
    if (!rPr.writesNothing) {
      rPr.writeTo(w, '${_p}rPr', prefix: _prefix, declaredAbove: _scope);
    }
    for (final DocxRunContent c in r.content) {
      _content(c);
    }
    w.end();
  }

  /// Writes one piece of run content.
  void _content(DocxRunContent c) {
    final XmlWriter w = _w;
    switch (c) {
      case DocxText(:final String text):
        w.start('${_p}t');
        if (textWasRead(c)) {
          writeKeptAttributes(w, contentAttributesOf(c), declaredAbove: _scope);
        } else if (_needsPreserve(text)) {
          w.attribute('xml:space', 'preserve');
        }
        w.text(scrubXmlText(text).text);
        w.end();
      case DocxTab():
        _empty('tab', c);
      case DocxBreak(:final DocxBreakType type):
        w.start('${_p}br');
        if (type != DocxBreakType.line) {
          w.attribute('${_p}type', type.name);
        }
        writeKeptAttributes(w, contentAttributesOf(c), declaredAbove: _scope);
        w.end();
      case DocxCarriageReturn():
        _empty('cr', c);
      case DocxOpaqueRunContent():
        opaqueRunContentXml(c).writeTo(w, declaredAbove: _scope);
    }
  }

  /// Writes `w:<localName>` with the attributes [c] kept and no content.
  void _empty(String localName, DocxRunContent c) {
    _w.start('$_p$localName');
    writeKeptAttributes(_w, contentAttributesOf(c), declaredAbove: _scope);
    _w.end();
  }
}

/// Whether text set through the API needs `xml:space="preserve"`: it starts
/// or ends with whitespace, or holds two spaces in a row, which a reader
/// would otherwise be free to collapse.
bool _needsPreserve(String text) {
  if (text.isEmpty) return false;
  return _isSpace(text.codeUnitAt(0)) ||
      _isSpace(text.codeUnitAt(text.length - 1)) ||
      text.contains('  ');
}

/// Whether [unit] is XML whitespace.
bool _isSpace(int unit) =>
    unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x0D;

/// One read of a document part.
final class _PartReader {
  _PartReader(this._r, this._partName, this._maxTextLength);

  final XmlPullReader _r;
  final String _partName;
  final int _maxTextLength;

  /// The index among the body's paragraphs of the paragraph being read,
  /// for errors: the index of a warning's location (`body/p[i]`), which
  /// other blocks do not shift.
  int _paragraphIndex = 0;

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
      _partName,
      root,
      List<OpaqueXml>.unmodifiable(before),
      bodyAttributes,
      blocks,
      finalSectPr,
      List<OpaqueXml>.unmodifiable(after),
      hasBody: bodySeen,
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
      if (_isW(r, 'p')) {
        blocks.add(_readParagraph());
        _paragraphIndex++;
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
    final List<DocxInline> inlines = <DocxInline>[];
    _children(r, () {
      if (properties == null && _isW(r, 'pPr')) {
        properties = PropertyContainer.read(r, paragraphPropertiesSchema);
      } else if (_isW(r, 'r')) {
        inlines.add(_readRun());
      } else {
        inlines.add(_readOpaqueInline());
      }
    });
    return readParagraph(
      properties: properties ?? const PropertyContainer.empty(),
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
    final List<DocxRunContent> content = <DocxRunContent>[];
    _children(r, () {
      if (r.namespaceUri != Ns.w) {
        content.add(opaqueRunContent(OpaqueXml.capture(r)));
        return;
      }
      switch (r.localName) {
        case 'rPr' when properties == null:
          properties = PropertyContainer.read(r, runPropertiesSchema);
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

  /// The `limitExceeded` failure of a text in the paragraph being read.
  DocxReadException _tooLong() => DocxReadException(
    DocxReadFailure.limitExceeded,
    'Limit maxTextLength ($_maxTextLength) exceeded by '
    'body/p[$_paragraphIndex].',
    part: _partName,
  );
}

/// Whether the element [r] is on is `w:<localName>`.
bool _isW(XmlPullReader r, String localName) =>
    r.namespaceUri == Ns.w && r.localName == localName;

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
