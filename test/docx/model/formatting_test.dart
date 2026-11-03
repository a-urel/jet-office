// Tests the shared formatting values (colour, shading, border): validation
// at construction, rounding to the file's units, and equality by value.
// They need no file, so they run on the web as well.
import 'package:jet_office/src/docx/model/formatting.dart';
import 'package:jet_office/src/docx/units.dart';
import 'package:test/test.dart';

void main() {
  group('DocxColor', () {
    test('rgb is upper-cased and FF00 throws ArgumentError', () {
      expect(DocxColor.rgb('ff8a0b').rgb, 'FF8A0B');
      expect(() => DocxColor.rgb('FF00'), throwsArgumentError);
      expect(() => DocxColor.rgb('red'), throwsArgumentError);
      expect(() => DocxColor.rgb('GG0000'), throwsArgumentError);
      expect(() => DocxColor.rgb('auto'), throwsArgumentError);
      expect(() => DocxColor.rgb('FF00000'), throwsArgumentError);
    });

    test('theme tint 256 throws RangeError', () {
      expect(
        () => DocxColor.theme(DocxThemeColor.accent1, tint: 256),
        throwsRangeError,
      );
      expect(
        () => DocxColor.theme(DocxThemeColor.accent1, shade: -1),
        throwsRangeError,
      );
      final DocxColor c = DocxColor.theme(
        DocxThemeColor.accent1,
        tint: 255,
        shade: 0,
      );
      expect(c.tint, 255);
      expect(c.shade, 0);
      expect(c.themeColor, DocxThemeColor.accent1);
      expect(c.rgb, isNull);
      expect(c.isAuto, isFalse);
    });

    test('auto is a constant with only isAuto set', () {
      const DocxColor c = DocxColor.auto;
      expect(c.isAuto, isTrue);
      expect(c.rgb, isNull);
      expect(c.themeColor, isNull);
    });

    test('values are equal by value', () {
      expect(DocxColor.rgb('ff0000'), DocxColor.rgb('FF0000'));
      expect(
        DocxColor.rgb('ff0000').hashCode,
        DocxColor.rgb('FF0000').hashCode,
      );
      expect(DocxColor.rgb('FF0000'), isNot(DocxColor.auto));
      expect(
        DocxColor.theme(DocxThemeColor.text1, tint: 1),
        DocxColor.theme(DocxThemeColor.text1, tint: 1),
      );
      expect(
        DocxColor.theme(DocxThemeColor.text1, tint: 1),
        isNot(DocxColor.theme(DocxThemeColor.text1, shade: 1)),
      );
    });
  });

  group('DocxBorder', () {
    test('border widthPt 0.3 rounds to 0.25 and 13 throws RangeError', () {
      expect(DocxBorder(widthPt: 0.3).widthPt, 0.25);
      expect(DocxBorder(widthPt: 12).widthPt, 12);
      expect(DocxBorder(widthPt: 0.25).widthPt, 0.25);
      expect(() => DocxBorder(widthPt: 13), throwsRangeError);
      expect(() => DocxBorder(widthPt: 0.1), throwsRangeError);
      expect(() => DocxBorder(spacePt: 32), throwsRangeError);
      expect(() => DocxBorder(spacePt: -1), throwsRangeError);
      expect(DocxBorder(spacePt: 3.4).spacePt, 3);
    });

    test('NaN and infinity throw ArgumentError', () {
      expect(() => DocxBorder(widthPt: double.nan), throwsArgumentError);
      expect(() => DocxBorder(widthPt: double.infinity), throwsArgumentError);
      expect(
        () => DocxBorder(spacePt: double.negativeInfinity),
        throwsArgumentError,
      );
      expect(() => DocxBorder(widthPt: 1e300), throwsRangeError);
    });

    test('values are equal by their stored units', () {
      expect(DocxBorder(widthPt: 0.5), DocxBorder());
      expect(DocxBorder(widthPt: 0.51), DocxBorder(widthPt: 0.5));
      expect(DocxBorder(widthPt: 0.51).hashCode, DocxBorder().hashCode);
      expect(DocxBorder(shadow: true), isNot(DocxBorder()));
      expect(
        DocxBorder(color: DocxColor.auto),
        isNot(DocxBorder(color: DocxColor.rgb('000000'))),
      );
    });
  });

  test('shadings are equal by value', () {
    expect(const DocxShading(), const DocxShading());
    expect(
      DocxShading(fill: DocxColor.rgb('ffff00')),
      DocxShading(fill: DocxColor.rgb('FFFF00')),
    );
    expect(
      const DocxShading(pattern: DocxShadingPattern.solid),
      isNot(const DocxShading()),
    );
  });

  test('the enums have 17, 38 and 27 values', () {
    expect(DocxThemeColor.values, hasLength(17));
    expect(DocxShadingPattern.values, hasLength(38));
    expect(DocxBorderStyle.values, hasLength(27));
  });

  group('units', () {
    test('round half away from zero to the file unit', () {
      expect(twipsOf(0.025, 'x', min: -10, max: 10), 1);
      expect(twipsOf(-0.025, 'x', min: -10, max: 10), -1);
      expect(halfPointsOf(10.75, 'x', min: 1, max: 100), 22);
      expect(eighthsOf(0.3, 'x', min: 2, max: 96), 2);
      expect(pointsOf(2.5, 'x', min: 0, max: 31), 3);
      expect(ptOfTwips(30), 1.5);
      expect(ptOfHalfPoints(23), 11.5);
      expect(ptOfEighths(4), 0.5);
    });

    test('NaN and infinity throw ArgumentError, out of range RangeError', () {
      expect(
        () => twipsOf(double.nan, 'x', min: 0, max: 5),
        throwsArgumentError,
      );
      expect(
        () => halfPointsOf(double.infinity, 'x', min: 0, max: 5),
        throwsArgumentError,
      );
      expect(() => twipsOf(1, 'x', min: 0, max: 5), throwsRangeError);
      expect(() => twipsOf(-1, 'x', min: 0, max: 5), throwsRangeError);
      expect(() => twipsOf(1e300, 'x', min: 0, max: 5), throwsRangeError);
      expect(() => twipsOf(-1e300, 'x', min: 0, max: 5), throwsRangeError);
      // Rounding first: 0.2 pt is 4 twips, in range.
      expect(twipsOf(0.2, 'x', min: 0, max: 5), 4);
    });
  });
}
