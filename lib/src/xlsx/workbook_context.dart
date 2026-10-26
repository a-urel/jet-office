/// [WorkbookContext], the workbook-level state a sheet writer shares with
/// its workbook writer, and [PackageContentTypes], the content types the
/// sheets add to the package.
///
/// New in jet_office. Quds' `XlsxSheetBuilder` held its rows and handed them
/// to `XlsxWorkbookBuilder.build`, which serialized everything at the end;
/// here a sheet encodes its cells as they arrive and hands its finished part
/// to the ZIP itself, so it needs the workbook's encoder, styles and ZIP. This
/// class gives it those without exposing the workbook writer's other state.
/// A finished sheet's parts beyond the worksheet (drawings, notes, tables)
/// need content types, which the workbook writes only at `close()`; the
/// sheet records them in [WorkbookContext.contentTypes]. The media parts of
/// pictures are shared across sheets, so the context numbers them
/// ([WorkbookContext.mediaPartFor]), and so are the table ids and the names
/// tables share with defined names ([WorkbookContext.takeTableId],
/// [WorkbookContext.checkNameFree]).
library;

import 'dart:collection';
import 'dart:typed_data';

import '../zip/archive_adapter.dart';
import 'cell_encoder.dart';
import 'image.dart';
import 'shared_strings.dart';
import 'sheet_name.dart';
import 'style_registry.dart';
import 'warnings.dart';
import 'worksheet_parts.dart';

/// What every sheet of one workbook shares: the cell encoder with the
/// shared strings, styles and warnings it records into, the ZIP that
/// receives finished parts, and whether the writer has failed.
///
/// One context belongs to one workbook writer, which creates it; a sheet
/// writer keeps a reference to the context of the writer that added it.
final class WorkbookContext {
  /// Creates the context of a workbook whose parts go to [zip], with empty
  /// shared strings, styles and warnings.
  WorkbookContext(this.zip);

  /// The archive that receives each finished part.
  final ZipWriter zip;

  /// The data problems repaired so far, in first-occurrence order.
  final WarningCollector warnings = WarningCollector();

  /// The workbook's distinct strings, written last as `sharedStrings.xml`.
  final SharedStrings strings = SharedStrings();

  /// The workbook's distinct styles, written last as `styles.xml`.
  final StyleRegistry styles = StyleRegistry();

  /// The content types of the parts the sheets wrote beyond the worksheets,
  /// which `close()` adds to `[Content_Types].xml`.
  final PackageContentTypes contentTypes = PackageContentTypes();

  /// The one cell encoder of the workbook (decision 0002).
  late final CellEncoder encoder = CellEncoder(
    strings: strings,
    styles: styles,
    warnings: warnings,
  );

  /// The first VML id block no sheet has taken yet.
  int _nextVmlBlock = 1;

  /// Takes [count] consecutive VML id blocks and returns the first.
  ///
  /// A sheet's VML drawing numbers its note shapes 1,024 to a block
  /// (`_x0000_s{1024 × block + i + 1}`) and lists its blocks in
  /// `o:idmap`; Excel needs both unique across the workbook. Blocks are
  /// handed out from 1 in the order sheets finish, so they follow the
  /// creation order. Throws [ArgumentError] for a [count] below 1.
  int takeVmlBlocks(int count) {
    if (count < 1) {
      throw ArgumentError.value(count, 'count', 'Must be at least 1.');
    }
    final int first = _nextVmlBlock;
    _nextVmlBlock += count;
    return first;
  }

  /// The media part each image's bytes went to, keyed by the identity of
  /// the `Uint8List` (Decision 5 of the M4 plan): nothing is hashed, and
  /// the bytes are not kept alive by the key.
  final Expando<String> _mediaParts = Expando<String>('media part');

  /// The number of media parts handed out so far.
  int _mediaCount = 0;

  /// The media part of [image]'s bytes, `xl/media/image{k}.{extension}`,
  /// and whether this call created it.
  ///
  /// The first call for a `Uint8List` takes the workbook's next media
  /// number (from 1, in first-use order) and returns `isNew` true: the
  /// caller writes the bytes to that part. Later calls for the same list,
  /// through any [XlsxImage] holding it, return the same part and false.
  /// Equal bytes in another list get a part of their own. Sheets call this
  /// when they finish, so the numbers follow the order sheets finish in.
  ///
  /// Throws [ArgumentError] named `image` when the bytes of a new image
  /// are neither a PNG nor a JPEG; no number is taken then.
  (String partName, bool isNew) mediaPartFor(XlsxImage image) {
    final Uint8List bytes = image.bytes;
    final String? known = _mediaParts[bytes];
    if (known != null) return (known, false);
    final XlsxImageFormat? format = image.format;
    if (format == null) {
      throw ArgumentError.value(
        image,
        'image',
        'Only a PNG or a JPEG can be a media part.',
      );
    }
    final String part = mediaPartName(++_mediaCount, format.extension);
    _mediaParts[bytes] = part;
    return (part, true);
  }

