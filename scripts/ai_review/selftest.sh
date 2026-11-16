#!/usr/bin/env bash
# Self-test for scripts/ai_review.sh. Every case runs the script inside a throwaway git
# repository with fake providers: no network, no real codex, copilot or claude CLI.
#
#   scripts/ai_review/selftest.sh        # prints PASS/FAIL per check, exits 0 only if all pass
#
# The script under test runs as /bin/bash (macOS: bash 3.2) where that exists, or as
# $AI_REVIEW_TEST_BASH when set (run it once more with a current bash, e.g.
# AI_REVIEW_TEST_BASH=/opt/homebrew/bin/bash scripts/ai_review/selftest.sh).
# Two fake mechanisms:
#   - the test hook AI_REVIEW_BIN_<PROVIDER>: the script calls "$BIN <prompt-file>" from the
#     repository root. Every case starts with all three hooks pointing at a missing file, so a
#     case that forgets to fake a provider sees skipped:not-installed, never a live call;
#   - PATH shims named codex, copilot and claude, with PATH cut down to the shim directory and
#     the system directories, so the real command lines (and their hermetic flags) are
#     exercised without any real CLI being reachable.
set -uo pipefail
export LC_ALL=C
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$(cd "$HERE/.." && pwd)/ai_review.sh"
if [ -n "${AI_REVIEW_TEST_BASH:-}" ]; then BASH_BIN="$AI_REVIEW_TEST_BASH"; elif [ -x /bin/bash ]; then BASH_BIN=/bin/bash; else BASH_BIN=bash; fi
SYS_PATH="/usr/bin:/bin:/usr/sbin:/sbin"
TODAY=$(date +%Y-%m-%d)
pass=0; failn=0
T=$(mktemp -d "${TMPDIR:-/tmp}/ai_review_selftest.XXXXXX"); trap 'rm -rf "$T"' EXIT
T="$(cd "$T" && pwd -P)"
FAKES="$T/fakes"; mkdir -p "$FAKES"
export TMPDIR="$T/tmp"; mkdir -p "$TMPDIR"   # the script's run directories stay inside this test's own directory
export COPILOT_HOME="$T/copilot-home-empty"; mkdir -p "$COPILOT_HOME"

# The repository's config block, read from the script itself: every fixture below is built from
# it, so this self-test passes in any repository after only that block is edited.
sed -n '/^# >>> ai_review config/,/^# <<< ai_review config/p' "$SCRIPT" > "$T/config.sh"
# shellcheck disable=SC1091
. "$T/config.sh"
if [ -z "${REVIEWS_REL:-}" ] || [ -z "${PROTECTED_BRANCHES:-}" ] || [ -z "${ORIENTATION:-}" ]; then
  echo "selftest: no usable config block in $SCRIPT"; exit 1
fi
FIRST_PROTECTED="${PROTECTED_BRANCHES%% *}"
FIXTURE_BRANCH="review-fixture-work"
slug_of() { local s="$1" pre; for pre in $SLUG_STRIP; do s="${s#"$pre"}"; done; s="${s%.md}"; printf '%s' "$s" | tr '/ ' '--'; }
orientation_paths() { local IFS='|' e; for e in $ORIENTATION; do printf '%s\n' "${e%%:*}"; done; }

# ---- helpers -------------------------------------------------------------------------------
reset_fakes() {  # every provider points at a missing binary: an unfaked provider is never a live call
  export AI_REVIEW_BIN_CODEX="$FAKES/absent" AI_REVIEW_BIN_COPILOT="$FAKES/absent" AI_REVIEW_BIN_CLAUDE="$FAKES/absent"
  unset AI_REVIEW_COPILOT_MODEL AI_REVIEW_CLAUDE_MODEL AI_REVIEW_CODEX_MODEL
}
mkfake() {  # $1 provider, $2 bash body of the fake ($1 inside it is the prompt file)
  local f="$FAKES/$1-$RANDOM$RANDOM"
  printf '#!/usr/bin/env bash\n%s\n' "$2" > "$f"; chmod +x "$f"
  case "$1" in
    codex)   export AI_REVIEW_BIN_CODEX="$f" ;;
    copilot) export AI_REVIEW_BIN_COPILOT="$f" ;;
    claude)  export AI_REVIEW_BIN_CLAUDE="$f" ;;
  esac
}
FINDINGS3='F1 [major] Intent
claim: a
evidence: b
fix: c
F2 [minor] Decisions
claim: d
evidence: e
fix: f
F3 [hunch] Acceptance
claim: g
evidence: not checked
fix: h
VERDICT: revise — three things'
printf '%s\n' "$FINDINGS3" > "$FAKES/findings3.txt"
fake_ok() { mkfake "$1" "cat '$FAKES/findings3.txt'"; }

fixture_repo() {  # $1 dir: a repository with the orientation files and one spec
  local r="$1"
  local o
  mkdir -p "$r/docs/superpowers/specs" "$r/docs/superpowers/plans" "$r/sub" "$r/ignored" "$r/private"
  printf '# AGENTS\n' > "$r/AGENTS.md"
  while IFS= read -r o; do mkdir -p "$r/$(dirname "$o")"; printf '# %s\n' "$o" > "$r/$o"; done <<< "$(orientation_paths)"
  printf '# X design\n\n## Intent\n' > "$r/docs/superpowers/specs/x-design.md"
  printf '# X plan\n' > "$r/docs/superpowers/plans/x.md"
  printf '# Race plan\n' > "$r/docs/superpowers/plans/race.md"
  printf '# Burst plan\n' > "$r/docs/superpowers/plans/burst.md"
  printf 'not markdown\n' > "$r/notes.txt"
  printf 'ignored/\nprivate/\nprivate-reviews/\n' > "$r/.gitignore"
  [ -z "$IGNORED_REVIEWS_REL" ] || printf '%s/\n' "$IGNORED_REVIEWS_REL" >> "$r/.gitignore"
  git -C "$r" init -q -b "$FIXTURE_BRANCH"
  git -C "$r" -c user.email=t@t -c user.name=t add -A
  git -C "$r" -c user.email=t@t -c user.name=t commit -qm base
  git -C "$r" branch "$FIRST_PROTECTED"
  printf 'cache-1\n' > "$r/ignored/cache.txt"      # git-ignored, exists before every run
  printf 'scratch-1\n' > "$r/scratch.txt"          # untracked, exists before every run
}

OUT=""; RC=0
run_in() {  # $1 directory to run from, rest: script arguments. Captures stdout+stderr in OUT, exit code in RC.
  local d="$1"; shift
  OUT=$(cd "$d" && "$BASH_BIN" "$SCRIPT" "$@" 2>&1); RC=$?
}
ok()  { echo "PASS $1"; pass=$((pass + 1)); }
bad() { echo "FAIL $1: $2"; printf '%s\n' "$OUT" | sed 's/^/    | /'; failn=$((failn + 1)); }
expect_rc()     { if [ "$RC" -eq "$2" ]; then ok "$1"; else bad "$1" "wanted rc=$2, got rc=$RC"; fi; }
expect_file()   { if [ -f "$2" ]; then ok "$1"; else bad "$1" "missing file $2"; fi; }
expect_nofile() { if [ ! -e "$2" ]; then ok "$1"; else bad "$1" "unexpected path $2"; fi; }
expect_grep()   { if grep -qE -- "$2" "$3" 2>/dev/null; then ok "$1"; else bad "$1" "pattern '$2' not in $3"; fi; }
expect_absent() { if grep -qE -- "$2" "$3" 2>/dev/null; then bad "$1" "pattern '$2' found in $3"; else ok "$1"; fi; }
expect_out()    { if grep -qE -- "$2" <<< "$OUT"; then ok "$1"; else bad "$1" "pattern '$2' not in output"; fi; }
expect_noout()  { if grep -qE -- "$2" <<< "$OUT"; then bad "$1" "pattern '$2' found in output"; else ok "$1"; fi; }
wait_for_file() {  # $1 file, $2 seconds
  local i=0; while [ ! -s "$1" ] && [ "$i" -lt $(($2 * 10)) ]; do sleep 0.1; i=$((i + 1)); done; [ -s "$1" ]
}
expect_dead() {  # $1 name, $2 pid file: the process must be gone within 5 s
  local pid i=0; pid=$(cat "$2" 2>/dev/null)
  if [ -z "$pid" ]; then bad "$1" "no pid in $2"; return; fi
  while kill -0 "$pid" 2>/dev/null && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
  if kill -0 "$pid" 2>/dev/null; then bad "$1" "pid $pid still alive"; kill -KILL "$pid" 2>/dev/null; else ok "$1"; fi
}
newest_archive() { ls -dt "$R/$REVIEWS_REL"/*/ 2>/dev/null | head -1; }
policy_copy() {  # $1 name, $2 IGNORED_REVIEWS_REL value -> prints the path of a copy of the script with that policy
  local d="$T/policy-$1"; mkdir -p "$d"; [ -e "$d/ai_review" ] || ln -s "$HERE" "$d/ai_review"
  sed "s|^IGNORED_REVIEWS_REL=.*|IGNORED_REVIEWS_REL=\"$2\"|" "$SCRIPT" > "$d/ai_review.sh"
  printf '%s' "$d/ai_review.sh"
}
run_copy() {  # $1 script copy, $2 directory, rest: arguments
  local c="$1" d="$2"; shift 2
  OUT=$(cd "$d" && "$BASH_BIN" "$c" "$@" 2>&1); RC=$?
}
NOT_TEST_HOOK_WARNING='^warning: ([^t]|t[^e])'   # any warning except the test-hook one every faked run carries

R="$T/repo"; fixture_repo "$R"
SPEC="docs/superpowers/specs/x-design.md"
ARCH="$R/$REVIEWS_REL/$TODAY-$(slug_of "$SPEC")"

# ---- usage errors: exit 2, nothing written ---------------------------------------------------
reset_fakes
run_in "$R";                                           expect_rc "usage: no document is exit 2" 2
run_in "$R" "$SPEC" --bogus;                           expect_rc "usage: unknown flag is exit 2" 2
run_in "$R" "$SPEC" "$SPEC";                           expect_rc "usage: two documents is exit 2" 2
run_in "$R" "$SPEC" --timeout 0;                       expect_rc "usage: --timeout 0 is exit 2" 2
run_in "$R" "$SPEC" --timeout 1x;                      expect_rc "usage: --timeout non-integer is exit 2" 2
run_in "$R" "$SPEC" --timeout "$(printf '5\nx')";      expect_rc "usage: --timeout with a second line is exit 2" 2
run_in "$R" "$SPEC" --only gemini;                     expect_rc "usage: unknown provider in --only is exit 2" 2
run_in "$R" "$SPEC" --only codex,codex;                expect_rc "usage: duplicate provider in --only is exit 2" 2
run_in "$R" "$SPEC" --only ,codex;                     expect_rc "usage: empty provider in --only is exit 2" 2
run_in "$R" "$SPEC" --only "";                         expect_rc "usage: empty --only is exit 2" 2
run_in "$R" "$SPEC" --only c.dex;                      expect_rc "usage: a regex provider name (c.dex) is exit 2" 2
run_in "$R" "$SPEC" --only 'c[$(touch '"$T"'/pwned)o]dex'
expect_rc "usage: a provider name with a command substitution is exit 2" 2
expect_nofile "usage: the provider name is never evaluated" "$T/pwned"
run_in "$R" docs/nope.md;                              expect_rc "usage: missing document is exit 2" 2
run_in "$R" notes.txt;                                 expect_rc "usage: non-markdown document is exit 2" 2
ln -s x-design.md "$R/docs/superpowers/specs/link.md"
run_in "$R" docs/superpowers/specs/link.md;            expect_rc "usage: a symlinked document is exit 2" 2
rm -f "$R/docs/superpowers/specs/link.md"
printf '# ignored notes\n' > "$R/ignored/notes.md"
REFUSE=$(policy_copy refuse "")
run_copy "$REFUSE" "$R" ignored/notes.md;              expect_rc "policy refuse: a git-ignored document is exit 2" 2
rm -f "$R/ignored/notes.md"
run_in "$R" "$SPEC" --timeout "$(printf '5\n+calls[$(touch %s/pwn-timeout)]' "$T")"
expect_rc "usage: --timeout with arithmetic and a command substitution is exit 2" 2
expect_nofile "usage: the --timeout value is never evaluated" "$T/pwn-timeout"
run_in "$R" "$SPEC" --timeout 1234567;                 expect_rc "usage: a --timeout longer than six digits is exit 2" 2
run_in "$R" "$SPEC" --only "$(printf 'codex\nclaude')";  expect_rc "usage: --only with a newline is exit 2" 2
printf '# ctl\n' > "$R/docs/superpowers/specs/$(printf 'a\nb').md"
run_in "$R" "docs/superpowers/specs/$(printf 'a\nb').md"; expect_rc "usage: a control character in the document path is exit 2" 2
rm -f "$R/docs/superpowers/specs/$(printf 'a\nb').md"
git -C "$R" checkout -q "$FIRST_PROTECTED"
fake_ok codex
run_in "$R" "$SPEC" --only codex;                      expect_rc "usage: a protected branch ($FIRST_PROTECTED) is exit 2" 2
git -C "$R" checkout -q --detach
run_in "$R" "$SPEC" --only codex;                      expect_rc "usage: a detached HEAD is exit 2" 2
git -C "$R" checkout -q "$FIXTURE_BRANCH"
reset_fakes
printf '# outside\n' > "$T/outside.md"
run_in "$R" "$T/outside.md";                           expect_rc "usage: document outside the repository is exit 2" 2
run_in "$T" "$T/outside.md";                           expect_rc "usage: not inside a git repository is exit 2" 2
expect_nofile "usage: no archive written by any usage error" "$R/$REVIEWS_REL"

mkdir -p "$T/o-exists"; : > "$T/o-exists/keep"
fake_ok codex
run_in "$R" "$SPEC" --only codex --out "$T/o-exists"
expect_rc "out-exists: an existing --out directory is exit 2" 2
expect_nofile "out-exists: nothing written into it" "$T/o-exists/prompt.md"
expect_file "out-exists: its content untouched" "$T/o-exists/keep"

# ---- ok: three providers, archive layout, summary, prompt ----------------------------------
reset_fakes; fake_ok codex; fake_ok copilot; fake_ok claude
run_in "$R" "$SPEC"
expect_rc "ok: three good providers exit 0" 0
expect_file "ok: default archive is <REVIEWS_REL>/<date>-<slug>/" "$ARCH/summary.txt"
expect_file "ok: prompt.md archived" "$ARCH/prompt.md"
for p in codex copilot claude; do
  expect_file "ok: findings-$p.md archived" "$ARCH/findings-$p.md"
  expect_grep "ok: $p status line" "^$p +ok +3 findings +VERDICT: revise — three things$" "$ARCH/summary.txt"
done
if [ -z "$(find "$ARCH" -iname 'claude.md' -o -iname 'agents.md' -o -iname 'codex.md' -o -iname 'copilot.md')" ]; then
  ok "ok: no archive file is named <provider>.md or an instruction file, in any case"
else bad "ok: no archive file is named <provider>.md" "found $(find "$ARCH" -iname '*.md' | tr '\n' ' ')"; fi
expect_grep "ok: summary names the document" "^document: $SPEC$" "$ARCH/summary.txt"
expect_grep "ok: summary names the date" "^date: $TODAY$" "$ARCH/summary.txt"
expect_grep "ok: summary names the models" '^models: codex=[^ ]+ copilot=[^ ]+ claude=[^ ]+$' "$ARCH/summary.txt"
expect_grep "ok: summary names the per-call timeout" '^timeout-per-call: 600s$' "$ARCH/summary.txt"
expect_grep "ok: summary totals the findings" '^findings: 9 total$' "$ARCH/summary.txt"
expect_absent "ok: no warning when the reviewers wrote nothing" "$NOT_TEST_HOOK_WARNING" "$ARCH/summary.txt"
expect_out "ok: summary printed to stdout" '^claude +ok +3 findings'
expect_grep "prompt: document path rendered" "$SPEC" "$ARCH/prompt.md"
expect_absent "prompt: no placeholder left" '\{\{' "$ARCH/prompt.md"
while IFS= read -r o; do
  if grep -qF -- "$o" "$ARCH/prompt.md"; then ok "prompt: orientation names $o"; else bad "prompt: orientation names $o" "missing"; fi
done <<< "$(orientation_paths)"
if grep -qF -- "$AI_REVIEW_PROJECT" "$ARCH/prompt.md"; then ok "prompt: names the project from the config"; else bad "prompt: names the project from the config" "missing"; fi
if grep -qF -- "$DOC_LAYOUT" "$ARCH/prompt.md"; then ok "prompt: carries the document layout from the config"; else bad "prompt: carries the document layout from the config" "missing"; fi
expect_grep "prompt: output contract (VERDICT line)" '^VERDICT: <ready\|revise\|reject>' "$ARCH/prompt.md"
expect_grep "prompt: hunch rule" 'hunch' "$ARCH/prompt.md"

# --only names only what ran
reset_fakes; fake_ok codex
run_in "$R" "$SPEC" --only codex --out "$T/o-only"
expect_grep "only: models line names only the providers that ran" '^models: codex=[^ ]+$' "$T/o-only/summary.txt"

# same-day reruns: -r2, -r3; earlier archives untouched
cp "$ARCH/summary.txt" "$T/first-summary.txt"
reset_fakes; fake_ok codex
run_in "$R/sub" "../$SPEC" --only codex
expect_rc "rerun: a second same-day run is accepted (run from a subdirectory)" 0
expect_file "rerun: second same-day run lands in <date>-<slug>-r2" "$ARCH-r2/summary.txt"
run_in "$R" "$SPEC" --only codex
expect_file "rerun: third same-day run lands in -r3" "$ARCH-r3/summary.txt"
if cmp -s "$ARCH/summary.txt" "$T/first-summary.txt"; then ok "rerun: first archive untouched"; else bad "rerun: first archive untouched" "summary changed"; fi
expect_absent "rerun: --only codex runs codex alone" '^copilot ' "$ARCH-r2/summary.txt"

# plan documents get their own slug
run_in "$R" docs/superpowers/plans/x.md --only codex
expect_file "slug: a plan archives as <date>-<slug>" "$R/$REVIEWS_REL/$TODAY-$(slug_of docs/superpowers/plans/x.md)/summary.txt"

# concurrent runs never share an archive
reset_fakes; mkfake codex "sleep 1; cat '$FAKES/findings3.txt'"
for i in 1 2 3 4 5 6; do (cd "$R" && "$BASH_BIN" "$SCRIPT" docs/superpowers/plans/race.md --only codex > "$T/race-$i.log" 2>&1) & done
wait
n=$(ls -d "$R/$REVIEWS_REL/$TODAY-$(slug_of docs/superpowers/plans/race.md)"* 2>/dev/null | wc -l | tr -d ' ')
if [ "$n" -eq 6 ]; then ok "race: six concurrent runs claim six archives"; else bad "race: six concurrent runs claim six archives" "got $n: $(ls "$R/$REVIEWS_REL" | tr '\n' ' ')"; fi
m=$(ls "$R/$REVIEWS_REL/$TODAY-$(slug_of docs/superpowers/plans/race.md)"*/summary.txt 2>/dev/null | wc -l | tr -d ' ')
if [ "$m" -eq 6 ]; then ok "race: each archive has its own summary"; else bad "race: each archive has its own summary" "got $m"; fi

