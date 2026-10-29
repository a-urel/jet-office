/// The built-in number format table of ECMA-376.
///
/// New in jet_office; Quds has no number format engine. The table is
/// ECMA-376 Part 1 §18.8.30.
library;

const Map<int, String> _builtinCodes = <int, String>{
  0: 'General',
  1: '0',
  2: '0.00',
  3: '#,##0',
  4: '#,##0.00',
  5: r'"$"#,##0_);("$"#,##0)',
  6: r'"$"#,##0_);[Red]("$"#,##0)',
  7: r'"$"#,##0.00_);("$"#,##0.00)',
  8: r'"$"#,##0.00_);[Red]("$"#,##0.00)',
  9: '0%',
  10: '0.00%',
  11: '0.00E+00',
  12: '# ?/?',
  13: '# ??/??',
  14: 'mm-dd-yy',
  15: 'd-mmm-yy',
  16: 'd-mmm',
  17: 'mmm-yy',
  18: 'h:mm AM/PM',
  19: 'h:mm:ss AM/PM',
  20: 'h:mm',
  21: 'h:mm:ss',
  22: 'm/d/yy h:mm',
  37: '#,##0 ;(#,##0)',
  38: '#,##0 ;[Red](#,##0)',
  39: '#,##0.00;(#,##0.00)',
  40: '#,##0.00;[Red](#,##0.00)',
  41: r'_(* #,##0_);_(* \(#,##0\);_(* "-"_);_(@_)',
  42: r'_("$"* #,##0_);_("$"* \(#,##0\);_("$"* "-"_);_(@_)',
  43: r'_(* #,##0.00_);_(* \(#,##0.00\);_(* "-"??_);_(@_)',
  44:
      r'_("$"* #,##0.00_);_("$"* \(#,##0.00\);'
      r'_("$"* "-"??_);_(@_)',
  45: 'mm:ss',
  46: '[h]:mm:ss',
  47: 'mmss.0',
  48: '##0.0E+0',
  49: '@',
};

/// The en-US format code of the built-in number format [id], or `null` for
/// an id this table does not hold.
///
/// The table is ECMA-376 Part 1 §18.8.30: ids 0–22 and 37–49. Ids 23–36
/// and 50 and above are locale dependent, so they have no code here. A
/// differential style writes the code next to the id, because Excel does
/// not look the id up there.
String? builtinNumberFormatCode(int id) => _builtinCodes[id];
