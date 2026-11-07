/// The reader of a story's blocks: paragraphs, tables, rows, cells and runs.
///
/// Not ported from Quds; written for jet_office.
///
/// [StoryReader] reads the blocks of a body, or of any part that holds blocks
/// as `w:body` does, with the pull reader. It types `w:p`, its `w:pPr` and its
/// runs; a run's `w:rPr`, text, tabs, breaks and carriage returns; `w:tbl`,
/// `w:tr` and `w:tc` with their `w:tblPr`, `w:trPr` and `w:tcPr`, the blocks of
/// a cell being read as those of the story. Everything else is kept as
/// written, in place: other blocks (content controls, bookmarks) as opaque
/// blocks, other children of `w:tbl` and `w:tr` (`w:tblGrid`, `w:tblPrEx`,
/// content controls, bookmarks) as kept children, other paragraph children
/// (tracked changes, hyperlinks, proofing marks) as opaque inlines, other run
/// children (drawings, `mc:AlternateContent`) as opaque run content, and
/// unknown attributes on `w:tbl`, `w:tr`, `w:tc`, `w:p`, `w:r`, `w:t`,
/// `w:tab`, `w:br` and `w:cr` as kept attributes. A `w:tbl` inside a kept
/// element stays kept. The visible text of an opaque inline is collected while
/// it is captured, so its slice is parsed once, under the part's own depth
/// limit.
///
/// `w:fldChar` and `w:instrText` are typed run content that keeps its element;
/// when a paragraph is read, [groupFields] puts each plain field of its inlines
/// in a `DocxField`.
///
/// A property element is typed only before the rows, cells or blocks of its
/// parent, and only the first of its name; one elsewhere is kept in place.
/// A table nested past [maxTableNesting] is refused.
///
/// Locations name the paragraph that failed as the writer's warnings do: a
/// [BlockReader] carries the location prefix of its container, `body` for the
/// main part's body, so a story part can read under its own.
///
/// Elements match by namespace URI and local name, never by prefix.
library;

import '../opc/ooxml.dart' show Ns;
import '../opc/opaque_xml.dart';
import '../xml/xml_escape.dart';
import '../xml/xml_pull_reader.dart';
import 'model/blocks.dart';
import 'model/inlines.dart';
import 'model/run_content.dart';
import 'paragraph_property_codecs.dart' show paragraphPropertiesSchema;
import 'properties.dart';
import 'property_codec.dart' show parseDecimal;
import 'read_exception.dart';
import 'run_property_codecs.dart' show runPropertiesSchema;
import 'table_property_codecs.dart'
    show
        tableCellPropertiesSchema,
        tablePropertiesSchema,
        tableRowPropertiesSchema;
import 'units.dart' show ptOfTwips;

/// The largest width of a `w:gridCol`, in twips: what `parseDecimal` reads.
const int _maxGridColumnTwips = 999999999;

/// One read of the blocks of a story.
final class StoryReader {
  /// Reads a part from [r], naming it in errors, with texts bounded and XML
  /// nested at most [maxDepth] deep.
  StoryReader(this.r, this._partName, this._maxTextLength, this.maxDepth);

  /// The pull reader the story is read from.
  final XmlPullReader r;
  final String _partName;
  final int _maxTextLength;

  /// The deepest nesting the part's XML may have.
  final int maxDepth;

  /// The body or cell of the paragraph being read, for errors.
  late BlockReader _paragraphIn;

  /// How many tables are open around the element being read.
  int _tableNesting = 0;

  /// Reads the block the reader is on, a child of a story's root or of a
  /// `w:tc`, into [into].
  void readBlock(BlockReader into) {
    final XmlPullReader r = this.r;
    if (isW(r, 'p')) {
      _paragraphIn = into;
      into.blocks.add(_readParagraph());
      into.paragraphs++;
    } else if (isW(r, 'tbl')) {
      into.blocks.add(_readTable('${into.path}/tbl[${into.tables++}]'));
    } else {
      into.blocks.add(opaqueBlock(OpaqueXml.capture(r)));
    }
  }

  /// Reads the `w:tbl` the reader is on, at the location [path].
  DocxTable _readTable(String path) {
    if (_tableNesting == maxTableNesting) {
      throw DocxReadException(
        DocxReadFailure.limitExceeded,
        'Limit table nesting ($maxTableNesting) exceeded by $path.',
        part: _partName,
      );
    }
    _tableNesting++;
    final XmlPullReader r = this.r;
    final List<KeptAttribute> attributes = List<KeptAttribute>.unmodifiable(
      keepAttributes(r),
    );
    PropertyContainer? properties;
    List<double?>? grid;
    final List<Object> children = <Object>[];
    int rows = 0;
    eachChild(r, () {
      if (isW(r, 'tr')) {
        children.add(_readRow('$path/tr[${rows++}]'));
      } else if (rows == 0 && properties == null && isW(r, 'tblPr')) {
        children.add(
          properties = PropertyContainer.read(r, tablePropertiesSchema),
        );
      } else if (rows == 0 && grid == null && isW(r, 'tblGrid')) {
        final List<double?> columns = <double?>[];
        children.add(_captureGrid(columns));
        grid = List<double?>.unmodifiable(columns);
      } else {
        children.add(OpaqueXml.capture(r));
      }
    });
    _tableNesting--;
    return readTable(
      properties: properties ?? const PropertyContainer.empty(),
      attributes: attributes,
      gridColumnsPt: grid,
      children: children,
    );
  }

