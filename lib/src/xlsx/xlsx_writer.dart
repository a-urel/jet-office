/// The streaming XLSX writers: [XlsxWriter] (in memory) and
/// [XlsxStreamWriter] (to a sink).
///
/// Ported from quds_office_engine `lib/src/builders/xlsx_io.dart` at commit 15c5d29.
/// Ported: `XlsxWorkbookBuilder.addSheet` and `build`. What changed: Quds
/// kept every sheet as a list of rows and serialized the whole workbook in
/// `build`; here one sheet is open at a time, [XlsxWriterBase.addSheet]
/// finishes the open one, whose part goes straight to the ZIP (see
/// `sheet_writer.dart`), and `close()` writes only the workbook-level parts.
/// Tab order is independent of creation order, the active tab is chosen by
/// the caller, a workbook without sheets is an error instead of silently
/// gaining `Sheet1`, and data problems are returned as warnings. The
/// workbook gets the hidden `_xlnm._FilterDatabase` name of each sheet's
/// auto filter, which Quds did not write, and the defined names, print areas
/// and print titles (see `workbook_parts.dart`). Charts and pictures are not
/// ported yet.
library;

import 'dart:typed_data';

import '../xml/utf8_buffer.dart';
import '../xml/xml_writer.dart';
import '../zip/archive_adapter.dart';
import 'defined_name.dart';
import 'properties.dart';
import 'sheet_name.dart';
import 'sheet_protection.dart';
import 'sheet_view.dart';
import 'sheet_writer.dart';
import 'warnings.dart';
import 'workbook_context.dart';
import 'workbook_parts.dart';

/// Writes a part with [write] and returns its UTF-8 bytes.
Uint8List _render(void Function(XmlWriter w) write) {
  final Utf8Buffer buffer = Utf8Buffer();
  write(XmlWriter(buffer));
  return buffer.takeBytes();
}

/// What the two XLSX writers share: adding sheets, ordering their tabs and
/// choosing the active one.
///
/// Use [XlsxWriter] to get the file as bytes, or [XlsxStreamWriter] to send
/// it to a sink as it is written. Both are synchronous: cells are encoded in
/// [XlsxSheetWriter.row], and `close()` writes the workbook-level parts and
/// finishes the ZIP.
///
/// One sheet is open at a time. [addSheet] finishes the open sheet, whose
/// part is then compressed and handed to the ZIP, so memory holds one sheet's
/// XML plus the workbook's distinct strings and styles, not the whole file.
/// The same calls always produce the same bytes.
sealed class XlsxWriterBase {
  XlsxWriterBase._(XlsxProperties properties, ZipWriter Function() createZip)
    : _coreXml = _render((XmlWriter w) => writeCoreProperties(w, properties)),
      _appXml = _render((XmlWriter w) => writeAppProperties(w, properties)),
      _context = WorkbookContext(createZip());

  final Uint8List _coreXml;
  final Uint8List _appXml;

  /// The encoder, styles, ZIP and failure state every sheet shares.
  final WorkbookContext _context;
  late final SheetNamer _namer = SheetNamer(_context.warnings);

  /// The sheets in tab order.
  final List<WorksheetWriter> _tabs = <WorksheetWriter>[];

  /// The workbook-scope defined names, in definition order.
  final List<XlsxDefinedName> _names = <XlsxDefinedName>[];
  XlsxWorkbookProtection? _protection;
  WorksheetWriter? _open;
  WorksheetWriter? _active;
  bool _closed = false;

  /// Finishes the open sheet and starts a new one named [name].
  ///
  /// The name is made valid and unique as Excel requires; a changed name is
  /// reported as a warning and is the one [XlsxSheetWriter.name] returns.
  ///
  /// The sheet is placed at index [position] of the tab order, `0` being the
  /// first tab; by default it goes last. Tab order is independent of the
  /// order sheets are written in, so a summary can be written last and still
  /// come first.
  ///
  /// A sheet that is [XlsxSheetVisibility.hidden] or
  /// [XlsxSheetVisibility.veryHidden] gets no visible tab but takes rows as
  /// any other; a workbook needs at least one visible sheet by `close()`.
  ///
  /// Throws [RangeError] when [position] is outside `0` to the number of
  /// sheets so far, and [StateError] after `close()` or after a failure.
  /// Rethrows what the sink throws while the open sheet is finished; the
  /// writer has then failed (see [XlsxStreamWriter]).
  XlsxSheetWriter addSheet(
    String name, {
    int? position,
    XlsxSheetVisibility visibility = XlsxSheetVisibility.visible,
  }) {
    _checkOpen();
    if (position != null) {
      RangeError.checkValueInInterval(position, 0, _tabs.length, 'position');
    }
    final WorksheetWriter? open = _open;
    if (open != null) _zipWork(open.finish);
    final WorksheetWriter sheet = WorksheetWriter(
      _context,
      _namer.assign(name),
      _tabs.length + 1,
      visibility,
    );
    _tabs.insert(position ?? _tabs.length, sheet);
    _open = sheet;
    return sheet;
  }

