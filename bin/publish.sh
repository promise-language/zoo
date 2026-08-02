#!/usr/bin/env bash
#
# publish.sh — privacy-check a zoo recording and publish it to promise-lang.org.
#
# Usage:   bin/publish.sh <claude|gemini> <task-dir>     (same args as record.sh)
#
# Finds <task-dir>/<task>-<agent>/demo.cast, then REFUSES to publish if it still
# contains private info — an un-masked @gmail.com (or any other email), your home
# path or username, or a /tmp prompt path. record.sh masks/scrubs all of these
# automatically, so a clean recording passes; this is the safety net before the
# cast goes public.
#
# On success it:
#   1. renders a still poster (the run's "END OF CAST" card) next to the cast,
#   2. copies the cast into the website repo (public/zoo/<id>.cast) so
#      promise-lang.org hosts and plays it with the self-hosted asciinema player,
#   3. upserts an entry in public/zoo/index.json (the player reads it for titles),
#   4. stamps the promise-lang.org player URL into the run's context.md and the
#      task README (the agent's poster embed + "▶ watch" link).
#
# Nothing is pushed — publishing is a git push of BOTH repos, which it prints for
# you to review and run. We host our own recordings now: no third-party account to
# get reset. (This replaces the old bin/upload.sh, which pushed to asciinema.org.)

set -uo pipefail

# --- where the website repo lives (holds public/zoo + the /cast player) ---
WWW_DIR="${WWW_DIR:-$HOME/prog/www}"
SITE="${SITE:-https://promise-lang.org}"

# --- args (same as record.sh) ---
agent="${1:-}"; task_dir="${2:-}"
[[ -n "$agent" && -n "$task_dir" ]] || { echo "usage: $0 <claude|gemini> <task-dir>" >&2; exit 2; }
[[ "$agent" == "claude" || "$agent" == "gemini" ]] || { echo "error: agent must be 'claude' or 'gemini' (got '$agent')" >&2; exit 2; }
task_dir="${task_dir%/}"
task="$(basename "$task_dir")"
run_subdir="$task-$agent"          # per-run dir name (holds demo.cast, poster.png)
run_dir="$task_dir/$run_subdir"
cast="$run_dir/demo.cast"
# id (the cast's public identity / URL) is derived below, once we know the epoch.
[[ -f "$cast" ]] || { echo "error: cast not found: $cast (record it first with bin/record.sh)" >&2; exit 1; }
[[ -d "$WWW_DIR/public/zoo" ]] || { echo "error: website repo not found at $WWW_DIR (set WWW_DIR=... to override)" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "error: jq not installed (needed to update the recordings manifest)" >&2; exit 1; }

# --- privacy sanity check: refuse to publish anything with PII still in it ---
echo "privacy check: $cast"
problems=()
# 1. un-masked @gmail.com — record.sh masks the local part to all-'x'; flag any that isn't
gleak="$(perl -ne 'while (/([A-Za-z0-9._%+-]+)\@gmail\.com/g){ print "$1\@gmail.com\n" unless $1 =~ /^x+$/ }' "$cast" | sort -u | head -5)"
[[ -n "$gleak" ]] && problems+=("un-masked @gmail.com: $(echo "$gleak" | paste -sd' ' -)")
# 2. any other (non-gmail, non-masked) email address — record.sh only masks @gmail.com
oleak="$(grep -oiE '[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}' "$cast" | grep -vi '@gmail\.com' | grep -viE '^x+@' | sort -u | head -5)"
[[ -n "$oleak" ]] && problems+=("other email(s) — only @gmail.com is auto-masked, add via REDACT: $(echo "$oleak" | paste -sd' ' -)")
# 3. home directory path / username
grep -qF "$HOME" "$cast" && problems+=("home path present ($HOME)")
grep -qwF "$(basename "$HOME")" "$cast" && problems+=("username present ($(basename "$HOME"))")
# 4. temp prompt-file path
grep -qF "/tmp/zoo-prompt" "$cast" && problems+=("/tmp prompt-file path present")

