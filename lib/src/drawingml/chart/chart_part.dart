/// The handle of a chart part (`xl/charts/chartN.xml`,
/// `word/charts/chartN.xml`) the XLSX and DOCX hosts hold as its
/// [PartContent].
///
/// Not ported from Quds; written for jet_office.
///
/// An opened part stays byte for byte until [DrawingChart.replace] gives it a
/// new [DrawingChartSpace]: [DrawingChart.encode] returns the bytes it was
/// opened with, so a chart the model cannot express still round-trips. Reading
/// is lazy (decision 0007: the part is untrusted): [DrawingChart.chart],
/// [DrawingChart.typed] and [DrawingChart.issues] read it on first use, once,
/// and never throw.
///
/// This layer imports `opc`, `xml`, `common`, `jet_charts_core` and `jet_core`
/// only, never `xlsx` or `docx` (decisions 0014 and 0015).
library;

import 'dart:typed_data';

import 'package:jet_charts_core/jet_charts_core.dart';

import '../../common/theme_colors.dart';
import '../../opc/package.dart';
import 'chart_reader.dart';
import 'chart_space.dart';
import 'chart_writer.dart';

/// A chart part: opened from bytes, or created and replaced from a
/// [DrawingChartSpace].
final class DrawingChart implements PartContent {
  /// A chart part opened from [bytes], held as given: the caller must not
  /// change them afterwards, as nothing is copied.
  ///
  /// Nothing is read until [chart], [typed] or [issues] is asked. [theme] and
  /// [themeColors] are passed to [readDrawingChartSpace].
  DrawingChart.opened(
    Uint8List bytes, {
    ChartTheme? theme,
    ThemeColors? themeColors,
    bool date1904 = false,
  }) : _bytes = bytes,
       _theme = theme,
       _themeColors = themeColors,
       _date1904 = date1904;

  /// A new chart part of [space], written with [theme] now.
  ///
  /// Throws an [ArgumentError] when the writer cannot express the chart
  /// ([writeDrawingChartSpace]).
  DrawingChart.created(
    DrawingChartSpace space,
    ChartTheme theme, {
    bool date1904 = false,
  }) : _theme = null,
       _themeColors = null,
       _date1904 = date1904 {
    replace(space, theme, date1904: date1904);
  }

  Uint8List? _bytes;
  final ChartTheme? _theme;
  final ThemeColors? _themeColors;
  bool _date1904;
  DrawingChartRead? _read;
  DrawingChartSpace? _space;
  List<DrawingChartIssue>? _writtenIssues;
  bool _changed = false;

  DrawingChartRead get _opened => _read ??= readDrawingChartSpace(
    _bytes!,
    theme: _theme,
    themeColors: _themeColors,
    date1904: _date1904,
  );

  /// What the part shows, or `null` when an opened part could not be read as
  /// a chart. After [replace], the replaced chart.
  Chart? get chart => _changed ? _space!.chart : _opened.chart;

  /// The part in typed form: `null` for an opened part the writer would not
  /// reproduce; after [replace], the given space.
  ///
  /// The given space is returned as it was given, which can differ from what
  /// reopening the encoded bytes gives: a UTC date reads back as a local one,
  /// a category axis minimum the writer drops is gone, characters XML 1.0
  /// forbids are scrubbed from the text, and a `NaN` in the axis scaling is
  /// not written. Reopen the bytes ([DrawingChart.opened]) to see what the
  /// part holds.
  DrawingChartSpace? get typed => _changed ? _space : _opened.typed;

  /// The data problems of the reader (opened part) or of the writer (after
  /// [replace] or [DrawingChart.created]).
  List<DrawingChartIssue> get issues =>
      _changed ? _writtenIssues! : _opened.issues;

  /// Whether [replace] was called (always for a created part).
  bool get changed => _changed;

  /// Replaces the part with [space], written with [theme] at once; later
  /// [encode] calls return the same bytes.
  ///
  /// [theme] is the one the part is written with; the theme given to
  /// [DrawingChart.opened], if any, is ignored here.
  ///
  /// [date1904] is the date system the part is written in (and declares); it
  /// is not inherited from [DrawingChart.opened].
  ///
  /// Throws an [ArgumentError] when the writer cannot express the chart, and
  /// then the part is as it was.
  void replace(
    DrawingChartSpace space,
    ChartTheme theme, {
    bool date1904 = false,
  }) {
    final DrawingChartWritten written = writeDrawingChartSpace(
      space,
      theme,
      date1904: date1904,
    );
    _date1904 = date1904;
    _bytes = written.bytes;
    _writtenIssues = written.issues;
    _space = space;
    _read = null;
    _changed = true;
  }

  @override
  List<Uint8List> encode() => <Uint8List>[_bytes!];
}
