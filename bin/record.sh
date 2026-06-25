#!/usr/bin/env bash
#
# record.sh — record an AI agent building a Promise program (one zoo run).
#
# Usage:   bin/record.sh [--rerecord] <claude|gemini> <task-dir>
#
# With --rerecord, replace an existing COMMITTED run in place against a newer
# toolchain. The old run is preserved via git history — linked from a growing
# "Prior runs" table (+ a one-line progress aggregate) in the task README and a
# "Previous runs" section in the run's context.md — then the dir is wiped, the agent
# re-runs fresh, and THIS agent's cast/watch in the README are reset to a "pending"
# state that bin/upload.sh stamps with the new recording URL. Only the current run's
# source + summary stay in-tree; old source/summary/cast live in git history.
# (Re-record refuses unless the existing run is committed and clean.)
#
# <task-dir> must contain prompt.md (the task's specific ask). The prompt actually
# sent to the agent is PROMPT_PREFIX.md + that prompt.md + PROMPT_SUFFIX.md — a
# shared preamble/postamble at the repo root that wrap every task (both optional).
# The agent runs in a per-agent subdir named <task>-<agent> (e.g.
# hello-world/hello-world-claude/) so several agents can do the same task side by
# side, none can clobber the task README, and Promise's folder-derived binary name
# is descriptive. Outputs go into that subdir:
#   SUMMARY.md   the agent's own TL;DR of the run (requested by PROMPT_SUFFIX.md)
#   context.md   provenance (date, OS, promise + agent versions, duration)
#   demo.cast    asciinema recording — view with the asciinema PLAYER, which
#                renders Claude's TUI faithfully. We do NOT render a GIF: agg's
#                emulator garbles Claude's live redraws (overlapping text). Use
#                `asciinema play demo.cast` (local) or upload/embed the player.
#   (plus the generated .pr; the compiled binary is removed)
#
# The agent runs INTERACTIVELY (its TUI renders — headless `-p` is blank) in
# auto-accept-edits mode with all Bash pre-granted via --allowedTools, so there is
# NO startup warning and NO mid-run permission dialog (a dialog overlaps the spinner
# and garbles the recording). No settings file needed. Watch it, then /exit to stop.
# (Bypass mode isn't used: its warning shows every run and can't be suppressed.)
#
# RECORDING SIZE: set your terminal width yourself BEFORE recording. Don't go too
# narrow — Claude's header (the account/org line) wraps if it doesn't fit, which
# pushes the whole layout and corrupts the GIF. ~110-120 cols is safe. (record.sh
# deliberately does NOT force a resize; doing so was wrapping the header.)
#
# Privacy: any @gmail.com address is masked in the recording before you play /
# upload / embed it — the local part becomes same-length 'x's, keeping @gmail.com
# (same length + escape-preserving so the cast's cursor positions stay valid).
# Add more via REDACT.
#   REDACT='you@work.com|secret' bin/record.sh claude <task-dir>
#
# The `promise` toolchain is required; ~/.promise/bin is put on PATH for this run.

set -uo pipefail

CLAUDE_FLAGS="--allowedTools Bash --permission-mode acceptEdits"   # grant all Bash via the CLI (no settings file, survives rm -rf); acceptEdits = no startup warning. Keep --allowedTools before another flag so its variadic list doesn't swallow the prompt arg.
AGY_FLAGS="--dangerously-skip-permissions"          # antigravity (agy) — auto-approve all tool requests (Google's Gemini-powered CLI; the old standalone gemini CLI is deprecated)
PROMISE_BIN="$HOME/.promise/bin"

