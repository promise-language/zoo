#!/usr/bin/env bash
#
# upload.sh — privacy-check a zoo recording and upload it to asciinema.org.
#
# Usage:   bin/upload.sh <claude|gemini> <task-dir>     (same args as record.sh)
#
# Finds <task-dir>/<task>-<agent>/demo.cast, then REFUSES to upload if it still
# contains private info — an un-masked @gmail.com (or any other email), your home
# path or username, or a /tmp prompt path. record.sh masks/scrubs all of these
# automatically, so a clean recording passes; this is the safety net before the
# cast goes public. On success it uploads with a title + description and prints
# the recording URL (paste it into the run's context.md "Recording" row).

set -uo pipefail

VISIBILITY=unlisted   # public | unlisted | private — unlisted pre-launch; flip all to public at T0 (launch)

# --- args (same as record.sh) ---
agent="${1:-}"; task_dir="${2:-}"
[[ -n "$agent" && -n "$task_dir" ]] || { echo "usage: $0 <claude|gemini> <task-dir>" >&2; exit 2; }
[[ "$agent" == "claude" || "$agent" == "gemini" ]] || { echo "error: agent must be 'claude' or 'gemini' (got '$agent')" >&2; exit 2; }
task_dir="${task_dir%/}"
task="$(basename "$task_dir")"
cast="$task_dir/$task-$agent/demo.cast"
[[ -f "$cast" ]] || { echo "error: cast not found: $cast (record it first with bin/record.sh)" >&2; exit 1; }
command -v asciinema >/dev/null 2>&1 || { echo "error: asciinema not installed" >&2; exit 1; }

# --- privacy sanity check: refuse to upload anything with PII still in it ---
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
  echo "ABORTED — the cast still contains private info; NOT uploading:" >&2
  printf '  - %s\n' "${problems[@]}" >&2
  echo "Re-record (record.sh masks @gmail + scrubs paths automatically), or for other" >&2
  echo "secrets re-record with REDACT='pat1|pat2', then retry." >&2
  exit 1
fi
echo "  clean — no @gmail/email/home/username/tmp leaks found"

# --- title + description for the recording page ---
case "$agent" in claude) label="Claude Code" ;; gemini) label="Gemini" ;; *) label="$agent" ;; esac
title="$label builds '$task' in Promise"
desc="$label, with no prior knowledge of [Promise](https://promise-lang.org) — a
statically-typed, AOT-compiled language designed so AI agents write correct,
maintainable code — learned it from the toolchain (\`promise --help\`,
\`promise guide\`) and built **$task**.

From the [Promise Zoo](https://github.com/promise-language/zoo): a gallery of real
programs built in Promise by AI agents — each with its prompt, the agent and
model, the Promise version, and an honest account of how the run went."

# --- confirm + upload (publishing externally — review first) ---
echo
echo "upload $cast to asciinema.org"
echo "  title:      $title"
echo "  visibility: $VISIBILITY"
echo "  description:"; printf '%s\n' "$desc" | sed 's/^/    /'
read -r -p "Proceed? [y/N] " ans
[[ "$ans" == [yY] ]] || { echo "aborted."; exit 1; }

# capture the upload output so we can auto-stamp the URL (still shown to the user)
out="$(asciinema upload "$cast" --title "$title" --description "$desc" --visibility "$VISIBILITY" 2>&1)"; rc=$?
printf '%s\n' "$out"
[[ $rc -eq 0 ]] || { echo "upload failed (rc=$rc) — nothing stamped." >&2; exit $rc; }
url="$(printf '%s\n' "$out" | grep -oE 'https://asciinema\.org/a/[A-Za-z0-9]+' | head -1)"
[[ -n "$url" ]] || { echo "uploaded, but couldn't parse the asciinema URL — stamp it by hand." >&2; exit 0; }

# --- auto-stamp the URL into context.md + the README (no manual paste) -----------
# Replaces the 'pending' placeholders left by record.sh / record.sh --rerecord:
#   context.md  -> the "| Recording |" row value
#   README      -> this agent's cast embed (between its cast markers, honoring an
#                  optional `width=` on the marker) + this agent's "▶ watch" link.
ctx="$task_dir/$task-$agent/context.md"
readme="$task_dir/README.md"
if [[ -f "$ctx" ]]; then
  URL="$url" perl -i -pe 's{^(\| Recording \|).*$}{"$1 $ENV{URL} |"}e' "$ctx"
  echo "stamped Recording URL into $ctx"
fi
if [[ -f "$readme" ]]; then
  AGENT="$agent" AGENT_LABEL="$label" TASK="$task" URL="$url" perl -0777 -i -pe '
    my $A=$ENV{AGENT}; my $L=$ENV{AGENT_LABEL}; my $TASK=$ENV{TASK}; my $U=$ENV{URL};
    # cast marker -> <a><img> embed (style-aware: multi-line block vs inline table cell)
    s{(<!-- cast:\Q$A\E\b([^>]*)-->)(.*?)(<!-- /cast:\Q$A\E -->)}{
      my ($o,$attrs,$inner,$c)=($1,$2,$3,$4);
      my $w=($attrs=~/width=(\S+)/)?" width=\"$1\"":"";
      my $img=qq{<a href="$U"><img src="$U.svg"$w alt="asciicast — $TASK, $L"></a>};
      ($inner=~/\n/) ? "$o\n$img\n$c" : "$o$img$c";
    }se;
    # this agent results-row watch link -> the URL (row links to TASK-AGENT/)
    s{^(\|.*\]\(\Q$TASK\E-\Q$A\E/\).*)$}{ my $r=$1; $r =~ s/(\[▶ watch\]\()[^)]*\)/${1}$U)/; $r }mge;
  ' "$readme"
  echo "stamped cast embed + watch link for '$agent' into $readme"
fi
echo
echo "→ $url is embedded. If this was a re-record, review the '$agent' Outcome cell"
echo "  (and any findings list) in $readme — that prose is editorial."
