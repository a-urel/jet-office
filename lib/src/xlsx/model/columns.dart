/// The typed `<cols>` of a worksheet part: its `<col>` runs, edited one
/// column at a time.
///
/// Not ported from Quds; written for jet_office.
///
/// The first `<cols>` of a part is read into [ColsGroup], an ordered list of
/// [ColRun]s. A run keeps every attribute of its `<col>` as written (`width`,
/// `style`, `hidden`, `customWidth`, `outlineLevel`, `collapsed`, and what
/// the model does not read: `bestFit`, `phonetic`, ...), so a sheet opened
/// and saved without a column edit writes its `<col>` elements as they were.
///
/// [setColumnInRuns] changes one column: the run holding it is split into up
/// to three, and the outer runs keep every attribute, so only the column
/// asked for changes. [replaceAttributes] is the one way an attribute list
/// changes: a changed attribute is replaced where it stood, a new one is
/// added after the others, and an absent value removes it.
///
/// Only a `<cols>` that is plain is typed: `<col>` elements of the
/// SpreadsheetML namespace, none with children or namespace declarations of
/// its own, with whole `min` and `max` inside the grid, sorted and not
/// overlapping, at least one of them. Any other `<cols>` stays an
/// `OpaqueXml` and is written as it was.
library;

import '../../opc/ooxml.dart';
import '../../opc/opaque_xml.dart';
import '../../xml/xml_pull_reader.dart';
import '../../xml/xml_writer.dart';
import '../limits.dart';

/// [old] with each entry of [changed] applied: an attribute without a
/// namespace named in [changed] is replaced where it stood (the later
/// duplicates dropped), a new one is added after the others in the order of
/// [changed], and a `null` value removes it. Other attributes are kept.
List<KeptAttribute> replaceAttributes(
  List<KeptAttribute> old,
  Map<String, String?> changed,
) {
  final List<KeptAttribute> next = <KeptAttribute>[];
  final Set<String> written = <String>{};
  for (final KeptAttribute a in old) {
    final String name = a.qualifiedName;
    if (a.namespaceUri.isNotEmpty || !changed.containsKey(name)) {
      next.add(a);
      continue;
    }
    final String? value = changed[name];
    if (value != null && written.add(name)) {
      next.add((qualifiedName: name, namespaceUri: '', value: value));
    }
  }
  changed.forEach((String name, String? value) {
    if (value != null && written.add(name)) {
      next.add((qualifiedName: name, namespaceUri: '', value: value));
    }
  });
  return next;
}

/// Whether [a] and [b] hold the same attributes in the same order.
bool sameAttributes(List<KeptAttribute> a, List<KeptAttribute> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// One `<col>`: the columns [min] to [max] (1-based, inclusive) and its
/// other [attributes], as written.
final class ColRun {
  /// A run of the columns [min] to [max] named [qualifiedName] in the file.
  const ColRun(this.min, this.max, this.qualifiedName, this.attributes);

  /// The first column, 1-based.
  final int min;

  /// The last column, 1-based.
  final int max;

  /// The element's name with its prefix, as written.
  final String qualifiedName;

  /// The attributes but `min` and `max`, in source order.
  final List<KeptAttribute> attributes;

  /// The value of the first attribute without a namespace named [name], or
  /// `null`.
  String? attribute(String name) {
    for (final KeptAttribute a in attributes) {
      if (a.namespaceUri.isEmpty && a.qualifiedName == name) return a.value;
    }
    return null;
  }

  /// This run over the columns [first] to [last].
  ColRun over(int first, int last) =>
      ColRun(first, last, qualifiedName, attributes);

  /// The outline level of the run: its `outlineLevel` when that is a level
  /// from 0 to 7, else 0.
  int get outlineLevel => parseOutlineLevel(attribute('outlineLevel')) ?? 0;

  /// Whether [other] writes the same `<col>` apart from its columns.
  bool sameAs(ColRun other) =>
      qualifiedName == other.qualifiedName &&
      sameAttributes(attributes, other.attributes);
}

/// Whether [a] and [b] write the same `<col>` elements.
bool sameRuns(List<ColRun> a, List<ColRun> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i].min != b[i].min || a[i].max != b[i].max || !a[i].sameAs(b[i])) {
      return false;
    }
  }
  return true;
}

/// [value] as an outline level from 0 to 7, or `null`.
int? parseOutlineLevel(String? value) {
  if (value == null || value.isEmpty || value.length > 3) return null;
  if (!_signedDigits.hasMatch(value)) return null;
  final int? level = int.tryParse(value);
  return level != null && level >= 0 && level <= XlsxLimits.maxOutlineLevel
      ? level
      : null;
}

/// [value] as a cell format index (whole, at most nine digits), or `null`
/// when it is absent or not one.
int? parseStyleIndex(String? value) {
  if (value == null ||
      value.isEmpty ||
      value.length > 9 ||
      !_signedDigits.hasMatch(value)) {
    return null;
  }
  return int.tryParse(value);
}

