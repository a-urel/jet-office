/// The codecs and schemas of the containers of the numbering part: a level
/// (`w:lvl`), its paragraph and run properties, and a level override
/// (`w:lvlOverride`).
///
/// Not ported from Quds; written for jet_office.
///
/// [levelSchema] types four children of a `w:lvl`: `w:start`, `w:numFmt`,
/// `w:lvlText` and `w:lvlJc`, and reads its `w:pPr` (`CT_PPrGeneral`, by
/// `paragraphPropertiesGeneralSchema`) and `w:rPr` (by
/// [levelRunPropertiesSchema], which types the bullet's `w:rFonts`) as
/// containers of their own. `w:lvlRestart`, `w:pStyle`, `w:isLgl`,
/// `w:suff`, `w:lvlPicBulletId`, `w:legacy` and every attribute of the
/// level (`w:ilvl`, `w:tplc`, `w:tentative`) are kept as read.
/// [levelOverrideSchema] types `w:startOverride` and keeps a `w:lvl` inside
/// the override as read.
///
/// The abstract definitions (`w:abstractNum`) and the instances
/// (`w:num`) are not property containers: they repeat `w:lvl` and
/// `w:lvlOverride`, so the numbering part reads them child by child
/// (`numbering_part.dart`).
library;

import '../xml/xml_escape.dart';
import '../xml/xml_writer.dart';
import 'model/numbering_formats.dart';
import 'paragraph_property_codecs.dart';
import 'properties.dart';
import 'property_codec.dart';
import 'run_property_codecs.dart';
import 'schema_order.dart';

/// The largest start value of a level (`w:start`, `w:startOverride`) the
/// model types: 32767, the largest Word accepts.
const int maxLevelStart = 32767;

/// The largest level of a list: 8, the ninth level.
const int maxListLevel = 8;

final Map<String, DocxNumberFormat> _formats = <String, DocxNumberFormat>{
  for (final DocxNumberFormat f in DocxNumberFormat.values) f.name: f,
};

/// The codec of `w:numFmt`. A format the model does not know, and one with
/// `w:format` (a custom format), have no view.
final class NumberFormatCodec extends ValEnumCodec<DocxNumberFormat> {
  /// The codec of `w:numFmt`.
  const NumberFormatCodec() : super('numFmt');

  @override
  Map<String, DocxNumberFormat> get byXml => _formats;
}

final Map<String, DocxLevelAlignment> _alignments =
    <String, DocxLevelAlignment>{
      for (final DocxLevelAlignment a in DocxLevelAlignment.values) a.name: a,
    };

/// The codec of `w:lvlJc`. The values of `ST_Jc` that do not place a
/// number (`both`, the kashida values) have no view.
final class LevelAlignmentCodec extends ValEnumCodec<DocxLevelAlignment> {
  /// The codec of `w:lvlJc`.
  const LevelAlignmentCodec() : super('lvlJc');

  @override
  Map<String, DocxLevelAlignment> get byXml => _alignments;
}

/// Whether [text] is a level text the model types: every `%` is followed by
/// a digit from 1 to 9 (the level whose number goes there), and no
/// character is one XML forbids.
bool isLevelText(String text) {
  for (int i = 0; i < text.length; i++) {
    if (text.codeUnitAt(i) != 0x25) {
      continue;
    }
    final int next = i + 1 < text.length ? text.codeUnitAt(i + 1) : 0;
    if (next < 0x31 || next > 0x39) {
      return false;
    }
    i++;
  }
  return scrubXmlText(text).removed == 0;
}

/// The codec of `w:lvlText`: the text of the number, `%1` standing for the
/// number of level 0, `%2` for level 1's, and so on.
///
/// A text that is not [isLevelText], and a `w:lvlText` with `w:null`, have
/// no view.
final class LevelTextCodec extends PropertyCodec<String> {
  /// The codec of `w:lvlText`.
  const LevelTextCodec() : super('lvlText');

  @override
  Set<String> get attributes => const <String>{'val'};

  @override
  String? parse(PropertyElement e) {
    final String? value = e.w('val');
    if (value == null || e.children.isNotEmpty || e.hasText) {
      return null;
    }
    return isLevelText(value) ? value : null;
  }

  @override
  void write(
    XmlWriter w,
    String prefix,
    String value,
    PropertyElement? asRead,
  ) => writeValElement(w, '$prefix:$localName', value, prefix: prefix);
}

/// The schema of a level's `w:rPr`: [rPrOrder], typing only the bullet's
/// font, `w:rFonts`.
const ContainerSchema levelRunPropertiesSchema = ContainerSchema(
  rPrOrder,
  codecs: <String, PropertyCodec<Object>>{'rFonts': BulletFontsCodec()},
);

/// The schema of a `w:lvl` (`CT_Lvl`): [lvlOrder], typing the start, the
/// number format, the level text and the alignment, with its paragraph and
/// run properties nested.
const ContainerSchema levelSchema = ContainerSchema(
  lvlOrder,
  codecs: <String, PropertyCodec<Object>>{
    'start': IntValCodec('start', 0, maxLevelStart),
    'numFmt': NumberFormatCodec(),
    'lvlText': LevelTextCodec(),
    'lvlJc': LevelAlignmentCodec(),
  },
  nested: <String, ContainerSchema>{
    'pPr': paragraphPropertiesGeneralSchema,
    'rPr': levelRunPropertiesSchema,
  },
);

/// The schema of a `w:lvlOverride` (`CT_NumLvl`): [lvlOverrideOrder],
/// typing `w:startOverride`; a `w:lvl` in it is kept as read.
const ContainerSchema levelOverrideSchema = ContainerSchema(
  lvlOverrideOrder,
  codecs: <String, PropertyCodec<Object>>{
    'startOverride': IntValCodec('startOverride', 0, maxLevelStart),
  },
);
