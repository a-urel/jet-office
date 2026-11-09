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

  test('no repeat over the 54 series of the Office cycle', () {
    final ChartTheme office = ChartTheme.office;
    final Set<int> seen = <int>{
      for (int i = 0; i < 54; i++) office.seriesColor(i).rgb,
    };
    expect(seen, hasLength(54));
  });

  test('the first pass is the palette itself, slots kept', () {
    final ChartTheme office = ChartTheme.office;
    for (int i = 0; i < 6; i++) {
      expect(office.seriesColor(i), office.palette[i]);
    }
  });

  test("series 7 and 8 are Excel's colors1 variation lumMod 0.6", () {
    // chart_defaults.xlsx, xl/charts/colors1.xml: the second variation.
    final ChartTheme office = ChartTheme.office;
    expect(
      office.seriesColor(6),
      ChartColor.scheme(ChartSchemeColor.accent1, rgb: 0x0D3A4E, lumMod: 0.6),
    );
    expect(
      office.seriesColor(7),
      ChartColor.scheme(ChartSchemeColor.accent2, rgb: 0x994010, lumMod: 0.6),
    );
  });

  test('series 13 is accent 1 at lumMod 0.8 and lumOff 0.2', () {
    expect(
      ChartTheme.office.seriesColor(12),
      ChartColor.scheme(
        ChartSchemeColor.accent1,
        rgb: 0x1F8EC0,
        lumMod: 0.8,
        lumOff: 0.2,
      ),
    );
  });

  test('every pass follows the variations of colors1', () {
    const List<(double, double)> variations = <(double, double)>[
      (1, 0),
      (0.6, 0),
      (0.8, 0.2),
      (0.8, 0),
      (0.6, 0.4),
      (0.5, 0),
      (0.7, 0.3),
      (0.7, 0),
      (0.5, 0.5),
    ];
    final ChartTheme office = ChartTheme.office;
    for (int i = 0; i < 60; i++) {
      final (double mod, double off) = variations[(i ~/ 6) % 9];
      final ChartColor color = office.seriesColor(i);
      expect(color.slot, office.palette[i % 6].slot, reason: 'series $i');
      expect(color.lumMod, mod, reason: 'series $i');
      expect(color.lumOff, off, reason: 'series $i');
    }
    // Past the ninth variation the cycle starts again.
    expect(office.seriesColor(54), office.palette[0]);
  });

  test('a fixed palette varies to a fixed colour', () {
    final ChartTheme theme = custom(
      palette: <ChartColor>[ChartColor.rgb(0x806040)],
    );
    expect(theme.seriesColor(1), ChartColor.rgb(0x4D3A26));
    expect(theme.seriesColor(1).slot, isNull);
  });

  test('a scheme colour with its own luminance composes', () {
    final ChartTheme theme = custom(
      palette: <ChartColor>[
        ChartColor.scheme(ChartSchemeColor.accent1, rgb: 0x156082, lumMod: 0.6),
        ChartColor.scheme(
          ChartSchemeColor.accent2,
          rgb: 0xE97132,
          lumMod: 0.75,
          lumOff: 0.5,
        ),
      ],
    );
    // 0.6 then 0.6: L * 0.36, still a scheme colour.
    final ChartColor composed = theme.seriesColor(2);
    expect(composed.slot, ChartSchemeColor.accent1);
    expect(composed.lumMod, closeTo(0.36, 1e-12));
    expect(composed.lumOff, 0);
    // 0.75 and 0.5 can pass 1 and be clamped: a fixed colour.
    final ChartColor fixed = theme.seriesColor(3);
    expect(fixed.slot, isNull);
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

  test("each bar kind and grouping has Excel's gap width and overlap", () {
    // The owner's chart_reference.xlsx (Excel for Mac 16.0300): clustered
    // column 219 and -27, clustered bar 182 and no overlap (0), every stacked
    // and percent stacked bar or column 150 and 100.
    final ChartTheme office = ChartTheme.office;
    expect(office.stackedGapWidthPercent, 150);
    expect(office.barGapWidthPercent, 182);
    expect(office.spacing.barOverlapPercent, 0);
    for (final (ChartKind kind, ChartGrouping grouping, double gap, double o)
        in <(ChartKind, ChartGrouping, double, double)>[
          (ChartKind.column, ChartGrouping.clustered, 219, -27),
          (ChartKind.column, ChartGrouping.stacked, 150, 100),
          (ChartKind.column, ChartGrouping.percentStacked, 150, 100),
          (ChartKind.bar, ChartGrouping.clustered, 182, 0),
          (ChartKind.bar, ChartGrouping.stacked, 150, 100),
          (ChartKind.bar, ChartGrouping.percentStacked, 150, 100),
        ]) {
      expect(office.gapWidthPercentOf(kind, grouping), gap, reason: '$kind');
      expect(office.overlapPercentOf(kind, grouping), o, reason: '$kind');
    }
    final ChartTheme changed = office.copyWith(
      gapWidthPercent: 100,
      stackedGapWidthPercent: 60,
      barGapWidthPercent: 80,
      spacing: office.spacing.copyWith(
        overlapPercent: 10,
        barOverlapPercent: -20,
      ),
    );
    expect(
      changed.gapWidthPercentOf(ChartKind.column, ChartGrouping.clustered),
      100,
    );
    expect(changed.gapWidthPercentOf(ChartKind.bar, ChartGrouping.stacked), 60);
    expect(
      changed.gapWidthPercentOf(ChartKind.bar, ChartGrouping.clustered),
      80,
    );
    expect(
      changed.overlapPercentOf(ChartKind.column, ChartGrouping.clustered),
      10,
    );
    expect(
      changed.overlapPercentOf(ChartKind.bar, ChartGrouping.clustered),
      -20,
    );
    expect(changed.overlapPercentOf(ChartKind.bar, ChartGrouping.stacked), 100);
    expect(changed, isNot(office));
    expect(office.copyWith(stackedGapWidthPercent: 1), isNot(office));
    expect(office.copyWith(barGapWidthPercent: 1), isNot(office));
    expect(
      office.copyWith(stackedGapWidthPercent: 1).hashCode,
      isNot(office.hashCode),
    );
  });

  test("office data labels are Excel's 404040", () {
    // chart_reference.xlsx, charts 20 and 21: `tx1` with lumMod 75000 and
    // lumOff 25000.
    final ChartColor color = ChartTheme.office.dataLabels.color;
    expect(color.rgb, 0x404040);
    expect(color.slot, ChartSchemeColor.dark1);
    expect(color.lumMod, 0.75);
    expect(color.lumOff, 0.25);
    expect(ChartTheme.office.dataLabels.size, 9);
    expect(ChartTheme.office.legendText.size, 9);
  });

  test("office theme has Excel's border and no value axis line", () {
    final ChartTheme office = ChartTheme.office;
    expect(office.border!.rgb, 0xD9D9D9);
    expect(office.borderWidth, 0.75);
    expect(office.valueAxisLine, isFalse);
    final ChartTheme plain = custom();
    expect(plain.border, isNull);
    expect(plain.borderWidth, 0.75);
    expect(plain.valueAxisLine, isTrue);
    final ChartTheme changed = office.copyWith(
      border: ChartColor.rgb(0x112233),
      borderWidth: 2,
      valueAxisLine: true,
    );
    expect(changed.border!.rgb, 0x112233);
    expect(changed.borderWidth, 2);
    expect(changed.valueAxisLine, isTrue);
    expect(changed, isNot(office));
    expect(office.copyWith(valueAxisLine: true), isNot(office));
    expect(office.copyWith(borderWidth: 1), isNot(office));
    expect(office.copyWith(border: ChartColor.rgb(1)), isNot(office));
    expect(office.copyWith(), office);
    expect(office.copyWith().hashCode, office.hashCode);
  });

  test("office tooltip is this library's own look", () {
    final ChartTooltipStyle office = ChartTheme.office.tooltip;
    expect(office.background, ChartColor.rgb(0xFFFFFF));
    expect(office.border, ChartColor.rgb(0xD9D9D9));
    expect(
      office.text,
      ChartTextStyle(
        fontFamily: 'Aptos Narrow',
        size: 10,
        color: ChartColor.rgb(0x404040),
      ),
    );
    expect(office.padding, 6);
    // An app theme that names no tooltip gets the same look.
    expect(custom().tooltip, office);
  });

  test('tooltip style copies, compares and replaces in a theme', () {
    final ChartTooltipStyle office = ChartTheme.office.tooltip;
    final ChartTooltipStyle dark = office.copyWith(
      background: ChartColor.rgb(0x202020),
      padding: 8,
    );
    expect(dark.background, ChartColor.rgb(0x202020));
    expect(dark.border, office.border);
    expect(dark.text, office.text);
    expect(dark.padding, 8);
    expect(dark, isNot(office));
    expect(office.copyWith(), office);
    expect(office.copyWith().hashCode, office.hashCode);
    expect(office.copyWith(border: ChartColor.rgb(1)), isNot(office));
    expect(
      office.copyWith(text: office.text.copyWith(bold: true)),
      isNot(office),
    );
    expect(
      ChartTooltipStyle(
        background: ChartColor.rgb(0xFFFFFF),
        border: ChartColor.rgb(0xD9D9D9),
        text: office.text,
        padding: 6,
      ),
      office,
    );

    final ChartTheme theme = ChartTheme.office.copyWith(tooltip: dark);
    expect(theme.tooltip, dark);
    expect(theme, isNot(ChartTheme.office));
    expect(theme.copyWith(), theme);
    expect(theme.copyWith().hashCode, theme.hashCode);
    expect(ChartTheme.office.copyWith(tooltip: office), ChartTheme.office);
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

  test('a tooltip padding that is negative or not finite throws', () {
    final ChartTooltipStyle office = ChartTheme.office.tooltip;
    for (final double padding in <double>[
      -1,
      double.nan,
      double.infinity,
      double.negativeInfinity,
    ]) {
      expect(
        () => ChartTooltipStyle(
          background: office.background,
          border: office.border,
          text: office.text,
          padding: padding,
        ),
        throwsArgumentError,
        reason: '$padding',
      );
      expect(
        () => office.copyWith(padding: padding),
        throwsArgumentError,
        reason: '$padding',
      );
    }
    expect(office.copyWith(padding: 0).padding, 0);
  });

  test('line markers are on by default and part of theme equality', () {
    final ChartTheme office = ChartTheme.office;
    expect(office.lineMarkers, isTrue);
    expect(custom().lineMarkers, isTrue);
    final ChartTheme off = office.copyWith(lineMarkers: false);
    expect(off.lineMarkers, isFalse);
    expect(off, isNot(office));
    expect(off.hashCode, isNot(office.hashCode));
    expect(off.copyWith(), off);
    expect(off.copyWith(lineMarkers: true), office);
  });

  test('spacing is part of theme equality', () {
    final ChartTheme a = custom();
    expect(a.spacing, ChartSpacing());
    final ChartTheme b = a.copyWith(spacing: ChartSpacing(padding: 12));
    expect(b, isNot(a));
    expect(b.spacing.padding, 12);
    expect(a, a.copyWith(spacing: ChartSpacing()));
    expect(a.hashCode, a.copyWith(spacing: ChartSpacing()).hashCode);
    expect(b.hashCode, isNot(a.hashCode));
  });

  test('spacing defaults and copyWith', () {
    final ChartSpacing s = ChartSpacing();
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
    expect(s.legendLineSymbol, 16);
    expect(s.copyWith(legendLineSymbol: 20).legendLineSymbol, 20);
    expect(s.copyWith(legendLineSymbol: 20), isNot(s));
    expect(s.copyWith(legendLineSymbol: 20).hashCode, isNot(s.hashCode));
    expect(s.barOverlapPercent, 0);
    expect(s.copyWith(barOverlapPercent: 5).barOverlapPercent, 5);
    expect(s.copyWith(barOverlapPercent: 5), isNot(s));
    expect(s.copyWith(barOverlapPercent: 5).hashCode, isNot(s.hashCode));
    expect(s.copyWith(), s);
    expect(s.copyWith(tickLength: 4).tickLength, 4);
    expect(s.copyWith(tickLength: 4), isNot(s));
    expect(ChartTheme.office.spacing, s);
  });
  test('a negative or non-finite spacing throws ArgumentError', () {
    final ChartSpacing s = ChartSpacing();
    final List<ChartSpacing Function(double)> fields =
        <ChartSpacing Function(double)>[
          (double v) => s.copyWith(padding: v),
          (double v) => s.copyWith(titleGap: v),
          (double v) => s.copyWith(legendGap: v),
          (double v) => s.copyWith(legendSymbol: v),
          (double v) => s.copyWith(legendItemGap: v),
          (double v) => s.copyWith(labelGap: v),
          (double v) => s.copyWith(minTextGap: v),
          (double v) => s.copyWith(tickLength: v),
          (double v) => s.copyWith(gridLineWidth: v),
          (double v) => s.copyWith(axisLineWidth: v),
          (double v) => s.copyWith(legendLineSymbol: v),
        ];
    for (int f = 0; f < fields.length; f++) {
      for (final double bad in <double>[
        -20,
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        expect(() => fields[f](bad), throwsArgumentError, reason: '$f $bad');
      }
      expect(fields[f](0), isA<ChartSpacing>());
    }
    expect(() => ChartSpacing(padding: -20), throwsArgumentError);
    // The overlap may be negative (a gap between bars), but must be finite.
    expect(s.copyWith(overlapPercent: -150).overlapPercent, -150);
    for (final double bad in <double>[double.nan, double.infinity]) {
      expect(() => s.copyWith(overlapPercent: bad), throwsArgumentError);
      expect(() => s.copyWith(barOverlapPercent: bad), throwsArgumentError);
    }
    expect(s.copyWith(barOverlapPercent: -150).barOverlapPercent, -150);
  });

  group('J4 theme values', () {
    test('Office values', () {
      final ChartTheme office = ChartTheme.office;
      expect(office.areaOpacity, 1);
      expect(office.areaLine, isFalse);
      expect(office.sliceBorderWidth, 0.75);
      expect(office.centerText, isNull);
      expect(office.centerTextStyle, office.titleText);
      expect(office.sparklineWidth, 0.75);
    });

    test('copyWith round trip and equality', () {
      final ChartTextStyle style = text(ChartColor.rgb(0x112233));
      final ChartTheme changed = custom().copyWith(
        areaOpacity: 0.4,
        areaLine: true,
        sliceBorderWidth: 2,
        centerText: style,
        sparklineWidth: 1.5,
      );
      expect(changed.areaOpacity, 0.4);
      expect(changed.areaLine, isTrue);
      expect(changed.sliceBorderWidth, 2);
      expect(changed.centerText, style);
      expect(changed.centerTextStyle, style);
      expect(changed.sparklineWidth, 1.5);
      expect(changed, isNot(custom()));
      expect(changed.copyWith(), changed);
      expect(changed.copyWith().hashCode, changed.hashCode);
      expect(custom().copyWith(areaOpacity: 0.5), isNot(custom()));
      expect(custom().copyWith(areaLine: true), isNot(custom()));
      expect(custom().copyWith(sliceBorderWidth: 1), isNot(custom()));
      expect(custom().copyWith(sparklineWidth: 1), isNot(custom()));
    });

    test('out of range values throw', () {
      ChartTheme build({
        double areaOpacity = 1,
        double sliceBorderWidth = 0.75,
        double sparklineWidth = 0.75,
      }) {
        final ChartTextStyle t = text(ChartColor.rgb(0));
        return ChartTheme(
          palette: <ChartColor>[ChartColor.rgb(0)],
          axisLabels: t,
          titleText: t,
          legendText: t,
          dataLabels: t,
          gridLine: ChartColor.rgb(0),
          axisLine: ChartColor.rgb(0),
          background: ChartColor.rgb(0),
          areaOpacity: areaOpacity,
          sliceBorderWidth: sliceBorderWidth,
          sparklineWidth: sparklineWidth,
        );
      }

      expect(build(areaOpacity: 0.01).areaOpacity, 0.01);
      expect(build(sliceBorderWidth: 0).sliceBorderWidth, 0);
      for (final double bad in <double>[0, -0.1, 1.1, double.nan]) {
        expect(() => build(areaOpacity: bad), throwsArgumentError);
      }
      for (final double bad in <double>[-1, double.nan, double.infinity]) {
        expect(() => build(sliceBorderWidth: bad), throwsArgumentError);
        expect(() => build(sparklineWidth: bad), throwsArgumentError);
      }
    });
  });
}
