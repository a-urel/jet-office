/// The workbook model: open an XLSX file or start an empty one, read and set
/// cell values, and save with nothing lost.
///
/// Not ported from Quds; written for jet_office.
///
/// One model, two births (spec §4.1): [XlsxWorkbook.open] reads a file and
/// [XlsxWorkbook.new] starts from the parts the writer writes for an empty
/// workbook (`workbook_parts.dart`, `StyleRegistry`, `properties.dart`), read
/// back the same way, so both save through one code path.
///
/// `open` reads the package skeleton only: the content types, the package
/// and workbook relationships and the workbook part (spec §4.5). It checks
/// every other entry's size and CRC-32 without keeping or parsing it, so a
/// damaged entry is refused at `open` (`corruptZip`) instead of at save.
/// The shared strings and styles load when the first sheet loads; a sheet
/// loads on first use. Saving writes every part of the package in its
/// order: a loaded part from the model, any other from its original bytes
/// (spec §4.3), so a part the model never loaded cannot change.
///
/// Bookkeeping on save (spec §4.4): when a cell changed, `calcChain.xml` is
/// removed (part, relationship and content type) and `calcPr` asks Excel to
/// recalculate, unless every sheet is loaded and none has a formula. The
/// shared strings are append-only, so an unloaded sheet's indexes stay
/// valid; their `count` is written only once every sheet is loaded and the
/// references can be counted. Part names and relationship ids of the file
/// are kept; a new part takes a free name and id. A macro-enabled workbook
/// keeps its `vbaProject.bin` like any part the model does not understand.
///
/// @docImport '../read/xlsx_reader.dart';
library;

import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import '../../common/properties.dart';
import '../../common/properties_parts.dart';
import '../../common/theme_colors.dart';
import '../../drawingml/media.dart';
import '../../opc/change_log.dart';
import '../../opc/ooxml.dart';
import '../../opc/opaque_xml.dart';
import '../../opc/package.dart';
import '../../xml/utf8_buffer.dart';
import '../../xml/xml_pull_reader.dart';
import '../../xml/xml_writer.dart';
import '../../zip/archive_adapter.dart';
import '../cell_encoder.dart';
import '../color.dart';
import '../defined_name.dart';
import '../formula/formula_reference.dart' show renderSheetPrefix;
import '../formula/reference_shift.dart';
import '../number_format.dart';
import '../raw_cell.dart';
import '../read/package_reader.dart';
import '../read/read_exception.dart';
import '../read/read_limits.dart';
import '../read/shared_strings_reader.dart';
import '../read/styles_reader.dart';
import '../shared_strings.dart';
import '../sheet_name.dart';
import '../sheet_protection.dart';
import '../sheet_view.dart';
import '../style_registry.dart';
import '../warnings.dart';
import '../workbook_parts.dart';
import '../worksheet_parts.dart';
import '../xlsx_writer.dart';
import 'cell_store.dart';
import 'defined_names.dart';
import 'element_node.dart';
import 'palette.dart';
import 'primitives.dart';
import 'protection_elements.dart';
import 'reference_holders.dart';
import 'styles_part.dart';
import 'table_part.dart';
import 'vml_part.dart';
import 'workbook_part.dart';
import 'worksheet_part.dart';
import 'xlsx_sheet.dart';

/// The package of [book], for tests.
OpcPackage packageOf(XlsxWorkbook book) => book._book.reader.package;

/// The change log of [book], for tests.
ChangeLog changeLogOf(XlsxWorkbook book) => book._book.log;

/// The reference holders of [book], for structural edits and tests.
ReferenceRegistry referenceRegistryOf(XlsxWorkbook book) =>
    book._book.references;

/// The shared strings of [book], or `null` before they load, for tests.
SharedStrings? sharedStringsOf(XlsxWorkbook book) => book._book._strings;

/// The styles part of [book], or `null` before it loads or when the file
/// has none, for tests.
StylesPart? stylesPartOf(XlsxWorkbook book) => book._book._styles;

/// The styles part of [book] as an edit needs it, made in memory for a file
/// without one (see `_stylesForEdit`), for tests.
StylesPart stylesForEditOf(XlsxWorkbook book) => book._book._stylesForEdit();

/// An XLSX workbook held in memory: opened from a file or started empty,
/// read and changed cell by cell, and saved.
///
/// ```dart
/// final XlsxWorkbook book = XlsxWorkbook.open(bytes);
/// final XlsxSheet prices = book.sheet('Fiyatlar');
/// prices.setCell(4, 1, XlsxDecimal('12.50'));
/// final XlsxResult result = book.save();
/// ```
///
/// Opening then saving with no change gives a file whose every part means
/// what the input's did; a change touches only what it changes, plus the
/// bookkeeping Excel needs (a dropped `calcChain.xml`, `fullCalcOnLoad`).
/// Formula results are not computed: the cached results of formulas the
/// model did not change are kept, so a reader that does not calculate (this
/// library's included) sees them as they were until Excel recalculates.
final class XlsxWorkbook {
  /// An empty workbook, with no sheets yet; add one with [addSheet].
  XlsxWorkbook()
    : _book = _Book(_emptyPackage(), const XlsxReadLimits(), created: true);

  /// Opens the XLSX file [bytes] within [limits].
  ///
  /// Reads only the package skeleton and the workbook part; sheets load on
  /// first use. Every other entry is inflated once and checked against its
  /// declared size and CRC-32, then dropped, so that saving cannot meet a
  /// damaged part. Throws an [ArgumentError] when a limit is below 1 and an
  /// [XlsxReadException] when the file is not a readable XLSX workbook, as
  /// [XlsxReader] does. A sheet the workbook lists without a part is kept,
  /// reads as empty and gets an [XlsxWarningCode.sheetPartMissing] warning.
  factory XlsxWorkbook.open(
    Uint8List bytes, {
    XlsxReadLimits limits = const XlsxReadLimits(),
  }) {
    limits.check();
    return XlsxWorkbook._(_Book(bytes, limits, created: false));
  }

  XlsxWorkbook._(this._book);

