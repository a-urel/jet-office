/// Complex fields: [DocxField], and the pass that finds them in the inlines
/// of a paragraph as read.
///
/// Not ported from Quds; written for jet_office. It is a part of the inlines'
/// library because [DocxInline] is sealed.
///
/// A complex field is a sequence of a paragraph's runs: a `begin` mark, the
/// instruction, an optional `separate` mark, the cached result, and an `end`
/// mark. A field is only ever those inlines: it holds them in order and the
/// writer writes them so, which is why typing a field read changes nothing in
/// the part. A field built by the API holds new runs, and editing one (its
/// instruction, its result, its properties) changes those runs.
///
/// [groupFields] types a field only when it is plain (plan Ruling 2), and
/// leaves every other run where it was, as a run with its marks as typed
/// content: a broken field never loses or gains anything.
part of 'inlines.dart';

/// How deep fields nest in a field's result before the deeper ones stay runs.
///
/// Nesting in a paragraph is not nesting in the XML, so `maxDepth` does not
/// bound it, and everything that walks a field recurses.
const int maxFieldNesting = 32;

/// What a field holds at one moment, for [_FieldEdit]: its inlines, where its
/// result starts, and the content of the runs an edit changes.
typedef _FieldState = ({
  List<DocxInline> inlines,
  int resultStart,
  Map<DocxRun, DocxRunText> texts,
});

/// A complex field: an instruction and the result cached for it.
///
/// The model does not evaluate fields. [DocxParagraph.inlines] shows a field
/// as one inline, and [result] shows the inlines of its result, whose runs can
/// be edited as those of the paragraph. A field across paragraphs, and any
/// other that is not plain, stays runs ([DocxFieldMark] has how to tell).
///
/// A field is built with [DocxField.new] or one of the helpers, and goes in a
/// paragraph with [DocxParagraph.addField] or [DocxParagraph.insertInline]; it
/// holds real runs (the `begin` mark, the instruction, the `separate` mark, the
/// cached result and the `end` mark), which the save writes in that order. The
/// model computes nothing: the result is the text it was given, and Word
/// recomputes `PAGE`, `NUMPAGES` and `SECTIONPAGES` when it lays the document
/// out, and `DATE` and `TIME` when it opens it. A field goes in one paragraph
/// once; inserting it again while it is in one throws [StateError].
final class DocxField extends DocxInline {
  /// A field with [instruction], such as ` PAGE \* Arabic `, and [result] as
  /// its cached result.
  ///
  /// The instruction is written as given (the field's own spaces and
  /// switches are the caller's). Characters XML forbids are removed from it
  /// and from [result], and the save reports how many
  /// (`DocxWarningCode.invalidCharactersRemoved`). An [instruction] that is
  /// empty or only white space, once those are removed, throws
  /// [ArgumentError].
  DocxField(String instruction, {String result = ''}) : super._() {
    final ScrubResult scrubbed = _checkInstruction(instruction);
    final DocxRun begin = _runOf(<DocxRunContent>[
      newFieldMark(DocxFieldMarkType.begin),
    ]);
    final DocxRun instructionRun = _runOf(<DocxRunContent>[
      newFieldInstruction(scrubbed.text),
    ], removed: scrubbed.removed);
    final DocxRun separate = _runOf(<DocxRunContent>[
      newFieldMark(DocxFieldMarkType.separate),
    ]);
    final DocxRun resultRun = DocxRun(result);
    final DocxRun end = _runOf(<DocxRunContent>[
      newFieldMark(DocxFieldMarkType.end),
    ]);
    _inlines = <DocxInline>[begin, instructionRun, separate, resultRun, end];
    _resultStart = 3;
    _attach();
  }

  /// A field that shows the number of the page it is on (` PAGE `), cached as
  /// `1`.
  factory DocxField.page() => DocxField(' PAGE ', result: '1');

  /// A field that shows the number of pages of the document
  /// (` NUMPAGES `), cached as `1`.
  factory DocxField.numPages() => DocxField(' NUMPAGES ', result: '1');

