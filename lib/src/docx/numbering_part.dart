/// The numbering part, `word/numbering.xml`, read into the numbering model
/// and written back from it.
///
/// Not ported from Quds; written for jet_office.
///
/// [NumberingPart.read] walks the part once with the pull reader. The root
/// must be `w:numbering`. Each `w:abstractNum` and `w:num` is read by the
/// model (`model/numbering.dart`), which types its levels and overrides and
/// keeps the rest as read; the picture bullets (`w:numPicBullet`),
/// `w:numIdMacAtCleanup` and every other child, in any namespace, are kept
/// as written, in place ([OpaqueXml]). Elements match by namespace URI and
/// local name, never by prefix.
///
/// [NumberingPart.encode] writes the root as read, with every namespace
/// declaration and `mc:Ignorable`, then each child in document order: a
/// kept one as written, a definition read with its start tag as read and
/// its levels and overrides merged with what was set, a definition added
/// with the part's prefix and its new id. An unchanged read writes a part
/// that means the same (by `tool/src/part_compare.dart`).
library;

import 'dart:typed_data';

import '../opc/ooxml.dart' show Ns;
import '../opc/opaque_xml.dart';
import '../opc/package.dart' show PartContent;
import '../xml/utf8_buffer.dart';
import '../xml/xml_pull_reader.dart';
import '../xml/xml_writer.dart';
import 'model/numbering.dart';
import 'model/primitives.dart' show DocxEdits;
import 'part_root.dart';
import 'property_codec.dart' show writeValElement;
import 'read_exception.dart';

/// The numbering part: the numbering model it was read into, or an empty
/// one for a document without the part.
final class NumberingPart implements PartContent {
  NumberingPart._(this.numbering);

  /// The numbering of a document without a numbering part: a
  /// `w:numbering` that declares only `w`, with nothing in it. Its edits are
  /// recorded in [edits].
  NumberingPart.empty(DocxEdits edits)
    : this._(
        newNumbering(
          edits,
          const XmlRoot.of('w:numbering', <String, String>{'w': Ns.w}),
          const <Object>[],
        ),
      );

  /// Reads the part from [r], which must not have been advanced, and
  /// consumes it to the end of the root element; edits of the numbering
  /// read are recorded in [edits].
  ///
  /// [partName] is the part's absolute name, for errors: a root that is not
  /// `w:numbering` throws a [DocxReadException] of
  /// [DocxReadFailure.malformedXml]. XML that is not well-formed, nested
  /// deeper than the reader allows or holds an entity that cannot be
  /// decoded throws [XmlParseException]: call this inside
  /// `DocxPackage.guard`, which turns it into a [DocxReadException].
  static NumberingPart read(XmlPullReader r, String partName, DocxEdits edits) {
    while (r.next()) {
      if (r.eventType == XmlEventType.startElement) break;
    }
    if (r.eventType != XmlEventType.startElement ||
        r.namespaceUri != Ns.w ||
        r.localName != 'numbering') {
      throw DocxReadException(
        DocxReadFailure.malformedXml,
        'The numbering part has no w:numbering root element.',
        part: partName,
      );
    }
    final XmlRoot root = XmlRoot.capture(r);
    final List<Object> children = <Object>[];
    if (r.isEmptyElement) {
      r.next();
    } else {
      final int depth = r.depth;
      while (r.next()) {
        final XmlEventType type = r.eventType;
        if (type == XmlEventType.endElement && r.depth < depth) break;
        if (type != XmlEventType.startElement) continue;
        final bool isW = r.namespaceUri == Ns.w;
        if (isW && r.localName == 'abstractNum') {
          children.add(readAbstractNumbering(r));
        } else if (isW && r.localName == 'num') {
          children.add(readNumberingInstance(r));
        } else {
          children.add(OpaqueXml.capture(r));
        }
      }
    }
    return NumberingPart._(newNumbering(edits, root, children));
  }

