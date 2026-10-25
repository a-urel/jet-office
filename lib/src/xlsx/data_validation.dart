/// [XlsxDataValidation], a rule on what a cell may hold, its checks and its
/// `dataValidations` XML.
///
/// Ported from quds_office_engine `lib/src/sheet/serial/sheet_serial.dart` at commit 15c5d29.
/// Ported: the `dataValidations` writing and the validation kinds. What
/// changed: Quds wrote only `type`, `sqref` and `formula1`, so it dropped
/// `formula2` (a `between` rule had one bound), the comparison operator, the
/// input and error messages and their show flags; it wrote a list literal
/// without quotes, which Excel reads as a range reference; and its worksheet
/// wrote validations before `mergeCells`, against the `CT_Worksheet` order.
/// Here a validation is a value type with a factory per kind; the writer
/// checks it when it is registered (ranges inside the sheet and not
/// overlapping an earlier validation, formulas, list length, message
/// lengths) and the trailer writes attributes in `CT_DataValidation` order,
/// those that differ from the schema defaults only.
library;

import '../xml/xml_escape.dart';
import '../xml/xml_number.dart';
import '../xml/xml_writer.dart';
import 'comparison.dart';
import 'date_serial.dart';
import 'formula_text.dart';
import 'limits.dart';
import 'range.dart';
import 'values.dart';

/// What a validation lets a cell hold (`ST_DataValidationType`).
enum XlsxValidationType {
  /// Any value; the validation only shows an input message. XML `none`.
  any,

  /// One of a list of values.
  list,

  /// A whole number.
  whole,

  /// A decimal number.
  decimal,

  /// A date.
  date,

  /// A time of day.
  time,

  /// Text of a given length.
  textLength,

  /// A value for which a formula is true.
  custom;

  /// Whether the type compares the cell with one or two operands.
  bool get compares =>
      this == whole ||
      this == decimal ||
      this == date ||
      this == time ||
      this == textLength;
}

/// How strictly Excel enforces a validation (`ST_DataValidationErrorStyle`).
enum XlsxValidationErrorStyle {
  /// A value that breaks the rule is refused.
  stop,

  /// Excel warns and lets the user keep the value.
  warning,

  /// Excel informs the user and keeps the value.
  information,
}

/// A rule on the values of [ranges], with optional input and error messages.
///
/// Build one with a factory for its kind; register it with the sheet
/// writer's `dataValidation`, which checks it and throws [ArgumentError]
/// naming the field. The factories only build the formula text; they do not
/// validate (apart from [XlsxDataValidation.list], which cannot keep an item
/// with a comma, and [XlsxDataValidation.date], which needs a date Excel
/// can store).
///
/// Only the fields of the kind count: [comparison] and [formula2] belong to
/// the kinds that compare, and [XlsxDataValidation.list], `custom` and
/// `any` ignore the comparison.
final class XlsxDataValidation {
  XlsxDataValidation._(
    List<XlsxRange> ranges,
    this.type,
    this.formula1,
    this.formula2,
    this.comparison, {
    required this.allowBlank,
    required this.showDropDownArrow,
    required this.showInputMessage,
    required this.showErrorMessage,
    required this.errorStyle,
    required this.errorTitle,
    required this.error,
    required this.promptTitle,
    required this.prompt,
  }) : ranges = List<XlsxRange>.unmodifiable(ranges);

