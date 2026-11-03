/// Every container schema the library defines, for the table-driven order
/// test (`test/docx/container_order_test.dart`).
///
/// A task that adds a `ContainerSchema` adds one entry to
/// [containerSchemaCases]: the container's local name, the schema, and one
/// sample value for each of its codecs (any value the codec accepts and
/// writes). Nested schemas are entries of their own as well.
library;

import 'package:jet_office/src/docx/properties.dart';

/// One container schema under test.
typedef ContainerSchemaCase = ({
  /// The container's local name, such as `pPr`.
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
    samples: <String, Object>{'pStyle': 'Title'},
  ),
  (
    name: 'rPr',
    schema: runPropertiesSchema,
    samples: <String, Object>{'rStyle': 'Strong'},
  ),
];