  /// A field that shows the number of pages of the section
  /// (` SECTIONPAGES `), cached as `1`.
  factory DocxField.sectionPages() => DocxField(' SECTIONPAGES ', result: '1');

  /// A field that shows the date, in [format] (a Word date picture such as
  /// `dd.MM.yyyy`): the instruction is ` DATE \@ "dd.MM.yyyy" `.
  ///
  /// The library has no clock, so [result] is what is cached (empty by default)
  /// and Word computes the date when it opens the file. A [format] holding `"`,
  /// or ending in a backslash, throws [ArgumentError]; the picture is not
  /// checked otherwise.
  factory DocxField.date({String format = 'dd.MM.yyyy', String result = ''}) =>
      DocxField(' DATE \\@ "${_picture(format)}" ', result: result);

  /// A field that shows the time, in [format] (a Word time picture such as
  /// `HH:mm`): the instruction is ` TIME \@ "HH:mm" `. [result] and [format]
  /// are as [DocxField.date] has them.
  factory DocxField.time({String format = 'HH:mm', String result = ''}) =>
      DocxField(' TIME \\@ "${_picture(format)}" ', result: result);

  DocxField._read(List<DocxInline> inlines, int resultStart)
    : _inlines = inlines,
      _resultStart = resultStart,
      super._() {
    _attach();
  }

  /// [format], which must not hold `"` or end in a backslash, or an
  /// [ArgumentError].
  static String _picture(String format) {
    if (format.contains('"') || format.endsWith('\\')) {
      throw ArgumentError.value(
        format,
        'format',
        'must not hold a quote or end in a backslash',
      );
    }
    return format;
  }

  static ScrubResult _checkInstruction(String instruction) {
    final ScrubResult scrubbed = scrubXmlText(instruction);
    if (scrubbed.text.trim().isEmpty) {
      throw ArgumentError.value(
        instruction,
        'instruction',
        'must not be empty',
      );
    }
    return scrubbed;
  }

  static DocxRun _runOf(List<DocxRunContent> content, {int removed = 0}) {
    final DocxRun run = DocxRun();
    run._content.addAll(content);
    run._removed = removed;
    return run;
  }

  /// Every inline of the field, from the `begin` run to the `end` run: as
  /// read, or as built, and as edited since. A field in the result is one of
  /// them.
  late List<DocxInline> _inlines;

  /// The index in [_inlines] of the first inline of the result, or of the
  /// `end` run for a field with no `separate`.
  late int _resultStart;

  late List<DocxInline> _result = _resultOf(_inlines, _resultStart);

  static List<DocxInline> _resultOf(List<DocxInline> inlines, int start) =>
      List<DocxInline>.unmodifiable(inlines.sublist(start, inlines.length - 1));

  /// Makes every inline of the field know the field and its paragraph.
  void _attach() {
    _result = _resultOf(_inlines, _resultStart);
    for (final DocxInline inline in _inlines) {
      inline._field = this;
      setParagraphOf(inline, _paragraph);
    }
  }

  DocxEditSink get _sink {
    final DocxParagraph? paragraph = _paragraph;
    return paragraph == null ? DocxEditSink.none : editSinkOf(paragraph);
  }

  /// The runs of the field, nested fields' among them, in order.
  List<DocxRun> get _runs {
    final List<DocxRun> out = <DocxRun>[];
    visitInlines(this, (DocxInline inline) {
      if (inline is DocxRun) out.add(inline);
    });
    return out;
  }

  /// The runs before the result that hold an instruction, in order.
  List<DocxRun> get _instructionRuns => <DocxRun>[
    for (final DocxInline inline in _inlines.take(_resultStart))
      if (inline is DocxRun &&
          inline._content.any((DocxRunContent c) => c is DocxFieldInstruction))
        inline,
  ];

  /// Whether the field has a `separate` mark.
  bool get _hasSeparate {
    final DocxInline before = _inlines[_resultStart - 1];
    return before is DocxRun &&
        before._content.any(
          (DocxRunContent c) =>
              c is DocxFieldMark && c.type == DocxFieldMarkType.separate,
        );
  }