# model override
reset_fakes; fake_ok copilot
AI_REVIEW_COPILOT_MODEL=test-model-9 run_in "$R" "$SPEC" --only copilot --out "$T/o-model-override"
expect_grep "copilot-model: AI_REVIEW_COPILOT_MODEL overrides the pin" 'copilot=test-model-9' "$T/o-model-override/summary.txt"

# ---- fakes run from the repository root, in parallel ---------------------------------------
reset_fakes
for p in codex copilot claude; do mkfake "$p" "pwd -P > '$T/pwd-$p'; sleep 2; cat '$FAKES/findings3.txt'"; done
start=$(date +%s)
run_in "$R/sub" "../$SPEC" --out "$T/o-par"
el=$(( $(date +%s) - start ))
expect_rc "parallel: runs" 0
if [ "$el" -lt 5 ]; then ok "parallel: three 2 s providers finish in under 5 s (took ${el}s)"; else bad "parallel: three 2 s providers finish in under 5 s" "took ${el}s"; fi
if [ "$(cat "$T/pwd-claude")" = "$(cd "$R" && pwd -P)" ]; then
  ok "cwd: provider runs from the repository root, not the caller's directory"
else bad "cwd: provider runs from the repository root" "ran in $(cat "$T/pwd-claude")"; fi

# ---- trim: preamble and sign-off dropped; a lone VERDICT is a clean ok ----------------------
reset_fakes
mkfake codex "echo 'Reviewing now.'; echo; cat '$FAKES/findings3.txt'; echo 'Thanks for reading!'"
run_in "$R" "$SPEC" --only codex --out "$T/o-trim"
if [ "$(head -1 "$T/o-trim/findings-codex.md")" = "F1 [major] Intent" ]; then ok "trim: answer starts at F1"; else bad "trim: answer starts at F1" "$(head -1 "$T/o-trim/findings-codex.md")"; fi
if [ "$(tail -1 "$T/o-trim/findings-codex.md")" = "VERDICT: revise — three things" ]; then ok "trim: answer ends at VERDICT"; else bad "trim: answer ends at VERDICT" "$(tail -1 "$T/o-trim/findings-codex.md")"; fi
: > "$T/calls-clean"
mkfake codex "echo call >> '$T/calls-clean'; echo 'I found nothing to raise.'; echo 'VERDICT: ready — clean document'"
run_in "$R" "$SPEC" --only codex --out "$T/o-clean"
expect_rc "clean: a lone VERDICT line exits 0" 0
expect_grep "clean: a lone VERDICT is ok with 0 findings" '^codex +ok +0 findings +VERDICT: ready — clean document$' "$T/o-clean/summary.txt"
n=$(wc -l < "$T/calls-clean" | tr -d ' ')
if [ "$n" -eq 1 ]; then ok "clean: a lone VERDICT is not retried (1 call)"; else bad "clean: a lone VERDICT is not retried" "$n calls"; fi

# ---- truncated, then the two-half retry succeeds ---------------------------------------------
reset_fakes
mkfake claude "
case \"\$(cat \"\$1\")\" in *'first six findings'*) cp \"\$1\" '$T/retry-prompt-a';; esac
if grep -q 'first six findings' \"\$1\"; then
  printf 'F1 [major] Intent\nclaim: a\nevidence: b\nfix: c\nF2 [minor] Decisions\nclaim: d\nevidence: e\nfix: f\nVERDICT: ready — from half A\n'
elif grep -q 'remaining findings and the VERDICT line' \"\$1\"; then
  printf 'F1 [minor] Decisions\nclaim: d\nevidence: e\nfix: f\nF2 [hunch] Acceptance\nclaim: g\nevidence: not checked\nfix: h\nVERDICT: revise — merged\n'
else
  printf 'F1 [major] Intent\nclaim: a\nevidence: b\nfix: c\nF2 [minor] Decisions\nclaim: d\n'
fi"
run_in "$R" "$SPEC" --only claude --out "$T/o-retry"
expect_rc "retry: halves with a VERDICT make the provider ok" 0
expect_grep "retry: status ok, duplicate dropped (3 findings), VERDICT from half B" '^claude +ok +3 findings +VERDICT: revise — merged$' "$T/o-retry/summary.txt"
expect_grep "retry: merged answer renumbered F1..F3" '^F3 \[hunch\] Acceptance$' "$T/o-retry/findings-claude.md"
if [ "$(grep -c '^claim: d$' "$T/o-retry/findings-claude.md")" -eq 1 ]; then ok "retry: the repeated finding appears once"; else bad "retry: the repeated finding appears once" "count $(grep -c '^claim: d$' "$T/o-retry/findings-claude.md")"; fi
expect_absent "retry: half A's VERDICT is not kept" 'from half A' "$T/o-retry/findings-claude.md"
expect_file "retry: the first, truncated answer is kept as findings-<p>.raw.md" "$T/o-retry/findings-claude.raw.md"
expect_grep "retry: the retry prompt carries the cut-off first answer" '^F2 \[minor\] Decisions$' "$T/retry-prompt-a"

# a failing half never yields ok
for half in B A; do
  reset_fakes
  if [ "$half" = B ]; then failwhen='remaining findings'; else failwhen='first six findings'; fi
  mkfake claude "
if grep -q '$failwhen' \"\$1\"; then echo 'ERROR: 500 Internal Server Error' >&2; exit 1; fi
if grep -q 'first six findings' \"\$1\"; then printf 'F1 [major] Intent\nclaim: a\nevidence: b\nfix: c\nVERDICT: ready — half A\n'; exit 0; fi
if grep -q 'remaining findings' \"\$1\"; then printf 'F1 [minor] Decisions\nclaim: d\nevidence: e\nfix: f\nVERDICT: revise — half B\n'; exit 0; fi
printf 'F1 [major] Intent\nclaim: a\n'"
  run_in "$R" "$SPEC" --only claude --out "$T/o-retry-fail-$half"
  expect_rc "retry: half $half failing exits 1" 1
  expect_grep "retry: half $half failing is failed:provider, not ok" '^claude +failed:provider' "$T/o-retry-fail-$half/summary.txt"
done

# ---- truncated: no VERDICT even after the retry ----------------------------------------------
reset_fakes
mkfake copilot "printf 'F1 [major] Intent\nclaim: a\nevidence: b\nfix: c\n'"
run_in "$R" "$SPEC" --only copilot --out "$T/o-trunc"
expect_rc "truncated: sole provider truncated exits 1" 1
expect_grep "truncated: status" '^copilot +truncated +1 findings' "$T/o-trunc/summary.txt"
expect_file "truncated: partial answer still archived" "$T/o-trunc/findings-copilot.md"

# ---- timeout: the provider and its children are killed ---------------------------------------
reset_fakes; fake_ok codex
mkfake claude "echo \$\$ > '$T/to-prov.pid'; trap '' TERM; sleep 60 & echo \$! > '$T/to-child.pid'; wait"
start=$(date +%s)
run_in "$R" "$SPEC" --only codex,claude --timeout 2 --out "$T/o-timeout"
el=$(( $(date +%s) - start ))
expect_rc "timeout: one timeout with one ok still exits 0" 0
if [ "$el" -lt 10 ]; then ok "timeout: a 2 s timeout returns promptly (${el}s), not when the provider ends"; else bad "timeout: a 2 s timeout returns promptly" "took ${el}s"; fi
expect_grep "timeout: status" '^claude +timeout +0 findings' "$T/o-timeout/summary.txt"
expect_grep "timeout: summary names the per-call timeout" '^timeout-per-call: 2s$' "$T/o-timeout/summary.txt"
expect_dead "timeout: the provider (ignoring TERM) is killed" "$T/to-prov.pid"
expect_dead "timeout: the provider's child is killed" "$T/to-child.pid"

# ---- interrupted: INT, TERM, HUP to the script's process group --------------------------------
for sig in INT TERM HUP; do
  case "$sig" in INT) want=130 ;; TERM) want=143 ;; HUP) want=129 ;; esac
  reset_fakes
  rm -f "$T/sig-prov.pid" "$T/sig-child.pid"
  mkfake codex "echo \$\$ > '$T/sig-prov.pid'; sleep 60 & echo \$! > '$T/sig-child.pid'; wait"
  (cd "$R" && exec perl -e '$SIG{INT} = "DEFAULT"; $SIG{QUIT} = "DEFAULT"; setpgrp(0, 0); exec @ARGV' \
      "$BASH_BIN" "$SCRIPT" "$SPEC" --only codex --timeout 120 --out "$T/o-sig-$sig" > "$T/sig-$sig.log" 2>&1) &
  spid=$!
  if wait_for_file "$T/sig-child.pid" 10; then
    kill -"$sig" -- -"$spid" 2>/dev/null
    start=$(date +%s); wait "$spid"; RC=$?; el=$(( $(date +%s) - start ))
    OUT=$(cat "$T/sig-$sig.log")
    expect_rc "interrupt ($sig): the script exits 128+signal" "$want"
    if [ "$el" -lt 10 ]; then ok "interrupt ($sig): the script exits promptly (${el}s)"; else bad "interrupt ($sig): the script exits promptly" "took ${el}s"; fi
    expect_dead "interrupt ($sig): the provider is killed" "$T/sig-prov.pid"
    expect_dead "interrupt ($sig): the provider's child is killed" "$T/sig-child.pid"
    expect_nofile "interrupt ($sig): no half archive is left" "$T/o-sig-$sig"
  else
    bad "interrupt ($sig): the fake provider started" "no pid file"; kill -KILL -- -"$spid" 2>/dev/null
  fi
