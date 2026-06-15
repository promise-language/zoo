#!/usr/bin/env bash
#
# record.sh — record an AI agent building a Promise program (one zoo run).
#
# Usage:   bin/record.sh <claude|gemini> <task-dir>
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
# auto-accept-edits mode, and .claude/settings.local.json allows all Bash, so there
# is NO startup warning and NO mid-run permission dialog (a dialog overlaps the
# spinner and garbles the recording). Watch it, then /exit to stop. (Bypass mode
# isn't used: its warning shows every run and can't be suppressed.)
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

CLAUDE_FLAGS="--permission-mode acceptEdits"   # no startup warning; .claude/settings.local.json allows all Bash so nothing prompts mid-run
GEMINI_FLAGS="--yolo"
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
    gemini) gemini $GEMINI_FLAGS "$prompt" ;;
  esac
  exit $?
fi

# --- args ---
agent="${1:-}"; task_dir="${2:-}"
[[ -n "$agent" && -n "$task_dir" ]] || { echo "usage: $0 <claude|gemini> <task-dir>" >&2; exit 2; }
[[ "$agent" == "claude" || "$agent" == "gemini" ]] || { echo "error: agent must be 'claude' or 'gemini' (got '$agent')" >&2; exit 2; }
task_dir="${task_dir%/}"
[[ -d "$task_dir" ]] || { echo "error: task dir '$task_dir' not found" >&2; exit 2; }
[[ -f "$task_dir/prompt.md" ]] || { echo "error: $task_dir/prompt.md not found (create it first)" >&2; exit 2; }
out_dir="$task_dir/$(basename "$task_dir")-$agent"
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

# --- agent present + version ---
command -v "$agent" >/dev/null 2>&1 || { echo "error: '$agent' not found on PATH" >&2; exit 1; }
agent_ver="$("$agent" --version 2>&1 | head -1)"
echo "agent:   $agent — $agent_ver"
echo "output:  $out_dir/"

# --- assembled prompt on clipboard as a seed fallback ---
if command -v pbcopy >/dev/null 2>&1; then pbcopy < "$prompt_file"; clip="the full prompt is on your clipboard — paste with Cmd+V"; else clip="the full prompt is in $prompt_file"; fi

# --- confirm ---
echo
echo "'$agent' will open INTERACTIVELY in $out_dir (auto-accept edits; all Bash pre-allowed)."
echo "Tip: make your terminal wide enough (~110+ cols) first, or Claude's header wraps."
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

# --- mask secrets in the recording (length- + escape-preserving) ---
# Same length keeps cursor positions valid; the (?:\e\[...)?\K skips a preceding
# ANSI escape so the greedy match can't eat its terminator and corrupt the render.
if [[ -f "$cast" ]]; then
  perl -i -pe 's/(?:\e\[[0-9;?]*[A-Za-z])?\K([A-Za-z0-9._%+-]+)(\@gmail\.com)/("x" x length($1)).$2/ge' "$cast"
  [[ -n "${REDACT:-}" ]] && REDACT="$REDACT" perl -i -pe 's/(?:\e\[[0-9;?]*[A-Za-z])?\K($ENV{REDACT})/"x" x length($1)/ge' "$cast"
  echo "masked @gmail.com${REDACT:+ + custom patterns} in the recording"
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

echo
echo "done — outputs in $out_dir:"
ls -la "$out_dir"
if [[ -f "$out_dir/SUMMARY.md" ]]; then
  echo; echo "=== SUMMARY.md (the agent's TL;DR — the session closes too fast to read live) ==="
  cat "$out_dir/SUMMARY.md"; echo
fi
echo "→ fill the results table in $task_dir/README.md; per-run provenance is in $ctx"
