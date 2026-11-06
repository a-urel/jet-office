// The list definitions of the helpers against the owner's `builtins.docx`,
// saved by Word for Mac 16.114 on a Turkish system: each equals the file's
// abstract definition (the bullets and the numbers) once the identifiers of
// plan Ruling 9 are removed. VM only: it reads the fixture from disk.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:jet_office/src/docx/builtin_numbering.dart';
import 'package:test/test.dart';

import '../../tool/src/part_compare.dart';

const String _fixture = 'test/fixtures/owner/docx/builtins.docx';

/// [element] without the identifiers.
String _cleaned(String element) => element
    .replaceAll(RegExp(r' w:abstractNumId="[^"]*"'), '')
    .replaceAll(RegExp(r' w15:restartNumberingAfterBreak="[^"]*"'), '')
    .replaceAll(RegExp(r'<w:nsid [^>]*/>'), '')
    .replaceAll(RegExp(r'<w:tmpl [^>]*/>'), '')
    .replaceAll(RegExp(r' w:tplc="[^"]*"'), '');

Uint8List _bytes(String xml) => Uint8List.fromList(utf8.encode(xml));

void main() {
  test('the definitions equal builtins.docx without the identifiers', () {
    final ArchiveFile part = ZipDecoder()
        .decodeBytes(File(_fixture).readAsBytesSync())
        .files
        .firstWhere((ArchiveFile f) => f.name == 'word/numbering.xml');
    final List<String> found = <String>[
      for (final RegExpMatch m in RegExp(
        r'<w:abstractNum .*?</w:abstractNum>',
        dotAll: true,
      ).allMatches(utf8.decode(part.content)))
        m.group(0)!,
    ];
    expect(found, hasLength(2));
    final String bullets = found.singleWhere(
      (String x) => x.contains('bullet'),
    );
    final String numbers = found.singleWhere(
      (String x) => !x.contains('bullet'),
    );
    String wrapped(String xml) => xml.replaceFirst(
      '<w:abstractNum',
      '<w:abstractNum xmlns:w="http://schemas.openxmlformats.org/'
          'wordprocessingml/2006/main"',
    );
    expect(
      compareXmlParts(
        'bullets',
        _bytes(wrapped(_cleaned(bullets))),
        _bytes(wrapped(bulletAbstractXml)),
      ),
      isEmpty,
    );
    expect(
      compareXmlParts(
        'numbers',
        _bytes(wrapped(_cleaned(numbers))),
        _bytes(wrapped(numberedAbstractXml)),
      ),
      isEmpty,
    );
  });
}