# --- internal entrypoint: the actual agent run (also invoked inside asciinema) ---
# Interactive (no -p) and unpiped (no `| tee`) — both would stop the TUI rendering.
# The prompt was pre-assembled (PREFIX + task prompt.md + SUFFIX) into $prompt_file
# by the main flow; $run_dir is the absolute per-agent subdir.
if [[ "${1:-}" == "__run" ]]; then
  agent="$2"; prompt_file="$3"; run_dir="$4"
  export PATH="$PROMISE_BIN:$PATH"
  prompt="$(cat "$prompt_file")"
  mkdir -p "$run_dir"
  cd "$run_dir" || exit 1
  case "$agent" in
    claude) claude $CLAUDE_FLAGS "$prompt" ;;
    gemini) agy $AGY_FLAGS -i "$prompt" ;;   # the "gemini" agent runs via Antigravity's agy CLI; -i = seed prompt + stay interactive
  esac
  rc=$?
  # Tidy SUMMARY.md BEFORE the end-card displays it, so the RECORDING captures the
  # clean version (and so does the committed file): rewrite the agent's absolute
  # file:// links to the run dir as repo-relative (also makes them work on GitHub)
  # and abbreviate any home path to ~.
  if [[ -f SUMMARY.md ]]; then
    HOME_DIR="$HOME" RD="$run_dir" perl -i -pe 's|file://\Q$ENV{RD}\E/||g; s|\Q$ENV{HOME_DIR}\E|~|g' SUMMARY.md
  fi
  # Show SUMMARY.md in glow's pager (captured IN the recording): it renders from the
  # top, full color, -w 0 = no premature wrap, as much as fits the screen. Quit it with
  # `q` once you've held it long enough (~6s) — that's what ends the recording. The
  # pager decides how much fits, so there's no cutoff to tune.
  if [[ -f SUMMARY.md ]] && command -v glow >/dev/null 2>&1; then
    glow -p -w 0 SUMMARY.md
  fi
  # --- final end-card: a deliberate last frame -----------------------------
  # glow's pager (above) restores the screen to claude's "Resume this session…"
  # message when you quit it — a confusing frame to freeze on. Clear it and print
  # a definitive "END OF CAST" card so a viewer (and asciinema's poster) lands on
  # something meaningful. context.md exists here (the main flow wrote it before
  # recording); SUMMARY.md + any BUG-/FEATURE- files were just written by the run.
  task_name="$(basename "$run_dir")"; task_name="${task_name%-"$agent"}"
  case "$agent" in claude) lbl="Claude Code" ;; gemini) lbl="Gemini" ;; *) lbl="$agent" ;; esac
  pver="$(perl -ne 'if (/^\| Promise version \| (.+?) \|/){my $v=$1; my ($s)=$v=~/version\s+(\S+)/; my ($c)=$v=~/commit\s+([0-9a-f]{7})/; print $c ? "$s ($c)" : ($s//$v); last}' context.md 2>/dev/null)"
  nbug="$(find . -maxdepth 1 -name 'BUG-*.md' 2>/dev/null | wc -l | tr -d ' ')"
  nfeat="$(find . -maxdepth 1 -name 'FEATURE-*.md' 2>/dev/null | wc -l | tr -d ' ')"
  B=$'\033[1m'; G=$'\033[32m'; D=$'\033[2m'; Z=$'\033[0m'
  rule="  ────────────────────────────────────────────────────────────"
  clear 2>/dev/null || printf '\033[H\033[2J'
  printf '\n%s\n' "$rule"
  printf '   %s✓  END OF CAST%s\n' "$G$B" "$Z"
  printf '%s\n' "$rule"
  printf '   %s built “%s” in Promise %s\n' "$lbl" "$task_name" "${pver:-?}"
  printf '   %s%s compiler bug(s) · %s missing-feature note(s) filed%s\n' "$D" "$nbug" "$nfeat" "$Z"
  [[ -f SUMMARY.md ]] && printf '   full write-up → %sSUMMARY.md%s   ·   provenance → %scontext.md%s\n' "$B" "$Z" "$B" "$Z"
  printf '   %sPromise Zoo · github.com/promise-language/zoo%s\n' "$D" "$Z"
  printf '%s\n\n' "$rule"
  sleep 1.5   # give the end-card real duration so playback/poster lands on it
  exit $rc
fi

