#!/usr/bin/env bash
# ai_review.sh — send one markdown document to up to three independent reviewer CLIs (codex,
# copilot, claude) in parallel, each with flags that keep it from writing and from loading this
# repository's or the user's assistant customisations (see "What the flags do and do not
# guarantee" below); archive their answers; never fail the run because one provider failed.
# The judgement (merge, re-verify, fold back) is the /spec-review skill's job:
# .claude/skills/spec-review/SKILL.md. Everything repository-specific is in the config block
# below; the rest of this file, scripts/ai_review/prompt.md and scripts/ai_review/selftest.sh are
# the same in every repository that uses them.
#
# Usage: scripts/ai_review.sh <doc.md> [--only codex,copilot,claude] [--out <dir>] [--timeout <s>]
#                                      [--allow-unconfined]
#   Run from anywhere inside the repository, on a branch that is not protected. The document is
#   a regular (not symlinked) .md file in the repository whose path holds no control character,
#   outside the reviews directories. A git-ignored document is refused, or, when
#   IGNORED_REVIEWS_REL is set, archived there (and --out must then be git-ignored too, or
#   outside every repository).
# Exit: 0 when at least one provider is ok, 1 when none is, 2 on a usage error, 128+n when
#   interrupted by signal n (INT, TERM, HUP) before the summary was written; such a run leaves no
#   archive and no run directory. A signal after the summary was written keeps the archive.
#   SIGINT limit: a shell that starts this script in the background (a non-interactive shell
#   does, and so does an agent's background tool) leaves SIGINT ignored, and an ignored signal
#   cannot be trapped; stop such a run with TERM.
#
# Provider status, one of: ok, truncated, timeout, skipped:not-installed, skipped:auth,
#   skipped:quota, skipped:unconfined, failed:model, failed:provider.
#   skipped:unconfined: an env file (.env, .env.* except *.example, *.sample, *.template) exists
#   in the repository root or, for a linked worktree, in the main checkout, and the provider's
#   file reads are not confined to the repository (today: codex). The file is never opened. Pass
#   --allow-unconfined to run such a provider anyway.
#
# Archive: <REVIEWS_REL>/<YYYY-MM-DD>-<slug>/ (or <IGNORED_REVIEWS_REL>/... for an ignored
#   document), claimed with mkdir: a same-day or concurrent rerun takes -r2, -r3, ...; an existing
#   directory is never written into. It holds prompt.md, findings-<provider>.md (the answer in
#   canonical form, from its first finding or VERDICT line through its last VERDICT line),
#   findings-<provider>.raw.md (the whole first answer, when the trim dropped text or the answer
#   was retried) and summary.txt (document, its blob id, the commit, date, models, statuses,
#   counts, verdicts, hints, warnings). Answer files are findings-<provider>.md, never
#   <provider>.md: on a case-insensitive filesystem (macOS) claude.md IS CLAUDE.md, which Claude
#   Code loads as instructions, and reviewer output is untrusted data. A provider's stderr is
#   never archived as such: for a non-ok provider, up to three of its error lines go into
#   summary.txt with paths, request ids and token-shaped strings masked. The run directory (raw
#   output, stderr) is removed when every provider is ok and kept, its path printed, otherwise.
#
# What the flags do and do not guarantee:
#   - Every provider runs with a scrubbed environment: env -i plus an allow-list (the basics, and
#     each provider's own credential variables, never another provider's; no base-URL, proxy or
#     instruction variables), in its own process group under a per-call timer. A provider child
#     that starts a process group of its own (setsid) is outside that group and is not killed by
#     the timeout or by an interruption.
#   - No provider is given a write tool or a shell that can write (codex: read-only sandbox;
#     copilot: read and search tools only, writes, shell and URLs denied; claude: Read, Grep and
#     Glob only). The worktree snapshot below detects writes that happen anyway.
#   - Claude's file tools are confined to the repository (--restricted); Copilot's paths to its
#     working directory by default (no --allow-all-paths, temp directory disallowed); Codex reads
#     are not confined. None of this keeps a provider from reading git-ignored files inside the
#     repository, which the skill screens for before an archive is committed.
#   - Each CLI still reads its own login and its own home directory (~/.codex, ~/.copilot,
#     ~/.claude): user configuration is skipped only as far as the flags say.
#
# Environment:
#   AI_REVIEW_COPILOT_MODEL  Copilot model (default below; GitHub retires models, so it is pinned
#                            for reproducibility and overridable without editing the script)
#   AI_REVIEW_CODEX_MODEL    Codex model (default below)
#   AI_REVIEW_CLAUDE_MODEL   Claude model alias (default below)
#   COPILOT_HOME             read to refuse a run when Copilot trusts this folder; passed on
#   AI_REVIEW_BIN_CODEX, AI_REVIEW_BIN_COPILOT, AI_REVIEW_BIN_CLAUDE
#                            Test hook: when set, the script runs "$BIN <prompt-file>" from the
#                            repository root instead of the real command line (no flags; the
#                            same scrubbed environment), and summary.txt carries a
#                            "warning: test hook" line. A path that is not an executable file
#                            reads as skipped:not-installed. It is how scripts/ai_review/selftest.sh
#                            injects fakes; never point it at a real CLI.
#
# Bash 3.2 compatible (macOS /bin/bash; inside $( ... ) every case pattern carries its leading
# parenthesis). No eval: provider names are checked against a fixed list before any use.
set -uo pipefail
export LC_ALL=C

# >>> ai_review config: the only repository-specific part; edit this block when copying >>>
AI_REVIEW_PROJECT="jet_office: a pure-Dart library that generates, reads and modifies XLSX and DOCX files, a pub workspace"
REVIEWS_REL="docs/reviews"               # tracked archive directory, relative to the repository root
IGNORED_REVIEWS_REL="docs/superpowers/reviews" # git-ignored archive directory for git-ignored documents; empty: refuse them
PROTECTED_BRANCHES="main"                # space-separated; the script and the skill refuse to run on them
ORIENTATION="AGENTS.md:the rules every agent follows and where the project stands|docs/decisions/:the decision records; an accepted one is never edited, a later one supersedes it|docs/docx-model.md:the DOCX model's rules, each with its test|docs/xlsx-model.md:the XLSX workbook model's rules, each with its test"
DOC_LAYOUT="Specs and plans live in the git-ignored docs/superpowers/ (specs/, plans/), decision records in docs/decisions/, the rules of each layer in docs/*.md."
SLUG_STRIP="docs/superpowers/ docs/"     # prefixes dropped from the document path to form the archive slug
# <<< ai_review config <<<

# ---------- signals: recorded until the archive is claimed, then handled ----------
CLAIMED=0; DONE=0; OUT=""; RUN=""; PENDING=""
trap 'PENDING="INT 130"' INT
trap 'PENDING="TERM 143"' TERM
trap 'PENDING="HUP 129"' HUP

HERE="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE="$HERE/ai_review/prompt.md"
PROVIDERS_ALL="codex copilot claude"
UNCONFINED_PROVIDERS="codex"
COPILOT_MODEL="${AI_REVIEW_COPILOT_MODEL:-gpt-6.1-sol}"
CODEX_MODEL="${AI_REVIEW_CODEX_MODEL:-gpt-6.1-sol}"   # gpt-5.5 is refused for ChatGPT-account logins (codex-cli 0.167.1)
CLAUDE_MODEL="${AI_REVIEW_CLAUDE_MODEL:-fable}"
VERDICT_MAX=200
CHANGES_MAX=20
STRICT_VERDICT_RE='^VERDICT: (ready|revise|reject)([^A-Za-z]|$)'
HEADER_RE='^F[0-9]+ \['

usage() {
  echo "usage: scripts/ai_review.sh <doc.md> [--only codex,copilot,claude] [--out <dir>] [--timeout <seconds>] [--allow-unconfined]" >&2
  exit 2
}
die2() {  # a usage or setup error; removes what this run created
  echo "ai_review: $*" >&2
  [ "$CLAIMED" = 1 ] && [ -n "$OUT" ] && rm -rf "$OUT"
  [ -n "$RUN" ] && rm -rf "$RUN"
  exit 2
}

