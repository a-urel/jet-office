# 0013 — One repository: a pub workspace, with jet_core under packages/

**Status:** Accepted — 2026-11-06

## Context

[`0012`](0012-jet-core-and-new-dependencies.md) moved the number format engine
to `jet_core`, in a repository of its own, used through a git dependency pinned
to a commit. `jet_core`'s own record (`packages/jet_core/docs/decisions/0001`)
says the same, and the jet_charts design planned a further repository for the
charts.

These packages have one developer and change together. With separate
repositories a breaking change in `jet_core` takes a push, a moved `ref` and a
second commit, and a consumer's break shows only when the `ref` moves. The owner
decided to keep them in one repository, the day `jet_core` was split out and
before any chart code existed, when moving costs least.

## Decision

**This repository is a pub workspace. `jet_office` stays at its root and
`jet_core` is `packages/jet_core`, with its history. The chart packages
(`jet_charts_core`, `jet_charts_flutter`) go under `packages/` too. This
supersedes the repository and dependency form of `0012` and of `jet_core`'s
`0001`, and the separate repositories of the jet_charts design.**

- **`jet_office` does not move.** A workspace root may be a package, so its
  paths, tools and open work stay as they are. Moving it under `packages/` is
  possible later and is not needed now.
- **Dependency form.** `jet_core: {path: packages/jet_core}`. Nothing pins a
  commit, and a change and its consumers land together.
- **The rules between packages do not change.** `jet_core` has no runtime
  dependency, knows no file format and may not import `jet_office`; its rule
  for what it may hold stands. Each package keeps its own `AGENTS.md`, tests
  and `docs/`.
- **The gate covers both.** `dart format` and `dart analyze` at the root see
  every package; `dart test` runs per package, so `jet_core`'s tests are added
  to the gate and to CI.
- **Outside users take one package** with a git dependency and
  `path: packages/jet_core`. Publishing is still undecided.
- **A repository is not a package's scope.** `jet_office` itself stays files
  only ([`0001`](0001-port-a-file-engine-from-quds.md)). A later package, such
  as a Flutter widget, is a package of its own here, decided when a real screen
  asks for it.

## Consequences

- **A workspace has one resolution.** A Flutter package in it brings Flutter's
  pinned versions to every package. `jet_charts_flutter` must try this first; if
  the pins hurt, it stays in this repository but outside the workspace.
- **`jet_core`'s oracle workbooks keep their tool-local writer**, though
  `jet_office`'s writer is now close by: `jet_core` may not depend on it.
- **The `a-urel/jet-core` GitHub repository is left over.** Nothing depends on it
  once this merges; archiving it is the owner's call.
- CI runs both packages on every change. A path filter for the heavy `validate`
  job waits until the charts make that worth it.