  /// Makes [sheet] the tab Excel shows when the file is opened.
  ///
  /// Without a call, the first visible tab in tab order is active. The tab
  /// index is resolved at `close()`, so later inserts before [sheet] keep it
  /// active.
  ///
  /// Throws [ArgumentError] when [sheet] was not added to this writer or is
  /// hidden (a hidden sheet cannot be the one Excel opens on), and
  /// [StateError] after `close()` or after a failure.
  void setActiveSheet(XlsxSheetWriter sheet) {
    _checkOpen();
    if (sheet is! WorksheetWriter || !identical(sheet.context, _context)) {
      throw ArgumentError.value(
        sheet.name,
        'sheet',
        'Not a sheet of this writer.',
      );
    }
    if (sheet.visibility != XlsxSheetVisibility.visible) {
      throw ArgumentError.value(
        sheet.name,
        'sheet',
        'A ${sheet.visibility.name} sheet cannot be the active sheet.',
      );
    }
    _active = sheet;
  }

  /// Defines [name] for the whole workbook.
  ///
  /// Names are written in the order made, before the names of any sheet; use
  /// [XlsxSheetWriter.defineName] for a name that belongs to one sheet. A
  /// workbook name is allowed until `close()`. The same spelling may also be
  /// defined on a sheet, where it hides this one.
  ///
  /// Throws [ArgumentError] for an invalid name, comment or formula (see
  /// [XlsxDefinedName]) or a name already defined in the workbook scope,
  /// ignoring case; the earlier names stay then. Throws [StateError] after
  /// `close()` or after a failure.
  void defineName(XlsxDefinedName name) {
    _checkOpen();
    _names.add(checkDefinedName(name, _names));
  }

  /// Protects the workbook, replacing an earlier call: [protection] says
  /// what is locked and gives the password that lifts it.
  ///
  /// Allowed until `close()`. It is not security: the password hash is weak
  /// and nothing is encrypted.
  ///
  /// Throws [ArgumentError] naming `password` when it is not 1 to 15
  /// characters from U+0020 to U+007E (the earlier protection stays then),
  /// and [StateError] after `close()` or after a failure.
  void protectWorkbook(XlsxWorkbookProtection protection) {
    _checkOpen();
    checkProtectionPassword(protection.password);
    _protection = protection;
  }

  void _checkOpen() {
    _context.checkNotFailed();
    if (_closed) {
      throw StateError('The XLSX writer is already closed.');
    }
  }

  /// Runs [work], which hands bytes to the ZIP; if it throws, the writer
  /// has failed and every later call throws a [StateError].
  T _zipWork<T>(T Function() work) {
    try {
      return work();
    } on Object catch (error) {
      _context.recordFailure(error);
      rethrow;
    }
  }

  /// Finishes the open sheet, writes the workbook-level parts and finishes
  /// the ZIP, returning its bytes in memory mode.
  Uint8List? _close() {
    _checkOpen();
    if (_tabs.isEmpty) {
      throw StateError('A workbook needs at least one sheet; add one first.');
    }
    if (_activeTab() < 0) {
      throw StateError(
        'A workbook needs at least one visible sheet; every sheet is hidden. '
        'Add a visible sheet first.',
      );
    }
    return _zipWork(() {
      _open?.finish();
      _open = null;
      final Uint8List? bytes = _writeWorkbookParts();
      _closed = true;
      return bytes;
    });
  }

  /// The tab index Excel opens on: the sheet chosen with [setActiveSheet],
  /// else the first visible tab; -1 when no tab is visible.
  int _activeTab() {
    final WorksheetWriter? chosen = _active;
    if (chosen != null) return _tabs.indexOf(chosen);
    return _tabs.indexWhere(
      (WorksheetWriter s) => s.visibility == XlsxSheetVisibility.visible,
    );
  }