  /// Captures the `w:tblGrid` the reader is on, adding the width of each
  /// `w:gridCol` child to [columns] in the same walk, and keeping the text of
  /// each other child for a grid written with new widths.
  TableGrid _captureGrid(List<double?> columns) {
    final int depth = r.depth;
    final Map<String, String> declared = <String, String>{};
    final List<String> kept = <String>[];
    int? keptStart;
    final OpaqueXml xml = OpaqueXml.capture(
      r,
      onEvent: (XmlPullReader r) {
        if (r.eventType == XmlEventType.startElement) {
          if (r.depth == depth) {
            declared.addAll(r.declaredNamespaces);
          } else if (r.depth == depth + 1) {
            if (isW(r, 'gridCol')) {
              final int? twips = parseDecimal(
                r.getAttribute('w', namespaceUri: Ns.w),
                min: 0,
                max: _maxGridColumnTwips,
              );
              columns.add(twips == null ? null : ptOfTwips(twips));
            } else if (r.isEmptyElement) {
              kept.add(r.sourceText(r.eventStart, r.eventEnd));
            } else {
              keptStart = r.eventStart;
            }
          }
        } else if (r.eventType == XmlEventType.endElement &&
            r.depth == depth &&
            keptStart != null) {
          kept.add(r.sourceText(keptStart!, r.eventEnd));
          keptStart = null;
        }
      },
    );
    return TableGrid(xml, Map<String, String>.unmodifiable(declared), kept);
  }

  /// Reads the `w:tr` the reader is on, at the location [path].
  DocxTableRow _readRow(String path) {
    final XmlPullReader r = this.r;
    final List<KeptAttribute> attributes = List<KeptAttribute>.unmodifiable(
      keepAttributes(r),
    );
    PropertyContainer? properties;
    final List<Object> children = <Object>[];
    int cells = 0;
    eachChild(r, () {
      if (isW(r, 'tc')) {
        children.add(_readCell('$path/tc[${cells++}]'));
      } else if (cells == 0 && properties == null && isW(r, 'trPr')) {
        children.add(
          properties = PropertyContainer.read(r, tableRowPropertiesSchema),
        );
      } else {
        children.add(OpaqueXml.capture(r));
      }
    });
    return readTableRow(
      properties: properties ?? const PropertyContainer.empty(),
      attributes: attributes,
      children: children,
    );
  }

  /// Reads the `w:tc` the reader is on, at the location [path].
  ///
  /// Only a first child `w:tcPr` is the cell's properties: the writer puts
  /// them first, so one anywhere else stays a block, in place.
  DocxTableCell _readCell(String path) {
    final XmlPullReader r = this.r;
    final List<KeptAttribute> attributes = List<KeptAttribute>.unmodifiable(
      keepAttributes(r),
    );
    PropertyContainer? properties;
    final List<DocxBlock> blocks = <DocxBlock>[];
    final BlockReader reader = BlockReader(path, blocks);
    eachChild(r, () {
      if (properties == null && blocks.isEmpty && isW(r, 'tcPr')) {
        properties = PropertyContainer.read(r, tableCellPropertiesSchema);
      } else {
        readBlock(reader);
      }
    });
    return readTableCell(
      properties: properties ?? const PropertyContainer.empty(),
      attributes: attributes,
      blocks: blocks,
    );
  }

  /// Reads the `w:p` the reader is on.
  DocxParagraph _readParagraph() {
    final XmlPullReader r = this.r;
    final List<KeptAttribute> attributes = List<KeptAttribute>.unmodifiable(
      keepAttributes(r),
    );
    PropertyContainer? properties;
    final List<DocxInline> inlines = <DocxInline>[];
    eachChild(r, () {
      if (properties == null && isW(r, 'pPr')) {
        properties = PropertyContainer.read(r, paragraphPropertiesSchema);
      } else if (isW(r, 'r')) {
        inlines.add(_readRun());
      } else {
        inlines.add(_readOpaqueInline());
      }
    });
    return readParagraph(
      properties: properties ?? const PropertyContainer.empty(),
      attributes: attributes,
      inlines: groupFields(inlines),
    );
  }

  /// Captures the inline the reader is on, collecting in the same walk its
  /// visible text and what a field around it needs to know of it.
  DocxOpaqueInline _readOpaqueInline() {
    final VisibleTextCollector text = VisibleTextCollector();
    bool holdsRuns = false;
    bool unpaired = false;
    int open = 0;
    final OpaqueXml xml = OpaqueXml.capture(
      r,
      onEvent: (XmlPullReader r) {
        text.add(r);
        if (text.length > _maxTextLength) throw _tooLong();
        if (r.eventType != XmlEventType.startElement) return;
        if (isW(r, 'r') || isW(r, 'fldSimple')) {
          holdsRuns = true;
        } else if (isW(r, 'fldChar')) {
          switch (_fieldMarkType(r)) {
            case DocxFieldMarkType.begin:
              open++;
            case DocxFieldMarkType.separate:
              if (open == 0) unpaired = true;
            case DocxFieldMarkType.end:
              if (open == 0) unpaired = true;
              if (open > 0) open--;
            case null:
              unpaired = true;
          }
        }
      },
    );
    return opaqueInline(
      xml,
      text: text.text,
      holdsRuns: holdsRuns,
      breaksFields: unpaired || open > 0,
    );
  }

