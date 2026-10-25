import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

import '../support/read_xlsx.dart';
import '../support/xlsx_checker.dart';

const String _sheet1 = 'xl/worksheets/sheet1.xml';

/// The `dataValidations` element of sheet 1 of a workbook in which [setup]
/// adds validations to the sheet `S`, or '' when there is none.
String _validations(void Function(XlsxSheetWriter sheet) setup) {
  final XlsxWriter book = XlsxWriter();
  final XlsxSheetWriter sheet = book.addSheet('S')..row(<Object?>['x']);
  setup(sheet);
  final String xml = readXlsx(book.close().bytes)[_sheet1]!;
  final RegExpMatch? m = RegExp(
    '<dataValidations.*</dataValidations>',
  ).firstMatch(xml);
  return m?.group(0) ?? '';
}

/// The one `dataValidation` of [v] as written.
String _one(XlsxDataValidation v) {
  final String xml = _validations((XlsxSheetWriter s) => s.dataValidation(v));
  expect(xml, startsWith('<dataValidations count="1">'));
  return xml.substring(
    '<dataValidations count="1">'.length,
    xml.length - '</dataValidations>'.length,
  );
}

final XlsxRange _a1 = XlsxRange.parse('A1');
final XlsxRange _b2 = XlsxRange.parse('B2:B5');

