/// The schema order of the children of the property and style containers.
///
/// Not ported from Quds; written for jet_office.
///
/// Word repairs a document whose children are out of the order the schema
/// gives, so a writer puts them in that order. Each list holds local names
/// in the WordprocessingML main namespace (`w:`), from ECMA-376 Part 1,
/// transitional `wml.xsd`; each was checked against the member order of the
/// Open XML SDK (3.5.1), which is generated from it.
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
/// `EG_RPrBase` sequence, then `rPrChange`. In the schema `EG_RPrBase` is a
/// choice, so any order validates; this list is the order Word writes and
/// is not the order of `CT_ParaRPr` (a paragraph mark's `rPr`), which puts
/// the revision marks `ins`, `del`, `moveFrom` and `moveTo` first.
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

/// The children of `w:pPr` inside a style, a numbering level or a
/// paragraph-properties default (`CT_PPrGeneral`, §17.7.6.1): `pPrOrder`
/// without `rPr` and `sectPr`, ending with `pPrChange`.
const List<String> pPrGeneralOrder = <String>[
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
  'pPrChange',
];

/// The children of a `w:style` (`CT_Style`, §17.7.4.17), in order.
const List<String> styleOrder = <String>[
  'name',
  'aliases',
  'basedOn',
  'next',
  'link',
  'autoRedefine',
  'hidden',
  'uiPriority',
  'semiHidden',
  'unhideWhenUsed',
  'qFormat',
  'locked',
  'personal',
  'personalCompose',
  'personalReply',
  'rsid',
  'pPr',
  'rPr',
  'tblPr',
  'trPr',
  'tcPr',
  'tblStylePr',
];

/// The children of `w:docDefaults` (`CT_DocDefaults`, §17.7.5.1), in order.
const List<String> docDefaultsOrder = <String>['rPrDefault', 'pPrDefault'];

/// The children of `w:rPrDefault` (`CT_RPrDefault`, §17.7.5.3): the run
/// properties default.
const List<String> rPrDefaultOrder = <String>['rPr'];

/// The children of `w:pPrDefault` (`CT_PPrDefault`, §17.7.5.2): the
/// paragraph properties default.
const List<String> pPrDefaultOrder = <String>['pPr'];

/// The children of a `w:lvl` (`CT_Lvl`, §17.9.6), in order.
const List<String> lvlOrder = <String>[
  'start',
  'numFmt',
  'lvlRestart',
  'pStyle',
  'isLgl',
  'suff',
  'lvlText',
  'lvlPicBulletId',
  'legacy',
  'lvlJc',
  'pPr',
  'rPr',
];

/// The children of a `w:abstractNum` (`CT_AbstractNum`, §17.9.1), in order.
const List<String> abstractNumOrder = <String>[
  'nsid',
  'multiLevelType',
  'tmpl',
  'name',
  'styleLink',
  'numStyleLink',
  'lvl',
];

/// The children of a `w:num` (`CT_Num`, §17.9.15), in order.
const List<String> numOrder = <String>['abstractNumId', 'lvlOverride'];

/// The children of a `w:lvlOverride` (`CT_NumLvl`, §17.9.8), in order.
const List<String> lvlOverrideOrder = <String>['startOverride', 'lvl'];

/// The children of a `w:numPr` (`CT_NumPr`, §17.3.1.19), in order.
const List<String> numPrOrder = <String>[
  'ilvl',
  'numId',
  'numberingChange',
  'ins',
];

/// The children of a `w:pBdr` (`CT_PBdr`, §17.3.1.24), in order.
const List<String> pBdrOrder = <String>[
  'top',
  'left',
  'bottom',
  'right',
  'between',
  'bar',
];

/// The children of the root `w:numbering` (`CT_Numbering`, §17.9.17), in
/// order.
const List<String> numberingOrder = <String>[
  'numPicBullet',
  'abstractNum',
  'num',
  'numIdMacAtCleanup',
];