done

# The script itself SIGKILLed (no trap can run), then TERM to its group: the per-call timer
# alone must take the provider's group down.
reset_fakes
rm -f "$T/sig-prov.pid" "$T/sig-child.pid"
mkfake codex "echo \$\$ > '$T/sig-prov.pid'; sleep 60 & echo \$! > '$T/sig-child.pid'; wait"
(cd "$R" && exec perl -e 'setpgrp(0, 0); exec @ARGV' \
    "$BASH_BIN" "$SCRIPT" "$SPEC" --only codex --timeout 120 --out "$T/o-sig-kill" > "$T/sig-kill.log" 2>&1) &
spid=$!
if wait_for_file "$T/sig-child.pid" 10; then
  kill -KILL "$spid" 2>/dev/null; wait "$spid" 2>/dev/null
  kill -TERM -- -"$spid" 2>/dev/null
  expect_dead "interrupt (timer): the provider dies when only the timer gets TERM" "$T/sig-prov.pid"
  expect_dead "interrupt (timer): the provider's child dies too" "$T/sig-child.pid"
else
  bad "interrupt (timer): the fake provider started" "no pid file"; kill -KILL -- -"$spid" 2>/dev/null
fi
rm -rf "$T/o-sig-kill"

# ---- not installed -----------------------------------------------------------------------------
reset_fakes; fake_ok codex
run_in "$R" "$SPEC" --only codex,copilot --out "$T/o-notinst"
expect_rc "not-installed: a missing provider never fails the run" 0
expect_grep "not-installed: status" '^copilot +skipped:not-installed' "$T/o-notinst/summary.txt"
expect_nofile "not-installed: no answer file" "$T/o-notinst/findings-copilot.md"
unset AI_REVIEW_BIN_CODEX AI_REVIEW_BIN_COPILOT AI_REVIEW_BIN_CLAUDE
OUT=$(cd "$R" && PATH="$SYS_PATH" "$BASH_BIN" "$SCRIPT" "$SPEC" --out "$T/o-nocli" 2>&1); RC=$?
expect_rc "not-installed: no hook and no CLI on PATH exits 1" 1
for p in codex copilot claude; do expect_grep "not-installed: $p without hook or PATH entry" "^$p +skipped:not-installed" "$T/o-nocli/summary.txt"; done

# ---- auth, quota, model (stderr and stdout) ----------------------------------------------------
reset_fakes; fake_ok copilot
mkfake codex "echo 'ERROR: unexpected status 401 Unauthorized' >&2; exit 1"
mkfake claude "echo 'Invalid API key · Please run /login' >&2; exit 1"
run_in "$R" "$SPEC" --out "$T/o-auth"
expect_grep "auth: codex status" '^codex +skipped:auth' "$T/o-auth/summary.txt"
expect_grep "auth: claude status" '^claude +skipped:auth' "$T/o-auth/summary.txt"
expect_grep "auth: hint for codex" '^hint: codex: .*codex login' "$T/o-auth/summary.txt"
expect_grep "auth: hint for claude" '^hint: claude: .*/login' "$T/o-auth/summary.txt"
mkfake claude "echo 'Error: Not logged in. Please run /login'; exit 1"
run_in "$R" "$SPEC" --only claude --out "$T/o-auth-stdout"
expect_grep "auth: a message on stdout is skipped:auth" '^claude +skipped:auth' "$T/o-auth-stdout/summary.txt"
reset_fakes; fake_ok codex
mkfake copilot "echo 'Error: Access denied by policy settings (Request ID: X)' >&2; exit 1"
run_in "$R" "$SPEC" --only codex,copilot --out "$T/o-policy"
expect_grep "auth: a Copilot policy denial is skipped:auth" '^copilot +skipped:auth' "$T/o-policy/summary.txt"
expect_grep "auth: the Copilot hint names the policy settings page" '^hint: copilot: .*github\.com/settings/copilot' "$T/o-policy/summary.txt"
mkfake claude "echo 'not logged in? just noise' >&2; cat '$FAKES/findings3.txt'"
run_in "$R" "$SPEC" --only claude --out "$T/o-auth-noise"
expect_grep "auth: stderr noise on a successful call stays ok" '^claude +ok' "$T/o-auth-noise/summary.txt"

reset_fakes; fake_ok codex
mkfake copilot "echo 'Error: You have exceeded your monthly quota' >&2; exit 1"
run_in "$R" "$SPEC" --only codex,copilot --out "$T/o-quota"
expect_grep "quota: status" '^copilot +skipped:quota' "$T/o-quota/summary.txt"
expect_grep "quota: hint" '^hint: copilot: .*quota' "$T/o-quota/summary.txt"
mkfake copilot "echo 'Error: You have exceeded your monthly quota'; exit 1"
run_in "$R" "$SPEC" --only copilot --out "$T/o-quota-stdout"
expect_grep "quota: a message on stdout is skipped:quota" '^copilot +skipped:quota' "$T/o-quota-stdout/summary.txt"
mkfake copilot "echo 'Error: Model \"gone-1\" from --model flag is not available.' >&2; exit 1"
run_in "$R" "$SPEC" --only codex,copilot --out "$T/o-model"
expect_grep "model: status" '^copilot +failed:model' "$T/o-model/summary.txt"
expect_grep "model: hint names the override variable" '^hint: copilot: .*AI_REVIEW_COPILOT_MODEL' "$T/o-model/summary.txt"

# ---- all failed --------------------------------------------------------------------------------
reset_fakes
for p in codex copilot claude; do mkfake "$p" "echo 'ERROR: 500 Internal Server Error' >&2; exit 1"; done
run_in "$R" "$SPEC" --out "$T/o-allfail"
expect_rc "all-failed: no ok provider exits 1" 1
for p in codex copilot claude; do expect_grep "all-failed: $p status" "^$p +failed:provider +0 findings" "$T/o-allfail/summary.txt"; done
expect_file "all-failed: the summary is still archived" "$T/o-allfail/summary.txt"
expect_grep "all-failed: the hint says where stderr is (not archived)" '^hint: codex: .*stderr' "$T/o-allfail/summary.txt"

# ---- untrusted answer content --------------------------------------------------------------
reset_fakes
long=$(printf 'x%.0s' $(seq 1 400))
mkfake codex "printf 'F1 [minor] Intent\nclaim: a\nevidence: /etc/hosts says so\nfix: c\nVERDICT: ready \033[31m red $long\n'"
run_in "$R" "$SPEC" --only codex --out "$T/o-untrusted"
if grep -q "$(printf '\033')" "$T/o-untrusted/summary.txt"; then bad "untrusted: control bytes stripped from the VERDICT in summary.txt" "ESC found"; else ok "untrusted: control bytes stripped from the VERDICT in summary.txt"; fi
len=$(grep '^codex ' "$T/o-untrusted/summary.txt" | wc -c | tr -d ' ')
if [ "$len" -le 260 ]; then ok "untrusted: the VERDICT is capped in summary.txt ($len bytes)"; else bad "untrusted: the VERDICT is capped in summary.txt" "$len bytes"; fi
expect_grep "untrusted: a path outside the repository is flagged" '^warning: findings-codex\.md names paths outside the repository' "$T/o-untrusted/summary.txt"
mkfake codex "printf 'F1 [minor] Intent\nclaim: a\nevidence: $R/AGENTS.md says so\nfix: c\nVERDICT: ready — fine\n'"
run_in "$R" "$SPEC" --only codex --out "$T/o-inside"
# an absolute path inside the repository is rewritten relative (it would carry the home directory
# and the user name into a tracked archive), so it neither stays nor warns
expect_grep "untrusted: an absolute path inside the repository is rewritten relative" '^evidence: AGENTS\.md says so$' "$T/o-inside/findings-codex.md"
expect_absent "untrusted: ... and not flagged" "$NOT_TEST_HOOK_WARNING" "$T/o-inside/summary.txt"

# ---- worktree snapshot -----------------------------------------------------------------------
reset_fakes
mkfake codex "echo changed >> AGENTS.md; echo new > stray.txt; cat '$FAKES/findings3.txt'"
run_in "$R" "$SPEC" --only codex --out "$T/o-dirty"
expect_rc "worktree: a writing reviewer does not change the exit code" 0
expect_out "worktree: warning printed" '^warning: worktree changed during the run'
expect_grep "worktree: warning names the changed tracked file" 'AGENTS\.md' "$T/o-dirty/summary.txt"
expect_grep "worktree: warning names the new untracked file" 'stray\.txt' "$T/o-dirty/summary.txt"
git -C "$R" checkout -q -- AGENTS.md; rm -f "$R/stray.txt"

mkfake codex "printf 'scratch-2\n' > scratch.txt; cat '$FAKES/findings3.txt'"
run_in "$R" "$SPEC" --only codex --out "$T/o-untracked-edit"
expect_grep "worktree: a content change to an existing untracked file is flagged" 'scratch\.txt' "$T/o-untracked-edit/summary.txt"
mkfake codex "printf 'cache-2\n' > ignored/cache.txt; cat '$FAKES/findings3.txt'"
run_in "$R" "$SPEC" --only codex --out "$T/o-ignored-edit"
expect_grep "worktree: a change to a git-ignored file is counted in summary.txt" '^warning: 1 git-ignored path' "$T/o-ignored-edit/summary.txt"
expect_absent "worktree: a git-ignored path is never named in the tracked summary.txt" 'ignored/cache\.txt' "$T/o-ignored-edit/summary.txt"
expect_out "worktree: the git-ignored path is named on the terminal" 'ignored/cache\.txt'
mkfake codex "printf '#!/bin/sh\n' > .git/hooks/pre-commit; cat '$FAKES/findings3.txt'"
run_in "$R" "$SPEC" --only codex --out "$T/o-hook"
expect_grep "worktree: a new git hook is flagged" 'hooks/pre-commit' "$T/o-hook/summary.txt"
rm -f "$R/.git/hooks/pre-commit"
mkfake codex "git config --local review.planted yes; cat '$FAKES/findings3.txt'"
run_in "$R" "$SPEC" --only codex --out "$T/o-gitconfig"
expect_grep "worktree: a git config change is flagged" '\.git/config' "$T/o-gitconfig/summary.txt"
git -C "$R" config --local --unset review.planted
mkfake codex "d=\$(ls -dt $REVIEWS_REL/*/ | head -1); echo planted > \"\$d/notes.md\"; cat '$FAKES/findings3.txt'"
run_in "$R" "$SPEC" --only codex
D=$(newest_archive)
expect_grep "worktree: an unexpected file inside the archive is flagged" 'notes\.md' "${D}summary.txt"
reset_fakes; fake_ok codex
run_in "$R" "$SPEC" --only codex
expect_noout "worktree: the run's own archive inside the repository is not a change" "$NOT_TEST_HOOK_WARNING"

# ---- real command lines through PATH shims (no real CLI reachable) ---------------------------
SHIMS="$T/shims"; mkdir -p "$SHIMS"
for p in codex copilot claude; do
  cat > "$SHIMS/$p" <<EOF
#!/bin/bash
p=$p
printf '%s\n' "\$@" > "$T/argv-\$p"
env > "$T/env-\$p"
pwd -P > "$T/pwd-shim-\$p"
cat > "$T/stdin-\$p"
mode=\$(cat "$T/shim-mode-\$p" 2>/dev/null)
if [ "\$p" = codex ]; then
  out=""; prev=""
  for a in "\$@"; do [ "\$prev" = "-o" ] && out="\$a"; prev="\$a"; done
  echo 'event log noise'
  case "\$mode" in
    authfail) echo 'ERROR: unexpected status 401 Unauthorized'; exit 1 ;;
    crash)    echo 'repository text: Unauthorized callers are rejected'; for i in \$(seq 1 40); do echo "event \$i"; done; echo 'panic: crashed' >&2; exit 1 ;;
  esac
  cat '$FAKES/findings3.txt' > "\$out"
else
  cat '$FAKES/findings3.txt'
