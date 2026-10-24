import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/xlsx/alignment.dart' as impl;
import 'package:test/test.dart';

void main() {
  group('alignmentXml', () {
    test('horizontal, vertical and wrap', () {
      expect(
        impl.alignmentXml(
          const XlsxAlignment(
            horizontal: XlsxHorizontalAlignment.center,
            vertical: XlsxVerticalAlignment.center,
            wrapText: true,
          ),
        ),
        '<alignment horizontal="center" vertical="center" wrapText="1"/>',
      );
    });

    test('indent', () {
      expect(
        impl.alignmentXml(
          const XlsxAlignment(
            horizontal: XlsxHorizontalAlignment.left,
            indent: 2,
          ),
        ),
        '<alignment horizontal="left" indent="2"/>',
      );
    });

    test('rotation and reading order', () {
      expect(
        impl.alignmentXml(const XlsxAlignment(textRotation: 90)),
        '<alignment textRotation="90"/>',
      );
      expect(
        impl.alignmentXml(
          const XlsxAlignment(readingOrder: XlsxReadingOrder.rightToLeft),
        ),
        '<alignment readingOrder="2"/>',
      );
      expect(
        impl.alignmentXml(
          const XlsxAlignment(readingOrder: XlsxReadingOrder.leftToRight),
        ),
        '<alignment readingOrder="1"/>',
      );
      expect(XlsxAlignment.verticalText, 255);
    });

    test('attribute order follows the Excel order', () {
      expect(
        impl.alignmentXml(
          const XlsxAlignment(
            readingOrder: XlsxReadingOrder.rightToLeft,
            shrinkToFit: true,
            justifyLastLine: true,
            indent: 1,
            wrapText: true,
            textRotation: 45,
            vertical: XlsxVerticalAlignment.distributed,
            horizontal: XlsxHorizontalAlignment.centerContinuous,
          ),
        ),
        '<alignment horizontal="centerContinuous" vertical="distributed" '
        'textRotation="45" wrapText="1" indent="1" justifyLastLine="1" '
        'shrinkToFit="1" readingOrder="2"/>',
      );
    });

    test('all defaults, set or not, give null', () {
      expect(impl.alignmentXml(null), isNull);
      expect(impl.alignmentXml(const XlsxAlignment()), isNull);
      expect(
        impl.alignmentXml(
          const XlsxAlignment(
            horizontal: XlsxHorizontalAlignment.general,
            vertical: XlsxVerticalAlignment.bottom,
            wrapText: false,
            indent: 0,
            textRotation: 0,
            shrinkToFit: false,
            justifyLastLine: false,
            readingOrder: XlsxReadingOrder.context,
          ),
        ),
        isNull,
      );
    });

    test('a column alignment merged with a bottom cell alignment is null', () {
      final XlsxAlignment merged = const XlsxAlignment(
        vertical: XlsxVerticalAlignment.center,
      ).merge(const XlsxAlignment(vertical: XlsxVerticalAlignment.bottom));
      expect(impl.alignmentXml(merged), isNull);
    });

    test('merge keeps fields the other leaves null', () {
      const XlsxAlignment base = XlsxAlignment(
        horizontal: XlsxHorizontalAlignment.right,
        wrapText: true,
      );
      final XlsxAlignment merged = base.merge(
        const XlsxAlignment(wrapText: false, indent: 3),
      );
      expect(merged.horizontal, XlsxHorizontalAlignment.right);
      expect(merged.wrapText, false);
      expect(merged.indent, 3);
      expect(base.merge(null), same(base));
    });
  });

  group('protectionXml', () {
    test('locked false and hidden true', () {
      expect(
        impl.protectionXml(const XlsxProtection(locked: false)),
        '<protection locked="0"/>',
      );
      expect(
        impl.protectionXml(const XlsxProtection(hidden: true)),
        '<protection hidden="1"/>',
      );
      expect(
        impl.protectionXml(const XlsxProtection(locked: false, hidden: true)),
        '<protection locked="0" hidden="1"/>',
      );
    });

    test('the defaults give null', () {
      expect(impl.protectionXml(null), isNull);
      expect(impl.protectionXml(const XlsxProtection()), isNull);
      expect(
        impl.protectionXml(const XlsxProtection(locked: true, hidden: false)),
        isNull,
      );
    });

    test('merge, equality and toString', () {
      final XlsxProtection merged = const XlsxProtection(
        locked: false,
      ).merge(const XlsxProtection(hidden: true));
      expect(merged, const XlsxProtection(locked: false, hidden: true));
      expect(
        merged.hashCode,
        const XlsxProtection(locked: false, hidden: true).hashCode,
      );
      expect(merged, isNot(const XlsxProtection()));
      expect(merged.toString(), contains('hidden'));
      const XlsxProtection p = XlsxProtection();
      expect(p.merge(null), same(p));
    });
  });

  group('validateAlignment', () {
    void rejects(XlsxAlignment a, String field) {
      expect(
        () => impl.validateAlignment(a),
        throwsA(isA<ArgumentError>().having((e) => e.name, 'name', field)),
      );
    }

    test('indent beyond 250 or negative throws', () {
      rejects(const XlsxAlignment(indent: 251), 'indent');
      rejects(const XlsxAlignment(indent: -1), 'indent');
    });

    test('rotation outside 0..180 other than 255 throws', () {
      rejects(const XlsxAlignment(textRotation: 181), 'textRotation');
      rejects(const XlsxAlignment(textRotation: -1), 'textRotation');
      rejects(const XlsxAlignment(textRotation: 254), 'textRotation');
    });

    test('the limits themselves are accepted', () {
      for (final XlsxAlignment a in const <XlsxAlignment>[
        XlsxAlignment(indent: 0),
        XlsxAlignment(indent: 250),
        XlsxAlignment(textRotation: 0),
        XlsxAlignment(textRotation: 180),
        XlsxAlignment(textRotation: XlsxAlignment.verticalText),
      ]) {
        expect(() => impl.validateAlignment(a), returnsNormally);
      }
    });
  });

  test('alignment equality, hashCode and toString', () {
    const XlsxAlignment a = XlsxAlignment(
      horizontal: XlsxHorizontalAlignment.fill,
      indent: 1,
    );
    expect(
      a,
      const XlsxAlignment(horizontal: XlsxHorizontalAlignment.fill, indent: 1),
    );
    expect(
      a.hashCode,
      const XlsxAlignment(
        horizontal: XlsxHorizontalAlignment.fill,
        indent: 1,
      ).hashCode,
    );
    expect(a, isNot(const XlsxAlignment()));
    expect(a.toString(), contains('indent: 1'));
  });
}
