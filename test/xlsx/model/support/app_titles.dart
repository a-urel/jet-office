/// A `docProps/app.xml` as Excel writes it, with [pairs] as `HeadingPairs`
/// (none when `null`) and [titles] as `TitlesOfParts`.
String appXml(List<(String, int)>? pairs, List<String> titles) {
  String esc(String t) => t.replaceAll('&', '&amp;').replaceAll('<', '&lt;');
  final StringBuffer b = StringBuffer(
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/'
    '2006/extended-properties" xmlns:vt="http://schemas.openxmlformats.org/'
    'officeDocument/2006/docPropsVTypes">'
    '<Application>Microsoft Excel</Application>',
  );
  if (pairs != null) {
    b.write(
      '<HeadingPairs><vt:vector size="${pairs.length * 2}" '
      'baseType="variant">',
    );
    for (final (String name, int count) in pairs) {
      b.write(
        '<vt:variant><vt:lpstr>${esc(name)}</vt:lpstr></vt:variant>'
        '<vt:variant><vt:i4>$count</vt:i4></vt:variant>',
      );
    }
    b.write('</vt:vector></HeadingPairs>');
  }
  b.write(
    '<TitlesOfParts><vt:vector size="${titles.length}" baseType="lpstr">',
  );
  for (final String t in titles) {
    b.write('<vt:lpstr>${esc(t)}</vt:lpstr>');
  }
  b.write('</vt:vector></TitlesOfParts></Properties>');
  return b.toString();
}

/// The titles of the `TitlesOfParts` of [app], unescaped.
List<String> appTitles(String app) => <String>[
  for (final RegExpMatch m in RegExp(
    '<vt:lpstr>([^<]*)</vt:lpstr>',
  ).allMatches(app.substring(app.indexOf('<TitlesOfParts'))))
    m[1]!
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&apos;', "'")
        .replaceAll('&quot;', '"')
        .replaceAll('&amp;', '&'),
];

/// The worksheet count and the titles' vector size of [app].
(String?, String?) appCounts(String app) => (
  RegExp('<vt:i4>([0-9]+)</vt:i4>').firstMatch(app)?[1],
  RegExp(r'<TitlesOfParts><vt:vector size="([0-9]+)"').firstMatch(app)?[1],
);