  /// The numbering model.
  final DocxNumbering numbering;

  /// Whether the part holds anything a file must keep, so a document
  /// without the part gains it at save (plan Ruling 7).
  bool get holdsSomething => numberingHoldsSomething(numbering);

  /// Writes the part from the model.
  @override
  List<Uint8List> encode() {
    final Utf8Buffer buffer = Utf8Buffer();
    final XmlWriter w = XmlWriter(buffer)..declaration();
    final (:String prefix, :Map<String, String> scope) = openWordRoot(
      w,
      numberingRootOf(numbering),
    );
    for (final Object child in numberingChildrenOf(numbering)) {
      switch (child) {
        case OpaqueXml():
          child.writeTo(w, declaredAbove: scope);
        case DocxAbstractNumbering():
          _writeDefinition(w, child, 'abstractNum', child.id, prefix, scope);
        case DocxNumberingInstance():
          _writeDefinition(w, child, 'num', child.id, prefix, scope);
        default:
          throw StateError('Not a child of w:numbering: $child');
      }
    }
    w.end();
    return buffer.takeChunks();
  }
}

/// Writes [definition], a [DocxAbstractNumbering] or a
/// [DocxNumberingInstance] whose element is `w:<localName>` and whose id is
/// [id], where [prefix] is bound to WordprocessingML in [scope].
///
/// One read is written with its start tag as read. When it rebinds
/// [prefix], its typed children use another prefix bound to
/// WordprocessingML, or a new `w1` (`w2`, …) declared on it.
void _writeDefinition(
  XmlWriter w,
  Object definition,
  String localName,
  int id,
  String prefix,
  Map<String, String> scope,
) {
  final NumberingStart start = numberingStartOf(definition);
  Map<String, String> inner = mergeNamespaces(scope, start.namespaces);
  String p = prefix;
  String? declare;
  if (inner[p] != Ns.w) {
    String? bound;
    for (final MapEntry<String, String> e in inner.entries) {
      if (e.key.isNotEmpty && e.value == Ns.w) {
        bound = e.key;
        break;
      }
    }
    if (bound == null) {
      declare = 'w1';
      for (int i = 2; inner.containsKey(declare); i++) {
        declare = 'w$i';
      }
      bound = declare;
      inner = <String, String>{...inner, declare!: Ns.w};
    }
    p = bound!;
  }
  final String? qualifiedName = start.qualifiedName;
  w.start(qualifiedName ?? '$p:$localName');
  writeNamespaceDeclarations(w, start.namespaces);
  if (declare != null) {
    w.attribute('xmlns:$declare', Ns.w);
  }
  if (qualifiedName == null) {
    w.attribute('$p:${localName}Id', '$id');
  }
  writeKeptAttributes(w, start.attributes, declaredAbove: inner);
  for (final Object child in numberingDefinitionChildrenOf(definition)) {
    switch (child) {
      case OpaqueXml():
        child.writeTo(w, declaredAbove: inner);
      case DocxNumberingLevel():
        levelPropertySetOf(
          child,
        ).writeTo(w, '$p:lvl', prefix: p, declaredAbove: inner);
      case DocxLevelOverride():
        levelOverridePropertySetOf(child).writeTo(
          w,
          '$p:lvlOverride',
          prefix: p,
          declaredAbove: inner,
          attributes: isNewLevelOverride(child)
              ? <KeptAttribute>[
                  (
                    qualifiedName: '$p:ilvl',
                    namespaceUri: Ns.w,
                    value: '${child.level}',
                  ),
                ]
              : null,
        );
      default:
        if (identical(child, newAbstractNumId)) {
          writeValElement(
            w,
            '$p:abstractNumId',
            '${abstractIdOf(definition as DocxNumberingInstance)}',
            prefix: p,
          );
        } else {
          throw StateError('Not a child of w:$localName: $child');
        }
    }
  }
  w.end();
}