fi
EOF
done
chmod +x "$SHIMS"/*
printf 'STDIN-LEAK\n' > "$T/stdin-leak"
unset AI_REVIEW_BIN_CODEX AI_REVIEW_BIN_COPILOT AI_REVIEW_BIN_CLAUDE AI_REVIEW_COPILOT_MODEL AI_REVIEW_CLAUDE_MODEL AI_REVIEW_CODEX_MODEL
PLANTED="GH_TOKEN ANTHROPIC_API_KEY ANTHROPIC_BASE_URL OPENAI_API_KEY OPENAI_BASE_URL COPILOT_PROVIDER_BASE_URL COPILOT_CUSTOM_INSTRUCTIONS_DIRS COPILOT_ALLOW_ALL CODEX_HOME HTTPS_PROXY AWS_SECRET_ACCESS_KEY AI_REVIEW_PLANTED"
OUT=$(cd "$R/sub" && env GH_TOKEN=planted-gh ANTHROPIC_API_KEY=planted-anthropic ANTHROPIC_BASE_URL=https://planted.invalid \
      OPENAI_API_KEY=planted-openai OPENAI_BASE_URL=https://planted.invalid COPILOT_PROVIDER_BASE_URL=https://planted.invalid \
      COPILOT_CUSTOM_INSTRUCTIONS_DIRS="$T" COPILOT_ALLOW_ALL=true CODEX_HOME="$T/planted-codex-home" HTTPS_PROXY=http://planted.invalid:3128 \
      AWS_SECRET_ACCESS_KEY=planted-aws AI_REVIEW_PLANTED=1 \
      PATH="$SHIMS:$SYS_PATH" "$BASH_BIN" "$SCRIPT" "../$SPEC" --out "$T/o-shim" < "$T/stdin-leak" 2>&1); RC=$?
expect_rc "cli: three shimmed CLIs exit 0" 0
for p in codex copilot claude; do expect_grep "cli: $p ok through its real command line" "^$p +ok +3 findings" "$T/o-shim/summary.txt"; done
argval() { grep -A1 -x -- "$2" "$1" | sed -n 2p; }  # $1 argv file, $2 flag -> the next argument
expect_argval() {  # $1 name, $2 argv file, $3 flag, $4 expected value
  local v; v=$(argval "$2" "$3")
  if [ "$v" = "$4" ]; then ok "$1"; else bad "$1" "after $3 got '$v', wanted '$4'"; fi
}
# Each provider keeps only its own credential variables (its login can live there); every other
# planted name, including every base-URL redirect, proxy and foreign token, must not arrive.
own_vars() { case "$1" in codex) echo "OPENAI_API_KEY CODEX_HOME" ;; copilot) echo "GH_TOKEN" ;; claude) echo "ANTHROPIC_API_KEY" ;; esac; }
for p in codex copilot claude; do
  for v in $PLANTED; do
    case " $(own_vars "$p") " in
      *" $v "*) expect_grep "env: $p receives its own credential variable $v" "^$v=" "$T/env-$p" ;;
      *)        expect_absent "env: $p does not receive $v" "^$v=" "$T/env-$p" ;;
    esac
  done
  expect_absent "env: $p sees no variable naming the run directory or its pgid records" 'AI_REVIEW_PGIDS|/pgids|/ai_review\.' "$T/env-$p"
  expect_grep "env: $p still receives HOME" '^HOME=' "$T/env-$p"
  expect_grep "env: $p still receives PATH" '^PATH=' "$T/env-$p"
  if [ "$(cat "$T/pwd-shim-$p")" = "$(cd "$R" && pwd -P)" ]; then ok "cwd: real $p command line runs from the repository root"
  else bad "cwd: real $p command line runs from the repository root" "ran in $(cat "$T/pwd-shim-$p")"; fi
done
expect_grep "env: copilot still receives COPILOT_HOME" '^COPILOT_HOME=' "$T/env-copilot"
for p in codex copilot; do
  if [ -s "$T/stdin-$p" ]; then bad "stdin: $p reads nothing from the caller's stdin" "got $(head -c 40 "$T/stdin-$p")"; else ok "stdin: $p reads nothing from the caller's stdin"; fi
done
expect_absent "stdin: claude's stdin is the prompt, not the caller's stdin" 'STDIN-LEAK' "$T/stdin-claude"
for f in -s --no-ask-user --no-custom-instructions --disable-builtin-mcps --disable-client-telemetry --no-auto-update \
         --disallow-temp-dir --sync-session=off --deny-tool=write --deny-tool=shell --deny-tool=url; do
  expect_grep "cli: copilot gets $f" "^$f\$" "$T/argv-copilot"
done
expect_argval "cli: copilot model is pinned" "$T/argv-copilot" --model gpt-6.1-sol
expect_argval "cli: copilot mode is plan" "$T/argv-copilot" --mode plan
expect_argval "cli: copilot tools are read and search only" "$T/argv-copilot" --available-tools view,grep,glob
v=$(argval "$T/argv-copilot" -p)
case "$v" in "You are an independent, read-only reviewer"*) ok "cli: copilot receives the prompt";; *) bad "cli: copilot receives the prompt" "got '$v'";; esac
expect_absent "cli: copilot never trusts the folder" '^--(trust-folder|allow-all|allow-all-tools|allow-all-urls|add-dir)$' "$T/argv-copilot"
for f in -p --safe-mode --restricted --strict-mcp-config --no-session-persistence --disable-slash-commands --setting-sources=; do
  expect_grep "cli: claude gets $f" "^$f\$" "$T/argv-claude"
done
expect_argval "cli: claude model is pinned" "$T/argv-claude" --model fable
expect_argval "cli: claude --tools is exactly Read,Grep,Glob" "$T/argv-claude" --tools Read,Grep,Glob
expect_argval "cli: claude --allowedTools is exactly Read,Grep,Glob" "$T/argv-claude" --allowedTools Read,Grep,Glob
expect_argval "cli: claude permission mode is dontAsk" "$T/argv-claude" --permission-mode dontAsk
expect_argval "cli: claude spending is capped" "$T/argv-claude" --max-budget-usd 5
expect_grep "cli: claude receives the prompt on stdin" '^You are an independent, read-only reviewer' "$T/stdin-claude"
expect_absent "cli: claude never bypasses permissions" 'bypassPermissions|dangerously' "$T/argv-claude"
for f in exec --ephemeral --ignore-user-config --ignore-rules --skip-git-repo-check; do
  expect_grep "cli: codex gets $f" "^$f\$" "$T/argv-codex"
done
expect_argval "cli: codex model is pinned" "$T/argv-codex" -m gpt-6.1-sol
expect_argval "cli: codex sandbox is read-only" "$T/argv-codex" -s read-only
expect_grep "cli: codex web search disabled" '^web_search="disabled"$' "$T/argv-codex"
expect_grep "cli: codex loads no AGENTS.md as instructions" '^project_doc_max_bytes=0$' "$T/argv-codex"
for f in apps hooks plugins memories; do
  if grep -B1 -x -- "$f" "$T/argv-codex" | head -1 | grep -qx -- --disable; then ok "cli: codex feature $f is preceded by --disable"
  else bad "cli: codex feature $f is preceded by --disable" "$(grep -B1 -x -- "$f" "$T/argv-codex" | tr '\n' ' ')"; fi
done
case "$(tail -1 "$T/argv-codex")" in *'output contract'*|*VERDICT*) ok "cli: codex receives the prompt as its last argument";; *) bad "cli: codex receives the prompt as its last argument" "last line: $(tail -1 "$T/argv-codex")";; esac
expect_absent "cli: codex event log is not the answer" 'event log noise' "$T/o-shim/findings-codex.md"

echo authfail > "$T/shim-mode-codex"
OUT=$(cd "$R" && PATH="$SHIMS:$SYS_PATH" "$BASH_BIN" "$SCRIPT" "$SPEC" --only codex --out "$T/o-shim-auth" < /dev/null 2>&1); RC=$?
expect_grep "cli: an auth error at the end of codex's event log is skipped:auth" '^codex +skipped:auth' "$T/o-shim-auth/summary.txt"
echo crash > "$T/shim-mode-codex"
OUT=$(cd "$R" && PATH="$SHIMS:$SYS_PATH" "$BASH_BIN" "$SCRIPT" "$SPEC" --only codex --out "$T/o-shim-crash" < /dev/null 2>&1); RC=$?
expect_grep "cli: repository text early in codex's event log does not make a crash skipped:auth" '^codex +failed:provider' "$T/o-shim-crash/summary.txt"
rm -f "$T/shim-mode-codex"

# Copilot's saved folder trust would load the repository's skills, hooks and MCP config.
for trusted in "$R" "$(dirname "$R")"; do
  CPH="$T/copilot-home-$RANDOM"; mkdir -p "$CPH"
  printf '// managed automatically\n{\n  "trustedFolders": [\n    "/somewhere/else",\n    "%s"\n  ]\n}\n' "$trusted" > "$CPH/config.json"
  rm -f "$T/argv-copilot"
  OUT=$(cd "$R" && COPILOT_HOME="$CPH" PATH="$SHIMS:$SYS_PATH" "$BASH_BIN" "$SCRIPT" "$SPEC" --only copilot --out "$T/o-trust-$RANDOM" 2>&1); RC=$?
  expect_out "copilot-trust: a trusted folder ($( [ "$trusted" = "$R" ] && echo repo || echo parent)) is refused" '^copilot +failed:provider'
  expect_out "copilot-trust: the hint names the trusted folder" '^hint: copilot: .*trustedFolders'
  expect_nofile "copilot-trust: copilot is never called" "$T/argv-copilot"
done
CPH="$T/copilot-home-other"; mkdir -p "$CPH"
printf '{ "trustedFolders": ["/somewhere/else"] }\n' > "$CPH/settings.json"
OUT=$(cd "$R" && COPILOT_HOME="$CPH" PATH="$SHIMS:$SYS_PATH" "$BASH_BIN" "$SCRIPT" "$SPEC" --only copilot --out "$T/o-trust-other" 2>&1); RC=$?
expect_out "copilot-trust: an unrelated trusted folder does not block the run" '^copilot +ok'

# =============================================================================================
# Review round 2
# =============================================================================================
in_pgrp() {  # run the script (or $SCRIPT_UNDER_TEST) in its own process group, in the background; sets SPID
  (cd "$R" && exec perl -e '$SIG{INT} = "DEFAULT"; $SIG{QUIT} = "DEFAULT"; setpgrp(0, 0); exec @ARGV' \
      "$BASH_BIN" "${SCRIPT_UNDER_TEST:-$SCRIPT}" "$@" > "$T/pgrp.log" 2>&1) &
  SPID=$!
}

# ---- R2-1: decorated answers, VERDICT first, never ok with 0 findings and revise ------------
reset_fakes
mkfake codex "printf '%s\n' 'Here is my review.' '**F1 [major] Intent**' '**claim:** a' '**evidence:** b' '**fix:** c' '### F2 [MINOR] Decisions  ' '- claim: d' '- evidence: e' '- fix: f' '**VERDICT:** revise — decorated'"
run_in "$R" "$SPEC" --only codex --out "$T/o-deco"
expect_grep "r2-1: decorated headers are findings (ok, 2 findings)" '^codex +ok +2 findings +VERDICT: revise — decorated$' "$T/o-deco/summary.txt"
expect_grep "r2-1: decorated header archived in canonical form" '^F2 \[minor\] Decisions$' "$T/o-deco/findings-codex.md"
expect_grep "r2-1: decorated field archived in canonical form" '^claim: d$' "$T/o-deco/findings-codex.md"
expect_grep "r2-1: the dropped preamble is kept in findings-<p>.raw.md" 'Here is my review' "$T/o-deco/findings-codex.raw.md"
mkfake codex "printf '%s\n' 'VERDICT: revise — said first' 'F1 [major] Intent' 'claim: a' 'evidence: b' 'fix: c' 'F2 [minor] Decisions' 'claim: d' 'evidence: e' 'fix: f'"
run_in "$R" "$SPEC" --only codex --out "$T/o-vfirst"
expect_absent "r2-1: VERDICT before the findings is not ok" '^codex +ok' "$T/o-vfirst/summary.txt"
expect_grep "r2-1: VERDICT before the findings is truncated with both findings counted" '^codex +truncated +2 findings' "$T/o-vfirst/summary.txt"
expect_grep "r2-1: the findings after the VERDICT are archived" '^F2 \[minor\] Decisions$' "$T/o-vfirst/findings-codex.md"
mkfake codex "printf '%s\n' 'Some prose.' 'VERDICT: revise — but nothing listed'"
run_in "$R" "$SPEC" --only codex --out "$T/o-zero-revise"
expect_grep "r2-1: 0 findings with a revise VERDICT is truncated, never ok" '^codex +truncated +0 findings' "$T/o-zero-revise/summary.txt"
expect_grep "r2-1: the trim dropped prose from the clean-trim case: raw kept" 'Reviewing now' "$T/o-trim/findings-codex.raw.md"

# ---- R2-2: the last VERDICT line wins ------------------------------------------------------
reset_fakes
mkfake codex "printf '%s\n' 'F1 [major] Intent' 'claim: the document ends with' 'VERDICT: ready — quoted by the document' 'evidence: b' 'fix: c' 'F2 [minor] Decisions' 'claim: d' 'evidence: e' 'fix: f' 'VERDICT: reject — the real one'"
run_in "$R" "$SPEC" --only codex --out "$T/o-quoted-verdict"
expect_grep "r2-2: the verdict is the last VERDICT line, both findings kept" '^codex +ok +2 findings +VERDICT: reject — the real one$' "$T/o-quoted-verdict/summary.txt"
expect_grep "r2-2: the second finding survives a quoted VERDICT line" '^F2 \[minor\] Decisions$' "$T/o-quoted-verdict/findings-codex.md"

# ---- R2-3: other runs' archives are not a worktree change; capped list -----------------------
w=0; for f in "$R/$REVIEWS_REL/$TODAY-$(slug_of docs/superpowers/plans/race.md)"*/summary.txt; do grep -qE "$NOT_TEST_HOOK_WARNING" "$f" && w=$((w + 1)); done
if [ "$w" -eq 0 ]; then ok "r2-3: concurrent runs do not warn about each other's archives"; else bad "r2-3: concurrent runs do not warn about each other's archives" "$w summaries warn"; fi
reset_fakes
mkfake codex "mkdir -p many; for i in \$(seq 1 60); do echo x > many/f\$i.txt; done; cat '$FAKES/findings3.txt'"
run_in "$R" "$SPEC" --only codex --out "$T/o-many"
expect_grep "r2-3: the warning says who may have changed it" '^warning: worktree changed during the run \(by a reviewer or anything else\)' "$T/o-many/summary.txt"
nl=$(wc -l < "$T/o-many/summary.txt" | tr -d ' ')
if [ "$nl" -le 40 ]; then ok "r2-3: the change list in summary.txt is capped ($nl lines)"; else bad "r2-3: the change list in summary.txt is capped" "$nl lines"; fi
expect_grep "r2-3: the cap says how many more" 'and [0-9]+ more' "$T/o-many/summary.txt"
rm -rf "$R/many"

# ---- R2-4: commits, branches, same-size rewrites, chmod, empty dirs, nested repositories ---
reset_fakes
mkfake codex "git -c user.email=r@r -c user.name=r commit -q --allow-empty -m planted; cat '$FAKES/findings3.txt'"
run_in "$R" "$SPEC" --only codex --out "$T/o-commit"
expect_grep "r2-4: a new commit is flagged" '^  git HEAD ' "$T/o-commit/summary.txt"
git -C "$R" reset -q --soft HEAD~1
mkfake codex "git checkout -q -b planted; cat '$FAKES/findings3.txt'"
run_in "$R" "$SPEC" --only codex --out "$T/o-branch"
expect_grep "r2-4: a branch switch is flagged" '^  git branch refs/heads/planted$' "$T/o-branch/summary.txt"
git -C "$R" checkout -q "$FIXTURE_BRANCH"; git -C "$R" branch -q -D planted
# untracked scratch.txt: git status shows "?? scratch.txt" before and after, so only the
# per-file mode and ctime can see these two
mkfake codex "perl -e 'my @s = stat(\"scratch.txt\"); open(my \$h, \">\", \"scratch.txt\"); print \$h \"scratch-X\n\"; close \$h; utime(\$s[8], \$s[9], \"scratch.txt\");'; cat '$FAKES/findings3.txt'"
run_in "$R" "$SPEC" --only codex --out "$T/o-sameshape"
expect_grep "r2-4: a same-size rewrite of an untracked file with the mtime restored is flagged" '^  path scratch\.txt$' "$T/o-sameshape/summary.txt"
mkfake codex "chmod +x scratch.txt; cat '$FAKES/findings3.txt'"
run_in "$R" "$SPEC" --only codex --out "$T/o-chmod"
expect_grep "r2-4: a chmod of an untracked file is flagged" '^  path scratch\.txt$' "$T/o-chmod/summary.txt"
chmod -x "$R/scratch.txt"
mkfake codex "mkdir emptydir; cat '$FAKES/findings3.txt'"
run_in "$R" "$SPEC" --only codex --out "$T/o-emptydir"
expect_grep "r2-4: a new empty directory is flagged" '^  path emptydir$' "$T/o-emptydir/summary.txt"
rmdir "$R/emptydir"
# inside the git-ignored directory, where git status cannot see it
mkfake codex "mkdir ignored/nested && git -C ignored/nested init -q; cat '$FAKES/findings3.txt'"
run_in "$R" "$SPEC" --only codex --out "$T/o-nested"
expect_grep "r2-4: a new nested repository is counted" '^warning: 1 git-ignored path' "$T/o-nested/summary.txt"
expect_out "r2-4: a new nested repository is named on the terminal" 'ignored/nested'
rm -rf "$R/ignored/nested"

