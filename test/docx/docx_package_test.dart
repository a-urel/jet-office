import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/docx/docx_package.dart';
import 'package:jet_office/src/docx/warnings.dart' show DocxWarningCollector;
import 'package:jet_office/src/opc/ooxml.dart';
import 'package:jet_office/src/xml/xml_pull_reader.dart';
import 'package:test/test.dart';

import 'support/docx_builder.dart';

/// Opens [bytes] with [limits].
DocxPackage _open(
  Uint8List bytes, {
  DocxReadLimits limits = const DocxReadLimits(),
  DocxWarningCollector? warnings,
}) => DocxPackage(bytes, limits, warnings ?? DocxWarningCollector());

/// Opens [bytes], reads the main part and its text to the end and requires a
/// [DocxReadException] of [reason]; returns it.
DocxReadException _refused(
  Uint8List bytes,
  DocxReadFailure reason, {
  DocxReadLimits limits = const DocxReadLimits(),
}) {
  Object? caught;
  try {
    final DocxPackage package = _open(bytes, limits: limits);
    package.guard(package.mainPart, () {
      final XmlPullReader reader = package.openXml(package.mainPart);
      // Text decodes lazily: an entity error surfaces only when read.
      final StringBuffer text = StringBuffer();
      while (reader.next()) {
        text.write(reader.text);
      }
      return text.toString();
    });
  } on Object catch (error) {
    caught = error;
  }
  expect(caught, isA<DocxReadException>(), reason: 'threw $caught');
  final DocxReadException e = caught! as DocxReadException;
  expect(e.reason, reason, reason: e.message);
  return e;
}

