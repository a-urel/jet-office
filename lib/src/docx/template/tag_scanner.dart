/// The template tag scanner: finds `{{...}}` tags in a string and parses a
/// tag's body into a [ParsedTag].
///
/// New in jet_office (decision 0024); quds_office_engine has no template
/// fill, so this is not ported from Quds. The scanner is pure: it works on a
/// string, never throws and runs in linear time. Spaces around a body and
/// after a sigil are U+0020 and U+00A0 only.
library;

/// What a well-formed tag asks for.
enum TagKind {
  /// `{{path}}` or `{{path:format}}`: a value.
  value,

  /// `{{#path}}`: the start of a section.
  section,

  /// `{{^path}}`: the start of an inverted section.
  invertedSection,

  /// `{{/path}}`: the end of a section.
  sectionEnd,

  /// `{{.}}` or `{{.:format}}`: the current item of a section.
  current,
}

/// A well-formed tag body.
final class ParsedTag {
  /// Creates a parsed tag.
  const ParsedTag(this.kind, this.path, this.format);

  /// What the tag asks for.
  final TagKind kind;

  /// The path's segments; empty for [TagKind.current].
  final List<String> path;

  /// The format, trimmed and never empty, or `null` when the tag has none.
  final String? format;
}

/// One finding of [scanTags]: a tag, or malformed text where one began.
final class TagMatch {
  /// Creates a finding of a scanned string over `[start, end)`.
  const TagMatch._(this._source, this.start, this.end, this.tag);

  final String _source;

  /// The start of the finding in the scanned string.
  final int start;

  /// The end (exclusive) of the finding in the scanned string.
  final int end;

  /// The parsed tag, or `null` when the text is malformed.
  final ParsedTag? tag;

  /// The scanned substring `[start, end)`.
  String get text => _source.substring(start, end);
}

final RegExp _path = RegExp(
  r'^[\p{L}\p{M}\p{N}_]+(?:\.[\p{L}\p{M}\p{N}_]+)*$',
  unicode: true,
);

bool _isSpace(int unit) => unit == 0x20 || unit == 0xA0;

String _trim(String s) {
  var a = 0;
  var b = s.length;
  while (a < b && _isSpace(s.codeUnitAt(a))) {
    a++;
  }
  while (b > a && _isSpace(s.codeUnitAt(b - 1))) {
    b--;
  }
  return s.substring(a, b);
}

/// Parses a tag [body], the text between the braces, untrimmed.
///
/// Returns `null` when the body is malformed: an empty or invalid path, a
/// `:` with an empty format, a format on a section tag, or a U+FFFC.
ParsedTag? parseTagBody(String body) {
  if (body.contains('￼')) return null;
  var rest = _trim(body);
  if (rest.isEmpty) return null;
  var kind = TagKind.value;
  switch (rest[0]) {
    case '#':
      kind = TagKind.section;
    case '^':
      kind = TagKind.invertedSection;
    case '/':
      kind = TagKind.sectionEnd;
  }
  final sigil = kind != TagKind.value;
  if (sigil) rest = _trim(rest.substring(1));
  String? format;
  final colon = rest.indexOf(':');
  if (colon >= 0) {
    if (sigil) return null;
    format = _trim(rest.substring(colon + 1));
    if (format.isEmpty) return null;
    rest = _trim(rest.substring(0, colon));
  }
  if (!sigil && rest == '.') {
    return ParsedTag(TagKind.current, const [], format);
  }
  if (!_path.hasMatch(rest)) return null;
  return ParsedTag(kind, rest.split('.'), format);
}

/// Finds every tag in [text], and every `{{` that does not start one.
///
/// From each `{{` the tag ends at the first `}}`. When another `{{` comes
/// first, the outer one is malformed up to that `{{` and scanning resumes
/// there; an unclosed `{{` is malformed up to the end. Never throws; runs in
/// linear time.
List<TagMatch> scanTags(String text) {
  final out = <TagMatch>[];
  var i = 0;
  var close = -2; // cached index of the next `}}`; -1 when there is none
  while (true) {
    final s = text.indexOf('{{', i);
    if (s < 0) break;
    if (close != -1 && close < s + 2) close = text.indexOf('}}', s + 2);
    final open = text.indexOf('{{', s + 1);
    if (open >= 0 && (close < 0 || open < close)) {
      out.add(TagMatch._(text, s, open, null));
      i = open;
    } else if (close < 0) {
      out.add(TagMatch._(text, s, text.length, null));
      break;
    } else {
      out.add(
        TagMatch._(
          text,
          s,
          close + 2,
          parseTagBody(text.substring(s + 2, close)),
        ),
      );
      i = close + 2;
    }
  }
  return out;
}