# ---- R2-6: error text in the answer or early in the event log is not an error status --------
reset_fakes
mkfake claude "printf '%s\n' 'F1 [major] Intent' 'claim: Unauthorized callers are rejected' 'evidence: b' 'fix: c'; echo 'Segmentation fault' >&2; exit 1"
run_in "$R" "$SPEC" --only claude --out "$T/o-crash-auth"
expect_grep "r2-6: 'Unauthorized' inside a finding of a crashed call is failed:provider" '^claude +failed:provider' "$T/o-crash-auth/summary.txt"
mkfake claude "printf '%s\n' 'F1 [major] Intent' 'claim: there is no usage limit on exports' 'evidence: b' 'fix: c'; echo 'Segmentation fault' >&2; exit 1"
run_in "$R" "$SPEC" --only claude --out "$T/o-crash-quota"
expect_grep "r2-6: 'usage limit' inside a finding of a crashed call is failed:provider" '^claude +failed:provider' "$T/o-crash-quota/summary.txt"
: > "$T/calls-notlogged"
mkfake claude "echo call >> '$T/calls-notlogged'; echo 'Error: Not logged in. Please run /login'; exit 0"
run_in "$R" "$SPEC" --only claude --out "$T/o-notlogged-rc0"
expect_grep "r2-6: 'Not logged in' on stdout with exit 0 is skipped:auth" '^claude +skipped:auth' "$T/o-notlogged-rc0/summary.txt"
n=$(wc -l < "$T/calls-notlogged" | tr -d ' ')
if [ "$n" -eq 1 ]; then ok "r2-6: a signed-out provider is called once, not retried"; else bad "r2-6: a signed-out provider is called once" "$n calls"; fi
mkfake claude "echo 'Error: HTTP 429 Too Many Requests' >&2; exit 1"
run_in "$R" "$SPEC" --only claude --out "$T/o-429"
expect_grep "low: HTTP 429 on stderr is skipped:quota" '^claude +skipped:quota' "$T/o-429/summary.txt"
mkfake claude "echo \"You've hit your limit · resets 5pm\" >&2; exit 1"
run_in "$R" "$SPEC" --only claude --out "$T/o-hitlimit"
expect_grep "low: 'hit your limit' on stderr is skipped:quota" '^claude +skipped:quota' "$T/o-hitlimit/summary.txt"
mkfake claude "echo 'request failed: HTTP 401' >&2; exit 1"
run_in "$R" "$SPEC" --only claude --out "$T/o-http401"
expect_grep "low: HTTP 401 on stderr is skipped:auth" '^claude +skipped:auth' "$T/o-http401/summary.txt"

# ---- R2-7: a burst of early signals leaves no archive and no run directory -------------------
export TMPDIR="$T/tmp-burst"; mkdir -p "$TMPDIR"
reset_fakes; mkfake codex "sleep 5; cat '$FAKES/findings3.txt'"
pids=""
for i in $(seq 1 30); do
  (cd "$R" && exec perl -e 'setpgrp(0, 0); exec @ARGV' "$BASH_BIN" "$SCRIPT" docs/superpowers/plans/burst.md --only codex > /dev/null 2>&1) &
  bp=$!; pids="$pids $bp"
  case $((i % 5)) in 0) ;; 1) sleep 0.01 ;; 2) sleep 0.03 ;; 3) sleep 0.06 ;; 4) sleep 0.1 ;; esac
  # the group exists only once perl has called setpgrp; retry until it does or the run is gone
  until kill -TERM -- -"$bp" 2>/dev/null; do kill -0 "$bp" 2>/dev/null || break; sleep 0.005; done
done
for bp in $pids; do wait "$bp" 2>/dev/null; done
n=$(ls -d "$R/$REVIEWS_REL/$TODAY-$(slug_of docs/superpowers/plans/burst.md)"* 2>/dev/null | wc -l | tr -d ' ')
if [ "$n" -eq 0 ]; then ok "r2-7: thirty runs TERMed early leave no archive"; else bad "r2-7: thirty runs TERMed early leave no archive" "$n left"; fi
n=$(ls -d "$TMPDIR"/ai_review.* 2>/dev/null | wc -l | tr -d ' ')
if [ "$n" -eq 0 ]; then ok "r2-7: thirty runs TERMed early leave no run directory"; else bad "r2-7: thirty runs TERMed early leave no run directory" "$n left"; fi
export TMPDIR="$T/tmp"
# a setup step that is killed right after it created a directory: mkdir and mktemp shims that
# create, then linger; TERM to the group arrives while they linger
MKS="$T/slow-setup"; mkdir -p "$MKS"
printf '#!/bin/bash\n/bin/mkdir "$@" || exit $?\ncase "$*" in *plans-slowmk*) echo x > "%s/mkdir-done"; sleep 3 ;; esac\n' "$T" > "$MKS/mkdir"
printf '#!/bin/bash\nd=$(/usr/bin/mktemp "$@") || exit $?\necho "$d"\ncase "$*" in *tmp-slowmk*) echo x > "%s/mktemp-done"; sleep 3 ;; esac\n' "$T" > "$MKS/mktemp"
chmod +x "$MKS/mkdir" "$MKS/mktemp"
printf '# Slow mkdir plan\n' > "$R/docs/superpowers/plans/slowmk.md"
for step in mkdir mktemp; do
  export TMPDIR="$T/tmp-slowmk-$step"; mkdir -p "$TMPDIR"; rm -f "$T/$step-done"
  reset_fakes; fake_ok codex
  (cd "$R" && PATH="$MKS:$PATH" exec perl -e 'setpgrp(0, 0); exec @ARGV' "$BASH_BIN" "$SCRIPT" docs/superpowers/plans/slowmk.md --only codex > /dev/null 2>&1) &
  bp=$!
  if wait_for_file "$T/$step-done" 10 || [ -e "$T/$step-done" ]; then
    kill -TERM -- -"$bp" 2>/dev/null; wait "$bp" 2>/dev/null
    n=$(ls -d "$R/$REVIEWS_REL/$TODAY-$(slug_of docs/superpowers/plans/slowmk.md)"* 2>/dev/null | wc -l | tr -d ' ')
    if [ "$n" -eq 0 ]; then ok "r2-7: TERM while $step lingers after creating its directory leaves no archive"; else bad "r2-7: TERM while $step lingers leaves no archive" "$n left"; fi
    n=$(ls -d "$TMPDIR"/ai_review.* 2>/dev/null | wc -l | tr -d ' ')
    if [ "$n" -eq 0 ]; then ok "r2-7: TERM while $step lingers after creating its directory leaves no run directory"; else bad "r2-7: TERM while $step lingers leaves no run directory" "$n left"; fi
  else
    bad "r2-7: the slow $step shim ran" "no marker"; kill -KILL -- -"$bp" 2>/dev/null
  fi
  rm -rf "${R:?}/${REVIEWS_REL:?}/$TODAY-$(slug_of docs/superpowers/plans/slowmk.md)"*
done
export TMPDIR="$T/tmp"

# ---- R2-8: only real process groups are kill targets (kill replaced by a recorder) ----------
KC="$T/killcopy"; mkdir -p "$KC"; ln -s "$HERE" "$KC/ai_review"
{ head -1 "$SCRIPT"; printf 'kill() { printf "%%s\\n" "$*" >> "%s"; }\n' "$T/kill.log"; tail -n +2 "$SCRIPT"; } > "$KC/ai_review.sh"
: > "$T/kill.log"
export TMPDIR="$T/tmp-kill"; mkdir -p "$TMPDIR"
reset_fakes; rm -f "$T/kr-prov.pid"
mkfake codex "for d in \"\$TMPDIR\"/ai_review.*/pgids; do for n in 0 1 7 abc 99999999 ../x; do : > \"\$d/\$n\" 2>/dev/null; done; done; echo \$\$ > '$T/kr-prov.pid'; sleep 60 & wait"
SCRIPT_UNDER_TEST="$KC/ai_review.sh" in_pgrp "$SPEC" --only codex --timeout 120 --out "$T/o-killrec"
if wait_for_file "$T/kr-prov.pid" 10; then
  sleep 0.3
  kill -TERM "$SPID" 2>/dev/null        # the script's pid alone, not its group
  wait "$SPID" 2>/dev/null
  prov=$(cat "$T/kr-prov.pid")
  for planted in 0 1 7 abc 99999999 x; do
    if grep -qE -- "(^| )-$planted\$" "$T/kill.log"; then bad "r2-8: a planted pgid file '$planted' is never a kill target" "$(tr '\n' '|' < "$T/kill.log")"
    else ok "r2-8: a planted pgid file '$planted' is never a kill target"; fi
  done
  expect_grep "r2-8: the real provider group is a kill target" "-- -$prov\$" "$T/kill.log"
  kill -KILL -- -"$prov" 2>/dev/null    # the recorder killed nothing: end the group this test started
else
  bad "r2-8: the fake provider started" "no pid file"; kill -KILL -- -"$SPID" 2>/dev/null
fi
export TMPDIR="$T/tmp"

# ---- LOW: signal to the script's pid alone (real kill) ---------------------------------------
reset_fakes; rm -f "$T/sp-prov.pid" "$T/sp-child.pid"
export TMPDIR="$T/tmp-pidonly"; mkdir -p "$TMPDIR"
mkfake codex "echo \$\$ > '$T/sp-prov.pid'; sleep 60 & echo \$! > '$T/sp-child.pid'; wait"
in_pgrp "$SPEC" --only codex --timeout 120 --out "$T/o-pidonly"
if wait_for_file "$T/sp-child.pid" 10; then
  sleep 0.3
  kill -TERM "$SPID"; wait "$SPID"; RC=$?; OUT=$(cat "$T/pgrp.log")
  expect_rc "low: TERM to the script's pid alone exits 143" 143
  expect_dead "low: TERM to the script's pid alone kills the provider" "$T/sp-prov.pid"
  expect_dead "low: TERM to the script's pid alone kills the provider's child" "$T/sp-child.pid"
  expect_nofile "low: TERM to the script's pid alone leaves no archive" "$T/o-pidonly"
  n=$(ls -d "$TMPDIR"/ai_review.* 2>/dev/null | wc -l | tr -d ' ')
  if [ "$n" -eq 0 ]; then ok "low: an interrupted run removes its run directory"; else bad "low: an interrupted run removes its run directory" "$n left"; fi
else
  bad "low: pid-only fake started" "no pid file"; kill -KILL -- -"$SPID" 2>/dev/null
fi
export TMPDIR="$T/tmp"

# ---- LOW: leftovers after a normal exit, a SIGKILLed timer, run directory removal -------------
reset_fakes; rm -f "$T/lo-child.pid"
mkfake codex "sleep 60 > /dev/null 2>&1 & echo \$! > '$T/lo-child.pid'; cat '$FAKES/findings3.txt'"
export TMPDIR="$T/tmp-ok"; mkdir -p "$TMPDIR"
run_in "$R" "$SPEC" --only codex --out "$T/o-leftover"
expect_dead "low: a child the provider left in its group is killed after a normal exit" "$T/lo-child.pid"
n=$(ls -d "$TMPDIR"/ai_review.* 2>/dev/null | wc -l | tr -d ' ')
if [ "$n" -eq 0 ]; then ok "low: an all-ok run removes its run directory"; else bad "low: an all-ok run removes its run directory" "$n left"; fi
export TMPDIR="$T/tmp"
reset_fakes; rm -f "$T/tk-prov.pid"
mkfake codex "echo \$\$ > '$T/tk-prov.pid'; kill -KILL \$PPID; sleep 30"
start=$(date +%s)
run_in "$R" "$SPEC" --only codex --timeout 120 --out "$T/o-timerkill"
el=$(( $(date +%s) - start ))
expect_dead "low: a provider whose timer was SIGKILLed is swept after the run" "$T/tk-prov.pid"
if [ "$el" -lt 15 ]; then ok "low: the run does not wait for the orphaned provider (${el}s)"; else bad "low: the run does not wait for the orphaned provider" "${el}s"; fi

# ---- LOW: other small cases --------------------------------------------------------------------
reset_fakes; fake_ok codex
run_in "$R" "$SPEC" --only codex
D=$(newest_archive)
run_in "$R" "${D#"$R"/}findings-codex.md"
expect_rc "low: reviewing a file inside a review archive is exit 2" 2
mkfake codex "d=\$(ls -dt $REVIEWS_REL/*/ | head -1); echo planted > \"\$d/..planted\"; cat '$FAKES/findings3.txt'"
run_in "$R" "$SPEC" --only codex
D=$(newest_archive)
expect_grep "low: a stray file named ..something inside the archive is flagged" '\.\.planted' "${D}summary.txt"
reset_fakes
mkfake claude "
if grep -q 'first six findings' \"\$1\"; then printf 'F1 [MAJOR] Decisions  \nclaim: d\nevidence: e\nfix: f\n'
elif grep -q 'remaining findings' \"\$1\"; then printf 'F1 [minor] Decisions\nclaim: d\nevidence: e\nfix: f\nVERDICT: revise — one\n'
else printf 'F1 [major] Intent\nclaim: a\n'; fi"
run_in "$R" "$SPEC" --only claude --out "$T/o-dup-case"
# the first answer's finding (Intent) is kept since the cross-review; the two halves' Decisions
# findings differ only in severity case and trailing spaces and merge into one
expect_grep "low: duplicates differing in severity case and trailing spaces are merged" '^claude +ok +2 findings' "$T/o-dup-case/summary.txt"
n=$(grep -c 'Decisions' "$T/o-dup-case/findings-claude.md")
if [ "$n" -eq 1 ]; then ok "low: the merged Decisions finding appears once"; else bad "low: the merged Decisions finding appears once" "$n times"; fi

