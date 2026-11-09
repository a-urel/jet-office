/// The gallery app of the owner's side-by-side check against Excel for Mac:
/// every chart of `gallery.dart` drawn by `JetChart` at Excel's default size,
/// with the overlaps `findOverlaps` finds (none, or the layout is wrong) and
/// the labels the layout hid.
library;

import 'package:flutter/material.dart';
import 'package:jet_charts_core/jet_charts_core.dart';
import 'package:jet_charts_flutter/jet_charts_flutter.dart';
import 'package:jet_core/jet_core.dart';

import 'gallery.dart';

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
              entry: entry,
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
    required this.entry,
    required this.locale,
    required this.strings,
    required this.measurer,
  });

  final GalleryEntry entry;
  final FormatLocale locale;
  final JetChartStrings strings;
  final FlutterTextMeasurer measurer;

  @override
  Widget build(BuildContext context) {
    final ChartLayout layout = layoutChart(
      entry.chart,
      theme: ChartTheme.office,
      size: gallerySize,
      measurer: measurer,
      locale: locale,
    );
    final int overlaps = findOverlaps(layout.primitives, layout.size).length;
    final String hidden = layout.hidden.isEmpty
        ? 'none'
        : layout.hidden.map((ChartHiddenLabel h) => h.text).join(', ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(entry.name, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          SizedBox(
            width: gallerySize.width,
            height: gallerySize.height,
            child: JetChart(
              chart: entry.chart,
              theme: ChartTheme.office,
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
