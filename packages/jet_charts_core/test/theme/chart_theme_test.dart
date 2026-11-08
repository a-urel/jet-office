import 'package:jet_charts_core/jet_charts_core.dart';
import 'package:test/test.dart';

ChartTextStyle text(ChartColor color) =>
    ChartTextStyle(fontFamily: 'Test', size: 10, color: color);

ChartTheme custom({List<ChartColor>? palette}) {
  final ChartColor ink = ChartColor.rgb(0x333333);
  return ChartTheme(
    palette:
        palette ??
        <ChartColor>[
          ChartColor.rgb(0xFF0000),
          ChartColor.rgb(0x00AA00),
          ChartColor.rgb(0x0000FF),
          ChartColor.rgb(0xAAAA00),
          ChartColor.rgb(0x00AAAA),
        ],
    axisLabels: text(ink),
    titleText: text(ink),
    legendText: text(ink),
    dataLabels: text(ink),
    gridLine: ink,
    axisLine: ink,
    background: ink,
  );
}

void main() {
  test('office accents', () {
    // Verified 2026-11-06 against Office Theme.thmx of Excel for Mac 16.114.4.
    final ChartTheme office = ChartTheme.office;
    expect(office.palette.map((ChartColor c) => c.rgb).toList(), <int>[
      0x156082,
      0xE97132,
      0x196B24,
      0x0F9ED5,
      0xA02B93,
      0x4EA72E,
    ]);
    expect(office.palette.map((ChartColor c) => c.slot).toList(), <Object?>[
      ChartSchemeColor.accent1,
      ChartSchemeColor.accent2,
      ChartSchemeColor.accent3,
      ChartSchemeColor.accent4,
      ChartSchemeColor.accent5,
      ChartSchemeColor.accent6,
    ]);
  });

  test('office exports through the file theme', () {
    expect(ChartTheme.office.exportColors, ChartExportColors.fileTheme);
  });

  test('an app theme defaults to fixed colours', () {
    expect(custom().exportColors, ChartExportColors.fixed);
  });

  test('no silent repeat', () {
    for (final ChartTheme theme in <ChartTheme>[ChartTheme.office, custom()]) {
      final Set<int> seen = <int>{
        for (int i = 0; i < 24; i++) theme.seriesColor(i).rgb,
      };
      expect(seen, hasLength(24));
    }
  });

  test('the first pass is the palette itself, slots kept', () {
    final ChartTheme office = ChartTheme.office;
    for (int i = 0; i < 6; i++) {
      expect(office.seriesColor(i), office.palette[i]);
    }
    expect(office.seriesColor(6).slot, isNull);
    expect(office.seriesColor(6).rgb, isNot(office.palette[0].rgb));
  });

  test('derived colours follow the rule', () {
    final ChartTheme theme = custom(
      palette: <ChartColor>[ChartColor.rgb(0x806040)],
    );
    // p = 1: times 0.6. p = 2: toward white by 0.4. p = 3: times 0.36.
    expect(theme.seriesColor(1).rgb, 0x4D3A26);
    expect(theme.seriesColor(2).rgb, 0xB3A08C);
    expect(theme.seriesColor(3).rgb, 0x2E2317);
  });

  test('seriesColor never throws past the palette', () {
    expect(
      ChartTheme.office.seriesColor(100).rgb,
      inInclusiveRange(0, 0xFFFFFF),
    );
    expect(custom().seriesColor(100).slot, isNull);
    expect(() => ChartTheme.office.seriesColor(-1), throwsRangeError);
  });

  test('an empty palette throws ArgumentError', () {
    expect(() => custom(palette: <ChartColor>[]), throwsArgumentError);
  });

  test('a colour outside 0..0xFFFFFF throws ArgumentError', () {
    expect(() => ChartColor.rgb(-1), throwsArgumentError);
    expect(() => ChartColor.rgb(0x1000000), throwsArgumentError);
    expect(
      () => ChartColor.scheme(ChartSchemeColor.accent1, rgb: 0x1000000),
      throwsArgumentError,
    );
    expect(ChartColor.rgb(0xFFFFFF).rgb, 0xFFFFFF);
  });

  test('colours and text styles compare by value', () {
    expect(ChartColor.rgb(1), ChartColor.rgb(1));
    expect(ChartColor.rgb(1).hashCode, ChartColor.rgb(1).hashCode);
    expect(
      ChartColor.scheme(ChartSchemeColor.accent1, rgb: 1),
      isNot(ChartColor.rgb(1)),
    );
    expect(text(ChartColor.rgb(1)), text(ChartColor.rgb(1)));
    expect(text(ChartColor.rgb(1)).hashCode, text(ChartColor.rgb(1)).hashCode);
    expect(text(ChartColor.rgb(1)), isNot(text(ChartColor.rgb(2))));
    expect(
      ChartTextStyle(fontFamily: 'a', size: 1, color: ChartColor.rgb(1)),
      isNot(
        ChartTextStyle(
          fontFamily: 'a',
          size: 1,
          color: ChartColor.rgb(1),
          bold: true,
        ),
      ),
    );
  });

  test('a theme overrides defaults', () {
    final ChartTheme base = custom();
    expect(base.gapWidthPercent, 219);
    expect(base.lineWidth, 2.25);
    expect(base.markerSize, 5);
    final ChartTheme changed = base.copyWith(gapWidthPercent: 50);
    expect(changed.gapWidthPercent, 50);
    expect(changed.lineWidth, 2.25);
    expect(changed, isNot(base));
    expect(base.copyWith(), base);
    expect(base.copyWith().hashCode, base.hashCode);
  });

  test('palette and semantic are copied and unmodifiable', () {
    final List<ChartColor> palette = <ChartColor>[ChartColor.rgb(1)];
    final Map<String, ChartColor> semantic = <String, ChartColor>{
      'income': ChartColor.rgb(2),
    };
    final ChartTheme theme = custom(
      palette: palette,
    ).copyWith(semantic: semantic);
    palette.add(ChartColor.rgb(3));
    semantic['expense'] = ChartColor.rgb(4);
    expect(theme.palette, hasLength(1));
    expect(theme.semantic, hasLength(1));
    expect(() => theme.palette.add(ChartColor.rgb(5)), throwsUnsupportedError);
    expect(
      () => theme.semantic['x'] = ChartColor.rgb(5),
      throwsUnsupportedError,
    );
    expect(custom().semantic, isEmpty);
    expect(theme.semantic, <String, ChartColor>{'income': ChartColor.rgb(2)});
  });

  test('spacing is part of theme equality', () {
    final ChartTheme a = custom();
    expect(a.spacing, const ChartSpacing());
    final ChartTheme b = a.copyWith(spacing: const ChartSpacing(padding: 12));
    expect(b, isNot(a));
    expect(b.spacing.padding, 12);
    expect(a, a.copyWith(spacing: const ChartSpacing()));
    expect(a.hashCode, a.copyWith(spacing: const ChartSpacing()).hashCode);
    expect(b.hashCode, isNot(a.hashCode));
  });

  test('spacing defaults and copyWith', () {
    const ChartSpacing s = ChartSpacing();
    expect(s.padding, 8);
    expect(s.titleGap, 6);
    expect(s.legendGap, 6);
    expect(s.legendSymbol, 7);
    expect(s.legendItemGap, 12);
    expect(s.labelGap, 4);
    expect(s.minTextGap, 2);
    expect(s.tickLength, 0);
    expect(s.gridLineWidth, 0.75);
    expect(s.axisLineWidth, 0.75);
    expect(s.overlapPercent, -27);
    expect(s.copyWith(), s);
    expect(s.copyWith(tickLength: 4).tickLength, 4);
    expect(s.copyWith(tickLength: 4), isNot(s));
    expect(ChartTheme.office.spacing, s);
  });
}
