/// The ids of the primitives layout produces.
///
/// The public statement of this scheme is the dartdoc of
/// `ChartLayout.primitives`, and `ChartElementId.parse`
/// (`lib/src/interaction/element_id.dart`) is its exact inverse; keep the
/// three in step. The scheme is stable: the
/// same chart, theme and size give the same ids, and a later version keeps
/// every id it has, so hit testing and golden tests can name a mark. An id is
/// a path of `/`-separated parts; indexes count from 0.
///
/// * [background], [title], [legend], [plot], [plotClip], [markerClip] (when
///   a line chart has markers), [placeholder]: one each.
/// * `legend/<s>/symbol` and `legend/<s>/text`: the legend entry of series
///   `<s>` ([legendSymbolId], [legendTextId]); a line series' entry also has
///   `legend/<s>/marker`, the marker on its line ([legendMarkerId]).
/// * `axis/<a>/line`, `axis/<a>/label/<i>` and `axis/<a>/title`, where `<a>` is
///   `value`, `category` or `secondary` (the secondary value axis)
///   ([axisLineId], [axisLabelId], [axisTitleId]).
/// * `grid/<a>/<i>`: gridline `<i>` of axis `<a>` ([gridId]).
/// * `series/<s>/bar/<c>`, `series/<s>/line/<run>`, `series/<s>/marker/<c>` and
///   `series/<s>/area`: the marks of series `<s>` ([seriesBarId],
///   [seriesLineId], [seriesMarkerId], [seriesAreaId]).
/// * `label/<s>/<c>`: the data label of series `<s>`, category `<c>`
///   ([dataLabelId]).
/// * `series/<s>/slice/<c>`: the slice of series `<s>` at category `<c>` in a
///   pie or donut ([seriesSliceId]); `label/<s>/<c>/leader`: the leader line
///   of that slice's data label ([dataLabelLeaderId]); `center`: a donut's
///   centre text ([centerTextId]). In a pie or donut a legend entry
///   `legend/<i>/...` is category `<i>`.
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

/// The clip that holds a line chart's markers: the plot grown by a marker's
/// reach, so a marker on the plot's edge is drawn whole.
const String markerClip = 'plot/markers';

/// A donut's centre text.
const String centerTextId = 'center';

/// What is drawn when there is nothing to draw.
const String placeholder = 'placeholder';

/// The prefix of every legend entry's id.
const String legendPrefix = 'legend/';

/// The prefix of every series mark's id.
const String seriesPrefix = 'series/';

/// The prefix of every data label's id.
const String dataLabelPrefix = 'label/';

/// The axis names used in ids.
const String valueAxis = 'value';

/// The axis names used in ids.
const String categoryAxis = 'category';

/// The axis names used in ids: the secondary value axis.
const String secondaryAxis = 'secondary';

/// The symbol of the legend entry of [series].
String legendSymbolId(int series) => 'legend/$series/symbol';

/// The marker on the line of the legend entry of [series], a line series.
String legendMarkerId(int series) => 'legend/$series/marker';

/// The text of the legend entry of [series].
String legendTextId(int series) => 'legend/$series/text';

/// The line of [axis] (`value`, `category` or `secondary`).
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

/// The slice of [series] at [category] in a pie or donut.
String seriesSliceId(int series, int category) =>
    'series/$series/slice/$category';

/// The leader line of the data label of [series] at [category].
String dataLabelLeaderId(int series, int category) =>
    'label/$series/$category/leader';
