/// The styles part, `word/styles.xml`, read into the styles model and
/// written back from it.
///
/// Not ported from Quds; written for jet_office.
///
/// [StylesPart.read] walks the part once with the pull reader. The root
/// must be `w:styles`. Its first `w:docDefaults` is read by
/// `docDefaultsSchema` and each `w:style` by `styleSchema`, so their
/// children are kept as read and typed views over them
/// (`properties.dart`); `w:latentStyles` and every other child, in any
/// namespace, are kept as written, in place ([OpaqueXml]). Elements match by
/// namespace URI and local name, never by prefix.
///
/// [StylesPart.encode] writes the root as read, with every namespace
/// declaration and `mc:Ignorable`, then each child in document order: a
/// kept one as written, a style or the defaults merged with what was set,
/// a style added after the last style, and document defaults created when
/// first set before the latent styles. An unchanged read writes a part that
/// means the same (by `tool/src/part_compare.dart`).
library;

import 'dart:typed_data';

import '../opc/ooxml.dart' show Ns;
import '../opc/opaque_xml.dart';
import '../opc/package.dart' show PartContent;
import '../xml/utf8_buffer.dart';
import '../xml/xml_pull_reader.dart';
import '../xml/xml_writer.dart';
import 'model/primitives.dart' show DocxEdits;
import 'model/styles.dart';
import 'part_root.dart';
import 'properties.dart';
import 'read_exception.dart';
import 'style_schemas.dart';

/// The styles part: the styles model it was read into, or an empty one for
/// a document without the part.
final class StylesPart implements PartContent {
  StylesPart._(this.styles);

  /// The styles of a document without a styles part: a `w:styles` that
  /// declares only `w`, with nothing in it. Its edits are recorded in
  /// [edits].
  StylesPart.empty(DocxEdits edits)
    : this._(
        newStyles(
          edits,
          const XmlRoot.of('w:styles', <String, String>{'w': Ns.w}),
          const <Object>[],
        ),
      );

  /// Reads the part from [r], which must not have been advanced, and
  /// consumes it to the end of the root element; edits of the styles read
  /// are recorded in [edits].
  ///
  /// [partName] is the part's absolute name, for errors: a root that is not
  /// `w:styles` throws a [DocxReadException] of
  /// [DocxReadFailure.malformedXml]. XML that is not well-formed, nested
  /// deeper than the reader allows or holds an entity that cannot be
  /// decoded throws [XmlParseException]: call this inside
  /// `DocxPackage.guard`, which turns it into a [DocxReadException].
  static StylesPart read(XmlPullReader r, String partName, DocxEdits edits) {
    while (r.next()) {
      if (r.eventType == XmlEventType.startElement) break;
    }
    if (r.eventType != XmlEventType.startElement ||
        r.namespaceUri != Ns.w ||
        r.localName != 'styles') {
      throw DocxReadException(
        DocxReadFailure.malformedXml,
        'The styles part has no w:styles root element.',
        part: partName,
      );
    }
    final XmlRoot root = XmlRoot.capture(r);
    final List<Object> children = <Object>[];
    bool defaultsRead = false;
    if (r.isEmptyElement) {
      r.next();
    } else {
      final int depth = r.depth;
      while (r.next()) {
        final XmlEventType type = r.eventType;
        if (type == XmlEventType.endElement && r.depth < depth) break;
        if (type != XmlEventType.startElement) continue;
        final bool isW = r.namespaceUri == Ns.w;
        if (isW && r.localName == 'style') {
          children.add(readStyle(PropertyContainer.read(r, styleSchema)));
        } else if (isW && r.localName == 'docDefaults' && !defaultsRead) {
          defaultsRead = true;
          children.add(PropertyContainer.read(r, docDefaultsSchema));
        } else {
          children.add(OpaqueXml.capture(r));
        }
      }
    }
    return StylesPart._(newStyles(edits, root, children));
  }

  /// The styles model.
  final DocxStyles styles;

  /// Whether the part holds anything a file must keep, so a document
  /// without the part gains it at save (plan Ruling 7).
  bool get holdsSomething => stylesHoldSomething(styles);

  /// Writes the part from the model.
  @override
  List<Uint8List> encode() {
    final Utf8Buffer buffer = Utf8Buffer();
    final XmlWriter w = XmlWriter(buffer)..declaration();
    final (:String prefix, :Map<String, String> scope) = openWordRoot(
      w,
      stylesRootOf(styles),
    );
    for (final Object child in stylesChildrenOf(styles)) {
      switch (child) {
        case OpaqueXml():
          child.writeTo(w, declaredAbove: scope);
        case DocxStyle():
          stylePropertySetOf(child).writeTo(
            w,
            '$prefix:style',
            prefix: prefix,
            declaredAbove: scope,
            attributes: newStyleAttributesOf(child, prefix),
          );
        case NestedProperties():
          child.writeTo(
            w,
            '$prefix:docDefaults',
            prefix: prefix,
            declaredAbove: scope,
          );
        default:
          throw StateError('Not a child of w:styles: $child');
      }
    }
    w.end();
    return buffer.takeChunks();
  }
}
