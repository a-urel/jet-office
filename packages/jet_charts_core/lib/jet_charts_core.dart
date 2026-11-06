/// The chart core of the jet_ packages: a chart model, a theme, axis scales,
/// layout and drawing primitives, in pure Dart.
///
/// It draws nothing itself. A backend (a Flutter painter, a PDF writer) draws
/// the primitives the layout produces, and `jet_office` writes the model as a
/// chart in an XLSX or DOCX file. The package depends on `jet_core` only.
///
/// This library exports nothing yet; the model, theme and primitives are
/// added by the milestone J1 tasks that follow.
library;