# A pgid file name is a kill target only when it is a number of at least two digits (never 0
# or 1) and ps reports that process as the leader of exactly that group.
valid_pgid() {
  case "$1" in ''|*[!0-9]*|0*) return 1 ;; esac
  [ "${#1}" -ge 2 ] || return 1
  local g; g=$(ps -o pgid= -p "$1" 2>/dev/null | tr -d ' ')
  [ "$g" = "$1" ]
}
kill_groups() {  # $1 signal: every valid registered provider group
  local f n
  [ -n "$RUN" ] && [ -d "$RUN/pgids" ] || return 0
  for f in "$RUN"/pgids/*; do
    [ -e "$f" ] || continue
    n="${f##*/}"
    if valid_pgid "$n"; then kill -"$1" -- "-$n" 2>/dev/null; fi
  done
}
on_signal() {  # $1 name, $2 exit code; tolerates a run that has created nothing yet
  trap '' INT TERM HUP
  local pids
  kill_groups TERM
  # each provider job forwards TERM to its timer, which takes its group down
  pids=$(jobs -p 2>/dev/null); [ -z "$pids" ] || kill -TERM $pids 2>/dev/null
  if [ -n "$RUN" ] && [ -d "$RUN/pgids" ]; then sleep 1; kill_groups KILL; fi
  if [ "$DONE" = 1 ]; then
    [ -n "$RUN" ] && rm -rf "$RUN"
    echo "ai_review: interrupted by SIG$1 after the summary was written; archive kept: $OUT" >&2
    exit "$2"
  fi
  [ "$CLAIMED" = 1 ] && [ -n "$OUT" ] && rm -rf "$OUT"
  [ -n "$RUN" ] && rm -rf "$RUN"
  echo "ai_review: interrupted by SIG$1; nothing archived" >&2
  exit "$2"
}
# noint <cmd...>: a setup step that creates something runs with the three signals ignored, so a
# signal sent to the whole process group cannot kill it after it created a directory and before
# the script recorded it; the script has recorded the signal and acts on it once armed.
noint() { ( trap '' INT TERM HUP; exec "$@" ); }
arm_signals() {
  trap 'on_signal INT 130' INT
  trap 'on_signal TERM 143' TERM
  trap 'on_signal HUP 129' HUP
  if [ -n "$PENDING" ]; then
    # shellcheck disable=SC2086
    set -- $PENDING; on_signal "$1" "$2"
  fi
}

# ---------- arguments ----------
DOC=""; ONLY=""; ONLY_SET=0; TIMEOUT=600; ALLOW_UNCONFINED=0
while [ $# -gt 0 ]; do
  case "$1" in
    --only)    [ $# -ge 2 ] || usage; ONLY="$2"; ONLY_SET=1; shift 2 ;;
    --out)     [ $# -ge 2 ] && [ -n "$2" ] || usage; OUT="$2"; shift 2 ;;
    --timeout) [ $# -ge 2 ] || usage; TIMEOUT="$2"; shift 2 ;;
    --allow-unconfined) ALLOW_UNCONFINED=1; shift ;;
    -h|--help) usage ;;
    -*)        echo "ai_review: unknown option: $1" >&2; usage ;;
    *)         [ -z "$DOC" ] || { echo "ai_review: one document only" >&2; usage; }; DOC="$1"; shift ;;
  esac
done
[ -n "$DOC" ] || usage
# checked as strings before any splitting or arithmetic
case "$TIMEOUT" in ''|*[!0-9]*|0*) die2 "--timeout must be a positive integer number of seconds" ;; esac
[ "${#TIMEOUT}" -le 6 ] || die2 "--timeout is at most six digits"
case "$DOC" in *[[:cntrl:]]*) die2 "refusing a document path with a control character" ;; esac
case "$OUT" in *[[:cntrl:]]*) die2 "refusing an --out path with a control character" ;; esac

if [ "$ONLY_SET" = 1 ]; then
  [ -n "$ONLY" ] || die2 "--only needs at least one provider (codex, copilot, claude)"
  case "$ONLY" in *[!a-z,]*) die2 "--only takes provider names separated by commas" ;; esac
  PROVIDERS=""
  rest="$ONLY,"
  while [ -n "$rest" ]; do
    p="${rest%%,*}"; rest="${rest#*,}"
    case "$p" in
      codex|copilot|claude) ;;
      '') die2 "--only: empty provider name" ;;
      *)  die2 "--only: unknown provider (expected codex, copilot, claude)" ;;
    esac
    case " $PROVIDERS " in *" $p "*) die2 "--only: duplicate provider $p" ;; esac
    PROVIDERS="$PROVIDERS $p"
  done
  PROVIDERS="${PROVIDERS# }"
else
  PROVIDERS="$PROVIDERS_ALL"
fi

# a test hook that is set but empty would silently fall through to the real CLI
for v in AI_REVIEW_BIN_CODEX AI_REVIEW_BIN_COPILOT AI_REVIEW_BIN_CLAUDE; do
  if [ -n "${!v+set}" ] && [ -z "${!v}" ]; then die2 "$v is set but empty; unset it"; fi
done

# ---------- document, repository, branch ----------
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || die2 "not inside a git repository"
ROOT_AS_GIT_SAYS="$ROOT"
ROOT="$(cd "$ROOT" && pwd -P)"
BRANCH="$(git -C "$ROOT" symbolic-ref -q --short HEAD 2>/dev/null)" || die2 "refusing a detached HEAD; check out a branch first"
for b in $PROTECTED_BRANCHES; do
  [ "$BRANCH" != "$b" ] || die2 "refusing the protected branch $b; branch first"
done
# the config block is checked against this repository: a "tracked" reviews directory that git
# ignores, or an "ignored" one that git tracks, would put archives where nobody expects them
if git -C "$ROOT" check-ignore -q -- "$REVIEWS_REL/probe" 2>/dev/null; then
  die2 "config: REVIEWS_REL ($REVIEWS_REL) is git-ignored here; archives there would never be committed"
fi
if [ -n "$IGNORED_REVIEWS_REL" ] && ! git -C "$ROOT" check-ignore -q -- "$IGNORED_REVIEWS_REL/probe" 2>/dev/null; then
  die2 "config: IGNORED_REVIEWS_REL ($IGNORED_REVIEWS_REL) is not git-ignored here"
