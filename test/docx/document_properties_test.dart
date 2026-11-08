// Tests of `DocxDocument.properties` (plan Rulings 3 and 4): read lazily from
// the parts the root relationships name, kept as read until set, added at save
// only when set, and a value that cannot be read reported once. They build
// every file in memory, so they run on the web as well; the owner's blank
// file is read in `document_properties_owner_test.dart`.
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/docx/docx_document.dart';
import 'package:jet_office/src/opc/change_log.dart' show ChangeSet;
import 'package:test/test.dart';

import '../../tool/src/part_compare.dart';

/// The parts of the ZIP [bytes] as text, by entry name.
Map<String, String> _parts(Uint8List bytes) => <String, String>{
  for (final ArchiveFile file in ZipDecoder().decodeBytes(bytes).files)
    if (file.isFile) file.name: utf8.decode(file.content),
};

/// The ZIP of [parts], in the order given.
Uint8List _zip(Map<String, String> parts) {
  final Archive archive = Archive();
  parts.forEach((String name, String text) {
    final List<int> data = utf8.encode(text);
    archive.addFile(ArchiveFile(name, data.length, data));
  });
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

/// A document with core and app properties, as a model save writes them.
Uint8List _withProperties() {
  final DocxDocument doc = DocxDocument();
  doc.properties = const OfficeProperties(
    title: 'Title',
    creator: 'Ahmet',
    revision: 3,
    application: 'Tester',
    company: 'Acme',
  );
  return doc.save().bytes;
}

/// [p] with the title [title].
OfficeProperties _retitled(OfficeProperties p, String title) =>
    OfficeProperties(
      title: title,
      creator: p.creator,
      revision: p.revision,
      application: p.application,
      company: p.company,
    );

DocxDocument _reopen(Map<String, String> parts) =>
    DocxDocument.open(_zip(parts));

void main() {
  group('reading', () {
    test('a new document reads empty properties and saves no docProps', () {
      final DocxDocument doc = DocxDocument();
      expect(doc.properties, const OfficeProperties());
      final Map<String, String> saved = _parts(doc.save().bytes);
      expect(saved.keys.where((String k) => k.startsWith('docProps')), isEmpty);
      expect(saved['_rels/.rels'], isNot(contains('docProps')));
      expect(saved['[Content_Types].xml'], isNot(contains('docProps')));
      expect(doc.save().warnings, isEmpty);
    });

    test('reads the typed values of core and app', () {
      final OfficeProperties p = DocxDocument.open(
        _withProperties(),
      ).properties;
      expect(p.title, 'Title');
      expect(p.creator, 'Ahmet');
      expect(p.revision, 3);
      expect(p.application, 'Tester');
      expect(p.company, 'Acme');
    });

    test('a part is found by its root relationship, not its name', () {
      final Map<String, String> parts = _parts(_withProperties());
      final String core = parts.remove('docProps/core.xml')!;
      parts['docProps/other.xml'] = core;
      parts['_rels/.rels'] = parts['_rels/.rels']!.replaceAll(
        'docProps/core.xml',
        'docProps/other.xml',
      );
      parts['[Content_Types].xml'] = parts['[Content_Types].xml']!.replaceAll(
        '/docProps/core.xml',
        '/docProps/other.xml',
      );
      expect(_reopen(parts).properties.title, 'Title');
    });

    test('a part that is not XML throws from properties, not from open', () {
      final Map<String, String> parts = _parts(_withProperties());
      parts['docProps/core.xml'] = '<cp:core';
      final DocxDocument doc = _reopen(parts);
      expect(() => doc.properties, throwsA(isA<DocxReadException>()));
      expect(doc.body.blocks, isNotEmpty);
    });

    test('a value that cannot be read reads null, is kept and warns once', () {
      final Map<String, String> parts = _parts(_withProperties());
      parts['docProps/core.xml'] = parts['docProps/core.xml']!.replaceFirst(
        '<cp:revision>3</cp:revision>',
        '<cp:revision>x</cp:revision>',
      );
      final DocxDocument doc = _reopen(parts);
      expect(doc.properties.revision, isNull);
      expect(doc.properties.title, 'Title');
      for (int i = 0; i < 2; i++) {
        final List<DocxWarning> warnings = doc
            .save()
            .warnings
            .where(
              (DocxWarning w) => w.code == DocxWarningCode.propertyValueInvalid,
            )
            .toList();
        expect(warnings, hasLength(1));
        expect(warnings.single.detail, 'cp:revision');
        expect(warnings.single.part, '/docProps/core.xml');
        expect(warnings.single.count, 1);
      }
      expect(
        _parts(doc.save().bytes)['docProps/core.xml'],
        parts['docProps/core.xml'],
      );
    });
  });

  group('saving', () {
    test('an opened file saved unchanged after reading is byte equal', () {
      final Uint8List input = _withProperties();
      final DocxDocument doc = DocxDocument.open(input);
      doc.properties;
      expect(_parts(doc.save().bytes), _parts(input));
      expect(comparePackages(input, doc.save().bytes), isEmpty);
    });

    test('setting title changes only that child of core.xml', () {
      final Uint8List input = _withProperties();
      final DocxDocument doc = DocxDocument.open(input);
      doc.properties = _retitled(doc.properties, 'Other');
      final Map<String, String> before = _parts(input);
      final Map<String, String> after = _parts(doc.save().bytes);
      expect(after['docProps/app.xml'], before['docProps/app.xml']);
      expect(
        after['docProps/core.xml'],
        before['docProps/core.xml']!.replaceFirst('>Title<', '>Other<'),
      );
      expect(DocxDocument.open(doc.save().bytes).properties.title, 'Other');
    });

    test('a new document with properties set gets core and app', () {
      final DocxDocument doc = DocxDocument();
      doc.properties = const OfficeProperties(title: 'T', company: 'C');
      final Uint8List bytes = doc.save().bytes;
      final Map<String, String> parts = _parts(bytes);
      expect(parts['docProps/core.xml'], contains('<dc:title>T</dc:title>'));
      expect(parts['docProps/app.xml'], contains('<Company>C</Company>'));
      expect(parts['_rels/.rels'], contains('docProps/core.xml'));
      expect(parts['_rels/.rels'], contains('docProps/app.xml'));
      expect(parts['[Content_Types].xml'], contains('/docProps/core.xml'));
      expect(parts['[Content_Types].xml'], contains('/docProps/app.xml'));
      final DocxDocument back = DocxDocument.open(bytes);
      expect(back.properties.title, 'T');
      expect(back.properties.company, 'C');
      expect(back.warnings, isEmpty);
      expect(back.save().warnings, isEmpty);
      expect(comparePackages(bytes, back.save().bytes), isEmpty);
    });

    test('custom properties are read and set', () {
      final DocxDocument doc = DocxDocument();
      doc.properties = const OfficeProperties(
        custom: <String, Object>{'Project': 'Alpha', 'Count': 4},
      );
      final DocxDocument back = DocxDocument.open(doc.save().bytes);
      expect(back.properties.custom, <String, Object>{
        'Project': 'Alpha',
        'Count': 4,
      });
    });

    test('a bad value throws and changes nothing', () {
      final DocxDocument doc = DocxDocument();
      expect(
        () => doc.properties = const OfficeProperties(revision: -1),
        throwsArgumentError,
      );
      expect(doc.properties, const OfficeProperties());
      expect(
        _parts(
          doc.save().bytes,
        ).keys.where((String k) => k.startsWith('docProps')),
        isEmpty,
      );
    });

    // Found by fuzzing (seed 1 case 617): a core part whose root is in
    // another namespace read empty, and setting a value it holds threw a
    // StateError, which no file may cause.
    test('a part whose root is not a properties part throws a read '
        'exception naming it when a value of it is set', () {
      final Map<String, String> parts = _parts(_withProperties());
      parts['docProps/core.xml'] = parts['docProps/core.xml']!.replaceFirst(
        'xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/'
            'core-properties"',
        'xmlns:cp="urn:other"',
      );
      final DocxDocument doc = _reopen(parts);
      final OfficeProperties read = doc.properties;
      expect(read.title, isNull);
      expect(read.company, 'Acme');
      expect(
        () => doc.properties = _retitled(read, 'New'),
        throwsA(
          isA<DocxReadException>()
              .having(
                (DocxReadException e) => e.reason,
                'reason',
                DocxReadFailure.malformedXml,
              )
              .having(
                (DocxReadException e) => e.part,
                'part',
                '/docProps/core.xml',
              ),
        ),
      );
      expect(
        () => doc.properties = const OfficeProperties(revision: -1),
        throwsArgumentError,
      );
      // A value of a part that is typed still changes.
      doc.properties = OfficeProperties(
        application: read.application,
        company: 'Other',
      );
      expect(doc.properties.company, 'Other');
      final Map<String, String> saved = _parts(doc.save().bytes);
      expect(saved['docProps/core.xml'], parts['docProps/core.xml']);
    });

    test('a transaction that throws leaves no part and no relationship', () {
      final DocxDocument doc = DocxDocument();
      expect(
        () => changeLogOf(doc).transaction(() {
          doc.properties = const OfficeProperties(title: 'T');
          throw StateError('boom');
        }),
        throwsStateError,
      );
      expect(doc.properties, const OfficeProperties());
      final Map<String, String> saved = _parts(doc.save().bytes);
      expect(saved.keys.where((String k) => k.startsWith('docProps')), isEmpty);
      expect(saved['_rels/.rels'], isNot(contains('docProps')));
    });

    test('an undo leaves no part and no relationship, a redo brings them', () {
      final DocxDocument doc = DocxDocument();
      final ChangeSet set = changeLogOf(
        doc,
      ).transaction(() => doc.properties = const OfficeProperties(title: 'T'));
      changeLogOf(doc).revertSet(set);
      expect(doc.properties, const OfficeProperties());
      final Map<String, String> saved = _parts(doc.save().bytes);
      expect(saved.keys.where((String k) => k.startsWith('docProps')), isEmpty);
      expect(saved['_rels/.rels'], isNot(contains('docProps')));
      expect(saved['[Content_Types].xml'], isNot(contains('docProps')));

      changeLogOf(doc).reapplySet(set);
      expect(
        _parts(doc.save().bytes)['docProps/core.xml'],
        contains('<dc:title>T</dc:title>'),
      );
    });

    test('the undo of a change to an opened file restores its bytes', () {
      final Uint8List input = _withProperties();
      final DocxDocument doc = DocxDocument.open(input);
      final ChangeSet set = changeLogOf(
        doc,
      ).transaction(() => doc.properties = _retitled(doc.properties, 'Other'));
      changeLogOf(doc).revertSet(set);
      final Map<String, String> before = _parts(input);
      final Map<String, String> after = _parts(doc.save().bytes);
      expect(after['docProps/core.xml'], before['docProps/core.xml']);
      expect(after['docProps/app.xml'], before['docProps/app.xml']);
    });
  });
}