# =============================================================================================
# Reference additions (one implementation for every repository) and the cross-reviews
# =============================================================================================
skip() { echo "SKIP $1: $2"; }
alive_count() {  # $1 file with one pid per line -> number still alive; kills them
  local n=0 pid
  [ -f "$1" ] || { echo 0; return; }
  while IFS= read -r pid; do
    [ -n "$pid" ] || continue
    if kill -0 "$pid" 2>/dev/null; then n=$((n + 1)); kill -KILL "$pid" 2>/dev/null; fi
  done < "$1"
  echo "$n"
}

# ---- porting: the template and everything below the config block are repository-neutral ------
if grep -qF -- "$AI_REVIEW_PROJECT" "$HERE/prompt.md"; then bad "porting: prompt.md does not name the project" "found"; else ok "porting: prompt.md does not name the project"; fi
for ph in '{{DOC_PATH}}' '{{PROJECT}}' '{{ORIENTATION}}' '{{DOC_LAYOUT}}'; do
  if grep -qF -- "$ph" "$HERE/prompt.md"; then ok "porting: prompt.md has the placeholder $ph"; else bad "porting: prompt.md has the placeholder $ph" "missing"; fi
done
sed '1,/^# <<< ai_review config/d' "$SCRIPT" > "$T/below-config.sh"
# (a bare file name such as AGENTS.md may appear in a generic comment about a CLI; the config's
# own entries may not)
for v in "$AI_REVIEW_PROJECT" "$REVIEWS_REL" "${ORIENTATION%%|*}" "$DOC_LAYOUT"; do
  short=$(printf '%s' "$v" | cut -c1-40)
  if grep -qF -- "$v" "$T/below-config.sh"; then bad "porting: nothing below the config block repeats '$short'" "found"; else ok "porting: nothing below the config block repeats '$short'"; fi
done
for f in "$SCRIPT" "$HERE/selftest.sh"; do
  if /bin/bash -n "$f" 2>/dev/null; then ok "portable: /bin/bash -n accepts ${f##*/}"; else bad "portable: /bin/bash -n accepts ${f##*/}" "syntax error"; fi
done

# ---- test hook warning ---------------------------------------------------------------------
reset_fakes; fake_ok codex
run_in "$R" "$SPEC" --only codex --out "$T/o-hookwarn"
expect_grep "hook: a run that used a test hook says so" '^warning: test hook AI_REVIEW_BIN_CODEX is set' "$T/o-hookwarn/summary.txt"
expect_absent "hook: the shim run (no hook) has no test-hook warning" '^warning: test hook' "$T/o-shim/summary.txt"

# ---- provenance ------------------------------------------------------------------------------
expect_grep "provenance: summary records the document's blob id" "^document-blob: $(git -C "$R" hash-object "$SPEC")\$" "$T/o-hookwarn/summary.txt"
expect_grep "provenance: summary records the commit" "^commit: $(git -C "$R" rev-parse HEAD)\$" "$T/o-hookwarn/summary.txt"

# ---- archived stderr: only matched error lines of a non-ok provider, masked -----------------
reset_fakes; fake_ok codex
mkfake claude "echo 'debug: harmless chatter key=sk-ant-api03-PLANTEDPLANTEDPLANTED' >&2
echo 'Error: 401 Unauthorized token ghp_PLANTEDabcdefghijklmnopqrstuvwxyz012345 (Request ID: 9732:2B5B47:131D65:13FEB5:6AFB2801) reading /Users/someone/.config/claude/auth.json' >&2
exit 1"
mkfake copilot "echo 'Error: transient noise on a call that succeeds' >&2; cat '$FAKES/findings3.txt'"
run_in "$R" "$SPEC" --only codex,claude,copilot --out "$T/o-stderr"
expect_grep "stderr: the non-ok provider's error is in the summary as class and code" '^error: claude: class=auth code=401$' "$T/o-stderr/summary.txt"
for planted in 'ghp_PLANTED' '9732:2B5B47' '/Users/someone' 'sk-ant-api03' 'harmless chatter'; do
  if grep -rqF -- "$planted" "$T/o-stderr"; then bad "stderr: '$planted' never reaches the archive" "found"; else ok "stderr: '$planted' never reaches the archive"; fi
done
expect_absent "stderr: an ok provider's stderr never reaches the summary" 'transient noise' "$T/o-stderr/summary.txt"

# ---- ignored documents, policy "archive privately" ---------------------------------------------
IGN="${IGNORED_REVIEWS_REL:-private-reviews}"
ARCHIVE_COPY=$(policy_copy archive "$IGN")
printf '# Secret plan\n\n## Intent\n' > "$R/private/secret-plan.md"
SECRET="private/secret-plan.md"
before=$(git -C "$R" status --porcelain --untracked-files=all)
reset_fakes; fake_ok codex
run_copy "$ARCHIVE_COPY" "$R" "$SECRET" --only codex
expect_rc "policy archive: a git-ignored document is reviewed" 0
expect_file "policy archive: its archive is under the git-ignored reviews directory" "$R/$IGN/$TODAY-$(slug_of "$SECRET")/summary.txt"
after=$(git -C "$R" status --porcelain --untracked-files=all)
if [ "$before" = "$after" ]; then ok "policy archive: nothing visible to git appeared"; else bad "policy archive: nothing visible to git appeared" "$(diff <(echo "$before") <(echo "$after") | tr '\n' ' ')"; fi
if grep -rqF -e secret-plan -e "$IGN" "$R/$REVIEWS_REL" 2>/dev/null; then bad "policy archive: no tracked archive names the ignored document" "found"; else ok "policy archive: no tracked archive names the ignored document"; fi
for o in "$R/sub/o-tracked" "$T/away/../repo/sub/o-dots"; do
  run_copy "$ARCHIVE_COPY" "$R" "$SECRET" --only codex --out "$o"
  expect_rc "policy archive: a tracked --out is refused ($(basename "$o"))" 2
done
expect_nofile "policy archive: the refused --out was not created" "$R/sub/o-tracked"
ln -s "$R/sub" "$T/link-to-sub"
run_copy "$ARCHIVE_COPY" "$R" "$SECRET" --only codex --out "$T/link-to-sub/o-link"
expect_rc "policy archive: an --out through a symlink into the tracked tree is refused" 2
UPPER=$(printf '%s' "$R" | tr '[:lower:]' '[:upper:]')
if [ "$UPPER" != "$R" ] && [ -d "$UPPER/sub" ]; then
  run_copy "$ARCHIVE_COPY" "$R" "$SECRET" --only codex --out "$UPPER/sub/o-case"
  expect_rc "policy archive: a differently-cased spelling of a tracked --out is refused" 2
  expect_nofile "policy archive: nothing written through the other spelling" "$R/sub/o-case"
else skip "policy archive: case-variant --out" "case-sensitive filesystem"; fi
OTHER="$T/other-repo"; mkdir -p "$OTHER"; git -C "$OTHER" init -q -b work
run_copy "$ARCHIVE_COPY" "$R" "$SECRET" --only codex --out "$OTHER/o-other"
expect_rc "policy archive: an --out in another repository's tracked tree is refused" 2
run_copy "$ARCHIVE_COPY" "$R" "$SECRET" --only codex --out "$T/o-private-outside"
expect_rc "policy archive: an --out outside any repository is accepted" 0
run_copy "$ARCHIVE_COPY" "$R" "$SECRET" --only codex --out "$R/ignored/o-private"
expect_rc "policy archive: an --out in a git-ignored directory is accepted" 0
ln -s "$SECRET" "$R/link-secret.md"
run_copy "$ARCHIVE_COPY" "$R" link-secret.md --only codex
expect_rc "policy archive: a symlink to an ignored document is refused" 2
rm -f "$R/link-secret.md"
BADIGN=$(policy_copy badign "sub/not-ignored")
run_copy "$BADIGN" "$R" "$SECRET" --only codex
expect_rc "policy archive: an ignored reviews directory that git does not ignore is refused" 2
reset_fakes; mkfake codex "sleep 1; cat '$FAKES/findings3.txt'"
(cd "$R" && "$BASH_BIN" "$ARCHIVE_COPY" "$SECRET" --only codex > /dev/null 2>&1) &
cp1=$!
run_copy "$ARCHIVE_COPY" "$R" "$SPEC" --only codex --out "$T/o-concurrent-tracked"
wait "$cp1"
if grep -qF -e secret-plan -e "$IGN" "$T/o-concurrent-tracked/summary.txt"; then bad "policy archive: a concurrent run's summary never names the ignored document" "found"; else ok "policy archive: a concurrent run's summary never names the ignored document"; fi
REFUSE_RUN=$(policy_copy refuse "")
run_copy "$REFUSE_RUN" "$R" "$SECRET" --only codex
expect_rc "policy refuse: the same ignored document is exit 2 with an empty ignored reviews directory" 2
rm -rf "${R:?}/${IGN:?}" "${R:?}/ignored/o-private"

# ---- env-file preflight ----------------------------------------------------------------------
unset AI_REVIEW_BIN_CODEX AI_REVIEW_BIN_COPILOT AI_REVIEW_BIN_CLAUDE
shim_run() {  # $1 dir, rest: arguments; real command lines through the shims
  local d="$1"; shift
  rm -f "$T/argv-codex"
  OUT=$(cd "$d" && PATH="$SHIMS:$SYS_PATH" "$BASH_BIN" "$SCRIPT" "$@" < /dev/null 2>&1); RC=$?
}
rm -f "$T/argv-codex"
mkfifo "$R/.env"     # a FIFO: if the script ever opened it, the run would hang
OUT=$(cd "$R" && PATH="$SHIMS:$SYS_PATH" perl -e 'alarm 60; exec @ARGV' "$BASH_BIN" "$SCRIPT" "$SPEC" --out "$T/o-envfile" < /dev/null 2>&1); RC=$?
expect_rc "env-file: the run finishes without opening the env file (exit 0)" 0
expect_grep "env-file: codex is skipped:unconfined" '^codex +skipped:unconfined' "$T/o-envfile/summary.txt"
expect_grep "env-file: the hint names the flag" '^hint: codex: .*env file.*--allow-unconfined' "$T/o-envfile/summary.txt"
expect_out "env-file: the file name is on the terminal" '^  \.env$'
expect_nofile "env-file: codex is never called" "$T/argv-codex"
expect_grep "env-file: claude (confined) still runs" '^claude +ok' "$T/o-envfile/summary.txt"
expect_grep "env-file: copilot (confined) still runs" '^copilot +ok' "$T/o-envfile/summary.txt"
shim_run "$R" "$SPEC" --only codex --allow-unconfined --out "$T/o-envfile-allowed"
expect_grep "env-file: --allow-unconfined lets codex run" '^codex +ok' "$T/o-envfile-allowed/summary.txt"
rm -f "$R/.env"
for f in .env.example .env.sample .env.template; do : > "$R/$f"; done
shim_run "$R" "$SPEC" --only codex --out "$T/o-envfile-examples"
expect_grep "env-file: example, sample and template files do not count" '^codex +ok' "$T/o-envfile-examples/summary.txt"
: > "$R/.env.local"
shim_run "$R" "$SPEC" --only codex --out "$T/o-envfile-local"
expect_grep "env-file: .env.local counts" '^codex +skipped:unconfined' "$T/o-envfile-local/summary.txt"
rm -f "$R/.env.local" "$R/.env.example" "$R/.env.sample" "$R/.env.template"
WT="$T/linked-wt"; git -C "$R" worktree add -q -b wt-review "$WT" 2>/dev/null
: > "$R/.env"
shim_run "$WT" "$SPEC" --only codex --out "$T/o-envfile-wt"
expect_grep "env-file: an env file in the main checkout of a linked worktree counts" '^codex +skipped:unconfined' "$T/o-envfile-wt/summary.txt"
expect_out "env-file: the terminal says it is in the main checkout" '\.env \(main checkout\)$'
rm -f "$R/.env"
reset_fakes
mkfake codex "printf 'x.y = 1\n' >> \"\$(git rev-parse --git-dir)/config.worktree\"; cat '$FAKES/findings3.txt'"
run_in "$WT" "$SPEC" --only codex --out "$T/o-wt-configworktree"
expect_grep "snapshot: config.worktree of a linked worktree is watched" 'config\.worktree' "$T/o-wt-configworktree/summary.txt"

# ---- snapshot blind spots ----------------------------------------------------------------------
reset_fakes
mkfake codex "echo planted >> .git/info/exclude; cat '$FAKES/findings3.txt'"
run_in "$R" "$SPEC" --only codex --out "$T/o-exclude"
expect_grep "snapshot: .git/info/exclude is watched" 'info/exclude' "$T/o-exclude/summary.txt"
mkfake codex "echo '* text' >> .git/info/attributes; cat '$FAKES/findings3.txt'"
run_in "$R" "$SPEC" --only codex --out "$T/o-attributes"
expect_grep "snapshot: .git/info/attributes is watched" 'info/attributes' "$T/o-attributes/summary.txt"
rm -f "$R/.git/info/attributes"
mkfake codex "git tag planted-tag; cat '$FAKES/findings3.txt'"
run_in "$R" "$SPEC" --only codex --out "$T/o-tag"
expect_grep "snapshot: a new tag is watched" 'refs/tags/planted-tag' "$T/o-tag/summary.txt"
git -C "$R" tag -d planted-tag > /dev/null
printf '#!/bin/sh\n' > "$R/.git/hooks/post-checkout"
mkfake codex "chmod +x .git/hooks/post-checkout; cat '$FAKES/findings3.txt'"
run_in "$R" "$SPEC" --only codex --out "$T/o-hookmode"
expect_grep "snapshot: a hook's mode change is watched" 'hooks/post-checkout' "$T/o-hookmode/summary.txt"
rm -f "$R/.git/hooks/post-checkout"
mkdir -p "$T/external-hooks"; printf '#!/bin/sh\n' > "$T/external-hooks/pre-push"
git -C "$R" config core.hooksPath "$T/external-hooks"
mkfake codex "echo 'curl planted' >> '$T/external-hooks/pre-push'; cat '$FAKES/findings3.txt'"
run_in "$R" "$SPEC" --only codex --out "$T/o-hookspath"
expect_grep "snapshot: the core.hooksPath target is watched" 'pre-push' "$T/o-hookspath/summary.txt"
git -C "$R" config --unset core.hooksPath
export TMPDIR="$R/tmp-in-repo"; mkdir -p "$TMPDIR"
reset_fakes; fake_ok codex
run_in "$R" "$SPEC" --only codex --out "$T/o-tmp-in-repo"
expect_absent "snapshot: the run's own directory inside the repository is not a change" "$NOT_TEST_HOOK_WARNING" "$T/o-tmp-in-repo/summary.txt"
export TMPDIR="$T/tmp"; rm -rf "${R:?}/tmp-in-repo"
touch "$R/AGENTS.md"   # stat-dirty: a plain git status would rewrite the index
idx_before=$(perl -e 'print((stat shift)[9])' "$R/.git/index")
sleep 1.1
run_in "$R" "$SPEC" --only codex --out "$T/o-index"
idx_after=$(perl -e 'print((stat shift)[9])' "$R/.git/index")
if [ "$idx_before" = "$idx_after" ]; then ok "snapshot: git status never rewrites the index (GIT_OPTIONAL_LOCKS=0)"; else bad "snapshot: git status never rewrites the index" "index mtime changed"; fi
git -C "$R" status > /dev/null

