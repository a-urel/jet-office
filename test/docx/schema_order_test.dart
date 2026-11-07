import 'package:jet_office/src/docx/schema_order.dart';
import 'package:test/test.dart';

void main() {
  test('pPrOrder and rPrOrder match the transitional schema', () {
    // ECMA-376 Part 1 transitional: CT_PPrBase followed by rPr, sectPr and
    // pPrChange (CT_PPr), and EG_RPrBase followed by rPrChange (CT_RPr).
    expect(pPrOrder, <String>[
      'pStyle', 'keepNext', 'keepLines', 'pageBreakBefore', 'framePr', //
      'widowControl', 'numPr', 'suppressLineNumbers', 'pBdr', 'shd', 'tabs',
      'suppressAutoHyphens', 'kinsoku', 'wordWrap', 'overflowPunct',
      'topLinePunct', 'autoSpaceDE', 'autoSpaceDN', 'bidi', 'adjustRightInd',
      'snapToGrid', 'spacing', 'ind', 'contextualSpacing', 'mirrorIndents',
      'suppressOverlap', 'jc', 'textDirection', 'textAlignment',
      'textboxTightWrap', 'outlineLvl', 'divId', 'cnfStyle', 'rPr', 'sectPr',
      'pPrChange',
    ]);
    expect(rPrOrder, <String>[
      'rStyle', 'rFonts', 'b', 'bCs', 'i', 'iCs', 'caps', 'smallCaps', //
      'strike', 'dstrike', 'outline', 'shadow', 'emboss', 'imprint',
      'noProof', 'snapToGrid', 'vanish', 'webHidden', 'color', 'spacing', 'w',
      'kern', 'position', 'sz', 'szCs', 'highlight', 'u', 'effect', 'bdr',
      'shd', 'fitText', 'vertAlign', 'rtl', 'cs', 'em', 'lang',
      'eastAsianLayout', 'specVanish', 'oMath', 'rPrChange',
    ]);
  });

  test('pPrOrder and rPrOrder name no element twice', () {
    expect(pPrOrder.toSet(), hasLength(pPrOrder.length));
    expect(rPrOrder.toSet(), hasLength(rPrOrder.length));
  });

  test('pPrGeneralOrder is pPrOrder without rPr and sectPr', () {
    expect(
      pPrGeneralOrder,
      pPrOrder.where((String n) => n != 'rPr' && n != 'sectPr').toList(),
    );
    expect(pPrGeneralOrder.last, 'pPrChange');
  });

  test('styleOrder matches the transitional schema', () {
    expect(styleOrder, <String>[
      'name', 'aliases', 'basedOn', 'next', 'link', 'autoRedefine', //
      'hidden', 'uiPriority', 'semiHidden', 'unhideWhenUsed', 'qFormat',
      'locked', 'personal', 'personalCompose', 'personalReply', 'rsid',
      'pPr', 'rPr', 'tblPr', 'trPr', 'tcPr', 'tblStylePr',
    ]);
  });

  test('docDefaultsOrder matches the transitional schema', () {
    expect(docDefaultsOrder, <String>['rPrDefault', 'pPrDefault']);
    expect(rPrDefaultOrder, <String>['rPr']);
    expect(pPrDefaultOrder, <String>['pPr']);
  });

  test('lvlOrder matches the transitional schema', () {
    expect(lvlOrder, <String>[
      'start', 'numFmt', 'lvlRestart', 'pStyle', 'isLgl', 'suff', //
      'lvlText', 'lvlPicBulletId', 'legacy', 'lvlJc', 'pPr', 'rPr',
    ]);
  });

  test('abstractNumOrder matches the transitional schema', () {
    expect(abstractNumOrder, <String>[
      'nsid', 'multiLevelType', 'tmpl', 'name', 'styleLink', //
      'numStyleLink', 'lvl',
    ]);
  });

  test('numOrder matches the transitional schema', () {
    expect(numOrder, <String>['abstractNumId', 'lvlOverride']);
  });

  test('lvlOverrideOrder matches the transitional schema', () {
    expect(lvlOverrideOrder, <String>['startOverride', 'lvl']);
  });

  test('numPrOrder matches the transitional schema', () {
    expect(numPrOrder, <String>['ilvl', 'numId', 'numberingChange', 'ins']);
  });

  test('pBdrOrder matches the transitional schema', () {
    expect(pBdrOrder, <String>[
      'top', 'left', 'bottom', 'right', 'between', 'bar', //
    ]);
  });

  test('numberingOrder matches the transitional schema', () {
    expect(numberingOrder, <String>[
      'numPicBullet', 'abstractNum', 'num', 'numIdMacAtCleanup', //
    ]);
  });

  test('stylesOrder matches the transitional schema', () {
    expect(stylesOrder, <String>['docDefaults', 'latentStyles', 'style']);
  });

  test('tblPrOrder matches the transitional schema', () {
    expect(tblPrOrder, <String>[
      'tblStyle', 'tblpPr', 'tblOverlap', 'bidiVisual', //
      'tblStyleRowBandSize', 'tblStyleColBandSize', 'tblW', 'jc',
      'tblCellSpacing', 'tblInd', 'tblBorders', 'shd', 'tblLayout',
      'tblCellMar', 'tblLook', 'tblCaption', 'tblDescription', 'tblPrChange',
    ]);
  });

  test('trPrOrder matches the transitional schema', () {
    expect(trPrOrder, <String>[
      'cnfStyle', 'divId', 'gridBefore', 'gridAfter', 'wBefore', 'wAfter', //
      'cantSplit', 'trHeight', 'tblHeader', 'tblCellSpacing', 'jc', 'hidden',
      'ins', 'del', 'trPrChange',
    ]);
  });

  test('tcPrOrder matches the transitional schema', () {
    expect(tcPrOrder, <String>[
      'cnfStyle', 'tcW', 'gridSpan', 'hMerge', 'vMerge', 'tcBorders', //
      'shd', 'noWrap', 'tcMar', 'textDirection', 'tcFitText', 'vAlign',
      'hideMark', 'headers', 'cellIns', 'cellDel', 'cellMerge', 'tcPrChange',
    ]);
  });

  test('tblBordersOrder matches the transitional schema', () {
    expect(tblBordersOrder, <String>[
      'top', 'left', 'start', 'bottom', 'right', 'end', 'insideH', //
      'insideV',
    ]);
  });

  test('tcBordersOrder matches the transitional schema', () {
    expect(tcBordersOrder, <String>[
      'top', 'left', 'start', 'bottom', 'right', 'end', 'insideH', //
      'insideV', 'tl2br', 'tr2bl',
    ]);
  });

  test('tblCellMarOrder matches the transitional schema', () {
    expect(tblCellMarOrder, <String>[
      'top', 'left', 'start', 'bottom', 'right', 'end', //
    ]);
  });

  test('no list names an element twice', () {
    for (final List<String> order in <List<String>>[
      pPrGeneralOrder, styleOrder, docDefaultsOrder, lvlOrder, //
      abstractNumOrder, numOrder, lvlOverrideOrder, numPrOrder, pBdrOrder,
      numberingOrder, stylesOrder, tblPrOrder, trPrOrder, tcPrOrder,
      tblBordersOrder, tcBordersOrder, tblCellMarOrder,
    ]) {
      expect(order.toSet(), hasLength(order.length));
    }
  });

  test('sectPrOrder matches the transitional schema', () {
    // CT_SectPrBase after the header and footer references, as the Open XML
    // SDK (3.5.1) orders the members.
    expect(sectPrOrder, <String>[
      'headerReference', 'footerReference', 'footnotePr', 'endnotePr', //
      'type', 'pgSz', 'pgMar', 'paperSrc', 'pgBorders', 'lnNumType',
      'pgNumType', 'cols', 'formProt', 'vAlign', 'noEndnote', 'titlePg',
      'textDirection', 'bidi', 'rtlGutter', 'docGrid', 'printerSettings',
      'sectPrChange',
    ]);
  });
}