  /// The document properties: core (`docProps/core.xml`), extended
  /// (`docProps/app.xml`) and custom (`docProps/custom.xml`) merged into
  /// the writer's [OfficeProperties].
  ///
  /// The parts load on first use, each found by its relationship in the
  /// package root. A part the file lacks, or whose root is not the expected
  /// element, reads as no values. A value that cannot be read (a date that
  /// is not W3CDTF, a custom number that is not one, a name that is empty
  /// or longer than `XlsxLimits.maxCustomPropertyNameLength`) stays as
  /// written, reads as no value and is reported once as
  /// [XlsxWarningCode.featureEntryInvalid] with the element's name. A
  /// custom property of another type than text, number, yes/no or date
  /// stays and is not listed, with no warning; of equal names the first is
  /// listed. Throws an [XlsxReadException] when a part is not readable XML
  /// or exceeds a limit; the workbook still saves, with the part as it was.
  OfficeProperties get properties => _book.propertiesState().parts.merged;

  /// Sets the document properties to [value].
  ///
  /// Only the fields that differ from [properties] change, each in its own
  /// element, which is replaced where it is, appended when new, or removed
  /// for a `null`; every other element of the parts (`dc:language`,
  /// `cp:lastPrinted`, `TitlesOfParts`, a property of a type that is not
  /// listed) stays. A custom property of an equal name and value stays as
  /// written; a new one takes the lowest free `pid`. A custom part joins
  /// the package when it first has a property and leaves when none is left
  /// and the part held no other, at the next save. The file's `modified` and
  /// `lastModifiedBy` change only when set here. A [value] equal to
  /// [properties] changes nothing.
  ///
  /// Throws an [ArgumentError] naming the field, as the writer's
  /// constructors do, for text XML cannot hold or a bad custom entry, and a
  /// [StateError] for a part that is not a properties part and would have
  /// to change, and an [XlsxReadException] when a part is not readable XML
  /// or exceeds a limit; nothing has changed then.
  set properties(OfficeProperties value) {
    final PropertiesState state = _book.propertiesState();
    _book.log.transaction(() => setProperties(_book.log, state, value));
  }

  final _Book _book;

  /// The sheets in tab order. Unmodifiable.
  List<XlsxSheet> get sheets => _book.sheetsView;

  /// The first sheet named [name], compared ignoring case as Excel compares
  /// sheet names.
  ///
  /// Throws an [ArgumentError] when no sheet has that name.
  XlsxSheet sheet(String name) {
    final String key = sheetNameKey(name);
    for (final XlsxSheet s in sheets) {
      if (sheetNameKey(s.name) == key) return s;
    }
    throw ArgumentError.value(name, 'name', 'No such sheet.');
  }

  /// Adds a visible sheet named [name] at the tab index [position]
  /// (0-based; after the last tab when `null`) and returns it.
  ///
  /// The name is made valid and unique as `XlsxWriter.addSheet` makes it,
  /// against the sheets the workbook already has, and a changed name is
  /// reported as a warning. The sheet's part and relationship take a name
  /// and an id the package does not use yet. A sheet placed before others
  /// leaves every tab index on its sheet: a sheet's names, the active tab
  /// and the first tab shown. Its title joins the sheet titles of
  /// `docProps/app.xml` at its place. Undone, the part, its relationship and its
  /// content type go again. Loads the shared strings and styles, so it
  /// throws an [XlsxReadException] when they cannot be read; a [RangeError]
  /// named `position` for a position past the last tab. Nothing changes
  /// when it throws.
  XlsxSheet addSheet(String name, {int? position}) =>
      _book.addSheet(name, position: position);

  /// Renames [sheet] to [newName], as Excel's Rename does: every reference
  /// to the sheet by name (formulas, names, rules, validations, charts and
  /// the parts the structural edits rewrite) names it anew, quoted when the
  /// name needs it, and the sheet's titles in `docProps/app.xml` follow
  /// (`TitlesOfParts`: the sheet's own and its named ranges', as
  /// `Data!Print_Area`). Nothing else changes.
  ///
  /// [newName] must be a name the writer would keep as it is: no character
  /// of `[ ] : * ? / \` or that XML cannot hold, no space or apostrophe
  /// at either end, not empty, at most 31 characters, and no other sheet's
  /// name or `History`, ignoring case; otherwise an [ArgumentError] named `newName` is thrown and
  /// nothing changes. The same name changes nothing; a name that differs
  /// only in case is a rename. Throws an [ArgumentError] for a sheet of
  /// another workbook, and an [XlsxReadException] when a sheet cannot be
  /// read; nothing changes then.
  void renameSheet(XlsxSheet sheet, String newName) =>
      _book.renameSheet(sheet, newName);

  /// Moves [sheet] to the tab index [position] (0-based, in the order after
  /// the move), as Excel's Move does: each name scoped to a sheet stays on
  /// it (`localSheetId`), the active tab and the first tab shown stay on
  /// their sheets, and a 3D reference whose first sheet comes after its
  /// last has its ends swapped, and the sheet titles of `docProps/app.xml`
  /// take the new order. The save asks Excel to recalculate, since a
  /// 3D reference may now span other sheets. The same position changes
  /// nothing.
  ///
  /// Throws a [RangeError] named `position` for a position past the last
  /// tab, an [ArgumentError] for a sheet of another workbook, and an
  /// [XlsxReadException] when a sheet cannot be read; nothing changes then.
  void moveSheet(XlsxSheet sheet, int position) =>
      _book.moveSheet(sheet, position);

  /// The sheet Excel opens on: the one at the first `workbookView`'s
  /// `activeTab`, or the first sheet when there is no such attribute or it
  /// is past the last tab.
  ///
  /// Throws a [StateError] for a workbook with no sheet.
  XlsxSheet get activeSheet => _book.activeSheet;

  /// The names defined for the whole workbook, in file order, as the file
  /// has them.
  ///
  /// Excel's built-in names (`_xlnm.Print_Area` and the like) are not
  /// listed, and a name the model cannot read is left out and reported
  /// (`featureEntryInvalid`); both stay in the file as written. A sheet's
  /// own names are [XlsxSheet.definedNames]. Unmodifiable.
  List<XlsxDefinedName> get definedNames =>
      definedNamesIn(_book.workbook, null);