  /// A validation that lets [items] be chosen from a drop-down list.
  ///
  /// The items are written as one quoted literal, `"a,b"`, with a `"` inside
  /// an item doubled. An item must not hold a comma (the list separator), or
  /// this throws [ArgumentError] naming `items`. The literal is at most
  /// [XlsxLimits.maxValidationListLength] characters between the quotes,
  /// checked when the validation is registered; use
  /// [XlsxDataValidation.listFrom] for a longer list. [showDropDownArrow]
  /// false hides the in-cell arrow.
  factory XlsxDataValidation.list(
    List<XlsxRange> ranges,
    List<String> items, {
    bool allowBlank = true,
    bool showDropDownArrow = true,
    bool showInputMessage = true,
    bool showErrorMessage = true,
    XlsxValidationErrorStyle errorStyle = XlsxValidationErrorStyle.stop,
    String? errorTitle,
    String? error,
    String? promptTitle,
    String? prompt,
  }) {
    for (final String item in items) {
      if (item.contains(',')) {
        throw ArgumentError.value(
          item,
          'items',
          'A list item must not contain a comma, the list separator; use '
              'listFrom with a range instead.',
        );
      }
    }
    final String joined = items
        .map((String item) => item.replaceAll('"', '""'))
        .join(',');
    return XlsxDataValidation._(
      ranges,
      XlsxValidationType.list,
      '"$joined"',
      null,
      XlsxComparison.between,
      allowBlank: allowBlank,
      showDropDownArrow: showDropDownArrow,
      showInputMessage: showInputMessage,
      showErrorMessage: showErrorMessage,
      errorStyle: errorStyle,
      errorTitle: errorTitle,
      error: error,
      promptTitle: promptTitle,
      prompt: prompt,
    );
  }

  /// A validation that lets a value of the list [formula] be chosen: a range
  /// (`$D$1:$D$9`, `Data!$A:$A`), a defined name or a formula that returns
  /// one. [formula] may start with `=`.
  factory XlsxDataValidation.listFrom(
    List<XlsxRange> ranges,
    String formula, {
    bool allowBlank = true,
    bool showDropDownArrow = true,
    bool showInputMessage = true,
    bool showErrorMessage = true,
    XlsxValidationErrorStyle errorStyle = XlsxValidationErrorStyle.stop,
    String? errorTitle,
    String? error,
    String? promptTitle,
    String? prompt,
  }) => XlsxDataValidation._(
    ranges,
    XlsxValidationType.list,
    formula,
    null,
    XlsxComparison.between,
    allowBlank: allowBlank,
    showDropDownArrow: showDropDownArrow,
    showInputMessage: showInputMessage,
    showErrorMessage: showErrorMessage,
    errorStyle: errorStyle,
    errorTitle: errorTitle,
    error: error,
    promptTitle: promptTitle,
    prompt: prompt,
  );

  /// A validation for whole numbers compared with [a].
  ///
  /// [b] is the second operand: [XlsxComparison.between] and
  /// [XlsxComparison.notBetween] need it, any other comparison must not have
  /// it; the writer checks that when the validation is registered.
  factory XlsxDataValidation.whole(
    List<XlsxRange> ranges,
    XlsxComparison comparison,
    int a, {
    int? b,
    bool allowBlank = true,
    bool showInputMessage = true,
    bool showErrorMessage = true,
    XlsxValidationErrorStyle errorStyle = XlsxValidationErrorStyle.stop,
    String? errorTitle,
    String? error,
    String? promptTitle,
    String? prompt,
  }) => XlsxDataValidation._(
    ranges,
    XlsxValidationType.whole,
    '$a',
    b == null ? null : '$b',
    comparison,
    allowBlank: allowBlank,
    showDropDownArrow: true,
    showInputMessage: showInputMessage,
    showErrorMessage: showErrorMessage,
    errorStyle: errorStyle,
    errorTitle: errorTitle,
    error: error,
    promptTitle: promptTitle,
    prompt: prompt,
  );

  /// A validation for decimal numbers compared with [a]. A NaN or infinite
  /// operand throws [ArgumentError] when the validation is registered.
  ///
  /// [b] is the second operand: [XlsxComparison.between] and
  /// [XlsxComparison.notBetween] need it, any other comparison must not have
  /// it; the writer checks that when the validation is registered.
  factory XlsxDataValidation.decimal(
    List<XlsxRange> ranges,
    XlsxComparison comparison,
    double a, {
    double? b,
    bool allowBlank = true,
    bool showInputMessage = true,
    bool showErrorMessage = true,
    XlsxValidationErrorStyle errorStyle = XlsxValidationErrorStyle.stop,
    String? errorTitle,
    String? error,
    String? promptTitle,
    String? prompt,
  }) => XlsxDataValidation._(
    ranges,
    XlsxValidationType.decimal,
    _number(a),
    b == null ? null : _number(b),
    comparison,
    allowBlank: allowBlank,
    showDropDownArrow: true,
    showInputMessage: showInputMessage,
    showErrorMessage: showErrorMessage,
    errorStyle: errorStyle,
    errorTitle: errorTitle,
    error: error,
    promptTitle: promptTitle,
    prompt: prompt,
  );

