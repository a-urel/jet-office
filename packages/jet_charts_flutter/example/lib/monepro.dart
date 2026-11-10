/// The "Monépro look" page's charts and themes: four charts of the gallery in
/// an app theme of `ChartTheme.fromColors`, light and dark, to look at on
/// screen only (Excel has no such theme, so the workbook does not hold them).
///
/// Pure Dart, no Flutter.
library;

import 'package:jet_charts_core/jet_charts_core.dart';

import 'gallery.dart';

/// The font family of the Monépro themes. The app bundles no font, so it is
/// drawn only when installed; the page says whether it was found.
const String moneproFontFamily = 'DM Sans';

/// The series colours of the light theme, of this app's choosing.
final List<ChartColor> _lightPalette = <ChartColor>[
  ChartColor.rgb(0x2563EB),
  ChartColor.rgb(0x10B981),
  ChartColor.rgb(0xF59E0B),
  ChartColor.rgb(0xEF4444),
  ChartColor.rgb(0x8B5CF6),
];

/// The series colours of the dark theme: the light ones, brighter.
final List<ChartColor> _darkPalette = <ChartColor>[
  ChartColor.rgb(0x60A5FA),
  ChartColor.rgb(0x34D399),
  ChartColor.rgb(0xFBBF24),
  ChartColor.rgb(0xF87171),
  ChartColor.rgb(0xA78BFA),
];

/// The light Monépro theme: dark grey text on white, [moneproFontFamily].
final ChartTheme moneproLightTheme = ChartTheme.fromColors(
  palette: _lightPalette,
  fontFamily: moneproFontFamily,
  text: ChartColor.rgb(0x1F2937),
  background: ChartColor.rgb(0xFFFFFF),
);

/// The dark Monépro theme: light grey text on near black,
/// [moneproFontFamily].
final ChartTheme moneproDarkTheme = ChartTheme.fromColors(
  palette: _darkPalette,
  fontFamily: moneproFontFamily,
  text: ChartColor.rgb(0xE5E7EB),
  background: ChartColor.rgb(0x0B0F19),
);

/// The names of the page's charts, in its order.
const List<String> _names = <String>[
  'donut_center',
  'sparkline_area',
  'line_smooth',
  'combo_column_line',
];

/// The page's charts: `donut_center`, `sparkline_area`, `line_smooth` and
/// `combo_column_line` of [galleryEntries], each at its gallery size.
List<GalleryEntry> moneproCharts() {
  final Map<String, GalleryEntry> byName = <String, GalleryEntry>{
    for (final GalleryEntry entry in galleryEntries()) entry.name: entry,
  };
  return <GalleryEntry>[for (final String name in _names) byName[name]!];
}

/// The theme [entry] is drawn in on the page: [theme] with the area opacity
/// and line of the entry's own theme, so a translucent area stays one.
ChartTheme moneproTheme(ChartTheme theme, GalleryEntry entry) => theme.copyWith(
  areaOpacity: entry.theme.areaOpacity,
  areaLine: entry.theme.areaLine,
);