  late final DocxRunProperties _properties = newFieldRunProperties(
    () => <PropertySet>[for (final DocxRun run in _runs) runPropertySetOf(run)],
    () => _sink,
  );

  /// The formatting of the field's runs (`w:rPr`), the same object every
  /// time.
  ///
  /// A member reads the first run of the field, the one that holds the
  /// `begin` mark. Setting one sets it on every run of the field, those of
  /// nested fields among them, as one edit: the instruction and the result
  /// show in the one format, as Word formats a field. The runs of a hyperlink
  /// in the field's result are among them. The runs an edit adds
  /// ([resultText] on a field with no result, [instruction] on one with no
  /// instruction run) carry none of it.
  DocxRunProperties get properties => _properties;

  /// The field's instruction, the text of its `w:instrText`s joined as read,
  /// such as ` PAGE `.
  ///
  /// Setting it puts the whole text in the first run that holds an
  /// instruction, which keeps its `w:rPr`, and removes the other instruction
  /// runs; inlines between them (a `w:proofErr`) stay. A field with no
  /// instruction run gets one after its `begin` run. The text is written as
  /// given, with characters XML forbids removed and reported at save. An
  /// empty instruction, or one of white space only, throws [ArgumentError]
  /// before anything changes. Setting the text the field has changes nothing.
  /// The edit is one change of the document's log.
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

  set instruction(String value) {
    final ScrubResult scrubbed = _checkInstruction(value);
    final List<DocxRun> runs = _instructionRuns;
    int removed = 0;
    for (final DocxRun run in runs) {
      removed += run._removed;
    }
    if (scrubbed.text == instruction && scrubbed.removed == removed) return;
    final DocxRunText next = (
      content: <DocxRunContent>[newFieldInstruction(scrubbed.text)],
      removed: scrubbed.removed,
    );
    final List<DocxInline> inlines = <DocxInline>[..._inlines];
    final Map<DocxRun, DocxRunText> before = <DocxRun, DocxRunText>{};
    final Map<DocxRun, DocxRunText> after = <DocxRun, DocxRunText>{};
    int resultStart = _resultStart;
    if (runs.isEmpty) {
      final DocxRun added = DocxRun();
      inlines.insert(1, added);
      resultStart++;
      after[added] = next;
    } else {
      before[runs.first] = runTextOf(runs.first);
      after[runs.first] = next;
      for (final DocxRun gone in runs.skip(1)) {
        inlines.remove(gone);
        resultStart--;
      }
    }
    _apply(before, inlines, resultStart, after);
  }

