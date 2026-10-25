/// Differential styles (`dxf`), the formatting a conditional-format rule
/// applies on top of a cell's own style.
///
/// New in jet_office. Quds wrote no `dxfs` (its conditional formatting
/// carried no style). A differential style renders only the fields its
/// [XlsxStyle] sets, so it is never resolved the way a cell format is: no
/// default font name or size is filled in, because that would override the
/// cell's own font whenever the rule fires. The registry in
/// `style_registry.dart` numbers and deduplicates the rendered entries.
library;

import '../xml/xml_writer.dart';
import 'border.dart';
import 'color.dart';
import 'fill.dart';
import 'font.dart';
import 'style.dart';

/// Checks that [style] can be a differential style, throwing
/// [ArgumentError] naming the field when it cannot.
///
/// Excel ignores a font name, size, family, charset and scheme, an
/// alignment and a protection in a conditional format, and a diagonal,
/// vertical or horizontal border side has no cell to draw on, so each is
/// refused instead of being dropped without a word. The number format is
/// checked by the registry, which owns the id table; this checks the rest.
void validateDifferentialStyle(XlsxStyle style) {
  final XlsxFont? font = style.font;
  if (font != null) {
    _refuse(font.name, 'name');
    _refuse(font.size, 'size');
    _refuse(font.family, 'family');
    _refuse(font.charset, 'charset');
    _refuse(font.scheme, 'scheme');
    validateFont(font);
  }
  _refuse(style.alignment, 'alignment');
  _refuse(style.protection, 'protection');
  final XlsxFill? fill = style.fill;
  if (fill != null) validateFill(fill);
  final XlsxBorder? border = style.border;
  if (border != null) {
    _refuse(border.diagonal, 'diagonal');
    _refuse(border.diagonalUp, 'diagonalUp');
    _refuse(border.diagonalDown, 'diagonalDown');
    _refuse(border.vertical, 'vertical');
    _refuse(border.horizontal, 'horizontal');
    validateBorder(border);
  }
}

void _refuse(Object? value, String field) {
  if (value != null) {
    throw ArgumentError.value(
      value,
      field,
      'A differential style cannot set $field.',
    );
  }
}

/// The number format of a differential style as it is written: an id with
/// its code.
typedef DifferentialNumFmt = ({int id, String code});

/// Writes [style] as one `<dxf>`, children in `CT_Dxf` order.
///
/// [style] must have passed [validateDifferentialStyle]; [numFmt] is its
/// number format, which only the registry can number.
void writeDifferentialStyleXml(
  XmlWriter w,
  XlsxStyle style,
  DifferentialNumFmt? numFmt,
) {
  w.start('dxf');
  final XlsxFont? font = style.font;
  if (font != null) _writeFont(w, font);
  if (numFmt != null) {
    w.empty('numFmt', <String, String>{
      'numFmtId': '${numFmt.id}',
      'formatCode': numFmt.code,
    });
  }
  final XlsxFill? fill = style.fill;
  if (fill != null) _writeFill(w, fill);
  final XlsxBorder? border = style.border;
  if (border != null) {
    // Only the four sides are written; validation refused the diagonal side
    // and its flags.
    writeBorderXml(
      w,
      XlsxBorder(
        left: border.left,
        right: border.right,
        top: border.top,
        bottom: border.bottom,
        outline: border.outline,
      ),
    );
  }
  w.end();
}

/// A solid fill in a differential style carries its color as `bgColor` and
/// no `patternType`, as Excel writes it; every other fill is as in a cell
/// format.
void _writeFill(XmlWriter w, XlsxFill fill) {
  if (fill is XlsxPatternFill && fill.type == XlsxPatternType.solid) {
    final XlsxColor? color = fill.foreground ?? fill.background;
    w.start('fill');
    w.start('patternFill');
    if (color != null) {
      w.start('bgColor');
      writeColorAttributes(w, color);
      w.end();
    }
    w.end();
    w.end();
    return;
  }
  writeFillXml(w, fill);
}

/// Writes [font] as a `<font>` that says only what it sets: `true` is
/// `<b/>`, `false` is `<b val="0"/>` (a decision to switch the style off on
/// a cell that has it), and `null` writes nothing, so the cell's font
/// shows through. A font that sets nothing writes nothing at all.
void _writeFont(XmlWriter w, XlsxFont font) {
  final XlsxUnderline? underline = font.underline;
  final XlsxFontScript? script = font.script;
  final XlsxColor? color = font.color;
  final bool writesScript = script != null && script != XlsxFontScript.baseline;
  if (font.bold == null &&
      font.italic == null &&
      font.strike == null &&
      font.condense == null &&
      font.extend == null &&
      font.outline == null &&
      font.shadow == null &&
      underline == null &&
      !writesScript &&
      color == null) {
    return;
  }
  w.start('font');
  _writeSwitch(w, 'b', font.bold);
  _writeSwitch(w, 'i', font.italic);
  _writeSwitch(w, 'strike', font.strike);
  _writeSwitch(w, 'condense', font.condense);
  _writeSwitch(w, 'extend', font.extend);
  _writeSwitch(w, 'outline', font.outline);
  _writeSwitch(w, 'shadow', font.shadow);
  if (underline != null) {
    switch (underline) {
      case XlsxUnderline.none:
        w.empty('u', <String, String>{'val': 'none'});
      case XlsxUnderline.single:
        w.empty('u');
      case XlsxUnderline.doubleLine:
        w.empty('u', <String, String>{'val': 'double'});
      case XlsxUnderline.singleAccounting:
        w.empty('u', <String, String>{'val': 'singleAccounting'});
      case XlsxUnderline.doubleAccounting:
        w.empty('u', <String, String>{'val': 'doubleAccounting'});
    }
  }
  if (writesScript) {
    w.empty('vertAlign', <String, String>{'val': script.name});
  }
  if (color != null) {
    w.start('color');
    writeColorAttributes(w, color);
    w.end();
  }
  w.end();
}

void _writeSwitch(XmlWriter w, String name, bool? value) {
  if (value == null) return;
  w.empty(name, value ? const {} : const <String, String>{'val': '0'});
}
