/// The formatting of a run: bold, size, colour, fonts and the rest of a
/// run's `w:rPr`.
///
/// Not ported from Quds; written for jet_office.
///
/// [DocxRunProperties] is a view over the `w:rPr` of a run as read (a
/// private [PropertySet]). Each member is a nullable getter and setter,
/// `null` meaning "not set here" (the style or the document default
/// decides). Reading gives
/// what the file holds when the model can type it, else `null`: a
/// `w:sz w:val="1in"` reads `null` and stays in the file (plan Ruling 2).
/// Setting writes one element, replacing the old one; it never touches the
/// complex-script variants (`w:bCs`, `w:szCs`, `w:rFonts/@w:cs`), which
/// stay as read (Ruling 3). Setting a property to the value it reads is a
/// no-op, so such a set neither records a change nor rewrites a child the
/// model reads in another spelling. To remove formatting the getter cannot
/// read, use [DocxRunProperties.clear].
///
/// Lengths are points; a value is rounded to the file's unit and reads back
/// rounded (Ruling 4).
library;

import '../properties.dart';
import '../property_codec.dart';
import '../run_property_codecs.dart';
import 'edit_sink.dart';
import 'formatting.dart';
import 'property_set.dart';
import 'styles.dart' show DocxStyleType;

/// A property of a run, to name it for [DocxRunProperties.clear].
enum DocxRunProperty {
  /// The character style, [DocxRunProperties.style] (`w:rStyle`).
  style('rStyle'),

  /// The fonts, [DocxRunProperties.fonts] (`w:rFonts`).
  fonts('rFonts'),

  /// Bold, [DocxRunProperties.bold] (`w:b`).
  bold('b'),

  /// Italic, [DocxRunProperties.italic] (`w:i`).
  italic('i'),

  /// Capital letters, [DocxRunProperties.caps] (`w:caps`).
  caps('caps'),

  /// Small capitals, [DocxRunProperties.smallCaps] (`w:smallCaps`).
  smallCaps('smallCaps'),

  /// Strikethrough, [DocxRunProperties.strike] (`w:strike`).
  strike('strike'),

  /// Double strikethrough, [DocxRunProperties.doubleStrike] (`w:dstrike`).
  doubleStrike('dstrike'),

  /// The text colour, [DocxRunProperties.color] (`w:color`).
  color('color'),

  /// The character spacing, [DocxRunProperties.characterSpacingPt]
  /// (`w:spacing`).
  characterSpacingPt('spacing'),

  /// The font size, [DocxRunProperties.sizePt] (`w:sz`).
  sizePt('sz'),

  /// The highlight, [DocxRunProperties.highlight] (`w:highlight`).
  highlight('highlight'),

  /// The underline, [DocxRunProperties.underline] (`w:u`).
  underline('u'),

  /// The shading, [DocxRunProperties.shading] (`w:shd`).
  shading('shd'),

  /// The vertical alignment, [DocxRunProperties.verticalAlign]
  /// (`w:vertAlign`).
  verticalAlign('vertAlign'),

  /// The language, [DocxRunProperties.language] (`w:lang/@w:val`).
  language('lang');

  const DocxRunProperty(this._element);

  final String _element;
}

/// The properties of a run (`w:rPr`).
///
/// Get one from `DocxRun.properties`, `DocxStyle.runProperties` or
/// `DocxDocumentDefaults.runProperties`; it is the same object every time.
/// Each set is one change of the document's change log.
final class DocxRunProperties {
  DocxRunProperties._(PropertyContainer source, DocxEditSink Function() sink)
    : _set = _RunSet(source, sink);

  /// The set behind the members; private so a caller cannot reach its
  /// untyped surface.
  final PropertySet _set;

  /// The id of the run's character style (`w:rStyle`), or `null`.
  ///
  /// A `w:rStyle` the model does not type (no `w:val`, an empty one, other
  /// attributes, child elements) reads `null` and is written back as read.
  /// Setting the empty string, or an id holding a character XML forbids,
  /// throws [ArgumentError]; `null` removes the style.
  ///
  /// On a run in a document, the id set is resolved against the document's
  /// styles, which loads them: an id the document defines is kept; the
  /// English id of a built-in character style (`Hyperlink`) becomes the id
  /// the document has for it, whatever its language, so this reads back
  /// that id, and the built-in is added when the document lacks it. Any
  /// other id is kept and reported at save
  /// (`DocxWarningCode.styleNotFound`). A run in no document is resolved
  /// when it is inserted into one.
  ///
  /// A styles part that cannot be read makes the set throw a
  /// `DocxReadException` naming it, on a document that opened; nothing
  /// changes then.
  String? get style => _set.valueOf('rStyle') as String?;

  set style(String? value) {
    checkStyleId(value);
    _set.setStyleId('rStyle', value, DocxStyleType.character);
  }

  /// The fonts (`w:rFonts`), or `null`.
  ///
  /// Setting replaces the ASCII, high ANSI and East Asian slots and their
  /// theme fonts, and keeps `w:cs`, `w:cstheme`, `w:hint` and the other
  /// attributes of the file.
  DocxFonts? get fonts => _set.valueOf('rFonts') as DocxFonts?;

  set fonts(DocxFonts? value) => _set.setValue('rFonts', value);