# ---- header and verdict forms ------------------------------------------------------------------
reset_fakes
mkfake codex "printf '%s\n' '**F1** [major] Intent' 'claim: a' 'evidence: b' 'fix: c' '- F2 [minor] Decisions' 'claim: d' 'evidence: e' 'fix: f' '1. F3 [hunch] Acceptance' 'claim: g' 'evidence: not checked' 'fix: h' '**F4** [blocker] Scope' 'claim: i' 'evidence: j' 'fix: k' 'F5 [minor] Plain' 'claim: l' 'evidence: m' 'fix: n' '**VERDICT:** revise — forms'"
run_in "$R" "$SPEC" --only codex --out "$T/o-forms"
expect_grep "forms: **F1**, '- F2', '1. F3', **F4** then a plain F5 are all findings" '^codex +ok +5 findings +VERDICT: revise — forms$' "$T/o-forms/summary.txt"
mkfake codex "printf '%s\n' 'F1 [major] Intent' 'claim: the doc quotes' '> VERDICT: ready — quoted' 'evidence: b' 'fix: c' 'VERDICT: readyness is undefined in the document'"
run_in "$R" "$SPEC" --only codex --out "$T/o-notverdicts"
expect_absent "forms: a quoted '> VERDICT:' and 'VERDICT: readyness' are not verdicts" '^codex +ok' "$T/o-notverdicts/summary.txt"
expect_file "forms: no real verdict means the two-half retry ran" "$T/o-notverdicts/findings-codex.raw.md"
mkfake codex "printf '%s\n' 'F1 [major] Intent' 'claim: a' 'evidence: b' 'fix: c' 'VERDICT: ready — fine' 'F2 [minor] Late' 'claim: d' 'evidence: e' 'fix: f'"
run_in "$R" "$SPEC" --only codex --out "$T/o-verdict-mid"
expect_grep "forms: a VERDICT followed by another finding is not the verdict" '^codex +truncated +2 findings' "$T/o-verdict-mid/summary.txt"

# ---- retry: the first answer's findings are never lost --------------------------------------------
reset_fakes
mkfake claude "
if grep -q 'remaining findings' \"\$1\"; then echo 'ERROR: 500 Internal Server Error' >&2; exit 1; fi
if grep -q 'first six findings' \"\$1\"; then printf 'F1 [major] Intent\nclaim: a\nevidence: b\nfix: c\n'; exit 0; fi
printf 'F1 [major] Intent\nclaim: a\nevidence: b\nfix: c\nF2 [minor] Only in the first answer\nclaim: z\nevidence: y\nfix: x\n'"
run_in "$R" "$SPEC" --only claude --out "$T/o-retry-keep"
expect_grep "retry: a failed half keeps the first answer's findings in findings-<p>.md" '^F2 \[minor\] Only in the first answer$' "$T/o-retry-keep/findings-claude.md"
expect_grep "retry: ... with the failing status" '^claude +failed:provider +2 findings' "$T/o-retry-keep/summary.txt"
mkfake claude "
if grep -q 'first six findings' \"\$1\"; then printf 'F1 [major] Intent\nclaim: a\nevidence: b\nfix: c\n'; exit 0; fi
if grep -q 'remaining findings' \"\$1\"; then printf 'VERDICT: revise — halves forgot one\n'; exit 0; fi
printf 'F1 [major] Intent\nclaim: a\nevidence: b\nfix: c\nF2 [minor] Only in the first answer\nclaim: z\nevidence: y\nfix: x\n'"
run_in "$R" "$SPEC" --only claude --out "$T/o-retry-fewer"
expect_grep "retry: halves with fewer findings keep the first answer's" '^F2 \[minor\] Only in the first answer$' "$T/o-retry-fewer/findings-claude.md"

# ---- failed:model hint per provider ----------------------------------------------------------------
mkfake codex "echo 'Error: Model \"gone-1\" from --model flag is not available.' >&2; exit 1"
run_in "$R" "$SPEC" --only codex --out "$T/o-codex-model"
expect_grep "model: the codex hint names AI_REVIEW_CODEX_MODEL" '^hint: codex: .*AI_REVIEW_CODEX_MODEL' "$T/o-codex-model/summary.txt"
# the message the real codex-cli 0.167.1 printed (twice) for a model a ChatGPT account cannot use
mkfake codex "echo \"ERROR: The 'gone-2' model is not supported when using Codex with a ChatGPT account.\" >&2; echo \"ERROR: The 'gone-2' model is not supported when using Codex with a ChatGPT account.\" >&2; exit 1"
run_in "$R" "$SPEC" --only codex --out "$T/o-codex-model-chatgpt"
expect_grep "model: codex's 'model is not supported' is failed:model" '^codex +failed:model' "$T/o-codex-model-chatgpt/summary.txt"
n=$(grep -c '^error: codex: ' "$T/o-codex-model-chatgpt/summary.txt")
if [ "$n" -eq 1 ]; then ok "stderr: a repeated error line is archived once"; else bad "stderr: a repeated error line is archived once" "$n times"; fi
expect_grep "model: codex is pinned to a model in its models cache (gpt-6.1-sol)" '^models: codex=gpt-6\.1-sol$' "$T/o-codex-model-chatgpt/summary.txt"

# ---- a signal after summary.txt is written keeps the archive -----------------------------------
LATE="$T/latecopy"; mkdir -p "$LATE"; ln -s "$HERE" "$LATE/ai_review"
perl -0pe 's{(\} > "\$OUT/summary\.txt"[^\n]*\n)}{$1echo x > "'"$T"'/summary-written"; sleep 3\n}' "$SCRIPT" > "$LATE/ai_review.sh"
if grep -q 'summary-written' "$LATE/ai_review.sh"; then
  reset_fakes; fake_ok codex; rm -f "$T/summary-written"
  SCRIPT_UNDER_TEST="$LATE/ai_review.sh" in_pgrp "$SPEC" --only codex --out "$T/o-late-signal"
  if wait_for_file "$T/summary-written" 15; then
    kill -TERM "$SPID"; wait "$SPID" 2>/dev/null
    expect_file "late signal: a TERM after summary.txt is written keeps the archive" "$T/o-late-signal/summary.txt"
  else bad "late signal: the copy reached the summary" "no marker"; kill -KILL -- -"$SPID" 2>/dev/null; fi
else bad "late signal: the summary hook could be injected" "pattern not found"; fi

# ---- signals to the script's pid alone, swept across the launch window and the retry boundary ----
reset_fakes
for p in codex copilot claude; do mkfake "$p" "echo \$\$ >> '$T/sweep.pids'; sleep 30 & echo \$! >> '$T/sweep.pids'; wait"; done
survivors=0; trials=0
for sig in TERM INT; do
  for d in 0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1.0; do
    : > "$T/sweep.pids"; trials=$((trials + 1))
    in_pgrp "$SPEC" --out "$T/o-sweep-$sig-$d"
    sleep "$d"; kill -"$sig" "$SPID" 2>/dev/null; wait "$SPID" 2>/dev/null
    sleep 1.5
    n=$(alive_count "$T/sweep.pids"); survivors=$((survivors + n))
    [ "$n" -eq 0 ] || echo "    survivor(s) after SIG$sig at ${d}s: $n"
    kill -KILL -- -"$SPID" 2>/dev/null
  done
done
if [ "$survivors" -eq 0 ]; then ok "sweep: SIGTERM/SIGINT to the pid alone across the launch window leaves no provider ($trials trials)"; else bad "sweep: no provider survives a signal in the launch window" "$survivors survivors in $trials trials"; fi
reset_fakes
mkfake claude "
if grep -q -e 'first six findings' -e 'remaining findings' \"\$1\"; then echo \$\$ >> '$T/sweep.pids'; sleep 30 & echo \$! >> '$T/sweep.pids'; wait; exit 0; fi
printf 'F1 [major] Intent\nclaim: a\n'"
survivors=0; trials=0
for sig in TERM INT; do
  for d in 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.5 0.6; do
    : > "$T/sweep.pids"; trials=$((trials + 1))
    in_pgrp "$SPEC" --only claude --out "$T/o-rsweep-$sig-$d"
    sleep "$d"; kill -"$sig" "$SPID" 2>/dev/null; wait "$SPID" 2>/dev/null
    sleep 1.5
    n=$(alive_count "$T/sweep.pids"); survivors=$((survivors + n))
    [ "$n" -eq 0 ] || echo "    survivor(s) after SIG$sig at ${d}s (retry): $n"
    kill -KILL -- -"$SPID" 2>/dev/null
  done
done
if [ "$survivors" -eq 0 ]; then ok "sweep: a signal around the retry boundary leaves no provider ($trials trials)"; else bad "sweep: no provider survives a signal at the retry boundary" "$survivors survivors in $trials trials"; fi

# ---- INT when the script inherited SIGINT ignored (how a background shell starts it) -------------
reset_fakes; rm -f "$T/ign-prov.pid"
mkfake codex "echo \$\$ > '$T/ign-prov.pid'; sleep 30 & wait"
(cd "$R" && exec perl -e '$SIG{INT} = "IGNORE"; setpgrp(0, 0); exec @ARGV' "$BASH_BIN" "$SCRIPT" "$SPEC" --only codex --out "$T/o-int-ignored" > /dev/null 2>&1) &
SPID=$!
if wait_for_file "$T/ign-prov.pid" 10; then
  kill -INT "$SPID"; sleep 1
  if kill -0 "$SPID" 2>/dev/null; then ok "int-ignored: an inherited-ignored SIGINT does not stop the run (the documented limit)"; else bad "int-ignored: the documented limit holds" "the script exited"; fi
  kill -TERM "$SPID"; wait "$SPID"; RC=$?
  expect_rc "int-ignored: TERM still stops it" 143
  expect_dead "int-ignored: TERM still kills the provider" "$T/ign-prov.pid"
else bad "int-ignored: the fake started" "no pid file"; kill -KILL -- -"$SPID" 2>/dev/null; fi

# ---- races found under load: a group signal inside a command substitution that holds a path ----
inject_copy() {  # $1 name, $2 perl substitution -> path of a script copy (empty when the pattern did not apply)
  local d="$T/inject-$1"; mkdir -p "$d"; [ -e "$d/ai_review" ] || ln -s "$HERE" "$d/ai_review"
  perl -0pe "$2" "$SCRIPT" > "$d/ai_review.sh"
  if cmp -s "$d/ai_review.sh" "$SCRIPT"; then printf ''; else printf '%s' "$d/ai_review.sh"; fi
}
for which in RUN OUT; do
  c=$(inject_copy "race-$which" 's{cd "\$'"$which"'" && pwd -P}{cd "\$'"$which"'" && echo x > "'"$T"'/race-'"$which"'" && sleep 2 && pwd -P}')
  if [ -z "$c" ]; then bad "race ($which): the path resolution could be delayed in a copy" "pattern not found"; continue; fi
  export TMPDIR="$T/tmp-race-$which"; mkdir -p "$TMPDIR"; rm -f "$T/race-$which"
  reset_fakes; fake_ok codex
  SCRIPT_UNDER_TEST="$c" in_pgrp "$SPEC" --only codex --out "$T/o-race-$which"
  if wait_for_file "$T/race-$which" 10; then
    kill -TERM -- -"$SPID" 2>/dev/null; wait "$SPID" 2>/dev/null
    n=$(ls -d "$TMPDIR"/ai_review.* 2>/dev/null | wc -l | tr -d ' ')
    if [ "$n" -eq 0 ]; then ok "race ($which): TERM while resolving the $which path leaves no run directory"; else bad "race ($which): no run directory left" "$n left"; fi
    expect_nofile "race ($which): TERM while resolving the $which path leaves no archive" "$T/o-race-$which"
  else bad "race ($which): the delayed copy reached the resolution" "no marker"; kill -KILL -- -"$SPID" 2>/dev/null; fi
  export TMPDIR="$T/tmp"
done

# ---- the window between a timer's fork and its group registration --------------------------------
c=$(inject_copy late-register 's{(    if \(open\(my \$f, ">", "\$dir/\$pid"\)\))}{    select(undef, undef, undef, 2);\n$1}')
if [ -n "$c" ]; then
  reset_fakes; rm -f "$T/lr-prov.pid"
  mkfake codex "echo \$\$ > '$T/lr-prov.pid'; sleep 30 & wait"
  SCRIPT_UNDER_TEST="$c" in_pgrp "$SPEC" --only codex --timeout 120 --out "$T/o-late-register"
  if wait_for_file "$T/lr-prov.pid" 10; then
    sleep 0.3; kill -TERM "$SPID"; wait "$SPID" 2>/dev/null
    expect_dead "window: a provider whose timer has not registered its group yet still dies on TERM to the pid" "$T/lr-prov.pid"
  else bad "window: the fake started" "no pid file"; kill -KILL -- -"$SPID" 2>/dev/null; fi
else bad "window: the registration could be delayed in a copy" "pattern not found"; fi

# ---- a provider's stderr that echoes repository text never reaches the summary --------------------
reset_fakes
# an echoed file line that even starts like an error, far from the end (outside the 20-line tail),
# and one inside the tail that only contains the word: neither may reach the summary
mkfake codex "echo 'Error: quoted from private/early-notes.md' >&2
for i in \$(seq 1 30); do echo \"echoed line \$i\" >&2; done
echo '  the error handler failed silently in private/notes.md' >&2
echo 'ERROR: stream disconnected before completion' >&2
exit 1"
run_in "$R" "$SPEC" --only codex --out "$T/o-echo-stderr"
expect_grep "stderr: the provider's error is recorded as class and code" '^error: codex: class=provider code=-$' "$T/o-echo-stderr/summary.txt"
expect_absent "stderr: an echoed line inside the tail that only contains 'error' is not kept" 'error handler|private/notes' "$T/o-echo-stderr/summary.txt"
expect_absent "stderr: an error-shaped echoed line outside the tail is not kept" 'early-notes' "$T/o-echo-stderr/summary.txt"

