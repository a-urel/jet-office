import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/xlsx/sheet_name.dart';
import 'package:jet_office/src/xlsx/warnings.dart' show WarningCollector;
import 'package:test/test.dart';

/// The warnings of a one-cell workbook whose cell holds [text].
List<XlsxWarning> _warningsFor(String text) {
  final XlsxWriter book = XlsxWriter();
  book.addSheet('S').row(<Object?>[text]);
  return book.close().warnings;
}

void main() {
  // Rows, columns and cell formats are tested where they are enforced:
  // `xlsx_writer_test.dart` ("row and column limits") and
  // `style_registry_test.dart` ("too many cell formats").
  group('XlsxLimitError', () {
    test('keeps the limit name and the maximum', () {
      final XlsxLimitError e = XlsxLimitError('rows', 1048576);
      expect(e.limit, 'rows');
      expect(e.max, 1048576);
    });

    test('says which limit was exceeded', () {
      expect(
        XlsxLimitError('rows', 1048576).toString(),
        "XlsxLimitError: rows exceeds Excel's maximum of 1048576.",
      );
    });

    test('is the error the writer raises for too many columns', () {
      final XlsxSheetWriter s = XlsxWriter().addSheet('S');
      expect(
        () => s.row(List<Object?>.filled(XlsxLimits.maxColumns + 1, 1)),
        throwsA(
          isA<XlsxLimitError>()
              .having((XlsxLimitError e) => e.limit, 'limit', 'columns')
              .having(
                (XlsxLimitError e) => e.max,
                'max',
                XlsxLimits.maxColumns,
              ),
        ),
      );
    });
  });

  group('cell text length', () {
    test('a text of the limit is written as given', () {
      expect(_warningsFor('a' * XlsxLimits.maxCellTextLength), isEmpty);
    });

    test('one unit more is cut, with a textTruncated warning', () {
      final List<XlsxWarning> warnings = _warningsFor(
        'a' * (XlsxLimits.maxCellTextLength + 1),
      );
      expect(warnings, hasLength(1));
      expect(warnings.single.code, XlsxWarningCode.textTruncated);
    });
  });

  group('sheet name length', () {
    test('a name of the limit is kept', () {
      final WarningCollector w = WarningCollector();
      final String name = 'n' * XlsxLimits.maxSheetNameLength;
      expect(SheetNamer(w).assign(name), name);
      expect(w.warnings, isEmpty);
    });

    test('one unit more is cut, with a sheetNameChanged warning', () {
      final WarningCollector w = WarningCollector();
      final String name = 'n' * (XlsxLimits.maxSheetNameLength + 1);
      expect(SheetNamer(w).assign(name), 'n' * XlsxLimits.maxSheetNameLength);
      expect(w.warnings.single.code, XlsxWarningCode.sheetNameChanged);
    });
  });
}
