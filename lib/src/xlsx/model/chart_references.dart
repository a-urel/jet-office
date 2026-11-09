/// The `charts` holder of a workbook: on a structural edit every chart
/// part's `c:f` (series `tx`, `cat`, `val`, `xVal`, `yVal`, `bubbleSize`,
/// titles; any `c:f` of the part) and every chartex part's `cx:f` follows
/// the edit through the formula rewriter (W5, Ruling 10). The caches
/// (`c:numCache`, `c:strCache`) and every other byte stay as read; Excel
/// refreshes the caches on open.
///
/// This file is new in jet_office; Quds has no equivalent.
///
/// The parts are rewritten as text here, in the XLSX layer: the DrawingML
/// layer does not know formulas (decision 0015). A part that is not readable
/// XML, or a formula the rewriter cannot read, is kept as written and
/// warned about (`referenceNotShifted`).
library;

import '../../xml/xml_escape.dart';
import '../../xml/xml_pull_reader.dart';
import '../formula/formula_rewrite.dart';
import '../formula/reference_shift.dart';
import 'opaque_references.dart';
import 'reference_holders.dart';

/// The `charts` holder over a workbook's [OpaqueScan].
final class ChartReferences implements ReferenceHolder {
  /// The holder over [_scan].
  ChartReferences(this._scan);

  final OpaqueScan _scan;

  @override
  String get holderName => 'charts';

  @override
  void shiftReferences(ReferenceMapper mapper, ReferenceShift? edit) {
    if (mapper is SheetMove) return;
    final Map<String, String> owners = _scan.owners();
    for (final String part in _scan.xmlParts()) {
      final ({String ns, String name})? root = _scan.rootOf(part);
      if (root == null) {
        if (_looksLikeChart(part)) _scan.warn(part);
        continue;
      }
      if (root.name != 'chartSpace' ||
          (root.ns != chartNamespace && root.ns != chartExNamespace)) {
        continue;
      }
      final String ns = root.ns;
      final String host = owners[part] ?? '';
      bool unfixed = false;
      final bool read = _scan.splice(part, (XmlPullReader r) {
        if (r.namespaceUri != ns || r.localName != 'f') return null;
        return SpliceEdit(
          text: (String text) {
            final String? next = rewriteFormula(
              text,
              mapper,
              host,
              onUnlexable: (_) => unfixed = true,
            );
            return next == null ? null : escapeXmlText(next);
          },
        );
      });
      if (!read || unfixed) _scan.warn(part);
    }
  }

  /// Whether [part] (a key) is where Excel puts charts, `xl/charts/`, so
  /// that a part there that cannot be read is taken for a chart.
  static bool _looksLikeChart(String part) => part.startsWith('xl/charts/');
}