  /// What the `w:fldChar` [r] is on marks, or `null` when it is no mark.
  DocxFieldMarkType? _fieldMarkType(XmlPullReader r) =>
      switch (r.getAttribute('fldCharType', namespaceUri: Ns.w)) {
        'begin' => DocxFieldMarkType.begin,
        'separate' => DocxFieldMarkType.separate,
        'end' => DocxFieldMarkType.end,
        _ => null,
      };

  /// Reads the `w:r` the reader is on.
  DocxRun _readRun() {
    final XmlPullReader r = this.r;
    final List<KeptAttribute> attributes = List<KeptAttribute>.unmodifiable(
      keepAttributes(r),
    );
    PropertyContainer? properties;
    final List<DocxRunContent> content = <DocxRunContent>[];
    eachChild(r, () {
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
        case 'fldChar':
          final DocxFieldMarkType? type = _fieldMarkType(r);
          final OpaqueXml xml = OpaqueXml.capture(r);
          content.add(
            type == null ? opaqueRunContent(xml) : readFieldMark(type, xml),
          );
        case 'instrText':
          content.add(_readInstruction());
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

  /// The `w:instrText` the reader is on, kept as read, with its own character
  /// data decoded and joined.
  DocxFieldInstruction _readInstruction() {
    final StringBuffer text = StringBuffer();
    final int depth = r.depth;
    final OpaqueXml xml = OpaqueXml.capture(
      r,
      onEvent: (XmlPullReader r) {
        final XmlEventType type = r.eventType;
        if ((type == XmlEventType.characters || type == XmlEventType.cdata) &&
            r.depth == depth) {
          text.write(r.text);
          if (text.length > _maxTextLength) throw _tooLong();
        }
      },
    );
    return readFieldInstruction(text.toString(), xml);
  }

  /// The `w:br` the reader is on; the reader stays on it.
  ///
  /// `w:type` `page` and `column` are typed and not kept. Any other value,
  /// such as `textWrapping`, reads as a line break and is kept as written.
  DocxBreak _readBreak() {
    final XmlPullReader r = this.r;
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
    final XmlPullReader r = this.r;
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

  /// The `limitExceeded` failure of a text in the paragraph being read,
  /// named as a warning names it (`body/p[i]`,
  /// `body/tbl[i]/tr[j]/tc[k]/p[m]`): other blocks do not shift the index.
  DocxReadException _tooLong() => DocxReadException(
    DocxReadFailure.limitExceeded,
    'Limit maxTextLength ($_maxTextLength) exceeded by '
    '${_paragraphIn.path}/p[${_paragraphIn.paragraphs}].',
    part: _partName,
  );
}

/// The blocks of a story or a cell being read, with the location of the
/// container and the count of each kind of block that has a location.
final class BlockReader {
  /// Reads into [blocks] under the location [path].
  BlockReader(this.path, this.blocks);

  /// The location of the container, such as `body`.
  final String path;

  /// The blocks read so far.
  final List<DocxBlock> blocks;

  /// How many paragraphs were read.
  int paragraphs = 0;

  /// How many tables were read.
  int tables = 0;
}

/// Whether the element [r] is on is `w:<localName>`.
bool isW(XmlPullReader r, String localName) =>
    r.namespaceUri == Ns.w && r.localName == localName;

/// Calls [onChild] with [r] on the start of each child element of the
/// element [r] is on; [onChild] must leave [r] on that child's end event.
/// Character data, comments and processing instructions between the
/// children are dropped. Leaves [r] on the element's end event.
void eachChild(XmlPullReader r, void Function() onChild) {
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

/// A reader over the element [xml] captured from a part, under a root that
/// declares the bindings the element inherited, so its prefixes resolve as
/// they did in the part. It is left on the element's start tag.
///
/// The wrapping root is one level the part did not have, so [maxDepth] is
/// raised by one: an element read at the depth limit in the part reads again.
XmlPullReader readerOfCaptured(OpaqueXml xml, int maxDepth) {
  final StringBuffer source = StringBuffer('<r');
  xml.inheritedNamespaces.forEach((String prefix, String uri) {
    source
      ..write(prefix.isEmpty ? ' xmlns="' : ' xmlns:$prefix="')
      ..write(escapeXmlAttribute(scrubXmlText(uri).text))
      ..write('"');
  });
  source
    ..write('>')
    ..write(xml.xml)
    ..write('</r>');
  final XmlPullReader r = XmlPullReader(
    source.toString(),
    maxDepth: maxDepth + 1,
  );
  r.nextTag();
  r.nextTag();
  return r;
}
