/// The settings part, `word/settings.xml`: one typed child,
/// `w:evenAndOddHeaders`, over the part as read.
///
/// Not ported from Quds; written for jet_office.
///
/// [SettingsPart.read] reads the root `w:settings` as one property container
/// ([settingsSchema]): every child is kept as written, in place, and only
/// `w:evenAndOddHeaders` has a view. Elements match by namespace URI and
/// local name, never by prefix. [SettingsPart.encode] writes the root as
/// read with the children merged with what was set, so an unchanged read
/// writes a part that means the same and `w:compat` and every other child
/// stay as they were.
library;

import 'dart:typed_data';

import '../opc/ooxml.dart' show Ns;
import '../opc/package.dart' show PartContent;
import '../xml/utf8_buffer.dart';
import '../xml/xml_pull_reader.dart';
import '../xml/xml_writer.dart';
import 'model/edit_sink.dart';
import 'model/primitives.dart' show DocxEdits;
import 'model/property_set.dart';
import 'properties.dart';
import 'property_codec.dart';
import 'read_exception.dart';
import 'run_property_codecs.dart' show OnOffCodec;
import 'schema_order.dart';

/// The name of the typed child.
const String _evenAndOdd = 'evenAndOddHeaders';

/// The schema of the root `w:settings`: [settingsOrder], typing
/// `w:evenAndOddHeaders`.
const ContainerSchema settingsSchema = ContainerSchema(
  settingsOrder,
  codecs: <String, PropertyCodec<Object>>{_evenAndOdd: OnOffCodec(_evenAndOdd)},
);

final class _SettingsSet extends PropertySet {
  _SettingsSet(PropertyContainer source, DocxEditSink Function() sink)
    : super(source, settingsSchema, sink);
}

/// The settings part: what it was read into, or an empty `w:settings` for a
/// document without the part.
final class SettingsPart implements PartContent {
  SettingsPart._(this._set, this._qualifiedName, this._prefix, this._partName);

  /// The settings of a document without a settings part: a `w:settings` that
  /// declares only `w`, with nothing in it. Its edits are recorded in
  /// [edits]; [partName] is where it will go, for errors.
  factory SettingsPart.empty(DocxEdits edits, String partName) {
    final XmlPullReader r = XmlPullReader('<w:settings xmlns:w="${Ns.w}"/>')
      ..nextTag();
    return SettingsPart._(
      _SettingsSet(PropertyContainer.read(r, settingsSchema), () => edits),
      'w:settings',
      'w',
      partName,
    );
  }

  /// Reads the part from [r], which must not have been advanced, and
  /// consumes it to the end of the root element; edits are recorded in
  /// [edits].
  ///
  /// [partName] is the part's absolute name, for errors: a root that is not
  /// `w:settings` throws a [DocxReadException] of
  /// [DocxReadFailure.malformedXml]. XML that is not well-formed, nested
  /// deeper than the reader allows or holds an entity that cannot be
  /// decoded throws [XmlParseException]: call this inside
  /// `DocxPackage.guard`, which turns it into a [DocxReadException].
  static SettingsPart read(XmlPullReader r, String partName, DocxEdits edits) {
    while (r.next()) {
      if (r.eventType == XmlEventType.startElement) break;
    }
    if (r.eventType != XmlEventType.startElement ||
        r.namespaceUri != Ns.w ||
        r.localName != 'settings') {
      throw DocxReadException(
        DocxReadFailure.malformedXml,
        'The settings part has no w:settings root element.',
        part: partName,
      );
    }
    final String qualifiedName = r.qualifiedName;
    final String rootPrefix = r.prefix;
    final Map<String, String> declared = r.declaredNamespaces;
    String? prefix;
    if (rootPrefix.isNotEmpty && declared[rootPrefix] == Ns.w) {
      prefix = rootPrefix;
    } else if (declared['w'] == Ns.w) {
      prefix = 'w';
    } else {
      for (final MapEntry<String, String> e in declared.entries) {
        if (e.key.isNotEmpty && e.value == Ns.w) {
          prefix = e.key;
          break;
        }
      }
    }
    return SettingsPart._(
      _SettingsSet(PropertyContainer.read(r, settingsSchema), () => edits),
      qualifiedName,
      prefix,
      partName,
    );
  }

  final _SettingsSet _set;
  final String _qualifiedName;

  /// A prefix bound to WordprocessingML on the root, or `null` when it binds
  /// the namespace only as the default, so a typed child cannot be written.
  final String? _prefix;
  final String _partName;

  /// Whether the document has odd and even headers: `true` for a bare
  /// `w:evenAndOddHeaders` or one whose `w:val` is true; `false` for none, a
  /// false `w:val`, a value that does not parse, or the element twice.
  bool get evenAndOddHeaders => _set.valueOf(_evenAndOdd) == true;

  /// Sets it: `true` writes `<w:evenAndOddHeaders/>`, replacing what was
  /// read, and `false` removes the child. Nothing changes when the value
  /// already reads as [value].
  ///
  /// A root that binds WordprocessingML only as its default namespace cannot
  /// take the child: this throws a [DocxReadException] naming the part, and
  /// nothing changes.
  set evenAndOddHeaders(bool value) {
    if (value == evenAndOddHeaders) return;
    if (_prefix == null) {
      throw DocxReadException(
        DocxReadFailure.malformedXml,
        'The settings part binds WordprocessingML only as the default '
        'namespace, so w:evenAndOddHeaders cannot be written to it.',
        part: _partName,
      );
    }
    _set.setValue(_evenAndOdd, value ? true : null);
  }

  /// Whether the part holds something a file must keep, so a document
  /// without the part gains it at save (plan Ruling 7).
  bool get holdsSomething => evenAndOddHeaders;

  /// Writes the part from the model.
  @override
  List<Uint8List> encode() {
    final Utf8Buffer buffer = Utf8Buffer();
    final XmlWriter w = XmlWriter(buffer)..declaration();
    _set.writeTo(w, _qualifiedName, prefix: _prefix ?? 'w');
    return buffer.takeChunks();
  }
}
