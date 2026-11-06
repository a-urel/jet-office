/// Number format codes jet_office's workbook fixtures store, as constants.
///
/// The fuzz corpus of jet_office's tests read every code of its `allFixtures()`
/// workbooks. jet_core has no workbooks, so the codes that neither the
/// built-in table, the three shipped locales nor `test_codes.dart` already
/// give are listed here, in the order the corpus met them. Fixed at the
/// extraction (jet_office commit 632115d) so the fuzz cases of a seed stay
/// the cases jet_office's fuzzer made.
library;

/// The fixture codes the corpus adds after the locale codes.
const List<String> fixtureFormatCodes = <String>[
  '#,##0.000',
  '0.00;[Red]-0.00',
  '0.0%',
  '#,##0.00" ₺"',
  '"\$"#,##0.00',
  '#,##0" €";[Red]-#,##0" €"',
  '#,##0.00" €"',
  'yyyy-mm-dd',
];
