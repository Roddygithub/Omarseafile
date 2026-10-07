#!/bin/bash
# Launch a cached file with Omarchy's MIME handler, then fall back to xdg-open.

if command -v xdg-mime >/dev/null 2>&1 && command -v uwsm-app >/dev/null 2>&1; then
    mime=$(xdg-mime query filetype "$1") && desktop=$(xdg-mime query default "$mime")
    if [[ -n "$desktop" ]]; then
        setsid uwsm-app -- "$desktop" "$1" &
        launcher=$!
        trap 'kill -- -"$launcher" 2>/dev/null; kill "$launcher" 2>/dev/null; wait "$launcher" 2>/dev/null; exit 143' TERM INT
        wait "$launcher"
        status=$?
        trap - TERM INT
        if [[ "$status" -eq 0 ]]; then exit 0; fi
        kill -- -"$launcher" 2>/dev/null
    fi
fi

exec xdg-open "$1"