# --- re-record helpers (only used with --rerecord) ---------------------------
# A re-record replaces a committed run in place: it relies on git history to keep the
# old source/summary/cast, so it refuses to run on an untracked or dirty run.
# rr_preflight_and_capture stashes facts about the run being replaced (RR_* globals),
# then deletes the dir so the agent runs fresh. rr_finalize (after the run) writes the
# "Previous runs" lineage into context.md and grows the "Prior runs" table + progress
# aggregate in the task README, then resets this agent's cast/watch to a "pending
# upload" state that bin/upload.sh later stamps with the new recording URL.
rr_preflight_and_capture() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "error: --rerecord needs a git repo" >&2; exit 2; }
  git ls-files --error-unmatch "$out_dir/context.md" >/dev/null 2>&1 \
    || { echo "error: no committed run at $out_dir to re-record (expected a tracked context.md)." >&2; exit 2; }
  [[ -z "$(git status --porcelain -- "$out_dir")" ]] \
    || { echo "error: $out_dir has uncommitted changes — commit or stash them first." >&2
         echo "       (re-record deletes the dir and relies on git history to preserve the old run.)" >&2; exit 2; }

  local ctx="$out_dir/context.md" remote
  RR_RELPATH="$(git -C "$out_dir" rev-parse --show-prefix)"; RR_RELPATH="${RR_RELPATH%/}"   # repo-relative, symlink-safe
  RR_OLD_SHA="$(git log -1 --format=%H -- "$out_dir")"
  remote="$(git remote get-url origin 2>/dev/null)"; remote="${remote%.git}"; remote="${remote/git@github.com:/https://github.com/}"
  RR_OLD_BROWSE="$remote/tree/$RR_OLD_SHA/$RR_RELPATH"
  RR_OLD_BLOB="$remote/blob/$RR_OLD_SHA/$RR_RELPATH"

  RR_OLD_DATE="$(perl -ne 'if (/^\| Date \| (\S+)/){print $1; last}' "$ctx")"
  RR_OLD_VER_FULL="$(perl -ne 'if (/^\| Promise version \| (.+?) \|/){print $1; last}' "$ctx")"
  RR_OLD_VER="$(printf '%s' "$RR_OLD_VER_FULL" | perl -ne 'if (/version\s+(\S+)/ || /\b(20\d\d\.\S+)/){print $1; last}')"
  RR_OLD_PLAY="$(perl -ne 'if (m{(https://asciinema\.org/a/[A-Za-z0-9]+)}){print $1; last}' "$ctx")"
  RR_OLD_BUGS="$(git ls-tree -r --name-only "$RR_OLD_SHA" -- "$out_dir" 2>/dev/null | grep -Ec '/BUG-[^/]*\.md$' || true)"
  # prior "Previous runs" rows already in the old context.md, to carry forward
  RR_CARRIED_CTX="$(perl -0777 -ne 'if (/\n## Previous runs\b(.*)$/s){my $b=$1; while ($b =~ /^(\|(?!\s*Date\b)(?!\s*:?-).*\|)\s*$/mg){print "$1\n"}}' "$ctx")"

  echo "re-record: replacing committed run at $out_dir"
  echo "  was: ${RR_OLD_DATE:-?} · Promise ${RR_OLD_VER:-?} · ${RR_OLD_BUGS} BUG file(s) · pinned @ ${RR_OLD_SHA:0:9}"
  rm -rf "$out_dir"
}