  /// Defines [name] for the whole workbook, after the names already there.
  ///
  /// Checked as the writer checks it: the same spelling may be defined on a
  /// sheet as well, where it hides this one. Throws an [ArgumentError]
  /// naming `name`, `formula` or `comment` for an invalid name, formula or
  /// comment, a workbook name already defined or a name that a table has,
  /// ignoring case; nothing changes then.
  ///
  /// A defined name changes what formulas show as a changed cell does, so
  /// the save asks Excel to recalculate every formula (`fullCalcOnLoad`)
  /// when the workbook has formulas; the calculation chain stays.
  void defineName(XlsxDefinedName name) => defineNameIn(
    _book.log,
    _book.workbook,
    null,
    name,
    _book.checkNotTableName,
  );

  /// Removes the workbook name [name], compared ignoring case.
  ///
  /// Throws an [ArgumentError] named `name` when the workbook has no such
  /// name (a built-in name is none); nothing changes then. The save asks
  /// for recalculation as [defineName] does.
  void removeName(String name) =>
      removeNameIn(_book.log, _book.workbook, null, name, 'the workbook');

  /// Makes [sheet] the sheet Excel opens on: sets `activeTab`, `tabSelected`
  /// on its view, and clears `tabSelected` on the sheet that was active
  /// (loading both sheets). A chartsheet or a sheet without a part has no
  /// view to select; only `activeTab` changes for it. The sheet that is
  /// active already changes nothing, so a file without `activeTab` or
  /// `tabSelected` stays without them.
  ///
  /// Throws an [ArgumentError] for a sheet of another workbook and a
  /// [StateError] for a sheet that is not visible; nothing changes then.
  /// Throws an [XlsxReadException] when a sheet to load cannot be read.
  set activeSheet(XlsxSheet sheet) => _book.setActiveSheet(sheet);

  /// Whether the workbook counts dates from 1904, as files from old Mac
  /// versions of Excel do; dates are set and read in its system.
  bool get date1904 => _book.workbook.date1904;

  /// The workbook's protection, or `null` when it has no
  /// `<workbookProtection>`.
  ///
  /// The password always reads `null`: the file stores a hash
  /// ([hasStoredPassword] says whether it has one). An element that locks
  /// nothing reads as a protection that locks nothing. Only the first
  /// element is read.
  XlsxWorkbookProtection? get protection {
    final Object? node = _book.workbook.element('workbookProtection');
    return node is XmlNode ? readWorkbookProtection(node) : null;
  }

  /// Protects the workbook as [value] says, or removes the
  /// `<workbookProtection>` with `null`, a stored hash with it.
  ///
  /// A new element is the writer's, in schema position. An existing one
  /// keeps its other attributes (`lockRevision`, the `revisions...` hash)
  /// and changes a lock only when its meaning changes. A [value] with no
  /// `password` keeps the stored hash; a password replaces the
  /// `workbook...` hash attributes. A value that locks nothing and has no
  /// password removes the element unless a stored hash stays, as the writer
  /// writes nothing for it. A value equal to [protection] changes nothing.
  ///
  /// Throws an [ArgumentError] named `password` for a password that is not
  /// 1 to 15 characters from U+0020 to U+007E and a [StateError] for a
  /// workbook part that is not a workbook; nothing has changed then.
  set protection(XlsxWorkbookProtection? value) {
    checkProtectionPassword(value?.password);
    final WorkbookPart part = _book.workbook;
    if (value == protection) return;
    final XmlNode? old = part.element('workbookProtection') as XmlNode?;
    final XmlNode? next = value == null
        ? null
        : applyWorkbookProtection(old, value, part.elementPrefix);
    _book.log.transaction(() {
      editWorkbook(
        _book.log,
        part,
        'workbookProtection',
        () => part.swapElement('workbookProtection', old, next),
      );
    });
  }

  /// Whether the workbook's `<workbookProtection>` stores a password: a
  /// `workbookPassword` or a `workbookHashValue`. The password itself is
  /// never read.
  bool get hasStoredPassword {
    final Object? node = _book.workbook.element('workbookProtection');
    return node is XmlNode && workbookHasStoredPassword(node);
  }

  /// The 64 colours `<color indexed="N"/>` shows: the file's `<indexedColors>`
  /// or the default palette (ECMA-376 Part 1, section 18.8.27), unmodifiable.
  ///
  /// A `[ColorN]` of a number format result is `XlsxColor.indexed(N + 7)`
  /// and its value is `indexedColors[N + 7]`. Loads the shared strings and
  /// styles, so it throws an [XlsxReadException] when they cannot be read.
  List<int> get indexedColors => _book.indexedColors;

  /// The colour [color] shows, as `0xAARRGGBB`, or `null` when it has none.
  ///
  /// An `rgb` colour is itself. An `indexed` colour 0 to 63 is
  /// [indexedColors]'s entry; 64 and 65 (the system colours) and anything
  /// else give `null`. A `theme` colour is the slot of the theme part the
  /// workbook relates to, in SpreadsheetML's order (0 lt1, 1 dk1, 2 lt2,
  /// 3 dk2, 4 to 9 accent1 to 6, 10 hlink, 11 folHlink), with its tint
  /// applied; a tint that is not finite or not within -1 to 1 is ignored, so
  /// the slot's own colour results. `auto`, a missing or unreadable theme
  /// and a missing slot give `null`.
  ///
  /// The theme part is read once, from its bytes, and stays unloaded: saving
  /// copies it unchanged. Only an `indexed` colour loads the styles (see
  /// [indexedColors]); no colour makes this method throw on a theme.
  int? resolveColor(XlsxColor color) => _book.resolveColor(color);

  /// What was repaired or could not be read exactly while opening, editing
  /// and saving, aggregated per sheet and [XlsxWarningCode]. An unmodifiable
  /// live view.
  List<XlsxWarning> get warnings => _book.warnings.warnings;

  /// Saves the workbook and returns the file with the warnings so far.
  ///
  /// Throws a [StateError] when a workbook started with [XlsxWorkbook.new]
  /// has no sheet or no visible sheet, with the writer's messages. An opened
  /// workbook saves the sheets it came with, as it came, even none or only
  /// hidden ones. [XlsxWorkbook.open] has checked every entry of the file,
  /// so a part the model did not load is copied from intact bytes.
  XlsxResult save() {
    _book.checkSavable();
    final ZipWriter zip = ZipWriter();
    _book.writeTo(zip);
    return xlsxResultOf(
      zip.close()!,
      List<XlsxWarning>.unmodifiable(_book.warnings.warnings),
    );
  }

