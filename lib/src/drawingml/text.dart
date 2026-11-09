/// The text property blocks of a chart: `c:txPr`, the look of the text Excel
/// draws itself (axis labels, an automatic title, the legend), and `c:rich`,
/// the text of a typed title.
///
/// Not ported from Quds; written for jet_office.
///
/// The blocks are the ones Excel for Mac writes, taken from the owner's
/// `chart_defaults.xlsx`: a `a:bodyPr` of fixed attributes, an empty
/// `a:lstStyle` and one paragraph whose `a:defRPr` carries the size, the
/// bold flag, the colour and the fonts. With `ChartExportColors.fileTheme`
/// the fonts are the file theme's minor font (`+mn-lt`, `+mn-ea`, `+mn-cs`),
/// as Excel writes them; with `fixed` the font is the style's family by name
/// (ruling R4 of C1).
///
/// This layer imports `opc`, `xml`, `common`, `jet_charts_core` and `jet_core`
/// only, never `xlsx` or `docx` (decisions 0014 and 0015).
library;

import 'package:jet_charts_core/jet_charts_core.dart';

import '../xml/xml_writer.dart';
import 'color.dart';

/// What a text property block is for, which decides the shape Excel gives it.
enum DrawingTextUse {
  /// A chart title: `a:bodyPr rot="0"` and `spc="0"` on the run properties.
  title,

  /// An axis title: as a chart title, but without `spc`, as Excel writes it
  /// (`chart_reference.xlsx`, chart 17), and turned a quarter to the left
  /// when its axis is vertical.
  axisTitle,

  /// An axis's labels: `a:bodyPr rot="-60000000"` and no `spc`.
  axis,

  /// The legend: `a:bodyPr rot="0"` and no `spc`, as Excel writes it
  /// (`chart_reference.xlsx`, every chart with a legend).
  legend,

  /// The data labels: `a:bodyPr rot="0"` with Excel's insets (`lIns` and
  /// `rIns` 38100, `tIns` and `bIns` 19050) and an `a:spAutoFit` child, and
  /// no `spc`, as Excel writes them (`chart_reference.xlsx`, charts 20 and
  /// 21).
  dataLabel,

  /// The chart space's own block: a bare `a:bodyPr` and `a:defRPr`, which
  /// Excel writes whatever the theme.
  chartSpace,
}

/// The attributes of `a:bodyPr` every block but the chart space's has, after
/// `rot`, in Excel's order.
const Map<String, String> _bodyAttributes = <String, String>{
  'spcFirstLastPara': '1',
  'vertOverflow': 'ellipsis',
  'vert': 'horz',
  'wrap': 'square',
  'anchor': 'ctr',
  'anchorCtr': '1',
};

/// The `rot` of a vertical axis' title, turned a quarter to the left, as
/// Excel writes it (with `vert="horz"`).
const String _verticalRotation = '-5400000';

/// The attributes of a data label's `a:bodyPr`, in Excel's order.
const Map<String, String> _dataLabelBodyAttributes = <String, String>{
  'rot': '0',
  'spcFirstLastPara': '1',
  'vertOverflow': 'ellipsis',
  'vert': 'horz',
  'wrap': 'square',
  'lIns': '38100',
  'tIns': '19050',
  'rIns': '38100',
  'bIns': '19050',
  'anchor': 'ctr',
  'anchorCtr': '1',
};

/// Writes a `c:txPr` of [style] for [use], as Excel writes it.
///
/// Every use but [DrawingTextUse.chartSpace] writes `a:bodyPr` (with `rot`
/// `-60000000` for an axis and `0` otherwise; a data label's also has
/// Excel's insets and an `a:spAutoFit` child), `a:lstStyle` and an `a:p`
/// whose `a:pPr/a:defRPr` has the size as `sz` in hundredths of a point
/// (`(size * 100).round()`), `b` from the bold flag, Excel's fixed `i`, `u`,
/// `strike`, `kern` and `baseline` (and `spc="0"` for a chart title), a
/// `a:solidFill` of the colour (`writeDrawingColor` in [mode]) and the fonts
/// of [mode]; the paragraph ends in `a:endParaRPr lang="[language]"`. The
/// chart space's block is the bare `a:bodyPr`, `a:lstStyle` and `a:defRPr`
/// with that `a:endParaRPr`, and does not show [style].
///
/// [vertical] turns an axis title's block a quarter to the left
/// (`rot="-5400000"`), as Excel writes the title of a vertical axis
/// (`chart_reference.xlsx`, chart 17); it changes no other use.
///
/// The `c:` and `a:` prefixes must be declared by the part.
void writeDrawingTextBody(
  XmlWriter w,
  ChartTextStyle style, {
  required ChartExportColors mode,
  required String language,
  required DrawingTextUse use,
  bool vertical = false,
}) {
  w.start('c:txPr');
  if (use == DrawingTextUse.chartSpace) {
    w.empty('a:bodyPr');
    w.empty('a:lstStyle');
    w.start('a:p');
    w.start('a:pPr');
    w.empty('a:defRPr');
    w.end();
    w.empty('a:endParaRPr', <String, String>{'lang': language});
    w.end();
    w.end();
    return;
  }
  final bool title = use == DrawingTextUse.title;
  final bool axisTitle = use == DrawingTextUse.axisTitle;
  if (use == DrawingTextUse.dataLabel) {
    w.start('a:bodyPr');
    for (final MapEntry<String, String> e in _dataLabelBodyAttributes.entries) {
      w.attribute(e.key, e.value);
    }
    w.empty('a:spAutoFit');
    w.end();
    w.empty('a:lstStyle');
  } else {
    _writeBodyAndList(
      w,
      rot: use == DrawingTextUse.axis
          ? '-60000000'
          : (vertical && axisTitle ? _verticalRotation : '0'),
    );
  }
  w.start('a:p');
  _writeParagraphProperties(w, style, mode: mode, spacing: title);
  w.empty('a:endParaRPr', <String, String>{'lang': language});
  w.end();
  w.end();
}