  /// A validation for text whose length in characters is compared with [a],
  /// which must not be negative (checked when the validation is registered).
  ///
  /// [b] is the second operand: [XlsxComparison.between] and
  /// [XlsxComparison.notBetween] need it, any other comparison must not have
  /// it; the writer checks that when the validation is registered.
  factory XlsxDataValidation.textLength(
    List<XlsxRange> ranges,
    XlsxComparison comparison,
    int a, {
    int? b,
    bool allowBlank = true,
    bool showInputMessage = true,
    bool showErrorMessage = true,
    XlsxValidationErrorStyle errorStyle = XlsxValidationErrorStyle.stop,
    String? errorTitle,
    String? error,
    String? promptTitle,
    String? prompt,
  }) => XlsxDataValidation._(
    ranges,
    XlsxValidationType.textLength,
    '$a',
    b == null ? null : '$b',
    comparison,
    allowBlank: allowBlank,
    showDropDownArrow: true,
    showInputMessage: showInputMessage,
    showErrorMessage: showErrorMessage,
    errorStyle: errorStyle,
    errorTitle: errorTitle,
    error: error,
    promptTitle: promptTitle,
    prompt: prompt,
  );

  /// A validation for dates compared with [a]; the formula is its serial.
  ///
  /// Throws [ArgumentError] for a date that does not exist or that Excel
  /// cannot store (before 1900-01-01 or after 9999-12-31). [b] is the second
  /// operand: [XlsxComparison.between] and [XlsxComparison.notBetween] need
  /// it, any other comparison must not have it; the writer checks that when
  /// the validation is registered.
  factory XlsxDataValidation.date(
    List<XlsxRange> ranges,
    XlsxComparison comparison,
    XlsxDate a, {
    XlsxDate? b,
    bool allowBlank = true,
    bool showInputMessage = true,
    bool showErrorMessage = true,
    XlsxValidationErrorStyle errorStyle = XlsxValidationErrorStyle.stop,
    String? errorTitle,
    String? error,
    String? promptTitle,
    String? prompt,
  }) => XlsxDataValidation._(
    ranges,
    XlsxValidationType.date,
    _serial(a, 'a'),
    b == null ? null : _serial(b, 'b'),
    comparison,
    allowBlank: allowBlank,
    showDropDownArrow: true,
    showInputMessage: showInputMessage,
    showErrorMessage: showErrorMessage,
    errorStyle: errorStyle,
    errorTitle: errorTitle,
    error: error,
    promptTitle: promptTitle,
    prompt: prompt,
  );

  /// A validation for times of day compared with [a]; the formula is the
  /// fraction of a day, so 12 hours is `0.5`.
  ///
  /// [b] is the second operand: [XlsxComparison.between] and
  /// [XlsxComparison.notBetween] need it, any other comparison must not have
  /// it; the writer checks that when the validation is registered.
  factory XlsxDataValidation.time(
    List<XlsxRange> ranges,
    XlsxComparison comparison,
    Duration a, {
    Duration? b,
    bool allowBlank = true,
    bool showInputMessage = true,
    bool showErrorMessage = true,
    XlsxValidationErrorStyle errorStyle = XlsxValidationErrorStyle.stop,
    String? errorTitle,
    String? error,
    String? promptTitle,
    String? prompt,
  }) => XlsxDataValidation._(
    ranges,
    XlsxValidationType.time,
    _dayFraction(a),
    b == null ? null : _dayFraction(b),
    comparison,
    allowBlank: allowBlank,
    showDropDownArrow: true,
    showInputMessage: showInputMessage,
    showErrorMessage: showErrorMessage,
    errorStyle: errorStyle,
    errorTitle: errorTitle,
    error: error,
    promptTitle: promptTitle,
    prompt: prompt,
  );