fi
[ ! -L "$DOC" ] || die2 "refusing a symlinked document: $DOC"
[ -f "$DOC" ] || die2 "document not found: $DOC"
case "$DOC" in *.md) ;; *) die2 "not a markdown document: $DOC" ;; esac
DOC_ABS="$(cd "$(dirname "$DOC")" && pwd -P)/$(basename "$DOC")"
case "$DOC_ABS" in *[[:cntrl:]]*) die2 "refusing a document path with a control character" ;; esac
case "$DOC_ABS" in
  "$ROOT"/*) REL="${DOC_ABS#"$ROOT"/}" ;;
  *) die2 "document is outside the repository $ROOT: $DOC" ;;
esac
case "$REL" in "$REVIEWS_REL"/*) die2 "refusing to review a review archive: $REL" ;; esac
if [ -n "$IGNORED_REVIEWS_REL" ]; then
  case "$REL" in "$IGNORED_REVIEWS_REL"/*) die2 "refusing to review a review archive: $REL" ;; esac
fi
IGNORED_DOC=0
if git -C "$ROOT" check-ignore -q -- "$REL" 2>/dev/null; then
  # A git-ignored document never has its review archived under the tracked reviews directory:
  # the prompt and the answers would carry ignored content into the repository.
  [ -n "$IGNORED_REVIEWS_REL" ] || die2 "refusing a git-ignored document (no ignored reviews directory is configured): $REL"
  IGNORED_DOC=1
fi
[ -f "$TEMPLATE" ] || die2 "prompt template missing: $TEMPLATE"
printf '%s' "$ORIENTATION" | tr '|' '\n' | while IFS= read -r entry; do
  op="${entry%%:*}"
  [ -z "$op" ] || [ -e "$ROOT/$op" ] || echo "ai_review: warning: orientation file not found: $op" >&2
done
ARCHIVE_REL="$REVIEWS_REL"; [ "$IGNORED_DOC" = 1 ] && ARCHIVE_REL="$IGNORED_REVIEWS_REL"

# resolve_path <abs path>: prints "<deepest existing directory, physical>\t<rest to create>".
# Components are taken one by one: an existing directory is resolved physically (symlinks, the
# filesystem's own spelling), ".." goes to the physical parent, and a ".." in the part still to
# be created cancels the last such part, as mkdir -p would; once that part is empty again,
# existing directories are resolved again.
resolve_path() {
  perl -MCwd=realpath -e '
    my @c = grep { length && $_ ne "." } split m{/}, shift;
    my ($cur, @rest) = ("/");
    for my $c (@c) {
      if ($c eq "..") {
        if (@rest) { pop @rest; } else { $cur =~ s{/[^/]+$}{}; $cur = "/" if $cur eq ""; }
        next;
      }
      my $cand = ($cur eq "/" ? "" : $cur) . "/$c";
      if (!@rest && -d $cand) { $cur = realpath($cand); } else { push @rest, $c; }
    }
    print $cur, "\t", join("/", @rest);' "$1"
}
# out_is_private <abs path>: exit 0 when the path is outside every repository, or git-ignored in
# the repository that contains it. Decided by git from the deepest existing directory, never by
# comparing path strings.
out_is_private() {
  local r anc rest
  r="$(resolve_path "$1")" || return 1
  anc="${r%%$'\t'*}"; rest="${r#*$'\t'}"
  git -C "$anc" rev-parse --show-toplevel > /dev/null 2>&1 || return 0
  [ -n "$rest" ] || return 1
  git -C "$anc" check-ignore -q -- "$rest" 2>/dev/null
}

# ---------- run directory and prompt (before any archive exists) ----------
RUN="$(noint mktemp -d "${TMPDIR:-/tmp}/ai_review.XXXXXX")" || die2 "cannot create a temporary directory"
# a path is never assigned straight from a command substitution: a signal to the process group
# can kill the subshell, and an empty result would lose track of a directory this run created
r=$(cd "$RUN" && pwd -P) && [ -n "$r" ] && RUN="$r"
RUN_REL="//none//"; case "$RUN" in "$ROOT"/*) RUN_REL="${RUN#"$ROOT"/}" ;; esac
mkdir -p "$RUN/pgids" || die2 "cannot create $RUN/pgids"
echo "$$" > "$RUN/pid" || die2 "cannot write $RUN/pid"
echo "ai_review: pid $$ (pid file $RUN/pid); stop it with kill -TERM \"\$(cat $RUN/pid)\", never with SIGKILL"
ORIENT_TEXT=$(printf '%s' "$ORIENTATION" | perl -ne '
  my @e = map { my ($p, $d) = split(/:/, $_, 2); defined $d && length $d ? "$p ($d)" : $p } split(/\|/, $_);
  print join(", then ", @e);')
DOC_PATH="$REL" P_PROJECT="$AI_REVIEW_PROJECT" P_ORIENT="$ORIENT_TEXT" P_LAYOUT="$DOC_LAYOUT" perl -pe '
  s/\{\{DOC_PATH\}\}/$ENV{DOC_PATH}/g; s/\{\{PROJECT\}\}/$ENV{P_PROJECT}/g;
  s/\{\{ORIENTATION\}\}/$ENV{P_ORIENT}/g; s/\{\{DOC_LAYOUT\}\}/$ENV{P_LAYOUT}/g;' "$TEMPLATE" > "$RUN/prompt.md" || die2 "cannot render the prompt"
if grep -q '{{' "$RUN/prompt.md"; then die2 "unrendered placeholder left in the prompt"; fi
DOC_BLOB="$(git -C "$ROOT" hash-object -- "$REL" 2>/dev/null || echo unknown)"
HEAD_COMMIT="$(git -C "$ROOT" rev-parse -q --verify HEAD 2>/dev/null || echo none)"

# ---------- env-file preflight (names only; the files are never opened) ----------
GIT_COMMON="$(git -C "$ROOT" rev-parse --git-common-dir 2>/dev/null || true)"
case "$GIT_COMMON" in ''|/*) ;; *) GIT_COMMON="$(cd "$ROOT" && cd "$GIT_COMMON" && pwd -P)" ;; esac
MAIN_CHECKOUT=""
case "$GIT_COMMON" in */.git) [ "${GIT_COMMON%/.git}" = "$ROOT" ] || MAIN_CHECKOUT="${GIT_COMMON%/.git}" ;; esac
# every spelling of the roots an answer may use: physical, as git printed it, and without the
# /private prefix macOS puts in front of /var and /tmp
ROOT_SPELLINGS=""
for r in "$ROOT" "$ROOT_AS_GIT_SAYS" "$MAIN_CHECKOUT"; do
  [ -n "$r" ] || continue
  ROOT_SPELLINGS="$ROOT_SPELLINGS$r"$'\n'
  case "$r" in /private/*) ROOT_SPELLINGS="$ROOT_SPELLINGS${r#/private}"$'\n' ;; esac
done
# Candidates at any depth: tracked, untracked and git-ignored files (git ls-files, NUL-separated),
# plus whatever sits in the root itself (a FIFO or socket is not listed by git). Names only; the
# names go to the terminal, summary.txt gets a count.
env_files_in() {  # $1 directory, $2 label suffix; prints one name per line
  {
    git -C "$1" -c core.quotePath=false ls-files -z --cached --others --exclude-standard 2>/dev/null
    git -C "$1" -c core.quotePath=false ls-files -z --others --ignored --exclude-standard 2>/dev/null
    for f in "$1"/.env "$1"/.env.* "$1"/.envrc; do
      [ -e "$f" ] || [ -L "$f" ] || continue
      printf '%s\0' "${f##*/}"
    done
  } | LABEL="$2" perl -0ne '
    chomp; my $b = (split m{/}, $_)[-1] // "";
    next unless $b eq ".env" || $b eq ".envrc" || $b =~ /^\.env\./;
    next if $b =~ /\.(?:example|sample|template)$/;
    s/[\x00-\x1f\x7f]/?/g; print "$_$ENV{LABEL}\n";' | sort -u
}
ENV_LIST="$(env_files_in "$ROOT" "")"
[ -z "$MAIN_CHECKOUT" ] || ENV_LIST="$ENV_LIST${ENV_LIST:+$'\n'}$(env_files_in "$MAIN_CHECKOUT" " (main checkout)")"
ENV_LIST="$(printf '%s\n' "$ENV_LIST" | sed '/^$/d')"
ENV_COUNT=$(printf '%s\n' "$ENV_LIST" | grep -c . || true)

# ---------- archive: claimed with a plain mkdir ----------
slug_for() {  # docs/superpowers/specs/2026-10-24-x-design.md -> specs-2026-10-24-x-design (per SLUG_STRIP)
  local s="$1" pre
  for pre in $SLUG_STRIP; do s="${s#"$pre"}"; done
  s="${s%.md}"
  printf '%s' "$s" | tr '/ ' '--'
}
TODAY=$(date +%Y-%m-%d)
if [ -z "$OUT" ]; then
  mkdir -p "$ROOT/$ARCHIVE_REL" || die2 "cannot create $ROOT/$ARCHIVE_REL"
  base="$ROOT/$ARCHIVE_REL/$TODAY-$(slug_for "$REL")"
  OUT="$base"; n=2
  until noint mkdir "$OUT" 2>/dev/null; do
    [ -e "$OUT" ] || die2 "cannot create $OUT"
    OUT="$base-r$n"; n=$((n + 1))
  done