void main() {
  group('list', () {
    test('quotes the items and doubles a quote inside one', () {
      expect(
        _one(
          XlsxDataValidation.list(<XlsxRange>[_a1], <String>['a', 'say "hi"']),
        ),
        '<dataValidation type="list" allowBlank="1" showInputMessage="1" '
        'showErrorMessage="1" sqref="A1">'
        '<formula1>"a,say ""hi"""</formula1></dataValidation>',
      );
    });
    test('an item with a comma throws', () {
      expect(
        () => XlsxDataValidation.list(<XlsxRange>[_a1], <String>['a,b']),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => e.name,
            'name',
            'items',
          ),
        ),
      );
    });
    test('255 units between the quotes are allowed, 256 throw', () {
      final String ok = 'x' * 255;
      expect(
        _one(XlsxDataValidation.list(<XlsxRange>[_a1], <String>[ok])),
        contains('<formula1>"$ok"</formula1>'),
      );
      expect(
        () => _validations(
          (XlsxSheetWriter s) => s.dataValidation(
            XlsxDataValidation.list(<XlsxRange>[_a1], <String>['x' * 256]),
          ),
        ),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => e.toString(),
            'message',
            contains('listFrom'),
          ),
        ),
      );
    });
    test('the limit counts the doubled quotes and the commas', () {
      // 127 + 1 + 127 = 255; with a doubled quote it is 256.
      final String a = 'x' * 127;
      expect(
        _one(XlsxDataValidation.list(<XlsxRange>[_a1], <String>[a, a])),
        contains('"$a,$a"'),
      );
      expect(
        () => _validations(
          (XlsxSheetWriter s) => s.dataValidation(
            XlsxDataValidation.list(<XlsxRange>[_a1], <String>[a, '$a"']),
          ),
        ),
        throwsArgumentError,
      );
    });
    test('an empty list throws', () {
      expect(
        () => _validations(
          (XlsxSheetWriter s) => s.dataValidation(
            XlsxDataValidation.list(<XlsxRange>[_a1], <String>[]),
          ),
        ),
        throwsArgumentError,
      );
    });
    test('items are escaped as formula text', () {
      expect(
        _one(XlsxDataValidation.list(<XlsxRange>[_a1], <String>['R&D', '<b>'])),
        contains('<formula1>"R&amp;D,&lt;b&gt;"</formula1>'),
      );
    });
    test('listFrom writes the formula without its equals sign', () {
      expect(
        _one(XlsxDataValidation.listFrom(<XlsxRange>[_a1], r'=$D$1:$D$9')),
        contains(r'<formula1>$D$1:$D$9</formula1>'),
      );
    });
    test('showDropDownArrow false writes showDropDown="1"', () {
      expect(
        _one(
          XlsxDataValidation.listFrom(
            <XlsxRange>[_a1],
            'Names',
            showDropDownArrow: false,
          ),
        ),
        startsWith(
          '<dataValidation type="list" allowBlank="1" '
          'showDropDown="1" showInputMessage="1"',
        ),
      );
    });
  });

  group('comparing types', () {
    test('whole between writes both formulas and no operator', () {
      expect(
        _one(
          XlsxDataValidation.whole(
            <XlsxRange>[_a1],
            XlsxComparison.between,
            1,
            b: 10,
          ),
        ),
        '<dataValidation type="whole" allowBlank="1" showInputMessage="1" '
        'showErrorMessage="1" sqref="A1">'
        '<formula1>1</formula1><formula2>10</formula2></dataValidation>',
      );
    });
    test('whole between without b throws', () {
      expect(
        () => _validations(
          (XlsxSheetWriter s) => s.dataValidation(
            XlsxDataValidation.whole(
              <XlsxRange>[_a1],
              XlsxComparison.between,
              1,
            ),
          ),
        ),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => e.name,
            'name',
            'formula2',
          ),
        ),
      );
    });
    test('notBetween without b throws', () {
      expect(
        () => _validations(
          (XlsxSheetWriter s) => s.dataValidation(
            XlsxDataValidation.textLength(
              <XlsxRange>[_a1],
              XlsxComparison.notBetween,
              1,
            ),
          ),
        ),
        throwsArgumentError,
      );
    });
    test('a second value with another comparison throws', () {
      expect(
        () => _validations(
          (XlsxSheetWriter s) => s.dataValidation(
            XlsxDataValidation.whole(
              <XlsxRange>[_a1],
              XlsxComparison.greaterThan,
              1,
              b: 2,
            ),
          ),
        ),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => e.name,
            'name',
            'formula2',
          ),
        ),
      );
    });
    test('every comparison writes its own name as the operator', () {
      for (final XlsxComparison c in XlsxComparison.values) {
        final bool two =
            c == XlsxComparison.between || c == XlsxComparison.notBetween;
        final String xml = _one(
          XlsxDataValidation.whole(<XlsxRange>[_a1], c, 1, b: two ? 2 : null),
        );
        if (c == XlsxComparison.between) {
          expect(xml, isNot(contains('operator')));
        } else {
          expect(xml, contains(' operator="${c.name}" '));
        }
        expect(xml.contains('<formula2>'), two);
      }
    });
    test('decimal writes the number', () {
      expect(
        _one(
          XlsxDataValidation.decimal(
            <XlsxRange>[_a1],
            XlsxComparison.greaterThan,
            0,
          ),
        ),
        contains('operator="greaterThan"'),
      );
      expect(
        _one(
          XlsxDataValidation.decimal(
            <XlsxRange>[_a1],
            XlsxComparison.lessThan,
            2.5,
          ),
        ),
        contains('<formula1>2.5</formula1>'),
      );
    });
    test('a non-finite decimal throws at registration', () {
      for (final double v in <double>[
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        final XlsxDataValidation validation = XlsxDataValidation.decimal(
          <XlsxRange>[_a1],
          XlsxComparison.equal,
          v,
        );
        expect(
          () =>
              _validations((XlsxSheetWriter s) => s.dataValidation(validation)),
          throwsArgumentError,
        );
      }
    });
    test('date writes the serial', () {
      final String xml = _one(
        XlsxDataValidation.date(
          <XlsxRange>[_a1],
          XlsxComparison.greaterThan,
          const XlsxDate(2026, 10, 24),
        ),
      );
      expect(xml, contains('type="date"'));
      expect(xml, contains('operator="greaterThan"'));
      expect(xml, contains('<formula1>46319</formula1>'));
    });
    test('date between writes two serials', () {
      expect(
        _one(
          XlsxDataValidation.date(
            <XlsxRange>[_a1],
            XlsxComparison.between,
            const XlsxDate(2026, 10, 24),
            b: const XlsxDate(2026, 10, 25),
          ),
        ),
        contains('<formula1>46319</formula1><formula2>46320</formula2>'),
      );
    });
    test('time writes the fraction of a day', () {
      final String xml = _one(
        XlsxDataValidation.time(
          <XlsxRange>[_a1],
          XlsxComparison.lessThan,
          const Duration(hours: 12),
        ),
      );
      expect(xml, contains('type="time"'));
      expect(xml, contains('operator="lessThan"'));
      expect(xml, contains('<formula1>0.5</formula1>'));
    });
    test('textLength writes the length', () {
      expect(
        _one(
          XlsxDataValidation.textLength(
            <XlsxRange>[_a1],
            XlsxComparison.lessThanOrEqual,
            5,
          ),
        ),
        allOf(
          contains('type="textLength"'),
          contains('operator="lessThanOrEqual"'),
          contains('<formula1>5</formula1>'),
        ),
      );
    });
    test('a negative text length throws', () {
      expect(
        () => _validations(
          (XlsxSheetWriter s) => s.dataValidation(
            XlsxDataValidation.textLength(
              <XlsxRange>[_a1],
              XlsxComparison.equal,
              -1,
            ),
          ),
        ),
        throwsArgumentError,
      );
    });
  });

  group('custom and any', () {
    test('custom writes the formula and ignores the comparison', () {
      expect(
        _one(
          XlsxDataValidation.custom(
            <XlsxRange>[_a1],
            'ISEVEN(B9)',
            errorStyle: XlsxValidationErrorStyle.warning,
          ),
        ),
        '<dataValidation type="custom" errorStyle="warning" allowBlank="1" '
        'showInputMessage="1" showErrorMessage="1" sqref="A1">'
        '<formula1>ISEVEN(B9)</formula1></dataValidation>',
      );
    });
    test('errorStyle information is written, stop is not', () {
      expect(
        _one(
          XlsxDataValidation.custom(
            <XlsxRange>[_a1],
            'TRUE',
            errorStyle: XlsxValidationErrorStyle.information,
          ),
        ),
        contains('errorStyle="information"'),
      );
      expect(
        _one(XlsxDataValidation.custom(<XlsxRange>[_a1], 'TRUE')),
        isNot(contains('errorStyle')),
      );
    });
    test('an empty formula throws', () {
      expect(
        () => _validations(
          (XlsxSheetWriter s) => s.dataValidation(
            XlsxDataValidation.custom(<XlsxRange>[_a1], '='),
          ),
        ),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => e.name,
            'name',
            'formula1',
          ),
        ),
      );
    });
    test('any writes no type and no formula', () {
      expect(
        _one(
          XlsxDataValidation.any(
            <XlsxRange>[_a1],
            promptTitle: 'Note',
            prompt: 'Optional',
          ),
        ),
        '<dataValidation allowBlank="1" showInputMessage="1" '
        'showErrorMessage="1" promptTitle="Note" prompt="Optional" '
        'sqref="A1"/>',
      );
    });
  });

  group('flags and messages', () {
    test('flags that are off are not written', () {
      final String xml = _one(
        XlsxDataValidation.custom(
          <XlsxRange>[_a1],
          'TRUE',
          allowBlank: false,
          showInputMessage: false,
          showErrorMessage: false,
        ),
      );
      expect(xml, startsWith('<dataValidation type="custom" sqref="A1">'));
    });
    test('titles and messages are written in schema order, escaped', () {
      expect(
        _one(
          XlsxDataValidation.custom(
            <XlsxRange>[_a1],
            'TRUE',
            errorTitle: 'A&B',
            error: 'say "no"\n_x0041_',
            promptTitle: 'P',
            prompt: 'q',
          ),
        ),
        contains(
          'errorTitle="A&amp;B" error="say &quot;no&quot;&#10;_x005F_x0041_" '
          'promptTitle="P" prompt="q" sqref="A1"',
        ),
      );
    });
    test('a title of 32 units is allowed, 33 throw', () {
      expect(
        _one(
          XlsxDataValidation.custom(
            <XlsxRange>[_a1],
            'TRUE',
            errorTitle: 'e' * 32,
            promptTitle: 'p' * 32,
          ),
        ),
        contains('errorTitle="${'e' * 32}"'),
      );
      for (final String field in <String>['errorTitle', 'promptTitle']) {
        final XlsxDataValidation v = XlsxDataValidation.custom(
          <XlsxRange>[_a1],
          'TRUE',
          errorTitle: field == 'errorTitle' ? 'x' * 33 : null,
          promptTitle: field == 'promptTitle' ? 'x' * 33 : null,
        );
        expect(
          () => _validations((XlsxSheetWriter s) => s.dataValidation(v)),
          throwsA(
            isA<ArgumentError>().having(
              (ArgumentError e) => e.name,
              'name',
              field,
            ),
          ),
        );
      }
    });
    test('a message of 255 units is allowed, 256 throw', () {
      expect(
        _one(
          XlsxDataValidation.custom(
            <XlsxRange>[_a1],
            'TRUE',
            error: 'e' * 255,
            prompt: 'p' * 255,
          ),
        ),
        contains('error="${'e' * 255}"'),
      );
      for (final String field in <String>['error', 'prompt']) {
        final XlsxDataValidation v = XlsxDataValidation.custom(
          <XlsxRange>[_a1],
          'TRUE',
          error: field == 'error' ? 'x' * 256 : null,
          prompt: field == 'prompt' ? 'x' * 256 : null,
        );
        expect(
          () => _validations((XlsxSheetWriter s) => s.dataValidation(v)),
          throwsA(
            isA<ArgumentError>().having(
              (ArgumentError e) => e.name,
              'name',
              field,
            ),
          ),
        );
      }
    });
    test('a character XML forbids in a message throws', () {
      expect(
        () => _validations(
          (XlsxSheetWriter s) => s.dataValidation(
            XlsxDataValidation.custom(
              <XlsxRange>[_a1],
              'TRUE',
              error: 'a\u0001b',
            ),
          ),
        ),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => e.name,
            'name',
            'error',
          ),
        ),
      );
    });
    test('limits are published', () {
      expect(XlsxLimits.maxValidationTitleLength, 32);
      expect(XlsxLimits.maxValidationMessageLength, 255);
      expect(XlsxLimits.maxValidationListLength, 255);
    });
  });

  group('ranges', () {
    test('several ranges are one space-separated sqref', () {
      expect(
        _one(XlsxDataValidation.custom(<XlsxRange>[_a1, _b2], 'TRUE')),
        contains('sqref="A1 B2:B5"'),
      );
    });
    test('no ranges, or a range outside the sheet, throws', () {
      expect(
        () => _validations(
          (XlsxSheetWriter s) =>
              s.dataValidation(XlsxDataValidation.custom(<XlsxRange>[], 'T')),
        ),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => e.name,
            'name',
            'ranges',
          ),
        ),
      );
      expect(
        () => _validations(
          (XlsxSheetWriter s) => s.dataValidation(
            XlsxDataValidation.custom(<XlsxRange>[
              const XlsxRange(0, 0, 0, 16384),
            ], 'T'),
          ),
        ),
        throwsArgumentError,
      );
    });
    test('validations are written in the order added, counted', () {
      final String xml = _validations((XlsxSheetWriter s) {
        s.dataValidation(XlsxDataValidation.custom(<XlsxRange>[_b2], 'TRUE'));
        s.dataValidation(XlsxDataValidation.custom(<XlsxRange>[_a1], 'FALSE'));
      });
      expect(xml, startsWith('<dataValidations count="2">'));
      expect(xml.indexOf('sqref="B2:B5"'), lessThan(xml.indexOf('sqref="A1"')));
    });
    test('a validation overlapping an earlier one throws; the first stays', () {
      late final String xml;
      Object? error;
      xml = _validations((XlsxSheetWriter s) {
        s.dataValidation(XlsxDataValidation.custom(<XlsxRange>[_b2], 'TRUE'));
        try {
          s.dataValidation(
            XlsxDataValidation.custom(<XlsxRange>[
              _a1,
              XlsxRange.parse('B5:C6'),
            ], 'FALSE'),
          );
        } on Object catch (e) {
          error = e;
        }
      });
      expect(error, isA<ArgumentError>());
      expect(error.toString(), allOf(contains('B5:C6'), contains('B2:B5')));
      expect(xml, startsWith('<dataValidations count="1">'));
      expect(xml, isNot(contains('FALSE')));
      expect(xml, isNot(contains('A1')));
    });
    test('ranges of one validation that overlap throw', () {
      expect(
        () => _validations(
          (XlsxSheetWriter s) => s.dataValidation(
            XlsxDataValidation.custom(<XlsxRange>[
              XlsxRange.parse('A1:B2'),
              XlsxRange.parse('B2:C3'),
            ], 'T'),
          ),
        ),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => e.toString(),
            'message',
            allOf(contains('A1:B2'), contains('B2:C3')),
          ),
        ),
      );
    });
    test('a rejected validation records nothing, even its good fields', () {
      final String xml = _validations((XlsxSheetWriter s) {
        expect(
          () => s.dataValidation(
            XlsxDataValidation.whole(
              <XlsxRange>[_a1],
              XlsxComparison.between,
              1,
            ),
          ),
          throwsArgumentError,
        );
      });
      expect(xml, '');
    });
    test('after the sheet is finished it throws StateError', () {
      final XlsxWriter book = XlsxWriter();
      final XlsxSheetWriter first = book.addSheet('A')..row(<Object?>[1]);
      book.addSheet('B');
      expect(
        () => first.dataValidation(
          XlsxDataValidation.custom(<XlsxRange>[_a1], 'TRUE'),
        ),
        throwsStateError,
      );
    });
  });

  group('constructor', () {
    test('holds what the XML allows: whole greaterThan with a reference', () {
      expect(
        _one(
          XlsxDataValidation(
            <XlsxRange>[_a1],
            XlsxValidationType.whole,
            comparison: XlsxComparison.greaterThan,
            formula1: r'$A$1',
            showDropDownArrow: false,
          ),
        ),
        '<dataValidation type="whole" operator="greaterThan" '
        'allowBlank="1" showDropDown="1" showInputMessage="1" '
        'showErrorMessage="1" sqref="A1">'
        r'<formula1>$A$1</formula1></dataValidation>',
      );
    });
    test('defaults are those of the schema and the brief', () {
      final XlsxDataValidation v = XlsxDataValidation(
        <XlsxRange>[_a1],
        XlsxValidationType.custom,
        formula1: 'TRUE',
      );
      expect(v.comparison, XlsxComparison.between);
      expect(v.allowBlank && v.showDropDownArrow, isTrue);
      expect(v.showInputMessage && v.showErrorMessage, isTrue);
      expect(v.errorStyle, XlsxValidationErrorStyle.stop);
      expect(v, XlsxDataValidation.custom(<XlsxRange>[_a1], 'TRUE'));
    });
    test('an invalid value is rejected at registration, nothing recorded', () {
      final String xml = _validations((XlsxSheetWriter s) {
        expect(
          () => s.dataValidation(
            XlsxDataValidation(
              <XlsxRange>[_a1],
              XlsxValidationType.whole,
              formula1: '1',
            ),
          ),
          throwsA(
            isA<ArgumentError>().having(
              (ArgumentError e) => e.name,
              'name',
              'formula2',
            ),
          ),
        );
      });
      expect(xml, '');
    });
    test('ranges is copied and every field takes part in equality', () {
      final List<XlsxRange> source = <XlsxRange>[_a1];
      final XlsxDataValidation v = XlsxDataValidation(
        source,
        XlsxValidationType.any,
      );
      source.add(_b2);
      expect(v.ranges, <XlsxRange>[_a1]);
      expect(
        v,
        isNot(
          XlsxDataValidation(
            <XlsxRange>[_a1],
            XlsxValidationType.any,
            showDropDownArrow: false,
          ),
        ),
      );
    });
  });

  group('value semantics', () {
    test('equal validations are equal and hash alike', () {
      XlsxDataValidation make() => XlsxDataValidation.whole(
        <XlsxRange>[_a1, _b2],
        XlsxComparison.between,
        1,
        b: 10,
        prompt: 'p',
      );
      expect(make(), make());
      expect(make().hashCode, make().hashCode);
      expect(
        make(),
        isNot(
          XlsxDataValidation.whole(
            <XlsxRange>[_a1],
            XlsxComparison.between,
            1,
            b: 10,
            prompt: 'p',
          ),
        ),
      );
      expect(make().toString(), startsWith('XlsxDataValidation('));
    });
    test('ranges is an unmodifiable copy', () {
      final List<XlsxRange> source = <XlsxRange>[_a1];
      final XlsxDataValidation v = XlsxDataValidation.custom(source, 'TRUE');
      source.add(_b2);
      expect(v.ranges, <XlsxRange>[_a1]);
      expect(() => v.ranges.add(_b2), throwsUnsupportedError);
    });
    test('the defaults are those of the schema', () {
      final XlsxDataValidation v = XlsxDataValidation.custom(<XlsxRange>[
        _a1,
      ], 'TRUE');
      expect(v.comparison, XlsxComparison.between);
      expect(v.allowBlank, isTrue);
      expect(v.showDropDownArrow, isTrue);
      expect(v.showInputMessage, isTrue);
      expect(v.showErrorMessage, isTrue);
      expect(v.errorStyle, XlsxValidationErrorStyle.stop);
    });
  });

  group('worksheet order', () {
    test('mergeCells, dataValidations, hyperlinks (Quds wrote them first)', () {
      final XlsxWriter book = XlsxWriter();
      book.addSheet('S')
        ..row(<Object?>[XlsxHyperlink.location('S!A1'), null])
        ..dataValidation(XlsxDataValidation.custom(<XlsxRange>[_b2], 'TRUE'))
        ..merge(XlsxRange.parse('C1:D1'));
      final XlsxResult result = book.close();
      final String xml = readXlsx(result.bytes)[_sheet1]!;
      final List<int> at = <int>[
        xml.indexOf('<mergeCells'),
        xml.indexOf('<dataValidations'),
        xml.indexOf('<hyperlinks'),
      ];
      expect(at, everyElement(greaterThan(-1)));
      expect(at[0], lessThan(at[1]));
      expect(at[1], lessThan(at[2]));
      expect(xml.indexOf('</sheetData>'), lessThan(at[0]));
      expect(checkXlsx(result.bytes), isEmpty);
    });
  });
}
