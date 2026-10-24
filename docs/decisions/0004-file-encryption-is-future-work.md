# 0004 — File encryption is future work, not excluded forever

**Status:** Accepted — 2026-10-24

## Context

[`0001`](0001-port-a-file-engine-from-quds.md) put encryption out of scope
("no macros, no encryption"). [`0003`](0003-phase-1-scope-output-and-diagnostics.md)
went further and listed "Macros and encryption, ever" under what phase 1
leaves out. That made encryption a permanent exclusion.

The owner wants password-protected files to stay possible. Consumers export
data that can be sensitive (current accounts, bank statements), and a
password to open the file is the protection Excel and Word users know.

File-level Office encryption is MS-OFFCRYPTO. The clear OPC ZIP is encrypted
and stored as the `EncryptedPackage` stream, next to an `EncryptionInfo`
stream, inside an OLE compound file (CFB). Excel 2010 introduced the Agile
form, and Excel 2013 and later write it with AES-256 and SHA-512 key
derivation. Excel 2007 wrote the older Standard form, which a reader may still
meet.

Quds already has this, measured at commit `15c5d29`:

| Quds file | Lines |
|---|---:|
| `opc/crypto/office_crypto.dart` (Agile and Standard, encrypt and decrypt) | 727 |
| `crypto/aes.dart` (pure-Dart AES) | 925 |
| `opc/ole/cfbf_writer.dart`, `opc/ole/cfbf_reader.dart` | 1,125 |

It imports `package:crypto` for SHA-1 and SHA-512. That package is pure Dart
and web-safe, but it would be a second runtime dependency next to `archive`.

## Decision

**File encryption is future work. It is not part of phase 1, and it is no
longer excluded forever. This record supersedes the encryption exclusion in
0001 and 0003.**

- **Encryption is not in phase 1.** The phase-1 scope stays M1 to M5 as 0003
  defines it.
- **When it is built, it is a password to open the file.** It wraps the
  finished XLSX or DOCX bytes. It does not change the writer: encryption takes
  the clear package as bytes and returns the encrypted file as bytes.
- **It stays pure Dart and web-safe.** The hard rules in `AGENTS.md` apply to
  it unchanged.
- **Macros stay excluded forever.** 0003's exclusion of macros is unchanged.

## Consequences

**Encryption needs a later decision record before any code.** That record
fixes the phase, the API, and the dependency question below.

**A crypto dependency may come with it.** If `package:crypto` is adopted, it
also removes the reason 0003 gave for not deciding SHA-512 sheet and workbook
protection.

**Output stays a ZIP until then.** Nothing in phase 1 writes a CFB file.

## What this does not decide

- **Which phase builds it**, and whether reading encrypted files (phase 3)
  comes before or with writing them.
- **Agile only, or Standard too.** Writing Agile is enough for the target
  readers in 0003. Reading may need both.
- **Whether to add `package:crypto` or port Quds' hashing.** Either way, the
  isolation rule for `archive` is a model for keeping the dependency in one
  file.
- **How the CFB writer is ported.** It is ported, not copied, under the same
  rules as every other Quds file.