  /// Saves the workbook to [sink], as [XlsxStreamWriter] sends a file, and
  /// closes it.
  ///
  /// Throws as [save] does; for a workbook without a (visible) sheet nothing
  /// is sent and the sink stays open. Rethrows what the sink throws.
  void saveTo(Sink<List<int>> sink) {
    _book.checkSavable();
    final ZipWriter zip = ZipWriter(sink: sink);
    _book.writeTo(zip);
    zip.close();
  }
}

/// The package of an empty workbook, written by the writer's own part
/// writers: a workbook without sheets, its relationships, empty styles and
/// shared strings, and the default document properties.
Uint8List _emptyPackage() {
  Uint8List render(void Function(XmlWriter w) write) {
    final Utf8Buffer out = Utf8Buffer();
    write(XmlWriter(out));
    return out.takeBytes();
  }

  const OfficeProperties properties = OfficeProperties();
  final ZipWriter zip = ZipWriter()
    ..add(
      'xl/workbook.xml',
      render(
        (XmlWriter w) => writeWorkbook(
          w,
          tabs: const <WorkbookSheet>[],
          activeTab: 0,
          fullCalcOnLoad: false,
        ),
      ),
    )
    ..add('xl/styles.xml', render(StyleRegistry().writeStylesXml))
    ..add('xl/sharedStrings.xml', render(SharedStrings().writeXml))
    ..add(
      'xl/_rels/workbook.xml.rels',
      render((XmlWriter w) => writeWorkbookRelationships(w, 0)),
    )
    ..add(
      'docProps/core.xml',
      render((XmlWriter w) => writeCoreProperties(w, properties)),
    )
    ..add(
      'docProps/app.xml',
      render((XmlWriter w) => writeAppProperties(w, properties)),
    )
    ..add('_rels/.rels', render(writeRootRelationships))
    ..add(
      '[Content_Types].xml',
      render((XmlWriter w) => writeContentTypes(w, 0)),
    );
  return zip.close()!;
}

/// The change of a table part leaving what the file's table parts say.
final class _TableHeadChange implements Change {
  _TableHeadChange(this.heads, this.part, this.head);

  final Map<String, ({int id, List<String> names})> heads;
  final String part;
  final ({int id, List<String> names}) head;

  @override
  void revert() => heads[part] = head;

  @override
  void reapply() => heads.remove(part);
}

/// The change of a sheet's name.
final class _RenameChange implements Change {
  _RenameChange(this.entry, this.before, this.after);

  final SheetEntry entry;
  final String before;
  final String after;

  @override
  void revert() => entry.name = before;

  @override
  void reapply() => entry.name = after;
}

/// The loading of the document properties by an edit: undone, the
/// workbook has not loaded them, and each properties part of the file
/// writes its bytes from the file again.
final class _PropertiesLoadChange implements Change {
  _PropertiesLoadChange(this.book, this.state)
    : parts = <String>[
        for (final PropertyKind kind in PropertyKind.values)
          if (book._package.hasPart(state.partName(kind))) state.partName(kind),
      ];

  final _Book book;
  final PropertiesState state;

  /// The properties parts the file has.
  final List<String> parts;

  @override
  void revert() {
    book._properties = null;
    final OpcPackage package = book._package;
    for (final String name in parts) {
      package.setContent(name, originalPartContent(package, name));
    }
  }

  @override
  void reapply() => book._properties = state;
}

/// The change of the order of the sheets: the workbook part's `<sheets>`
/// items and the model's sheets, before and after.
final class _OrderChange implements Change {
  _OrderChange(
    this.book,
    this.itemsBefore,
    this.itemsAfter,
    this.sheetsBefore,
    this.sheetsAfter,
  );

  final _Book book;
  final List<Object> itemsBefore;
  final List<Object> itemsAfter;
  final List<XlsxSheet> sheetsBefore;
  final List<XlsxSheet> sheetsAfter;

  void _set(List<Object> items, List<XlsxSheet> sheets) {
    book.workbook.restoreSheetItems(items);
    book._sheets
      ..clear()
      ..addAll(sheets);
  }

  @override
  void revert() => _set(itemsBefore, sheetsBefore);

  @override
  void reapply() => _set(itemsAfter, sheetsAfter);
}

/// The shared strings as a part's content.
///
/// [_root] and [_trailing] are the opened part's `<sst>` start tag and its
/// children other than `<si>`, written back so nothing of the part is lost.
final class _SharedStringsContent implements PartContent {
  _SharedStringsContent(
    this._strings, {
    XmlRoot? root,
    List<OpaqueXml> trailing = const <OpaqueXml>[],
  }) : _root = root,
       _trailing = trailing;

  final SharedStrings _strings;
  final XmlRoot? _root;
  final List<OpaqueXml> _trailing;

  @override
  List<Uint8List> encode() {
    final Utf8Buffer out = Utf8Buffer();
    _strings.writeXml(XmlWriter(out), root: _root, trailing: _trailing);
    return out.takeChunks();
  }
}

/// The shared strings' texts by index as a list, without copying them.
final class _Texts extends ListBase<String> {
  _Texts(this._strings);

  final SharedStrings _strings;

  @override
  int get length => _strings.length;

  @override
  set length(int value) => throw UnsupportedError('Read-only.');

  @override
  String operator [](int index) => _strings.textAt(index);

  @override
  void operator []=(int index, String value) =>
      throw UnsupportedError('Read-only.');
}