void main() {
  test('finds the main part through the root relationship wherever it '
      'lives', () {
    final DocxWarningCollector warnings = DocxWarningCollector();
    final DocxPackage package = _open(
      buildDocx(mainPath: 'custom/doc.xml'),
      warnings: warnings,
    );
    expect(package.mainPart, '/custom/doc.xml');
    expect(package.mainContentType, ContentType.wmlDocument);
    expect(package.package.hasPart('/custom/doc.xml'), isTrue);
    final XmlPullReader reader = package.openXml(package.mainPart);
    expect(reader.nextTag(), isTrue);
    expect(reader.localName, 'document');
    expect(reader.namespaceUri, Ns.w);
    expect(warnings.warnings, isEmpty);
  });

  test('accepts .docm, .dotx and .dotm main types', () {
    for (final String type in <String>[
      ContentType.wmlMacroDocument,
      ContentType.wmlTemplate,
      ContentType.wmlMacroTemplate,
    ]) {
      final DocxWarningCollector warnings = DocxWarningCollector();
      final DocxPackage package = _open(
        buildDocx(contentType: type),
        warnings: warnings,
      );
      expect(package.mainPart, '/word/document.xml');
      expect(package.mainContentType, type);
      expect(warnings.warnings, isEmpty, reason: type);
    }
  });

  test('refuses an XLSX with unsupportedFormat naming XLSX', () {
    for (final String type in <String>[
      ContentType.workbook,
      ContentType.smlMacroWorkbook,
      ContentType.smlTemplate,
      ContentType.smlMacroTemplate,
      ContentType.smlBinaryWorkbook,
    ]) {
      final DocxReadException e = _refused(
        buildDocx(mainPath: 'xl/workbook.xml', contentType: type),
        DocxReadFailure.unsupportedFormat,
      );
      expect(e.message, contains('XLSX'), reason: type);
      expect(e.message, isNot(contains('PPTX')), reason: type);
    }
  });

  test('refuses a PPTX with unsupportedFormat naming PPTX', () {
    for (final String type in <String>[
      ContentType.pmlPresentation,
      ContentType.pmlTemplate,
      ContentType.pmlSlideshow,
      ContentType.pmlMacroPresentation,
      ContentType.pmlMacroTemplate,
      ContentType.pmlMacroSlideshow,
    ]) {
      final DocxReadException e = _refused(
        buildDocx(mainPath: 'ppt/presentation.xml', contentType: type),
        DocxReadFailure.unsupportedFormat,
      );
      expect(e.message, contains('PPTX'), reason: type);
    }
  });

  test('refuses Strict with unsupportedFormat', () {
    final DocxReadException e = _refused(
      buildDocx(relType: RelType.officeDocumentStrict),
      DocxReadFailure.unsupportedFormat,
    );
    expect(e.message, contains('Strict'));
  });

  test('refuses a missing main part with missingDocument', () {
    final DocxReadException e = _refused(
      buildZip(<String, List<int>>{
        '[Content_Types].xml': utf8.encode('<Types xmlns="$contentTypesNs"/>'),
        'docs/readme.txt': utf8.encode('hi'),
      }),
      DocxReadFailure.missingDocument,
    );
    expect(e.part, isNull);
  });

  test('a root relationship to a missing main part throws missingDocument '
      'naming the part', () {
    final DocxReadException e = _refused(
      buildZip(
        docxEntries(rels: rootRels('word/document.xml'))
          ..remove('word/document.xml'),
      ),
      DocxReadFailure.missingDocument,
    );
    expect(e.part, '/word/document.xml');
  });

  test('refuses a CFB file with legacyDoc and an encrypted one with '
      'encrypted', () {
    final DocxReadException legacy = _refused(
      buildCfb(encrypted: false),
      DocxReadFailure.legacyDoc,
    );
    expect(
      legacy.message,
      'The file is a legacy Word document (.doc), not a DOCX; save it as a '
      'Word Document (.docx).',
    );
    final DocxReadException encrypted = _refused(
      buildCfb(encrypted: true),
      DocxReadFailure.encrypted,
    );
    expect(
      encrypted.message,
      'The file is an encrypted (password protected) Office file.',
    );
  });

  test('an encrypted ZIP entry is encrypted', () {
    final DocxReadException e = _refused(
      patchFlags(buildDocx(), 'word/document.xml', 1),
      DocxReadFailure.encrypted,
    );
    expect(
      e.message,
      'The file is an encrypted (password protected) Office file.',
    );
  });

  test('refuses a non-ZIP with notZip', () {
    _refused(Uint8List(0), DocxReadFailure.notZip);
    _refused(
      Uint8List.fromList(utf8.encode('{"not": "a document"}')),
      DocxReadFailure.notZip,
    );
  });

  test('a truncated ZIP is corruptZip', () {
    final Uint8List zip = buildDocx();
    _refused(
      Uint8List.sublistView(zip, 0, zip.length ~/ 2),
      DocxReadFailure.corruptZip,
    );
  });

  test('refuses a DTD with malformedXml', () {
    const String laughs =
        '<!DOCTYPE w:document [<!ENTITY a "aaaaaaaaaa">'
        '<!ENTITY b "&a;&a;&a;&a;&a;&a;&a;&a;&a;&a;">]>';
    final DocxReadException inDocument = _refused(
      buildDocx(document: '$laughs$minimalDocument'),
      DocxReadFailure.malformedXml,
    );
    expect(inDocument.part, '/word/document.xml');
    final DocxReadException inRels = _refused(
      buildDocx(rels: '$laughs${rootRels('word/document.xml')}'),
      DocxReadFailure.malformedXml,
    );
    expect(inRels.part, isNotNull);
  });

  test('names the part in an XML failure', () {
    // The entity error only surfaces while reading, inside guard.
    final DocxReadException e = _refused(
      buildDocx(
        mainPath: 'custom/doc.xml',
        document:
            '<w:document xmlns:w="${Ns.w}"><w:body><w:p><w:r><w:t>a &bogus; b'
            '</w:t></w:r></w:p></w:body></w:document>',
      ),
      DocxReadFailure.malformedXml,
    );
    expect(e.part, '/custom/doc.xml');
    expect(e.message, startsWith('The XML cannot be read: '));
  });

  test('a CRC mismatch in the main part is corruptZip naming it', () {
    final Uint8List zip = buildDocx(store: true);
    final int at = indexOfBytes(zip, utf8.encode('<w:body>'));
    expect(at, greaterThan(0));
    final DocxReadException e = _refused(
      Uint8List.fromList(zip)..[at + 1] = 0x5A,
      DocxReadFailure.corruptZip,
    );
    expect(e.part, '/word/document.xml');
  });

  test('warns contentTypeMissing for a main part without a type', () {
    final DocxWarningCollector warnings = DocxWarningCollector();
    final DocxPackage package = _open(
      buildDocx(contentType: null),
      warnings: warnings,
    );
    expect(package.mainPart, '/word/document.xml');
    expect(package.mainContentType, ContentType.wmlDocument);
    expect(warnings.warnings, hasLength(1));
    final DocxWarning w = warnings.warnings.single;
    expect(w.code, DocxWarningCode.contentTypeMissing);
    expect(w.part, '/word/document.xml');
    expect(w.detail, ContentType.wmlDocument);
  });

  test('warns mainPartContentTypeUnexpected for another type', () {
    final DocxWarningCollector warnings = DocxWarningCollector();
    final DocxPackage package = _open(
      buildDocx(contentType: 'application/xml'),
      warnings: warnings,
    );
    expect(package.mainContentType, ContentType.wmlDocument);
    final DocxWarning w = warnings.warnings.single;
    expect(w.code, DocxWarningCode.mainPartContentTypeUnexpected);
    expect(w.part, '/word/document.xml');
    expect(w.detail, 'application/xml');
  });

  test('openXml of a part the package lacks is a StateError', () {
    final DocxPackage package = _open(buildDocx());
    expect(() => package.openXml('/word/nothing.xml'), throwsStateError);
  });

  test('a malformed part read through guard throws DocxReadException, not '
      'OpcFormatException', () {
    final DocxPackage package = _open(
      buildDocx(
        extra: <String, List<int>>{
          'word/_rels/document.xml.rels': utf8.encode('<Relationships'),
        },
      ),
    );
    Object? caught;
    try {
      package.guard(
        '/word/_rels/document.xml.rels',
        () => package.package.relationshipsOf(package.mainPart),
      );
    } on Object catch (error) {
      caught = error;
    }
    expect(caught, isA<DocxReadException>(), reason: 'threw $caught');
    final DocxReadException e = caught! as DocxReadException;
    expect(e.reason, DocxReadFailure.malformedXml);
    expect(e.part, '/word/_rels/document.xml.rels');
  });

  test('DocxReadLimits has the XLSX defaults and refuses a value below 1', () {
    const DocxReadLimits limits = DocxReadLimits();
    expect(limits.maxEntries, 10000);
    expect(limits.maxEntryBytes, 256 * 1024 * 1024);
    expect(limits.maxTotalBytes, 1024 * 1024 * 1024);
    expect(limits.maxCompressionRatio, 1000);
    expect(limits.maxDepth, 256);
    expect(limits.maxTextLength, 1048576);
    limits.check();
    const DocxReadLimits(maxEntries: 1).check();
    expect(
      () => const DocxReadLimits(maxDepth: 0).check(),
      throwsA(
        isA<ArgumentError>().having(
          (ArgumentError e) => e.name,
          'name',
          'maxDepth',
        ),
      ),
    );
    expect(
      () => _open(buildDocx(), limits: const DocxReadLimits(maxTextLength: 0)),
      throwsArgumentError,
    );
  });

  test('a DocxReadException cleans, shortens and roots a part name', () {
    final DocxReadException e = DocxReadException(
      DocxReadFailure.corruptZip,
      'The ZIP archive is damaged: x.',
      part: 'word/${'x' * 300}\u0007.xml',
    );
    expect(e.part, startsWith('/word/'));
    expect(e.part, endsWith('…'));
    expect(e.part!.length, 257);
    expect(e.part, isNot(contains('\u0007')));
    expect(e.toString(), startsWith('DocxReadException(corruptZip, /word/'));
    expect(
      DocxReadException(
        DocxReadFailure.malformedXml,
        'm',
        part: 'a\u0007.xml',
      ).part,
      '/a\uFFFD.xml',
    );
  });

  group('limits', () {
    test('refuses entries past maxEntries before inflating', () {
      // The content types entry is stored with a broken CRC: reading it
      // would fail as corruptZip, so limitExceeded proves the count came
      // first, from the central directory alone.
      final Uint8List zip = buildZip(<String, List<int>>{
        ...docxEntries(),
        for (int i = 0; i < 8; i++) 'pad/e$i.xml': utf8.encode('<a/>'),
      }, store: true);
      final int at = indexOfBytes(zip, utf8.encode('<Types'));
      expect(at, greaterThan(0));
      final Uint8List broken = Uint8List.fromList(zip)..[at + 2] = 0x5A;
      _refused(broken, DocxReadFailure.corruptZip);
      final DocxReadException e = _refused(
        broken,
        DocxReadFailure.limitExceeded,
        limits: const DocxReadLimits(maxEntries: 10),
      );
      expect(e.message, contains('maxEntries'));
    });

    test('refuses an entry past maxEntryBytes', () {
      final DocxReadException e = _refused(
        patchDeclaredSize(buildDocx(), 'word/document.xml', 1 << 30),
        DocxReadFailure.limitExceeded,
      );
      expect(e.message, contains('maxEntryBytes'));
      expect(e.part, '/word/document.xml');
    });

    test('refuses entries past maxTotalBytes', () {
      final DocxReadException e = _refused(
        buildDocx(
          extra: <String, List<int>>{
            for (int i = 0; i < 3; i++)
              'word/pad$i.bin': List<int>.generate(
                1000,
                (int k) => (k * 7) % 256,
              ),
          },
        ),
        DocxReadFailure.limitExceeded,
        limits: const DocxReadLimits(maxTotalBytes: 2500),
      );
      expect(e.message, contains('maxTotalBytes'));
    });

    test('refuses a ratio past maxCompressionRatio', () {
      final DocxReadException e = _refused(
        buildDocx(
          extra: <String, List<int>>{
            'word/pad.bin': List<int>.filled(2 * 1024 * 1024, 65),
          },
        ),
        DocxReadFailure.limitExceeded,
        limits: const DocxReadLimits(maxCompressionRatio: 100),
      );
      expect(e.message, contains('maxCompressionRatio'));
    });

    test('refuses XML nested past maxDepth', () {
      final DocxReadException e = _refused(
        buildDocx(
          document:
              '<w:document xmlns:w="${Ns.w}"><w:body>'
              '${'<w:p>' * 20}${'</w:p>' * 20}</w:body></w:document>',
        ),
        DocxReadFailure.limitExceeded,
        limits: const DocxReadLimits(maxDepth: 10),
      );
      expect(e.message, contains('maxDepth (10)'));
      expect(e.part, '/word/document.xml');
    });
  });

  test('no DOCX failure message mentions xls, xlsx as advice, or Excel', () {
    final Uint8List zip = buildDocx(store: true);
    final int body = indexOfBytes(zip, utf8.encode('<w:body>'));
    final List<(DocxReadFailure, Uint8List, DocxReadLimits)> inputs =
        <(DocxReadFailure, Uint8List, DocxReadLimits)>[
          (DocxReadFailure.notZip, Uint8List(0), const DocxReadLimits()),
          (
            DocxReadFailure.corruptZip,
            Uint8List.fromList(zip)..[body + 1] = 0x5A,
            const DocxReadLimits(),
          ),
          (
            DocxReadFailure.encrypted,
            buildCfb(encrypted: true),
            const DocxReadLimits(),
          ),
          (
            DocxReadFailure.encrypted,
            patchFlags(buildDocx(), 'word/document.xml', 1),
            const DocxReadLimits(),
          ),
          (
            DocxReadFailure.legacyDoc,
            buildCfb(encrypted: false),
            const DocxReadLimits(),
          ),
          for (final String type in <String>[
            ContentType.workbook,
            ContentType.smlMacroWorkbook,
            ContentType.smlBinaryWorkbook,
            ContentType.pmlPresentation,
          ])
            (
              DocxReadFailure.unsupportedFormat,
              buildDocx(mainPath: 'x/main.xml', contentType: type),
              const DocxReadLimits(),
            ),
          (
            DocxReadFailure.unsupportedFormat,
            buildDocx(relType: RelType.officeDocumentStrict),
            const DocxReadLimits(),
          ),
          (
            DocxReadFailure.missingDocument,
            buildZip(docxEntries()..remove('word/document.xml')),
            const DocxReadLimits(),
          ),
          (
            DocxReadFailure.missingDocument,
            buildZip(<String, List<int>>{'a.txt': utf8.encode('a')}),
            const DocxReadLimits(),
          ),
          (
            DocxReadFailure.malformedXml,
            buildDocx(document: '<w:document'),
            const DocxReadLimits(),
          ),
          (
            DocxReadFailure.limitExceeded,
            buildDocx(),
            const DocxReadLimits(maxEntries: 1),
          ),
          (
            DocxReadFailure.limitExceeded,
            patchDeclaredSize(buildDocx(), 'word/document.xml', 1 << 30),
            const DocxReadLimits(),
          ),
          (
            DocxReadFailure.limitExceeded,
            buildDocx(),
            const DocxReadLimits(maxDepth: 1),
          ),
        ];
    expect(
      <DocxReadFailure>{
        for (final (DocxReadFailure reason, _, _) in inputs) reason,
      },
      DocxReadFailure.values.toSet(),
      reason: 'every failure needs an input here',
    );
    for (final (DocxReadFailure reason, Uint8List bytes, DocxReadLimits limits)
        in inputs) {
      final String message = _refused(
        bytes,
        reason,
        limits: limits,
      ).message.toLowerCase();
      expect(message, isNot(contains('.xls')), reason: message);
      expect(message, isNot(contains('excel')), reason: message);
    }
  });
}
