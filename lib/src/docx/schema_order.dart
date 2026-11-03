/// The schema order of the children of `w:pPr` and `w:rPr`.
///
/// Not ported from Quds; written for jet_office.
///
/// Word repairs a document whose property children are out of the order
/// the schema gives, so a writer puts them in that order. Both lists hold
/// local names in the WordprocessingML main namespace (`w:`), from
/// ECMA-376 Part 1, transitional `wml.xsd`.
library;

/// The children of a paragraph's `w:pPr` (`CT_PPr`, §17.3.1.26), in order:
/// the `CT_PPrBase` sequence, then `rPr`, `sectPr` and `pPrChange`.
const List<String> pPrOrder = <String>[
  'pStyle',
  'keepNext',
  'keepLines',
  'pageBreakBefore',
  'framePr',
  'widowControl',
  'numPr',
  'suppressLineNumbers',
  'pBdr',
  'shd',
  'tabs',
  'suppressAutoHyphens',
  'kinsoku',
  'wordWrap',
  'overflowPunct',
  'topLinePunct',
  'autoSpaceDE',
  'autoSpaceDN',
  'bidi',
  'adjustRightInd',
  'snapToGrid',
  'spacing',
  'ind',
  'contextualSpacing',
  'mirrorIndents',
  'suppressOverlap',
  'jc',
  'textDirection',
  'textAlignment',
  'textboxTightWrap',
  'outlineLvl',
  'divId',
  'cnfStyle',
  'rPr',
  'sectPr',
  'pPrChange',
];

/// The children of a run's `w:rPr` (`CT_RPr`, §17.3.2.28), in order: the
/// `EG_RPrBase` sequence, then `rPrChange`.
const List<String> rPrOrder = <String>[
  'rStyle',
  'rFonts',
  'b',
  'bCs',
  'i',
  'iCs',
  'caps',
  'smallCaps',
  'strike',
  'dstrike',
  'outline',
  'shadow',
  'emboss',
  'imprint',
  'noProof',
  'snapToGrid',
  'vanish',
  'webHidden',
  'color',
  'spacing',
  'w',
  'kern',
  'position',
  'sz',
  'szCs',
  'highlight',
  'u',
  'effect',
  'bdr',
  'shd',
  'fitText',
  'vertAlign',
  'rtl',
  'cs',
  'em',
  'lang',
  'eastAsianLayout',
  'specVanish',
  'oMath',
  'rPrChange',
];