/// The state behind an [XlsxWorkbook], which its sheets share.
final class _Book implements SheetHost {
  _Book(Uint8List bytes, XlsxReadLimits limits, {required this.created})
    : reader = PackageReader(bytes, limits) {
    final String plain = reader.workbookPart;
    workbookName = reader.package.canonicalPartName(plain)!;
    final WorkbookPart part = reader.guardXml(
      plain,
      () => WorkbookPart.read(
        reader.openXml(plain),
        limits,
        warn: _styleWarning,
        part: plain,
      ),
    );
    if (!part.isTyped) {
      throw XlsxReadException(
        XlsxReadFailure.missingWorkbook,
        'The workbook part is not a SpreadsheetML workbook.',
        part: plain,
      );
    }
    workbook = part;
    reader.package.setContent(workbookName, part);
    final Map<String, String> targets = <String, String>{
      for (final PartRelationship r in reader.relationshipsOf(plain))
        r.id: r.target,
    };
    for (final SheetEntry entry in part.sheets) {
      final String? target = targets[entry.relationshipId];
      final String? partName = target == null
          ? null
          : reader.package.canonicalPartName(target);
      final XlsxSheet sheet = newSheet(this, entry, partName);
      _sheets.add(sheet);
      if (partName == null) {
        warnings.add(
          XlsxWarningCode.sheetPartMissing,
          sheet: entry.name,
          key: sheet,
        );
      }
    }
    // Last, so a broken skeleton is reported as the reader reports it.
    reader.verifyEntries();
  }

  @override
  final PackageReader reader;

  /// Whether the workbook was started with `XlsxWorkbook()`, so that saving
  /// it without a (visible) sheet is a programmer error; an opened workbook
  /// saves the sheets it came with, none or all hidden included.
  final bool created;

  @override
  final ChangeLog log = ChangeLog();

  @override
  final WarningCollector warnings = WarningCollector();

  /// The workbook part's name, absolute, as stored.
  late final String workbookName;
  late final WorkbookPart workbook;

  final List<XlsxSheet> _sheets = <XlsxSheet>[];
  late final List<XlsxSheet> sheetsView = UnmodifiableListView<XlsxSheet>(
    _sheets,
  );

  /// Every holder of a reference in the workbook, for structural edits.
  @override
  late final ReferenceRegistry references = ReferenceRegistry(
    log,
    () => _sheets,
    workbookPart: () => workbook,
    reader: () => reader,
    warnings: warnings,
  );

  CellEncoder? _encoder;
  SharedStrings? _strings;
  late final _Texts _texts = _Texts(_strings!);

  /// The shared strings part's name; `null` while the package has none.
  String? _stringsName;
  StylesPart? _styles;

  /// The theme's colours, read once; `null` for no theme or an unreadable one.
  ThemeColors? _theme;
  bool _themeRead = false;

  List<int> get indexedColors {
    loadTables();
    return _styles?.indexedColors ?? defaultIndexedColors;
  }

  int? resolveColor(XlsxColor color) {
    switch (color.kind) {
      case XlsxColorKind.rgb:
        return color.argb;
      case XlsxColorKind.auto:
        return null;
      case XlsxColorKind.indexed:
        final int i = color.paletteIndex!;
        return i >= 0 && i < 64 ? indexedColors[i] : null;
      case XlsxColorKind.theme:
        final int i = color.themeIndex!;
        if (i < 0 || i >= themeSlotNames.length) return null;
        final int? base = _themeColors()?.argbOf(themeSlotNames[i]);
        if (base == null) return null;
        final double tint = color.tint;
        return tint.isFinite && tint >= -1 && tint <= 1
            ? applyTint(base, tint)
            : base;
    }
  }

  ThemeColors? _themeColors() {
    if (_themeRead) return _theme;
    _themeRead = true;
    final String? target = _target(RelType.theme);
    if (target == null) return null;
    try {
      return _theme = reader.guardXml(
        target,
        () => ThemeColors.read(reader.openXml(target)),
      );
    } on XlsxReadException {
      return null;
    }
  }

  OpcPackage get _package => reader.package;

  @override
  bool get date1904 => workbook.date1904;

  @override
  WorkbookPart get workbookPart => workbook;

  @override
  int sheetIndexOf(XlsxSheet sheet) =>
      _sheets.indexWhere((XlsxSheet s) => identical(s, sheet));

  /// The VML blocks the package's parts use, once they were scanned.
  Set<int>? _usedVmlBlocks;

  /// The next VML block to try.
  int _nextVmlBlock = 1;

  DrawingMediaIndex? _mediaIndex;

  @override
  DrawingMediaIndex get mediaIndex =>
      _mediaIndex ??= DrawingMediaIndex(_package);

  @override
  int takeVmlBlock() {
    final Set<int> used = _usedVmlBlocks ??= _scanVmlBlocks();
    while (used.contains(_nextVmlBlock)) {
      _nextVmlBlock++;
    }
    return _nextVmlBlock++;
  }

  /// The blocks every `.vml` part of the file uses, read from its text:
  /// VML need not be XML, and the parts of unloaded sheets count.
  Set<int> _scanVmlBlocks() {
    final Set<int> used = <int>{};
    for (final String name in _package.partNames.toList()) {
      if (!name.toLowerCase().endsWith('.vml')) continue;
      final Uint8List bytes = reader.guardXml(
        name,
        () => _package.originalBytes(name),
      );
      used.addAll(vmlBlocksIn(utf8.decode(bytes, allowMalformed: true)));
    }
    return used;
  }

  /// The `id` and the names of every table part of the file, read once from
  /// each root, by part name: a part no sheet types keeps its name and id
  /// that way, and so does one of a sheet never read. Parts added since are
  /// typed, so a sheet's list holds them; a part that leaves leaves this too
  /// ([forgetTablePart]), so a later part of its name is not taken for it.
  Map<String, ({int id, List<String> names})>? _tableHeads;

  Map<String, ({int id, List<String> names})> get _fileTables =>
      _tableHeads ??= _readTableHeads();

  Map<String, ({int id, List<String> names})> _readTableHeads() {
    final Map<String, ({int id, List<String> names})> heads =
        <String, ({int id, List<String> names})>{};
    for (final String name in _package.partNames.toList()) {
      if (_package.contentTypeOf(name) != ContentType.table) continue;
      try {
        final ({int id, List<String> names})? head = reader.guardXml(
          name,
          () => TablePart.readHead(reader.openXml(name)),
        );
        if (head != null) heads[name] = head;
      } on XlsxReadException {
        // Kept as written: an unreadable part has no name to keep.
      }
    }
    return heads;
  }

  @override
  void forgetTablePart(String name) {
    final String? part = _package.canonicalPartName(name);
    final ({int id, List<String> names})? head = _fileTables[part];
    if (part == null || head == null) return;
    applyChange(log, _TableHeadChange(_fileTables, part, head));
  }