  /// The first word of [instruction] in upper case, such as `PAGE`, or `null`
  /// for an instruction of no word. A word ends at white space or at a
  /// backslash, so `PAGE\* Arabic` is `PAGE`.
  String? get name {
    final String word = instruction.trim().split(RegExp(r'[\s\\]')).first;
    return word.isEmpty ? null : word.toUpperCase();
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

  /// Sets the cached result to [value], split into text, tabs and breaks as
  /// [DocxRun.text] is, with characters XML forbids removed and reported at
  /// save.
  ///
  /// The first run of the result keeps its `w:rPr` and takes the text, and
  /// every other inline of the old result goes, a field nested in it with
  /// them. A field with no `separate` gets one, and a run for the text. The
  /// edit is one change of the document's log, and setting what the result
  /// already is changes nothing.
  set resultText(String value) {
    final ScrubResult scrubbed = scrubXmlText(value);
    final List<DocxRunContent> content = _split(scrubbed.text);
    DocxRun? kept;
    for (final DocxInline inline in _result) {
      if (inline is DocxRun) {
        kept = inline;
        break;
      }
    }
    if (scrubbed.text == text && scrubbed.removed == (kept?._removed ?? 0)) {
      return;
    }
    final DocxRun run = kept ?? DocxRun(value);
    final List<DocxInline> inlines = _inlines.sublist(0, _resultStart);
    if (!_hasSeparate) {
      inlines.add(
        _runOf(<DocxRunContent>[newFieldMark(DocxFieldMarkType.separate)]),
      );
    }
    final int resultStart = inlines.length;
    inlines
      ..add(run)
      ..add(_inlines.last);
    final Map<DocxRun, DocxRunText> before = <DocxRun, DocxRunText>{};
    if (kept != null) before[kept] = runTextOf(kept);
    _apply(before, inlines, resultStart, <DocxRun, DocxRunText>{
      run: (content: content, removed: scrubbed.removed),
    });
  }

  /// Records the edit that gives the field [inlines], [resultStart] and the
  /// run content [after], from what it has and [before] now.
  void _apply(
    Map<DocxRun, DocxRunText> before,
    List<DocxInline> inlines,
    int resultStart,
    Map<DocxRun, DocxRunText> after,
  ) {
    _sink.apply(
      _FieldEdit(
        this,
        (inlines: _inlines, resultStart: _resultStart, texts: before),
        (inlines: inlines, resultStart: resultStart, texts: after),
      ),
    );
  }

  /// Puts [state] on the field, without reporting it.
  void _restore(_FieldState state) {
    final Set<DocxInline> kept = Set<DocxInline>.identity()
      ..addAll(state.inlines);
    for (final DocxInline gone in _inlines) {
      if (kept.contains(gone)) continue;
      gone._field = null;
      setParagraphOf(gone, null);
    }
    _inlines = state.inlines;
    _resultStart = state.resultStart;
    _attach();
    state.texts.forEach(restoreRunText);
  }

  @override
  String toString() => 'DocxField($name)';
}

/// An edit of a field's inlines and the content of some of its runs, from one
/// state to another.
final class _FieldEdit implements Change {
  _FieldEdit(this._field, this._before, this._after);

  final DocxField _field;
  final _FieldState _before;
  final _FieldState _after;

  @override
  void revert() => _field._restore(_before);

  @override
  void reapply() => _field._restore(_after);
}

/// Calls [visit] with [inline], or for a field or a hyperlink with every
/// inline it holds, in file order: runs, bookmark marks and opaque inlines,
/// never a field or a hyperlink. That order is the one the inlines were read
/// in, whatever was typed as a field or a hyperlink.
void visitInlines(DocxInline inline, void Function(DocxInline inline) visit) {
  final List<DocxInline>? held = heldInlinesOf(inline);
  if (held == null) {
    visit(inline);
    return;
  }
  for (final DocxInline h in held) {
    visitInlines(h, visit);
  }
}

/// Every inline [inline] holds, in file order, when it is a field (from its
/// `begin` run to its `end` run) or a hyperlink; `null` for any other.
List<DocxInline>? heldInlinesOf(DocxInline inline) => switch (inline) {
  DocxField() => inline._inlines,
  DocxHyperlink() => inline._inlines,
  _ => null,
};

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
        pairs.opaque(inline._holdsRuns, inline._breaksFields);
      case final DocxHyperlink link:
        // As the opaque inline it was before D5: its own fields are grouped
        // inside it, and what crosses its edge breaks a field around it.
        pairs.opaque(link._holdsRuns, link._breaksFields);
      case DocxBookmarkStart() || DocxBookmarkEnd():
        // Holds no run and no mark: it sits anywhere in a field.
        break;
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
      DocxField._read(<DocxInline>[
        ...inlines.getRange(i, resultStart),
        ...result,
        inlines[field.end],
      ], head),
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

  /// Takes an inline that is no run: an opaque inline or a hyperlink, which
  /// [holdsRuns] when a run or a `w:fldSimple` is inside it and
  /// [breaksFields] when the field marks inside it do not pair.
  void opaque(bool holdsRuns, bool breaksFields) {
    if (breaksFields) _breakOpen();
    final _OpenField? top = _top;
    if (top != null && top.readsInstruction && holdsRuns) {
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
