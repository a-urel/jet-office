// Tests the owner DOCX manifest format (test/support/owner_docx.dart): what
// it accepts, what it refuses, and the directory rules. Web-safe: no files.
library;

import 'package:test/test.dart';

import '../support/owner_docx.dart';

void main() {
  group('parseOwnerDocxManifest', () {
    test('reads a draft and a confirmed entry', () {
      final List<OwnerDocx> entries = parseOwnerDocxManifest('''
[
  {"file": "a.docx", "producer": "", "confirmedBy": null},
  {"file": "b.docx", "producer": "Microsoft Word for Mac 16.114.1",
   "confirmedBy": "owner"}
]''');
      expect(entries, hasLength(2));
      expect(entries[0].file, 'a.docx');
      expect(entries[0].confirmed, isFalse);
      expect(entries[1].producer, 'Microsoft Word for Mac 16.114.1');
      expect(entries[1].confirmed, isTrue);
    });

    test('refuses what is not a list of objects', () {
      expect(
        () => parseOwnerDocxManifest('{}'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => parseOwnerDocxManifest('["a.docx"]'),
        throwsA(
          isA<FormatException>().having(
            (FormatException e) => e.message,
            'message',
            contains('[0]'),
          ),
        ),
      );
    });

    test('refuses a confirmedBy that is not exactly "owner"', () {
      expect(
        () => parseOwnerDocxManifest(
          '[{"file": "a.docx", "producer": "Word", "confirmedBy": "me"}]',
        ),
        throwsA(
          isA<FormatException>().having(
            (FormatException e) => e.message,
            'message',
            contains('[0].confirmedBy'),
          ),
        ),
      );
    });

    test('refuses a confirmed entry with an empty producer', () {
      expect(
        () => parseOwnerDocxManifest(
          '[{"file": "a.docx", "producer": "", "confirmedBy": "owner"}]',
        ),
        throwsA(
          isA<FormatException>().having(
            (FormatException e) => e.message,
            'message',
            contains('[0].producer'),
          ),
        ),
      );
    });

    test('refuses a file that is not a .docx name, and unknown keys', () {
      expect(
        () => parseOwnerDocxManifest(
          '[{"file": "dir/a.docx", "producer": "", "confirmedBy": null}]',
        ),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => parseOwnerDocxManifest(
          '[{"file": "a.doc", "producer": "", "confirmedBy": null}]',
        ),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => parseOwnerDocxManifest(
          '[{"file": "a.docx", "producer": "", "confirmedBy": null, '
          '"text": "x"}]',
        ),
        throwsA(
          isA<FormatException>().having(
            (FormatException e) => e.message,
            'message',
            contains('[0].text'),
          ),
        ),
      );
    });
  });

  group('ownerDocxDirectoryProblems', () {
    List<OwnerDocx> listed(List<String> files) => <OwnerDocx>[
      for (final String f in files) OwnerDocx(f, '', null),
    ];

    test(
      'a listed file with its text is fine; Word lock files are ignored',
      () {
        expect(
          ownerDocxDirectoryProblems(<String>[
            'manifest.json',
            'a.docx',
            'a.expected.txt',
            r'~$a.docx',
          ], listed(<String>['a.docx'])),
          isEmpty,
        );
      },
    );

    test('reports unlisted, missing, partnerless and stray files', () {
      expect(
        ownerDocxDirectoryProblems(<String>[
          'manifest.json',
          'a.docx',
          'b.docx',
          'b.expected.txt',
          'c.expected.txt',
          'notes.md',
        ], listed(<String>['b.docx', 'd.docx', 'b.docx'])),
        <String>[
          'manifest.json: "d.docx" is not in the directory',
          'manifest.json: "b.docx" is listed twice',
          'a.docx is not in manifest.json',
          'a.docx has no a.expected.txt',
          'c.expected.txt has no c.docx',
          'notes.md does not belong here',
        ],
      );
    });
  });
}
