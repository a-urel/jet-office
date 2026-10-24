/// Collects the styles of a workbook and writes `xl/styles.xml`.
///
/// Ported from quds_office_engine `lib/src/builders/xlsx_io.dart` at commit 15c5d29.
/// Ported: `style`, `_numFmtId`, `_Xf` and `_stylesXml`, reduced to number
/// formats. What changed: styles are value objects deduplicated by equality,
/// custom codes are validated and scrubbed, the cell format limit is
/// enforced, and the fixed parts (one font, two fills, one border) are
/// written through `XmlWriter`.
library;

import '../xml/xml_escape.dart';
import '../xml/xml_writer.dart';
import 'limits.dart';
import 'number_format.dart';
import 'style.dart';

const String _mainNamespace =
    'http://schemas.openxmlformats.org/spreadsheetml/2006/main';

/// Hands out cell format ids (`s` attribute values) for styles and writes
/// the `styles.xml` part.
///
/// Id 0 is the default style (no number format). Equal styles get the same
/// id; custom number format codes are numbered from 164 and deduplicated by
/// code.
final class StyleRegistry {
  final List<XlsxStyle> _styles = <XlsxStyle>[const XlsxStyle()];
  final Map<XlsxStyle, int> _ids = <XlsxStyle, int>{const XlsxStyle(): 0};
  final List<String> _customCodes = <String>[];
  final Map<String, int> _customIds = <String, int>{};

  /// The id of [style], registering it on first use. `null` and an empty
  /// style give 0.
  ///
  /// Throws [ArgumentError] for a built-in id outside `0..163` or an empty
  /// custom code, or one XML cannot carry. Throws [XlsxLimitError] when the
  /// workbook would hold more than [XlsxLimits.maxCellFormats] cell formats
  /// (the default format counts as one).
  int idFor(XlsxStyle? style) {
    if (style == null) return 0;
    final int? known = _ids[style];
    if (known != null) return known;
    final XlsxNumFmt? fmt = style.numFmt;
    if (fmt != null) _validate(fmt);
    if (_styles.length >= XlsxLimits.maxCellFormats) {
      throw XlsxLimitError('cell formats', XlsxLimits.maxCellFormats);
    }
    if (fmt != null && fmt.code != null && !_customIds.containsKey(fmt.code)) {
      _customIds[fmt.code!] = 164 + _customCodes.length;
      _customCodes.add(fmt.code!);
    }
    final int id = _styles.length;
    _styles.add(style);
    _ids[style] = id;
    return id;
  }

  void _validate(XlsxNumFmt fmt) {
    final int? builtin = fmt.builtinId;
    if (builtin != null) {
      if (builtin < 0 || builtin > 163) {
        throw ArgumentError.value(
          builtin,
          'numFmt',
          'A built-in number format id must be in 0..163.',
        );
      }
      return;
    }
    final String code = fmt.code!;
    if (code.isEmpty) {
      throw ArgumentError.value(code, 'numFmt', 'A format code is empty.');
    }
    if (scrubXmlText(code).removed > 0) {
      throw ArgumentError.value(
        code,
        'numFmt',
        'A format code contains characters XML cannot carry.',
      );
    }
  }

  int _numFmtId(XlsxNumFmt fmt) => fmt.builtinId ?? _customIds[fmt.code!]!;

  /// Writes the complete `styles.xml` document to [w].
  void writeStylesXml(XmlWriter w) {
    w.declaration();
    w.start('styleSheet');
    w.attribute('xmlns', _mainNamespace);
    if (_customCodes.isNotEmpty) {
      w.start('numFmts');
      w.attribute('count', '${_customCodes.length}');
      for (var i = 0; i < _customCodes.length; i++) {
        w.empty('numFmt', <String, String>{
          'numFmtId': '${164 + i}',
          'formatCode': _customCodes[i],
        });
      }
      w.end();
    }
    w.raw(
      '<fonts count="1"><font><sz val="11"/><name val="Calibri"/></font>'
      '</fonts>'
      '<fills count="2"><fill><patternFill patternType="none"/></fill>'
      '<fill><patternFill patternType="gray125"/></fill></fills>'
      '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/>'
      '</border></borders>'
      '<cellStyleXfs count="1">'
      '<xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>',
    );
    w.start('cellXfs');
    w.attribute('count', '${_styles.length}');
    for (final XlsxStyle style in _styles) {
      final XlsxNumFmt? fmt = style.numFmt;
      w.start('xf');
      w.attribute('numFmtId', '${fmt == null ? 0 : _numFmtId(fmt)}');
      w.attribute('fontId', '0');
      w.attribute('fillId', '0');
      w.attribute('borderId', '0');
      w.attribute('xfId', '0');
      if (fmt != null) w.attribute('applyNumberFormat', '1');
      w.end();
    }
    w.end();
    w.raw(
      '<cellStyles count="1">'
      '<cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
      '<dxfs count="0"/><tableStyles count="0"/>',
    );
    w.end();
  }
}
