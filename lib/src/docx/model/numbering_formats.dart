/// The values of a numbering level: its number format and its alignment.
///
/// Not ported from Quds; transcribed from ECMA-376 Part 1, §17.18.59
/// (`ST_NumberFormat`) and §17.18.44 (`ST_Jc`), for jet_office. They live
/// apart from the numbering model so that the codecs that read them
/// (`numbering_schemas.dart`) and the model can both import them.
library;

/// How a numbering level shows its number (`w:numFmt`): the formats the
/// model types, spelled in the file as the value's name.
///
/// The other values of `ST_NumberFormat` (`chicago`, the East Asian and
/// other scripts' counting systems) and a `w:numFmt` with `w:format` read
/// `null` and are written back as read.
enum DocxNumberFormat {
  /// Arabic numerals: 1, 2, 3.
  decimal,

  /// Arabic numerals with a leading zero below ten: 01, 02, … 10.
  decimalZero,

  /// Upper-case Roman numerals: I, II, III.
  upperRoman,

  /// Lower-case Roman numerals: i, ii, iii.
  lowerRoman,

  /// Upper-case letters: A, B, C.
  upperLetter,

  /// Lower-case letters: a, b, c.
  lowerLetter,

  /// Ordinal numbers: 1st, 2nd, 3rd (in the document's language).
  ordinal,

  /// Cardinal numbers as text: One, Two, Three.
  cardinalText,

  /// Ordinal numbers as text: First, Second, Third.
  ordinalText,

  /// A bullet: the level text is shown as it is.
  bullet,

  /// No number.
  none,
}

/// Where a level's number sits against the indentation (`w:lvlJc`).
enum DocxLevelAlignment {
  /// The number starts at the indentation, on the left.
  left,

  /// The number is centered on the indentation.
  center,

  /// The number ends at the indentation, on the right.
  right,

  /// The number starts at the indentation on the reading side (left in
  /// left-to-right text).
  start,

  /// The number ends at the indentation on the reading side.
  end,
}