  /// A validation that accepts a value for which [formula] is true, written
  /// for the first cell of each range and relative to it: `ISEVEN(B9)`.
  /// [formula] may start with `=`.
  factory XlsxDataValidation.custom(
    List<XlsxRange> ranges,
    String formula, {
    bool allowBlank = true,
    bool showInputMessage = true,
    bool showErrorMessage = true,
    XlsxValidationErrorStyle errorStyle = XlsxValidationErrorStyle.stop,
    String? errorTitle,
    String? error,
    String? promptTitle,
    String? prompt,
  }) => XlsxDataValidation._(
    ranges,
    XlsxValidationType.custom,
    formula,
    null,
    XlsxComparison.between,
    allowBlank: allowBlank,
    showDropDownArrow: true,
    showInputMessage: showInputMessage,
    showErrorMessage: showErrorMessage,
    errorStyle: errorStyle,
    errorTitle: errorTitle,
    error: error,
    promptTitle: promptTitle,
    prompt: prompt,
  );

  /// A validation that accepts any value; it only shows the input message
  /// [promptTitle] and [prompt] (with [showInputMessage]).
  factory XlsxDataValidation.any(
    List<XlsxRange> ranges, {
    bool allowBlank = true,
    bool showInputMessage = true,
    bool showErrorMessage = true,
    XlsxValidationErrorStyle errorStyle = XlsxValidationErrorStyle.stop,
    String? errorTitle,
    String? error,
    String? promptTitle,
    String? prompt,
  }) => XlsxDataValidation._(
    ranges,
    XlsxValidationType.any,
    null,
    null,
    XlsxComparison.between,
    allowBlank: allowBlank,
    showDropDownArrow: true,
    showInputMessage: showInputMessage,
    showErrorMessage: showErrorMessage,
    errorStyle: errorStyle,
    errorTitle: errorTitle,
    error: error,
    promptTitle: promptTitle,
    prompt: prompt,
  );

  /// The cells the validation covers, an unmodifiable copy.
  final List<XlsxRange> ranges;

  /// What the cells may hold.
  final XlsxValidationType type;

  /// How the cell is compared with [formula1] (and [formula2]); used by the
  /// kinds that compare, and [XlsxComparison.between] for the others.
  final XlsxComparison comparison;

  /// The first operand, the list or the formula, as text, or `null` for
  /// [XlsxValidationType.any].
  final String? formula1;

  /// The second operand of [XlsxComparison.between] and
  /// [XlsxComparison.notBetween], or `null`.
  final String? formula2;

  /// Whether an empty cell is accepted. XML `allowBlank`.
  final bool allowBlank;

  /// Whether a list shows its drop-down arrow in the cell. The XML attribute
  /// `showDropDown` has the opposite meaning: `showDropDown="1"` hides the
  /// arrow, so `false` here writes `1`.
  final bool showDropDownArrow;

  /// Whether the input message ([promptTitle], [prompt]) is shown when the
  /// cell is selected.
  final bool showInputMessage;

  /// Whether the error message ([errorTitle], [error]) is shown when a value
  /// breaks the rule.
  final bool showErrorMessage;

  /// How strictly a value that breaks the rule is handled.
  final XlsxValidationErrorStyle errorStyle;

  /// The title of the error message, at most
  /// [XlsxLimits.maxValidationTitleLength] characters.
  final String? errorTitle;

  /// The text of the error message, at most
  /// [XlsxLimits.maxValidationMessageLength] characters.
  final String? error;

  /// The title of the input message, at most
  /// [XlsxLimits.maxValidationTitleLength] characters.
  final String? promptTitle;

  /// The text of the input message, at most
  /// [XlsxLimits.maxValidationMessageLength] characters.
  final String? prompt;