rr_finalize() {
  local ctx="$out_dir/context.md" readme="$task_dir/README.md" cur_ver cur_bugs play
  cur_ver="$(printf '%s' "$promise_ver" | perl -ne 'if (/version\s+(\S+)/ || /\b(20\d\d\.\S+)/){print $1; last}')"
  cur_bugs="$(find "$out_dir" -maxdepth 1 -name 'BUG-*.md' 2>/dev/null | wc -l | tr -d ' ')"

  # 1) context.md — append/grow the "## Previous runs" lineage (links pinned to old SHA)
  play=""; [[ -n "$RR_OLD_PLAY" ]] && play="[▶ play]($RR_OLD_PLAY) · "
  {
    echo
    echo "## Previous runs"
    echo
    echo "Re-recorded against an updated Promise toolchain. Prior runs' source & summary"
    echo "are not kept in-tree — reach them at the pinned commit."
    echo
    echo "| Date | Promise version | Links |"
    echo "|---|---|---|"
    echo "| $RR_OLD_DATE | $RR_OLD_VER_FULL | ${play}[SUMMARY]($RR_OLD_BLOB/SUMMARY.md) · [demo.cast]($RR_OLD_BLOB/demo.cast) · [browse]($RR_OLD_BROWSE) |"
    [[ -n "$RR_CARRIED_CTX" ]] && printf '%s\n' "$RR_CARRIED_CTX"
  } >> "$ctx"

  # 2) README — reset this agent's cast→pending + watch→PENDING, then add/grow the
  #    "## Prior runs" table (newest-first) + one-line aggregate. The perl self-extracts
  #    any existing Prior-runs rows from the README and recomputes the aggregate.
  [[ -f "$readme" ]] || { echo "note: no $readme — skipped Prior runs table"; return; }
  AGENT="$agent" AGENT_LABEL="$agent_label" TASK="$task" TASKDIR="$task_dir" \
  OLD_DATE="$RR_OLD_DATE" OLD_VER="$RR_OLD_VER" OLD_BUGS="$RR_OLD_BUGS" \
  OLD_PLAY="$RR_OLD_PLAY" OLD_BROWSE="$RR_OLD_BROWSE" \
  CUR_VER="$cur_ver" CUR_BUGS="$cur_bugs" \
  perl -0777 -i -pe '
    my $A=$ENV{AGENT}; my $TASK=$ENV{TASK}; my $TD=$ENV{TASKDIR};
    # cast marker -> pending note (style-aware: multi-line block vs inline table cell)
    s{(<!-- cast:\Q$A\E\b[^>]*-->)(.*?)(<!-- /cast:\Q$A\E -->)}{
      my ($o,$inner,$c)=($1,$2,$3);
      my $note="_▶ recording pending — run `bin/upload.sh $A $TD` to embed it_";
      ($inner =~ /\n/) ? "$o\n$note\n$c" : "$o$note$c";
    }se;
    # this agent results-row watch link -> PENDING (row links to TASK-AGENT/)
    s{^(\|.*\]\(\Q$TASK\E-\Q$A\E/\).*)$}{ my $r=$1; $r =~ s/(\[▶ watch\]\()[^)]*\)/${1}PENDING)/; $r }mge;
    # add/grow "## Prior runs": superseded run as newest row + recomputed aggregate
    my $L=$ENV{AGENT_LABEL};
    my $play=($ENV{OLD_PLAY} ne "") ? "[▶ play]($ENV{OLD_PLAY}) · " : "";
    my $newrow="| $L | $ENV{OLD_DATE} | $ENV{OLD_VER} | $ENV{OLD_BUGS} | ${play}[browse]($ENV{OLD_BROWSE}) |";
    my @rows;
    if (s/\n(## Prior runs\b.*?)(?=\n## Caveats)//s) {
      my $blk=$1;
      while ($blk =~ /^(\|(?!\s*Agent\b)(?!\s*:?-).*\|)\s*$/mg) { push @rows,$1; }
    }
    unshift @rows,$newrow;
    my @tl=reverse @rows;
    my @bugseq=map { (split /\s*\|\s*/,$_)[4] } @tl; push @bugseq,$ENV{CUR_BUGS};
    my $voldest=(split /\s*\|\s*/,$tl[0])[3];
    my $N=scalar(@rows)+1;
    my $agg="> **$N runs** · Promise $voldest→$ENV{CUR_VER} · compiler bugs hit ".join("→",@bugseq);
    my $hdr="| Agent | Date | Promise | Bugs | Links |\n|---|---|---|---|---|";
    my $block="\n## Prior runs\n\n$agg\n\n$hdr\n".join("\n",@rows)."\n";
    s/(?=\n## Caveats)/$block/ or $_ .= $block;
  ' "$readme"
  echo "updated $readme — Prior runs table + progress aggregate; $agent cast/watch reset to pending"
}

# --- args (optional --rerecord / -r before the positional args) ---
rerecord=0; pos=()
for a in "$@"; do
  case "$a" in
    --rerecord|-r) rerecord=1 ;;
    *) pos+=("$a") ;;
  esac
done
set -- "${pos[@]:-}"
agent="${1:-}"; task_dir="${2:-}"
[[ -n "$agent" && -n "$task_dir" ]] || { echo "usage: $0 [--rerecord] <claude|gemini> <task-dir>" >&2; exit 2; }
[[ "$agent" == "claude" || "$agent" == "gemini" ]] || { echo "error: agent must be 'claude' or 'gemini' (got '$agent')" >&2; exit 2; }
case "$agent" in claude) agent_label="Claude Code" ;; gemini) agent_label="Gemini" ;; esac
task_dir="${task_dir%/}"
task="$(basename "$task_dir")"
[[ -d "$task_dir" ]] || { echo "error: task dir '$task_dir' not found" >&2; exit 2; }
[[ -f "$task_dir/prompt.md" ]] || { echo "error: $task_dir/prompt.md not found (create it first)" >&2; exit 2; }
out_dir="$task_dir/$task-$agent"

