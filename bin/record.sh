#!/usr/bin/env bash
#
# record.sh — record an AI agent building a Promise program (one zoo run).
#
# Usage:   bin/record.sh <claude|gemini> <task-dir>
#
# <task-dir> must contain prompt.md. The agent runs in a per-agent subdir named
# <task>-<agent> (e.g. hello-world/hello-world-claude/) so several agents can do
# the same task side by side, none can clobber the task README, and Promise's
# folder-derived binary name is descriptive. Outputs go into that subdir:
#   context.md   provenance (date, OS, promise + agent versions, duration)
#   demo.cast    asciinema recording   (if asciinema is installed)
#   demo.gif     GIF render            (if agg is installed)
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
# Privacy: any @gmail.com address is masked in the recording before the GIF — the
# local part becomes same-length 'x's, keeping @gmail.com (same length + escape-
# preserving so the cast's cursor positions stay valid). Add more via REDACT.
#   REDACT='you@work.com|secret' bin/record.sh claude <task-dir>
#
# The `promise` toolchain is required; ~/.promise/bin is put on PATH for this run.

set -uo pipefail

CLAUDE_FLAGS="--permission-mode acceptEdits"   # no startup warning; .claude/settings.local.json allows all Bash so nothing prompts mid-run
GEMINI_FLAGS="--yolo"
PROMISE_BIN="$HOME/.promise/bin"

# --- internal entrypoint: the actual agent run (also invoked inside asciinema) ---
# Interactive (no -p) and unpiped (no `| tee`) — both would stop the TUI rendering.
if [[ "${1:-}" == "__run" ]]; then
  agent="$2"; task_dir="$3"
  export PATH="$PROMISE_BIN:$PATH"
  prompt="$(cat "$task_dir/prompt.md")"
  sub="$(basename "$task_dir")-$agent"   # e.g. hello-world-claude
  mkdir -p "$task_dir/$sub"
  cd "$task_dir/$sub" || exit 1
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

# --- prompt on clipboard as a seed fallback ---
if command -v pbcopy >/dev/null 2>&1; then pbcopy < "$task_dir/prompt.md"; clip="it's on your clipboard — paste with Cmd+V"; else clip="it's in $task_dir/prompt.md"; fi

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
inner="bash $(printf %q "$0") __run $(printf %q "$agent") $(printf %q "$task_dir")"
if command -v asciinema >/dev/null 2>&1; then
  asciinema rec "$cast" --overwrite -c "$inner"
else
  echo "(asciinema not found — running without a screen recording)"
  bash "$0" __run "$agent" "$task_dir"
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

# --- gif ---
if command -v agg >/dev/null 2>&1 && [[ -f "$cast" ]]; then
  agg "$cast" "$out_dir/demo.gif" && echo "wrote $out_dir/demo.gif"
fi

# --- drop compiled binaries (extensionless executables; regenerable) ---
for f in "$out_dir"/*; do
  [[ -f "$f" && -x "$f" && "$(basename "$f")" != *.* ]] && rm -f "$f" && echo "removed build artifact: $(basename "$f")"
done

echo
echo "done — outputs in $out_dir:"
ls -la "$out_dir"
echo "→ fill the results table in $task_dir/README.md; per-run provenance is in $ctx"
