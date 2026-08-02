#!/usr/bin/env bash
#
# poster.sh — render a still poster (a single frame) from an asciinema cast.
#
# Usage:  bin/poster.sh <cast> <out.png> [at]
#           <at>  a time (seconds or ffmpeg HH:MM:SS) to grab, or "last" (default)
#                 for the final frame — the run's deliberate "END OF CAST" card.
#
# Why a still: agg's GIF animation garbles the agents' mid-run TUI redraws (see
# bin/record.sh), so we don't publish GIFs. But a single, fully-painted frame — the
# end card, or an explicit timestamp — rasterizes cleanly, which is all a poster is.
# The cast is rendered to a short-lived GIF with agg, then one frame is pulled out
# with ffmpeg. --fps-cap keeps long sessions cheap; --last-frame-duration holds the
# end card so "last" reliably lands on it.

set -euo pipefail

cast="${1:?usage: poster.sh <cast> <out.png> [at]}"
out="${2:?usage: poster.sh <cast> <out.png> [at]}"
at="${3:-last}"

command -v agg    >/dev/null 2>&1 || { echo "poster: agg not installed (cargo install agg / brew install agg)"   >&2; exit 1; }
command -v ffmpeg >/dev/null 2>&1 || { echo "poster: ffmpeg not installed" >&2; exit 1; }
[[ -f "$cast" ]] || { echo "poster: cast not found: $cast" >&2; exit 1; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
gif="$tmp/poster.gif"

# Render to a GIF (theme/cols/rows come from the cast header). Cap fps so a long
# session doesn't explode into tens of thousands of frames; hold the last frame.
agg --fps-cap 2 --last-frame-duration 2 "$cast" "$gif" >/dev/null 2>&1

if [[ "$at" == "last" ]]; then
  # ffmpeg can't -sseof-seek a GIF, so reverse the stream and take the first frame
  # (= the last frame, i.e. the held end card). GIF frames are palettized, so this
  # stays cheap even for a long session.
  ffmpeg -y -loglevel error -i "$gif" -vf reverse -frames:v 1 "$out"
else
  ffmpeg -y -loglevel error -ss "$at" -i "$gif" -frames:v 1 "$out"
fi

[[ -s "$out" ]] || { echo "poster: failed to produce $out" >&2; exit 1; }
echo "poster: $out ($(wc -c < "$out") bytes)"
