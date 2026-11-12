/// The gallery app of the owner's side-by-side check against Excel for Mac:
/// every chart of `gallery.dart` drawn by `JetChart` at Excel's default size,
/// with the overlaps `findOverlaps` finds (none, or the layout is wrong) and
/// the labels the layout hid, and a "Monépro look" page (`monepro.dart`).
library;

import 'package:jet_charts_core/jet_charts_core.dart';
import 'package:jet_charts_flutter/jet_charts_flutter.dart';
import 'package:jet_core/jet_core.dart';
import 'package:material_ui/material_ui.dart';

import 'gallery.dart';
import 'monepro.dart';

void main() {
  runApp(const GalleryApp());
}

/// The font family Excel's default charts use.
const String excelFontFamily = 'Aptos Narrow';

/// Whether [family] is installed: true when a sample measures to another
/// width in [family] than in a family that cannot exist (Flutter draws both
/// in its fallback font when [family] is missing).
bool fontFound(FlutterTextMeasurer measurer, String family) {
  const String sample = 'Sales by quarter 0123456789';
  final ChartColor black = ChartColor.rgb(0x000000);
  final double found = measurer
      .measure(
        sample,
        ChartTextStyle(fontFamily: family, size: 14, color: black),
      )
      .width;
  final double missing = measurer
      .measure(
        sample,
        ChartTextStyle(
          fontFamily: 'No Such Font jet_charts 7f3a',
          size: 14,
          color: black,
        ),
      )
      .width;
  return found != missing;
}

/// The app: a scrolling list of the gallery with a switch for Turkish texts
/// and `FormatLocale.trTR`.
final class GalleryApp extends StatelessWidget {
  /// Creates the app.
  const GalleryApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'jet_charts gallery',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorSchemeSeed: const Color(0xFF156082)),
    home: const GalleryPage(),
  );
}

/// The gallery's one page.
final class GalleryPage extends StatefulWidget {
  /// Creates the page.
  const GalleryPage({super.key});

  @override
  State<GalleryPage> createState() => _GalleryPageState();
}

final class _GalleryPageState extends State<GalleryPage> {
  final List<GalleryEntry> _entries = galleryEntries();
  final FlutterTextMeasurer _measurer = FlutterTextMeasurer();
  late final bool _fontFound = fontFound(_measurer, excelFontFamily);
  bool _turkish = false;

  @override
  void dispose() {
    _measurer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final FormatLocale locale = _turkish
        ? FormatLocale.trTR
        : FormatLocale.enUS;
    return Scaffold(
      appBar: AppBar(
        title: const Text('jet_charts gallery'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (BuildContext context) =>
                    MoneproPage(measurer: _measurer),
              ),
            ),
            child: const Text('Monépro look'),
          ),
          const SizedBox(width: 16),
          const Text('Türkçe (tr-TR)'),
          Switch(
            value: _turkish,
            onChanged: (bool value) => setState(() => _turkish = value),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text(
            _fontFound
                ? 'Font $excelFontFamily found: fonts can be compared.'
                : 'Font $excelFontFamily not found: Flutter draws a fallback '
                      'font, so font differences do not count.',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: _fontFound ? null : const Color(0xFFB00020),
            ),
          ),
          const SizedBox(height: 16),
          for (final GalleryEntry entry in _entries)
            _EntryView(
              caption: entry.name,
              chart: entry.chart,
              theme: entry.theme,
              size: entry.size,
              locale: locale,
              strings: _turkish ? JetChartStrings.tr : JetChartStrings.en,
              measurer: _measurer,
            ),
        ],
      ),
    );
  }
}

final class _EntryView extends StatelessWidget {
  const _EntryView({
    required this.caption,
    required this.chart,
    required this.theme,
    required this.size,
    required this.locale,
    required this.strings,
    required this.measurer,
  });

  final String caption;
  final Chart chart;
  final ChartTheme theme;
  final ChartSize size;
  final FormatLocale locale;
  final JetChartStrings strings;
  final FlutterTextMeasurer measurer;

  @override
  Widget build(BuildContext context) {
    final ChartLayout layout = layoutChart(
      chart,
      theme: theme,
      size: size,
      measurer: measurer,
      locale: locale,
    );
    // The count comes from a scale-1 layout of its own, not the painted one.
    final int overlaps = findOverlaps(layout.primitives, layout.size).length;
    final String hidden = layout.hidden.isEmpty
        ? 'none'
        : layout.hidden.map((ChartHiddenLabel h) => h.text).join(', ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(caption, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          SizedBox(
            width: size.width,
            height: size.height,
            child: JetChart(
              chart: chart,
              theme: theme,
              locale: locale,
              strings: strings,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'overlaps: $overlaps; hidden labels: $hidden',
            style: TextStyle(
              color: overlaps == 0 ? null : const Color(0xFFB00020),
            ),
          ),
        ],
      ),
    );
  }
}

/// The "Monépro look" page: the charts of [moneproCharts] in
/// [moneproLightTheme] and [moneproDarkTheme], side by side, with a line that
/// says whether the font [moneproFontFamily] was found. Excel has no such
/// theme: this page is compared with nothing, only looked at.
final class MoneproPage extends StatelessWidget {
  /// Creates the page, measuring with [measurer].
  const MoneproPage({required this.measurer, super.key});

  /// The measurer of the overlap counts and the font check.
  final FlutterTextMeasurer measurer;

  @override
  Widget build(BuildContext context) {
    final bool found = fontFound(measurer, moneproFontFamily);
    return Scaffold(
      appBar: AppBar(title: const Text('Monépro look')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text(
            found
                ? 'Font $moneproFontFamily found.'
                : 'Font $moneproFontFamily not found: Flutter draws a '
                      'fallback font.',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          for (final GalleryEntry entry in moneproCharts())
            Wrap(
              spacing: 24,
              children: <Widget>[
                for (final (String look, ChartTheme theme)
                    in <(String, ChartTheme)>[
                      ('light', moneproLightTheme),
                      ('dark', moneproDarkTheme),
                    ])
                  ColoredBox(
                    color: Color(0xFF000000 | theme.background.rgb),
                    child: DefaultTextStyle.merge(
                      style: TextStyle(
                        color: Color(0xFF000000 | theme.axisLabels.color.rgb),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: _EntryView(
                          caption: '${entry.name} ($look)',
                          chart: entry.chart,
                          theme: moneproTheme(theme, entry),
                          size: entry.size,
                          locale: FormatLocale.trTR,
                          strings: JetChartStrings.tr,
                          measurer: measurer,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