final RegExp _signedDigits = RegExp(r'^[+-]?[0-9]+$');

final RegExp _digits = RegExp(r'^[0-9]+$');

/// The typed first `<cols>`: its name, declarations and attributes as
/// written, and its [runs].
final class ColsGroup {
  /// A `<cols>` named [qualifiedName] holding [runs].
  ColsGroup(this.qualifiedName, this.namespaces, this.attributes, this.runs);

  /// The element's name with its prefix.
  final String qualifiedName;

  /// The namespace declarations of the start tag.
  final Map<String, String> namespaces;

  /// The attributes of `<cols>` itself (the schema has none).
  final List<KeptAttribute> attributes;

  /// The runs, sorted by column and not overlapping.
  final List<ColRun> runs;

  /// This group holding [next].
  ColsGroup withRuns(List<ColRun> next) =>
      ColsGroup(qualifiedName, namespaces, attributes, next);

  /// The run holding [column] (1-based), or `null`.
  ColRun? runAt(int column) {
    int low = 0;
    int high = runs.length - 1;
    while (low <= high) {
      final int mid = (low + high) >> 1;
      final ColRun run = runs[mid];
      if (column < run.min) {
        high = mid - 1;
      } else if (column > run.max) {
        low = mid + 1;
      } else {
        return run;
      }
    }
    return null;
  }

  /// The deepest outline level of the runs, 0 when none.
  int get deepestOutline {
    int deepest = 0;
    for (final ColRun run in runs) {
      if (run.outlineLevel > deepest) deepest = run.outlineLevel;
    }
    return deepest;
  }

  /// Writes the element. [above] holds the bindings in scope at the
  /// worksheet's root.
  void writeTo(XmlWriter w, Map<String, String> above) {
    w.start(qualifiedName);
    writeNamespaceDeclarations(w, namespaces);
    final Map<String, String> inner = mergeNamespaces(above, namespaces);
    writeKeptAttributes(w, attributes, declaredAbove: inner);
    for (final ColRun run in runs) {
      w
        ..start(run.qualifiedName)
        ..attribute('min', '${run.min}')
        ..attribute('max', '${run.max}');
      writeKeptAttributes(w, run.attributes, declaredAbove: inner);
      w.end();
    }
    w.end();
  }
}

/// [runs] with column [column] (1-based) given [edit]'s attributes, or
/// taken out of its run when [edit] returns `null`.
///
/// [edit] gets the attributes of the run holding [column], or `null` when
/// none does. The run holding the column is split into the columns before
/// it, the column itself and the columns after it; the outer runs keep
/// every attribute. A column no run holds becomes a run named
/// [qualifiedName]. The column joins a neighbouring run when it ends up
/// writing the same `<col>`. Throws nothing; [runs] is not changed.
List<ColRun> setColumnInRuns(
  List<ColRun> runs,
  int column,
  String qualifiedName,
  List<KeptAttribute>? Function(List<KeptAttribute>? old) edit,
) {
  int at = 0;
  while (at < runs.length && runs[at].max < column) {
    at++;
  }
  final ColRun? holder = at < runs.length && runs[at].min <= column
      ? runs[at]
      : null;
  final List<KeptAttribute>? attributes = edit(holder?.attributes);
  final List<ColRun> pieces = <ColRun>[];
  if (holder != null) {
    if (holder.min < column) pieces.add(holder.over(holder.min, column - 1));
  }
  final int centre = pieces.length;
  if (attributes != null) {
    pieces.add(
      ColRun(
        column,
        column,
        holder?.qualifiedName ?? qualifiedName,
        attributes,
      ),
    );
  }
  if (holder != null && column < holder.max) {
    pieces.add(holder.over(column + 1, holder.max));
  }
  final List<ColRun> result = <ColRun>[
    ...runs.take(at),
    ...pieces,
    ...runs.skip(holder == null ? at : at + 1),
  ];
  if (attributes == null) return result;
  return _joined(result, at + centre);
}

/// [runs] with the run at [index] joined to its neighbours that write the
/// same `<col>` and touch it.
List<ColRun> _joined(List<ColRun> runs, int index) {
  int first = index;
  int last = index;
  final ColRun mid = runs[index];
  if (index > 0 &&
      runs[index - 1].max + 1 == mid.min &&
      runs[index - 1].sameAs(mid)) {
    first = index - 1;
  }
  if (index + 1 < runs.length &&
      mid.max + 1 == runs[index + 1].min &&
      runs[index + 1].sameAs(mid)) {
    last = index + 1;
  }
  if (first == last) return runs;
  return <ColRun>[
    ...runs.take(first),
    mid.over(runs[first].min, runs[last].max),
    ...runs.skip(last + 1),
  ];
}

/// What reading a `<cols>` gave: the element as written and, when it is
/// plain, the typed group.
typedef CapturedCols = ({OpaqueXml whole, ColsGroup? typed});

