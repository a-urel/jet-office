import 'package:jet_core/jet_core.dart' show FormatKind;
import 'package:jet_office/src/opc/opaque_xml.dart';
import 'package:jet_office/src/xlsx/cell_encoder.dart';
import 'package:jet_office/src/xlsx/date_serial.dart';
import 'package:jet_office/src/xlsx/number_format.dart';
import 'package:jet_office/src/xlsx/raw_cell.dart';
import 'package:jet_office/src/xlsx/read/styles_reader.dart';
import 'package:jet_office/src/xlsx/shared_strings.dart';
import 'package:jet_office/src/xlsx/style.dart';
import 'package:jet_office/src/xlsx/style_registry.dart';
import 'package:jet_office/src/xlsx/values.dart';
import 'package:jet_office/src/xlsx/warnings.dart';
import 'package:jet_office/src/xml/xml_pull_reader.dart';
import 'package:jet_office/src/xml/xml_writer.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart' show XmlDocument, XmlElement;

const String _main =
    'http://schemas.openxmlformats.org/spreadsheetml/2006/main';

/// The first element named [localName] of [xml], captured as opaque XML.
OpaqueXml _capture(String xml, String localName) {
  final XmlPullReader r = XmlPullReader(xml);
  while (r.next()) {
    if (r.eventType == XmlEventType.startElement && r.localName == localName) {
      return OpaqueXml.capture(r);
    }
  }
  throw StateError('no <$localName>');
}

/// A recorded call of the fake `dateStyle`.
typedef _DateStyleCall = ({int? style, bool withTime});

