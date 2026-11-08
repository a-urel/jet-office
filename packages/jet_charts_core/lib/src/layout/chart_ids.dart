/// The ids of the primitives layout produces.
///
/// The public statement of this scheme is the dartdoc of
/// `ChartLayout.primitives`; keep the two in step. The scheme is stable: the
/// same chart, theme and size give the same ids, and a later version keeps
/// every id it has, so hit testing and golden tests can name a mark. An id is
/// a path of `/`-separated parts; indexes count from 0.
///
/// * [background], [title], [legend], [plot], [plotClip], [placeholder]:
///   one each.
/// * `legend/<s>/symbol` and `legend/<s>/text`: the legend entry of series
///   `<s>` ([legendSymbolId], [legendTextId]).
/// * `axis/<a>/line`, `axis/<a>/label/<i>` and `axis/<a>/title`, where `<a>` is
///   `value` or `category` ([axisLineId], [axisLabelId], [axisTitleId]).
/// * `grid/<a>/<i>`: gridline `<i>` of axis `<a>` ([gridId]).
/// * `series/<s>/bar/<c>`, `series/<s>/line/<run>`, `series/<s>/marker/<c>` and
///   `series/<s>/area`: the marks of series `<s>` ([seriesBarId],
///   [seriesLineId], [seriesMarkerId], [seriesAreaId]).
/// * `label/<s>/<c>`: the data label of series `<s>`, category `<c>`
///   ([dataLabelId]).
library;

/// The chart's background rectangle.
const String background = 'background';

/// The chart title.
const String title = 'title';

/// The legend's rectangle.
const String legend = 'legend';

/// The plot area's rectangle.
const String plot = 'plot';

/// The clip that holds the series marks.
const String plotClip = 'plot/clip';

/// What is drawn when there is nothing to draw.
const String placeholder = 'placeholder';

/// The prefix of every legend entry's id.
const String legendPrefix = 'legend/';

/// The axis names used in ids.
const String valueAxis = 'value';

/// The axis names used in ids.
const String categoryAxis = 'category';

/// The symbol of the legend entry of [series].
String legendSymbolId(int series) => 'legend/$series/symbol';

/// The text of the legend entry of [series].
String legendTextId(int series) => 'legend/$series/text';

/// The line of [axis] (`value` or `category`).
String axisLineId(String axis) => 'axis/$axis/line';

/// Label [index] of [axis].
String axisLabelId(String axis, int index) => 'axis/$axis/label/$index';

/// The title of [axis].
String axisTitleId(String axis) => 'axis/$axis/title';

/// Gridline [index] of [axis].
String gridId(String axis, int index) => 'grid/$axis/$index';

/// The bar of [series] at [category].
String seriesBarId(int series, int category) => 'series/$series/bar/$category';

/// Run [run] of the line of [series]; a gap in the data starts a new run.
String seriesLineId(int series, int run) => 'series/$series/line/$run';

/// The marker of [series] at [category].
String seriesMarkerId(int series, int category) =>
    'series/$series/marker/$category';

/// The area of [series].
String seriesAreaId(int series) => 'series/$series/area';

/// The data label of [series] at [category].
String dataLabelId(int series, int category) => 'label/$series/$category';