  @override
  void checkNotTableName(String name) {
    final String key = sheetNameKey(name);
    final Iterable<String> tables = <String>[
      for (final XlsxSheet s in _sheets) ...sheetTableNames(s),
      for (final ({int id, List<String> names}) head in _fileTables.values)
        ...head.names,
    ];
    for (final String table in tables) {
      if (sheetNameKey(table) == key) {
        throw ArgumentError.value(
          name,
          'name',
          'The name "$name" is already the name of the table "$table"; '
              'table names and defined names are compared ignoring case.',
        );
      }
    }
  }

  @override
  void checkTableNameFree(String name) {
    checkNotTableName(name);
    final String key = sheetNameKey(name);
    for (final NameEntry e in workbook.names) {
      if (sheetNameKey(e.name) == key) {
        throw ArgumentError.value(
          name,
          'name',
          'The name "$name" is already a defined name, "${e.name}"; table '
              'names and defined names are compared ignoring case.',
        );
      }
    }
  }

  @override
  int takeTableId() {
    int highest = 0;
    for (final int id in <int>[
      for (final ({int id, List<String> names}) head in _fileTables.values)
        head.id,
      ..._sheets.expand(sheetTableIds),
    ]) {
      if (id > highest) highest = id;
    }
    return highest + 1;
  }

  @override
  StyleTable get styleTable => _styles?.table ?? StyleTable.empty;

  @override
  SharedStrings? get sharedStrings => _strings;

  @override
  List<String>? get sharedStringTexts =>
      _stringsName != null || _strings!.length > 0 ? _texts : null;

  @override
  CellEncoder loadTables() {
    final CellEncoder? loaded = _encoder;
    if (loaded != null) return loaded;
    final XlsxReadLimits limits = reader.limits;
    final String? stylesTarget = _target(RelType.styles);
    final StylesPart? styles = stylesTarget == null
        ? null
        : reader.guardXml(
            stylesTarget,
            () => StylesPart.read(
              reader.openXml(stylesTarget),
              limits,
              warn: _styleWarning,
              part: stylesTarget,
            ),
          );
    final String? stringsTarget = _target(RelType.sharedStrings);
    final SharedStrings strings;
    SharedStringsRead? read;
    if (stringsTarget == null) {
      strings = SharedStrings();
    } else {
      read = readSharedStringsRaw(reader, stringsTarget, limits);
      strings = SharedStrings.seeded(read.texts, raw: read.raw);
    }
    // Both read: only now is anything kept.
    if (stylesTarget != null) {
      _package.setContent(stylesTarget, styles!);
      _styles = styles;
    }
    if (stringsTarget != null) {
      _stringsName = _package.canonicalPartName(stringsTarget);
      _package.setContent(
        stringsTarget,
        _SharedStringsContent(
          strings,
          root: read!.root,
          trailing: read.trailing,
        ),
      );
    }
    _strings = strings;
    return _encoder = CellEncoder(
      strings: strings,
      // Unused: the model's styles are raw indexes into its styles part.
      styles: StyleRegistry(),
      warnings: warnings,
    );
  }

  /// Reports a style entry that cannot be read exactly: a warning about
  /// the workbook, so it names no sheet.
  void _styleWarning(XlsxWarningCode code, String detail) =>
      warnings.add(code, sheet: '', detail: detail);

  @override
  StylesPart? get styles => _styles;

  @override
  StylesPart stylesForEdit() => _stylesForEdit();

  @override
  int? dateStyle(int? style, {required bool withTime}) {
    final XlsxNumFmt format = withTime
        ? XlsxNumFmt.localeDateTime
        : XlsxNumFmt.localeShortDate;
    final StylesPart styles = _stylesForEdit();
    if (!styles.isTyped) return null;
    return appendNumberFormat(log, styles, style, format.builtinId!);
  }

  /// The styles part; for a file without one, a part of the writer's empty
  /// styles that is held in memory only and joins the package on save once
  /// it holds an appended entry (see [writeTo]), so an edit that fails or is
  /// undone leaves the package as it was.
  StylesPart _stylesForEdit() {
    final StylesPart? loaded = _styles;
    if (loaded != null) return loaded;
    final Utf8Buffer out = Utf8Buffer();
    StyleRegistry().writeStylesXml(XmlWriter(out));
    final StylesPart part = StylesPart.read(
      XmlPullReader.fromBytes(out.takeBytes()),
      reader.limits,
      warn: _styleWarning,
    );
    _createdStyles = part.mark();
    return _styles = part;
  }

  PropertiesState? _properties;

  /// The document properties, loaded on first use; a part that cannot be
  /// read throws and nothing is kept.
  PropertiesState propertiesState() => _properties ??= PropertiesState.load(
    _XlsxPropertiesSource(reader),
    (String element) => warnings.add(
      XlsxWarningCode.featureEntryInvalid,
      sheet: '',
      detail: element,
    ),
  );

  /// The counts of the styles part the model made for a file without one,
  /// while it is not in the package yet; `null` otherwise.
  StylesMark? _createdStyles;

  XlsxSheet get activeSheet {
    if (_sheets.isEmpty) throw StateError('The workbook has no sheet.');
    final int i = workbook.activeTab;
    return _sheets[i < _sheets.length ? i : 0];
  }

  /// The tab index of [sheet]; throws an [ArgumentError] named `sheet`
  /// for a sheet of another workbook.
  int _indexOf(XlsxSheet sheet) {
    final int index = sheetIndexOf(sheet);
    if (index < 0) {
      throw ArgumentError.value(
        sheet.name,
        'sheet',
        'The sheet belongs to another workbook.',
      );
    }
    return index;
  }

  void setActiveSheet(XlsxSheet sheet) {
    _indexOf(sheet);
    if (sheet.visibility != XlsxSheetVisibility.visible) {
      throw StateError(
        'The ${sheet.visibility.name} sheet "${sheet.name}" cannot be the '
        'active sheet.',
      );
    }
    if (identical(sheet, activeSheet)) return;
    log.transaction(() => _activate(sheet));
  }

  /// Makes [target] active inside a transaction: `tabSelected` moves from
  /// the sheet that was active, and `activeTab` is set.
  void _activate(XlsxSheet target) {
    final XlsxSheet old = activeSheet;
    if (!identical(old, target) && sheetIsWorksheet(old)) {
      setSheetTabSelected(old, false);
    }
    if (sheetIsWorksheet(target)) setSheetTabSelected(target, true);
    setActiveTab(log, workbook, _sheets.indexOf(target));
  }