  /// Writes the workbook-level parts and finishes the ZIP.
  Uint8List? _writeWorkbookParts() {
    final int sheetCount = _tabs.length;
    final ZipWriter zip = _context.zip;
    zip
      ..add('xl/sharedStrings.xml', _render(_context.strings.writeXml))
      ..add('xl/styles.xml', _render(_context.styles.writeStylesXml))
      ..add(
        'xl/workbook.xml',
        _render(
          (XmlWriter w) => writeWorkbook(
            w,
            tabs: <WorkbookSheet>[
              for (final WorksheetWriter s in _tabs)
                (
                  name: s.name,
                  number: s.number,
                  visibility: s.visibility,
                  autoFilter: s.autoFilterRange,
                  names: s.sheetNames,
                ),
            ],
            workbookNames: _names,
            protection: _protection,
            activeTab: _activeTab(),
            fullCalcOnLoad: _context.encoder.wroteFormula,
          ),
        ),
      )
      ..add(
        'xl/_rels/workbook.xml.rels',
        _render((XmlWriter w) => writeWorkbookRelationships(w, sheetCount)),
      )
      ..add('docProps/core.xml', _coreXml)
      ..add('docProps/app.xml', _appXml)
      ..add('_rels/.rels', _render(writeRootRelationships))
      ..add(
        '[Content_Types].xml',
        _render((XmlWriter w) => writeContentTypes(w, sheetCount)),
      );
    return zip.close();
  }
}

/// Writes an XLSX file in memory and returns it from [close].
///
/// ```dart
/// final XlsxWriter book = XlsxWriter();
/// final XlsxSheetWriter sheet = book.addSheet('Accounts');
/// sheet.row(<Object?>['Code', 'Balance']);
/// sheet.row(<Object?>['A-1', XlsxDecimal('1234.50')]);
/// final XlsxResult out = book.close();
/// ```
final class XlsxWriter extends XlsxWriterBase {
  /// Creates a writer whose document properties are [properties].
  ///
  /// Throws [ArgumentError] when a property holds characters XML forbids.
  XlsxWriter({XlsxProperties properties = const XlsxProperties()})
    : super._(properties, ZipWriter.new);

  /// Finishes the open sheet and the file, and returns the file with the
  /// warnings about data that had to be changed.
  ///
  /// Throws [StateError] when no sheet was added or when called twice.
  XlsxResult close() => XlsxResult._(_close()!, _context.warnings.warnings);
}

/// Writes an XLSX file to a sink as it goes.
///
/// Each finished sheet is compressed, and the compressed bytes reach the sink
/// in chunks of about 64 KiB as parts finish; the writer keeps none of the
/// bytes it has sent. The bytes that reach the sink are identical to what
/// [XlsxWriter] returns for the same calls.
///
/// When the sink throws, the call that was writing to it (`addSheet` or
/// `close()`) rethrows the error, the sink is closed and the writer has
/// failed: every later call throws a [StateError]. The file in the sink is
/// then incomplete and should be discarded.
final class XlsxStreamWriter extends XlsxWriterBase {
  /// Creates a writer that sends the file to [sink], with the document
  /// properties [properties].
  ///
  /// Throws [ArgumentError] when a property holds characters XML forbids;
  /// nothing has been sent to [sink] then.
  XlsxStreamWriter(
    Sink<List<int>> sink, {
    XlsxProperties properties = const XlsxProperties(),
  }) : super._(properties, () => ZipWriter(sink: sink));

  /// Finishes the open sheet and the file, closes the sink and returns the
  /// warnings about data that had to be changed.
  ///
  /// Throws [StateError] when no sheet was added (the sink then stays open),
  /// when called twice or after a failure. Rethrows what the sink throws.
  List<XlsxWarning> close() {
    _close();
    return _context.warnings.warnings;
  }
}

/// A finished XLSX file and what the writer had to change to produce it.
final class XlsxResult {
  XlsxResult._(this.bytes, this.warnings);

  /// The XLSX file.
  final Uint8List bytes;

  /// Data problems the writer repaired, in first-occurrence order. Empty
  /// when the data was written exactly as given. Unmodifiable, and final once
  /// `close()` has returned.
  final List<XlsxWarning> warnings;
}
