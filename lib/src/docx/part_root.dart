/// The root of a WordprocessingML part written back from the model: its
/// start tag as read and the prefix the typed elements use.
///
/// Not ported from Quds; written for jet_office. The document part and the
/// styles part write their root the same way.
library;

import '../opc/ooxml.dart' show Ns;
import '../opc/opaque_xml.dart';
import '../xml/xml_writer.dart';

/// Opens [root] on [w], as read, and returns the prefix typed elements are
/// written with and the bindings in scope inside the root.
///
/// The prefix is one bound to WordprocessingML on the root: `w` first, then
/// the root's own, then any other. Attributes need a prefix, so a root that
/// binds the namespace only as the default gets `w` (or `w1`, `w2`, …)
/// declared on it. The caller writes the content and ends the root.
({String prefix, Map<String, String> scope}) openWordRoot(
  XmlWriter w,
  XmlRoot root,
) {
  final String rootPrefix = _prefixOf(root.qualifiedName);
  String? prefix = root.namespaces['w'] == Ns.w
      ? 'w'
      : rootPrefix.isNotEmpty && root.namespaces[rootPrefix] == Ns.w
      ? rootPrefix
      : _boundPrefix(root.namespaces);
  final Map<String, String> scope = <String, String>{...root.namespaces};
  root.writeStart(w);
  if (prefix == null) {
    prefix = 'w';
    for (int i = 1; scope.containsKey(prefix); i++) {
      prefix = 'w$i';
    }
    scope[prefix!] = Ns.w;
    w.attribute('xmlns:$prefix', Ns.w);
  }
  return (prefix: prefix, scope: scope);
}

/// The prefix of the qualified name [name], or `''` for none.
String _prefixOf(String name) {
  final int colon = name.indexOf(':');
  return colon < 0 ? '' : name.substring(0, colon);
}

/// A non-empty prefix [namespaces] binds to WordprocessingML, or null.
String? _boundPrefix(Map<String, String> namespaces) {
  for (final MapEntry<String, String> e in namespaces.entries) {
    if (e.key.isNotEmpty && e.value == Ns.w) return e.key;
  }
  return null;
}