  @override
  void setVisibility(SheetEntry entry, XlsxSheetVisibility value) {
    if (entry.visibility == value) return;
    final bool hiding =
        entry.visibility == XlsxSheetVisibility.visible &&
        value != XlsxSheetVisibility.visible;
    final int index = _sheets.indexWhere(
      (XlsxSheet s) => identical(entryOf(s), entry),
    );
    if (hiding &&
        !_sheets.any(
          (XlsxSheet s) =>
              !identical(entryOf(s), entry) &&
              s.visibility == XlsxSheetVisibility.visible,
        )) {
      throw StateError(
        'The sheet "${entry.name}" is the last visible sheet and cannot be '
        'hidden.',
      );
    }
    log.transaction(() {
      final bool wasActive = identical(activeSheet, _sheets[index]);
      setEntryVisibility(log, entry, value);
      if (wasActive && hiding) {
        _activate(
          _sheets.firstWhere(
            (XlsxSheet s) => s.visibility == XlsxSheetVisibility.visible,
          ),
        );
      }
    });
  }

  XlsxSheet addSheet(String requested, {int? position}) {
    final int count = _sheets.length;
    if (position != null) {
      RangeError.checkValueInInterval(position, 0, count, 'position');
    }
    final CellEncoder encoder = loadTables();
    return warnings.keepOnSuccess(() {
      final SheetNamer namer = SheetNamer(warnings);
      for (final XlsxSheet s in _sheets) {
        namer.reserve(s.name);
      }
      final String name = namer.assign(requested);
      final int number = count + 1;
      final WorksheetSettings settings = WorksheetSettings(sheetNumber: number);
      final WorksheetPart part = WorksheetPart.read(
        XmlPullReader(
          worksheetHeader(settings, hasRows: false) +
              worksheetTrailer(settings, hasRows: false),
        ),
        part: 'worksheets/sheet$number.xml',
        limits: reader.limits,
        warn: (XlsxWarningCode code, String? cell, {String? detail}) {},
      )..bindEncoder(encoder);
      late XlsxSheet sheet;
      log.transaction(() {
        final String folder = workbookName.substring(
          0,
          workbookName.lastIndexOf('/') + 1,
        );
        final String partName = addStoredPart(
          log,
          _package,
          '${folder}worksheets/sheet$number.xml',
          ContentType.worksheet,
          part,
        );
        final String id = addStoredRelationship(
          log,
          _package,
          workbookName,
          type: RelType.worksheet,
          target: partName.startsWith(folder)
              ? partName.substring(folder.length)
              : partName,
        );
        final int at = position ?? count;
        _reorder(() {
          sheet = newSheet(
            this,
            workbook.addSheet(name, id),
            partName,
            part: part,
          );
          _sheets.add(sheet);
          if (at != count) {
            workbook.moveSheet(count, at);
            _sheets.insert(at, _sheets.removeLast());
          }
        });
        if (at != count) _remapIndexes((int i) => i >= at ? i + 1 : i);
        _editSheetTitles(
          <String>[
            for (final XlsxSheet s in _sheets)
              if (!identical(s, sheet)) s.name,
          ],
          <String>[for (final XlsxSheet s in _sheets) s.name],
        );
      });
      return sheet;
    });
  }

  void renameSheet(XlsxSheet sheet, String newName) {
    _indexOf(sheet);
    final String old = sheet.name;
    if (newName == old) return;
    final SheetNamer namer = SheetNamer(WarningCollector());
    for (final XlsxSheet s in _sheets) {
      if (!identical(s, sheet)) namer.reserve(s.name);
    }
    if (namer.assign(newName) != newName) {
      throw ArgumentError.value(
        newName,
        'newName',
        'Not a valid sheet name, or another sheet has it, ignoring case.',
      );
    }
    final List<String> before = <String>[
      for (final XlsxSheet s in _sheets) s.name,
    ];
    warnings.keepOnSuccess(
      () => log.transaction(() {
        references.apply(SheetRename(old, newName), null);
        applyChange(log, _RenameChange(entryOf(sheet), old, newName));
        _editSheetTitles(
          before,
          <String>[for (final XlsxSheet s in _sheets) s.name],
          renamedFrom: old,
          renamedTo: newName,
        );
      }),
    );
  }

  void moveSheet(XlsxSheet sheet, int position) {
    final int from = _indexOf(sheet);
    RangeError.checkValidIndex(position, _sheets, 'position');
    if (from == position) return;
    final List<String> order = <String>[
      for (final XlsxSheet s in _sheets) s.name,
    ];
    final int count = _sheets.length;
    int? moved(int i) {
      if (i >= count) return null;
      if (i == from) return position;
      if (from < position && i > from && i <= position) return i - 1;
      if (position < from && i >= position && i < from) return i + 1;
      return i;
    }

    warnings.keepOnSuccess(
      () => log.transaction(() {
        references.apply(SheetMove(order, from, position), null);
        _reorder(() {
          workbook.moveSheet(from, position);
          _sheets.insert(position, _sheets.removeAt(from));
        });
        _remapIndexes(moved);
        _editSheetTitles(order, <String>[
          for (final XlsxSheet s in _sheets) s.name,
        ]);
        workbook.structureEdits++;
        log.record(StructureEditChange(workbook));
      }),
    );
  }

  /// Makes the sheet titles of `docProps/app.xml` list [after] where they
  /// listed [before] (`AppProperties.withSheetTitles`), recording the
  /// change. The properties load here, inside the edit's transaction, and
  /// the load itself is recorded: a failed or undone edit gives every
  /// properties part its bytes from the file back. A part that cannot be
  /// read keeps its titles.
  void _editSheetTitles(
    List<String> before,
    List<String> after, {
    String? renamedFrom,
    String? renamedTo,
  }) {
    final bool loaded = _properties != null;
    final PropertiesState state;
    try {
      state = propertiesState();
    } on XlsxReadException {
      return;
    }
    if (!loaded) log.record(_PropertiesLoadChange(this, state));
    final PropertyParts parts = state.parts;
    final AppProperties app = parts.app.withSheetTitles(
      before: before,
      after: after,
      prefix: renderSheetPrefix,
      renamedFrom: renamedFrom,
      renamedTo: renamedTo,
    );
    if (identical(app, parts.app)) return;
    applyChange(
      log,
      SetPropertiesChange(
        state,
        parts,
        PropertyParts(parts.core, app, parts.custom),
      ),
    );
  }

