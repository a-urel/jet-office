import 'package:jet_office/src/common/read_guard.dart';
import 'package:jet_office/src/opc/package.dart';
import 'package:jet_office/src/xml/xml_pull_reader.dart';
import 'package:jet_office/src/zip/archive_adapter.dart';
import 'package:test/test.dart';

/// A failure the tests throw from `guardRead`'s callback.
final class _Failed implements Exception {
  _Failed(this.problem);

  final ReadProblem problem;
}

ReadProblem _caught(String? part, void Function() body) {
  try {
    guardRead<void>(part, body, _Failed.new);
  } on _Failed catch (e) {
    return e.problem;
  }
  fail('guardRead did not call onProblem');
}

void main() {
  group('mapZipError', () {
    const Map<ZipReadErrorKind, (ReadProblemKind, String?)> expected =
        <ZipReadErrorKind, (ReadProblemKind, String?)>{
          ZipReadErrorKind.notZip: (ReadProblemKind.notZip, null),
          ZipReadErrorKind.corrupt: (ReadProblemKind.corruptZip, null),
          ZipReadErrorKind.duplicateEntry: (ReadProblemKind.corruptZip, null),
          ZipReadErrorKind.encrypted: (ReadProblemKind.encrypted, null),
          ZipReadErrorKind.legacyXls: (ReadProblemKind.legacyBinary, null),
          ZipReadErrorKind.tooManyEntries: (
            ReadProblemKind.limitExceeded,
            'maxEntries',
          ),
          ZipReadErrorKind.entryTooLarge: (
            ReadProblemKind.limitExceeded,
            'maxEntryBytes',
          ),
          ZipReadErrorKind.totalTooLarge: (
            ReadProblemKind.limitExceeded,
            'maxTotalBytes',
          ),
          ZipReadErrorKind.ratioTooHigh: (
            ReadProblemKind.limitExceeded,
            'maxCompressionRatio',
          ),
        };

    test('covers every ZipReadErrorKind', () {
      expect(expected.keys.toSet(), ZipReadErrorKind.values.toSet());
    });

    for (final MapEntry<ZipReadErrorKind, (ReadProblemKind, String?)> e
        in expected.entries) {
      test('${e.key.name} maps to ${e.value.$1.name}', () {
        final ReadProblem p = mapZipError(
          ZipReadError(e.key, 'cause text', entry: 'xl/a.xml'),
        );
        expect(p.kind, e.value.$1);
        expect(p.limit, e.value.$2);
        expect(p.detail, 'cause text');
        expect(p.part, 'xl/a.xml');
      });
    }

    test('the entry wins over the part, which is the fallback', () {
      expect(
        mapZipError(
          const ZipReadError(ZipReadErrorKind.corrupt, 'm', entry: 'e'),
          part: 'p',
        ).part,
        'e',
      );
      expect(
        mapZipError(
          const ZipReadError(ZipReadErrorKind.corrupt, 'm'),
          part: 'p',
        ).part,
        'p',
      );
      expect(
        mapZipError(const ZipReadError(ZipReadErrorKind.notZip, 'm')).part,
        isNull,
      );
    });
  });

  group('mapXmlError', () {
    test('too deep maps to limitExceeded naming maxDepth', () {
      final ReadProblem p = mapXmlError(
        const XmlParseException('too deep', 3, kind: XmlParseKind.tooDeep),
        'word/document.xml',
      );
      expect(p, (
        kind: ReadProblemKind.limitExceeded,
        part: 'word/document.xml',
        detail: 'too deep',
        limit: 'maxDepth',
      ));
    });

    for (final XmlParseKind kind in <XmlParseKind>[
      XmlParseKind.doctype,
      XmlParseKind.malformed,
      XmlParseKind.encoding,
    ]) {
      test('${kind.name} maps to malformedXml', () {
        final ReadProblem p = mapXmlError(
          XmlParseException('bad', 0, kind: kind),
          'a.xml',
        );
        expect(p, (
          kind: ReadProblemKind.malformedXml,
          part: 'a.xml',
          detail: 'bad',
          limit: null,
        ));
      });
    }
  });

  group('mapPackageError', () {
    test('a ZIP cause maps as a ZIP error with the package part', () {
      final ReadProblem p = mapPackageError(
        const OpcFormatException(
          OpcFormatKind.zip,
          part: 'x.xml',
          cause: ZipReadError(ZipReadErrorKind.corrupt, 'crc'),
        ),
      );
      expect(p.kind, ReadProblemKind.corruptZip);
      expect(p.part, 'x.xml');
      expect(p.detail, 'crc');
    });

    test('an XML cause names xmlPart when given, else the package part', () {
      const OpcFormatException e = OpcFormatException(
        OpcFormatKind.xml,
        part: 'Pkg.xml',
        cause: XmlParseException('bad', 0, kind: XmlParseKind.doctype),
      );
      expect(mapPackageError(e).part, 'Pkg.xml');
      expect(mapPackageError(e, xmlPart: 'pkg.xml').part, 'pkg.xml');
      expect(mapPackageError(e).kind, ReadProblemKind.malformedXml);
    });

    test('a missing part maps to missingPart', () {
      final ReadProblem p = mapPackageError(
        const OpcFormatException(OpcFormatKind.missingPart, part: 'gone.xml'),
      );
      expect(p.kind, ReadProblemKind.missingPart);
      expect(p.part, 'gone.xml');
      expect(p.limit, isNull);
    });
  });

  group('guardRead', () {
    test('returns the body result when nothing fails', () {
      expect(guardRead<int>('a.xml', () => 7, _Failed.new), 7);
    });

    test('an XmlParseException carries the part', () {
      final ReadProblem p = _caught('a.xml', () {
        throw const XmlParseException('deep', 0, kind: XmlParseKind.tooDeep);
      });
      expect(p.kind, ReadProblemKind.limitExceeded);
      expect(p.part, 'a.xml');
    });

    test('a ZipReadError names its own entry', () {
      final ReadProblem p = _caught('a.xml', () {
        throw const ZipReadError(
          ZipReadErrorKind.legacyXls,
          'ole',
          entry: 'b.bin',
        );
      });
      expect(p.kind, ReadProblemKind.legacyBinary);
      expect(p.part, 'b.bin');
    });

    test('an OpcFormatException with an XML cause names the part', () {
      final ReadProblem p = _caught('a.xml', () {
        throw const OpcFormatException(
          OpcFormatKind.xml,
          part: 'A.XML',
          cause: XmlParseException('bad', 0),
        );
      });
      expect(p.kind, ReadProblemKind.malformedXml);
      expect(p.part, 'a.xml');
    });

    test('an OpcFormatException without a part guard names its own', () {
      final ReadProblem p = _caught(null, () {
        throw const OpcFormatException(OpcFormatKind.missingPart, part: 'x');
      });
      expect(p.kind, ReadProblemKind.missingPart);
      expect(p.part, 'x');
    });

    test('other exceptions pass through', () {
      expect(
        () => guardRead<void>(null, () => throw StateError('no'), _Failed.new),
        throwsStateError,
      );
    });
  });
}
