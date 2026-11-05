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

  test('no list names an element twice', () {
    for (final List<String> order in <List<String>>[
      pPrGeneralOrder, styleOrder, docDefaultsOrder, lvlOrder, //
      abstractNumOrder, numOrder, lvlOverrideOrder, numPrOrder, pBdrOrder,
      numberingOrder, stylesOrder,
    ]) {
      expect(order.toSet(), hasLength(order.length));
    }
  });
}