/// The children of the root `w:styles` (`CT_Styles`, §17.7.4.18), in order.
const List<String> stylesOrder = <String>[
  'docDefaults',
  'latentStyles',
  'style',
];

/// The children of a table's `w:tblPr` (`CT_TblPr`, §17.4.60), in order: the
/// `CT_TblPrBase` sequence, then `tblPrChange`.
const List<String> tblPrOrder = <String>[
  'tblStyle',
  'tblpPr',
  'tblOverlap',
  'bidiVisual',
  'tblStyleRowBandSize',
  'tblStyleColBandSize',
  'tblW',
  'jc',
  'tblCellSpacing',
  'tblInd',
  'tblBorders',
  'shd',
  'tblLayout',
  'tblCellMar',
  'tblLook',
  'tblCaption',
  'tblDescription',
  'tblPrChange',
];

/// The children of a row's `w:trPr` (`CT_TrPr`, §17.4.82), in order. In the
/// schema `CT_TrPrBase` is a choice, so any order validates; this list is
/// the order Word writes, followed by the revision children `ins`, `del`
/// and `trPrChange`.
const List<String> trPrOrder = <String>[
  'cnfStyle',
  'divId',
  'gridBefore',
  'gridAfter',
  'wBefore',
  'wAfter',
  'cantSplit',
  'trHeight',
  'tblHeader',
  'tblCellSpacing',
  'jc',
  'hidden',
  'ins',
  'del',
  'trPrChange',
];

/// The children of a cell's `w:tcPr` (`CT_TcPr`, §17.4.70), in order: the
/// `CT_TcPrBase` sequence, then the revision children.
const List<String> tcPrOrder = <String>[
  'cnfStyle',
  'tcW',
  'gridSpan',
  'hMerge',
  'vMerge',
  'tcBorders',
  'shd',
  'noWrap',
  'tcMar',
  'textDirection',
  'tcFitText',
  'vAlign',
  'hideMark',
  'headers',
  'cellIns',
  'cellDel',
  'cellMerge',
  'tcPrChange',
];

/// The children of a table's `w:tblBorders` (`CT_TblBorders`, §17.4.38), in
/// order. `start` and `end` are the newer names of `left` and `right`; a
/// file holds one or the other.
const List<String> tblBordersOrder = <String>[
  'top',
  'left',
  'start',
  'bottom',
  'right',
  'end',
  'insideH',
  'insideV',
];

/// The children of a cell's `w:tcBorders` (`CT_TcBorders`, §17.4.66), in
/// order: `tblBordersOrder` then the two diagonals.
const List<String> tcBordersOrder = <String>[
  'top',
  'left',
  'start',
  'bottom',
  'right',
  'end',
  'insideH',
  'insideV',
  'tl2br',
  'tr2bl',
];

/// The children of a table's `w:tblCellMar` (`CT_TblCellMar`, §17.4.43), in
/// order.
const List<String> tblCellMarOrder = <String>[
  'top',
  'left',
  'start',
  'bottom',
  'right',
  'end',
];

/// The children of a section's `w:sectPr` (`CT_SectPr`, §17.6.17), in order:
/// the header and footer references, then the `CT_SectPrBase` sequence
/// (`EG_HdrFtrReferences` come first and each repeats), then `sectPrChange`;
/// checked against the member order of the Open XML SDK (3.5.1).
const List<String> sectPrOrder = <String>[
  'headerReference',
  'footerReference',
  'footnotePr',
  'endnotePr',
  'type',
  'pgSz',
  'pgMar',
  'paperSrc',
  'pgBorders',
  'lnNumType',
  'pgNumType',
  'cols',
  'formProt',
  'vAlign',
  'noEndnote',
  'titlePg',
  'textDirection',
  'bidi',
  'rtlGutter',
  'docGrid',
  'printerSettings',
  'sectPrChange',
];