  @override
  bool operator ==(Object other) {
    if (other is! XlsxDataValidation ||
        other.type != type ||
        other.comparison != comparison ||
        other.formula1 != formula1 ||
        other.formula2 != formula2 ||
        other.allowBlank != allowBlank ||
        other.showDropDownArrow != showDropDownArrow ||
        other.showInputMessage != showInputMessage ||
        other.showErrorMessage != showErrorMessage ||
        other.errorStyle != errorStyle ||
        other.errorTitle != errorTitle ||
        other.error != error ||
        other.promptTitle != promptTitle ||
        other.prompt != prompt ||
        other.ranges.length != ranges.length) {
      return false;
    }
    for (int i = 0; i < ranges.length; i++) {
      if (other.ranges[i] != ranges[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    type,
    comparison,
    formula1,
    formula2,
    allowBlank,
    showDropDownArrow,
    showInputMessage,
    showErrorMessage,
    errorStyle,
    errorTitle,
    error,
    promptTitle,
    prompt,
    Object.hashAll(ranges),
  );

  @override
  String toString() =>
      'XlsxDataValidation(${type.name}, $ranges'
      '${type.compares ? ', ${comparison.name}' : ''}'
      '${formula1 == null ? '' : ', $formula1'}'
      '${formula2 == null ? '' : ', $formula2'})';
}

String _number(double value) =>
    value.isFinite ? formatXmlDouble(value) : value.toString();

String _serial(XlsxDate date, String name) {
  final int? serial = dateSerial(date.year, date.month, date.day);
  if (serial == null) {
    throw ArgumentError.value(
      date,
      name,
      'Excel stores dates from 1900-01-01 to 9999-12-31 only.',
    );
  }
  return '$serial';
}

String _dayFraction(Duration time) =>
    formatXmlDouble(time.inMicroseconds / 86400e6);

/// Checks [validation] against the sheet's [earlier] validations and throws
/// [ArgumentError] naming the field when it is not valid.
///
/// Checked: at least one range, each inside the sheet and none overlapping
/// another range of this or an earlier validation; the formulas (see
/// `checkFormulaText`), the second operand present exactly for
/// [XlsxComparison.between] and [XlsxComparison.notBetween], a finite
/// decimal, a text length that is not negative, a list literal that is not
/// empty and fits [XlsxLimits.maxValidationListLength]; and the lengths and
/// characters of the titles and messages. Nothing is recorded here, so a
/// throw leaves the caller's state alone.
void checkDataValidation(
  XlsxDataValidation validation,
  Iterable<XlsxDataValidation> earlier,
) {
  _checkRanges(validation, earlier);
  _checkFormulas(validation);
  _checkText(
    validation.errorTitle,
    'errorTitle',
    XlsxLimits.maxValidationTitleLength,
  );
  _checkText(validation.error, 'error', XlsxLimits.maxValidationMessageLength);
  _checkText(
    validation.promptTitle,
    'promptTitle',
    XlsxLimits.maxValidationTitleLength,
  );
  _checkText(
    validation.prompt,
    'prompt',
    XlsxLimits.maxValidationMessageLength,
  );
}

void _checkRanges(
  XlsxDataValidation validation,
  Iterable<XlsxDataValidation> earlier,
) {
  final List<XlsxRange> ranges = validation.ranges;
  if (ranges.isEmpty) {
    throw ArgumentError.value(
      ranges,
      'ranges',
      'A validation needs at least one range.',
    );
  }
  for (int i = 0; i < ranges.length; i++) {
    validateRange(ranges[i], 'ranges[$i]');
  }
  for (int i = 0; i < ranges.length; i++) {
    for (int j = 0; j < i; j++) {
      if (ranges[j].overlaps(ranges[i])) {
        throw ArgumentError.value(
          ranges[i],
          'ranges[$i]',
          'The range ${ranges[i].ref} overlaps the range ${ranges[j].ref} of '
              'the same validation.',
        );
      }
    }
    for (final XlsxDataValidation other in earlier) {
      for (final XlsxRange taken in other.ranges) {
        if (taken.overlaps(ranges[i])) {
          throw ArgumentError.value(
            ranges[i],
            'ranges[$i]',
            'The range ${ranges[i].ref} overlaps the range ${taken.ref} of '
                'an earlier validation.',
          );
        }
      }
    }
  }
}

void _checkFormulas(XlsxDataValidation v) {
  if (v.type == XlsxValidationType.any) return;
  final String first = checkFormulaText(v.formula1 ?? '', 'formula1');
  if (v.type.compares) {
    final String? second = v.formula2;
    if (v.comparison.takesTwoOperands) {
      if (second == null) {
        throw ArgumentError.value(
          second,
          'formula2',
          'The comparison ${v.comparison.name} needs a second value.',
        );
      }
    } else if (second != null) {
      throw ArgumentError.value(
        second,
        'formula2',
        'Only between and notBetween take a second value, not '
            '${v.comparison.name}.',
      );
    }
    if (second != null) checkFormulaText(second, 'formula2');
    for (final (String text, String field) in <(String, String)>[
      (first, 'formula1'),
      if (second != null) (second, 'formula2'),
    ]) {
      _checkNumber(v.type, text, field);
    }
    return;
  }
  if (v.type == XlsxValidationType.list &&
      first.length >= 2 &&
      first.startsWith('"') &&
      first.endsWith('"')) {
    final int length = first.length - 2;
    if (length == 0) {
      throw ArgumentError.value(first, 'formula1', 'A list needs items.');
    }
    if (length > XlsxLimits.maxValidationListLength) {
      throw ArgumentError.value(
        '$length characters',
        'formula1',
        'A list written inline has at most '
            '${XlsxLimits.maxValidationListLength} characters between the '
            'quotes; use listFrom with a range or a name instead.',
      );
    }
  }
}

/// Rejects a decimal that is not finite and a negative text length, when
/// [text] reads as a number; text that is a reference or a formula passes.
void _checkNumber(XlsxValidationType type, String text, String field) {
  final double? number = double.tryParse(text);
  if (number == null) return;
  if (type == XlsxValidationType.decimal && !number.isFinite) {
    throw ArgumentError.value(text, field, 'A decimal must be finite.');
  }
  if (type == XlsxValidationType.textLength && number < 0) {
    throw ArgumentError.value(
      text,
      field,
      'A text length must not be negative.',
    );
  }
}

void _checkText(String? text, String field, int max) {
  if (text == null) return;
  if (text.length > max) {
    throw ArgumentError.value(
      '${text.length} characters',
      field,
      'It has at most $max characters.',
    );
  }
  if (scrubXmlText(text).removed > 0) {
    throw ArgumentError.value(
      text,
      field,
      'It must not contain characters XML forbids.',
    );
  }
}

/// Writes the `dataValidations` element for [validations], which the writer
/// has checked, or nothing when there are none.
///
/// Attributes follow `CT_DataValidation`; those at the schema default are
/// left out: `type="none"`, `errorStyle="stop"`, `operator="between"` and the
/// flags that are false. Titles and messages go through `escapeXstring`,
/// formulas through `escapeFormulaText`.
void writeDataValidations(XmlWriter w, List<XlsxDataValidation> validations) {
  if (validations.isEmpty) return;
  w.start('dataValidations');
  w.attribute('count', '${validations.length}');
  for (final XlsxDataValidation v in validations) {
    w.start('dataValidation');
    if (v.type != XlsxValidationType.any) w.attribute('type', v.type.name);
    if (v.errorStyle != XlsxValidationErrorStyle.stop) {
      w.attribute('errorStyle', v.errorStyle.name);
    }
    if (v.type.compares && v.comparison != XlsxComparison.between) {
      w.attribute('operator', v.comparison.name);
    }
    if (v.allowBlank) w.attribute('allowBlank', '1');
    if (!v.showDropDownArrow) w.attribute('showDropDown', '1');
    if (v.showInputMessage) w.attribute('showInputMessage', '1');
    if (v.showErrorMessage) w.attribute('showErrorMessage', '1');
    final String? errorTitle = v.errorTitle;
    final String? error = v.error;
    final String? promptTitle = v.promptTitle;
    final String? prompt = v.prompt;
    if (errorTitle != null) {
      w.attribute('errorTitle', escapeXstring(errorTitle));
    }
    if (error != null) w.attribute('error', escapeXstring(error));
    if (promptTitle != null) {
      w.attribute('promptTitle', escapeXstring(promptTitle));
    }
    if (prompt != null) w.attribute('prompt', escapeXstring(prompt));
    w.attribute('sqref', v.ranges.map((XlsxRange r) => r.ref).join(' '));
    final String? formula1 = v.formula1;
    final String? formula2 = v.formula2;
    if (v.type != XlsxValidationType.any && formula1 != null) {
      _writeFormula(w, 'formula1', formula1);
      if (formula2 != null) _writeFormula(w, 'formula2', formula2);
    }
    w.end();
  }
  w.end();
}

void _writeFormula(XmlWriter w, String element, String text) {
  w.start(element);
  w.raw(escapeFormulaText(checkFormulaText(text, element)));
  w.end();
}