  /// The number of table ids handed out so far.
  int _tableCount = 0;

  /// Takes the workbook's next table id, from 1, in the order tables are
  /// registered; it also numbers the table's part, `xl/tables/table{id}.xml`.
  /// Call it only once the table is checked, so a table that throws takes
  /// no id.
  int takeTableId() => ++_tableCount;

  /// The names of the tables, keyed by [sheetNameKey], with their spelling.
  final Map<String, String> _tableNames = <String, String>{};

  /// The names defined in any scope, keyed by [sheetNameKey], with the
  /// first spelling.
  final Map<String, String> _definedNames = <String, String>{};

  /// Throws [ArgumentError] named [field] when a table or a defined name of
  /// any scope already has [name], ignoring case as [sheetNameKey] does.
  ///
  /// A table's name lives in the same namespace as the defined names of
  /// every scope: a formula refers to `Sales[Amount]` from any sheet.
  void checkNameFree(String name, String field) {
    checkNotTableName(name, field);
    final String? defined = _definedNames[sheetNameKey(name)];
    if (defined != null) {
      throw ArgumentError.value(
        name,
        field,
        'The name "$name" is already a defined name, "$defined"; table '
        'names and defined names are compared ignoring case.',
      );
    }
  }

  /// Throws [ArgumentError] named [field] when a table already has [name],
  /// ignoring case. A defined name checks this one: the same spelling may
  /// be defined in two scopes, but never next to a table.
  void checkNotTableName(String name, String field) {
    final String? table = _tableNames[sheetNameKey(name)];
    if (table != null) {
      throw ArgumentError.value(
        name,
        field,
        'The name "$name" is already the name of the table "$table"; table '
        'names and defined names are compared ignoring case.',
      );
    }
  }

  /// Records that a table is named [name]; call it after [checkNameFree].
  void reserveTableName(String name) {
    _tableNames[sheetNameKey(name)] = name;
  }

  /// Records that a name [name] is defined in some scope; call it after
  /// [checkNotTableName]. A repeat in another scope changes nothing.
  void reserveDefinedName(String name) {
    _definedNames.putIfAbsent(sheetNameKey(name), () => name);
  }

  /// What the ZIP work threw, once it has failed; the writer is then dead.
  Object? _failure;

  /// Records that handing bytes to the ZIP threw [error]; every later
  /// [checkNotFailed] throws.
  ///
  /// Called only by the workbook writer's ZIP work (`_zipWork` in
  /// `xlsx_writer.dart`). Sheet code reaches the context too, but must not
  /// call this: an error it throws on its own leaves the writer usable.
  void recordFailure(Object error) {
    _failure = error;
  }

  /// Throws a [StateError] naming the earlier error once the writer has
  /// failed (see [recordFailure]).
  void checkNotFailed() {
    final Object? failure = _failure;
    if (failure != null) {
      throw StateError(
        'The writer failed earlier and cannot continue: $failure',
      );
    }
  }
}

/// The default and override content types the sheets of one workbook
/// register for the parts they write, such as `png` images or a table part.
///
/// Both are kept in the order first registered; `writeContentTypes` writes
/// them with the workbook's own. Nothing is checked here: the values come
/// from the writer's own constants, not from the caller.
final class PackageContentTypes {
  final Map<String, String> _defaults = <String, String>{};
  final Map<String, String> _overrides = <String, String>{};

  /// Declares [type] for every part whose name ends in [extension] (without
  /// the dot). The first registration wins: a later one for the same
  /// extension changes nothing, so each sheet may register what it uses.
  void addDefault(String extension, String type) {
    _defaults.putIfAbsent(extension, () => type);
  }

  /// Declares [type] for the single part named [partName], an absolute name
  /// such as `/xl/tables/table1.xml`. The first registration wins, as with
  /// [addDefault].
  void addOverride(String partName, String type) {
    _overrides.putIfAbsent(partName, () => type);
  }

  /// The extensions and their types, in first-registration order; a view
  /// that cannot be changed.
  Map<String, String> get defaults => UnmodifiableMapView(_defaults);

  /// The part names and their types, in first-registration order; a view
  /// that cannot be changed.
  Map<String, String> get overrides => UnmodifiableMapView(_overrides);
}
