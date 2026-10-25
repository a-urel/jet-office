/// Colors for fonts, fills, borders and tabs.
///
/// Ported from quds_office_engine `lib/src/sheet/styles/sml_styles.dart` at commit 15c5d29.
/// Ported: the idea of `SmlStyleSheet.normalizeRgb` (trim, drop `#`, upper
/// case, accept six or eight hex digits). What changed: invalid input throws
/// [ArgumentError] instead of becoming an empty "no color" string, and a color
/// is a value type that can also be a theme, indexed or automatic color.
library;

import '../xml/xml_number.dart';
import '../xml/xml_writer.dart';

final RegExp _hexPattern = RegExp(r'^#?([0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$');

/// The highest theme color index SpreadsheetML defines (`0..11`).
const int _maxThemeIndex = 11;

/// The highest legacy palette index (`0..63` colors plus `64` and `65`, the
/// system foreground and background).
const int _maxIndexedColor = 65;

/// A color as SpreadsheetML (`CT_Color`) describes it: an RGB value, a theme
/// color with an optional tint, an indexed palette color, or the automatic
/// color.
///
/// The `const` constructors cannot check their arguments. An out-of-range
/// value is reported when the color is registered with the writer, which
/// throws [ArgumentError] naming the field. [XlsxColor.hex] checks at once.
///
/// Equality is by meaning: `XlsxColor.rgb(0x1F4E79)`,
/// `XlsxColor.argb(0xFF1F4E79)` and `XlsxColor.hex('#1f4e79')` are equal.
final class XlsxColor {
  /// An opaque color from [rgb], laid out as `0xRRGGBB`.
  const XlsxColor.rgb(int rgb)
    : _kind = _rgbKind,
      _alpha = 0xFF,
      _value = rgb,
      tint = 0;

  /// A color from [argb], laid out as `0xAARRGGBB`.
  const XlsxColor.argb(int argb)
    : _kind = _rgbKind,
      _alpha = argb < 0 ? -1 : argb ~/ 0x1000000,
      _value = argb % 0x1000000,
      tint = 0;

  /// The color from [hex]: six digits (`1F4E79`), a leading `#` (`#1F4E79`)
  /// or eight digits with alpha first (`FF1F4E79`), in either case.
  ///
  /// Throws [ArgumentError] for anything else, including color names such as
  /// `red`.
  factory XlsxColor.hex(String hex) {
    final RegExpMatch? match = _hexPattern.firstMatch(hex);
    if (match == null) {
      throw ArgumentError.value(
        hex,
        'hex',
        'Expected 6 or 8 hex digits, optionally after "#".',
      );
    }
    final String digits = match.group(1)!;
    final int value = int.parse(digits, radix: 16);
    return digits.length == 6 ? XlsxColor.rgb(value) : XlsxColor.argb(value);
  }

  /// The theme color at [index] (`0..11`), lightened (positive) or darkened
  /// (negative) by [tint], a fraction in `-1..1`.
  const XlsxColor.theme(int index, {this.tint = 0})
    : _kind = _themeKind,
      _alpha = 0,
      _value = index;

  /// The legacy palette color at [index] (`0..65`).
  const XlsxColor.indexed(int index)
    : _kind = _indexedKind,
      _alpha = 0,
      _value = index,
      tint = 0;

  const XlsxColor._auto() : _kind = _autoKind, _alpha = 0, _value = 0, tint = 0;

  /// The automatic color, which the application chooses (usually black for
  /// text).
  static const XlsxColor auto = XlsxColor._auto();

  static const int _rgbKind = 0;
  static const int _themeKind = 1;
  static const int _indexedKind = 2;
  static const int _autoKind = 3;

  final int _kind;

  /// Alpha for an RGB color; `-1` or above 255 marks an out-of-range `argb`.
  /// Plain arithmetic, not bit operations, so the browser (32-bit shifts)
  /// agrees with the VM. Kept apart from [_value] so that an out-of-range
  /// `rgb` cannot alias an `argb` value.
  final int _alpha;

  /// The RGB body, theme index or palette index, per [_kind].
  final int _value;

  /// The tint of a theme color; `0` for every other kind.
  final double tint;

  @override
  bool operator ==(Object other) =>
      other is XlsxColor &&
      other._kind == _kind &&
      other._alpha == _alpha &&
      other._value == _value &&
      (other.tint == tint || (other.tint.isNaN && tint.isNaN));

  /// Equal tints hash alike: `-0.0` as `0.0` and every NaN as one NaN, so
  /// that `==`, which treats two NaN tints as equal, stays consistent.
  @override
  int get hashCode => Object.hash(
    _kind,
    _alpha,
    _value,
    tint == 0
        ? 0.0
        : tint.isNaN
        ? double.nan
        : tint,
  );

  @override
  String toString() {
    switch (_kind) {
      case _rgbKind:
        final int argb = _alpha * 0x1000000 + _value;
        return 'XlsxColor.argb(0x${argb.toRadixString(16).toUpperCase()})';
      case _themeKind:
        return 'XlsxColor.theme($_value, tint: $tint)';
      case _indexedKind:
        return 'XlsxColor.indexed($_value)';
      default:
        return 'XlsxColor.auto';
    }
  }
}

/// Checks that [color] is within SpreadsheetML's limits: theme `0..11`, tint
/// finite in `-1..1`, indexed `0..65`, rgb `0..0xFFFFFF`, argb
/// `0..0xFFFFFFFF`.
///
/// Throws [ArgumentError] naming [field] when it is not.
void validateColor(XlsxColor color, String field) {
  switch (color._kind) {
    case XlsxColor._rgbKind:
      if (color._alpha < 0 ||
          color._alpha > 0xFF ||
          color._value < 0 ||
          color._value > 0xFFFFFF) {
        throw ArgumentError.value(
          color,
          field,
          'An RGB color must be within 0..0xFFFFFF (ARGB 0..0xFFFFFFFF).',
        );
      }
    case XlsxColor._themeKind:
      if (color._value < 0 || color._value > _maxThemeIndex) {
        throw ArgumentError.value(
          color,
          field,
          'A theme color index must be within 0..$_maxThemeIndex.',
        );
      }
      if (!color.tint.isFinite || color.tint < -1 || color.tint > 1) {
        throw ArgumentError.value(
          color,
          field,
          'A tint must be finite and within -1..1.',
        );
      }
    case XlsxColor._indexedKind:
      if (color._value < 0 || color._value > _maxIndexedColor) {
        throw ArgumentError.value(
          color,
          field,
          'An indexed color must be within 0..$_maxIndexedColor.',
        );
      }
  }
}

/// Writes the attributes of [color] onto the open start tag of [w]: exactly
/// one of `rgb`, `theme` (plus `tint` when it is not 0), `indexed` or `auto`.
///
/// The color must have passed [validateColor].
void writeColorAttributes(XmlWriter w, XlsxColor color) {
  switch (color._kind) {
    case XlsxColor._rgbKind:
      final int argb = color._alpha * 0x1000000 + color._value;
      w.attribute('rgb', argb.toRadixString(16).toUpperCase().padLeft(8, '0'));
    case XlsxColor._themeKind:
      w.attribute('theme', '${color._value}');
      if (color.tint != 0) {
        w.attribute('tint', formatXmlDouble(color.tint));
      }
    case XlsxColor._indexedKind:
      w.attribute('indexed', '${color._value}');
    default:
      w.attribute('auto', '1');
  }
}