if (( ${#problems[@]} )); then
  echo "ABORTED — the cast still contains private info; NOT publishing:" >&2
  printf '  - %s\n' "${problems[@]}" >&2
  echo "Re-record (record.sh masks @gmail + scrubs paths automatically), or for other" >&2
  echo "secrets re-record with REDACT='pat1|pat2', then retry." >&2
  exit 1
fi
echo "  clean — no @gmail/email/home/username/tmp leaks found"

# --- metadata for the player (from context.md + git remote) ---
ctx="$run_dir/context.md"
case "$agent" in claude) label="Claude Code" ;; gemini) label="Gemini" ;; *) label="$agent" ;; esac
title="$label builds “${task}” in Promise"
date="$(perl -ne 'if(/^\| Date \| (\S+)/){print $1; last}' "$ctx" 2>/dev/null)"
pver="$(perl -ne 'if (/^\| Promise version \| (.+?) \|/){my $v=$1; my ($s)=$v=~/version\s+(\S+)/; print $s//$v; last}' "$ctx" 2>/dev/null)"
repo="$(git -C "$task_dir" remote get-url origin 2>/dev/null)"; repo="${repo%.git}"; repo="${repo/git@github.com:/https://github.com/}"
repo="${repo:-https://github.com/promise-language/zoo}"
prompt_url="$repo/blob/main/$task/prompt.md"
run_url="$repo/tree/main/$task/$run_subdir"

# --- cast identity: carries the Promise epoch --------------------------------
# A task is re-recorded against newer toolchains, so <task>-<agent> alone would
# make each re-record OVERWRITE (and lose) the previous recording's URL. The epoch
# makes every run distinct: <task>-<agent>-<epoch>, e.g. mini-git-claude-2026.4.
# Two runs can still share an epoch — disambiguate the later one with its date.
manifest="$WWW_DIR/public/zoo/index.json"
[[ -f "$manifest" ]] || printf '{\n  "recordings": []\n}\n' > "$manifest"
id="$task-$agent${pver:+-$pver}"
if jq -e --arg id "$id" --arg d "$date" '((.recordings // [])[] | select(.id==$id and .date!=$d))' "$manifest" >/dev/null 2>&1; then
  id="$id${date:+-$date}"   # same epoch, different run — keep both
fi
player_url="$SITE/cast/?c=$id"

# --- confirm (this mutates two repos' working trees; you push them yourself) ---
echo
echo "publish $id"
echo "  cast     -> $WWW_DIR/public/zoo/$id.cast"
echo "  poster   -> $run_dir/poster.png"
echo "  manifest -> $WWW_DIR/public/zoo/index.json  (title: $title)"
echo "  player   -> $player_url"
read -r -p "Proceed? [y/N] " ans
[[ "$ans" == [yY] ]] || { echo "aborted."; exit 1; }

# --- 1. poster (still frame; new casts land on the END OF CAST card) ---
"$(dirname "$0")/poster.sh" "$cast" "$run_dir/poster.png" last || { echo "poster render failed" >&2; exit 1; }
cp "$run_dir/poster.png" "$WWW_DIR/public/zoo/$id.png"   # gallery thumbnail + social-card image

# --- 2. copy the cast into the website repo (promise-lang.org serves it) ---
cp "$cast" "$WWW_DIR/public/zoo/$id.cast"
echo "copied cast + poster -> $WWW_DIR/public/zoo/$id.{cast,png}"

# --- 2b. viewer context snippet (shown under the player) ----------------------
# The same blurb the old bin/upload.sh sent to asciinema.org: what the run is, a
# pointer to the zoo, then the task's own prompt.md (wrapped at run time with the
# shared PROMPT_PREFIX/SUFFIX, which we link rather than repeat). Rendered as
# Markdown beneath the player.
snippet="$WWW_DIR/public/zoo/$id.md"
{
  printf '%s, with no prior knowledge of [Promise](https://promise-lang.org) — a\n' "$label"
  printf 'statically-typed, AOT-compiled language designed so AI agents write correct,\n'
  printf 'maintainable code — learned it from the toolchain (`promise --help`,\n'
  printf '`promise guide`) and built **%s**.\n\n' "$task"
  printf 'From the [Promise Zoo](%s): a gallery of real programs built in Promise by AI\n' "$repo"
  printf 'agents — each with its prompt, the agent and model, the Promise version, and an\n'
  printf 'honest account of how the run went.\n'
  if [[ -f "$task_dir/prompt.md" ]]; then
    printf '\n---\n\n'
    printf '**The task prompt** — the task-specific ask. At run time it is wrapped with the\n'
    printf 'shared [`PROMPT_PREFIX.md`](%s/blob/main/PROMPT_PREFIX.md) (learn Promise first)\n' "$repo"
    printf 'and [`PROMPT_SUFFIX.md`](%s/blob/main/PROMPT_SUFFIX.md) (write a SUMMARY, report\n' "$repo"
    printf 'bugs upstream):\n\n'
    cat "$task_dir/prompt.md"
  fi
} > "$snippet"
echo "wrote viewer context -> $snippet"