else
  case "$OUT" in /*) ;; *) OUT="$PWD/$OUT" ;; esac
  if [ "$IGNORED_DOC" = 1 ]; then
    if ! out_is_private "$OUT"; then
      OUT_FAILED="$OUT"; OUT=""
      die2 "refusing an --out that git does not ignore for a git-ignored document: $OUT_FAILED"
    fi
    r="$(resolve_path "$OUT")"; OUT="${r%%$'\t'*}/${r#*$'\t'}"   # create exactly what was checked
  fi
  mkdir -p "$(dirname "$OUT")" 2>/dev/null
  if ! noint mkdir "$OUT" 2>/dev/null; then
    OUT_FAILED="$OUT"; OUT=""
    die2 "archive directory already exists or cannot be created, refusing: $OUT_FAILED"
  fi
fi
CLAIMED=1
r=$(cd "$OUT" && pwd -P) && [ -n "$r" ] && OUT="$r"
OUT_REL=""
case "$OUT" in "$ROOT"/*) OUT_REL="${OUT#"$ROOT"/}" ;; esac
cp "$RUN/prompt.md" "$OUT/prompt.md" || die2 "cannot write $OUT/prompt.md"
arm_signals

# ---------- worktree snapshot ----------
# Git state (HEAD, the current branch, every ref, git status without taking the index lock) and
# every path under the repository with type and mode, and for files sub-second mtime, ctime and
# size; git-ignored files included. Left out: the reviews directories (other runs write there;
# this run's archive is checked by name below) and this run's own directory. A nested repository
# or worktree is recorded by its top directory only. Plus the git configuration, hooks, info
# files and config.worktree of the git dir and the common dir, and the core.hooksPath target.
GIT_DIR_ABS="$(git -C "$ROOT" rev-parse --absolute-git-dir 2>/dev/null || true)"
HOOKS_PATH="$(git -C "$ROOT" config --get core.hooksPath 2>/dev/null || true)"
case "$HOOKS_PATH" in ''|/*) ;; \~/*) HOOKS_PATH="$HOME/${HOOKS_PATH#\~/}" ;; *) HOOKS_PATH="$ROOT/$HOOKS_PATH" ;; esac
snapshot() {
  {
    echo "G HEAD $(GIT_OPTIONAL_LOCKS=0 git -C "$ROOT" rev-parse -q --verify HEAD 2>/dev/null || echo none)"
    echo "G branch $(GIT_OPTIONAL_LOCKS=0 git -C "$ROOT" symbolic-ref -q HEAD 2>/dev/null || echo detached)"
    GIT_OPTIONAL_LOCKS=0 git -C "$ROOT" for-each-ref --format='G ref %(refname) %(objectname)' 2>/dev/null
    GIT_OPTIONAL_LOCKS=0 git -C "$ROOT" status --porcelain --untracked-files=all 2>/dev/null \
      | grep -vF -e " $REVIEWS_REL/" -e " ${IGNORED_REVIEWS_REL:-//none//}/" -e " $RUN_REL/" | sed 's/^/S /'
    perl -MFile::Find -MTime::HiRes=lstat -e '
      my ($root, $reviews, $ignored, $run, $gitdir, $common, $hooks) = @ARGV;
      sub show { my $p = shift;
        return $1 if $p =~ m{^\Q$root\E/(.*)$};
        $p =~ s{^\Q$common\E}{<git-common-dir>} if length $common;
        $p =~ s{^\Q$gitdir\E}{<git-dir>} if length $gitdir;
        $p =~ s{^\Q$hooks\E}{<core.hooksPath>} if length $hooks;
        return $p; }
      sub entry { my $p = shift; my @s = lstat($p) or return;
        if (-l _) { printf "P L %o %s -> %s\n", $s[2], show($p), readlink($p) // ""; }
        elsif (-d _) { printf "P D %o %s\n", $s[2], show($p); }
        else { printf "P F %o %.6f %.6f %d %s\n", $s[2], $s[9], $s[10], $s[7], show($p); } }
      find({ no_chdir => 1, wanted => sub {
        my $p = $File::Find::name;
        return if $p eq $root;
        if (-d $p && !-l $p) {
          if ($p eq "$root/.git" || $p eq "$root/$reviews" || (length $ignored && $p eq "$root/$ignored") || $p eq $run) {
            $File::Find::prune = 1; return;
          }
          if (-e "$p/.git") { printf "P N %s\n", show($p); $File::Find::prune = 1; return; }
        }
        entry($p);
      }}, $root);
      for my $d (grep { length } ($common, $gitdir)) {
        entry("$d/config"); entry("$d/config.worktree");
        for my $sub ("hooks", "info") {
          next unless -d "$d/$sub";
          find({ no_chdir => 1, wanted => sub { entry($File::Find::name) } }, "$d/$sub");
        }
      }
      if (length $hooks && -d $hooks) { find({ no_chdir => 1, wanted => sub { entry($File::Find::name) } }, $hooks); }
    ' "$ROOT" "$REVIEWS_REL" "$IGNORED_REVIEWS_REL" "$RUN" "$GIT_DIR_ABS" "$GIT_COMMON" "$HOOKS_PATH" 2>/dev/null
  } | sort | uniq
}
BEFORE=$(snapshot)

# ---------- provider invocation ----------
hook_for() {
  case "$1" in
    codex)   printf '%s' "${AI_REVIEW_BIN_CODEX:-}" ;;
    copilot) printf '%s' "${AI_REVIEW_BIN_COPILOT:-}" ;;
    claude)  printf '%s' "${AI_REVIEW_BIN_CLAUDE:-}" ;;
  esac
}
bin_for() {  # the binary to run (hook or PATH), "" when none
  local h; h=$(hook_for "$1")
  if [ -n "$h" ]; then printf '%s' "$h"; else command -v "$1" 2>/dev/null || true; fi
}
installed() { local b; b=$(bin_for "$1"); [ -n "$b" ] && [ -f "$b" ] && [ -x "$b" ]; }
unconfined() { case " $UNCONFINED_PROVIDERS " in *" $1 "*) return 0 ;; esac; return 1; }

# provider_env <provider>: fills ENVV with NAME=value for the allow-listed variables that are
# set: the basics, and the provider's own credential variables (its login can live there).
# Never another provider's credentials, base-URL redirects, proxies or instruction variables.
provider_env() {
  local n v extra=""
  case "$1" in
    codex)   extra="CODEX_HOME OPENAI_API_KEY" ;;
    copilot) extra="COPILOT_HOME GH_TOKEN GITHUB_TOKEN COPILOT_GITHUB_TOKEN GH_HOST XDG_CONFIG_HOME XDG_STATE_HOME XDG_CACHE_HOME" ;;
    claude)  extra="ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN CLAUDE_CODE_OAUTH_TOKEN CLAUDE_CONFIG_DIR" ;;
  esac
  ENVV=()
  for n in HOME USER LOGNAME PATH SHELL TERM LANG TMPDIR TZ SSL_CERT_FILE SSL_CERT_DIR NODE_EXTRA_CA_CERTS $extra; do
    v="${!n:-}"
    [ -n "$v" ] && ENVV+=("$n=$v")
  done
}

# with_timeout <seconds> <cmd...>: replaces the calling (sub)shell with a perl timer that runs
# cmd in its own process group (registered in $RUN/pgids for the script's signal trap and final
# sweep). On expiry, or when the timer gets INT, TERM or HUP (even one that arrives before the
# fork has returned), it kills the whole group (TERM, then KILL after 2 s) and exits 142
# (expiry) or 128+signal. After a normal exit it kills whatever the provider left in its group.
with_timeout() {
  AI_REVIEW_PGIDS="$RUN/pgids" AI_REVIEW_SCRIPT_PID="$$" exec perl -e '
    my $t = shift; my $dir = $ENV{AI_REVIEW_PGIDS}; my $script = $ENV{AI_REVIEW_SCRIPT_PID};
    delete @ENV{qw(AI_REVIEW_PGIDS AI_REVIEW_SCRIPT_PID)};
    my ($pid, $got) = (0, 0);
    my $stop = sub {
      my $code = shift;
      kill "TERM", -$pid, $pid;
      for (1 .. 20) { last unless kill 0, -$pid; select(undef, undef, undef, 0.1); }
      kill "KILL", -$pid, $pid;
      waitpid($pid, 0); unlink "$dir/$pid"; exit $code;
    };
    my %code = (ALRM => 142, INT => 130, TERM => 143, HUP => 129);
    for my $s (keys %code) { $SIG{$s} = sub { if ($pid > 0) { $stop->($code{$s}); } else { $got ||= $code{$s}; } }; }
    $pid = fork; die "fork: $!" unless defined $pid;
    if ($pid == 0) { $SIG{$_} = "DEFAULT" for keys %code; setpgrp(0, 0); exec { $ARGV[0] } @ARGV or exit 127; }
    if (open(my $f, ">", "$dir/$pid")) { close $f; }
    # Watchdog: in a process group of its own, so a SIGKILL to the group of the script (which takes
    # this timer down with it) does not reach it. It ends the provider group when the script is
    # gone, and ends itself when the provider group is gone.
    my $wd = fork;
    if (defined $wd && $wd == 0) {
      setpgrp(0, 0); $SIG{$_} = "IGNORE" for qw(INT TERM HUP); $SIG{ALRM} = "DEFAULT";
      for (1 .. 40) { last if kill 0, -$pid; select(undef, undef, undef, 0.05); }
      while (kill 0, -$pid) {
        if ($script && !kill(0, $script)) {
          kill "TERM", -$pid;
          for (1 .. 20) { last unless kill 0, -$pid; select(undef, undef, undef, 0.1); }
          kill "KILL", -$pid; last;
        }
        select(undef, undef, undef, 0.5);
      }
      exit 0;
    }
    $stop->($got) if $got;
    alarm $t;
    waitpid($pid, 0); my $s = $?;
    alarm 0;
    kill "KILL", -$pid;   # anything the provider left running in its group
    unlink "$dir/$pid";
    exit(($s & 127) ? 128 + ($s & 127) : $s >> 8);
  ' "$@"
}

# Command lines. Flags checked against each CLI's --help on 2026-11-16 (codex-cli 0.167.1,
# GitHub Copilot CLI 1.0.105, Claude Code 2.1.311); codex's --disable names against
# `codex features list`.
invoke_codex() {  # $1 bin, $2 prompt file, $3 answer file. codex writes its final message with -o; stdout is the event log.
  # --ignore-user-config: no $CODEX_HOME/config.toml, so none of its MCP servers or profiles
  # (auth still works). --ignore-rules: no execpolicy rules. project_doc_max_bytes=0: AGENTS.md
  # is not loaded as instructions. --ephemeral: no session files. -s read-only: no writes, no
  # network from shell commands. Reads are not confined to the repository.
  with_timeout "$TIMEOUT" /usr/bin/env -i "${ENVV[@]}" "$1" exec -m "$CODEX_MODEL" -s read-only --ephemeral \
    --ignore-user-config --ignore-rules --skip-git-repo-check -c 'web_search="disabled"' -c project_doc_max_bytes=0 \
    --disable apps --disable hooks --disable plugins --disable memories \
    -o "$3" "$(cat "$2")" < /dev/null > "$RUN/codex.events" 2>> "$RUN/codex.err"
}
invoke_copilot() {
  # --available-tools: the model sees only the read and search tools (no shell, no edits, no
  # web fetch, no MCP tool, user-configured MCP servers included); the deny rules back that up.
  # --no-custom-instructions skips AGENTS.md and friends; --disable-builtin-mcps drops the GitHub
  # MCP servers; --sync-session=off keeps the run out of account history sync;
  # --disallow-temp-dir drops the automatic temp-directory access. The working directory is not
  # trusted (no --trust-folder; copilot_trusts_root refuses a saved trust before the call, and
  # COPILOT_ALLOW_ALL never reaches the CLI), so its skills, hooks and MCP config are not loaded.
  with_timeout "$TIMEOUT" /usr/bin/env -i "${ENVV[@]}" "$1" -p "$(cat "$2")" --model "$COPILOT_MODEL" --mode plan -s \
    --no-ask-user --available-tools view,grep,glob \
    --no-custom-instructions --disable-builtin-mcps --disable-client-telemetry --no-auto-update \
    --sync-session=off --disallow-temp-dir \
    --deny-tool=write --deny-tool=shell --deny-tool=url \
    < /dev/null > "$3" 2>> "$RUN/copilot.err"
}
invoke_claude() {
  # --safe-mode: no CLAUDE.md, skills, plugins, hooks, MCP servers or custom commands.
  # --restricted: no command-running tools or WebFetch, settings files ignored, and the file
  # tools confined to the working directory (the repository root). --setting-sources= loads no
  # settings; --strict-mcp-config with no --mcp-config means no MCP server; --tools limits the
  # model to three read-only tools; dontAsk denies anything else that would prompt.
  # The prompt goes in on stdin, so no variadic flag can swallow it.
  with_timeout "$TIMEOUT" /usr/bin/env -i "${ENVV[@]}" "$1" -p --model "$CLAUDE_MODEL" --safe-mode --restricted \
    --setting-sources= --strict-mcp-config \
    --no-session-persistence --disable-slash-commands --tools Read,Grep,Glob --allowedTools Read,Grep,Glob \
    --disallowedTools 'Read(**/.env),Read(**/.env.*),Read(**/.envrc)' \
    --permission-mode dontAsk --max-budget-usd 5 \
    < "$2" > "$3" 2>> "$RUN/claude.err"
}
copilot_trusts_root() {  # exit 0 when a trustedFolders entry in Copilot's config covers $ROOT
  local home="${COPILOT_HOME:-$HOME/.copilot}" f
  for f in "$home/config.json" "$home/settings.json"; do
    [ -f "$f" ] || continue
    perl -e '
      my ($file, $root) = @ARGV; local $/; open(my $h, "<", $file) or exit 1; my $t = <$h>;
      $t =~ s{^\s*//[^\n]*}{}mg;
      exit 1 unless $t =~ /"(?:trustedFolders|trusted_folders)"\s*:\s*\[(.*?)\]/s;
      for my $e ($1 =~ /"((?:[^"\\]|\\.)*)"/g) {
        $e =~ s{\\(.)}{$1}g; $e =~ s{/+$}{};
        exit 0 if $e eq "" || $root eq $e || index($root, "$e/") == 0;
      }
      exit 1;
    ' "$f" "$ROOT" && return 0
  done
  return 1
}
# call_provider <provider> <prompt file> <answer file>: runs one call from the repository root as
# a background job of the provider's own subshell, so that subshell's signal trap can forward to
# the timer at once; returns the call's exit code.
call_provider() {
  local p="$1" b h rc; b=$(bin_for "$p"); h=$(hook_for "$p")
  provider_env "$p"
  if [ -n "$h" ]; then
    ( cd "$ROOT" && with_timeout "$TIMEOUT" /usr/bin/env -i "${ENVV[@]}" "$b" "$2" < /dev/null > "$3" 2>> "$RUN/$p.err" ) &
  else
    case "$p" in
      codex)   ( cd "$ROOT" && invoke_codex "$b" "$2" "$3" ) & ;;
      copilot) ( cd "$ROOT" && invoke_copilot "$b" "$2" "$3" ) & ;;
      claude)  ( cd "$ROOT" && invoke_claude "$b" "$2" "$3" ) & ;;
    esac
  fi
  wait "$!"; rc=$?
  [ -f "$3" ] || : > "$3"
  return $rc
}
provider_stop() {  # inside a provider subshell: forward the signal to the running call, then leave
  trap '' INT TERM HUP
  local j; j=$(jobs -p 2>/dev/null)
  [ -z "$j" ] || kill -TERM $j 2>/dev/null
  wait 2>/dev/null
  exit "$1"
}