  /// Runs [body], which changes the order of the sheets (the workbook
  /// part's `<sheets>` and [_sheets] together), and records the change.
  void _reorder(void Function() body) {
    final List<Object> itemsBefore = workbook.sheetItems();
    final List<XlsxSheet> sheetsBefore = List<XlsxSheet>.of(_sheets);
    try {
      body();
    } catch (_) {
      workbook.restoreSheetItems(itemsBefore);
      _sheets
        ..clear()
        ..addAll(sheetsBefore);
      rethrow;
    }
    log.record(
      _OrderChange(
        this,
        itemsBefore,
        workbook.sheetItems(),
        sheetsBefore,
        List<XlsxSheet>.of(_sheets),
      ),
    );
  }

  /// Gives every tab index the workbook part holds (a name's
  /// `localSheetId`, a view's `activeTab` and `firstSheet`) the index [map]
  /// gives it, recording the changes.
  void _remapIndexes(int? Function(int) map) {
    remapNameScopes(log, workbook, map);
    final XmlNode? before = workbook.bookViews;
    final XmlNode? after = workbook.remappedBookViews(map);
    if (after != null) {
      applyChange(log, SetBookViewsChange(workbook, before, after));
    }
  }

  /// Adds [content] as a part of [contentType] named [name] in the
  /// workbook's folder (or the next free name) with a workbook relationship
  /// of [relType]; returns the part's name and the relationship's id.
  (String, String) _addWorkbookPart(
    String name,
    String contentType,
    String relType,
    PartContent content,
  ) {
    final String folder = workbookName.substring(
      0,
      workbookName.lastIndexOf('/') + 1,
    );
    final String partName = _package.addPart(
      '$folder$name',
      contentType,
      content,
    );
    final String id = _package.addRelationship(
      workbookName,
      type: relType,
      target: partName.startsWith(folder)
          ? partName.substring(folder.length)
          : partName,
    );
    return (partName, id);
  }

  /// The target of the workbook's first relationship of [type] whose part
  /// exists (normalized, no leading `/`), or `null`.
  String? _target(String type) {
    for (final PartRelationship r in reader.relationshipsOf(
      reader.workbookPart,
    )) {
      if (r.type == type && reader.hasPart(r.target)) return r.target;
    }
    return null;
  }

  void checkSavable() {
    if (!created) return;
    if (_sheets.isEmpty) throw StateError(noSheetMessage);
    if (!_sheets.any(
      (XlsxSheet s) => s.visibility == XlsxSheetVisibility.visible,
    )) {
      throw StateError(noVisibleSheetMessage);
    }
  }

  /// Applies the save bookkeeping and writes the package to [zip].
  void writeTo(ZipWriter zip) {
    final bool allLoaded = _sheets.every(
      (XlsxSheet s) => isLoadedSheet(s) || !sheetHasPart(s),
    );
    // Only a changed cell value or formula (spec section 4.4) makes the
    // calculation chain and cached results stale.
    // A row or column edit moves cells, so it does too.
    final bool valueEdited =
        workbook.structureEdits > 0 ||
        _sheets.any((XlsxSheet s) => (cellStoreOf(s)?.valueEdits ?? 0) > 0);
    // A defined name that was defined or removed, or a table that was
    // resized, changes results as a changed cell does, but the chain of
    // cells stays as it was.
    if (valueEdited || workbook.nameEdits > 0 || workbook.tableEdits > 0) {
      final String? chain = valueEdited ? _target(RelType.calcChain) : null;
      if (chain != null) {
        // Only the workbook refers to the calculation chain, so no other
        // relationships part is read or rewritten.
        reader.guardXml(
          chain,
          () => _package.removePart(chain, sources: <String>[workbookName]),
        );
      }
      final bool formulas =
          !allLoaded ||
          _sheets.any((XlsxSheet s) => cellStoreOf(s)?.hasFormulas ?? false);
      if (formulas) workbook.requestFullCalculation();
    }
    final StylesMark? created = _createdStyles;
    final StylesPart? styles = _styles;
    if (created != null && styles != null && styles.mark() != created) {
      _addWorkbookPart(
        'styles.xml',
        ContentType.styles,
        RelType.styles,
        styles,
      );
      _createdStyles = null;
    }
    final SharedStrings? strings = _strings;
    if (strings != null) {
      var references = 0;
      for (final XlsxSheet s in _sheets) {
        final CellStore? store = cellStoreOf(s);
        if (store != null) {
          references += store.countOf(RawCellKind.sharedString);
        }
      }
      if (allLoaded) strings.setCount(references);
      // An undone edit leaves its string in the table, used by no cell.
      if (_stringsName == null && strings.length > 0 && references > 0) {
        _stringsName = _addWorkbookPart(
          'sharedStrings.xml',
          ContentType.sharedStrings,
          RelType.sharedStrings,
          _SharedStringsContent(strings),
        ).$1;
      }
    }
    final PropertiesState? properties = _properties;
    if (properties != null) {
      reader.guardXml(reader.workbookPart, properties.sync);
    }
    reader.guardXml(reader.workbookPart, () => _package.writeTo(zip));
  }
}

/// The package of a workbook as the document properties read it: the
/// workbook's limits and its read exceptions.
final class _XlsxPropertiesSource implements PropertiesSource {
  _XlsxPropertiesSource(this._reader);

  final PackageReader _reader;

  @override
  OpcPackage get package => _reader.package;

  /// A workbook's properties part lists at most as many entries as it may
  /// have sheets.
  @override
  int get maxChildren => _reader.limits.maxSheets;

  @override
  int get maxTextLength => _reader.limits.maxTextLength;

  @override
  T guard<T>(String part, T Function() body) => _reader.guardXml(part, body);

  @override
  XmlPullReader openXml(String part) => _reader.openXml(part);

  @override
  Never limitExceeded(String part, String message) =>
      throw XlsxReadException(XlsxReadFailure.limitExceeded, message);
}
