/// Complex fields: [DocxField], and the pass that finds them in the inlines
/// of a paragraph as read.
///
/// Not ported from Quds; written for jet_office. It is a part of the inlines'
/// library because [DocxInline] is sealed.
///
/// A complex field is a sequence of a paragraph's runs: a `begin` mark, the
/// instruction, an optional `separate` mark, the cached result, and an `end`
/// mark. A field is only ever a view of those inlines: it holds them in order
/// and the writer writes them so, which is why typing a field changes nothing
/// in the part.
///
/// [groupFields] types a field only when it is plain (plan Ruling 2), and
/// leaves every other run where it was, as a run with its marks as typed
/// content: a broken field never loses or gains anything.
part of 'inlines.dart';

/// How deep fields nest in a field's result before the deeper ones stay runs.
///
/// Nesting in a paragraph is not nesting in the XML, so `maxDepth` does not
/// bound it, and everything that walks a field recurses. Word's own limit is
/// far below this.
const int maxFieldNesting = 32;

/// A complex field: an instruction and the result cached for it.
///
/// The model does not evaluate fields. [DocxParagraph.inlines] shows a field
/// as one inline, and [result] shows the inlines of its result, whose runs can
/// be edited as those of the paragraph. A field across paragraphs, and any
/// other that is not plain, stays runs ([DocxFieldMark] has how to tell).
final class DocxField extends DocxInline {
  DocxField._read(this._inlines, this._resultStart, int resultEnd)
    : _result = List<DocxInline>.unmodifiable(
        _inlines.sublist(_resultStart, resultEnd),
      ),
      super._() {
    for (final DocxInline inline in _inlines) {
      inline._field = this;
    }
  }

  /// Every inline of the field, from the `begin` run to the `end` run, as
  /// read. A field in the result is one of them.
  final List<DocxInline> _inlines;

  /// The index in [_inlines] of the first inline of the result, or of the
  /// `end` run for a field with no `separate`.
  final int _resultStart;

  final List<DocxInline> _result;

  /// The field's instruction, the text of its `w:instrText`s joined as read,
  /// such as ` PAGE `.
  String get instruction {
    final StringBuffer out = StringBuffer();
    for (final DocxInline inline in _inlines.take(_resultStart)) {
      if (inline is! DocxRun) continue;
      for (final DocxRunContent c in inline._content) {
        if (c is DocxFieldInstruction) out.write(c.text);
      }
    }
    return out.toString();
  }

  /// The first word of [instruction] in upper case, such as `PAGE`, or `null`
  /// for an instruction of no word.
  String? get name {
    final String trimmed = instruction.trim();
    if (trimmed.isEmpty) return null;
    return trimmed.split(RegExp(r'\s')).first.toUpperCase();
  }

  /// The inlines of the cached result, in order: empty for a field with no
  /// `separate`. A field nested in the result is one [DocxField] here. The
  /// list cannot be modified.
  List<DocxInline> get result => _result;

  /// The text of [result]; the instruction is never text.
  @override
  String get text {
    final StringBuffer out = StringBuffer();
    for (final DocxInline inline in _result) {
      out.write(inline.text);
    }
    return out.toString();
  }

  @override
  String toString() => 'DocxField($name)';
}

/// Calls [visit] with [inline], or for a field with every inline it holds, in
/// file order: runs and opaque inlines, never a field. That order is the one
/// the inlines were read in, whatever was typed as a field.
void visitInlines(DocxInline inline, void Function(DocxInline inline) visit) {
  if (inline is DocxField) {
    for (final DocxInline held in inline._inlines) {
      visitInlines(held, visit);
    }
  } else {
    visit(inline);
  }
}

/// Whether [inline] is held by a field, removed from a paragraph or not.
bool isInField(DocxInline inline) => inline._field != null;

/// [inlines], the inlines of a paragraph as read, with each plain field in
/// one [DocxField]; [inlines] itself when there is none.
///
/// A field is plain when its `begin`, its `separate` if any and its `end` are
/// runs of [inlines] holding that one mark and nothing else, and what lies
/// between `begin` and `separate` (or `end`) is runs holding only
/// `w:instrText`, and inlines that hold no run. Marks pair as brackets do. A
/// field in a result is a [DocxField] of that result, up to
/// [maxFieldNesting]. Left as runs are:
///
/// * a mark with no partner, as those of a field across paragraphs;
/// * a field in an instruction, and the field around it;
/// * a field with two `separate`s, or `w:instrText` in its result;
/// * every field open around a run that holds a mark and anything else, a
///   `w:fldChar` that is no mark, or an inline whose own marks do not pair:
///   from there on nothing says which mark belongs to which.
List<DocxInline> groupFields(List<DocxInline> inlines) {
  final _FieldPairs pairs = _FieldPairs();
  for (int i = 0; i < inlines.length; i++) {
    switch (inlines[i]) {
      case final DocxRun run:
        pairs.run(i, run);
      case final DocxOpaqueInline inline:
        pairs.opaque(inline);
      case DocxField():
        throw StateError('The inlines were grouped already.');
    }
  }
  if (pairs.closed.isEmpty) return inlines;
  return _grouped(inlines, pairs.closed, 0, inlines.length);
}