/// Writes a `c:rich` of [text] in [style]: one `a:p` per line of [text]
/// (split at CR LF, CR and LF), as Excel writes a typed title.
///
/// [use] is [DrawingTextUse.title] (the default) or
/// [DrawingTextUse.axisTitle], whose paragraphs have no `spc`, as their
/// `c:txPr` has none; any other use throws an [ArgumentError].
///
/// The block opens as a title's `c:txPr` does (`a:bodyPr rot="0"` and
/// `a:lstStyle`), and each paragraph has the title's `a:pPr`, then a run
/// `a:r` of `a:rPr lang="[language]"` and the line as `a:t`; an empty line
/// is a paragraph without a run that ends in `a:endParaRPr lang="[language]"`.
///
/// [text] must hold only characters XML 1.0 allows (`scrubXmlText`); the
/// writer escapes markup and throws an [ArgumentError] otherwise. [vertical]
/// turns an axis title's block a quarter to the left (`rot="-5400000"`), as
/// Excel writes the title of a vertical axis. The `c:` and `a:` prefixes must
/// be declared by the part.
void writeDrawingRichText(
  XmlWriter w,
  String text,
  ChartTextStyle style, {
  required ChartExportColors mode,
  required String language,
  DrawingTextUse use = DrawingTextUse.title,
  bool vertical = false,
}) {
  if (use != DrawingTextUse.title && use != DrawingTextUse.axisTitle) {
    throw ArgumentError.value(use, 'use', 'must be title or axisTitle');
  }
  final bool axisTitle = use == DrawingTextUse.axisTitle;
  w.start('c:rich');
  _writeBodyAndList(w, rot: vertical && axisTitle ? _verticalRotation : '0');
  for (final String line in text.split(_lineBreak)) {
    w.start('a:p');
    _writeParagraphProperties(w, style, mode: mode, spacing: !axisTitle);
    if (line.isEmpty) {
      w.empty('a:endParaRPr', <String, String>{'lang': language});
    } else {
      w.start('a:r');
      w.empty('a:rPr', <String, String>{'lang': language});
      w.start('a:t');
      w.text(line);
      w.end();
      w.end();
    }
    w.end();
  }
  w.end();
}

final RegExp _lineBreak = RegExp('\r\n|\r|\n');

void _writeBodyAndList(XmlWriter w, {required String rot}) {
  w.empty('a:bodyPr', <String, String>{'rot': rot, ..._bodyAttributes});
  w.empty('a:lstStyle');
}

void _writeParagraphProperties(
  XmlWriter w,
  ChartTextStyle style, {
  required ChartExportColors mode,
  required bool spacing,
}) {
  w.start('a:pPr');
  w.start('a:defRPr');
  w.attribute('sz', (style.size * 100).round().toString());
  w.attribute('b', style.bold ? '1' : '0');
  w.attribute('i', '0');
  w.attribute('u', 'none');
  w.attribute('strike', 'noStrike');
  w.attribute('kern', '1200');
  if (spacing) {
    w.attribute('spc', '0');
  }
  w.attribute('baseline', '0');
  w.start('a:solidFill');
  writeDrawingColor(w, style.color, mode);
  w.end();
  if (mode == ChartExportColors.fileTheme) {
    w.empty('a:latin', <String, String>{'typeface': '+mn-lt'});
    w.empty('a:ea', <String, String>{'typeface': '+mn-ea'});
    w.empty('a:cs', <String, String>{'typeface': '+mn-cs'});
  } else {
    w.empty('a:latin', <String, String>{'typeface': style.fontFamily});
  }
  w.end();
  w.end();
}
