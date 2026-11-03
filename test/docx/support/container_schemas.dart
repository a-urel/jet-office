/// Every container schema the library defines, for the table-driven order
/// test (`test/docx/container_order_test.dart`).
///
/// A task that adds a `ContainerSchema` adds one entry to
/// [containerSchemaCases]: the container's local name, the schema, and one
/// sample value for each of its codecs (any value the codec accepts and
/// writes). Nested schemas are entries of their own as well; a schema with
/// nested containers is also checked with replacements written in their
/// place.
library;

import 'package:jet_office/src/docx/model/formatting.dart';
import 'package:jet_office/src/docx/model/numbering_formats.dart';
import 'package:jet_office/src/docx/numbering_schemas.dart';
import 'package:jet_office/src/docx/paragraph_property_codecs.dart';
import 'package:jet_office/src/docx/properties.dart';
import 'package:jet_office/src/docx/run_property_codecs.dart';
import 'package:jet_office/src/docx/style_schemas.dart';

/// One container schema under test.
typedef ContainerSchemaCase = ({
  /// The container's local name, such as `pPr`, followed by a note in
  /// parentheses when two schemas share it (`pPr (general)`).
  String name,

  /// The schema.
  ContainerSchema schema,

  /// A value for each codec of [schema], by local name.
  Map<String, Object> samples,
});

/// The container schemas of the library.
final List<ContainerSchemaCase> containerSchemaCases = <ContainerSchemaCase>[
  (
    name: 'pPr',
    schema: paragraphPropertiesSchema,
    samples: <String, Object>{
      'pStyle': 'Title',
      'keepNext': true,
      'keepLines': true,
      'pageBreakBefore': true,
      'widowControl': true,
      'numPr': DocxNumberingRef(1, level: 1),
      'pBdr': const DocxParagraphBorders(),
      'shd': const DocxShading(pattern: DocxShadingPattern.clear),
      'tabs': <DocxTabStop>[DocxTabStop(10)],
      'spacing': DocxSpacing(afterPt: 8),
      'ind': DocxIndentation(leftPt: 36),
      'jc': DocxAlignment.center,
      'outlineLvl': 1,
    },
  ),
  (
    name: 'pBdr',
    schema: paragraphBordersSchema,
    samples: <String, Object>{
      'top': DocxBorder(),
      'left': DocxBorder(),
      'bottom': DocxBorder(),
      'right': DocxBorder(),
      'between': DocxBorder(),
      'bar': DocxBorder(),
    },
  ),
  (
    name: 'rPr',
    schema: runPropertiesSchema,
    samples: <String, Object>{
      'rStyle': 'Strong',
      'rFonts': DocxFonts.all('Arial'),
      'b': true,
      'i': true,
      'caps': true,
      'smallCaps': true,
      'strike': true,
      'dstrike': true,
      'color': DocxColor.rgb('FF0000'),
      'spacing': 1.5,
      'sz': 10.5,
      'highlight': DocxHighlight.yellow,
      'u': const DocxUnderline(DocxUnderlineStyle.single),
      'shd': const DocxShading(pattern: DocxShadingPattern.clear),
      'vertAlign': DocxVerticalAlign.subscript,
      'lang': 'tr-TR',
    },
  ),
  (
    name: 'pPr (general)',
    schema: paragraphPropertiesGeneralSchema,
    samples: <String, Object>{
      'pStyle': 'Title',
      'keepNext': true,
      'keepLines': true,
      'pageBreakBefore': true,
      'widowControl': true,
      'numPr': DocxNumberingRef(1, level: 1),
      'pBdr': const DocxParagraphBorders(),
      'shd': const DocxShading(pattern: DocxShadingPattern.clear),
      'tabs': <DocxTabStop>[DocxTabStop(10)],
      'spacing': DocxSpacing(afterPt: 8),
      'ind': DocxIndentation(leftPt: 36),
      'jc': DocxAlignment.center,
      'outlineLvl': 1,
    },
  ),
  (
    name: 'style',
    schema: styleSchema,
    samples: <String, Object>{
      'name': 'Note',
      'basedOn': 'Normal',
      'next': 'Normal',
      'link': 'NoteChar',
      'uiPriority': 5,
      'qFormat': true,
    },
  ),
  (name: 'docDefaults', schema: docDefaultsSchema, samples: <String, Object>{}),
  (name: 'rPrDefault', schema: rPrDefaultSchema, samples: <String, Object>{}),
  (name: 'pPrDefault', schema: pPrDefaultSchema, samples: <String, Object>{}),
  (
    name: 'lvl',
    schema: levelSchema,
    samples: <String, Object>{
      'start': 1,
      'numFmt': DocxNumberFormat.decimal,
      'lvlText': '%1.',
      'lvlJc': DocxLevelAlignment.left,
    },
  ),
  (
    name: 'rPr (level)',
    schema: levelRunPropertiesSchema,
    samples: <String, Object>{
      'rFonts': DocxFonts(ascii: 'Symbol', hAnsi: 'Symbol'),
    },
  ),
  (
    name: 'lvlOverride',
    schema: levelOverrideSchema,
    samples: <String, Object>{'startOverride': 3},
  ),
];