void main() {
  late SharedStrings strings;
  late StyleRegistry styles;
  late WarningCollector warnings;
  late CellEncoder encoder;
  late List<_DateStyleCall> dateStyleCalls;

  setUp(() {
    strings = SharedStrings.seeded(const <String>['first']);
    styles = StyleRegistry();
    warnings = WarningCollector();
    encoder = CellEncoder(strings: strings, styles: styles, warnings: warnings);
    dateStyleCalls = <_DateStyleCall>[];
  });

  int fakeDateStyle(int? style, {required bool withTime}) {
    dateStyleCalls.add((style: style, withTime: withTime));
    return 90 + dateStyleCalls.length;
  }

  RawCell prepare(
    Object? value, {
    RawCell? current,
    CellFormat format = CellFormat.general,
    bool date1904 = false,
  }) => encoder.prepare(
    value,
    sheet: 'S',
    row: 4,
    column: 2,
    current: current,
    currentFormat: format,
    date1904: date1904,
    dateStyle: fakeDateStyle,
  );

  String write(
    RawCell cell, {
    int row = 0,
    int column = 0,
    Map<String, String> declaredAbove = const <String, String>{},
  }) {
    final StringBuffer buffer = StringBuffer();
    encoder.writeRaw(
      XmlWriter(buffer),
      row: row,
      column: column,
      cell: cell,
      declaredAbove: declaredAbove,
    );
    return buffer.toString();
  }

  List<XlsxWarningCode> codes() =>
      warnings.warnings.map((XlsxWarning w) => w.code).toList();

  group('prepare', () {
    test('prepare interns a string into the shared table', () {
      final RawCell cell = prepare(
        'hello',
        current: const RawCell(kind: RawCellKind.number, style: 3, value: '1'),
      );
      expect(cell.kind, RawCellKind.sharedString);
      expect(cell.value, '1');
      expect(cell.style, 3);
      expect(strings.textAt(1), 'hello');
      expect(prepare('first').value, '0');
    });

    test('prepare repairs and warns like encode', () {
      final RawCell cell = prepare('a\u0001b');
      expect(cell.kind, RawCellKind.sharedString);
      expect(strings.textAt(int.parse(cell.value!)), 'ab');
      expect(codes(), <XlsxWarningCode>[
        XlsxWarningCode.invalidCharactersRemoved,
      ]);
      expect(warnings.warnings.single.cells, <String>['C5']);
      expect(warnings.warnings.single.sheet, 'S');
    });

    test('prepare truncates long text and warns', () {
      final RawCell cell = prepare('x' * 40000);
      expect(strings.textAt(int.parse(cell.value!)).length, 32767);
      expect(codes(), <XlsxWarningCode>[XlsxWarningCode.textTruncated]);
    });

    test('prepare throws like encode', () {
      final int before = strings.length;
      for (final Object value in <Object>[
        double.nan,
        double.infinity,
        const XlsxFormula('='),
        const XlsxFormula('A1', cached: double.nan),
        const XlsxFormula('A1', cached: 'a\u0001'),
        const XlsxDate(2026, 2, 30),
        Object(),
      ]) {
        expect(() => prepare(value), throwsArgumentError, reason: '$value');
      }
      expect(strings.length, before);
      expect(warnings.warnings, isEmpty);
      expect(dateStyleCalls, isEmpty);
      // Nothing was registered: the first new style still gets id 1.
      expect(styles.idFor(const XlsxStyle(numFmt: XlsxNumFmt.integer)), 1);
    });

    test('prepare writes numbers and booleans as encode does', () {
      expect(prepare(42).value, '42');
      expect(prepare(42).kind, RawCellKind.number);
      expect(prepare(-0.0).value, '0');
      expect(prepare(1.5).value, '1.5');
      expect(prepare(true).kind, RawCellKind.boolean);
      expect(prepare(true).value, '1');
      expect(prepare(false).value, '0');
      expect(warnings.warnings, isEmpty);
      // 2^53 + 2: past 2^53, yet exact in JavaScript, so this runs on the web.
      expect(prepare(9007199254740994).value, '9007199254740994');
      expect(codes(), <XlsxWarningCode>[XlsxWarningCode.intPrecisionLost]);
    });

    test('prepare keeps the digits of an XlsxDecimal', () {
      final RawCell cell = prepare(XlsxDecimal('12.50'));
      expect(cell.kind, RawCellKind.number);
      expect(cell.value, '12.50');
    });

    test('prepare of null gives an empty cell with the current style', () {
      final RawCell cell = prepare(
        null,
        current: const RawCell(kind: RawCellKind.number, style: 7, value: '1'),
      );
      expect(cell.isEmpty, isTrue);
      expect(cell.style, 7);
      expect(prepare(null).style, isNull);
    });

    test('prepare gives a General cell a date style', () {
      const RawCell current = RawCell(
        kind: RawCellKind.number,
        style: 3,
        value: '1',
      );
      final RawCell dated = prepare(
        const XlsxDate(2026, 11, 2),
        current: current,
      );
      expect(dated.style, 91);
      expect(dated.kind, RawCellKind.number);
      expect(dated.value, '${dateSerial(2026, 11, 2)}');
      final RawCell timed = prepare(
        DateTime(2026, 11, 2, 12),
        current: current,
      );
      expect(timed.style, 92);
      expect(timed.value, '${dateTimeSerial(DateTime(2026, 11, 2, 12))}');
      // A DateTime at midnight still gets the date-time format, as in the
      // writer, which chooses by type.
      final RawCell midnight = prepare(DateTime(2026, 11, 2));
      expect(midnight.style, 93);
      expect(midnight.value, '${dateSerial(2026, 11, 2)}');
      expect(dateStyleCalls, <_DateStyleCall>[
        (style: 3, withTime: false),
        (style: 3, withTime: true),
        (style: null, withTime: true),
      ]);
      expect(warnings.warnings, isEmpty);
    });

    test('prepare keeps a date format', () {
      const RawCell current = RawCell(kind: RawCellKind.number, style: 5);
      for (final CellFormat format in const <CellFormat>[
        CellFormat(14, 'm/d/yyyy', FormatKind.date),
        CellFormat(20, 'h:mm', FormatKind.time),
      ]) {
        final RawCell cell = prepare(
          DateTime(2026, 11, 2, 6),
          current: current,
          format: format,
        );
        expect(cell.style, 5);
      }
      expect(dateStyleCalls, isEmpty);
      expect(warnings.warnings, isEmpty);
    });

    test('prepare keeps a non-date format and warns', () {
      final RawCell cell = prepare(
        const XlsxDate(2026, 11, 2),
        current: const RawCell(kind: RawCellKind.number, style: 4),
        format: const CellFormat(2, '0.00', FormatKind.number),
      );
      expect(cell.style, 4);
      expect(cell.value, '${dateSerial(2026, 11, 2)}');
      expect(dateStyleCalls, isEmpty);
      expect(codes(), <XlsxWarningCode>[XlsxWarningCode.dateInNonDateFormat]);
    });

    test('prepare writes a date outside Excel\'s range as text', () {
      final RawCell cell = prepare(
        DateTime(1850, 6, 15),
        current: const RawCell(kind: RawCellKind.number, style: 2),
      );
      expect(cell.kind, RawCellKind.sharedString);
      expect(cell.style, 2);
      expect(
        strings.textAt(int.parse(cell.value!)),
        DateTime(1850, 6, 15).toIso8601String(),
      );
      expect(codes(), <XlsxWarningCode>[XlsxWarningCode.dateOutsideExcelRange]);
      expect(dateStyleCalls, isEmpty);
    });

    test('prepare writes a 1904 serial in a 1904 workbook', () {
      expect(
        prepare(const XlsxDate(2026, 11, 2), date1904: true).value,
        '${dateSerial(2026, 11, 2)! - 1462}',
      );
      expect(
        prepare(DateTime(2026, 11, 2, 12), date1904: true).value,
        '${dateTimeSerial(DateTime(2026, 11, 2, 12))! - 1462}',
      );
      // Before 1904-01-01 a 1904 workbook has no serial: text and a warning.
      final RawCell early = prepare(
        const XlsxDate(1903, 12, 31),
        date1904: true,
      );
      expect(early.kind, RawCellKind.sharedString);
      expect(strings.textAt(int.parse(early.value!)), '1903-12-31');
      expect(codes(), <XlsxWarningCode>[XlsxWarningCode.dateOutsideExcelRange]);
    });

    test('prepare stores a formula with its cached value', () {
      final RawCell text = prepare(
        const XlsxFormula('=A1&"x"', cached: 'a_x0041_'),
      );
      expect(text.kind, RawCellKind.string);
      expect(text.formula!.type, FormulaType.normal);
      expect(text.formula!.text, 'A1&"x"');
      // The <v> text as written: escaped against ST_Xstring decoding.
      expect(text.value, 'a_x005F_x0041_');
      final RawCell none = prepare(const XlsxFormula('A1*2'));
      expect(none.kind, RawCellKind.number);
      expect(none.value, isNull);
      expect(none.formula!.text, 'A1*2');
      expect(prepare(const XlsxFormula('A1', cached: true)).value, '1');
      expect(
        prepare(const XlsxFormula('A1', cached: true)).kind,
        RawCellKind.boolean,
      );
      expect(prepare(const XlsxFormula('A1', cached: 2.5)).value, '2.5');
      expect(warnings.warnings, isEmpty);
    });

    test('prepare and writeRaw give the bytes encode gives', () {
      final CellEncoder writer = CellEncoder(
        strings: SharedStrings.seeded(const <String>['first']),
        styles: StyleRegistry(),
        warnings: WarningCollector(),
      );
      for (final Object value in <Object>[
        'first',
        'a<b & _x0041_',
        42,
        -1.25e-7,
        true,
        XlsxDecimal('-12.50'),
        const XlsxFormula('=A1&"<"', cached: 'x_x0041_<'),
        const XlsxFormula('SUM(A1:A3)', cached: 6),
        const XlsxFormula('A1', cached: false),
        const XlsxFormula('_x0041_1'),
      ]) {
        final StringBuffer expected = StringBuffer();
        writer.encode(
          XmlWriter(expected),
          sheet: 'S',
          row: 4,
          column: 2,
          value: value,
        );
        expect(
          write(prepare(value), row: 4, column: 2),
          expected.toString(),
          reason: '$value',
        );
      }
    });
  });

  group('writeRaw', () {
    test('writeRaw writes kept attributes, formula groups and inline XML', () {
      expect(
        write(
          const RawCell(
            kind: RawCellKind.number,
            value: '2',
            formula: RawFormula(
              type: FormulaType.shared,
              text: 'A2*2',
              ref: 'B2:B4',
              si: '0',
            ),
          ),
          row: 1,
          column: 1,
        ),
        '<c r="B2"><f t="shared" ref="B2:B4" si="0">A2*2</f><v>2</v></c>',
      );
      expect(
        write(
          const RawCell(
            kind: RawCellKind.number,
            value: '4',
            formula: RawFormula(type: FormulaType.shared, si: '0'),
          ),
          row: 2,
          column: 1,
        ),
        '<c r="B3"><f t="shared" si="0"/><v>4</v></c>',
      );
      expect(
        write(
          const RawCell(
            kind: RawCellKind.number,
            style: 2,
            value: '6',
            formula: RawFormula(
              type: FormulaType.array,
              text: 'SUM(A1:A3*B1:B3)',
              ref: 'C1',
              attributes: <KeptAttribute>[
                (qualifiedName: 'aca', namespaceUri: '', value: '1'),
              ],
            ),
          ),
          column: 2,
        ),
        '<c r="C1" s="2"><f t="array" ref="C1" aca="1">SUM(A1:A3*B1:B3)</f>'
        '<v>6</v></c>',
      );
      expect(
        write(
          const RawCell(
            kind: RawCellKind.number,
            value: '6',
            formula: RawFormula(
              type: FormulaType.array,
              text: '_xlfn.UNIQUE(A1:A3)',
              ref: 'D1:D3',
            ),
            attributes: <KeptAttribute>[
              (qualifiedName: 'cm', namespaceUri: '', value: '1'),
            ],
          ),
          column: 3,
        ),
        '<c r="D1" cm="1"><f t="array" ref="D1:D3">_xlfn.UNIQUE(A1:A3)</f>'
        '<v>6</v></c>',
      );
      const String inline =
          '<is><r><rPr><b/></rPr><t>Bold</t></r>'
          '<r><t xml:space="preserve"> plain</t></r></is>';
      expect(
        write(
          RawCell(
            kind: RawCellKind.inlineString,
            inline: _capture('<c xmlns="$_main">$inline</c>', 'is'),
          ),
          row: 4,
          declaredAbove: const <String, String>{'': _main},
        ),
        '<c r="A5" t="inlineStr">$inline</c>',
      );
      expect(
        write(
          const RawCell(kind: RawCellKind.number, style: 7),
          row: 4,
          column: 2,
        ),
        '<c r="C5" s="7"/>',
      );
    });

    test('writeRaw writes nothing for an empty cell without a style', () {
      expect(write(const RawCell(kind: RawCellKind.number)), '');
    });

    test('writeRaw keeps an unknown formula type and escapes the text', () {
      expect(
        write(
          const RawCell(
            kind: RawCellKind.unknown,
            typeText: 'future',
            value: 'a<b',
            formula: RawFormula(
              type: FormulaType.normal,
              text: '_x0041_1&"<"',
              attributes: <KeptAttribute>[
                (qualifiedName: 't', namespaceUri: '', value: 'later'),
              ],
            ),
          ),
        ),
        '<c r="A1" t="future"><f t="later">_x005F_x0041_1&amp;"&lt;"</f>'
        '<v>a&lt;b</v></c>',
      );
    });

    test('writeRaw writes other children after the value, declaring what '
        'is not above', () {
      const String x14 =
          'http://schemas.microsoft.com/office/spreadsheetml/2009/9/main';
      final OpaqueXml ext = _capture(
        '<c xmlns="$_main" xmlns:x14="$x14"><v>1</v>'
            '<extLst><ext uri="{X}"><x14:a/></ext></extLst></c>',
        'extLst',
      );
      expect(
        write(
          RawCell(
            kind: RawCellKind.number,
            value: '1',
            extraChildren: <OpaqueXml>[ext],
            attributes: const <KeptAttribute>[
              (qualifiedName: 'vm', namespaceUri: '', value: '2'),
              (qualifiedName: 'x14:z', namespaceUri: x14, value: 'a"b'),
            ],
          ),
          declaredAbove: const <String, String>{'': _main, 'x14': x14},
        ),
        '<c r="A1" vm="2" x14:z="a&quot;b"><v>1</v>'
        '<extLst><ext uri="{X}"><x14:a/></ext></extLst></c>',
      );
      expect(
        write(
          RawCell(
            kind: RawCellKind.number,
            value: '1',
            extraChildren: <OpaqueXml>[ext],
          ),
          declaredAbove: const <String, String>{'': _main},
        ),
        '<c r="A1"><v>1</v>'
        '<extLst xmlns:x14="$x14"><ext uri="{X}"><x14:a/></ext></extLst></c>',
      );
    });

    test('writeRaw declares the prefix of a kept attribute that is not '
        'declared above', () {
      const String x14 =
          'http://schemas.microsoft.com/office/spreadsheetml/2009/9/main';
      final String xml = write(
        const RawCell(
          kind: RawCellKind.number,
          value: '1',
          attributes: <KeptAttribute>[
            (qualifiedName: 'x14:z', namespaceUri: x14, value: '1'),
          ],
          formula: RawFormula(
            type: FormulaType.normal,
            text: 'A1',
            attributes: <KeptAttribute>[
              (qualifiedName: 'x14:y', namespaceUri: x14, value: '2'),
            ],
          ),
        ),
        declaredAbove: const <String, String>{'': _main},
      );
      expect(
        xml,
        '<c r="A1" xmlns:x14="$x14" x14:z="1">'
        '<f x14:y="2">A1</f><v>1</v></c>',
      );
      final XmlElement c = XmlDocument.parse(
        '<sheetData xmlns="$_main">$xml</sheetData>',
      ).rootElement.childElements.single;
      expect(c.getAttribute('z', namespaceUri: x14), '1');
    });

    test('writeRaw writes a kept attribute of an empty unstyled cell', () {
      expect(
        write(
          const RawCell(
            kind: RawCellKind.number,
            attributes: <KeptAttribute>[
              (qualifiedName: 's', namespaceUri: '', value: 'x'),
            ],
          ),
        ),
        '<c r="A1" s="x"/>',
      );
    });

    test('writeRaw drops a character XML forbids from stored text', () {
      // Only a character reference in the source (`&#1;`) can put one there.
      expect(
        write(const RawCell(kind: RawCellKind.string, value: 'a\u0001b')),
        '<c r="A1" t="str"><v>ab</v></c>',
      );
    });
  });
}