/// The inlines from [from] to [to], each field of [closed] (by the index of
/// its `begin`) in one [DocxField]. It recurses once per level of a result,
/// at most [maxFieldNesting] deep.
List<DocxInline> _grouped(
  List<DocxInline> inlines,
  Map<int, _ClosedField> closed,
  int from,
  int to,
) {
  final List<DocxInline> out = <DocxInline>[];
  for (int i = from; i < to; i++) {
    final _ClosedField? field = closed[i];
    if (field == null) {
      out.add(inlines[i]);
      continue;
    }
    final int? separate = field.separate;
    final int resultStart = separate == null ? field.end : separate + 1;
    final List<DocxInline> result = _grouped(
      inlines,
      closed,
      resultStart,
      field.end,
    );
    final int head = resultStart - i;
    out.add(
      DocxField._read(
        <DocxInline>[
          ...inlines.getRange(i, resultStart),
          ...result,
          inlines[field.end],
        ],
        head,
        head + result.length,
      ),
    );
    i = field.end;
  }
  return out;
}

/// Where the `separate` and the `end` of a plain field are.
typedef _ClosedField = ({int? separate, int end});

/// A field whose `begin` was met and whose `end` was not.
final class _OpenField {
  _OpenField(this.begin, {required this.inInstruction, required this.broken});

  final int begin;

  /// Whether an open field has this one in its instruction, however deep.
  final bool inInstruction;

  /// The index of its `separate`.
  int? separate;

  /// Whether it is known not to be plain. It stays open, so that its `end`
  /// does not close the field around it.
  bool broken;

  /// Whether what comes next is its instruction.
  bool get readsInstruction => separate == null;
}

/// Pairs the marks of one paragraph's inlines, given in order. An edit of its
/// state costs a constant, however many fields are open.
final class _FieldPairs {
  /// The plain fields found, by the index of the `begin`.
  final Map<int, _ClosedField> closed = <int, _ClosedField>{};

  final List<_OpenField> _open = <_OpenField>[];

  /// The open fields below this index of [_open] are broken.
  int _brokenBelow = 0;

  _OpenField? get _top => _open.isEmpty ? null : _open.last;

  void _breakOpen() {
    _brokenBelow = _open.length;
  }

  /// Takes the run at [index].
  void run(int index, DocxRun run) {
    final List<DocxRunContent> content = run._content;
    final bool alone = content.length == 1;
    for (final DocxRunContent c in content) {
      final _OpenField? top = _top;
      switch (c) {
        case DocxFieldMark(:final DocxFieldMarkType type):
          _mark(type, index, alone: alone);
        case DocxFieldInstruction():
          if (top != null && !top.readsInstruction) top.broken = true;
        case DocxOpaqueRunContent()
            when c.localName == 'fldChar' && c.namespaceUri == Ns.w:
          _breakOpen();
        default:
          if (top != null && top.readsInstruction) top.broken = true;
      }
    }
  }

  /// Takes an inline that is no run.
  void opaque(DocxOpaqueInline inline) {
    if (inline._breaksFields) _breakOpen();
    final _OpenField? top = _top;
    if (top != null && top.readsInstruction && inline._holdsRuns) {
      top.broken = true;
    }
  }

  /// Takes a mark of [type] in the run at [index], which holds nothing else
  /// when [alone].
  void _mark(DocxFieldMarkType type, int index, {required bool alone}) {
    if (!alone) _breakOpen();
    final _OpenField? top = _top;
    switch (type) {
      case DocxFieldMarkType.begin:
        final bool inInstruction =
            top != null && (top.inInstruction || top.readsInstruction);
        if (top != null && top.readsInstruction) top.broken = true;
        _open.add(
          _OpenField(
            index,
            inInstruction: inInstruction,
            broken: !alone || inInstruction || _open.length >= maxFieldNesting,
          ),
        );
      case DocxFieldMarkType.separate:
        if (top == null) return;
        if (top.separate != null) _breakOpen();
        top.separate ??= index;
      case DocxFieldMarkType.end:
        if (top == null) return;
        final bool broken = top.broken || _open.length <= _brokenBelow;
        _open.removeLast();
        if (_brokenBelow > _open.length) _brokenBelow = _open.length;
        if (!broken) {
          closed[top.begin] = (separate: top.separate, end: index);
        }
    }
  }
}
