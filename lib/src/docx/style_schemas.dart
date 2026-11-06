/// The schemas of the containers of the styles part: a `w:style` and the
/// document defaults.
///
/// Not ported from Quds; written for jet_office.
///
/// [styleSchema] types six children of a `w:style`: `w:name`, `w:basedOn`,
/// `w:next`, `w:link`, `w:uiPriority` and `w:qFormat`, and reads its
/// `w:pPr` (`CT_PPrGeneral`) and `w:rPr` as containers of their own. Every
/// other child, such as `w:rsid`, `w:tblPr` or `w:tblStylePr`, is kept as
/// read (until D3 types tables). [docDefaultsSchema] reads `w:docDefaults`
/// as two levels of nested containers: `w:rPrDefault/w:rPr` and
/// `w:pPrDefault/w:pPr`.
library;

import 'paragraph_property_codecs.dart';
import 'properties.dart';
import 'property_codec.dart';
import 'run_property_codecs.dart';
import 'schema_order.dart';

/// The largest `w:uiPriority` the model types: 99, the highest Word gives.
const int maxUiPriority = 99;

/// The schema of a `w:style` (`CT_Style`): [styleOrder], typing its name,
/// links, priority and quick-format flag, with its paragraph and run
/// properties nested.
const ContainerSchema styleSchema = ContainerSchema(
  styleOrder,
  codecs: <String, PropertyCodec<Object>>{
    'name': StyleIdCodec('name'),
    'basedOn': StyleIdCodec('basedOn'),
    'next': StyleIdCodec('next'),
    'link': StyleIdCodec('link'),
    'uiPriority': IntValCodec('uiPriority', 0, maxUiPriority),
    'qFormat': OnOffCodec('qFormat'),
  },
  nested: <String, ContainerSchema>{
    'pPr': paragraphPropertiesGeneralSchema,
    'rPr': runPropertiesSchema,
  },
);

/// The schema of `w:rPrDefault`: its `w:rPr`, nested.
const ContainerSchema rPrDefaultSchema = ContainerSchema(
  rPrDefaultOrder,
  nested: <String, ContainerSchema>{'rPr': runPropertiesSchema},
);

/// The schema of `w:pPrDefault`: its `w:pPr` (`CT_PPrGeneral`), nested.
const ContainerSchema pPrDefaultSchema = ContainerSchema(
  pPrDefaultOrder,
  nested: <String, ContainerSchema>{'pPr': paragraphPropertiesGeneralSchema},
);

/// The schema of `w:docDefaults`: [docDefaultsOrder], with both defaults
/// nested.
const ContainerSchema docDefaultsSchema = ContainerSchema(
  docDefaultsOrder,
  nested: <String, ContainerSchema>{
    'rPrDefault': rPrDefaultSchema,
    'pPrDefault': pPrDefaultSchema,
  },
);
