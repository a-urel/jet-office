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

  test('neither list names an element twice', () {
    expect(pPrOrder.toSet(), hasLength(pPrOrder.length));
    expect(rPrOrder.toSet(), hasLength(rPrOrder.length));
  });
}
