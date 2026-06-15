#!/usr/bin/env bash
#
# record.sh — record an AI agent building a Promise program (one zoo run).
#
# Usage:   bin/record.sh <claude|gemini> <task-dir>
#
# <task-dir> must contain prompt.md (the prompt sent to the agent). The agent runs
# in a per-agent subdir named <task>-<agent> (e.g. hello-world/hello-world-claude/)
# so several agents can do the same task side by side, none can clobber the task's
# own README.md, and Promise's folder-derived binary name is descriptive
# (./hello-world-claude, not ./claude). Outputs go into that subdir:
#   context.md      provenance — date, OS, promise + agent versions, duration
#   demo.cast       asciinema recording      (if asciinema is installed)
#   demo.gif        GIF render of the cast    (if agg is installed)
#   (plus the agent's generated .pr source; the compiled binary is removed)
#
# The agent runs INTERACTIVELY (its TUI), so the session actually renders in the
# recording — headless `-p` just shows a blank screen. It's still autonomous
# (tool approvals bypassed) so there are no approval interruptions; you just watch
# and, when it's done, exit the agent to stop the recording. The terminal is sized
# to REC_COLS x REC_ROWS (default 100x30) for a legible GIF, then restored.
#
# Privacy: any @gmail.com address in the recording is auto-redacted to
# <redacted>@gmail.com before the GIF is rendered. To scrub additional secrets,
# set REDACT (a sed-style alternation):
#   REDACT='you@work.com|another-secret' bin/record.sh claude <task-dir>
#
# The `promise` toolchain is required. This script puts ~/.promise/bin on PATH
# *for this run only* (it does not touch your shell config) and verifies
# `promise version` before launching the agent.

set -uo pipefail

CLAUDE_FLAGS="--dangerously-skip-permissions"
GEMINI_FLAGS="--yolo"
PROMISE_BIN="$HOME/.promise/bin"
REC_COLS=100   # recording window size for a legible GIF (best-effort — tmux / some
REC_ROWS=30    # terminals ignore the resize escape; your original size is restored after)

# --- internal entrypoint: the actual agent run (also invoked inside asciinema) ---
# NOTE: launched interactively (no -p) and NOT piped (no `| tee`) — both would stop
# the TUI from rendering. The prompt is passed as the seed message.
if [[ "${1:-}" == "__run" ]]; then
  agent="$2"; task_dir="$3"
  export PATH="$PROMISE_BIN:$PATH"
  prompt="$(cat "$task_dir/prompt.md")"
  sub="$(basename "$task_dir")-$agent"   # e.g. hello-world-claude → folder name = binary name
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
out_dir="$task_dir/$(basename "$task_dir")-$agent"   # e.g. hello-world/hello-world-claude
mkdir -p "$out_dir"

# --- promise prerequisite (on PATH + verified) ---
export PATH="$PROMISE_BIN:$PATH"
command -v promise >/dev/null 2>&1 || { echo "error: 'promise' not on PATH (looked in $PROMISE_BIN)" >&2; exit 1; }
promise_ver="$(promise version 2>&1 | head -1)"
echo "promise: $(command -v promise) — $promise_ver"

# --- agent present + version ---
command -v "$agent" >/dev/null 2>&1 || { echo "error: '$agent' not found on PATH" >&2; exit 1; }
agent_ver="$("$agent" --version 2>&1 | head -1)"
echo "agent:   $agent — $agent_ver"
echo "output:  $out_dir/"

# --- put the prompt on the clipboard as a fallback if it isn't auto-seeded ---
if command -v pbcopy >/dev/null 2>&1; then pbcopy < "$task_dir/prompt.md"; clip="it's on your clipboard — paste with Cmd+V"; else clip="it's in $task_dir/prompt.md"; fi

# --- confirm (you drive the interactive session) ---
echo
echo "'$agent' will open INTERACTIVELY in $out_dir (tool approvals bypassed)."
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

# --- size the window for a legible recording (best-effort), remembering the original ---
orig_size="$(stty size 2>/dev/null || true)"   # "rows cols"
printf '\e[8;%d;%dt' "$REC_ROWS" "$REC_COLS"; sleep 0.3

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

# --- restore the original window size ---
[[ -n "${orig_size:-}" ]] && printf '\e[8;%s;%st' "${orig_size%% *}" "${orig_size##* }"

# --- redact secrets from the recording before rendering ---
# Always: any <local>@gmail.com -> <redacted>@gmail.com. Optional: REDACT='pat1|pat2'.
if [[ -f "$cast" ]]; then
  LC_ALL=C sed -i.bak -E 's/[A-Za-z0-9._%+-]+@gmail\.com/<redacted>@gmail.com/g' "$cast"
  [[ -n "${REDACT:-}" ]] && LC_ALL=C sed -i.bak -E "s/(${REDACT})/[redacted]/g" "$cast"
  rm -f "$cast.bak"
  echo "redacted @gmail.com${REDACT:+ + custom patterns} from the recording"
fi

# --- gif ---
if command -v agg >/dev/null 2>&1 && [[ -f "$cast" ]]; then
  agg "$cast" "$out_dir/demo.gif" && echo "wrote $out_dir/demo.gif"
fi

# --- drop compiled binaries (extensionless executables; regenerable) — keep .pr/.md/.cast/.gif/.txt ---
for f in "$out_dir"/*; do
  [[ -f "$f" && -x "$f" && "$(basename "$f")" != *.* ]] && rm -f "$f" && echo "removed build artifact: $(basename "$f")"
done

echo
echo "done — outputs in $out_dir:"
ls -la "$out_dir"
echo "→ fill the results table in $task_dir/README.md; per-run provenance is in $ctx"
