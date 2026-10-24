import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/xlsx/fill.dart' as impl;
import 'package:jet_office/src/xml/xml_writer.dart';
import 'package:test/test.dart';

String xml(XlsxFill fill) {
  final StringBuffer out = StringBuffer();
  impl.writeFillXml(XmlWriter(out), fill);
  return out.toString();
}

void main() {
  const XlsxColor white = XlsxColor.rgb(0xFFFFFF);
  const XlsxColor blue = XlsxColor.rgb(0x4472C4);

  test('solid fill', () {
    expect(
      xml(const XlsxFill.solid(XlsxColor.rgb(0xDDEBF7))),
      '<fill><patternFill patternType="solid"><fgColor rgb="FFDDEBF7"/>'
      '</patternFill></fill>',
    );
  });

  test('pattern fill with both colors', () {
    expect(
      xml(
        const XlsxFill.pattern(
          XlsxPatternType.lightGray,
          foreground: XlsxColor.rgb(0xFF0000),
          background: white,
        ),
      ),
      '<fill><patternFill patternType="lightGray"><fgColor rgb="FFFF0000"/>'
      '<bgColor rgb="FFFFFFFF"/></patternFill></fill>',
    );
  });

  test('pattern fill without colors is an empty patternFill', () {
    expect(
      xml(const XlsxFill.pattern(XlsxPatternType.none)),
      '<fill><patternFill patternType="none"/></fill>',
    );
    expect(
      xml(const XlsxFill.pattern(XlsxPatternType.gray125)),
      '<fill><patternFill patternType="gray125"/></fill>',
    );
  });

  test('all 19 pattern types are written by name', () {
    expect(XlsxPatternType.values, hasLength(19));
    for (final XlsxPatternType t in XlsxPatternType.values) {
      expect(xml(XlsxFill.pattern(t)), contains('patternType="${t.name}"'));
    }
  });

  test('linear gradient', () {
    expect(
      xml(
        XlsxGradientFill.linear(
          degree: 90,
          stops: const <XlsxGradientStop>[
            XlsxGradientStop(0, white),
            XlsxGradientStop(1, blue),
          ],
        ),
      ),
      '<fill><gradientFill degree="90"><stop position="0">'
      '<color rgb="FFFFFFFF"/></stop><stop position="1">'
      '<color rgb="FF4472C4"/></stop></gradientFill></fill>',
    );
  });

  test('linear gradient at degree 0 omits the attribute', () {
    expect(
      xml(
        XlsxGradientFill.linear(
          stops: const <XlsxGradientStop>[
            XlsxGradientStop(0, white),
            XlsxGradientStop(0.5, blue),
          ],
        ),
      ),
      startsWith('<fill><gradientFill><stop position="0">'),
    );
  });

  test('path gradient', () {
    expect(
      xml(
        XlsxGradientFill.path(
          left: .5,
          right: .5,
          top: .5,
          bottom: .5,
          stops: const <XlsxGradientStop>[
            XlsxGradientStop(0, white),
            XlsxGradientStop(1, blue),
          ],
        ),
      ),
      '<fill><gradientFill type="path" left="0.5" right="0.5" top="0.5" '
      'bottom="0.5"><stop position="0"><color rgb="FFFFFFFF"/></stop>'
      '<stop position="1"><color rgb="FF4472C4"/></stop></gradientFill></fill>',
    );
  });

  test('equality and hashing', () {
    expect(
      const XlsxFill.solid(white),
      const XlsxFill.pattern(XlsxPatternType.solid, foreground: white),
    );
    expect(
      const XlsxFill.solid(white).hashCode,
      const XlsxFill.pattern(XlsxPatternType.solid, foreground: white).hashCode,
    );
    expect(const XlsxFill.solid(white).runtimeType, XlsxPatternFill);
    expect(const XlsxFill.solid(white), isNot(const XlsxFill.solid(blue)));
    expect(const XlsxFill.solid(white).toString(), contains('solid'));
  });

  test('gradient equality compares stops element by element', () {
    XlsxGradientFill g() => XlsxGradientFill.linear(
      degree: 45,
      stops: <XlsxGradientStop>[
        const XlsxGradientStop(0, white),
        const XlsxGradientStop(1, blue),
      ],
    );
    expect(g(), g());
    expect(g().hashCode, g().hashCode);
    expect(
      g(),
      isNot(
        XlsxGradientFill.linear(
          degree: 45,
          stops: const <XlsxGradientStop>[
            XlsxGradientStop(0, white),
            XlsxGradientStop(0.9, blue),
          ],
        ),
      ),
    );
    expect(
      XlsxGradientFill.linear(
        stops: const <XlsxGradientStop>[XlsxGradientStop(0, white)],
      ),
      isNot(const XlsxFill.solid(white)),
    );
  });

  test('the fill keeps its own copy of the stops', () {
    final List<XlsxGradientStop> stops = <XlsxGradientStop>[
      const XlsxGradientStop(0, white),
      const XlsxGradientStop(1, blue),
    ];
    final XlsxGradientFill fill = XlsxGradientFill.linear(stops: stops);
    final String before = xml(fill);
    stops.add(const XlsxGradientStop(1, white));
    expect(fill.stops, hasLength(2));
    expect(xml(fill), before);
    expect(
      () => fill.stops.add(const XlsxGradientStop(1, white)),
      throwsUnsupportedError,
    );
  });

  group('validateFill', () {
    void bad(XlsxFill f, [String? field]) => expect(
      () => impl.validateFill(f),
      throwsA(
        isA<ArgumentError>().having(
          (ArgumentError e) => e.name,
          'name',
          field ?? anything,
        ),
      ),
    );
    XlsxGradientFill lin(List<XlsxGradientStop> s, {double degree = 0}) =>
        XlsxGradientFill.linear(degree: degree, stops: s);

    test('accepts valid fills', () {
      impl.validateFill(const XlsxFill.solid(white));
      impl.validateFill(
        lin(const <XlsxGradientStop>[
          XlsxGradientStop(0, white),
          XlsxGradientStop(0, blue),
          XlsxGradientStop(1, blue),
        ]),
      );
    });

    test('rejects a gradient with fewer than two stops', () {
      bad(lin(const <XlsxGradientStop>[XlsxGradientStop(0, white)]), 'stops');
      bad(lin(const <XlsxGradientStop>[]), 'stops');
    });

    test('rejects bad positions', () {
      bad(
        lin(const <XlsxGradientStop>[
          XlsxGradientStop(0.6, white),
          XlsxGradientStop(0.4, blue),
        ]),
      );
      bad(
        lin(const <XlsxGradientStop>[
          XlsxGradientStop(0, white),
          XlsxGradientStop(1.2, blue),
        ]),
      );
      bad(
        lin(const <XlsxGradientStop>[
          XlsxGradientStop(-0.1, white),
          XlsxGradientStop(1, blue),
        ]),
      );
    });

    test('rejects a non-finite degree and bad edges', () {
      const List<XlsxGradientStop> ok = <XlsxGradientStop>[
        XlsxGradientStop(0, white),
        XlsxGradientStop(1, blue),
      ];
      bad(lin(ok, degree: double.nan), 'degree');
      bad(lin(ok, degree: double.infinity), 'degree');
      bad(XlsxGradientFill.path(left: 1.5, stops: ok), 'left');
      bad(XlsxGradientFill.path(top: -0.1, stops: ok), 'top');
      bad(XlsxGradientFill.path(bottom: double.nan, stops: ok), 'bottom');
    });

    test('rejects invalid colors', () {
      bad(const XlsxFill.solid(XlsxColor.theme(12)), 'foreground');
      bad(
        const XlsxFill.pattern(
          XlsxPatternType.solid,
          background: XlsxColor.indexed(66),
        ),
      );
      bad(
        lin(const <XlsxGradientStop>[
          XlsxGradientStop(0, XlsxColor.theme(12)),
          XlsxGradientStop(1, blue),
        ]),
      );
    });
  });
}
