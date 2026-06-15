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
#   transcript.txt  the agent's stdout
#   demo.cast       asciinema recording      (if asciinema is installed)
#   demo.gif        GIF render of the cast    (if agg is installed)
#   (plus the agent's generated .pr source; the compiled binary is removed)
#
# Privacy: any @gmail.com address in the cast/transcript is auto-redacted to
# <redacted>@gmail.com before the GIF is rendered. To scrub additional secrets,
# set REDACT (a sed-style alternation):
#   REDACT='you@work.com|another-secret' bin/record.sh claude <task-dir>
#
# The `promise` toolchain is required. This script puts ~/.promise/bin on PATH
# *for this run only* (it does not touch your shell config) and verifies
# `promise version` before launching the agent.
#
# NOTE: the agent runs UNATTENDED with tool-approval bypassed (claude:
# --dangerously-skip-permissions, gemini: --yolo) so it can run `promise` and
# write files without prompting. You confirm once before it starts. Edit the
# *_FLAGS below if you want a different permission posture.

set -uo pipefail

CLAUDE_FLAGS="--dangerously-skip-permissions"
GEMINI_FLAGS="--yolo"
PROMISE_BIN="$HOME/.promise/bin"

# --- internal entrypoint: the actual agent run (also invoked inside asciinema) ---
if [[ "${1:-}" == "__run" ]]; then
  agent="$2"; task_dir="$3"
  export PATH="$PROMISE_BIN:$PATH"
  prompt="$(cat "$task_dir/prompt.md")"
  sub="$(basename "$task_dir")-$agent"   # e.g. hello-world-claude → folder name = binary name
  mkdir -p "$task_dir/$sub"
  cd "$task_dir/$sub" || exit 1
  case "$agent" in
    claude) claude $CLAUDE_FLAGS -p "$prompt" 2>&1 | tee transcript.txt ;;
    gemini) gemini $GEMINI_FLAGS -p "$prompt" 2>&1 | tee transcript.txt ;;
  esac
  exit "${PIPESTATUS[0]}"
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

# --- confirm (human-in-the-loop before the unattended run) ---
echo
echo "About to run '$agent' UNATTENDED (tool approvals bypassed) in: $out_dir"
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
echo "| Duration | $(( $(date +%s) - start ))s |" >> "$ctx"

# --- redact secrets from the cast + transcript before rendering ---
# Always: any <local>@gmail.com -> <redacted>@gmail.com. Optional: REDACT='pat1|pat2'.
for f in "$cast" "$out_dir/transcript.txt"; do
  [[ -f "$f" ]] || continue
  LC_ALL=C sed -i.bak -E 's/[A-Za-z0-9._%+-]+@gmail\.com/<redacted>@gmail.com/g' "$f"
  [[ -n "${REDACT:-}" ]] && LC_ALL=C sed -i.bak -E "s/(${REDACT})/[redacted]/g" "$f"
  rm -f "$f.bak"
done
echo "redacted @gmail.com${REDACT:+ + custom patterns} from cast + transcript"

# --- gif ---
if command -v agg >/dev/null 2>&1 && [[ -f "$cast" ]]; then
  agg "$cast" "$out_dir/demo.gif" && echo "wrote $out_dir/demo.gif"
fi

# --- drop the compiled binary (regenerable; keep source + provenance + recording) ---
bin_path="$out_dir/$(basename "$out_dir")"
[[ -f "$bin_path" ]] && rm -f "$bin_path" && echo "removed build artifact: $(basename "$bin_path")"

echo
echo "done — outputs in $out_dir:"
ls -la "$out_dir"
echo "→ summarize the result in $task_dir/README.md (per-agent results table); context: $ctx"