if (( rerecord )); then
  rr_preflight_and_capture                       # captures RR_* then wipes the dir
elif git ls-files --error-unmatch "$out_dir/context.md" >/dev/null 2>&1; then
  echo "error: a committed run already exists at $out_dir." >&2
  echo "       to replace it against a newer toolchain (preserving history), re-record:" >&2
  echo "         $0 --rerecord $agent $task_dir" >&2
  exit 2
fi
mkdir -p "$out_dir"
out_dir_abs="$(cd "$out_dir" && pwd)"   # absolute — the agent run cd's here

# --- assemble the prompt: PROMPT_PREFIX.md + the task's prompt.md + PROMPT_SUFFIX.md ---
# Shared preamble/postamble (repo root) wrap each task's specific prompt; both optional.
root="$(cd "$(dirname "$0")/.." && pwd)"
prompt_file="$(mktemp "${TMPDIR:-/tmp}/zoo-prompt.XXXXXX")"
trap 'rm -f "$prompt_file"' EXIT
{
  [[ -f "$root/PROMPT_PREFIX.md" ]] && { cat "$root/PROMPT_PREFIX.md"; printf '\n\n'; }
  cat "$task_dir/prompt.md"
  [[ -f "$root/PROMPT_SUFFIX.md" ]] && { printf '\n\n'; cat "$root/PROMPT_SUFFIX.md"; }
} > "$prompt_file"

# --- promise prerequisite ---
export PATH="$PROMISE_BIN:$PATH"
command -v promise >/dev/null 2>&1 || { echo "error: 'promise' not on PATH (looked in $PROMISE_BIN)" >&2; exit 1; }
promise_ver="$(promise version 2>&1 | head -1)"
echo "promise: $(command -v promise) — $promise_ver"

# --- agent present + version --- (the "gemini" agent runs through Google's Antigravity CLI, `agy`)
case "$agent" in gemini) agent_cmd=agy; agent_cli="Antigravity (agy)" ;; *) agent_cmd="$agent"; agent_cli="" ;; esac
command -v "$agent_cmd" >/dev/null 2>&1 || { echo "error: '$agent_cmd' not found on PATH" >&2; exit 1; }
agent_ver="$("$agent_cmd" --version 2>&1 | head -1)"
[[ -n "$agent_cli" ]] && agent_ver="$agent_cli $agent_ver"   # record the actual CLI in provenance, e.g. "Antigravity (agy) 1.0.8"
echo "agent:   $agent — $agent_ver"
echo "output:  $out_dir/"

# --- assembled prompt on clipboard as a seed fallback ---
if command -v pbcopy >/dev/null 2>&1; then pbcopy < "$prompt_file"; clip="the full prompt is on your clipboard — paste with Cmd+V"; else clip="the full prompt is in $prompt_file"; fi

# --- confirm ---
echo
(( rerecord )) && echo "RE-RECORD — the previous run was captured for history; the agent runs fresh below."
echo "'$agent' will open INTERACTIVELY in $out_dir (auto-approving tool actions)."
echo "Tip: make your terminal wide enough (~110+ cols) first, or the agent's header may wrap."
echo "The prompt should seed automatically; if it doesn't, $clip."
echo "When the agent finishes, exit it (/exit or Ctrl-D) to stop the recording."
read -r -p "Proceed? [y/N] " ans
[[ "$ans" == [yY] ]] || { echo "aborted."; exit 1; }

# --- provenance ---
ctx="$out_dir/context.md"
os="$(uname -srm)"
command -v sw_vers >/dev/null 2>&1 && os="$(sw_vers -productName) $(sw_vers -productVersion) ($(uname -m))"
{
  echo "# Run context"
  echo
  echo "| field | value |"
  echo "|---|---|"
  echo "| Date | $(date '+%Y-%m-%d %H:%M %Z') |"
  echo "| OS / platform | $os |"
  echo "| Promise version | $promise_ver |"
  echo "| Agent | $agent — $agent_ver |"
} > "$ctx"

