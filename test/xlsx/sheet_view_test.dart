import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/xlsx/sheet_view.dart'
    show checkPane, checkSheetView;
import 'package:test/test.dart';

void main() {
  group('XlsxSheetView', () {
    test('defaults are Excel\'s defaults', () {
      const XlsxSheetView view = XlsxSheetView();
      expect(view.zoom, 100);
      expect(view.showGridLines, isTrue);
      expect(view.showHeadings, isTrue);
      expect(view.rightToLeft, isFalse);
      expect(view.showZeros, isTrue);
      expect(view.showFormulas, isFalse);
      expect(view.pane, isNull);
    });

    test('compares by value', () {
      expect(const XlsxSheetView(zoom: 85), const XlsxSheetView(zoom: 85));
      expect(
        const XlsxSheetView(zoom: 85).hashCode,
        const XlsxSheetView(zoom: 85).hashCode,
      );
      expect(const XlsxSheetView(zoom: 85), isNot(const XlsxSheetView()));
      expect(
        const XlsxSheetView(pane: XlsxPane.frozen(rows: 1)),
        isNot(const XlsxSheetView(pane: XlsxPane.frozen(rows: 2))),
      );
    });

    test('copyWith replaces only the named fields', () {
      const XlsxSheetView view = XlsxSheetView(
        zoom: 85,
        showGridLines: false,
        pane: XlsxPane.frozen(rows: 1),
      );
      expect(view.copyWith(), view);
      final XlsxSheetView changed = view.copyWith(
        zoom: 120,
        showHeadings: false,
        rightToLeft: true,
        showZeros: false,
        showFormulas: true,
        pane: const XlsxPane.split(x: 10),
      );
      expect(
        changed,
        const XlsxSheetView(
          zoom: 120,
          showGridLines: false,
          showHeadings: false,
          rightToLeft: true,
          showZeros: false,
          showFormulas: true,
          pane: XlsxPane.split(x: 10),
        ),
      );
    });

    test('toString names the non-default fields', () {
      expect(const XlsxSheetView().toString(), 'XlsxSheetView()');
      expect(
        const XlsxSheetView(zoom: 85, rightToLeft: true).toString(),
        'XlsxSheetView(zoom: 85, rightToLeft: true)',
      );
    });
  });

  group('XlsxPane', () {
    test('compares by value and tells frozen from split', () {
      expect(const XlsxPane.frozen(rows: 1), const XlsxPane.frozen(rows: 1));
      expect(
        const XlsxPane.frozen(rows: 1).hashCode,
        const XlsxPane.frozen(rows: 1).hashCode,
      );
      expect(const XlsxPane.split(x: 1), const XlsxPane.split(x: 1));
      expect(const XlsxPane.frozen(rows: 1), isNot(const XlsxPane.split(y: 1)));
      expect(const XlsxPane.frozen(columns: 1).isFrozen, isTrue);
      expect(const XlsxPane.split(x: 1).isFrozen, isFalse);
    });

    test('compares split offsets as the rounded twips written', () {
      // 10.02 and 9.99 points are 200.4 and 199.8 twips, both written 200.
      for (final (XlsxPane a, XlsxPane b) in <(XlsxPane, XlsxPane)>[
        (const XlsxPane.split(x: 10), const XlsxPane.split(x: 10.02)),
        (const XlsxPane.split(y: 10), const XlsxPane.split(y: 9.99)),
        (const XlsxPane.split(x: 0.01), const XlsxPane.split()),
        (const XlsxPane.split(x: -0.01), const XlsxPane.split()),
      ]) {
        expect(a, b, reason: '$a, $b');
        expect(a.hashCode, b.hashCode, reason: '$a, $b');
      }
      // 10.03 points is 200.6 twips, written 201.
      expect(
        const XlsxPane.split(x: 10),
        isNot(const XlsxPane.split(x: 10.03)),
      );
      // Not constants, so the two panes are distinct instances.
      final double nan = double.parse('NaN');
      expect(XlsxPane.split(x: nan), XlsxPane.split(x: -nan));
      expect(XlsxPane.split(x: nan).hashCode, XlsxPane.split(x: -nan).hashCode);
    });

    test('toString', () {
      expect(
        const XlsxPane.frozen(rows: 1, columns: 2).toString(),
        'XlsxPane.frozen(rows: 1, columns: 2)',
      );
      expect(
        const XlsxPane.split(x: 100, y: 50).toString(),
        'XlsxPane.split(x: 100, y: 50)',
      );
      // Not yet validated, so toString must not throw on it.
      expect(
        const XlsxPane.split(x: double.nan, y: double.infinity).toString(),
        'XlsxPane.split(x: NaN, y: Infinity)',
      );
    });
  });

  test('XlsxSheetVisibility has the three SpreadsheetML states', () {
    expect(XlsxSheetVisibility.values, <XlsxSheetVisibility>[
      XlsxSheetVisibility.visible,
      XlsxSheetVisibility.hidden,
      XlsxSheetVisibility.veryHidden,
    ]);
  });

  group('XlsxLimits zoom', () {
    test('is 10 to 400', () {
      expect(XlsxLimits.minZoom, 10);
      expect(XlsxLimits.maxZoom, 400);
    });
  });

  group('checkSheetView and checkPane', () {
    Matcher rejects(String field) => throwsA(
      isA<ArgumentError>().having((ArgumentError e) => e.name, 'name', field),
    );

    test('accept the limits', () {
      checkSheetView(const XlsxSheetView(zoom: 10));
      checkSheetView(const XlsxSheetView(zoom: 400));
      checkPane(const XlsxPane.frozen(rows: 1048575, columns: 16383));
      checkPane(const XlsxPane.split(x: 0, y: 1e6));
    });

    test('reject a zoom outside 10 to 400', () {
      expect(
        () => checkSheetView(const XlsxSheetView(zoom: 9)),
        rejects('zoom'),
      );
      expect(
        () => checkSheetView(const XlsxSheetView(zoom: 401)),
        rejects('zoom'),
      );
    });

    test('reject frozen counts out of range', () {
      expect(() => checkPane(const XlsxPane.frozen(rows: -1)), rejects('rows'));
      expect(
        () => checkPane(const XlsxPane.frozen(rows: 1048576)),
        rejects('rows'),
      );
      expect(
        () => checkPane(const XlsxPane.frozen(columns: 16384)),
        rejects('columns'),
      );
    });

    test('accept a split offset up to 2^31 - 1 twips, rounded (R12)', () {
      // 107,374,182.35 points are 2,147,483,647 twips; 107,374,182.374 are
      // 2,147,483,647.48 twips, which round down to it.
      checkPane(const XlsxPane.split(x: 107374182.35));
      checkPane(const XlsxPane.split(y: 107374182.374));
    });

    test('reject a split offset past 2^31 - 1 twips (R12)', () {
      // 2,147,483,647.5 twips round up to 2^31.
      expect(
        () => checkPane(const XlsxPane.split(x: 107374182.375)),
        rejects('x'),
      );
      expect(
        () => checkPane(const XlsxPane.split(y: 107374182.4)),
        rejects('y'),
      );
      expect(() => checkPane(const XlsxPane.split(x: 1e308)), rejects('x'));
      expect(
        () => checkPane(const XlsxPane.split(y: double.maxFinite)),
        rejects('y'),
      );
    });

    test('reject split offsets that are negative, NaN or infinite', () {
      expect(() => checkPane(const XlsxPane.split(x: -1)), rejects('x'));
      expect(() => checkPane(const XlsxPane.split(y: -1)), rejects('y'));
      expect(
        () => checkPane(const XlsxPane.split(x: double.nan)),
        rejects('x'),
      );
      expect(
        () => checkPane(const XlsxPane.split(y: double.infinity)),
        rejects('y'),
      );
    });
  });
}