# ---------- answers (untrusted text) ----------
# normalize: a finding header (optionally "- ", "1. ", "#", bold or italic markers around it),
# a VERDICT line whose word is exactly ready, revise or reject (optionally bold), and a
# claim/evidence/fix line are rewritten to the canonical form; severity and verdict lower-cased.
# A quoted line ("> ...") is left as it is: it is never a header or a verdict.
normalize_answer() {  # $1 raw, $2 out
  perl -ne '
    s/\r$//;
    if (/^[ \t#*_-]*(?:\d+[.)][ \t]+)?[*_]*F(\d+)[*_]*[ \t]*\[[ \t]*([A-Za-z]+)[ \t]*\][*_]*[ \t]*(.*?)[\s*_#]*$/) { print "F$1 [" . lc($2) . "] $3\n"; next; }
    if (/^[ \t#*_]*VERDICT[*_]*[ \t]*:[\s*_]*(ready|revise|reject)\b(.*?)[\s*_]*$/) { print "VERDICT: $1$2\n"; next; }
    if (/^[ \t*_-]*(claim|evidence|fix)[*_]*[ \t]*:[\s*_]*(.*?)\s*$/i) { print lc($1) . ": $2\n"; next; }
    print;
  ' "$1" > "$2" 2>/dev/null || : > "$2"
}
# trim: from the first finding or verdict line through the LAST verdict line. A verdict line
# followed by another finding is not the verdict: the whole rest is kept (lost=1) and the
# provider is truncated. Prints "<lost> <dropped>"; dropped=1 when a non-blank line fell outside
# the kept part. The same strict verdict rule decides "has a verdict".
trim_answer() {  # $1 normalized, $2 out
  perl -e '
    my ($in, $out) = @ARGV; open(my $h, "<", $in) or die; my @l = <$h>; close $h;
    my $v = qr/^VERDICT: (?:ready|revise|reject)(?:[^A-Za-z]|$)/;
    my ($first, $lastv) = (-1, -1);
    for my $i (0 .. $#l) {
      $first = $i if $first < 0 && ($l[$i] =~ /^F\d+ \[/ || $l[$i] =~ $v);
      $lastv = $i if $l[$i] =~ $v;
    }
    my ($s, $e, $lost, $dropped) = (0, -1, 0, 0);
    if ($first >= 0) {
      $s = $first; $e = $lastv >= 0 ? $lastv : $#l;
      for my $i ($e + 1 .. $#l) { $lost = 1 if $l[$i] =~ /^F\d+ \[/; }
      $e = $#l if $lost;
    }
    for my $i (0 .. $#l) { next if $i >= $s && $i <= $e; $dropped = 1 if $l[$i] =~ /\S/; }
    open(my $o, ">", $out) or die; print $o @l[$s .. $e] if $e >= $s; close $o;
    print "$lost $dropped\n";
  ' "$1" "$2" 2>/dev/null || { : > "$2"; echo "0 1"; }
}
count_findings() { local n; n=$(grep -cE "$HEADER_RE" "$1" 2>/dev/null) || true; echo "${n:-0}"; }
has_verdict()    { tail -n 1 "$1" 2>/dev/null | grep -qE "$STRICT_VERDICT_RE"; }   # the kept part ends with it
structured()     { grep -qE -e "$HEADER_RE" -e "$STRICT_VERDICT_RE" "$@" 2>/dev/null; }
verdict_of() {  # the last strict verdict line; control bytes stripped, capped at VERDICT_MAX bytes on a UTF-8 boundary
  grep -E "$STRICT_VERDICT_RE" "$1" 2>/dev/null | tail -n 1 | perl -pe '
    s/[\x00-\x08\x0b-\x1f\x7f]//g; chomp;
    if (length($_) > '"$VERDICT_MAX"') { $_ = substr($_, 0, '"$VERDICT_MAX"'); s/[\xc0-\xff][\x80-\xbf]*\z//; $_ .= " [cut]"; }
    $_ .= "\n";' || true
}
verdict_is_ready() { verdict_of "$1" | grep -qE '^VERDICT: ready([^A-Za-z]|$)'; }
last_block_complete() {  # the last finding block (if any) has its claim, evidence and fix lines
  perl -e '
    open(my $h, "<", shift) or exit 1; my @l = <$h>; my $last = -1;
    for my $i (0 .. $#l) { $last = $i if $l[$i] =~ /^F\d+ \[/; }
    exit 0 if $last < 0;
    my %have;
    for my $i ($last + 1 .. $#l) { last if $l[$i] =~ /^F\d+ \[/; $have{$1} = 1 if $l[$i] =~ /^(claim|evidence|fix):/; }
    exit(($have{claim} && $have{evidence} && $have{fix}) ? 0 : 1);' "$1"
}
# merge: the findings of every input in order (the first answer's included, so a merge never has
# fewer findings than the cut-off answer), duplicates (same section and claim, ignoring case and
# punctuation) dropped, renumbered; the verdict is the last input's last verdict line, if any.
merge_answers() {  # $1 out, then the trimmed inputs
  local out="$1"; shift
  perl -e '
    my $v = qr/^VERDICT: (?:ready|revise|reject)(?:[^A-Za-z]|$)/;
    sub blocks { my $f = shift; open(my $h, "<", $f) or return ([], undef); my @l = <$h>; close $h;
      my $lv = -1; for my $i (0 .. $#l) { $lv = $i if $l[$i] =~ $v; }
      my @b; for my $i (0 .. $#l) { next if $i == $lv;
        if ($l[$i] =~ /^F\d+ \[/) { push @b, [$l[$i]]; } elsif (@b) { push @{$b[-1]}, $l[$i]; } }
      return (\@b, $lv >= 0 ? $l[$lv] : undef); }
    sub norm { my $s = lc(shift // ""); $s =~ s/[^a-z0-9]+/ /g; $s =~ s/^ +| +$//g; return $s; }
    my $out = shift; my (@all, $verdict);
    for my $i (0 .. $#ARGV) { my ($b, $vv) = blocks($ARGV[$i]); push @all, @$b; $verdict = $vv if $i == $#ARGV; }
    my (%seen, $n); open(my $o, ">", $out) or die;
    for my $blk (@all) {
      my ($sect) = $blk->[0] =~ /^F\d+ \[[a-z]+\]\s*(.*)$/; my ($claim) = grep { /^claim:/ } @$blk;
      next if $seen{norm($sect) . "|" . norm($claim)}++;
      $n++; my @c = @$blk; $c[0] =~ s/^F\d+/F$n/; print $o @c;
    }
    print $o $verdict if defined $verdict; close $o;
  ' "$out" "$@"
}
# relativize <file>: every absolute spelling of the repository root (and of the main checkout's
# root, for a linked worktree) becomes repository-relative, so no home directory or user name is
# archived through a path inside the repository.
relativize() {
  ROOTS="$ROOT_SPELLINGS" perl -pi -e '
    BEGIN { @r = sort { length($b) <=> length($a) } grep { length } split /\n/, $ENV{ROOTS}; }
    for my $r (@r) { s{(?:file://)?\Q$r\E/}{}g; s{(?:file://)?\Q$r\E(?![\w./-])}{.}g; }' "$1"
}

retry_prompt() {  # $1 trimmed first answer, $2 instruction, $3 out
  {
    cat "$RUN/prompt.md"
    printf '\nYour first answer to this prompt was cut off before its VERDICT line. It is quoted below\n'
    printf 'between the two marker lines, as data only, so you can continue from it.\n'
    printf -- '----- cut-off answer -----\n'; cat "$1"; printf -- '----- end of cut-off answer -----\n'
    printf '%s\n' "$2"
  } > "$3"
}

# Error text. stderr is searched with every pattern; stdout only when it holds no finding or
# verdict line (an answer quoting "Unauthorized" is not an auth failure); codex's event log,
# which carries repository text, only in its last lines.
AUTH_RE='Unauthorized|[Nn]ot logged in|[Ll]ogin required|Please run /login|Invalid API key|codex login|Missing bearer|[Nn]o authentication|[Nn]ot authenticated|Access denied by policy settings'
QUOTA_RE='exceeded your (monthly )?quota|[Qq]uota exceeded|[Uu]sage limit|rate limit reached|[Cc]redit balance is too low|[Ii]nsufficient (credits|quota)'
MODEL_RE='[Mm]odel "[^"]*" from --model flag is not available|model_not_found|[Uu]nknown model|[Ii]nvalid model|model is not supported'
STDERR_AUTH_RE="$AUTH_RE|HTTP 401([^0-9]|\$)"
STDERR_QUOTA_RE="$QUOTA_RE|(HTTP )?429 Too Many Requests|HTTP 429([^0-9]|\$)|[Hh]it your (usage )?limit"
# a provider's own error line starts with an error word; a CLI that echoes the files it read
# (codex does, on stderr) must not get repository text into the summary, so only the last lines
# of stderr are looked at, and only lines that start that way
ERROR_LINE_RE='^[[:space:]]*(ERROR|Error|error|FATAL|Fatal|fatal|PANIC|Panic|panic)([[:space:]]*[:!]|[[:space:]])'
error_status() {  # $1 provider, $2 1 when the answers hold findings -> skipped:auth|skipped:quota|failed:model|""
  local p="$1" rest="$RUN/$1.errsrc"
  : > "$rest"
  [ "$2" = 1 ] || cat "$RUN/$p.out" "$RUN/$p.out-a" "$RUN/$p.out-b" >> "$rest" 2>/dev/null
  [ "$p" = codex ] && tail -n 20 "$RUN/codex.events" >> "$rest" 2>/dev/null
  if grep -qsE "$STDERR_AUTH_RE" "$RUN/$p.err" || grep -qsE "$AUTH_RE" "$rest"; then echo "skipped:auth"; return; fi
  if grep -qsE "$STDERR_QUOTA_RE" "$RUN/$p.err" || grep -qsE "$QUOTA_RE" "$rest"; then echo "skipped:quota"; return; fi
  if grep -qsE "$MODEL_RE" "$RUN/$p.err" || grep -qsE "$MODEL_RE" "$rest"; then echo "failed:model"; return; fi
}
failure_status() {  # $1 provider, $2 rc (non-zero) -> status
  local s
  if [ "$2" -eq 142 ]; then echo "timeout"; return; fi
  if structured "$RUN/$1.norm" "$RUN/$1.norm-a" "$RUN/$1.norm-b"; then s=$(error_status "$1" 1); else s=$(error_status "$1" 0); fi
  echo "${s:-failed:provider}"
}
# masked_error_lines <provider>: up to three of the last 20 stderr lines that start as errors, with paths,
# request ids and token-shaped strings masked and control bytes stripped. Nothing else of a
# provider's stderr ever leaves the run directory.
masked_error_lines() {
  tail -n 20 "$RUN/$1.err" 2>/dev/null | grep -E "$ERROR_LINE_RE" | awk '!seen[$0]++' | head -n 3 | perl -pe '
    s/[\x00-\x08\x0b-\x1f\x7f]//g;
    s{(?:~|/(?:Users|home|private|var|tmp|opt|Volumes|root|etc|Library))/\S*}{<path>}g;
    s{(?i:request[ _-]?id)\s*[:=]?\s*[\w:.\-]+}{request-id <masked>}g;
    s{\b(?:sk|pk|rk)-[A-Za-z0-9_\-]{6,}}{<token>}g;
    s{\b(?:ghp|gho|ghs|ghu|ghr|github_pat)_[A-Za-z0-9_]{6,}}{<token>}g;
    s{\b(?:eyJ)[A-Za-z0-9_\-]{10,}(?:\.[A-Za-z0-9_\-]+)*}{<token>}g;
    s{[A-Za-z0-9+/_\-]{24,}={0,2}}{<token>}g;
    s{\b[0-9a-fA-F]{16,}\b}{<hex>}g;
    $_ = substr($_, 0, 200) . "\n" if length($_) > 201;' || true
}

run_provider() {  # $1 provider; runs as a background job; leaves $RUN/<p>.{status,count,verdict} and $OUT/findings-<p>.md
  local p="$1" rc rca rcb st="" stats lost dropped retried=0
  trap 'provider_stop 143' TERM
  trap 'provider_stop 130' INT
  trap 'provider_stop 129' HUP
  : > "$RUN/$p.err"; echo 0 > "$RUN/$p.count"; : > "$RUN/$p.verdict"; : > "$RUN/$p.trim"
  if ! installed "$p"; then echo "skipped:not-installed" > "$RUN/$p.status"; return; fi
  if [ "$ENV_COUNT" -gt 0 ] && [ "$ALLOW_UNCONFINED" = 0 ] && unconfined "$p"; then
    echo "skipped:unconfined" > "$RUN/$p.status"; return
  fi
  if [ "$p" = copilot ] && [ -z "$(hook_for copilot)" ] && copilot_trusts_root; then
    echo "failed:provider" > "$RUN/$p.status"; : > "$RUN/copilot.trusted"; return
  fi
  call_provider "$p" "$RUN/prompt.md" "$RUN/$p.out"; rc=$?
  normalize_answer "$RUN/$p.out" "$RUN/$p.norm"
  stats=$(trim_answer "$RUN/$p.norm" "$RUN/$p.trim"); lost="${stats% *}"; dropped="${stats#* }"
  if [ "$rc" -ne 0 ]; then
    st=$(failure_status "$p" "$rc")
  elif ! structured "$RUN/$p.norm"; then
    st=$(error_status "$p" 0)          # e.g. "Not logged in" printed with exit 0
  fi
  if [ -z "$st" ] && [ "$lost" = 0 ] && ! has_verdict "$RUN/$p.trim"; then
    # Truncated: ask again in two halves (each carrying the cut-off answer); both must succeed.
    # The cut-off answer's findings stay in the result whatever the halves do.
    retried=1
    cp "$RUN/$p.trim" "$RUN/$p.trim-first"
    retry_prompt "$RUN/$p.trim" "Output only your first six findings." "$RUN/$p.prompt-a"
    retry_prompt "$RUN/$p.trim" "Output only your remaining findings and the VERDICT line." "$RUN/$p.prompt-b"
    call_provider "$p" "$RUN/$p.prompt-a" "$RUN/$p.out-a"; rca=$?
    call_provider "$p" "$RUN/$p.prompt-b" "$RUN/$p.out-b"; rcb=$?
    normalize_answer "$RUN/$p.out-a" "$RUN/$p.norm-a"; normalize_answer "$RUN/$p.out-b" "$RUN/$p.norm-b"
    if [ "$rca" -ne 0 ]; then st=$(failure_status "$p" "$rca")
    elif [ "$rcb" -ne 0 ]; then st=$(failure_status "$p" "$rcb")
    else
      trim_answer "$RUN/$p.norm-a" "$RUN/$p.trim-a" > /dev/null
      trim_answer "$RUN/$p.norm-b" "$RUN/$p.trim-b" > /dev/null
      merge_answers "$RUN/$p.trim" "$RUN/$p.trim-first" "$RUN/$p.trim-a" "$RUN/$p.trim-b"
    fi
  fi
  if [ -z "$st" ]; then
    if [ "$lost" = 1 ]; then st="truncated"
    elif has_verdict "$RUN/$p.trim"; then
      # never ok with no findings and a verdict other than ready
      # and never ok while the last finding lacks its claim, evidence or fix line
      if [ "$(count_findings "$RUN/$p.trim")" -eq 0 ] && ! verdict_is_ready "$RUN/$p.trim"; then st="truncated"
      elif ! last_block_complete "$RUN/$p.trim"; then st="truncated"
      else st="ok"; fi
    else st="truncated"
    fi
  fi
  echo "$st" > "$RUN/$p.status"
  # Every status reached after a call (ok, truncated, timeout, failed:*, skipped:auth,
  # skipped:quota) keeps whatever findings the answer holds; only the skips decided before any
  # call (not-installed, unconfined, trusted folder) have none.
  if [ -s "$RUN/$p.trim" ]; then
    relativize "$RUN/$p.trim"
    cp "$RUN/$p.trim" "$OUT/findings-$p.md"
    if [ "$dropped" = 1 ] || [ "$retried" = 1 ]; then
      cp "$RUN/$p.out" "$OUT/findings-$p.raw.md"; relativize "$OUT/findings-$p.raw.md"
    fi
    count_findings "$RUN/$p.trim" > "$RUN/$p.count"; verdict_of "$RUN/$p.trim" > "$RUN/$p.verdict"
  fi
}

for p in $PROVIDERS; do run_provider "$p" & done
wait
# a provider whose timer was SIGKILLed keeps running with a stale pgid file: sweep it
kill_groups KILL
rm -f "$RUN"/pgids/* 2>/dev/null

# ---------- what changed outside the answers ----------
AFTER=$(snapshot)
DIFF=""
[ "$BEFORE" = "$AFTER" ] || DIFF=$(diff <(printf '%s\n' "$BEFORE") <(printf '%s\n' "$AFTER") | grep '^[<>]' | cut -c3- || true)
ENTRIES=$(printf '%s\n' "$DIFF" | awk 'NF {
    if ($1 == "P" && $2 == "F") { $1 = $2 = $3 = $4 = $5 = $6 = ""; sub(/^ +/, ""); print "path " $0 }
    else if ($1 == "P" && ($2 == "D" || $2 == "L")) { $1 = $2 = $3 = ""; sub(/^ +/, ""); sub(/ -> .*/, ""); print "path " $0 }
    else if ($1 == "P" && $2 == "N") { $1 = $2 = ""; sub(/^ +/, ""); print "path " $0 " (nested repository)" }
    else if ($1 == "G") { print "git " $2 " " $3 }
    else if ($1 == "S") { $1 = ""; sub(/^ +/, ""); print "git status " $0 }
  }' | sort -u)
# Ignored or not is decided by git with NUL-separated, unquoted paths (core.quotePath=false), and
# fails closed: a path with a control character, a quote or a backslash, or one git does not
# answer for cleanly, counts as ignored and is never named in summary.txt.
TRACKED_CHANGES=""; IGNORED_CHANGES=""
if [ -n "$ENTRIES" ]; then
  printf '%s\n' "$ENTRIES" | sed -n 's/^path //p' | sed 's/ (nested repository)$//' | grep -v '^<' | grep -v '^\.git/' \
    | tr '\n' '\000' > "$RUN/paths0" || true
  git -C "$ROOT" -c core.quotePath=false check-ignore --stdin -z < "$RUN/paths0" > "$RUN/ignored0" 2>/dev/null
  ign_rc=$?   # 0: some ignored, 1: none; anything else is a failure and fails closed
  case "$ign_rc" in 0|1) ALL_IGNORED=0 ;; *) ALL_IGNORED=1 ;; esac
  CLASSIFIED=$(printf '%s\n' "$ENTRIES" | ALL_IGNORED="$ALL_IGNORED" perl -e '
    my %ign; if (open(my $h, "<", shift)) { local $/ = "\0"; while (my $x = <$h>) { chomp $x; $ign{$x} = 1; } }
    my $all = $ENV{ALL_IGNORED};
    while (my $e = <STDIN>) { chomp $e; next unless length $e;
      if ($e =~ /^path (.*?)(?: \(nested repository\))?$/) {
        my $p = $1;
        if ($p =~ /^</ || $p =~ m{^\.git/}) { print "T\t$e\n"; next; }
        if ($all || $p =~ /[\x00-\x1f\x7f"\\]/ || $ign{$p}) { $p =~ s/[\x00-\x1f\x7f]/?/g; print "I\t$p\n"; next; }
      }
      $e =~ s/[\x00-\x1f\x7f]/?/g; print "T\t$e\n";
    }' "$RUN/ignored0")
  TRACKED_CHANGES=$(printf '%s\n' "$CLASSIFIED" | sed -n 's/^T	//p')
  IGNORED_CHANGES=$(printf '%s\n' "$CLASSIFIED" | sed -n 's/^I	//p')
  [ -z "$TRACKED_CHANGES" ] || TRACKED_CHANGES="$TRACKED_CHANGES"$'\n'
  [ -z "$IGNORED_CHANGES" ] || IGNORED_CHANGES="$IGNORED_CHANGES"$'\n'
fi
expected_in_archive() {
  local name="$1" p
  [ "$name" = prompt.md ] && return 0
  for p in $PROVIDERS; do
    [ "$name" = "findings-$p.md" ] || [ "$name" = "findings-$p.raw.md" ] && return 0
  done
  return 1
}
ARCHIVE_EXTRA=""
while IFS= read -r name; do
  [ -n "$name" ] || continue
  if [ -d "$OUT/$name" ] || ! expected_in_archive "$name"; then ARCHIVE_EXTRA="$ARCHIVE_EXTRA $name"; fi
done <<< "$(ls -A "$OUT")"
cmp -s "$RUN/prompt.md" "$OUT/prompt.md" || ARCHIVE_EXTRA="$ARCHIVE_EXTRA prompt.md(modified)"
ARCHIVE_EXTRA=$(printf '%s' "$ARCHIVE_EXTRA" | tr -d '\000-\037\177' | cut -c1-300)
OUTSIDE=""
for f in "$OUT"/findings-*.md; do
  [ -f "$f" ] || continue
  # after relativize, any absolute path left (also after file://, also a Windows drive path) is
  # outside the repository
  if perl -ne '
       $hit = 1 if m{(?:^|[\s"\x27(\[<:=,`])(?:file://)?(?:~/|/[A-Za-z0-9._@+-]+/)};
       $hit = 1 if m{(?:^|[^A-Za-z0-9])[A-Za-z]:\\[A-Za-z0-9._ -]};
       END { exit($hit ? 0 : 1) }' "$f"; then
    OUTSIDE="$OUTSIDE ${f##*/}"
  fi
done

# ---------- summary and exit code ----------
total=0; any_ok=1; all_ok=1; models=""
for p in $PROVIDERS; do
  total=$((total + $(cat "$RUN/$p.count")))
  if [ "$(cat "$RUN/$p.status")" = "ok" ]; then any_ok=0; else all_ok=0; fi
  case "$p" in
    codex)   models="$models codex=$CODEX_MODEL" ;;
    copilot) models="$models copilot=$COPILOT_MODEL" ;;
    claude)  models="$models claude=$CLAUDE_MODEL" ;;
  esac
done
n_tracked=$(printf '%s' "$TRACKED_CHANGES" | grep -c . || true)
n_ignored=$(printf '%s' "$IGNORED_CHANGES" | grep -c . || true)
{
  echo "document: $REL"
  echo "document-blob: $DOC_BLOB"
  echo "commit: $HEAD_COMMIT"
  echo "date: $TODAY"
  if [ -n "$OUT_REL" ]; then echo "archive: $OUT_REL"; else echo "archive: $OUT (outside the repository)"; fi
  echo "models:$models"
  echo "timeout-per-call: ${TIMEOUT}s"
  for p in $PROVIDERS; do
    v=$(cat "$RUN/$p.verdict"); [ -n "$v" ] || v="-"
    printf '%-8s %-22s %s findings  %s\n' "$p" "$(cat "$RUN/$p.status")" "$(cat "$RUN/$p.count")" "$v"
  done
  echo "findings: $total total"
  for p in $PROVIDERS; do
    st=$(cat "$RUN/$p.status")
    case "$st" in
      skipped:auth)
        case "$p" in
          codex)   echo "hint: codex: not signed in; run 'codex login', then rerun with --only codex" ;;
          copilot) echo "hint: copilot: not signed in, or Copilot CLI access is off for the account; run 'copilot' and use /login, or check the policies at https://github.com/settings/copilot, then rerun with --only copilot" ;;
          claude)  echo "hint: claude: not signed in; run 'claude' and use /login, then rerun with --only claude" ;;
        esac ;;
      skipped:quota) echo "hint: $p: the provider's usage quota is exhausted; rerun with --only $p once it resets" ;;
      skipped:unconfined) echo "hint: $p: not called: $ENV_COUNT env file(s) present (names on the terminal) and $p's file reads are not confined to the repository; remove them, or rerun with --allow-unconfined to accept the risk" ;;
      failed:model)
        case "$p" in
          copilot) echo "hint: copilot: model $COPILOT_MODEL is not available; set AI_REVIEW_COPILOT_MODEL to one the account offers" ;;
          codex)   echo "hint: codex: model $CODEX_MODEL is not available; set AI_REVIEW_CODEX_MODEL" ;;
          claude)  echo "hint: claude: model $CLAUDE_MODEL is not available; set AI_REVIEW_CLAUDE_MODEL" ;;
        esac ;;
      timeout)   echo "hint: $p: no answer within ${TIMEOUT}s per call; rerun with --only $p --timeout $((TIMEOUT * 2))" ;;
      truncated) echo "hint: $p: no usable VERDICT line (missing even after the two-half retry, followed by another finding, or revise/reject with no finding); its answer is archived" ;;
      failed:provider)
        if [ "$p" = copilot ] && [ -e "$RUN/copilot.trusted" ]; then
          echo "hint: copilot: not called: a trustedFolders entry in Copilot's config covers this repository, which would load its skills, hooks and MCP config; remove the entry or rerun without copilot"
        else
          echo "hint: $p: the CLI exited with an error; its stderr is not archived (its last error lines are on the terminal)"
        fi ;;
    esac
    # nothing of a provider's stderr text is archived: only the error class and an HTTP-style code
    case "$st" in
      skipped:auth) cls=auth ;; skipped:quota) cls=quota ;; failed:model) cls=model ;;
      timeout) cls=timeout ;; failed:provider) cls=provider ;; *) cls="" ;;
    esac
    if [ -n "$cls" ] && ! { [ "$p" = copilot ] && [ -e "$RUN/copilot.trusted" ]; }; then
      code=$(tail -n 20 "$RUN/$p.err" 2>/dev/null | grep -oE '(^|[^0-9])[45][0-9][0-9]([^0-9]|$)' | grep -oE '[45][0-9][0-9]' | head -n 1)
      echo "error: $p: class=$cls code=${code:--}"
    fi
  done
  for p in $PROVIDERS; do
    [ -z "$(hook_for "$p")" ] || echo "warning: test hook AI_REVIEW_BIN_$(printf '%s' "$p" | tr '[:lower:]' '[:upper:]') is set; this run used a fake $p, not the real CLI"
  done
  [ "$ENV_COUNT" -eq 0 ] || echo "warning: env files: $ENV_COUNT, names on the terminal (never opened)"
  if [ "$n_tracked" -gt 0 ]; then
    echo "warning: worktree changed during the run (by a reviewer or anything else), outside the reviews directories:"
    printf '%s' "$TRACKED_CHANGES" | head -n "$CHANGES_MAX" | tr -d '\000-\010\013-\037\177' | sed 's/^/  /'
    [ "$n_tracked" -le "$CHANGES_MAX" ] || echo "  ... and $((n_tracked - CHANGES_MAX)) more"
  fi
  [ "$n_ignored" -eq 0 ] || echo "warning: $n_ignored git-ignored path(s) changed during the run (by a reviewer or anything else); listed on the terminal only"
  [ -z "$ARCHIVE_EXTRA" ] || echo "warning: unexpected files in the archive (written by a reviewer?):$ARCHIVE_EXTRA"
  for f in $OUTSIDE; do echo "warning: $f names paths outside the repository; check it before committing the archive"; done
} > "$OUT/summary.txt" && DONE=1   # from here on a signal keeps the archive
cat "$OUT/summary.txt"
for p in $PROVIDERS; do
  case "$(cat "$RUN/$p.status")" in ok|skipped:not-installed|skipped:unconfined) continue ;; esac
  lines=$(masked_error_lines "$p")
  [ -z "$lines" ] || printf '%s\n' "$lines" | sed "s/^/$p stderr (terminal only, masked): /"
done
if [ "$ENV_COUNT" -gt 0 ]; then
  echo "env files (names only, never opened, not archived):"
  printf '%s\n' "$ENV_LIST" | sed 's/^/  /'
fi
if [ "$n_ignored" -gt 0 ]; then
  echo "git-ignored paths changed during the run (not archived):"
  printf '%s' "$IGNORED_CHANGES" | head -n 200 | sed 's/^/  /'
fi
if [ "$all_ok" = 1 ]; then
  rm -rf "$RUN"
else
  echo "run directory (stderr, raw answers; not archived): $RUN"
fi
exit $any_ok
