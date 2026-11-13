#!/usr/bin/env bash
# Runs the quality gate of AGENTS.md ("The quality gate") from the
# repository root: every leg, in order, even after one fails. Prints
# `== FAILED: <command>` for each failed leg and a summary, and exits 1
# when any leg failed. test/tool/gate_script_test.dart keeps the legs equal
# to AGENTS.md's.
#
# Before each leg it runs `flutter --version`. Flutter's launcher
# (bin/internal/shared.sh) deletes bin/cache/flutter.version.json whenever
# its tool stamp does not match, for instance when another process runs
# Flutter's `dart` while git cannot read the SDK, and only the next
# `flutter` command writes the file back. Until then `dart test` cannot
# tell Flutter's SDK is there, re-resolves the workspace and fails with
# "Because jet_charts_gallery requires the Flutter SDK, version solving
# failed." `flutter --version` writes the file back, so the gate does not
# depend on what another process did to the shared SDK.
set -u
cd "$(dirname "$0")/.."

failed=()

leg() {
  local command="$1"
  echo "== $command"
  flutter --version >/dev/null 2>&1 || true
  if bash -c "$command"; then
    echo "== ok: $command"
  else
    echo "== FAILED: $command"
    failed+=("$command")
  fi
}

leg 'dart format --output=none --set-exit-if-changed .'
leg 'dart analyze --fatal-infos'
leg 'dart test'
leg 'dart test -p chrome'
leg '(cd packages/jet_core && dart test && dart test -p chrome)'
leg '(cd packages/jet_charts_core && dart test && dart test -p chrome)'
leg '(cd packages/jet_charts_flutter && flutter test && flutter test --platform chrome --exclude-tags golden)'
leg '(cd packages/jet_charts_flutter/example && flutter test)'

if [ "${#failed[@]}" -gt 0 ]; then
  echo "== gate failed: ${#failed[@]} leg(s)"
  for command in "${failed[@]}"; do
    echo "   $command"
  done
  exit 1
fi
echo "== gate passed"