/// Captures the `<cols>` the current event of [r] starts and consumes it,
/// typing it when it is plain (see the library comment).
CapturedCols captureCols(XmlPullReader r) {
  final String qualifiedName = r.qualifiedName;
  final Map<String, String> namespaces = Map<String, String>.of(
    r.declaredNamespaces,
  );
  final List<KeptAttribute> attributes = keepAttributes(r);
  final int depth = r.depth;
  final List<ColRun> runs = <ColRun>[];
  bool plain = true;
  int previousMax = 0;
  final OpaqueXml whole = OpaqueXml.capture(
    r,
    onEvent: (XmlPullReader e) {
      if (e.eventType != XmlEventType.startElement || e.depth == depth) {
        return;
      }
      if (e.depth > depth + 1) {
        plain = false;
        return;
      }
      if (!plain) return;
      if (e.namespaceUri != Ns.main ||
          e.localName != 'col' ||
          e.declaredNamespaces.isNotEmpty) {
        plain = false;
        return;
      }
      final List<KeptAttribute> all = keepAttributes(e);
      int? min;
      int? max;
      final List<KeptAttribute> rest = <KeptAttribute>[];
      for (final KeptAttribute a in all) {
        if (a.namespaceUri.isEmpty && a.qualifiedName == 'min') {
          min ??= _column(a.value);
        } else if (a.namespaceUri.isEmpty && a.qualifiedName == 'max') {
          max ??= _column(a.value);
        } else {
          rest.add(a);
        }
      }
      if (min == null || max == null || max < min || min <= previousMax) {
        plain = false;
        return;
      }
      previousMax = max;
      runs.add(ColRun(min, max, e.qualifiedName, rest));
    },
  );
  if (!plain || runs.isEmpty) return (whole: whole, typed: null);
  return (
    whole: whole,
    typed: ColsGroup(qualifiedName, namespaces, attributes, runs),
  );
}

/// [value] as a column number from 1 to the last column, or `null`.
int? _column(String value) {
  if (value.isEmpty || value.length > 5 || !_digits.hasMatch(value)) {
    return null;
  }
  final int column = int.parse(value);
  return column >= 1 && column <= XlsxLimits.maxColumns ? column : null;
}

/// The attributes a row or column inserted next to [attributes] takes, as
/// Excel's "Format same as above" (or "as left") gives it: all but
/// `hidden` and `collapsed`.
List<KeptAttribute> insertedFormat(List<KeptAttribute> attributes) =>
    <KeptAttribute>[
      for (final KeptAttribute a in attributes)
        if (a.namespaceUri.isNotEmpty ||
            (a.qualifiedName != 'hidden' && a.qualifiedName != 'collapsed'))
          a,
    ];

/// [runs] (1-based, ascending) after [count] columns are inserted before
/// column [index] (1-based), or deleted from it on when [count] is
/// negative.
///
/// Runs after the edit shift; a run the edit cuts splits around an insert
/// or shrinks for a delete, and a run wholly deleted goes. The inserted
/// columns take the format of the column to their left ([insertedFormat]):
/// the run holding it grows when that leaves its attributes as they are,
/// else a run of its own holds them. Runs pushed past the last column go
/// or are cut there. Runs the edit misses are kept as they are.
List<ColRun> shiftColumnRuns(List<ColRun> runs, int index, int count) {
  const int limit = XlsxLimits.maxColumns;
  int atMost(int v) => v > limit ? limit : v;
  final List<ColRun> out = <ColRun>[];
  if (count < 0) {
    final int end = index - count - 1;
    for (final ColRun run in runs) {
      if (run.max < index) {
        out.add(run);
      } else if (run.min > end) {
        out.add(run.over(run.min + count, run.max + count));
      } else {
        final int first = run.min < index ? run.min : index;
        final int last = run.max > end ? run.max + count : index - 1;
        if (last >= first) out.add(run.over(first, last));
      }
    }
    return out;
  }
  final int lastNew = atMost(index + count - 1);
  for (final ColRun run in runs) {
    final bool left = run.min <= index - 1 && index - 1 <= run.max;
    final List<KeptAttribute> inherited = left
        ? insertedFormat(run.attributes)
        : const <KeptAttribute>[];
    final bool grows = left && sameAttributes(inherited, run.attributes);
    if (run.max < index) {
      if (grows) {
        out.add(run.over(run.min, lastNew));
      } else {
        out.add(run);
        if (inherited.isNotEmpty) {
          out.add(ColRun(index, lastNew, run.qualifiedName, inherited));
        }
      }
    } else if (run.min >= index) {
      if (run.min + count > limit) continue;
      out.add(run.over(run.min + count, atMost(run.max + count)));
    } else if (grows) {
      out.add(run.over(run.min, atMost(run.max + count)));
    } else {
      out.add(run.over(run.min, index - 1));
      if (inherited.isNotEmpty) {
        out.add(ColRun(index, lastNew, run.qualifiedName, inherited));
      }
      if (index + count <= limit) {
        out.add(run.over(index + count, atMost(run.max + count)));
      }
    }
  }
  return out;
}
