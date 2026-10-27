/// [XlsxComparison], the operators of data validation and conditional
/// formatting.
///
/// New in jet_office. Quds wrote a validation's operator as free text. It
/// sits in its own file so that data validation and conditional formatting
/// share it without importing each other.
library;

/// How a value is compared with one or two operands.
///
/// It maps to `ST_DataValidationOperator` and
/// `ST_ConditionalFormattingOperator`; each value's XML name is its Dart
/// name.
enum XlsxComparison {
  /// The value is from the first operand to the second, both included.
  between,

  /// The value is below the first operand or above the second.
  notBetween,

  /// The value equals the operand.
  equal,

  /// The value differs from the operand.
  notEqual,

  /// The value is above the operand.
  greaterThan,

  /// The value is below the operand.
  lessThan,

  /// The value is the operand or above it.
  greaterThanOrEqual,

  /// The value is the operand or below it.
  lessThanOrEqual;

  /// Whether this comparison takes two operands: [between] and [notBetween].
  ///
  /// Public because it describes SpreadsheetML, not the writer: the schema
  /// gives these two operators a `formula2` and the others none, which a
  /// reader of a parsed file needs as much as the writer's checks do.
  bool get takesTwoOperands => this == between || this == notBetween;
}