  /// Whether the text is bold (`w:b`), or `null`. `false` is written as
  /// `w:val="0"`, which turns off bold a style turned on.
  ///
  /// Setting does not change `w:bCs`, the complex-script bold.
  bool? get bold => _set.valueOf('b') as bool?;

  set bold(bool? value) => _set.setValue('b', value);

  /// Whether the text is italic (`w:i`), or `null`. Setting does not change
  /// `w:iCs`.
  bool? get italic => _set.valueOf('i') as bool?;

  set italic(bool? value) => _set.setValue('i', value);

  /// Whether the text is in capital letters (`w:caps`), or `null`.
  bool? get caps => _set.valueOf('caps') as bool?;

  set caps(bool? value) => _set.setValue('caps', value);

  /// Whether the text is in small capitals (`w:smallCaps`), or `null`.
  bool? get smallCaps => _set.valueOf('smallCaps') as bool?;

  set smallCaps(bool? value) => _set.setValue('smallCaps', value);

  /// Whether the text has a line through it (`w:strike`), or `null`.
  bool? get strike => _set.valueOf('strike') as bool?;

  set strike(bool? value) => _set.setValue('strike', value);

  /// Whether the text has a double line through it (`w:dstrike`), or
  /// `null`.
  bool? get doubleStrike => _set.valueOf('dstrike') as bool?;

  set doubleStrike(bool? value) => _set.setValue('dstrike', value);

  /// The text colour (`w:color`), or `null`.
  DocxColor? get color => _set.valueOf('color') as DocxColor?;

  set color(DocxColor? value) => _set.setValue('color', value);

  /// The space added after each character, in points (`w:spacing`, stored
  /// in twips), or `null`. Negative condenses.
  ///
  /// A value is rounded to a twentieth of a point and reads back rounded.
  /// A value that is not finite throws [ArgumentError]; one outside -1584
  /// to 1584 points throws [RangeError].
  double? get characterSpacingPt => _set.valueOf('spacing') as double?;

  set characterSpacingPt(double? value) => _set.setValue(
    'spacing',
    value == null ? null : roundedCharacterSpacingPt(value),
  );

  /// The font size in points (`w:sz`, stored in half-points), or `null`.
  ///
  /// A value is rounded to a half-point and reads back rounded (11.3 reads
  /// 11.5). A value that is not finite throws [ArgumentError]; one outside
  /// 1 to 1638 points throws [RangeError]. Setting does not change
  /// `w:szCs`, the complex-script size.
  double? get sizePt => _set.valueOf('sz') as double?;

  set sizePt(double? value) =>
      _set.setValue('sz', value == null ? null : roundedSizePt(value));

  /// The highlight colour (`w:highlight`), or `null`.
  DocxHighlight? get highlight => _set.valueOf('highlight') as DocxHighlight?;

  set highlight(DocxHighlight? value) => _set.setValue('highlight', value);

  /// The underline (`w:u`), or `null`.
  DocxUnderline? get underline => _set.valueOf('u') as DocxUnderline?;

  set underline(DocxUnderline? value) => _set.setValue('u', value);

  /// The shading behind the text (`w:shd`), or `null`.
  DocxShading? get shading => _set.valueOf('shd') as DocxShading?;

  set shading(DocxShading? value) => _set.setValue('shd', value);

  /// Whether the text is raised or lowered (`w:vertAlign`), or `null`.
  DocxVerticalAlign? get verticalAlign =>
      _set.valueOf('vertAlign') as DocxVerticalAlign?;

  set verticalAlign(DocxVerticalAlign? value) =>
      _set.setValue('vertAlign', value);

  /// The language of the text (`w:lang/@w:val`), such as `tr-TR`, or
  /// `null`.
  ///
  /// A `w:lang` without `w:val` (only `w:eastAsia` or `w:bidi`) reads
  /// `null`. Setting keeps `w:eastAsia` and `w:bidi`. A value that is not
  /// a language tag (letters of two to eight, then groups of letters and
  /// digits joined by hyphens) throws [ArgumentError].
  String? get language => _set.valueOf('lang') as String?;

  set language(String? value) {
    if (value != null && !isLanguageTag(value)) {
      throw ArgumentError.value(value, 'language', 'must be a language tag');
    }
    _set.setValue('lang', value);
  }

  /// Removes [property] from the run, whatever the getter reads of it.
  ///
  /// Setting a property to `null` does nothing when it already reads `null`,
  /// so a child the model cannot type (a `w:sz w:val="1in"`, two `w:b`)
  /// stays; clear removes every such child. It removes the element of
  /// [property] only: clearing [DocxRunProperty.bold] leaves `w:bCs`, and
  /// clearing [DocxRunProperty.sizePt] leaves `w:szCs`. Nothing is recorded
  /// when the run has no such child.
  void clear(DocxRunProperty property) => _set.clearChild(property._element);
}

/// The run properties over [source], as `DocxRun` holds them; edits go to
/// the sink [sink] gives.
DocxRunProperties newRunProperties(
  PropertyContainer source,
  DocxEditSink Function() sink,
) => DocxRunProperties._(source, sink);

/// The property set behind [properties], for the writer and the edit
/// primitives. Not exported.
PropertySet propertySetOfRunProperties(DocxRunProperties properties) =>
    properties._set;

/// The property set of a run's `w:rPr`.
final class _RunSet extends PropertySet {
  _RunSet(PropertyContainer source, DocxEditSink Function() sink)
    : super(source, runPropertiesSchema, sink);
}