# --- run, recording if asciinema is available ---
cast="$out_dir/demo.cast"
start=$(date +%s)
inner="bash $(printf %q "$0") __run $(printf %q "$agent") $(printf %q "$prompt_file") $(printf %q "$out_dir_abs")"
if command -v asciinema >/dev/null 2>&1; then
  asciinema rec "$cast" --overwrite -c "$inner"
else
  echo "(asciinema not found — running without a screen recording)"
  bash "$0" __run "$agent" "$prompt_file" "$out_dir_abs"
fi
echo "| Session duration | $(( $(date +%s) - start ))s |" >> "$ctx"
echo "| Recording | _run \`asciinema upload demo.cast\` and paste the asciinema.org URL here_ |" >> "$ctx"

# --- mask secrets in the recording (length- + escape-preserving) ---
# Same length keeps cursor positions valid; the (?:\e\[...)?\K skips a preceding
# ANSI escape so the greedy match can't eat its terminator and corrupt the render.
if [[ -f "$cast" ]]; then
  perl -i -pe 's/(?:\e\[[0-9;?]*[A-Za-z])?\K([A-Za-z0-9._%+-]+)(\@gmail\.com)/("x" x length($1)).$2/ge' "$cast"
  [[ -n "${REDACT:-}" ]] && REDACT="$REDACT" perl -i -pe 's/(?:\e\[[0-9;?]*[A-Za-z])?\K($ENV{REDACT})/"x" x length($1)/ge' "$cast"
  # scrub local paths from the recorded command (header line 1 only — it's metadata,
  # not rendered output, so editing it can't desync the playback) so uploads don't
  # leak $HOME (your username) or the /tmp prompt file path
  HOME_DIR="$HOME" PF="$prompt_file" perl -i -pe 'if ($. == 1) { s/\Q$ENV{PF}\E/<prompt>/g; s/\Q$ENV{HOME_DIR}\E/~/g }' "$cast"
  # mask the username everywhere (length-preserving, so it's safe across the whole
  # cast — unlike the $HOME->~ scrub above): some agents (e.g. antigravity/agy) print
  # full /Users/<you>/... paths in the TUI body, not just the header
  u="$(basename "$HOME")"; [[ ${#u} -ge 3 ]] && USER_NAME="$u" perl -i -pe 's/\Q$ENV{USER_NAME}\E/"x" x length($ENV{USER_NAME})/ge' "$cast"
  echo "masked @gmail.com + username${REDACT:+ + custom patterns} and scrubbed local paths in the recording"
fi

# --- the asciinema PLAYER renders the TUI faithfully; agg's GIF renderer garbles
#     Claude's redraws, so we keep the .cast (no GIF) and point at the player ---
if [[ -f "$cast" ]]; then
  echo "recording: $cast"
  echo "  preview faithfully:  asciinema play $(printf %q "$cast")"
  echo "  share:  asciinema upload <cast>  (asciinema.org), or embed asciinema-player on the site"
fi

# --- drop compiled binaries (extensionless executables; regenerable) ---
for f in "$out_dir"/*; do
  [[ -f "$f" && -x "$f" && "$(basename "$f")" != *.* ]] && rm -f "$f" && echo "removed build artifact: $(basename "$f")"
done

# --- re-record: write the history lineage into context.md + grow the README's
#     "Prior runs" table/aggregate + reset this agent's cast/watch to pending ---
(( rerecord )) && rr_finalize

echo
echo "done — outputs in $out_dir:"
ls -la "$out_dir"
sumry="$out_dir/SUMMARY.md"
if [[ -f "$sumry" ]]; then
  echo
  # glow's pager already showed the summary during the recording (see __run). Here,
  # after asciinema has stopped, just link the full file (cmd/ctrl-click to open it).
  echo "the agent's full TL;DR → $out_dir_abs/SUMMARY.md   (cmd/ctrl-click to open, or: open $(printf %q "$out_dir_abs/SUMMARY.md"))"
fi
if (( rerecord )); then
  echo "→ re-record done. NEXT: bin/upload.sh $agent $task_dir  — stamps the new recording URL"
  echo "  into context.md + the README cast/watch (replacing the 'pending' placeholders)."
  echo "  Then review the '$agent' row Outcome + any findings list in $task_dir/README.md (editorial)."
else
  echo "→ fill the results table in $task_dir/README.md; per-run provenance is in $ctx"
fi