# --- 3. upsert the recordings manifest (remove any old entry for this id, append) ---
tmp="$(mktemp)"
jq --arg id "$id" --arg task "$task" --arg agent "$agent" --arg label "$label" \
   --arg title "$title" --arg date "${date:-}" --arg promise "${pver:-}" \
   --arg prompt "$prompt_url" --arg repo "$run_url" --arg posterImage "/zoo/$id.png" '
  .recordings = ((.recordings // []) | map(select(.id != $id)) + [{
    id:$id, task:$task, agent:$agent, agentLabel:$label, title:$title,
    date:$date, promise:$promise, prompt:$prompt, repo:$repo, posterImage:$posterImage
  }])
' "$manifest" > "$tmp" && mv "$tmp" "$manifest"
echo "updated manifest: $manifest"

# --- 4. stamp the player URL into context.md + the README --------------------
# Replaces the 'pending' placeholders left by record.sh / record.sh --rerecord:
#   context.md  -> the "| Recording |" row value
#   README      -> this agent's poster embed (between its cast markers, honoring an
#                  optional `width=` on the marker) + this agent's "▶ watch" link.
readme="$task_dir/README.md"
if [[ -f "$ctx" ]]; then
  URL="$player_url" perl -i -pe 's{^(\| Recording \|).*$}{"$1 $ENV{URL} |"}e' "$ctx"
  echo "stamped Recording URL into $ctx"
fi
if [[ -f "$readme" ]]; then
  AGENT="$agent" AGENT_LABEL="$label" TASK="$task" RUNDIR="$run_subdir" URL="$player_url" perl -0777 -i -pe '
    my $A=$ENV{AGENT}; my $L=$ENV{AGENT_LABEL}; my $TASK=$ENV{TASK}; my $RD=$ENV{RUNDIR}; my $U=$ENV{URL};
    # cast marker -> <a><img> poster embed (style-aware: multi-line block vs inline table cell).
    # The poster is committed next to the run (run subdir), referenced relative to the README.
    s{(<!-- cast:\Q$A\E\b([^>]*)-->)(.*?)(<!-- /cast:\Q$A\E -->)}{
      my ($o,$attrs,$inner,$c)=($1,$2,$3,$4);
      my $w=($attrs=~/width=(\S+)/)?" width=\"$1\"":"";
      my $img=qq{<a href="$U"><img src="$RD/poster.png"$w alt="asciicast — $TASK, $L"></a>};
      ($inner=~/\n/) ? "$o\n$img\n$c" : "$o$img$c";
    }se;
    # this agent results-row watch link -> the player URL (row links to TASK-AGENT/)
    s{^(\|.*\]\(\Q$TASK\E-\Q$A\E/\).*)$}{ my $r=$1; $r =~ s/(\[▶ watch\]\()[^)]*\)/${1}$U)/; $r }mge;
  ' "$readme"
  echo "stamped poster embed + watch link for '$agent' into $readme"
fi

# --- next steps: two repos to commit + push (this is the actual publish) ------
zoo_root="$(git -C "$task_dir" rev-parse --show-toplevel 2>/dev/null || echo "$task_dir")"
cat <<EOF

→ $player_url is wired up. Nothing is pushed yet — review, then publish both repos:

  # 1) website (hosts the cast + player):
  cd $WWW_DIR
  git add public/zoo/ public/cast/
  git commit -m "zoo: publish $id recording"
  git push

  # 2) zoo (poster + stamped README/context):
  cd $zoo_root
  git add $task/
  git commit -m "$task: point $agent recording at promise-lang.org"
  git push

If this was a re-record, also review the '$agent' Outcome cell (and any findings
list) in $readme — that prose is editorial.
EOF
