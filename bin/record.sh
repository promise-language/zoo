#!/usr/bin/env bash
#
# record.sh — record an AI agent building a Promise program (one zoo run).
#
# Usage:   bin/record.sh <claude|gemini> <run-dir>
#
# <run-dir> must contain prompt.md (the prompt sent to the agent). Outputs are
# written into <run-dir>:
#   context.md      provenance — date, OS, promise + agent versions, duration
#   transcript.txt  the agent's stdout
#   demo.cast       asciinema recording     (if asciinema is installed)
#   demo.gif        GIF render of the cast   (if agg is installed)
#
# Privacy: any @gmail.com address in the cast/transcript is auto-redacted to
# <redacted>@gmail.com before the GIF is rendered. To scrub additional secrets,
# set REDACT (a sed-style alternation):
#   REDACT='you@work.com|another-secret' bin/record.sh claude <run-dir>
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
  agent="$2"; dir="$3"
  export PATH="$PROMISE_BIN:$PATH"
  cd "$dir" || exit 1
  prompt="$(cat prompt.md)"
  case "$agent" in
    claude) claude $CLAUDE_FLAGS -p "$prompt" 2>&1 | tee transcript.txt ;;
    gemini) gemini $GEMINI_FLAGS -p "$prompt" 2>&1 | tee transcript.txt ;;
  esac
  exit "${PIPESTATUS[0]}"
fi

# --- args ---
agent="${1:-}"; run_dir="${2:-}"
[[ -n "$agent" && -n "$run_dir" ]] || { echo "usage: $0 <claude|gemini> <run-dir>" >&2; exit 2; }
[[ "$agent" == "claude" || "$agent" == "gemini" ]] || { echo "error: agent must be 'claude' or 'gemini' (got '$agent')" >&2; exit 2; }
run_dir="${run_dir%/}"
[[ -d "$run_dir" ]] || { echo "error: run dir '$run_dir' not found" >&2; exit 2; }
[[ -f "$run_dir/prompt.md" ]] || { echo "error: $run_dir/prompt.md not found (create it first)" >&2; exit 2; }

# --- promise prerequisite (on PATH + verified) ---
export PATH="$PROMISE_BIN:$PATH"
command -v promise >/dev/null 2>&1 || { echo "error: 'promise' not on PATH (looked in $PROMISE_BIN)" >&2; exit 1; }
promise_ver="$(promise version 2>&1 | head -1)"
echo "promise: $(command -v promise) — $promise_ver"

# --- agent present + version ---
command -v "$agent" >/dev/null 2>&1 || { echo "error: '$agent' not found on PATH" >&2; exit 1; }
agent_ver="$("$agent" --version 2>&1 | head -1)"
echo "agent:   $agent — $agent_ver"

# --- confirm (human-in-the-loop before the unattended run) ---
echo
echo "About to run '$agent' UNATTENDED (tool approvals bypassed) in: $run_dir"
read -r -p "Proceed? [y/N] " ans
[[ "$ans" == [yY] ]] || { echo "aborted."; exit 1; }

# --- provenance ---
ctx="$run_dir/context.md"
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
cast="$run_dir/demo.cast"
start=$(date +%s)
inner="bash $(printf %q "$0") __run $(printf %q "$agent") $(printf %q "$run_dir")"
if command -v asciinema >/dev/null 2>&1; then
  asciinema rec "$cast" --overwrite -c "$inner"
else
  echo "(asciinema not found — running without a screen recording)"
  bash "$0" __run "$agent" "$run_dir"
fi
echo "| Duration | $(( $(date +%s) - start ))s |" >> "$ctx"

# --- redact secrets from the cast + transcript before rendering ---
# Always: any <local>@gmail.com -> <redacted>@gmail.com (catches a personal login;
#         leaves @promise-lang.org and other intended addresses alone).
# Optional: set REDACT='pat1|pat2' to scrub anything else too.
for f in "$cast" "$run_dir/transcript.txt"; do
  [[ -f "$f" ]] || continue
  LC_ALL=C sed -i.bak -E 's/[A-Za-z0-9._%+-]+@gmail\.com/<redacted>@gmail.com/g' "$f"
  [[ -n "${REDACT:-}" ]] && LC_ALL=C sed -i.bak -E "s/(${REDACT})/[redacted]/g" "$f"
  rm -f "$f.bak"
done
echo "redacted @gmail.com${REDACT:+ + custom patterns} from cast + transcript"

# --- gif ---
if command -v agg >/dev/null 2>&1 && [[ -f "$cast" ]]; then
  agg "$cast" "$run_dir/demo.gif" && echo "wrote $run_dir/demo.gif"
fi

echo
echo "done — outputs in $run_dir:"
ls -la "$run_dir"
echo "→ paste $ctx into the run's README.md; transcript is $run_dir/transcript.txt"
