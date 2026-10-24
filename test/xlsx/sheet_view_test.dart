import 'package:jet_office/jet_office.dart';
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

    test('toString', () {
      expect(
        const XlsxPane.frozen(rows: 1, columns: 2).toString(),
        'XlsxPane.frozen(rows: 1, columns: 2)',
      );
      expect(
        const XlsxPane.split(x: 100, y: 50).toString(),
        'XlsxPane.split(x: 100, y: 50)',
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
}