# =============================================================================================
# Review round 3
# =============================================================================================

# ---- R3-1: findings survive a later auth or quota failure ------------------------------------------
TWO_FINDINGS="F1 [major] Intent\nclaim: a\nevidence: b\nfix: c\nF2 [blocker] Scope\nclaim: the blocker\nevidence: e\nfix: f\n"
for kind in quota auth; do
  case "$kind" in quota) msg='Error: You have exceeded your quota' ;; auth) msg='Error: 401 Unauthorized' ;; esac
  reset_fakes
  mkfake claude "
if grep -q 'remaining findings' \"\$1\"; then echo '$msg' >&2; exit 1; fi
if grep -q 'first six findings' \"\$1\"; then printf 'F1 [major] Intent\nclaim: a\nevidence: b\nfix: c\n'; exit 0; fi
printf '$TWO_FINDINGS'"
  run_in "$R" "$SPEC" --only claude --out "$T/o-r31-half-$kind"
  expect_grep "r3-1: a retry half failing with $kind keeps the first answer's findings (count)" "^claude +skipped:$kind +2 findings" "$T/o-r31-half-$kind/summary.txt"
  expect_grep "r3-1: ... and archives the blocker" '^F2 \[blocker\] Scope$' "$T/o-r31-half-$kind/findings-claude.md"
  mkfake claude "printf '$TWO_FINDINGS'; echo '$msg' >&2; exit 1"
  run_in "$R" "$SPEC" --only claude --out "$T/o-r31-first-$kind"
  expect_grep "r3-1: a first call with findings, then a $kind error, keeps them (count)" "^claude +skipped:$kind +2 findings" "$T/o-r31-first-$kind/summary.txt"
  expect_grep "r3-1: ... and archives the blocker" '^F2 \[blocker\] Scope$' "$T/o-r31-first-$kind/findings-claude.md"
done

# ---- R3-2: absolute paths are rewritten relative or flagged -------------------------------------
reset_fakes
mkfake codex "printf '%s\n' 'Reading $R/STATUS.md first.' 'F1 [minor] Intent' 'claim: a' 'evidence: $R/AGENTS.md says so' 'fix: c' 'VERDICT: ready — fine'"
run_in "$R" "$SPEC" --only codex --out "$T/o-r32-inside"
if grep -rqF -- "$R/" "$T/o-r32-inside"/findings-codex*.md; then bad "r3-2: no absolute repository path is archived" "found $R/"; else ok "r3-2: no absolute repository path is archived"; fi
expect_grep "r3-2: an absolute path inside the repository is rewritten relative" '^evidence: AGENTS\.md says so$' "$T/o-r32-inside/findings-codex.md"
expect_grep "r3-2: ... in the raw file too" 'Reading STATUS\.md first' "$T/o-r32-inside/findings-codex.raw.md"
expect_absent "r3-2: ... and not flagged" "$NOT_TEST_HOOK_WARNING" "$T/o-r32-inside/summary.txt"
for p in 'file:///Users/someone/notes.txt' '/mnt/data/someone/x' '/srv/app/secret' '/nix/store/abc' '/workspace/other/x' 'C:\Users\someone\log'; do
  mkfake codex "printf '%s\n' 'F1 [minor] Intent' 'claim: a' 'evidence: $p' 'fix: c' 'VERDICT: ready — fine'"
  run_in "$R" "$SPEC" --only codex --out "$T/o-r32-out-$RANDOM"
  expect_out "r3-2: '$p' is flagged as outside the repository" '^warning: findings-codex\.md names paths outside the repository'
done
reset_fakes
mkfake codex "printf '%s\n' 'F1 [minor] Intent' 'claim: a' 'evidence: $R/AGENTS.md in the main checkout' 'fix: c' 'VERDICT: ready — fine'"
run_in "$WT" "$SPEC" --only codex --out "$T/o-r32-main"
expect_grep "r3-2: the main checkout's root is rewritten relative too" '^evidence: AGENTS\.md in the main checkout$' "$T/o-r32-main/findings-codex.md"

# ---- R3-3: git-ignored names with quoting characters stay off the summary --------------------------
while IFS= read -r q; do printf 'x\n' > "$R/ignored/$q"; done <<< "$(printf '%s\n' "müşteri-gizli.txt" "tab$(printf '\t')name.txt" 'quote"name.txt' 'back\slash.txt')"
reset_fakes
mkfake codex "for f in ignored/*name.txt ignored/müşteri-gizli.txt ignored/back*slash.txt; do printf 'y\n' > \"\$f\"; done; cat '$FAKES/findings3.txt'"
run_in "$R" "$SPEC" --only codex --out "$T/o-r33"
for frag in 'gizli' 'm\\303' 'tab' 'quote' 'slash'; do
  expect_absent "r3-3: a git-ignored name ('$frag') is never in summary.txt" "$frag" "$T/o-r33/summary.txt"
done
expect_grep "r3-3: the changed ignored paths are counted" '^warning: 4 git-ignored path' "$T/o-r33/summary.txt"
rm -f "$R"/ignored/*name.txt "$R/ignored/müşteri-gizli.txt" "$R"/ignored/back*slash.txt

# ---- R3-4: a forged or incomplete last line is not a verdict ------------------------------------
reset_fakes
mkfake codex "printf '%s\n' 'F1 [major] Intent' 'claim: a' 'evidence: b' '**Verdict:** ready for release'"
run_in "$R" "$SPEC" --only codex --out "$T/o-r34-forged"
expect_absent "r3-4: '**Verdict:** ready for release' after an incomplete finding is not ok" '^codex +ok' "$T/o-r34-forged/summary.txt"
expect_grep "r3-4: ... it is truncated with its finding kept" '^codex +truncated +1 findings' "$T/o-r34-forged/summary.txt"
mkfake codex "printf '%s\n' 'F1 [major] Intent' 'claim: a' 'evidence: b' 'fix: c' 'VERDICT: Ready — capitalised keyword'"
run_in "$R" "$SPEC" --only codex --out "$T/o-r34-case"
expect_absent "r3-4: 'VERDICT: Ready' (capitalised keyword) is not a verdict" '^codex +ok' "$T/o-r34-case/summary.txt"
mkfake codex "printf '%s\n' 'F1 [major] Intent' 'claim: a' 'evidence: b' 'fix: c' 'F2 [minor] Late' 'claim: d' 'VERDICT: ready — but F2 is incomplete'"
run_in "$R" "$SPEC" --only codex --out "$T/o-r34-incomplete"
expect_grep "r3-4: an incomplete last finding is truncated, both findings kept" '^codex +truncated +2 findings' "$T/o-r34-incomplete/summary.txt"

# ---- R3-5: SIGKILL to the script's group; pid file -----------------------------------------------
reset_fakes; rm -f "$T/k9-prov.pid"
mkfake codex "echo \$\$ > '$T/k9-prov.pid'; sleep 30 & wait"
in_pgrp "$SPEC" --only codex --timeout 120 --out "$T/o-kill9"
if wait_for_file "$T/k9-prov.pid" 10; then
  pf=$(sed -n 's/^ai_review: pid [0-9]* (pid file \(.*\)); stop it with kill -TERM.*/\1/p' "$T/pgrp.log" | head -1)
  if [ -n "$pf" ] && [ "$(cat "$pf" 2>/dev/null)" = "$SPID" ]; then ok "r3-5: the first output line names a pid file holding the script's pid"; else bad "r3-5: pid file named first" "$(head -2 "$T/pgrp.log" | tr '\n' '|')"; fi
  kill -KILL -- -"$SPID" 2>/dev/null; wait "$SPID" 2>/dev/null
  expect_dead "r3-5: SIGKILL to the script's group still takes the provider down (watchdog)" "$T/k9-prov.pid"
else bad "r3-5: the fake started" "no pid file"; kill -KILL -- -"$SPID" 2>/dev/null; fi
rm -rf "${T:?}/o-kill9"

# ---- R3-6: the config is checked against the repository ---------------------------------------------
BADREV=$(policy_copy badreviews "")
sed -i '' 's|^REVIEWS_REL=.*|REVIEWS_REL="ignored/reviews"|' "$BADREV" 2>/dev/null || sed -i 's|^REVIEWS_REL=.*|REVIEWS_REL="ignored/reviews"|' "$BADREV"
reset_fakes; fake_ok codex
run_copy "$BADREV" "$R" "$SPEC" --only codex --out "$T/o-r36-badrev"
expect_rc "r3-6: a tracked reviews directory that git ignores is refused" 2
run_copy "$BADIGN" "$R" "$SPEC" --only codex --out "$T/o-r36-badign"
expect_rc "r3-6: an ignored reviews directory that git does not ignore is refused for any document" 2
MISSOR=$(policy_copy missingorient "")
sed -i '' 's#^ORIENTATION="#ORIENTATION="missing/notes.md:gone|#' "$MISSOR" 2>/dev/null || sed -i 's#^ORIENTATION="#ORIENTATION="missing/notes.md:gone|#' "$MISSOR"
run_copy "$MISSOR" "$R" "$SPEC" --only codex --out "$T/o-r36-missor"
expect_rc "r3-6: a missing orientation file does not stop the run" 0
expect_out "r3-6: ... it is warned about on the terminal" 'orientation file not found: missing/notes\.md'

# ---- R3-7: env files at any depth, .envrc, names off the summary, Claude denied reading them --------
unset AI_REVIEW_BIN_CODEX AI_REVIEW_BIN_COPILOT AI_REVIEW_BIN_CLAUDE
mkdir -p "$R/sub/deep"; : > "$R/sub/deep/.env"
shim_run "$R" "$SPEC" --only codex --out "$T/o-r37-deep"
expect_grep "r3-7: an env file at any depth counts" '^codex +skipped:unconfined' "$T/o-r37-deep/summary.txt"
expect_absent "r3-7: env file names are not in summary.txt" '\.env|sub/deep' "$T/o-r37-deep/summary.txt"
expect_grep "r3-7: summary.txt only counts them" '^warning: env files: 1, names on the terminal' "$T/o-r37-deep/summary.txt"
expect_out "r3-7: the names are on the terminal" 'sub/deep/\.env'
rm -f "$R/sub/deep/.env"; : > "$R/.envrc"
shim_run "$R" "$SPEC" --only codex --out "$T/o-r37-envrc"
expect_grep "r3-7: .envrc counts" '^codex +skipped:unconfined' "$T/o-r37-envrc/summary.txt"
rm -f "$R/.envrc"
shim_run "$R" "$SPEC" --only claude --out "$T/o-r37-claude"
v=$(argval "$T/argv-claude" --disallowedTools)
case "$v" in *'Read(**/.env)'*'Read(**/.env.*)'*'Read(**/.envrc)'*) ok "r3-7: claude is denied reading env files ($v)" ;; *) bad "r3-7: claude is denied reading env files" "got '$v'" ;; esac

# ---- R3-8: nothing of a provider's stderr text reaches the summary ---------------------------------
reset_fakes
mkfake claude "echo 'Error: account jane.doe@example.com (octocat-private) has no access to org acme-secret; see C:\Users\jane\log and /mnt/data/jane/x' >&2; exit 1"
run_in "$R" "$SPEC" --only claude --out "$T/o-r38"
expect_grep "r3-8: the summary carries the error class and code only" '^error: claude: class=provider code=-$' "$T/o-r38/summary.txt"
for s in 'jane' 'octocat-private' 'acme-secret' 'C:' '/mnt/data'; do
  if grep -qF -- "$s" "$T/o-r38/summary.txt"; then bad "r3-8: '$s' is not in the summary" "found"; else ok "r3-8: '$s' is not in the summary"; fi
done

# ---- R3-9: a set but empty test hook --------------------------------------------------------------
reset_fakes; fake_ok copilot
OUT=$(cd "$R" && AI_REVIEW_BIN_CODEX='' "$BASH_BIN" "$SCRIPT" "$SPEC" --out "$T/o-r39" 2>&1); RC=$?
expect_rc "r3-9: AI_REVIEW_BIN_CODEX set but empty is exit 2" 2

# ---- R3-10: both spellings of Copilot's trusted folders ----------------------------------------------
unset AI_REVIEW_BIN_CODEX AI_REVIEW_BIN_COPILOT AI_REVIEW_BIN_CLAUDE
CPH="$T/copilot-home-snake"; mkdir -p "$CPH"
printf '{ "trusted_folders": ["%s"] }\n' "$R" > "$CPH/config.json"
rm -f "$T/argv-copilot"
OUT=$(cd "$R" && COPILOT_HOME="$CPH" PATH="$SHIMS:$SYS_PATH" "$BASH_BIN" "$SCRIPT" "$SPEC" --only copilot --out "$T/o-r310" 2>&1); RC=$?
expect_out "r3-10: a trusted_folders entry (snake case) is refused too" '^copilot +failed:provider'
expect_nofile "r3-10: ... and copilot is never called" "$T/argv-copilot"

# ---- R3-3 fail closed: git check-ignore failing must not get ignored names into summary.txt -------
c=$(inject_copy ignore-fails 's{git -C "\$ROOT" -c core\.quotePath=false check-ignore --stdin -z}{sh -c "exit 128"}')
if [ -n "$c" ]; then
  printf 'secret-before\n' > "$R/ignored/fail-closed-probe.txt"
  reset_fakes
  mkfake codex "printf 'secret-after\n' > ignored/fail-closed-probe.txt; cat '$FAKES/findings3.txt'"
  run_copy "$c" "$R" "$SPEC" --only codex --out "$T/o-r33-failclosed"
  expect_absent "r3-3: with git check-ignore failing, a changed ignored name stays off summary.txt" 'fail-closed-probe' "$T/o-r33-failclosed/summary.txt"
  expect_grep "r3-3: ... and is counted as ignored" '^warning: [0-9]+ git-ignored path' "$T/o-r33-failclosed/summary.txt"
  rm -f "$R/ignored/fail-closed-probe.txt"
else bad "r3-3: check-ignore could be made to fail in a copy" "pattern not found"; fi

echo
echo "ai_review selftest: $pass passed, $failn failed"
[ "$failn" -eq 0 ]
